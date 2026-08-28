//! Blocking Unix-domain socket adapter for the native event-driven client.
//! Writes are fully ordered and flushed before returning; reads may be pumped
//! incrementally so callers choose their own thread/event-loop policy.
const std = @import("std");
const builtin = @import("builtin");
const net = std.Io.net;
const client_mod = @import("client.zig");

pub const MAX_UNIX_SOCKET_PATH_BYTES: usize = if (builtin.os.tag == .linux) 107 else 103;

pub const Options = struct {
    path: []const u8,
    max_pending_bytes: usize = @import("../protocol/framing.zig").DEFAULT_MAX_FRAME_LENGTH * 4,
};

pub const Error = error{
    EmptyPath,
    PathTooLong,
    InvalidPendingByteLimit,
    UnsupportedPlatform,
    Closed,
    EmptyReadBuffer,
};

pub const UnixTransport = struct {
    io: std.Io = undefined,
    stream: net.Stream = undefined,
    reader: net.Stream.Reader = undefined,
    writer: net.Stream.Writer = undefined,
    read_buffer: [16 * 1024]u8 = undefined,
    write_buffer: [16 * 1024]u8 = undefined,
    closed: bool = true,
    max_pending_bytes: usize = 0,

    pub fn connect(self: *UnixTransport, io: std.Io, options: Options) !void {
        try validateOptions(options);
        if (!net.has_unix_sockets) return Error.UnsupportedPlatform;
        const address = net.UnixAddress.init(options.path) catch return Error.PathTooLong;
        const stream = try address.connect(io);
        self.initFromStream(io, stream, options.max_pending_bytes);
    }

    pub fn initFromStream(self: *UnixTransport, io: std.Io, stream: net.Stream, max_pending_bytes: usize) void {
        self.io = io;
        self.stream = stream;
        self.closed = false;
        self.max_pending_bytes = max_pending_bytes;
        self.reader = stream.reader(io, &self.read_buffer);
        self.writer = stream.writer(io, &self.write_buffer);
    }

    pub fn deinit(self: *UnixTransport) void {
        self.close();
        self.* = undefined;
    }

    pub fn byteTransport(self: *UnixTransport) client_mod.ByteTransport {
        return .{ .context = self, .send_fn = sendCallback, .close_fn = closeCallback };
    }

    /// Reads one arbitrary chunk and delivers it to the client. Returns false
    /// after orderly EOF, after first notifying the client's frame decoder.
    pub fn pumpOnce(self: *UnixTransport, client: *client_mod.Client, scratch: []u8) !bool {
        if (self.closed) return Error.Closed;
        if (scratch.len == 0) return Error.EmptyReadBuffer;
        const message = try self.stream.socket.receive(self.io, scratch);
        if (message.data.len == 0) {
            client.transportEnded() catch {};
            self.closed = true;
            return false;
        }
        try client.feed(message.data);
        return true;
    }

    pub fn pumpToEnd(self: *UnixTransport, client: *client_mod.Client, scratch: []u8) !void {
        while (try self.pumpOnce(client, scratch)) {}
    }

    /// Reads one chunk using an absolute timeout. Callers that need a bounded
    /// command lifecycle can reuse the same deadline across fragmented frames.
    pub fn pumpOnceUntil(self: *UnixTransport, client: *client_mod.Client, scratch: []u8, timeout: std.Io.Timeout) !bool {
        if (self.closed) return Error.Closed;
        if (scratch.len == 0) return Error.EmptyReadBuffer;
        const message = try self.stream.socket.receiveTimeout(self.io, scratch, timeout);
        if (message.data.len == 0) {
            client.transportEnded() catch {};
            self.closed = true;
            return false;
        }
        try client.feed(message.data);
        return true;
    }

    pub fn close(self: *UnixTransport) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.close(self.io);
    }

    fn sendCallback(raw: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *UnixTransport = @ptrCast(@alignCast(raw.?));
        if (self.closed) return Error.Closed;
        if (bytes.len > self.max_pending_bytes) return Error.InvalidPendingByteLimit;
        try self.writer.interface.writeAll(bytes);
        try self.writer.interface.flush();
    }

    fn closeCallback(raw: ?*anyopaque) void {
        const self: *UnixTransport = @ptrCast(@alignCast(raw.?));
        self.close();
    }
};

pub fn validateOptions(options: Options) !void {
    if (options.path.len == 0) return Error.EmptyPath;
    if (options.path.len > MAX_UNIX_SOCKET_PATH_BYTES) return Error.PathTooLong;
    if (options.max_pending_bytes == 0) return Error.InvalidPendingByteLimit;
    if (builtin.os.tag == .windows) return Error.UnsupportedPlatform;
}

test "unix transport validates path and pending limits" {
    try std.testing.expectError(Error.EmptyPath, validateOptions(.{ .path = "" }));
    const long_path = "x" ** (MAX_UNIX_SOCKET_PATH_BYTES + 1);
    try std.testing.expectError(Error.PathTooLong, validateOptions(.{ .path = long_path }));
    try std.testing.expectError(Error.InvalidPendingByteLimit, validateOptions(.{ .path = "/tmp/pi.sock", .max_pending_bytes = 0 }));
    if (builtin.os.tag != .windows) try validateOptions(.{ .path = "/tmp/pi.sock" });
}

test "stream adapter orders client hello and pumps fragmented server data" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    const protocol = @import("../protocol/root.zig");
    var handles: [2]std.posix.socket_t = undefined;
    const rc = std.posix.system.socketpair(
        std.posix.AF.UNIX,
        std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC,
        0,
        &handles,
    );
    if (std.posix.errno(rc) != .SUCCESS) return error.SkipZigTest;
    const placeholder: net.IpAddress = .{ .ip4 = .loopback(0) };
    var peer = net.Stream{ .socket = .{ .handle = handles[0], .address = placeholder } };
    defer peer.close(std.testing.io);
    var transport: UnixTransport = undefined;
    transport.initFromStream(std.testing.io, .{ .socket = .{ .handle = handles[1], .address = placeholder } }, 1024 * 1024);
    defer if (!transport.closed) transport.close();

    var client = try client_mod.Client.init(std.testing.allocator, .{});
    defer client.deinit();
    try client.connect(transport.byteTransport());

    var peer_read_buffer: [4096]u8 = undefined;
    var peer_reader = peer.reader(std.testing.io, &peer_read_buffer);
    var prefix: [4]u8 = undefined;
    try peer_reader.interface.readSliceAll(&prefix);
    const length = (@as(usize, prefix[0]) << 24) | (@as(usize, prefix[1]) << 16) | (@as(usize, prefix[2]) << 8) | prefix[3];
    const payload = try std.testing.allocator.alloc(u8, length);
    defer std.testing.allocator.free(payload);
    try peer_reader.interface.readSliceAll(payload);
    const framed = try std.testing.allocator.alloc(u8, length + 4);
    defer std.testing.allocator.free(framed);
    @memcpy(framed[0..4], &prefix);
    @memcpy(framed[4..], payload);
    var decoded = try protocol.codec.decodeClientFrame(std.testing.allocator, framed);
    defer protocol.json.deinitClientMessage(std.testing.allocator, &decoded);
    try std.testing.expect(decoded == .hello);

    const server_json = "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"unix-1\",\"snapshot\":{\"serverId\":\"server\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}}";
    const response = try protocol.codec.encodeJsonFrame(std.testing.allocator, server_json);
    defer std.testing.allocator.free(response);
    var peer_write_buffer: [4096]u8 = undefined;
    var peer_writer = peer.writer(std.testing.io, &peer_write_buffer);
    try peer_writer.interface.writeAll(response[0..3]);
    try peer_writer.interface.flush();
    var scratch: [2]u8 = undefined;
    _ = try transport.pumpOnce(&client, &scratch);
    try peer_writer.interface.writeAll(response[3..]);
    try peer_writer.interface.flush();
    while (!client.connected()) _ = try transport.pumpOnce(&client, &scratch);
    try std.testing.expect(client.connected());
}
