//! Blocking TCP adapter for the native event-driven Pi protocol client.
//! It mirrors the Unix-domain adapter while remaining available on Windows and
//! remote hosts. Endpoints accept IPv4, bracketed IPv6, and validated DNS
//! hostnames such as `pi.example.com:3141`. Hostname lookup uses Zig's native
//! resolver and races all returned addresses rather than blocking on one family.
const std = @import("std");
const net = std.Io.net;
const client_mod = @import("client.zig");

pub const Options = struct {
    address: []const u8,
    max_pending_bytes: usize = @import("../protocol/framing.zig").DEFAULT_MAX_FRAME_LENGTH * 4,
};

pub const Error = error{
    EmptyAddress,
    MissingPort,
    InvalidAddress,
    InvalidPendingByteLimit,
    Closed,
    EmptyReadBuffer,
};

pub const TcpTransport = struct {
    io: std.Io = undefined,
    stream: net.Stream = undefined,
    reader: net.Stream.Reader = undefined,
    writer: net.Stream.Writer = undefined,
    read_buffer: [16 * 1024]u8 = undefined,
    write_buffer: [16 * 1024]u8 = undefined,
    closed: bool = true,
    max_pending_bytes: usize = 0,

    pub fn connect(self: *TcpTransport, io: std.Io, options: Options) !void {
        try validateOptions(options);
        const endpoint = parseEndpoint(options.address) catch |err| return err;
        // Zig 0.16.0's threaded Io backend currently panics when an IP
        // connect timeout is supplied. Use its portable OS-bounded connect path;
        // callers enforce explicit deadlines on handshake and protocol traffic.
        const connect_options: net.IpAddress.ConnectOptions = .{ .mode = .stream, .protocol = .tcp };
        const stream = switch (endpoint) {
            .literal => |address| try address.connect(io, connect_options),
            .host => |host| try host.name.connect(io, host.port, connect_options),
        };
        self.initFromStream(io, stream, options.max_pending_bytes);
    }

    pub fn initFromStream(self: *TcpTransport, io: std.Io, stream: net.Stream, max_pending_bytes: usize) void {
        self.io = io;
        self.stream = stream;
        self.closed = false;
        self.max_pending_bytes = max_pending_bytes;
        self.reader = stream.reader(io, &self.read_buffer);
        self.writer = stream.writer(io, &self.write_buffer);
    }

    pub fn deinit(self: *TcpTransport) void {
        self.close();
        self.* = undefined;
    }

    pub fn byteTransport(self: *TcpTransport) client_mod.ByteTransport {
        return .{ .context = self, .send_fn = sendCallback, .close_fn = closeCallback };
    }

    pub fn pumpOnce(self: *TcpTransport, client: *client_mod.Client, scratch: []u8) !bool {
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

    pub fn pumpToEnd(self: *TcpTransport, client: *client_mod.Client, scratch: []u8) !void {
        while (try self.pumpOnce(client, scratch)) {}
    }

    pub fn pumpOnceUntil(self: *TcpTransport, client: *client_mod.Client, scratch: []u8, timeout: std.Io.Timeout) !bool {
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

    pub fn close(self: *TcpTransport) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.close(self.io);
    }

    fn sendCallback(raw: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *TcpTransport = @ptrCast(@alignCast(raw.?));
        if (self.closed) return Error.Closed;
        if (bytes.len > self.max_pending_bytes) return Error.InvalidPendingByteLimit;
        try self.writer.interface.writeAll(bytes);
        try self.writer.interface.flush();
    }

    fn closeCallback(raw: ?*anyopaque) void {
        const self: *TcpTransport = @ptrCast(@alignCast(raw.?));
        self.close();
    }
};

pub const Endpoint = union(enum) {
    literal: net.IpAddress,
    host: struct {
        name: net.HostName,
        port: u16,
    },

    pub fn port(self: Endpoint) u16 {
        return switch (self) {
            .literal => |address| address.getPort(),
            .host => |value| value.port,
        };
    }
};

/// Parse an endpoint without performing network I/O. IPv6 literals must use
/// brackets so the final colon remains an unambiguous port separator.
pub fn parseEndpoint(raw: []const u8) !Endpoint {
    if (raw.len == 0) return Error.EmptyAddress;
    if (net.IpAddress.parseLiteral(raw)) |address| {
        if (address.getPort() == 0) return Error.MissingPort;
        return .{ .literal = address };
    } else |_| {}

    const colon = std.mem.lastIndexOfScalar(u8, raw, ':') orelse return Error.MissingPort;
    const host_bytes = raw[0..colon];
    const port_bytes = raw[colon + 1 ..];
    if (host_bytes.len == 0 or port_bytes.len == 0) return Error.MissingPort;
    if (std.mem.indexOfScalar(u8, host_bytes, ':') != null) return Error.InvalidAddress;
    const port = std.fmt.parseInt(u16, port_bytes, 10) catch return Error.InvalidAddress;
    if (port == 0) return Error.MissingPort;
    const host_name = net.HostName.init(host_bytes) catch return Error.InvalidAddress;
    return .{ .host = .{ .name = host_name, .port = port } };
}

/// Backwards-compatible literal-only parser retained for embedding callers.
pub fn parseAddress(raw: []const u8) !net.IpAddress {
    const endpoint = try parseEndpoint(raw);
    return switch (endpoint) {
        .literal => |address| address,
        .host => Error.InvalidAddress,
    };
}

pub fn validateOptions(options: Options) !void {
    _ = try parseEndpoint(options.address);
    if (options.max_pending_bytes == 0) return Error.InvalidPendingByteLimit;
}

test "TCP transport validates IPv4 IPv6 and hostname endpoints" {
    const ip4 = try parseEndpoint("127.0.0.1:3141");
    try std.testing.expect(ip4 == .literal);
    try std.testing.expectEqual(@as(u16, 3141), ip4.port());
    const ip6 = try parseEndpoint("[::1]:9876");
    try std.testing.expect(ip6 == .literal);
    try std.testing.expectEqual(@as(u16, 9876), ip6.port());
    const local = try parseEndpoint("localhost:3141");
    try std.testing.expect(local == .host);
    try std.testing.expectEqualStrings("localhost", local.host.name.bytes);
    try std.testing.expectEqual(@as(u16, 3141), local.host.port);
    const fqdn = try parseEndpoint("pi.example.com.:443");
    try std.testing.expect(fqdn == .host);
    try std.testing.expectEqual(@as(u16, 443), fqdn.port());
    try std.testing.expectError(Error.EmptyAddress, parseEndpoint(""));
    try std.testing.expectError(Error.MissingPort, parseEndpoint("127.0.0.1"));
    try std.testing.expectError(Error.MissingPort, parseEndpoint("localhost"));
    try std.testing.expectError(Error.InvalidAddress, parseEndpoint("::1:3141"));
    try std.testing.expectError(Error.InvalidAddress, parseEndpoint("bad_name:3141"));
    try std.testing.expectError(Error.InvalidAddress, parseAddress("localhost:3141"));
    try std.testing.expectError(Error.InvalidPendingByteLimit, validateOptions(.{ .address = "localhost:1", .max_pending_bytes = 0 }));
}

test "TCP stream adapter performs protocol handshake over a stream pair" {
    if (@import("builtin").os.tag == .windows or @import("builtin").os.tag == .wasi) return error.SkipZigTest;
    const protocol = @import("../protocol/root.zig");
    var handles: [2]std.posix.socket_t = undefined;
    const rc = std.posix.system.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM | std.posix.SOCK.CLOEXEC, 0, &handles);
    if (std.posix.errno(rc) != .SUCCESS) return error.SkipZigTest;
    const placeholder: net.IpAddress = .{ .ip4 = .loopback(0) };
    var peer = net.Stream{ .socket = .{ .handle = handles[0], .address = placeholder } };
    defer peer.close(std.testing.io);
    var transport: TcpTransport = undefined;
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

    const hello = try protocol.codec.encodeJsonFrame(std.testing.allocator, "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"tcp-1\",\"snapshot\":{\"serverId\":\"server\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}}");
    defer std.testing.allocator.free(hello);
    var peer_write_buffer: [4096]u8 = undefined;
    var peer_writer = peer.writer(std.testing.io, &peer_write_buffer);
    try peer_writer.interface.writeAll(hello);
    try peer_writer.interface.flush();
    var scratch: [64]u8 = undefined;
    while (!client.connected()) _ = try transport.pumpOnce(&client, &scratch);
    try std.testing.expect(client.connected());
}
