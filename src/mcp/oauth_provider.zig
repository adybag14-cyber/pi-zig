//! Connection token ownership. Rotation is joined and persisted before shutdown.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const store_mod = @import("oauth_store.zig");
const flow = @import("oauth_flow.zig");
const http = @import("oauth_http.zig");
pub const ResolveOptions = *const fn (?*anyopaque, json.Value) anyerror!flow.TokenOptions;
pub const Provider = struct {
    store: store_mod.Store,
    name: []const u8,
    server_url: []const u8,
    client: http.Client,
    options_context: ?*anyopaque,
    resolve_options: ResolveOptions,
    mutex: std.Io.Mutex = .init,
    closed: bool = false,

    pub fn settled(self: *Provider) void {
        self.mutex.lockUncancelable(self.store.io);
        self.mutex.unlock(self.store.io);
    }
    pub fn close(self: *Provider) void {
        self.mutex.lockUncancelable(self.store.io);
        defer self.mutex.unlock(self.store.io);
        self.closed = true;
    }
    pub fn token(self: *Provider) !?[]u8 {
        try self.mutex.lock(self.store.io);
        defer self.mutex.unlock(self.store.io);
        if (self.closed) return error.McpOAuthProviderClosed;
        var state = (try self.store.load(self.name, self.server_url, null)) orelse return null;
        defer state.deinit();
        const current = accessToken(state.value);
        const expiry = json.get(state.value, "tokensExpireAt");
        const expires_at: ?f64 = if (expiry) |value| switch (value) {
            .integer => @floatFromInt(value.integer),
            .float => value.float,
            else => null,
        } else null;
        const expired = if (expires_at) |value| value - 30_000 <= @as(f64, @floatFromInt(std.Io.Clock.real.now(self.store.io).toMilliseconds())) else false;
        if (!expired or refreshToken(state.value) == null) return if (current) |value| try self.store.gpa.dupe(u8, value) else null;
        self.refreshLocked(current) catch {};
        var latest = (try self.store.load(self.name, self.server_url, null)) orelse return null;
        defer latest.deinit();
        return if (accessToken(latest.value)) |value| try self.store.gpa.dupe(u8, value) else null;
    }
    pub fn unauthorized(self: *Provider, stale_token: ?[]const u8, insufficient_scope: bool) !void {
        if (insufficient_scope) return error.McpOAuthAuthorizationRequired;
        try self.mutex.lock(self.store.io);
        defer self.mutex.unlock(self.store.io);
        if (self.closed) return error.McpOAuthProviderClosed;
        try self.refreshLocked(stale_token);
    }
    fn refreshLocked(self: *Provider, stale_token: ?[]const u8) !void {
        const io = self.store.io;
        const lease = try self.store.refreshLease(self.name, self.server_url, null);
        defer lease.close(io);
        var state = (try self.store.load(self.name, self.server_url, null)) orelse return error.McpOAuthAuthorizationRequired;
        defer state.deinit();
        const current = accessToken(state.value);
        if (!equalOptional(current, stale_token)) return;
        const refresh_token = refreshToken(state.value) orelse return error.McpOAuthAuthorizationRequired;
        const options = try self.resolve_options(self.options_context, state.value);
        // Never discard a server's rotated credential due to caller cancellation.
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        var reply = try flow.refresh(self.client.rotationSafe(), options, refresh_token);
        defer reply.deinit();
        const a = state.arena.allocator();
        try state.value.object.put(a, "tokens", try json.clone(a, reply.value));
        if (json.get(reply.value, "expires_in")) |expiry| {
            const seconds: f64 = switch (expiry) {
                .integer => @floatFromInt(expiry.integer),
                .float => expiry.float,
                else => return error.InvalidOAuthTokenExpiry,
            };
            try state.value.object.put(a, "tokensExpireAt", .{ .float = @as(f64, @floatFromInt(std.Io.Clock.real.now(io).toMilliseconds())) + seconds * 1000 });
        } else _ = state.value.object.orderedRemove("tokensExpireAt");
        try self.store.save(self.name, self.server_url, state.value, null);
    }
};
fn equalOptional(a: ?[]const u8, b: ?[]const u8) bool {
    if (a) |value| return if (b) |other| std.mem.eql(u8, value, other) else false;
    return b == null;
}
fn accessToken(state: json.Value) ?[]const u8 {
    return tokenField(state, "access_token");
}
fn refreshToken(state: json.Value) ?[]const u8 {
    return tokenField(state, "refresh_token");
}
fn tokenField(state: json.Value, field: []const u8) ?[]const u8 {
    const tokens = json.get(state, "tokens") orelse return null;
    const value = json.get(tokens, field) orelse return null;
    return if (value == .string) value.string else null;
}

test "mcp.runtime OAuth connection refresh rereads cross-process tokens and preserves rotated credentials on caller abort" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-provider-rotation-7fb.json"));
    defer original.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try store_mod.Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    var initial = try json.Owned.parse(gpa, "{\"tokens\":{\"access_token\":\"old\",\"refresh_token\":\"refresh-old\"},\"tokensExpireAt\":0,\"clientInformation\":{\"client_id\":\"client\"}}");
    defer initial.deinit();
    try store.save("server", "https://service.example/mcp", initial.value, null);
    const fixture = @import("../ai/http_fixture.zig");
    const server = try fixture.PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"rotated\",\"refresh_token\":\"saved-refresh\",\"token_type\":\"Bearer\",\"expires_in\":3600}", .payload_contains = "refresh_token=refresh-old", .headers = &.{.{ .name = "content-type", .value = "application/json" }} }});
    defer server.deinit();
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    const Options = struct {
        endpoint: []const u8,
        calls: usize = 0,
        fn resolve(raw: ?*anyopaque, _: json.Value) !flow.TokenOptions {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .{ .endpoint = self.endpoint, .client_id = "client" };
        }
    };
    var options: Options = .{ .endpoint = endpoint };
    var caller_aborted = true;
    var provider: Provider = .{ .store = store, .name = "server", .server_url = "https://service.example/mcp", .client = .{ .gpa = gpa, .io = io, .abort_flag = &caller_aborted }, .options_context = &options, .resolve_options = Options.resolve };
    const token = (try provider.token()).?;
    defer gpa.free(token);
    try std.testing.expectEqualStrings(try protocol.text(original.value, "first"), token);
    try provider.unauthorized("old", false);
    try std.testing.expectEqual(@as(usize, @intCast(try json.asInteger(json.get(original.value, "settingsCalls").?))), options.calls);
    var persisted = (try store.load("server", "https://service.example/mcp", null)).?;
    defer persisted.deinit();
    try std.testing.expectEqualStrings(try protocol.text(original.value, "refreshToken"), refreshToken(persisted.value).?);
    try std.testing.expectEqualStrings(try protocol.text(original.value, "retainedClient"), try protocol.text(json.get(persisted.value, "clientInformation").?, "client_id"));
    try std.testing.expect(json.get(persisted.value, "tokensExpireAt").?.float > @as(f64, @floatFromInt(std.Io.Clock.real.now(io).toMilliseconds())));
    try std.testing.expectError(error.McpOAuthAuthorizationRequired, provider.unauthorized("rotated", true));
    provider.settled();
    provider.close();
    try std.testing.expectError(error.McpOAuthProviderClosed, provider.token());
    try server.finish();
}

test "mcp.runtime OAuth connection close waits for live rotation and saved refresh token" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try store_mod.Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    var initial = try json.Owned.parse(gpa, "{\"tokens\":{\"access_token\":\"old\",\"refresh_token\":\"old-refresh\"},\"tokensExpireAt\":0}");
    defer initial.deinit();
    try store.save("server", "https://service.example/mcp", initial.value, null);
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"rotated\",\"refresh_token\":\"saved-refresh\",\"token_type\":\"Bearer\"}", .request_observed = &observed, .response_release = &release }});
    defer server.deinit();
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    const Options = struct {
        endpoint: []const u8,
        fn resolve(raw: ?*anyopaque, _: json.Value) !flow.TokenOptions {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return .{ .endpoint = self.endpoint, .client_id = "client" };
        }
    };
    var options: Options = .{ .endpoint = endpoint };
    var aborted = false;
    var provider: Provider = .{ .store = store, .name = "server", .server_url = "https://service.example/mcp", .client = .{ .gpa = gpa, .io = io, .abort_flag = &aborted }, .options_context = &options, .resolve_options = Options.resolve };
    var worker = try io.concurrent(Provider.token, .{&provider});
    var worker_joined = false;
    defer if (!worker_joined) {
        release.set(io);
        if (worker.cancel(io)) |result| {
            if (result) |value| gpa.free(value);
        } else |_| {}
    };
    try observed.wait(io);
    @atomicStore(bool, &aborted, true, .release);
    const Close = struct {
        provider: *Provider,
        entered: std.Io.Event = .unset,
        done: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            self.entered.set(self.provider.store.io);
            self.provider.close();
            self.done.store(true, .release);
        }
    };
    var closer: Close = .{ .provider = &provider };
    var closing = try io.concurrent(Close.run, .{&closer});
    var close_joined = false;
    defer if (!close_joined) {
        release.set(io);
        closing.cancel(io);
    };
    try closer.entered.wait(io);
    try io.sleep(.fromMilliseconds(50), .awake);
    try std.testing.expect(!closer.done.load(.acquire));
    release.set(io);
    const result = try worker.await(io);
    worker_joined = true;
    defer if (result) |value| gpa.free(value);
    try std.testing.expectEqualStrings("rotated", result.?);
    closing.await(io);
    close_joined = true;
    var saved = (try store.load("server", "https://service.example/mcp", null)).?;
    defer saved.deinit();
    try std.testing.expectEqualStrings("saved-refresh", refreshToken(saved.value).?);
    try std.testing.expect(json.get(saved.value, "tokensExpireAt") == null);
    try std.testing.expectError(error.McpOAuthProviderClosed, provider.token());
    try server.finish();
}
