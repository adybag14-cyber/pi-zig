//! Joined native loopback callback listener with independently correlated states.
const std = @import("std");
const callback = @import("oauth_callback.zig");
const urls = @import("../extensions/url_parser.zig");
const params = @import("../extensions/url_search_params.zig");
pub const Options = struct { host: []const u8 = "127.0.0.1", redirect_host: ?[]const u8 = null, port: u16 = 0, path: []const u8 = "/callback", extra_paths: []const []const u8 = &.{}, timeout_ms: u64 = 300_000, max_connections: usize = 32 };
const Pending = struct { path: ?[]const u8, response: ?callback.Response = null, cause: ?anyerror = null };
pub const Server = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    arena: std.heap.ArenaAllocator,
    listener: std.Io.net.Server,
    redirect_uri: []const u8,
    paths: []const []const u8,
    timeout_ms: u64,
    max_connections: usize,
    closing: std.atomic.Value(bool) = .init(false),
    active_connections: std.atomic.Value(usize) = .init(0),
    mutex: std.Io.Mutex = .init,
    close_mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    waiters: usize = 0,
    pending: std.StringHashMapUnmanaged(*Pending) = .empty,
    future: ?std.Io.Future(anyerror!void) = null,
    handlers: std.Io.Group = .init,
    pub fn listen(gpa: std.mem.Allocator, io: std.Io, options: Options) !*Server {
        const self = try gpa.create(Server);
        errdefer gpa.destroy(self);
        const listen_host = std.mem.trim(u8, options.host, "[]");
        const address = if (std.mem.indexOfScalar(u8, listen_host, ':') != null) try std.Io.net.IpAddress.parseIp6(listen_host, options.port) else try std.Io.net.IpAddress.parseIp4(listen_host, options.port);
        var listener = try address.listen(io, .{ .reuse_address = true });
        errdefer listener.deinit(io);
        self.* = .{ .gpa = gpa, .io = io, .arena = .init(gpa), .listener = listener, .redirect_uri = undefined, .paths = undefined, .timeout_ms = options.timeout_ms, .max_connections = options.max_connections };
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        const redirect_host = std.mem.trim(u8, options.redirect_host orelse options.host, "[]");
        const ipv6 = std.mem.indexOfScalar(u8, redirect_host, ':') != null;
        self.redirect_uri = try std.fmt.allocPrint(a, "http://{s}{s}{s}:{d}{s}", .{ if (ipv6) "[" else "", redirect_host, if (ipv6) "]" else "", listener.socket.address.getPort(), options.path });
        const paths = try a.alloc([]const u8, options.extra_paths.len + 1);
        paths[0] = try a.dupe(u8, options.path);
        for (options.extra_paths, 1..) |path, index| paths[index] = try a.dupe(u8, path);
        self.paths = paths;
        self.future = try io.concurrent(serve, .{self});
        return self;
    }
    pub fn wait(self: *Server, state: []const u8, path: ?[]const u8, flag: ?*const bool) !callback.Response {
        var pending: Pending = .{ .path = path };
        try self.mutex.lock(self.io);
        if (self.closing.load(.acquire)) {
            self.mutex.unlock(self.io);
            return error.OAuthCallbackServerClosed;
        }
        if (self.pending.contains(state)) {
            self.mutex.unlock(self.io);
            return error.OAuthStateAlreadyPending;
        }
        self.pending.put(self.gpa, state, &pending) catch |cause| {
            self.mutex.unlock(self.io);
            return cause;
        };
        self.waiters += 1;
        self.mutex.unlock(self.io);
        defer {
            self.mutex.lockUncancelable(self.io);
            if (self.pending.get(state) == &pending) _ = self.pending.remove(state);
            self.waiters -= 1;
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
            if (pending.response) |*response| response.deinit(self.gpa);
        }
        const deadline = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, @intCast(@min(self.timeout_ms, std.math.maxInt(i64))));
        while (true) {
            self.mutex.lockUncancelable(self.io);
            if (pending.cause) |cause| {
                self.mutex.unlock(self.io);
                return cause;
            }
            if (pending.response) |result| {
                pending.response = null;
                self.mutex.unlock(self.io);
                return result;
            }
            self.mutex.unlock(self.io);
            if (flag) |aborted| if (@atomicLoad(bool, aborted, .acquire)) return error.McpSignInCancelled;
            if (std.Io.Clock.awake.now(self.io).toMilliseconds() >= deadline) return error.OAuthCallbackTimeout;
            try self.io.sleep(.fromMilliseconds(5), .awake);
        }
    }
    pub fn close(self: *Server) void {
        self.close_mutex.lockUncancelable(self.io);
        defer self.close_mutex.unlock(self.io);
        self.closing.store(true, .release);
        self.mutex.lockUncancelable(self.io);
        var iterator = self.pending.iterator();
        while (iterator.next()) |entry| entry.value_ptr.*.cause = error.OAuthCallbackServerClosed;
        self.mutex.unlock(self.io);
        if (self.future) |*future| {
            // A loopback wake retires accept normally. Zig 0.16's Windows AFD
            // cancellation can otherwise print INVALID_PARAMETER diagnostics.
            const wake: ?std.Io.net.Stream = self.listener.socket.address.connect(self.io, .{ .mode = .stream, .protocol = .tcp }) catch null;
            if (wake) |stream| {
                defer stream.close(self.io);
                future.await(self.io) catch {};
            } else future.cancel(self.io) catch {};
            self.future = null;
        }
        self.handlers.cancel(self.io);
        self.mutex.lockUncancelable(self.io);
        while (self.waiters != 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
    }
    pub fn deinit(self: *Server) void {
        self.close();
        self.listener.deinit(self.io);
        self.pending.deinit(self.gpa);
        self.arena.deinit();
        const gpa = self.gpa;
        gpa.destroy(self);
    }
    fn serve(self: *Server) anyerror!void {
        while (!self.closing.load(.acquire)) {
            const stream = try self.listener.accept(self.io);
            if (self.closing.load(.acquire)) {
                stream.close(self.io);
                return;
            }
            if (self.active_connections.fetchAdd(1, .acq_rel) >= self.max_connections) {
                _ = self.active_connections.fetchSub(1, .acq_rel);
                stream.close(self.io);
                continue;
            }
            self.handlers.concurrent(self.io, handle, .{ self, stream }) catch |cause| {
                _ = self.active_connections.fetchSub(1, .acq_rel);
                stream.close(self.io);
                return cause;
            };
        }
    }
    fn get(pairs: []const params.Pair, key: []const u8) ?[]const u8 {
        for (pairs) |pair| if (std.mem.eql(u8, pair.name, key)) return pair.value;
        return null;
    }
    fn handle(self: *Server, stream: std.Io.net.Stream) std.Io.Cancelable!void {
        defer stream.close(self.io);
        defer _ = self.active_connections.fetchSub(1, .acq_rel);
        self.respond(stream) catch |cause| {
            if (cause == error.Canceled) return error.Canceled;
        };
    }
    fn respond(self: *Server, stream: std.Io.net.Stream) !void {
        var read_buffer: [8192]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;
        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &write_buffer);
        var server = std.http.Server.init(&reader.interface, &writer.interface);
        var request = try server.receiveHead();
        var base = try urls.parse(self.gpa, self.redirect_uri, null);
        defer base.deinit(self.gpa);
        var url = try urls.parse(self.gpa, request.head.target, &base);
        defer url.deinit(self.gpa);
        const headers: []const std.http.Header = &.{.{ .name = "content-type", .value = "text/plain; charset=utf-8" }};
        var pairs = try params.parse(self.gpa, url.query orelse "");
        defer params.freePairs(self.gpa, &pairs);
        const packet = try self.correlate(url.path, pairs.items);
        defer if (packet.owned) self.gpa.free(packet.body);
        try request.respond(packet.body, .{ .status = packet.status, .keep_alive = false, .extra_headers = headers });
    }
    const Packet = struct { status: std.http.Status, body: []const u8, owned: bool = false };
    fn correlate(self: *Server, path: []const u8, pairs: []const params.Pair) !Packet {
        var known = false;
        for (self.paths) |route| if (std.mem.eql(u8, route, path)) {
            known = true;
        };
        if (!known) return .{ .status = .not_found, .body = "Not found" };
        const state = get(pairs, "state") orelse "";
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const pending = if (state.len != 0) self.pending.get(state) else null;
        if (pending == null) return .{ .status = .bad_request, .body = "Invalid or expired OAuth state" };
        _ = self.pending.remove(state);
        errdefer |cause| pending.?.cause = cause;
        if (pending.?.path) |expected| if (!std.mem.eql(u8, expected, path)) {
            pending.?.cause = error.OAuthCallbackUnexpectedRoute;
            return .{ .status = .bad_request, .body = "Unexpected redirect URI" };
        };
        if (get(pairs, "error")) |failure| if (failure.len != 0) {
            const detail = get(pairs, "error_description") orelse failure;
            const body = try std.fmt.allocPrint(self.gpa, "Authorization failed. You may close this window.\n\n{s}", .{detail});
            errdefer self.gpa.free(body);
            pending.?.response = .{ .rejection = try self.gpa.dupe(u8, detail) };
            return .{ .status = .ok, .body = body, .owned = true };
        };
        const code = get(pairs, "code") orelse "";
        if (code.len == 0) {
            pending.?.cause = error.OAuthCallbackCodeMissing;
            return .{ .status = .bad_request, .body = "Missing authorization code" };
        }
        var result: callback.Response = .{ .code = try self.gpa.dupe(u8, code) };
        errdefer result.deinit(self.gpa);
        result.state = try self.gpa.dupe(u8, state);
        if (get(pairs, "iss")) |issuer| {
            if (issuer.len != 0) result.issuer = try self.gpa.dupe(u8, issuer);
        }
        pending.?.response = result;
        return .{ .status = .ok, .body = "Authorization complete. You may close this window." };
    }
};
pub fn errorMessage(cause: anyerror) []const u8 {
    return switch (cause) {
        error.OAuthCallbackUnexpectedRoute => "The authorization response arrived on another redirect URI",
        error.OAuthCallbackServerClosed => "OAuth callback server closed",
        error.OAuthStateAlreadyPending => "OAuth state is already pending",
        error.OAuthCallbackTimeout => "OAuth callback timed out",
        error.OAuthCallbackCodeMissing => "OAuth callback did not include an authorization code",
        else => @errorName(cause),
    };
}

fn waitUntilRegistered(server: *Server, state: []const u8) !void {
    const end = std.Io.Clock.awake.now(server.io).toMilliseconds() + 2000;
    while (true) {
        server.mutex.lockUncancelable(server.io);
        const registered = server.pending.contains(state);
        server.mutex.unlock(server.io);
        if (registered) return;
        if (std.Io.Clock.awake.now(server.io).toMilliseconds() >= end) return error.CallbackRegistrationTimeout;
        try server.io.sleep(.fromMilliseconds(1), .awake);
    }
}
fn query(server: *Server, target: []const u8) !u16 {
    const gpa = server.gpa;
    const root = std.mem.lastIndexOfScalar(u8, server.redirect_uri, '/') orelse unreachable;
    const location = try std.fmt.allocPrint(gpa, "{s}{s}", .{ server.redirect_uri[0..root], target });
    defer gpa.free(location);
    var client: std.http.Client = .{ .allocator = gpa, .io = server.io };
    defer client.deinit();
    var body: std.Io.Writer.Allocating = .init(gpa);
    defer body.deinit();
    const reply = try @import("../ai/http_fetch.zig").fetchControlled(&client, .{ .location = .{ .url = location }, .response_writer = &body.writer, .keep_alive = false }, 2000, null);
    return reply.status;
}

test "mcp.runtime live OAuth callback states correlate independently and enforce exact callback route" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const json = @import("protocol.zig").json;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-live-callback-7fb.json"));
    defer original.deinit();
    const statuses = json.get(original.value, "statuses").?.array.items;
    const server = try Server.listen(gpa, io, .{ .extra_paths = &.{"/callback/server"}, .timeout_ms = 2000 });
    defer server.deinit();
    var first = try io.concurrent(Server.wait, .{ server, "one", "/callback", @as(?*const bool, null) });
    var first_joined = false;
    defer if (!first_joined) {
        if (first.cancel(io)) |response| {
            var result = response;
            result.deinit(gpa);
        } else |_| {}
    };
    var second = try io.concurrent(Server.wait, .{ server, "two", "/callback/server", @as(?*const bool, null) });
    var second_joined = false;
    defer if (!second_joined) {
        if (second.cancel(io)) |response| {
            var result = response;
            result.deinit(gpa);
        } else |_| {}
    };
    try waitUntilRegistered(server, "one");
    try waitUntilRegistered(server, "two");
    try std.testing.expectError(error.OAuthStateAlreadyPending, server.wait("one", null, null));
    try std.testing.expectEqual(@as(u16, @intCast(try json.asInteger(statuses[0]))), try query(server, "/unknown?state=one&code=c"));
    try std.testing.expectEqual(@as(u16, @intCast(try json.asInteger(statuses[1]))), try query(server, "/callback?state=other&code=c"));
    try std.testing.expectEqual(@as(u16, @intCast(try json.asInteger(statuses[2]))), try query(server, "/callback?state=two&code=wrong-route"));
    const wrong_route = second.await(io);
    second_joined = true;
    try std.testing.expectError(error.OAuthCallbackUnexpectedRoute, wrong_route);
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(json.get(original.value, "wrongRoute").?, "error"), errorMessage(error.OAuthCallbackUnexpectedRoute));
    try std.testing.expectEqual(@as(u16, @intCast(try json.asInteger(statuses[3]))), try query(server, "/callback?state=one&code=owned&iss=https%3A%2F%2Fissuer.example"));
    const delivered = first.await(io);
    first_joined = true;
    var response = try delivered;
    defer response.deinit(gpa);
    const expected = json.get(original.value, "response").?;
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "code"), response.code.?);
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "iss"), response.issuer.?);
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "state"), response.state.?);
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(original.value, "closed"), errorMessage(error.OAuthCallbackServerClosed));
    server.close();
    server.close();
    try std.testing.expectError(error.OAuthCallbackServerClosed, server.wait("new", null, null));
}

test "mcp.runtime OAuth listener closes pending callback and incomplete HTTP connection without detached work" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const server = try Server.listen(gpa, io, .{});
    defer server.deinit();
    var future = try io.concurrent(Server.wait, .{ server, "pending", "/callback", @as(?*const bool, null) });
    var joined = false;
    defer if (!joined) {
        if (future.cancel(io)) |response| {
            var result = response;
            result.deinit(gpa);
        } else |_| {}
    };
    try waitUntilRegistered(server, "pending");
    const incomplete = try server.listener.socket.address.connect(io, .{ .mode = .stream, .protocol = .tcp });
    defer incomplete.close(io);
    var buffer: [128]u8 = undefined;
    var writer = incomplete.writer(io, &buffer);
    try writer.interface.writeAll("GET /callback HTTP/1.1\r\n");
    try writer.interface.flush();
    const start = std.Io.Clock.awake.now(io).toMilliseconds();
    server.close();
    const result = future.await(io);
    joined = true;
    try std.testing.expectError(error.OAuthCallbackServerClosed, result);
    try std.testing.expectEqual(@as(usize, 0), server.active_connections.load(.acquire));
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - start < 1000);
}

test "mcp.runtime OAuth callback timeout and cancellation retire the pending state for reuse" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const server = try Server.listen(gpa, io, .{ .timeout_ms = 20 });
    defer server.deinit();
    try std.testing.expectError(error.OAuthCallbackTimeout, server.wait("reusable", null, null));
    var cancelled = true;
    try std.testing.expectError(error.McpSignInCancelled, server.wait("reusable", null, &cancelled));
    try std.testing.expectEqual(@as(usize, 0), server.pending.count());
    try std.testing.expectEqual(@as(usize, 0), server.waiters);
}

test "mcp.runtime OAuth callback constructor allocation failures close every prepared listener" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const server = try Server.listen(gpa, std.testing.io, .{ .extra_paths = &.{ "/callback/a", "/callback/b" } });
            defer server.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
