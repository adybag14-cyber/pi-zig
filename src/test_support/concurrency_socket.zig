//! Cancellable portable loopback peer for native HTTP/SSE/WebSocket races.
const std = @import("std");
const Io = std.Io;
pub const Reply = struct {
    head: []const u8 = "HTTP/1.1 200 OK\r\nContent-Length: 1\r\nConnection: close\r\n\r\n",
    body: []const u8 = "x",
    head_delay_ms: u32 = 0,
    body_delay_ms: u32 = 0,
    websocket_upgrade: bool = false,
};
pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    listener: Io.net.Server,
    reply: Reply,
    head_seen: Io.Event = .unset,
    request_seen: Io.Event = .unset,
    future: ?Io.Future(anyerror!void) = null,
    pub fn init(gpa: std.mem.Allocator, io: Io, reply: Reply) !*Server {
        const self = try gpa.create(Server);
        errdefer gpa.destroy(self);
        const address = try Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        self.* = .{ .gpa = gpa, .io = io, .listener = try address.listen(io, .{ .reuse_address = true }), .reply = reply };
        errdefer self.listener.deinit(io);
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    pub fn url(self: *Server, gpa: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/controlled", .{self.listener.socket.address.getPort()});
    }
    pub fn finish(self: *Server) !void {
        if (self.future) |*future| {
            const result = future.await(self.io);
            self.future = null;
            try result;
        }
    }
    pub fn deinit(self: *Server) void {
        if (self.future) |*future| future.cancel(self.io) catch {};
        self.listener.deinit(self.io);
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    fn serve(self: *Server) anyerror!void {
        const peer = try self.listener.accept(self.io);
        defer peer.close(self.io);
        var read_buffer: [16 * 1024]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;
        var reader = peer.reader(self.io, &read_buffer);
        var writer = peer.writer(self.io, &write_buffer);
        var http = std.http.Server.init(&reader.interface, &writer.interface);
        var request = try http.receiveHead();
        self.request_seen.set(self.io);
        if (self.reply.head_delay_ms > 0) try self.io.sleep(.fromMilliseconds(self.reply.head_delay_ms), .awake);
        if (self.reply.websocket_upgrade) {
            var iterator = request.iterateHeaders();
            var key: ?[]const u8 = null;
            while (iterator.next()) |header| if (std.ascii.eqlIgnoreCase(header.name, "sec-websocket-key")) {
                key = header.value;
            };
            var sha = std.crypto.hash.Sha1.init(.{});
            sha.update(key orelse return error.MissingFixtureWebSocketKey);
            sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
            var digest: [20]u8 = undefined;
            sha.final(&digest);
            var encoded: [28]u8 = undefined;
            const accept = std.base64.standard.Encoder.encode(&encoded, &digest);
            try writer.interface.print("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
        } else try writer.interface.writeAll(self.reply.head);
        try writer.interface.flush();
        self.head_seen.set(self.io);
        if (self.reply.body_delay_ms > 0) try self.io.sleep(.fromMilliseconds(self.reply.body_delay_ms), .awake);
        try writer.interface.writeAll(self.reply.body);
        try writer.interface.flush();
    }
};

pub fn abortAfterRequest(comptime Adapter: type, adapter: *Adapter, started: *Io.Event, expected: anyerror) !void {
    const Task = struct {
        adapter: *Adapter,
        aborted: bool = false,
        done: Io.Event = .unset,
        failure: ?anyerror = null,
        fn run(self: *@This()) Io.Cancelable!void {
            defer self.done.set(std.testing.io);
            self.adapter.run(&self.aborted) catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var task: Task = .{ .adapter = adapter };
    var group: Io.Group = .init;
    defer group.cancel(std.testing.io);
    try group.concurrent(std.testing.io, Task.run, .{&task});
    try started.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    try std.testing.io.sleep(.fromMilliseconds(25), .awake);
    @atomicStore(bool, &task.aborted, true, .release);
    try task.done.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    try std.testing.expectEqual(expected, task.failure.?);
}
