//! Native terminal client over an existing session-fenced daemon connection.
//! The connection must outlive its terminals. Callbacks borrow each raw output
//! slice and may close the terminal; destroy it from outside its reader callback.
const std = @import("std");
const native = @import("connection.zig");
const wire = @import("frame.zig");
const Transport = @import("remote_env.zig").Transport;
const Io = std.Io;
pub const Options = struct {
    cwd: []const u8,
    argv: ?[]const []const u8 = null,
    env: ?std.json.Value = null,
    inheritEnv: ?bool = null,
    cols: u32,
    rows: u32,
    onData: *const fn (?*anyopaque, []const u8) void,
    context: ?*anyopaque = null,
};
pub const Failure = struct {
    fields: std.json.Parsed(std.json.Value),
    fn init(gpa: std.mem.Allocator, value: std.json.Value) !Failure {
        const bytes = try std.json.Stringify.valueAlloc(gpa, value, .{});
        defer gpa.free(bytes);
        return .{ .fields = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{ .allocate = .alloc_always }) };
    }
    pub fn code(self: Failure) []const u8 {
        const value = self.fields.value.object.get("code") orelse return "unknown";
        return if (value == .string) value.string else "unknown";
    }
    pub fn message(self: Failure) []const u8 {
        const value = self.fields.value.object.get("message") orelse return "Remote operation failed";
        return if (value == .string) value.string else "Remote operation failed";
    }
    pub fn deinit(self: *Failure) void {
        self.fields.deinit();
        self.* = undefined;
    }
};
pub const OpenResult = union(enum) { terminal: *Terminal, failure: Failure };
pub const ExitResult = union(enum) { exit_code: i64, failure: Failure };
pub const Foreground = struct {
    pid: u32,
    name: ?[]u8,
    pub fn deinit(self: *Foreground, gpa: std.mem.Allocator) void {
        if (self.name) |name| gpa.free(name);
        self.* = undefined;
    }
};
pub const ForegroundResult = union(enum) { job: ?Foreground, failure: Failure };
pub const Terminal = struct {
    gpa: std.mem.Allocator,
    io: Io,
    pid: u32,
    ticket: native.Ticket,
    on_data: *const fn (?*anyopaque, []const u8) void,
    context: ?*anyopaque,
    mutex: Io.Mutex = .init,
    finished: Io.Event = .unset,
    reply: ?wire.Frame = null,
    transport_failure: ?anyerror = null,
    detaching: std.atomic.Value(bool) = .init(false),
    worker_id: std.atomic.Value(std.Thread.Id) = .init(0),
    thread: ?std.Thread = null,

    pub fn open(gpa: std.mem.Allocator, io: Io, connection: Transport, options: Options) !OpenResult {
        var ticket = try connection.begin(.{ .op = "pty", .cwd = options.cwd, .argv = options.argv, .env = options.env, .inheritEnv = options.inheritEnv, .cols = options.cols, .rows = options.rows }, "", null);
        var transferred = false;
        defer if (!transferred) ticket.deinit();
        errdefer ticket.cancel(false) catch {};
        while (true) {
            var first = try ticket.next(60_000);
            defer first.deinit();
            if (first.kind == .remote_error) return .{ .failure = try Failure.init(gpa, first.json.value) };
            if (first.kind != .event) return error.TerminalEndedBeforeStarted;
            const kind = try text(first.json.value, "kind");
            if (std.mem.eql(u8, kind, "output")) {
                options.onData(options.context, first.payload);
                continue;
            }
            if (!std.mem.eql(u8, kind, "started")) continue;
            const pid = try number(first.json.value, "pid");
            const self = try gpa.create(Terminal);
            errdefer gpa.destroy(self);
            self.* = .{ .gpa = gpa, .io = io, .pid = pid, .ticket = ticket, .on_data = options.onData, .context = options.context };
            self.thread = try std.Thread.spawn(.{}, receive, .{self});
            transferred = true;
            return .{ .terminal = self };
        }
    }
    /// Writes are sent synchronously in call order and split at the original
    /// client's one-MiB boundary. Their replies are deliberately unobserved.
    pub fn write(self: *Terminal, bytes: []const u8) void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const end = offset + @min(bytes.len - offset, 1024 * 1024);
            var request = self.ticket.connection.begin(.{ .op = "ptyWrite", .target = self.ticket.id }, bytes[offset..end], self.ticket.session) catch return;
            request.deinit();
            offset = end;
        }
    }
    pub fn resize(self: *Terminal, cols: u32, rows: u32) void {
        var request = self.ticket.connection.begin(.{ .op = "ptyResize", .target = self.ticket.id, .cols = cols, .rows = rows }, "", self.ticket.session) catch return;
        request.deinit();
    }
    pub fn close(self: *Terminal) void {
        self.ticket.cancel(false) catch {};
    }
    /// Owns copied failure fields or a copied optional process name.
    pub fn foreground(self: *Terminal, gpa: std.mem.Allocator) !ForegroundResult {
        var request = try self.ticket.connection.begin(.{ .op = "ptyForeground", .target = self.ticket.id }, "", self.ticket.session);
        defer request.deinit();
        var reply = try request.next(60_000);
        defer reply.deinit();
        if (reply.kind == .remote_error) return .{ .failure = try Failure.init(gpa, reply.json.value) };
        if (reply.kind != .result) return error.InvalidTerminalForegroundReply;
        const value = reply.json.value.object.get("foreground") orelse return .{ .job = null };
        if (value == .null) return .{ .job = null };
        if (value != .object) return error.InvalidTerminalForegroundReply;
        const pid = try number(value, "pid");
        const raw_name = value.object.get("name");
        const name = if (raw_name != null and raw_name.? == .string and raw_name.?.string.len != 0) try gpa.dupe(u8, raw_name.?.string) else null;
        return .{ .job = .{ .pid = pid, .name = name } };
    }
    pub fn wait(self: *Terminal, gpa: std.mem.Allocator) !ExitResult {
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return error.TerminalWaitInsideOutputCallback;
        try self.finished.wait(self.io);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.transport_failure) |err| return err;
        const reply = self.reply orelse return error.MissingTerminalOutcome;
        if (reply.kind == .remote_error) return .{ .failure = try Failure.init(gpa, reply.json.value) };
        const code = reply.json.value.object.get("exitCode") orelse return error.InvalidTerminalExit;
        if (code != .integer) return error.InvalidTerminalExit;
        return .{ .exit_code = code.integer };
    }
    pub fn deinit(self: *Terminal) void {
        std.debug.assert(self.worker_id.load(.acquire) != std.Thread.getCurrentId());
        self.close();
        self.detaching.store(true, .release);
        if (self.thread) |thread| thread.join();
        self.ticket.deinit();
        if (self.reply) |*reply| reply.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    fn receive(self: *Terminal) void {
        self.worker_id.store(std.Thread.getCurrentId(), .release);
        defer self.worker_id.store(0, .release);
        defer self.finished.set(self.io);
        while (!self.detaching.load(.acquire)) {
            var reply = self.ticket.next(100) catch |err| switch (err) {
                error.Timeout => continue,
                else => {
                    self.transport_failure = err;
                    return;
                },
            };
            var retained = false;
            defer if (!retained) reply.deinit();
            if (reply.kind == .event) {
                const kind = text(reply.json.value, "kind") catch |err| {
                    self.transport_failure = err;
                    return;
                };
                if (std.mem.eql(u8, kind, "output")) self.on_data(self.context, reply.payload);
                continue;
            }
            self.mutex.lockUncancelable(self.io);
            self.reply = reply;
            retained = true;
            self.mutex.unlock(self.io);
            return;
        }
        self.transport_failure = error.TerminalDisposed;
    }
};
fn text(value: std.json.Value, key: []const u8) ![]const u8 {
    if (value != .object) return error.InvalidTerminalReply;
    const field = value.object.get(key) orelse return error.InvalidTerminalReply;
    return if (field == .string) field.string else error.InvalidTerminalReply;
}
fn number(value: std.json.Value, key: []const u8) !u32 {
    if (value != .object) return error.InvalidTerminalReply;
    const field = value.object.get(key) orelse return error.InvalidTerminalReply;
    if (field != .integer or field.integer < 1 or field.integer > std.math.maxInt(u32)) return error.InvalidTerminalReply;
    return @intCast(field.integer);
}
