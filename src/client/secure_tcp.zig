//! Raw Pi protocol transport over direct TCP or certificate-verified TLS.
//!
//! Connections may use target-aware HTTP/HTTPS CONNECT proxies from the
//! process environment or an explicit CLI proxy. The protocol itself remains
//! Pi's length-prefixed protocol-v1 stream; HTTP is used only for proxy tunnel
//! establishment by `std.http.Client`.
const std = @import("std");
const net = std.Io.net;
const client_mod = @import("client.zig");
const tcp = @import("tcp.zig");
const http_proxy = @import("../ai/http_proxy.zig");

pub const Options = struct {
    address: []const u8,
    tls: bool = false,
    /// Explicit proxy URL. It overrides proxy environment variables.
    proxy: ?[]const u8 = null,
    /// Disable both environment and explicit proxy routing.
    disable_proxy: bool = false,
    environ: ?*const std.process.Environ.Map = null,
    max_pending_bytes: usize = @import("../protocol/framing.zig").DEFAULT_MAX_FRAME_LENGTH * 4,
};

pub const Error = error{
    InvalidPendingByteLimit,
    EmptyReadBuffer,
    Closed,
    ConflictingProxyOptions,
    CertificateBundleLoadFailure,
};

pub const SecureTcpTransport = struct {
    gpa: std.mem.Allocator = undefined,
    io: std.Io = undefined,
    proxy_arena: std.heap.ArenaAllocator = undefined,
    http_client: std.http.Client = undefined,
    connection: ?*std.http.Client.Connection = null,
    /// A second TLS layer used after an HTTP CONNECT tunnel. The underlying
    /// connection may itself be TLS when the proxy URL uses https://.
    target_tls: ?*std.crypto.tls.Client = null,
    target_tls_read_buffer: ?[]u8 = null,
    target_tls_write_buffer: ?[]u8 = null,
    closed: bool = true,
    max_pending_bytes: usize = 0,

    pub fn connect(self: *SecureTcpTransport, gpa: std.mem.Allocator, io: std.Io, options: Options) !void {
        try validateOptions(options);
        self.* = .{
            .gpa = gpa,
            .io = io,
            .proxy_arena = std.heap.ArenaAllocator.init(gpa),
            .http_client = .{ .allocator = gpa, .io = io },
            .connection = null,
            .target_tls = null,
            .target_tls_read_buffer = null,
            .target_tls_write_buffer = null,
            .closed = true,
            .max_pending_bytes = options.max_pending_bytes,
        };
        errdefer {
            self.releaseConnection();
            self.freeTargetTls();
            self.http_client.deinit();
            self.proxy_arena.deinit();
            self.* = undefined;
        }

        const arena = self.proxy_arena.allocator();
        const scheme = if (options.tls) "https" else "http";
        const target_url = try std.fmt.allocPrint(arena, "{s}://{s}/", .{ scheme, options.address });
        const uri = std.Uri.parse(target_url) catch return tcp.Error.InvalidAddress;
        var host_buffer: [net.HostName.max_len]u8 = undefined;
        const host = uri.getHost(&host_buffer) catch return tcp.Error.InvalidAddress;
        const port = uri.port orelse return tcp.Error.MissingPort;

        const proxy_env = if (options.disable_proxy or options.proxy != null) null else options.environ;
        const explicit_proxy = if (options.disable_proxy) null else options.proxy;
        const configured_proxy = try http_proxy.configureClientForTarget(&self.http_client, arena, target_url, proxy_env, explicit_proxy);

        const target_protocol: std.http.Client.Protocol = if (options.tls) .tls else .plain;
        const proxy = if (configured_proxy) switch (target_protocol) {
            .plain => self.http_client.http_proxy,
            .tls => self.http_client.https_proxy,
        } else null;

        // A CONNECT response and a nested TLS handshake both need enough room
        // in the underlying reader for a complete TLS record.
        if (proxy != null or target_protocol == .tls) {
            self.http_client.read_buffer_size = @max(self.http_client.read_buffer_size, std.crypto.tls.Client.min_buffer_len);
            try prepareTls(&self.http_client);
        }

        if (proxy) |selected| {
            if (selected.host.eql(host) and selected.port == port and selected.protocol == target_protocol) {
                self.connection = try self.http_client.connectTcp(host, port, target_protocol);
            } else {
                self.connection = try establishConnectTunnel(&self.http_client, selected, host, port);
                if (target_protocol == .tls) try self.enableTargetTls(host);
            }
        } else {
            self.connection = try self.http_client.connectTcp(host, port, target_protocol);
        }
        self.closed = false;
    }

    pub fn deinit(self: *SecureTcpTransport) void {
        self.close();
        self.freeTargetTls();
        self.http_client.deinit();
        self.proxy_arena.deinit();
        self.* = undefined;
    }

    pub fn byteTransport(self: *SecureTcpTransport) client_mod.ByteTransport {
        return .{ .context = self, .send_fn = sendCallback, .close_fn = closeCallback };
    }

    pub fn pumpOnce(self: *SecureTcpTransport, client: *client_mod.Client, scratch: []u8) !bool {
        if (self.closed) return Error.Closed;
        if (scratch.len == 0) return Error.EmptyReadBuffer;
        const count = try readAvailable(self.activeReader(), scratch);
        return self.finishRead(client, scratch[0..count]);
    }

    pub fn pumpOnceUntil(self: *SecureTcpTransport, client: *client_mod.Client, scratch: []u8, timeout: std.Io.Timeout) !bool {
        if (self.closed) return Error.Closed;
        if (scratch.len == 0) return Error.EmptyReadBuffer;

        const Race = union(enum) { read: anyerror!usize, timeout: bool };
        var queue: [2]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        select.async(.read, readSomeTask, .{ self.activeReader(), scratch });
        select.async(.timeout, timeoutTask, .{ self.io, timeout });
        const winner = try select.await();
        switch (winner) {
            .read => |result| {
                while (select.cancel()) |_| {}
                const count = try result;
                return self.finishRead(client, scratch[0..count]);
            },
            .timeout => |expired| {
                while (select.cancel()) |_| {}
                if (expired) return error.Timeout;
                return error.Canceled;
            },
        }
    }

    pub fn pumpToEnd(self: *SecureTcpTransport, client: *client_mod.Client, scratch: []u8) !void {
        while (try self.pumpOnce(client, scratch)) {}
    }

    pub fn close(self: *SecureTcpTransport) void {
        if (self.closed) return;
        self.closed = true;
        if (self.target_tls) |tls_client| {
            tls_client.end() catch {};
            if (self.connection) |connection| connection.flush() catch {};
        }
        self.releaseConnection();
    }

    fn releaseConnection(self: *SecureTcpTransport) void {
        if (self.connection) |connection| {
            connection.end() catch {};
            connection.closing = true;
            self.http_client.connection_pool.release(connection, self.io);
            self.connection = null;
        }
    }

    fn activeReader(self: *SecureTcpTransport) *std.Io.Reader {
        if (self.target_tls) |tls_client| return &tls_client.reader;
        return self.connection.?.reader();
    }

    fn activeWriter(self: *SecureTcpTransport) *std.Io.Writer {
        if (self.target_tls) |tls_client| return &tls_client.writer;
        return self.connection.?.writer();
    }

    fn enableTargetTls(self: *SecureTcpTransport, host: net.HostName) !void {
        const read_buffer = try self.gpa.alloc(u8, std.crypto.tls.Client.min_buffer_len + 16 * 1024);
        errdefer self.gpa.free(read_buffer);
        const write_buffer = try self.gpa.alloc(u8, std.crypto.tls.Client.min_buffer_len);
        errdefer self.gpa.free(write_buffer);
        const tls_client = try self.gpa.create(std.crypto.tls.Client);
        errdefer self.gpa.destroy(tls_client);

        var entropy: [std.crypto.tls.Client.Options.entropy_len]u8 = undefined;
        self.io.random(&entropy);
        tls_client.* = try std.crypto.tls.Client.init(
            self.connection.?.reader(),
            self.connection.?.writer(),
            .{
                .host = .{ .explicit = host.bytes },
                .ca = .{ .bundle = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .lock = &self.http_client.ca_bundle_lock,
                    .bundle = &self.http_client.ca_bundle,
                } },
                .write_buffer = write_buffer,
                .read_buffer = read_buffer,
                .entropy = &entropy,
                .realtime_now = self.http_client.now.?,
                .allow_truncation_attacks = false,
            },
        );
        self.target_tls = tls_client;
        self.target_tls_read_buffer = read_buffer;
        self.target_tls_write_buffer = write_buffer;
    }

    fn freeTargetTls(self: *SecureTcpTransport) void {
        if (self.target_tls) |value| self.gpa.destroy(value);
        if (self.target_tls_read_buffer) |value| self.gpa.free(value);
        if (self.target_tls_write_buffer) |value| self.gpa.free(value);
        self.target_tls = null;
        self.target_tls_read_buffer = null;
        self.target_tls_write_buffer = null;
    }

    fn finishRead(self: *SecureTcpTransport, client: *client_mod.Client, bytes: []const u8) !bool {
        if (bytes.len == 0) {
            client.transportEnded() catch {};
            self.close();
            return false;
        }
        try client.feed(bytes);
        return true;
    }

    fn sendCallback(raw: ?*anyopaque, bytes: []const u8) anyerror!void {
        const self: *SecureTcpTransport = @ptrCast(@alignCast(raw.?));
        if (self.closed) return Error.Closed;
        if (bytes.len > self.max_pending_bytes) return Error.InvalidPendingByteLimit;
        try self.activeWriter().writeAll(bytes);
        try self.activeWriter().flush();
        // A nested target TLS writer flushes ciphertext into the proxy
        // connection; flush that lower layer as well.
        try self.connection.?.flush();
    }

    fn closeCallback(raw: ?*anyopaque) void {
        const self: *SecureTcpTransport = @ptrCast(@alignCast(raw.?));
        self.close();
    }
};

pub fn validateOptions(options: Options) !void {
    try tcp.validateOptions(.{ .address = options.address, .max_pending_bytes = options.max_pending_bytes });
    if (options.proxy != null and options.disable_proxy) return Error.ConflictingProxyOptions;
}

fn establishConnectTunnel(
    client: *std.http.Client,
    proxy: *std.http.Client.Proxy,
    target_host: net.HostName,
    target_port: u16,
) !*std.http.Client.Connection {
    const connection = try client.connectTcp(proxy.host, proxy.port, proxy.protocol);
    errdefer {
        connection.closing = true;
        client.connection_pool.release(connection, client.io);
    }

    var authorization_header: [1]std.http.Header = undefined;
    const extra_headers: []const std.http.Header = if (proxy.authorization) |authorization| headers: {
        authorization_header[0] = .{ .name = "proxy-authorization", .value = authorization };
        break :headers &authorization_header;
    } else &.{};

    var request = try client.request(.CONNECT, .{
        .scheme = "http",
        .host = .{ .raw = target_host.bytes },
        .port = target_port,
    }, .{
        .redirect_behavior = .unhandled,
        .connection = connection,
        .extra_headers = extra_headers,
    });
    defer request.deinit();
    try request.sendBodiless();
    const response = try request.receiveHead(&.{});
    if (response.head.status != .ok) return error.ProxyTunnelRejected;

    // The connection is now a raw tunnel and must never return to the ordinary
    // HTTP keep-alive pool. SecureTcpTransport releases it only during close.
    request.connection = null;
    connection.proxied = false;
    connection.closing = false;
    return connection;
}

fn prepareTls(client: *std.http.Client) !void {
    var bundle: std.crypto.Certificate.Bundle = .empty;
    errdefer bundle.deinit(client.allocator);
    const now = std.Io.Clock.real.now(client.io);
    bundle.rescan(client.allocator, client.io, now) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => return Error.CertificateBundleLoadFailure,
    };
    client.now = now;
    std.mem.swap(std.crypto.Certificate.Bundle, &client.ca_bundle, &bundle);
    bundle.deinit(client.allocator);
}

fn readSomeTask(reader: *std.Io.Reader, buffer: []u8) anyerror!usize {
    return readAvailable(reader, buffer);
}

/// Zig 0.16 `readSliceShort` fills the entire destination unless EOF occurs,
/// which is unsuitable for an open streaming protocol. Pull at least one byte
/// and return every byte already buffered without waiting for `buffer.len`.
fn readAvailable(reader: *std.Io.Reader, buffer: []u8) !usize {
    if (buffer.len == 0) return 0;
    const available = reader.peekGreedy(1) catch |err| switch (err) {
        error.EndOfStream => return 0,
        else => return err,
    };
    const count = @min(buffer.len, available.len);
    @memcpy(buffer[0..count], available[0..count]);
    reader.toss(count);
    return count;
}

fn timeoutTask(io: std.Io, timeout: std.Io.Timeout) bool {
    timeout.sleep(io) catch return false;
    return true;
}

test "secure TCP options validate endpoint and proxy conflicts" {
    try validateOptions(.{ .address = "localhost:3141", .tls = true });
    try validateOptions(.{ .address = "[::1]:443", .tls = true, .proxy = "http://proxy:3128" });
    try std.testing.expectError(Error.ConflictingProxyOptions, validateOptions(.{ .address = "localhost:1", .proxy = "http://proxy", .disable_proxy = true }));
    try std.testing.expectError(tcp.Error.MissingPort, validateOptions(.{ .address = "localhost" }));
    try std.testing.expectError(Error.InvalidPendingByteLimit, validateOptions(.{ .address = "localhost:1", .max_pending_bytes = 0 }));
}

test "secure transport explicit proxy overrides environment and disable_proxy bypasses both" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("HTTPS_PROXY", "http://environment:8080");

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    var client: std.http.Client = .{ .allocator = gpa, .io = std.testing.io };
    defer client.deinit();
    const target = "https://example.com:443/";
    _ = try http_proxy.configureClientForTarget(&client, arena_state.allocator(), target, null, "http://explicit:3128");
    try std.testing.expectEqualStrings("explicit", client.https_proxy.?.host.bytes);

    var direct_client: std.http.Client = .{ .allocator = gpa, .io = std.testing.io };
    defer direct_client.deinit();
    var direct_arena = std.heap.ArenaAllocator.init(gpa);
    defer direct_arena.deinit();
    const configured = try http_proxy.configureClientForTarget(&direct_client, direct_arena.allocator(), target, null, null);
    try std.testing.expect(!configured);
}
