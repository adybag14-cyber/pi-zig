//! Compatibility adapter: native session owns every live transport and pending request.
const std = @import("std");
const builtin = @import("builtin");
const session = @import("session.zig");
const protocol = @import("protocol.zig");
const Stdio = @import("stdio_transport.zig").Stdio;
const Http = @import("http_transport.zig").Http;

pub const Adapter = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    stdio: ?*Stdio = null,
    http: ?*Http = null,
    client: ?*session.Client = null,
    notifications: std.atomic.Value(usize) = .init(0),

    /// An omitted map preserves legacy spawn's inherited environment. Explicit maps
    /// are capabilities: even an explicitly empty PATH retains its precedence.
    pub fn openStdio(gpa: std.mem.Allocator, io: std.Io, argv: []const []const u8, environment: ?*const std.process.Environ.Map, timeout_ms: u32) !*Adapter {
        var inherited: ?std.process.Environ.Map = null;
        defer if (inherited) |*map| map.deinit();
        const map = environment orelse blk: {
            inherited = try inheritedEnvironment(gpa);
            break :blk &inherited.?;
        };
        const self = try gpa.create(Adapter);
        self.* = .{ .gpa = gpa, .io = io };
        errdefer self.deinit();
        self.stdio = try Stdio.create(gpa, io, .{ .argv = argv, .environ = map });
        try self.initialize(timeout_ms);
        return self;
    }
    pub fn openHttp(gpa: std.mem.Allocator, io: std.Io, url: []const u8, timeout_ms: u32) !*Adapter {
        const self = try gpa.create(Adapter);
        self.* = .{ .gpa = gpa, .io = io };
        errdefer self.deinit();
        self.http = try Http.create(gpa, io, .{ .url = url, .open_get_stream = false });
        try self.initialize(timeout_ms);
        return self;
    }
    fn initialize(self: *Adapter, timeout_ms: u32) !void {
        const transport = if (self.stdio) |stdio| stdio.transport() else self.http.?.transport();
        self.client = try session.Client.create(self.gpa, self.io, transport, .{
            .version = "1.1.0",
            .request_timeout_ms = @floatFromInt(timeout_ms),
            .context = self,
            .on_notification = notified,
        });
        var initialized = try self.client.?.connect();
        initialized.deinit();
    }
    fn notified(raw: ?*anyopaque, _: []const u8, _: ?protocol.Value) !void {
        const self: *Adapter = @ptrCast(@alignCast(raw.?));
        _ = self.notifications.fetchAdd(1, .monotonic);
    }
    pub fn protocolVersion(self: *Adapter) []const u8 {
        return self.client.?.initialized.?.value.object.get("protocolVersion").?.string;
    }
    pub fn childPointer(self: *Adapter) ?*std.process.Child {
        if (self.stdio) |stdio| if (stdio.child != null) return &stdio.child.?;
        return null;
    }
    pub fn exchange(self: *Adapter, request: []const u8, expected_id: u64, timeout_ms: u32) ![]u8 {
        const client = self.client orelse return error.NotConnected;
        const parsed = try std.json.parseFromSlice(protocol.Value, self.gpa, request, .{});
        defer parsed.deinit();
        const method = try protocol.text(parsed.value, "method");
        // The compatibility facade is sequential and retains its public numeric ID.
        client.mutex.lockUncancelable(self.io);
        if (client.pending.count() != 0) {
            client.mutex.unlock(self.io);
            return error.ConcurrentLegacyMcpRequest;
        }
        client.next_id = expected_id;
        client.mutex.unlock(self.io);
        var result = try client.request(method, parsed.value.object.get("params"), .{ .timeout_ms = @floatFromInt(timeout_ms) });
        defer result.deinit();
        var response = try protocol.response(self.gpa, .{ .integer = @intCast(expected_id) }, result.value, false);
        defer response.deinit();
        return protocol.json.stringify(self.gpa, response.value);
    }
    /// A legacy caller may explicitly close stdin and wait on the retained child.
    /// Join readers before forgetting that already-reaped handle; never wait twice.
    fn reconcileExternalWait(self: *Adapter) void {
        const stdio = self.stdio orelse return;
        if (stdio.child) |child| if (child.id == null) {
            stdio.lifecycle.lockUncancelable(self.io);
            defer stdio.lifecycle.unlock(self.io);
            if (stdio.reader) |*reader| {
                reader.cancel(self.io) catch {};
                stdio.reader = null;
            }
            if (stdio.stderr_reader) |*reader| {
                reader.cancel(self.io) catch {};
                stdio.stderr_reader = null;
            }
            if (stdio.control) |*control| {
                control.deinit();
                stdio.control = null;
            }
            stdio.child = null;
        };
    }
    pub fn close(self: *Adapter) void {
        self.reconcileExternalWait();
        if (self.client) |client| client.close() catch {};
    }
    pub fn deinit(self: *Adapter) void {
        self.close();
        if (self.client) |client| client.deinit();
        if (self.stdio) |stdio| stdio.deinit();
        if (self.http) |http| http.deinit();
        self.gpa.destroy(self);
    }
};

extern "c" fn _NSGetEnviron() *[*:null]?[*:0]u8;
fn inheritedEnvironment(gpa: std.mem.Allocator) !std.process.Environ.Map {
    if (builtin.os.tag == .windows) return (std.process.Environ{ .block = .global }).createMap(gpa);
    const variables = if (builtin.os.tag.isDarwin()) _NSGetEnviron().* else std.c.environ;
    return (std.process.Environ{ .block = .{ .slice = std.mem.span(variables) } }).createMap(gpa);
}
