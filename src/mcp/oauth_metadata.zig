//! OAuth metadata validation preserves unknown fields like the source parser.
const std = @import("std");
const json = @import("protocol.zig").json;
const url = @import("../extensions/url_parser.zig");
pub fn clientInformation(gpa: std.mem.Allocator, bytes: []const u8) !json.Owned {
    var parsed = try json.Owned.parse(gpa, bytes);
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOAuthClientInformation;
    const client_id = parsed.value.object.get("client_id") orelse return error.InvalidOAuthClientId;
    if (client_id != .string or client_id.string.len == 0) return error.InvalidOAuthClientId;
    if (parsed.value.object.get("client_secret")) |secret| {
        if (secret == .null or (secret == .string and secret.string.len == 0)) _ = parsed.value.object.orderedRemove("client_secret") else if (secret != .string) return error.InvalidOAuthClientSecret;
    }
    for ([_][]const u8{ "client_id_issued_at", "client_secret_expires_at" }) |name| if (parsed.value.object.get(name)) |value| {
        if (value != .float and value != .integer) _ = parsed.value.object.orderedRemove(name);
    };
    if (parsed.value.object.get("redirect_uris")) |redirects| {
        if (redirects == .null) {
            try parsed.value.object.put(parsed.arena.allocator(), "redirect_uris", .{ .array = .init(parsed.arena.allocator()) });
        } else {
            if (redirects != .array) return error.InvalidOAuthRedirectUris;
            for (redirects.array.items) |redirect| if (redirect != .string) return error.InvalidOAuthRedirectUris;
        }
    } else try parsed.value.object.put(parsed.arena.allocator(), "redirect_uris", .{ .array = .init(parsed.arena.allocator()) });
    return parsed;
}
pub fn clientInformationError(cause: anyerror) []const u8 {
    return switch (cause) {
        error.InvalidOAuthClientInformation => "Invalid OAuth client registration response",
        error.InvalidOAuthClientId => "Invalid client_id",
        error.InvalidOAuthClientSecret => "Invalid client_secret",
        error.InvalidOAuthRedirectUris => "Invalid redirect_uris",
        else => @errorName(cause),
    };
}

test "mcp.runtime OAuth client registration parser retains actual original normalization and errors" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-registration-7fb.json"));
    defer fixture.deinit();
    for (json.get(fixture.value, "information").?.array.items) |row| {
        const input = try json.stringify(gpa, json.get(row, "input").?);
        defer gpa.free(input);
        var result = clientInformation(gpa, input) catch |cause| {
            try std.testing.expectEqualStrings(try json.asString(json.get(row, "error").?), clientInformationError(cause));
            continue;
        };
        defer result.deinit();
        try std.testing.expect(json.equal(json.get(row, "result").?, result.value));
    }
}
pub fn endpoint(gpa: std.mem.Allocator, text: []const u8) !void {
    var parsed = try url.parse(gpa, text, null);
    defer parsed.deinit(gpa);
    const host = parsed.host orelse "";
    const loopback = std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "[::1]");
    if (!std.mem.eql(u8, parsed.scheme, "https") and !loopback) return error.OAuthInsecureEndpoint;
}
fn safe(gpa: std.mem.Allocator, value: json.Value) !void {
    const text = try json.asString(value);
    if (text.len == 0) return error.InvalidOAuthMetadataUrl;
    var parsed = url.parse(gpa, text, null) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return error.InvalidOAuthMetadataUrl;
    };
    defer parsed.deinit(gpa);
    for ([_][]const u8{ "javascript", "data", "vbscript" }) |scheme| if (std.mem.eql(u8, parsed.scheme, scheme)) return error.InvalidOAuthMetadataUrl;
}
fn optionalUrls(gpa: std.mem.Allocator, object: *std.json.ObjectMap, names: []const []const u8) !void {
    for (names) |name| if (object.get(name)) |value| {
        if (value == .null or (value == .string and value.string.len == 0)) {
            _ = object.orderedRemove(name);
            continue;
        }
        try safe(gpa, value);
    };
}
fn optionalStrings(object: *std.json.ObjectMap, names: []const []const u8) !void {
    for (names) |name| if (object.get(name)) |value| {
        if (value == .null) {
            _ = object.orderedRemove(name);
            continue;
        }
        if (value != .array) return error.InvalidOAuthMetadataStrings;
        for (value.array.items) |item| if (item != .string) return error.InvalidOAuthMetadataStrings;
    };
}
pub fn protected(gpa: std.mem.Allocator, bytes: []const u8) !json.Owned {
    var parsed = try json.Owned.parse(gpa, bytes);
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOAuthProtectedMetadata;
    try safe(gpa, parsed.value.object.get("resource") orelse return error.InvalidOAuthProtectedMetadata);
    try optionalStrings(&parsed.value.object, &.{ "authorization_servers", "scopes_supported" });
    if (parsed.value.object.get("authorization_servers")) |servers| for (servers.array.items) |server| try safe(gpa, server);
    return parsed;
}
pub fn authorization(gpa: std.mem.Allocator, bytes: []const u8) !json.Owned {
    var parsed = try json.Owned.parse(gpa, bytes);
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOAuthAuthorizationMetadata;
    for ([_][]const u8{ "issuer", "authorization_endpoint", "token_endpoint" }) |name| try safe(gpa, parsed.value.object.get(name) orelse return error.InvalidOAuthAuthorizationMetadata);
    const responses = parsed.value.object.get("response_types_supported") orelse return error.InvalidOAuthResponseTypes;
    if (responses != .array) return error.InvalidOAuthResponseTypes;
    for (responses.array.items) |response| if (response != .string) return error.InvalidOAuthResponseTypes;
    try optionalUrls(gpa, &parsed.value.object, &.{"registration_endpoint"});
    try optionalStrings(&parsed.value.object, &.{ "scopes_supported", "grant_types_supported", "token_endpoint_auth_methods_supported", "code_challenge_methods_supported" });
    for ([_][]const u8{ "client_id_metadata_document_supported", "authorization_response_iss_parameter_supported" }) |name| if (parsed.value.object.get(name)) |value| if (value != .bool) {
        _ = parsed.value.object.orderedRemove(name);
    };
    return parsed;
}
test "mcp.runtime OAuth metadata retains extension fields omits source absent values and validates endpoints" {
    const gpa = std.testing.allocator;
    var result = try authorization(gpa, "{\"issuer\":\"https://issuer.example\",\"authorization_endpoint\":\"https://issuer.example/auth\",\"token_endpoint\":\"https://issuer.example/token\",\"response_types_supported\":[\"code\"],\"registration_endpoint\":null,\"grant_types_supported\":null,\"extra\":{\"retained\":true}}");
    defer result.deinit();
    try std.testing.expect(result.value.object.contains("extra"));
    try std.testing.expect(!result.value.object.contains("registration_endpoint") and !result.value.object.contains("grant_types_supported"));
    try endpoint(gpa, "https://issuer.example/token");
    try endpoint(gpa, "http://127.0.0.1:32123/token");
    try std.testing.expectError(error.OAuthInsecureEndpoint, endpoint(gpa, "http://issuer.example/token"));
    try std.testing.expectError(error.InvalidOAuthMetadataUrl, protected(gpa, "{\"resource\":\"javascript:alert(1)\"}"));
}

test "mcp.runtime OAuth metadata parser replays actual original provider metadata values" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-metadata-7fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |case| {
        const bytes = try json.stringify(gpa, case.object.get("input").?);
        defer gpa.free(bytes);
        var actual = if (std.mem.eql(u8, case.object.get("kind").?.string, "authorization")) try authorization(gpa, bytes) else try protected(gpa, bytes);
        defer actual.deinit();
        try std.testing.expect(json.equal(case.object.get("result").?, actual.value));
    }
}
