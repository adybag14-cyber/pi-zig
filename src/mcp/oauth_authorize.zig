//! Native discovery/client/PKCE/token transaction with source retry boundaries.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const Value = json.Value;
const urls = @import("../extensions/url_parser.zig");
const http = @import("oauth_http.zig");
const flow = @import("oauth_flow.zig");
const callback = @import("oauth_callback.zig");
const oauth = @import("oauth.zig");
const Store = @import("oauth_store.zig").Store;
pub const Options = struct {
    name: []const u8,
    server_url: []const u8,
    redirect_uri: []const u8,
    client_metadata: Value,
    client_id: ?[]const u8 = null,
    client_secret: ?[]const u8 = null,
    cimd: bool = false,
    scope: ?[]const u8 = null,
    resource_metadata_url: ?[]const u8 = null,
    authorization_metadata_url: ?[]const u8 = null,
    authorization_code: ?[]const u8 = null,
    response_issuer: ?[]const u8 = null,
    skip_refresh: bool = false,
    skip_issuer_validation: bool = false,
};
pub const Result = union(enum) {
    authorized,
    redirect: flow.Authorization,
    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        if (self.* == .redirect) self.redirect.deinit(gpa);
    }
};
fn text(value: Value, field: []const u8) ?[]const u8 {
    const item = json.get(value, field) orelse return null;
    return if (item == .string) item.string else null;
}
fn nonempty(value: ?[]const u8) ?[]const u8 {
    if (value) |item| if (item.len != 0) return item;
    return null;
}
fn put(state: *json.Owned, key: []const u8, value: Value) !void {
    const a = state.arena.allocator();
    try state.value.object.put(a, key, try json.clone(a, value));
}
fn save(store: Store, options: Options, state: *json.Owned) !void {
    try store.save(options.name, options.server_url, state.value, null);
}
pub fn authorize(client: http.Client, store: Store, options: Options) !Result {
    var failure: http.Failure = .{ .gpa = client.gpa };
    defer failure.deinit();
    var configured = client;
    configured.failure = &failure;
    return run(configured, store, options) catch |cause| {
        if (failure.kind != .token or failure.code == null) return cause;
        const code = failure.code.?;
        const all = std.mem.eql(u8, code, "invalid_client") or std.mem.eql(u8, code, "unauthorized_client");
        const tokens = std.mem.eql(u8, code, "invalid_grant");
        if (!all and !tokens) return cause;
        var state = (try store.load(options.name, options.server_url, null)) orelse return cause;
        defer state.deinit();
        _ = state.value.object.orderedRemove("tokens");
        _ = state.value.object.orderedRemove("tokensExpireAt");
        if (all) for ([_][]const u8{ "clientInformation", "codeVerifier", "discovery", "oauthState" }) |field| {
            _ = state.value.object.orderedRemove(field);
        };
        try save(store, options, &state);
        return run(configured, store, options);
    };
}
fn resource(gpa: std.mem.Allocator, server_url: []const u8, metadata: ?Value) !?[]u8 {
    const value = metadata orelse return null;
    const raw = try protocol.text(value, "resource");
    var requested = try urls.parse(gpa, server_url, null);
    defer requested.deinit(gpa);
    var configured = try urls.parse(gpa, raw, null);
    defer configured.deinit(gpa);
    const a = try urls.origin(gpa, requested);
    defer gpa.free(a);
    const b = try urls.origin(gpa, configured);
    defer gpa.free(b);
    const request_path = try std.fmt.allocPrint(gpa, "{s}{s}", .{ requested.path, if (std.mem.endsWith(u8, requested.path, "/")) "" else "/" });
    defer gpa.free(request_path);
    const prefix = try std.fmt.allocPrint(gpa, "{s}{s}", .{ configured.path, if (std.mem.endsWith(u8, configured.path, "/")) "" else "/" });
    defer gpa.free(prefix);
    if (!std.mem.eql(u8, a, b) or !std.mem.startsWith(u8, request_path, prefix)) return error.OAuthResourceMismatch;
    return try gpa.dupe(u8, raw);
}
fn scopeText(gpa: std.mem.Allocator, value: ?Value) !?[]u8 {
    const metadata = value orelse return null;
    const scopes = json.get(metadata, "scopes_supported") orelse return null;
    if (scopes != .array or scopes.array.items.len == 0) return null;
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    for (scopes.array.items, 0..) |scope, index| {
        if (index != 0) try result.append(gpa, ' ');
        try result.appendSlice(gpa, try json.asString(scope));
    }
    return try result.toOwnedSlice(gpa);
}
fn run(client: http.Client, store: Store, options: Options) !Result {
    const gpa = client.gpa;
    var state = if (try store.load(options.name, options.server_url, null)) |loaded| loaded else try json.Owned.parse(gpa, "{}");
    defer state.deinit();
    const a = state.arena.allocator();
    var protected: ?json.Owned = null;
    defer if (protected) |*value| value.deinit();
    var authorization: ?json.Owned = null;
    defer if (authorization) |*value| value.deinit();
    var issuer: []const u8 = undefined;
    var protected_value: ?Value = null;
    var metadata: ?Value = null;
    const cached = if (options.authorization_metadata_url == null) json.get(state.value, "discovery") else null;
    if (cached != null and nonempty(text(cached.?, "authorizationServerUrl")) != null) {
        issuer = text(cached.?, "authorizationServerUrl").?;
        protected_value = json.get(cached.?, "resourceMetadata");
        metadata = json.get(cached.?, "authorizationServerMetadata");
        if (metadata == null) {
            authorization = try client.authorizationMetadata(issuer, options.skip_issuer_validation);
            if (authorization) |value| metadata = value.value;
        }
    } else {
        protected = client.protectedMetadata(options.server_url, options.resource_metadata_url) catch |cause| switch (cause) {
            error.OAuthProtectedMetadataHttpError, error.InvalidOAuthProtectedMetadata, error.InvalidOAuthMetadataUrl, error.InvalidOAuthMetadataStrings, error.InvalidJSON => null,
            else => return cause,
        };
        if (protected) |value| protected_value = value.value;
        if (options.authorization_metadata_url) |location| {
            authorization = try client.authorizationDocument(location);
            metadata = authorization.?.value;
            issuer = try protocol.text(metadata.?, "issuer");
        } else {
            var parsed_server = try urls.parse(gpa, options.server_url, null);
            defer parsed_server.deinit(gpa);
            const origin = try urls.origin(gpa, parsed_server);
            defer gpa.free(origin);
            const fallback = try std.fmt.allocPrint(a, "{s}/", .{origin});
            issuer = fallback;
            if (protected_value) |value| if (json.get(value, "authorization_servers")) |servers| if (servers == .array and servers.array.items.len != 0) {
                issuer = try json.asString(servers.array.items[0]);
            };
            authorization = try client.authorizationMetadata(issuer, options.skip_issuer_validation);
            if (authorization) |value| metadata = value.value;
        }
    }
    if (options.authorization_metadata_url == null) {
        var discovery: Value = .{ .object = .empty };
        try discovery.object.put(a, "authorizationServerUrl", .{ .string = try a.dupe(u8, issuer) });
        if (metadata) |value| try discovery.object.put(a, "authorizationServerMetadata", try json.clone(a, value));
        if (protected_value) |value| try discovery.object.put(a, "resourceMetadata", try json.clone(a, value));
        if (options.resource_metadata_url) |location| try discovery.object.put(a, "resourceMetadataUrl", .{ .string = try a.dupe(u8, location) });
        try put(&state, "discovery", discovery);
        try save(store, options, &state);
    }
    const selected_resource = try resource(gpa, options.server_url, protected_value);
    defer if (selected_resource) |value| gpa.free(value);
    const discovered_scope = try scopeText(gpa, protected_value);
    defer if (discovered_scope) |value| gpa.free(value);
    const scope = nonempty(options.scope) orelse nonempty(discovered_scope) orelse nonempty(text(options.client_metadata, "scope"));
    var client_information: Value = if (json.get(state.value, "clientInformation")) |value| value else .null;
    if (nonempty(options.client_id)) |id| {
        client_information = .{ .object = .empty };
        try client_information.object.put(a, "client_id", .{ .string = try a.dupe(u8, id) });
        if (nonempty(options.client_secret)) |secret| try client_information.object.put(a, "client_secret", .{ .string = try a.dupe(u8, secret) });
    }
    var document: ?callback.ClientMetadata = null;
    defer if (document) |*value| value.deinit(gpa);
    if (client_information == .null and options.cimd) {
        document = try callback.clientMetadata(gpa, options.server_url, options.redirect_uri, metadata orelse return error.OAuthCimdUnsupported);
        client_information = .{ .object = .empty };
        try client_information.object.put(a, "client_id", .{ .string = try a.dupe(u8, document.?.url) });
    }
    if (client_information == .null) {
        if (nonempty(options.authorization_code) != null) return error.OAuthClientInformationMissing;
        var registered = try flow.register(client, issuer, metadata, options.client_metadata, scope);
        defer registered.deinit();
        try put(&state, "clientInformation", registered.value);
        try save(store, options, &state);
        client_information = json.get(state.value, "clientInformation").?;
    }
    const redirect_uri = if (document) |value| value.redirect_uri else options.redirect_uri;
    var methods: std.ArrayList([]const u8) = .empty;
    defer methods.deinit(gpa);
    if (metadata) |value| if (json.get(value, "token_endpoint_auth_methods_supported")) |supported| if (supported == .array) for (supported.array.items) |item| {
        try methods.append(gpa, try json.asString(item));
    };
    var fallback_issuer = try urls.parse(gpa, issuer, null);
    defer fallback_issuer.deinit(gpa);
    var fallback_token = try urls.parse(gpa, "/token", &fallback_issuer);
    defer fallback_token.deinit(gpa);
    const fallback_endpoint = try urls.serialize(gpa, fallback_token);
    defer gpa.free(fallback_endpoint);
    var token_options: flow.TokenOptions = .{ .endpoint = if (metadata) |value| try protocol.text(value, "token_endpoint") else fallback_endpoint, .client_id = try protocol.text(client_information, "client_id"), .client_secret = text(client_information, "client_secret"), .redirect_url = redirect_uri, .resource = selected_resource, .scope = scope, .supported_methods = methods.items, .preferred_method = text(client_information, "token_endpoint_auth_method") };
    if (nonempty(options.authorization_code)) |code| {
        if (metadata) |value| {
            const required = json.get(value, "authorization_response_iss_parameter_supported");
            try oauth.validateResponseIssuer(try protocol.text(value, "issuer"), options.response_issuer, required != null and required.? == .bool and required.?.bool);
        }
        const verifier = nonempty(text(state.value, "codeVerifier")) orelse return error.OAuthCodeVerifierMissing;
        var tokens = try flow.exchange(client, token_options, code, verifier);
        defer tokens.deinit();
        if (text(tokens.value, "scope") == null) if (scope) |value| try tokens.value.object.put(tokens.arena.allocator(), "scope", .{ .string = try tokens.arena.allocator().dupe(u8, value) });
        try persistTokens(store, options, &state, tokens.value);
        return .authorized;
    }
    if (!options.skip_refresh) if (json.get(state.value, "tokens")) |existing| if (nonempty(text(existing, "refresh_token"))) |refresh_token| {
        token_options.scope = text(existing, "scope");
        if (flow.refresh(client, token_options, refresh_token)) |value| {
            var tokens = value;
            defer tokens.deinit();
            try persistTokens(store, options, &state, tokens.value);
            return .authorized;
        } else |cause| {
            if (client.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.Canceled;
            if (cause == error.OAuthInsecureEndpoint or cause == error.OutOfMemory) return cause;
            if (client.failure) |failure| if (failure.code) |code| if (!std.mem.eql(u8, code, "server_error")) return cause;
        }
    };
    const random_state = if (nonempty(text(state.value, "oauthState"))) |value| value else blk: {
        var random: [32]u8 = undefined;
        try client.io.randomSecure(&random);
        const hex = std.fmt.bytesToHex(random, .lower);
        const value = try a.dupe(u8, &hex);
        try state.value.object.put(a, "oauthState", .{ .string = value });
        break :blk value;
    };
    var redirect = try flow.start(gpa, client.io, .{ .issuer = issuer, .metadata = metadata, .client_id = try protocol.text(client_information, "client_id"), .redirect_url = redirect_uri, .scope = scope, .state = random_state, .resource = selected_resource });
    errdefer redirect.deinit(gpa);
    try put(&state, "codeVerifier", .{ .string = redirect.verifier });
    try save(store, options, &state);
    return .{ .redirect = redirect };
}
fn persistTokens(store: Store, options: Options, state: *json.Owned, tokens: Value) !void {
    try put(state, "tokens", tokens);
    const a = state.arena.allocator();
    if (json.get(tokens, "expires_in")) |expiry| {
        const seconds: f64 = if (expiry == .float) expiry.float else @floatFromInt(try json.asInteger(expiry));
        try state.value.object.put(a, "tokensExpireAt", .{ .float = @as(f64, @floatFromInt(std.Io.Clock.real.now(store.io).toMilliseconds())) + seconds * 1000 });
    } else _ = state.value.object.orderedRemove("tokensExpireAt");
    try save(store, options, state);
}

fn cachedFixture(gpa: std.mem.Allocator, issuer: []const u8, token_endpoint: []const u8) !json.Owned {
    const bytes = try std.json.Stringify.valueAlloc(gpa, .{
        .clientInformation = .{ .client_id = "client", .redirect_uris = [_][]const u8{"http://127.0.0.1/callback"} },
        .discovery = .{
            .authorizationServerUrl = issuer,
            .authorizationServerMetadata = .{ .issuer = issuer, .authorization_endpoint = issuer, .token_endpoint = token_endpoint, .response_types_supported = [_][]const u8{"code"}, .code_challenge_methods_supported = [_][]const u8{"S256"}, .token_endpoint_auth_methods_supported = [_][]const u8{"none"}, .authorization_response_iss_parameter_supported = true },
            .resourceMetadata = .{ .resource = "https://service.example", .scopes_supported = [_][]const u8{"read"} },
        },
    }, .{});
    defer gpa.free(bytes);
    return json.Owned.parse(gpa, bytes);
}
test "mcp.runtime complete native authorization preserves PKCE and resource scope and validates issuer before exchange" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-authorize-7fb.json"));
    defer original.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"accepted\",\"token_type\":\"Bearer\"}", .payload_contains = "code_verifier=" }});
    defer server.deinit();
    const issuer = try server.url(gpa, "/authorize");
    defer gpa.free(issuer);
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    var state = try cachedFixture(gpa, issuer, endpoint);
    defer state.deinit();
    try put(&state, "oauthState", .{ .string = "fixed-state" });
    try store.save("server", "https://service.example/mcp", state.value, null);
    const client: http.Client = .{ .gpa = gpa, .io = io };
    var options: Options = .{ .name = "server", .server_url = "https://service.example/mcp", .redirect_uri = "http://127.0.0.1/callback", .client_metadata = .{ .object = .empty } };
    var redirect = try authorize(client, store, options);
    defer redirect.deinit(gpa);
    try std.testing.expect(redirect == .redirect);
    const expected_redirect = json.get(original.value, "redirect").?;
    try std.testing.expectEqual(@as(usize, @intCast(try json.asInteger(json.get(expected_redirect, "verifierLength").?))), redirect.redirect.verifier.len);
    var parsed_redirect = try urls.parse(gpa, redirect.redirect.url, null);
    defer parsed_redirect.deinit(gpa);
    var pairs = try @import("../extensions/url_search_params.zig").parse(gpa, parsed_redirect.query.?);
    defer @import("../extensions/url_search_params.zig").freePairs(gpa, &pairs);
    var expected_params = json.get(expected_redirect, "params").?.object.iterator();
    while (expected_params.next()) |entry| {
        var actual: ?[]const u8 = null;
        for (pairs.items) |pair| if (std.mem.eql(u8, pair.name, entry.key_ptr.*)) {
            actual = pair.value;
            break;
        };
        try std.testing.expectEqualStrings(try json.asString(entry.value_ptr.*), actual orelse return error.MissingAuthorizationParameter);
    }
    try std.testing.expect(std.mem.indexOf(u8, redirect.redirect.url, "scope=read") != null);
    try std.testing.expect(std.mem.indexOf(u8, redirect.redirect.url, "resource=https%3A%2F%2Fservice.example") != null);
    var prepared = (try store.load("server", options.server_url, null)).?;
    defer prepared.deinit();
    try std.testing.expectEqualStrings(redirect.redirect.verifier, try protocol.text(prepared.value, "codeVerifier"));
    options.authorization_code = "code-one";
    options.response_issuer = "https://other.example";
    try std.testing.expectError(error.OAuthIssuerMismatch, authorize(client, store, options));
    options.response_issuer = issuer;
    var authorized = try authorize(client, store, options);
    defer authorized.deinit(gpa);
    try std.testing.expect(authorized == .authorized);
    var saved = (try store.load("server", options.server_url, null)).?;
    defer saved.deinit();
    const tokens = json.get(saved.value, "tokens").?;
    try std.testing.expect(json.equal(json.get(json.get(original.value, "exchange").?, "tokens").?, tokens));
    try std.testing.expectEqualStrings("accepted", try protocol.text(tokens, "access_token"));
    try std.testing.expectEqualStrings("read", try protocol.text(tokens, "scope"));
    try std.testing.expect(json.get(saved.value, "tokensExpireAt") == null);
    try server.finish();
}

test "mcp.runtime invalid grant clears only tokens then creates browser authorization without a second stale refresh" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var original = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-authorize-7fb.json"));
    defer original.deinit();
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/token", .status = .bad_request, .body = "{\"error\":\"invalid_grant\"}", .payload_contains = "refresh_token=stale-refresh" }});
    defer server.deinit();
    const issuer = try server.url(gpa, "/authorize");
    defer gpa.free(issuer);
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    var state = try cachedFixture(gpa, issuer, endpoint);
    defer state.deinit();
    var tokens = try json.Owned.parse(gpa, "{\"access_token\":\"stale-access\",\"refresh_token\":\"stale-refresh\",\"scope\":\"old-scope\"}");
    defer tokens.deinit();
    try put(&state, "tokens", tokens.value);
    try state.value.object.put(state.arena.allocator(), "tokensExpireAt", .{ .integer = 1 });
    try store.save("server", "https://service.example/mcp", state.value, null);
    const options: Options = .{ .name = "server", .server_url = "https://service.example/mcp", .redirect_uri = "http://127.0.0.1/callback", .client_metadata = .{ .object = .empty } };
    var result = try authorize(.{ .gpa = gpa, .io = io }, store, options);
    defer result.deinit(gpa);
    try std.testing.expect(result == .redirect);
    var saved = (try store.load("server", options.server_url, null)).?;
    defer saved.deinit();
    try std.testing.expect(json.get(saved.value, "tokens") == null and json.get(saved.value, "tokensExpireAt") == null);
    try std.testing.expect(json.get(saved.value, "clientInformation") != null and json.get(saved.value, "discovery") != null);
    try server.finish();
    const expected = json.get(original.value, "invalidGrant").?;
    try std.testing.expectEqual(@as(usize, @intCast(try json.asInteger(json.get(expected, "staleRequests").?))), server.captured.items.len);
    try std.testing.expectEqualStrings(try protocol.text(expected, "retainedClient"), try protocol.text(json.get(saved.value, "clientInformation").?, "client_id"));
}

test "mcp.runtime sign-in cancellation during refresh never falls back to browser authorization" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    var store = try Store.init(gpa, io, buffer[0..count]);
    defer store.deinit();
    var observed: std.Io.Event = .unset;
    var release: std.Io.Event = .unset;
    const server = try @import("../ai/http_fixture.zig").PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"unused\",\"token_type\":\"Bearer\"}", .request_observed = &observed, .response_release = &release }});
    defer server.deinit();
    const issuer = try server.url(gpa, "/authorize");
    defer gpa.free(issuer);
    const endpoint = try server.url(gpa, "/token");
    defer gpa.free(endpoint);
    var state = try cachedFixture(gpa, issuer, endpoint);
    defer state.deinit();
    var tokens = try json.Owned.parse(gpa, "{\"access_token\":\"original\",\"refresh_token\":\"refresh\"}");
    defer tokens.deinit();
    try put(&state, "tokens", tokens.value);
    try store.save("server", "https://service.example/mcp", state.value, null);
    var aborted = false;
    const Work = struct {
        client: http.Client,
        store: Store,
        fn run(self: *@This()) !Result {
            return authorize(self.client, self.store, .{ .name = "server", .server_url = "https://service.example/mcp", .redirect_uri = "http://127.0.0.1/callback", .client_metadata = .{ .object = .empty } });
        }
    };
    var work: Work = .{ .client = .{ .gpa = gpa, .io = io, .abort_flag = &aborted }, .store = store };
    var future = try io.concurrent(Work.run, .{&work});
    var joined = false;
    defer if (!joined) {
        @atomicStore(bool, &aborted, true, .release);
        release.set(io);
        if (future.cancel(io)) |value| {
            var result = value;
            result.deinit(gpa);
        } else |_| {}
    };
    try observed.wait(io);
    @atomicStore(bool, &aborted, true, .release);
    const result = future.await(io);
    joined = true;
    try std.testing.expectError(error.Canceled, result);
    var saved = (try store.load("server", "https://service.example/mcp", null)).?;
    defer saved.deinit();
    try std.testing.expectEqualStrings("original", try protocol.text(json.get(saved.value, "tokens").?, "access_token"));
    try std.testing.expect(json.get(saved.value, "codeVerifier") == null and json.get(saved.value, "oauthState") == null);
    release.set(io);
}
