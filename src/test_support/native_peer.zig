//! Bounded portable raw native-worker protocol with exact owned-child cleanup.
const std = @import("std");
const Io = std.Io;
pub const Peer = struct {
    gpa: std.mem.Allocator,
    io: Io,
    child: std.process.Child,
    buffer: [4096]u8 = undefined,
    reader: Io.File.Reader,
    closed: bool = false,
    actions: std.ArrayList([]u8) = .empty,
    pub fn start(gpa: std.mem.Allocator, io: Io, binary: []const u8, source: []const u8, errors: Io.File) !*Peer {
        const self = try gpa.create(Peer);
        errdefer gpa.destroy(self);
        var env: std.process.Environ.Map = .init(gpa);
        defer env.deinit();
        try env.put("PATH", std.fs.path.dirname(binary).?);
        const child = try std.process.spawn(io, .{ .argv = &.{ binary, "--internal-native-extension-worker", source }, .environ_map = &env, .stdin = .pipe, .stdout = .pipe, .stderr = .{ .file = errors }, .create_no_window = true });
        self.* = .{ .gpa = gpa, .io = io, .child = child, .reader = undefined };
        self.reader = self.child.stdout.?.readerStreaming(io, &self.buffer);
        return self;
    }
    pub fn deinit(self: *Peer) void {
        self.stop();
        if (self.child.stdin) |file| file.close(self.io);
        if (self.child.stdout) |file| file.close(self.io);
        for (self.actions.items) |bytes| self.gpa.free(bytes);
        self.actions.deinit(self.gpa);
        self.gpa.destroy(self);
    }
    fn stop(self: *Peer) void {
        if (self.closed) return;
        self.closed = true;
        if (self.child.id != null) {
            if (@import("builtin").os.tag == .windows) self.child.kill(self.io) else {
                std.posix.kill(self.child.id.?, .KILL) catch {};
                _ = self.child.wait(self.io) catch {};
            }
        }
    }
    pub fn send(self: *Peer, value: anytype) !void {
        const bytes = try std.json.Stringify.valueAlloc(self.gpa, value, .{});
        defer self.gpa.free(bytes);
        try self.child.stdin.?.writeStreamingAll(self.io, bytes);
        try self.child.stdin.?.writeStreamingAll(self.io, "\n");
    }
    fn blocking(self: *Peer) ![]u8 {
        while (try self.reader.interface.takeByte() != 0x1e) {}
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(self.gpa);
        while (true) {
            const byte = try self.reader.interface.takeByte();
            if (byte == '\n') return bytes.toOwnedSlice(self.gpa);
            if (bytes.items.len >= 2 * 1024 * 1024) return error.NativePeerRecordTooLarge;
            try bytes.append(self.gpa, byte);
        }
    }
    fn deadline(io: Io) bool {
        io.sleep(.fromSeconds(10), .awake) catch return false;
        return true;
    }
    pub fn record(self: *Peer) !std.json.Parsed(std.json.Value) {
        const Race = union(enum) { record: anyerror![]u8, timeout: bool };
        var queue: [2]Race = undefined;
        var select = Io.Select(Race).init(self.io, &queue);
        defer while (select.cancel()) |pending| switch (pending) {
            .record => |result| if (result) |bytes| self.gpa.free(bytes) else |_| {},
            .timeout => {},
        };
        try select.concurrent(.record, blocking, .{self});
        try select.concurrent(.timeout, deadline, .{self.io});
        const winner = try select.await();
        const bytes = switch (winner) {
            .record => |result| try result,
            .timeout => {
                // Kill only this owned, unreaped child before joining a
                // pending pipe read, so an uncooperative worker cannot pin it.
                self.stop();
                return error.NativePeerTimeout;
            },
        };
        defer self.gpa.free(bytes);
        return std.json.parseFromSlice(std.json.Value, self.gpa, bytes, .{ .allocate = .alloc_always });
    }
    pub fn shutdown(self: *Peer) !void {
        try self.send(.{ .kind = "shutdown" });
        const ack = try self.record();
        defer ack.deinit();
        try std.testing.expectEqual(std.json.Value{ .bool = true }, ack.value.object.get("ok").?);
        self.child.stdin.?.close(self.io);
        self.child.stdin = null;
        const term = try self.child.wait(self.io);
        self.closed = true;
        try std.testing.expect(term == .exited and term.exited == 0);
    }
};
