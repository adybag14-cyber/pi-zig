//! MCP newline transport with a retained exact child/group and joined reader teardown.
const std = @import("std");
const builtin = @import("builtin");
const protocol = @import("protocol.zig");
const transport_mod = @import("transport.zig");
const framing = @import("framing.zig");
const ownership = @import("../durable/process_ownership.zig");
const startup = @import("../durable/startup.zig");
pub const Options = struct {
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
    environ: ?*const std.process.Environ.Map = null,
    close_timeout_ms: u32 = 2000,
    max_message_bytes: usize = 16 * 1024 * 1024,
    max_stderr_bytes: usize = 64 * 1024,
};
pub const Stdio = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    options: Options,
    environment: std.process.Environ.Map,
    lifecycle: std.Io.Mutex = .init,
    writing: std.Io.Mutex = .init,
    child: ?std.process.Child = null,
    control: ?ownership.Control = null,
    reader: ?std.Io.Future(anyerror!void) = null,
    stderr_reader: ?std.Io.Future(anyerror!void) = null,
    receiver: ?transport_mod.Receiver = null,
    started: bool = false,
    closing: std.atomic.Value(bool) = .init(false),
    close_emitted: std.atomic.Value(bool) = .init(false),
    callback_thread: std.atomic.Value(std.Thread.Id) = .init(0),
    stderr_mutex: std.Io.Mutex = .init,
    stderr_tail: std.ArrayList(u8) = .empty,
    pub fn create(gpa: std.mem.Allocator, io: std.Io, options: Options) !*Stdio {
        if (options.argv.len == 0 or options.argv[0].len == 0) return error.EmptyMcpCommand;
        const self = try gpa.create(Stdio);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .arena = .init(gpa), .options = options, .environment = if (options.environ) |map| try map.clone(gpa) else .init(gpa) };
        errdefer self.environment.deinit();
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        const argv = try a.alloc([]const u8, options.argv.len);
        for (argv, options.argv) |*to, source| to.* = try a.dupe(u8, source);
        self.options.argv = argv;
        if (options.cwd) |cwd| self.options.cwd = try a.dupe(u8, cwd);
        try self.stderr_tail.ensureTotalCapacity(gpa, options.max_stderr_bytes);
        return self;
    }
    pub fn deinit(self: *Stdio) void {
        self.close() catch {};
        self.stderr_tail.deinit(self.gpa);
        self.environment.deinit();
        self.arena.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    pub fn transport(self: *Stdio) transport_mod.Transport {
        return .{ .context = self, .vtable = &vtable };
    }
    const vtable: transport_mod.Transport.VTable = .{ .start = startRaw, .send = sendRaw, .close = closeRaw };
    fn from(raw: *anyopaque) *Stdio {
        return @ptrCast(@alignCast(raw));
    }
    fn startRaw(raw: *anyopaque, receiver: transport_mod.Receiver) !void {
        try from(raw).start(receiver);
    }
    fn sendRaw(raw: *anyopaque, value: protocol.Value, flag: ?*bool) !void {
        try from(raw).send(value, flag);
    }
    fn closeRaw(raw: *anyopaque) !void {
        try from(raw).close();
    }
    fn start(self: *Stdio, receiver: transport_mod.Receiver) !void {
        try self.lifecycle.lock(self.io);
        defer self.lifecycle.unlock(self.io);
        if (self.started) return error.McpTransportAlreadyStarted;
        if (self.closing.load(.acquire)) return error.McpConnectionClosed;
        const cwd = self.options.cwd orelse ".";
        const program = try startup.resolveProgram(self.gpa, self.io, self.options.argv[0], cwd, &self.environment);
        defer self.gpa.free(program);
        const argv = try self.gpa.dupe([]const u8, self.options.argv);
        defer self.gpa.free(argv);
        argv[0] = program;
        self.child = try std.process.spawn(self.io, .{ .argv = argv, .cwd = if (self.options.cwd) |path| .{ .path = path } else .inherit, .environ_map = &self.environment, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe, .pgid = if (builtin.os.tag == .windows) null else 0, .start_suspended = builtin.os.tag == .windows, .create_no_window = true });
        errdefer {
            self.child.?.kill(self.io);
            self.child = null;
        }
        self.control = try ownership.Control.init(&self.child.?);
        errdefer {
            self.control.?.kill();
            self.control.?.deinit();
            self.control = null;
        }
        self.receiver = receiver;
        self.started = true;
        self.reader = try self.io.concurrent(readLoop, .{self});
        errdefer {
            self.reader.?.cancel(self.io) catch {};
            self.reader = null;
        }
        self.stderr_reader = try self.io.concurrent(readStderr, .{self});
    }
    fn send(self: *Stdio, value: protocol.Value, abort_flag: ?*bool) !void {
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.McpRequestAborted;
        const bytes = try protocol.json.stringify(self.gpa, value);
        defer self.gpa.free(bytes);
        if (bytes.len > self.options.max_message_bytes) return error.McpMessageTooLarge;
        try self.writing.lock(self.io);
        defer self.writing.unlock(self.io);
        if (self.closing.load(.acquire)) return error.McpConnectionClosed;
        const child = self.child orelse return error.McpConnectionClosed;
        const stdin = child.stdin orelse return error.McpConnectionClosed;
        var buffer: [256]u8 = undefined;
        var writer = stdin.writerStreaming(self.io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    fn emitClosed(self: *Stdio) void {
        if (!self.close_emitted.swap(true, .acq_rel)) if (self.receiver) |receiver| receiver.closed(receiver.context);
    }
    fn readLoop(self: *Stdio) anyerror!void {
        const stdout = self.child.?.stdout.?;
        var input: framing.LineBuffer = .{ .max_message_bytes = self.options.max_message_bytes };
        defer input.deinit(self.gpa);
        while (!self.closing.load(.acquire)) {
            while (input.next(self.gpa) catch |cause| {
                self.receiver.?.failure(self.receiver.?.context, cause);
                self.emitClosed();
                return cause;
            }) |line| {
                defer self.gpa.free(line);
                if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
                var value = protocol.json.Owned.parse(self.gpa, line) catch |cause| {
                    self.receiver.?.failure(self.receiver.?.context, cause);
                    continue;
                };
                defer value.deinit();
                _ = protocol.kind(value.value) catch |cause| {
                    self.receiver.?.failure(self.receiver.?.context, cause);
                    continue;
                };
                self.callback_thread.store(std.Thread.getCurrentId(), .release);
                self.receiver.?.message(self.receiver.?.context, value.value) catch |cause| self.receiver.?.failure(self.receiver.?.context, cause);
                self.callback_thread.store(0, .release);
            }
            var bytes: [4096]u8 = undefined;
            const count = stdout.readStreaming(self.io, &.{&bytes}) catch |cause| {
                if (cause != error.Canceled) {
                    input.finish() catch |failure| self.receiver.?.failure(self.receiver.?.context, failure);
                    self.emitClosed();
                }
                return cause;
            };
            if (count == 0) {
                input.finish() catch |failure| self.receiver.?.failure(self.receiver.?.context, failure);
                self.emitClosed();
                return;
            }
            input.append(self.gpa, bytes[0..count]) catch |cause| {
                self.receiver.?.failure(self.receiver.?.context, cause);
                self.emitClosed();
                return cause;
            };
        }
    }
    fn readStderr(self: *Stdio) anyerror!void {
        const stderr = self.child.?.stderr.?;
        while (!self.closing.load(.acquire)) {
            var bytes: [4096]u8 = undefined;
            const count = stderr.readStreaming(self.io, &.{&bytes}) catch return;
            if (count == 0) return;
            self.stderr_mutex.lockUncancelable(self.io);
            defer self.stderr_mutex.unlock(self.io);
            const keep = @min(count, self.options.max_stderr_bytes);
            const remove = (self.stderr_tail.items.len + keep) -| self.options.max_stderr_bytes;
            std.mem.copyForwards(u8, self.stderr_tail.items[0 .. self.stderr_tail.items.len - remove], self.stderr_tail.items[remove..]);
            self.stderr_tail.items.len -= remove;
            self.stderr_tail.appendSliceAssumeCapacity(bytes[count - keep .. count]);
        }
    }
    pub fn stderrCopy(self: *Stdio, gpa: std.mem.Allocator) ![]u8 {
        try self.stderr_mutex.lock(self.io);
        defer self.stderr_mutex.unlock(self.io);
        return gpa.dupe(u8, self.stderr_tail.items);
    }
    pub fn close(self: *Stdio) !void {
        if (self.callback_thread.load(.acquire) == std.Thread.getCurrentId()) return error.ReentrantMcpTransportClose;
        self.closing.store(true, .release);
        self.lifecycle.lockUncancelable(self.io);
        defer self.lifecycle.unlock(self.io);
        if (self.reader) |*reader| {
            reader.cancel(self.io) catch {};
            self.reader = null;
        }
        if (self.stderr_reader) |*reader| {
            reader.cancel(self.io) catch {};
            self.stderr_reader = null;
        }
        self.writing.lockUncancelable(self.io);
        defer self.writing.unlock(self.io);
        if (self.child) |*child| {
            if (child.stdin) |file| {
                file.close(self.io);
                child.stdin = null;
            }
            if (self.control) |*control| {
                const grace_end = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, @min(500, self.options.close_timeout_ms));
                while ((control.peek() catch null) == null and std.Io.Clock.awake.now(self.io).toMilliseconds() < grace_end) self.io.sleep(.fromMilliseconds(5), .awake) catch break;
                if ((control.peek() catch null) == null) {
                    if (builtin.os.tag == .windows) control.kill() else if (child.id) |id| std.posix.kill(-id, .TERM) catch {
                        std.posix.kill(id, .TERM) catch {};
                    };
                    const end = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, self.options.close_timeout_ms);
                    while ((control.peek() catch null) == null and std.Io.Clock.awake.now(self.io).toMilliseconds() < end) self.io.sleep(.fromMilliseconds(5), .awake) catch break;
                }
                if ((control.peek() catch null) == null) control.kill();
                _ = child.wait(self.io) catch {
                    child.kill(self.io);
                };
                control.deinit();
                self.control = null;
            } else child.kill(self.io);
            self.child = null;
        }
        self.emitClosed();
    }
};
