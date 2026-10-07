//! Native OAuth authorization-code/PKCE and form request construction.
const std = @import("std");
const protocol = @import("protocol.zig");
const json = protocol.json;
const urls = @import("../extensions/url_parser.zig");
const pkce = @import("../auth/pkce.zig");
const metadata_validation = @import("oauth_metadata.zig");
const search_params = @import("../extensions/url_search_params.zig");
const oauth_http = @import("oauth_http.zig");
pub const FormField = struct { name: []const u8, value: []const u8 };
pub const Authorization = struct {
    url: []u8,
    verifier: []u8,
    pub fn deinit(self: *Authorization, gpa: std.mem.Allocator) void {
        gpa.free(self.url);
        gpa.free(self.verifier);
    }
};
pub const Options = struct { issuer: []const u8, metadata: ?json.Value = null, client_id: []const u8, redirect_url: []const u8, scope: ?[]const u8 = null, state: ?[]const u8 = null, resource: ?[]const u8 = null };
pub const TokenOptions = struct {
    endpoint: []const u8,
    client_id: []const u8,
    client_secret: ?[]const u8 = null,
    redirect_url: ?[]const u8 = null,
    resource: ?[]const u8 = null,
    scope: ?[]const u8 = null,
    supported_methods: []const []const u8 = &.{},
    preferred_method: ?[]const u8 = null,
};
fn method(options: TokenOptions) []const u8 {
    if (options.preferred_method) |hint| if (std.mem.eql(u8, hint, "client_secret_basic") or std.mem.eql(u8, hint, "client_secret_post") or std.mem.eql(u8, hint, "none")) {
        if (options.supported_methods.len == 0) return hint;
        for (options.supported_methods) |supported| if (std.mem.eql(u8, hint, supported)) return hint;
    };
    if (options.supported_methods.len == 0) return if (options.client_secret != null) "client_secret_basic" else "none";
    if (options.client_secret != null) for ([_][]const u8{ "client_secret_basic", "client_secret_post" }) |candidate| for (options.supported_methods) |supported| if (std.mem.eql(u8, candidate, supported)) return candidate;
    for (options.supported_methods) |supported| if (std.mem.eql(u8, supported, "none")) return "none";
    return if (options.client_secret != null) "client_secret_post" else "none";
}
fn token(client: oauth_http.Client, options: TokenOptions, fields: *std.ArrayList(FormField)) !json.Owned {
    const selected = method(options);
    var configured = client;
    var authorization: ?[]u8 = null;
    defer if (authorization) |value| client.gpa.free(value);
    var headers: [1]std.http.Header = undefined;
    if (std.mem.eql(u8, selected, "client_secret_basic")) {
        const secret = options.client_secret orelse return error.OAuthClientSecretRequired;
        const credentials = try std.fmt.allocPrint(client.gpa, "{s}:{s}", .{ options.client_id, secret });
        defer client.gpa.free(credentials);
        const encoded = try client.gpa.alloc(u8, std.base64.standard.Encoder.calcSize(credentials.len));
        defer client.gpa.free(encoded);
        _ = std.base64.standard.Encoder.encode(encoded, credentials);
        authorization = try std.fmt.allocPrint(client.gpa, "Basic {s}", .{encoded});
        headers[0] = .{ .name = "authorization", .value = authorization.? };
        configured.request_headers = &headers;
    } else {
        try fields.append(client.gpa, .{ .name = "client_id", .value = options.client_id });
        if (std.mem.eql(u8, selected, "client_secret_post")) if (options.client_secret) |secret| try fields.append(client.gpa, .{ .name = "client_secret", .value = secret });
    }
    if (options.resource) |resource| try fields.append(client.gpa, .{ .name = "resource", .value = resource });
    const body = try form(client.gpa, fields.items);
    defer client.gpa.free(body);
    return configured.tokenRequest(options.endpoint, body);
}
pub fn refresh(client: oauth_http.Client, options: TokenOptions, refresh_token: []const u8) !json.Owned {
    var fields: std.ArrayList(FormField) = .empty;
    defer fields.deinit(client.gpa);
    try fields.appendSlice(client.gpa, &.{ .{ .name = "grant_type", .value = "refresh_token" }, .{ .name = "refresh_token", .value = refresh_token } });
    var result = try token(client, options, &fields);
    errdefer result.deinit();
    const a = result.arena.allocator();
    if (json.get(result.value, "refresh_token") == null) try result.value.object.put(a, "refresh_token", .{ .string = try a.dupe(u8, refresh_token) });
    if (json.get(result.value, "scope") == null) if (options.scope) |scope| if (scope.len != 0) try result.value.object.put(a, "scope", .{ .string = try a.dupe(u8, scope) });
    return result;
}
pub fn exchange(client: oauth_http.Client, options: TokenOptions, code: []const u8, verifier: []const u8) !json.Owned {
    var fields: std.ArrayList(FormField) = .empty;
    defer fields.deinit(client.gpa);
    try fields.appendSlice(client.gpa, &.{ .{ .name = "grant_type", .value = "authorization_code" }, .{ .name = "code", .value = code }, .{ .name = "code_verifier", .value = verifier }, .{ .name = "redirect_uri", .value = options.redirect_url orelse return error.OAuthRedirectRequired } });
    return token(client, options, &fields);
}
fn includes(value: json.Value, wanted: []const u8) bool {
    if (value != .array) return false;
    for (value.array.items) |item| if (item == .string and std.mem.eql(u8, item.string, wanted)) return true;
    return false;
}
fn encode(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    const hex = "0123456789ABCDEF";
    for (text) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '*' or byte == '-' or byte == '.' or byte == '_') try result.append(gpa, byte) else if (byte == ' ') try result.append(gpa, '+') else try result.appendSlice(gpa, &.{ '%', hex[byte >> 4], hex[byte & 15] });
    }
    return result.toOwnedSlice(gpa);
}
pub fn form(gpa: std.mem.Allocator, entries: []const FormField) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    for (entries, 0..) |entry, index| {
        const name = try encode(gpa, entry.name);
        defer gpa.free(name);
        const value = try encode(gpa, entry.value);
        defer gpa.free(value);
        if (index != 0) try output.writer.writeByte('&');
        try output.writer.print("{s}={s}", .{ name, value });
    }
    return output.toOwnedSlice();
}
pub fn start(gpa: std.mem.Allocator, io: std.Io, options: Options) !Authorization {
    if (options.metadata) |metadata| {
        if (!includes(json.get(metadata, "response_types_supported") orelse return error.InvalidOAuthResponseTypes, "code")) return error.OAuthAuthorizationCodeUnsupported;
        if (json.get(metadata, "code_challenge_methods_supported")) |methods| if (!includes(methods, "S256")) return error.OAuthPkceS256Unsupported;
    }
    var issuer = try urls.parse(gpa, options.issuer, null);
    defer issuer.deinit(gpa);
    const endpoint = if (options.metadata) |metadata| try gpa.dupe(u8, try protocol.text(metadata, "authorization_endpoint")) else blk: {
        var fallback = try urls.parse(gpa, "/authorize", &issuer);
        defer fallback.deinit(gpa);
        break :blk try urls.serialize(gpa, fallback);
    };
    defer gpa.free(endpoint);
    try metadata_validation.endpoint(gpa, endpoint);
    const pair = try pkce.generate(gpa, io);
    defer gpa.free(pair.challenge);
    errdefer gpa.free(pair.verifier);
    var fields: std.ArrayList(FormField) = .empty;
    defer fields.deinit(gpa);
    try fields.appendSlice(gpa, &.{ .{ .name = "response_type", .value = "code" }, .{ .name = "client_id", .value = options.client_id }, .{ .name = "code_challenge", .value = pair.challenge }, .{ .name = "code_challenge_method", .value = "S256" }, .{ .name = "redirect_uri", .value = options.redirect_url } });
    if (options.state) |state| if (state.len != 0) try fields.append(gpa, .{ .name = "state", .value = state });
    if (options.scope) |scope| if (scope.len != 0) {
        try fields.append(gpa, .{ .name = "scope", .value = scope });
        var tokens = std.mem.tokenizeAny(u8, scope, " \t\r\n\x0b\x0c");
        while (tokens.next()) |scope_token| if (std.mem.eql(u8, scope_token, "offline_access")) {
            try fields.append(gpa, .{ .name = "prompt", .value = "consent" });
            break;
        };
    };
    if (options.resource) |resource| if (resource.len != 0) try fields.append(gpa, .{ .name = "resource", .value = resource });
    var record = try urls.parse(gpa, endpoint, null);
    defer record.deinit(gpa);
    var pairs = try search_params.parse(gpa, record.query orelse "");
    defer search_params.freePairs(gpa, &pairs);
    for (fields.items) |field| {
        var first: ?usize = null;
        var index: usize = 0;
        while (index < pairs.items.len) {
            if (std.mem.eql(u8, pairs.items[index].name, field.name)) {
                if (first == null) {
                    first = index;
                    index += 1;
                } else {
                    const removed = pairs.orderedRemove(index);
                    gpa.free(removed.name);
                    gpa.free(removed.value);
                }
            } else index += 1;
        }
        const value = try gpa.dupe(u8, field.value);
        errdefer gpa.free(value);
        if (first) |selected_index| {
            gpa.free(pairs.items[selected_index].value);
            pairs.items[selected_index].value = value;
        } else {
            const name = try gpa.dupe(u8, field.name);
            errdefer gpa.free(name);
            try pairs.append(gpa, .{ .name = name, .value = value });
        }
    }
    const query = try search_params.serialize(gpa, pairs.items);
    if (record.query) |previous| gpa.free(previous);
    record.query = query;
    const authorization_url = try urls.serialize(gpa, record);
    return .{ .url = authorization_url, .verifier = pair.verifier };
}
test "mcp.runtime OAuth form uses source application form encoding and secure authorization defaults" {
    const gpa = std.testing.allocator;
    const encoded = try form(gpa, &.{.{ .name = "scope", .value = "read write/🌍" }});
    defer gpa.free(encoded);
    try std.testing.expectEqualStrings("scope=read+write%2F%F0%9F%8C%8D", encoded);
    var authorization = try start(gpa, std.testing.io, .{ .issuer = "https://issuer.example/tenant", .client_id = "client", .redirect_url = "http://127.0.0.1/callback", .scope = "offline_access read", .state = "owned" });
    defer authorization.deinit(gpa);
    try std.testing.expect(std.mem.startsWith(u8, authorization.url, "https://issuer.example/authorize?response_type=code"));
    try std.testing.expect(std.mem.indexOf(u8, authorization.url, "code_challenge_method=S256") != null and std.mem.indexOf(u8, authorization.url, "prompt=consent") != null);
    try std.testing.expect(authorization.verifier.len >= 43);
}

test "mcp.runtime OAuth authorization allocation failures release query PKCE and URL ownership" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var result = start(gpa, std.testing.io, .{ .issuer = "https://issuer.example/tenant", .client_id = "owned", .redirect_url = "http://127.0.0.1/callback", .scope = "offline_access read", .state = "owned-state" }) catch |cause| {
                var probe = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                if (cause == error.WriteFailed and gpa.vtable == probe.allocator().vtable) {
                    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(gpa.ptr));
                    if (failing.has_induced_failure) return error.OutOfMemory;
                }
                return cause;
            };
            defer result.deinit(gpa);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

test "mcp.runtime OAuth refresh negotiates source Basic and POST client auth and preserves rotated token scope" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const fixture = @import("../ai/http_fixture.zig");
    for ([_][]const u8{ "client_secret_basic", "client_secret_post" }) |selected| {
        const basic = std.mem.eql(u8, selected, "client_secret_basic");
        const expected_headers: []const std.http.Header = if (basic) &.{.{ .name = "authorization", .value = "Basic Y2xpZW50OnNlY3JldA==" }} else &.{};
        const server = try fixture.PlanServer.init(gpa, io, &.{.{ .path = "/token", .body = "{\"access_token\":\"new-access\",\"token_type\":\"Bearer\"}", .headers = &.{.{ .name = "content-type", .value = "application/json" }}, .expected_request_headers = expected_headers, .payload_contains = if (basic) "grant_type=refresh_token&refresh_token=old-refresh" else "client_id=client&client_secret=secret" }});
        defer server.deinit();
        const endpoint = try server.url(gpa, "/token");
        defer gpa.free(endpoint);
        var result = try refresh(.{ .gpa = gpa, .io = io }, .{ .endpoint = endpoint, .client_id = "client", .client_secret = "secret", .scope = "read write", .supported_methods = &.{selected} }, "old-refresh");
        defer result.deinit();
        try std.testing.expectEqualStrings("old-refresh", try protocol.text(result.value, "refresh_token"));
        try std.testing.expectEqualStrings("read write", try protocol.text(result.value, "scope"));
        try server.finish();
    }
}
