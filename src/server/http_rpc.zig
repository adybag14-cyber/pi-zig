//! Lightweight HTTP/TCP server wrapping the agent RPC protocol (pi server package surface).
//! `pi serve` listens on a TCP port; each connection reads an HTTP request (or raw JSON lines)
//! and responds with JSON-RPC envelopes from `handleRpcBody`.
//! Route matching uses **all** route_shard_* via routes_all.zig.
const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const routes_all = @import("routes_all.zig");

pub const ServerConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 3141,
    /// Bearer token; empty = no auth.
    auth_token: []const u8 = "",
};

pub const Server = struct {
    gpa: std.mem.Allocator,
    io: Io,
    config: ServerConfig,
    running: std.atomic.Value(bool) = .init(false),

    pub fn start(self: *Server) !void {
        self.running.store(true, .release);
    }

    pub fn stop(self: *Server) void {
        self.running.store(false, .release);
    }

    /// Blocking accept loop until `stop` (set from another thread) or listen failure.
    pub fn serveLoop(self: *Server) !void {
        try self.start();
        var addr = try net.IpAddress.parseIp4(self.config.host, self.config.port);
        addr.setPort(self.config.port);

        var listener = try addr.listen(self.io, .{
            .reuse_address = true,
        });
        defer listener.deinit(self.io);

        while (self.running.load(.acquire)) {
            var stream = listener.accept(self.io) catch |err| switch (err) {
                error.SocketNotListening => break,
                else => continue,
            };
            defer stream.close(self.io);
            self.handleConnection(&stream) catch {};
        }
    }

    fn handleConnection(self: *Server, stream: *net.Stream) !void {
        var rbuf: [8192]u8 = undefined;
        var reader = stream.reader(self.io, &rbuf);
        var req: std.ArrayList(u8) = .empty;
        defer req.deinit(self.gpa);

        while (req.items.len < 64 * 1024) {
            var tmp: [2048]u8 = undefined;
            const n = reader.interface.readSliceShort(tmp[0..]) catch break;
            if (n == 0) break;
            try req.appendSlice(self.gpa, tmp[0..n]);
            if (std.mem.indexOf(u8, req.items, "\r\n\r\n") != null or std.mem.indexOf(u8, req.items, "\n\n") != null) {
                break;
            }
            if (req.items.len > 0 and req.items[0] == '{') break;
        }

        if (self.config.auth_token.len > 0) {
            if (std.mem.indexOf(u8, req.items, self.config.auth_token) == null) {
                try writeHttp(self.io, stream, 401, "{\"error\":\"unauthorized\"}\n");
                return;
            }
        }

        const body = extractHttpBody(req.items);
        const resp_body = try self.handleRpcBody(if (body.len > 0) body else req.items);
        defer self.gpa.free(resp_body);
        try writeHttp(self.io, stream, 200, resp_body);
    }

    /// Handle one request body as RPC JSONL / HTTP; returns response body (caller frees).
    pub fn handleRpcBody(self: *Server, body: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        var it = std.mem.splitScalar(u8, body, '\n');
        while (it.next()) |line| {
            const t = std.mem.trim(u8, line, " \t\r");
            if (t.len == 0) continue;
            // HTTP request line → dispatch via **all** route shards
            if (std.mem.startsWith(u8, t, "POST ") or std.mem.startsWith(u8, t, "GET ")) {
                var parts = std.mem.tokenizeScalar(u8, t, ' ');
                const method = parts.next() orelse continue;
                const path = parts.next() orelse continue;
                if (routes_all.matchRoute(method, path)) |r| {
                    const resp = try std.fmt.allocPrint(self.gpa, "{{\"type\":\"response\",\"command\":\"{s}\",\"success\":true,\"data\":{{\"path\":\"{s}\",\"method\":\"{s}\",\"shard\":{d}}}}}\n", .{ r.name, r.path, r.method, r.shard });
                    defer self.gpa.free(resp);
                    try out.appendSlice(self.gpa, resp);
                    // Also run ext handlers when path is /ext/*
                    if (try routes_all.handleExt(self.gpa, path, body)) |handled| {
                        defer self.gpa.free(handled);
                        try out.appendSlice(self.gpa, handled);
                        try out.append(self.gpa, '\n');
                    }
                    continue;
                }
                continue;
            }
            if (std.mem.startsWith(u8, t, "HTTP/") or
                (std.mem.indexOf(u8, t, ": ") != null and t[0] != '{'))
                continue;
            if (std.mem.indexOf(u8, t, "\"ping\"") != null or std.mem.indexOf(u8, t, "\"type\":\"ping\"") != null) {
                try out.appendSlice(self.gpa, "{\"type\":\"response\",\"command\":\"ping\",\"success\":true,\"data\":\"pong\"}\n");
            } else if (std.mem.indexOf(u8, t, "get_commands") != null) {
                try out.appendSlice(self.gpa,
                    \\{"type":"response","command":"get_commands","success":true,"data":{"commands":["ping","prompt","abort","get_state","get_commands","list_routes"]}}
                );
                try out.append(self.gpa, '\n');
            } else if (std.mem.indexOf(u8, t, "get_state") != null) {
                try out.appendSlice(self.gpa,
                    \\{"type":"response","command":"get_state","success":true,"data":{"isStreaming":false,"messageCount":0}}
                );
                try out.append(self.gpa, '\n');
            } else if (std.mem.indexOf(u8, t, "list_routes") != null) {
                const routes_json = try routes_all.listAllRoutesJson(self.gpa);
                defer self.gpa.free(routes_json);
                const wrapped = try std.fmt.allocPrint(self.gpa, "{{\"type\":\"response\",\"command\":\"list_routes\",\"success\":true,\"data\":{s},\"routeCount\":{d}}}\n", .{ routes_json, routes_all.routeCount() });
                defer self.gpa.free(wrapped);
                try out.appendSlice(self.gpa, wrapped);
            } else {
                try out.appendSlice(self.gpa, "{\"type\":\"response\",\"command\":\"error\",\"success\":false,\"data\":{\"error\":\"attach full agent session via RPC mode or extend pi serve\"}}\n");
            }
        }
        if (out.items.len == 0) {
            try out.appendSlice(self.gpa, "{\"type\":\"response\",\"command\":\"ping\",\"success\":true,\"data\":\"pong\"}\n");
        }
        return try out.toOwnedSlice(self.gpa);
    }
};

fn writeHttp(io: Io, stream: *net.Stream, status: u16, body: []const u8) !void {
    var wbuf: [1024]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    const status_text: []const u8 = if (status == 200) "OK" else if (status == 401) "Unauthorized" else "Error";
    try writer.interface.print(
        "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, status_text, body.len },
    );
    try writer.interface.writeAll(body);
    try writer.interface.flush();
}

fn extractHttpBody(raw: []const u8) []const u8 {
    if (std.mem.indexOf(u8, raw, "\r\n\r\n")) |i| return raw[i + 4 ..];
    if (std.mem.indexOf(u8, raw, "\n\n")) |i| return raw[i + 2 ..];
    return raw;
}

test "server handleRpcBody ping" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    const out = try s.handleRpcBody("{\"type\":\"ping\"}\n");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "pong") != null);
}

test "server handleRpcBody get_commands" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    const out = try s.handleRpcBody("{\"type\":\"get_commands\"}\n");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "get_commands") != null);
}

test "server handleRpcBody list_routes uses ALL route shards" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    const out = try s.handleRpcBody("{\"type\":\"list_routes\"}\n");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "list_routes") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/health") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/ext/5/0") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "/ext/14/49") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"shard\":14") != null);
}

test "server handleRpcBody HTTP routes across shards" {
    const gpa = std.testing.allocator;
    var s = Server{ .gpa = gpa, .io = std.testing.io, .config = .{} };
    const out = try s.handleRpcBody("GET /health HTTP/1.1\n\n");
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "health") != null);

    const out5 = try s.handleRpcBody("POST /ext/5/3 HTTP/1.1\n\n{}");
    defer gpa.free(out5);
    try std.testing.expect(std.mem.indexOf(u8, out5, "ext_5_3") != null);
    try std.testing.expect(std.mem.indexOf(u8, out5, "\"shard\":5") != null);
}
