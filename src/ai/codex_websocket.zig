//! Minimal RFC6455 client transport used by ChatGPT Codex Responses.
//! The connection remains owned by a std.http.Client so TLS/proxy/certificate
//! behavior stays identical to the existing HTTP transport.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");

pub const Transport = enum {
    sse,
    websocket,
    websocket_cached,
    auto,

    pub fn parse(raw: []const u8) ?Transport {
        if (std.ascii.eqlIgnoreCase(raw, "sse")) return .sse;
        if (std.ascii.eqlIgnoreCase(raw, "websocket")) return .websocket;
        if (std.ascii.eqlIgnoreCase(raw, "websocket-cached") or std.ascii.eqlIgnoreCase(raw, "websocket_cached")) return .websocket_cached;
        if (std.ascii.eqlIgnoreCase(raw, "auto")) return .auto;
        return null;
    }

    pub fn usesWebSocket(self: Transport) bool {
        return self != .sse;
    }

    pub fn usesCachedContext(self: Transport) bool {
        return self == .websocket_cached or self == .auto;
    }
};

pub const OPENAI_BETA = "responses_websockets=2026-02-06";
pub const DEFAULT_CONNECT_TIMEOUT_MS: u64 = 15_000;
pub const DEFAULT_IDLE_TIMEOUT_MS: u64 = 300_000;
pub const CACHE_TTL_MS: i64 = 5 * 60 * 1000;
pub const MAX_AGE_MS: i64 = 55 * 60 * 1000;

pub const Frame = struct {
    opcode: Opcode,
    data: []u8,

    pub fn deinit(self: *Frame, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
        self.* = undefined;
    }
};

pub const Opcode = enum(u4) {
    continuation = 0,
    text = 1,
    binary = 2,
    close = 8,
    ping = 9,
    pong = 10,
    _,
};

pub const Client = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Owns all proxy URI, host and authorization storage retained by `http`.
    /// It must outlive the HTTP client and therefore travels with a cached
    /// WebSocket connection.
    proxy_arena: std.heap.ArenaAllocator,
    http: std.http.Client,
    connection: *std.http.Client.Connection,
    created_ms: i64,
    last_used_ms: i64,

    pub fn connectWithTimeout(
        gpa: std.mem.Allocator,
        io: Io,
        https_url: []const u8,
        extra_headers: []const std.http.Header,
        timeout_ms: u64,
    ) !Client {
        return connectWithTimeoutAndAbortProxy(gpa, io, https_url, extra_headers, timeout_ms, null, .{});
    }

    /// Connect with both a hard deadline and cooperative caller cancellation.
    /// Cancellation is surfaced distinctly so higher layers do not mistake a
    /// user abort for a transport failure and poison future turns.
    pub fn connectWithTimeoutAndAbort(
        gpa: std.mem.Allocator,
        io: Io,
        https_url: []const u8,
        extra_headers: []const std.http.Header,
        timeout_ms: u64,
        abort_flag: ?*bool,
    ) !Client {
        return connectWithTimeoutAndAbortProxy(gpa, io, https_url, extra_headers, timeout_ms, abort_flag, .{});
    }

    /// Proxy-aware form used by the Responses client. The proxy configuration
    /// is copied into the connection task and all parsed proxy state is then
    /// owned by the returned Client for the full cached WebSocket lifetime.
    pub fn connectWithTimeoutAndAbortProxy(
        gpa: std.mem.Allocator,
        io: Io,
        https_url: []const u8,
        extra_headers: []const std.http.Header,
        timeout_ms: u64,
        abort_flag: ?*bool,
        proxy_config: http_proxy.Config,
    ) !Client {
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.WebSocketAborted;
        if (timeout_ms == 0 and abort_flag == null) return connectWithProxy(gpa, io, https_url, extra_headers, proxy_config);
        const Race = union(enum) { connected: anyerror!Client, timeout: bool, aborted: bool };
        var queue: [3]Race = undefined;
        var select = Io.Select(Race).init(io, &queue);
        select.async(.connected, connectWithProxy, .{ gpa, io, https_url, extra_headers, proxy_config });
        if (timeout_ms > 0) select.async(.timeout, sleepMs, .{ io, timeout_ms });
        if (abort_flag) |flag| select.async(.aborted, watchAbort, .{ io, flag });
        const winner = try select.await();
        switch (winner) {
            .connected => |result| {
                drainConnectRace(&select);
                return result;
            },
            .timeout => |expired| {
                drainConnectRace(&select);
                if (expired) return error.WebSocketConnectTimeout;
                return error.Canceled;
            },
            .aborted => |aborted| {
                drainConnectRace(&select);
                if (aborted) return error.WebSocketAborted;
                return error.Canceled;
            },
        }
    }

    pub fn connect(
        gpa: std.mem.Allocator,
        io: Io,
        https_url: []const u8,
        extra_headers: []const std.http.Header,
    ) !Client {
        return connectWithProxy(gpa, io, https_url, extra_headers, .{});
    }

    pub fn connectWithProxy(
        gpa: std.mem.Allocator,
        io: Io,
        https_url: []const u8,
        extra_headers: []const std.http.Header,
        proxy_config: http_proxy.Config,
    ) !Client {
        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        errdefer proxy_arena.deinit();
        var http: std.http.Client = .{ .allocator = gpa, .io = io };
        errdefer http.deinit();
        _ = try http_proxy.configureClient(&http, proxy_arena.allocator(), https_url, proxy_config);

        const uri = try std.Uri.parse(https_url);
        var key_bytes: [16]u8 = undefined;
        io.random(&key_bytes);
        var key_buf: [std.base64.standard.Encoder.calcSize(key_bytes.len)]u8 = undefined;
        const key = std.base64.standard.Encoder.encode(&key_buf, &key_bytes);

        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try headers.appendSlice(gpa, extra_headers);
        try headers.append(gpa, .{ .name = "upgrade", .value = "websocket" });
        try headers.append(gpa, .{ .name = "sec-websocket-key", .value = key });
        try headers.append(gpa, .{ .name = "sec-websocket-version", .value = "13" });

        var req = try http.request(.GET, uri, .{
            .keep_alive = true,
            .redirect_behavior = .unhandled,
            .headers = .{ .connection = .{ .override = "Upgrade" }, .accept_encoding = .omit },
            .extra_headers = headers.items,
        });
        defer req.deinit();
        try req.sendBodiless();
        const response = try req.receiveHead(&.{});
        if (response.head.status != .switching_protocols) return error.WebSocketUpgradeRejected;
        const accept = findHeader(response.head.bytes, "sec-websocket-accept") orelse return error.WebSocketAcceptMissing;
        var expected: [28]u8 = undefined;
        expectedAccept(key, &expected);
        if (!std.mem.eql(u8, std.mem.trim(u8, accept, " \t"), &expected)) return error.WebSocketAcceptMismatch;

        const connection = req.connection orelse return error.WebSocketUpgradeRejected;
        // Steal the upgraded stream from Request. It stays in the owning
        // Client's used pool and is closed by http.deinit().
        req.connection = null;
        connection.closing = false;
        const now = Io.Clock.real.now(io).toMilliseconds();
        return .{
            .gpa = gpa,
            .io = io,
            .proxy_arena = proxy_arena,
            .http = http,
            .connection = connection,
            .created_ms = now,
            .last_used_ms = now,
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
        self.proxy_arena.deinit();
        self.* = undefined;
    }

    pub fn reusable(self: *const Client) bool {
        const now = Io.Clock.real.now(self.io).toMilliseconds();
        return now - self.last_used_ms <= CACHE_TTL_MS and now - self.created_ms <= MAX_AGE_MS and !self.connection.closing;
    }

    pub fn sendText(self: *Client, text: []const u8) !void {
        try writeClientFrame(self.io, self.connection.writer(), .text, text);
        try self.connection.flush();
        self.last_used_ms = Io.Clock.real.now(self.io).toMilliseconds();
    }

    pub fn readMessage(self: *Client, gpa: std.mem.Allocator) !Frame {
        while (true) {
            const first = try readFrame(gpa, self.connection.reader());
            self.last_used_ms = Io.Clock.real.now(self.io).toMilliseconds();
            switch (first.opcode) {
                .close => {
                    gpa.free(first.data);
                    return error.WebSocketClosed;
                },
                .ping => {
                    defer gpa.free(first.data);
                    try self.sendPong(first.data);
                    continue;
                },
                .pong => {
                    gpa.free(first.data);
                    continue;
                },
                .text, .binary => {},
                else => {
                    gpa.free(first.data);
                    return error.WebSocketUnexpectedOpcode;
                },
            }
            if (first.fin) return .{ .opcode = first.opcode, .data = first.data };

            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(gpa);
            try out.appendSlice(gpa, first.data);
            gpa.free(first.data);
            const message_opcode = first.opcode;
            while (true) {
                const next = try readFrame(gpa, self.connection.reader());
                self.last_used_ms = Io.Clock.real.now(self.io).toMilliseconds();
                if (next.opcode == .ping) {
                    defer gpa.free(next.data);
                    try self.sendPong(next.data);
                    continue;
                }
                if (next.opcode == .pong) {
                    gpa.free(next.data);
                    continue;
                }
                if (next.opcode == .close) {
                    gpa.free(next.data);
                    return error.WebSocketClosed;
                }
                if (next.opcode != .continuation) {
                    gpa.free(next.data);
                    return error.WebSocketUnexpectedOpcode;
                }
                defer gpa.free(next.data);
                try out.appendSlice(gpa, next.data);
                if (next.fin) break;
            }
            return .{ .opcode = message_opcode, .data = try out.toOwnedSlice(gpa) };
        }
    }

    pub fn readMessageWithTimeout(self: *Client, gpa: std.mem.Allocator, timeout_ms: u64) !Frame {
        return self.readMessageWithControl(gpa, timeout_ms, null);
    }

    /// Wait for one complete message, racing both an idle deadline and the
    /// caller's abort flag. Any late frame produced by the canceled read task
    /// is reclaimed before returning.
    pub fn readMessageWithControl(self: *Client, gpa: std.mem.Allocator, timeout_ms: u64, abort_flag: ?*bool) !Frame {
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.WebSocketAborted;
        if (timeout_ms == 0 and abort_flag == null) return self.readMessage(gpa);
        const Race = union(enum) { message: anyerror!Frame, timeout: bool, aborted: bool };
        var queue: [3]Race = undefined;
        var select = Io.Select(Race).init(self.io, &queue);
        select.async(.message, readMessageTask, .{ self, gpa });
        if (timeout_ms > 0) select.async(.timeout, sleepMs, .{ self.io, timeout_ms });
        if (abort_flag) |flag| select.async(.aborted, watchAbort, .{ self.io, flag });
        const winner = try select.await();
        switch (winner) {
            .message => |result| {
                drainReadRace(&select, gpa);
                return result;
            },
            .timeout => |expired| {
                drainReadRace(&select, gpa);
                if (expired) return error.WebSocketIdleTimeout;
                return error.Canceled;
            },
            .aborted => |aborted| {
                drainReadRace(&select, gpa);
                if (aborted) return error.WebSocketAborted;
                return error.Canceled;
            },
        }
    }

    fn sendPong(self: *Client, data: []const u8) !void {
        try writeClientFrame(self.io, self.connection.writer(), .pong, data);
        try self.connection.flush();
    }
};

fn sleepMs(io: Io, timeout_ms: u64) bool {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } };
    timeout.sleep(io) catch return false;
    return true;
}

fn readMessageTask(client: *Client, gpa: std.mem.Allocator) anyerror!Frame {
    return client.readMessage(gpa);
}

fn watchAbort(io: Io, flag: *bool) bool {
    while (!@atomicLoad(bool, flag, .acquire)) {
        if (!sleepMs(io, 25)) return false;
    }
    return true;
}

fn drainReadRace(select: anytype, gpa: std.mem.Allocator) void {
    while (select.cancel()) |pending| switch (pending) {
        .message => |result| {
            if (result) |frame_value| {
                var frame = frame_value;
                frame.deinit(gpa);
            } else |_| {}
        },
        .timeout, .aborted => {},
    };
}

fn drainConnectRace(select: anytype) void {
    while (select.cancel()) |pending| switch (pending) {
        .connected => |result| {
            if (result) |client_value| {
                var client = client_value;
                client.deinit();
            } else |_| {}
        },
        .timeout, .aborted => {},
    };
}

pub fn expectedAccept(key: []const u8, out: *[28]u8) void {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(key);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [std.crypto.hash.Sha1.digest_length]u8 = undefined;
    sha1.final(&digest);
    _ = std.base64.standard.Encoder.encode(out, &digest);
}

pub fn findHeader(head_bytes: []const u8, wanted: []const u8) ?[]const u8 {
    var it = std.mem.splitSequence(u8, head_bytes, "\r\n");
    _ = it.next();
    while (it.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), wanted)) continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

/// Client-to-server frames MUST be masked (RFC6455 section 5.3).
pub fn writeClientFrame(io: Io, w: *std.Io.Writer, opcode: Opcode, payload: []const u8) !void {
    try w.writeByte(0x80 | @as(u8, @intFromEnum(opcode)));
    if (payload.len <= 125) {
        try w.writeByte(0x80 | @as(u8, @intCast(payload.len)));
    } else if (payload.len <= std.math.maxInt(u16)) {
        try w.writeByte(0x80 | 126);
        try w.writeInt(u16, @intCast(payload.len), .big);
    } else {
        try w.writeByte(0x80 | 127);
        try w.writeInt(u64, @intCast(payload.len), .big);
    }
    var mask: [4]u8 = undefined;
    io.random(&mask);
    try w.writeAll(&mask);
    var scratch: [4096]u8 = undefined;
    var offset: usize = 0;
    while (offset < payload.len) {
        const n = @min(scratch.len, payload.len - offset);
        for (payload[offset .. offset + n], 0..) |byte, i| scratch[i] = byte ^ mask[(offset + i) & 3];
        try w.writeAll(scratch[0..n]);
        offset += n;
    }
}

fn readFrame(gpa: std.mem.Allocator, r: *std.Io.Reader) !struct { fin: bool, opcode: Opcode, data: []u8 } {
    const head = try r.takeArray(2);
    const fin = (head[0] & 0x80) != 0;
    if ((head[0] & 0x70) != 0) return error.WebSocketReservedBits;
    const opcode: Opcode = @enumFromInt(head[0] & 0x0f);
    // Server-to-client frames MUST NOT be masked.
    if ((head[1] & 0x80) != 0) return error.WebSocketServerFrameMasked;
    const len7 = head[1] & 0x7f;
    const len_u64: u64 = switch (len7) {
        126 => try r.takeInt(u16, .big),
        127 => try r.takeInt(u64, .big),
        else => len7,
    };
    const len = std.math.cast(usize, len_u64) orelse return error.WebSocketMessageTooLarge;
    if ((@intFromEnum(opcode) & 0x8) != 0 and (!fin or len > 125)) return error.WebSocketInvalidControlFrame;
    const data = try gpa.alloc(u8, len);
    errdefer gpa.free(data);
    try r.readSliceAll(data);
    return .{ .fin = fin, .opcode = opcode, .data = data };
}

pub fn readServerMessage(gpa: std.mem.Allocator, r: *std.Io.Reader) !Frame {
    const first = try readFrame(gpa, r);
    errdefer gpa.free(first.data);
    switch (first.opcode) {
        .close => return error.WebSocketClosed,
        .ping, .pong => return .{ .opcode = first.opcode, .data = first.data },
        .text, .binary => {},
        else => return error.WebSocketUnexpectedOpcode,
    }
    if (first.fin) return .{ .opcode = first.opcode, .data = first.data };

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, first.data);
    gpa.free(first.data);
    const opcode = first.opcode;
    while (true) {
        const next = try readFrame(gpa, r);
        defer gpa.free(next.data);
        if (next.opcode == .close) return error.WebSocketClosed;
        if (next.opcode == .ping or next.opcode == .pong) return error.WebSocketControlDuringFragment;
        if (next.opcode != .continuation) return error.WebSocketUnexpectedOpcode;
        try out.appendSlice(gpa, next.data);
        if (next.fin) break;
    }
    return .{ .opcode = opcode, .data = try out.toOwnedSlice(gpa) };
}

// Deterministic frame decoder test helpers use a fixed reader; client masking is
// intentionally not asserted byte-for-byte because masking randomness is required.
test "websocket accept matches RFC6455 vector" {
    var out: [28]u8 = undefined;
    expectedAccept("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &out);
}

test "websocket header lookup is case insensitive" {
    const raw = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: value\r\n\r\n";
    try std.testing.expectEqualStrings("value", findHeader(raw, "sec-websocket-accept").?);
}

test "transport parser supports cached websocket spelling" {
    try std.testing.expectEqual(Transport.websocket_cached, Transport.parse("websocket-cached").?);
    try std.testing.expect(Transport.auto.usesCachedContext());
    try std.testing.expect(!Transport.websocket.usesCachedContext());
}
