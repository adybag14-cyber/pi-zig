//! MCP OAuth structural contracts, issuer checks and step-up scope retention.
const std = @import("std");

pub const Tokens = struct {
    access_token: []const u8,
    token_type: []const u8,
    expires_in: ?f64 = null,
    scope: ?[]const u8 = null,
    refresh_token: ?[]const u8 = null,
    id_token: ?[]const u8 = null,
};

pub const OwnedTokens = struct {
    parsed: std.json.Parsed(std.json.Value),
    tokens: Tokens,
    pub fn deinit(self: *OwnedTokens) void {
        self.parsed.deinit();
        self.* = undefined;
    }
};

fn requiredString(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.MissingOAuthField;
    if (value != .string or value.string.len == 0) return error.InvalidOAuthString;
    return value.string;
}

fn optionalString(object: std.json.ObjectMap, name: []const u8) !?[]const u8 {
    const value = object.get(name) orelse return null;
    if (value == .null) return null;
    if (value != .string) return error.InvalidOAuthString;
    return if (value.string.len == 0) null else value.string;
}

pub fn parseTokens(gpa: std.mem.Allocator, source: []const u8) !OwnedTokens {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOAuthResponse;
    const object = parsed.value.object;
    var expires: ?f64 = null;
    if (object.get("expires_in")) |value| {
        expires = switch (value) {
            .null => null,
            .integer => |number| @floatFromInt(number),
            .float => |number| number,
            .string => |text| if (text.len == 0) null else std.fmt.parseFloat(f64, std.mem.trim(u8, text, " \t\r\n")) catch return error.InvalidOAuthExpiry,
            .bool => |boolean| if (boolean) 1 else 0,
            else => return error.InvalidOAuthExpiry,
        };
        if (expires) |number| if (!std.math.isFinite(number)) return error.InvalidOAuthExpiry;
    }
    return .{ .parsed = parsed, .tokens = .{
        .access_token = try requiredString(object, "access_token"),
        .token_type = try requiredString(object, "token_type"),
        .expires_in = expires,
        .scope = try optionalString(object, "scope"),
        .refresh_token = try optionalString(object, "refresh_token"),
        .id_token = try optionalString(object, "id_token"),
    } };
}

/// Validate RFC 9207 before any authorization code is sent for exchange.
pub fn validateResponseIssuer(expected: []const u8, received: ?[]const u8, issuer_required: bool) !void {
    if (received) |issuer| {
        if (!std.mem.eql(u8, expected, issuer)) return error.OAuthIssuerMismatch;
    } else if (issuer_required) return error.OAuthIssuerMismatch;
}

/// Discovery requires exact issuer identity after removing trailing slashes.
/// Explicitly configured metadata documents have a separate trusted boundary.
pub fn validateDiscoveryIssuer(expected: []const u8, received: []const u8) !void {
    if (!std.mem.eql(u8, std.mem.trimEnd(u8, expected, "/"), std.mem.trimEnd(u8, received, "/"))) return error.OAuthIssuerMismatch;
}

pub fn stepUpScope(gpa: std.mem.Allocator, granted: ?[]const u8, challenged: ?[]const u8) !?[]u8 {
    const next = challenged orelse return null;
    if (next.len == 0) return null;
    var scopes: std.StringHashMapUnmanaged(void) = .empty;
    defer scopes.deinit(gpa);
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    for ([_][]const u8{ granted orelse "", next }) |source| {
        var tokens = std.mem.tokenizeAny(u8, source, " \t\r\n\x0b\x0c");
        while (tokens.next()) |scope| {
            if (scopes.contains(scope)) continue;
            try scopes.put(gpa, scope, {});
            if (output.items.len > 0) try output.append(gpa, ' ');
            try output.appendSlice(gpa, scope);
        }
    }
    return try output.toOwnedSlice(gpa);
}

/// The caller supplies the canonical URL used by the connection. Matches Pi's
/// mcpNamespace(name) + "|" + URL.href key; legacy URL-only migration belongs
/// to the credential store, not this key constructor.
pub fn credentialKeyForNormalizedUrl(gpa: std.mem.Allocator, server_name: []const u8, normalized_url: []const u8) ![]u8 {
    const key = try std.fmt.allocPrint(gpa, "mcp__{s}|{s}", .{ server_name, normalized_url });
    for (key[5 .. 5 + server_name.len]) |*byte| if (byte.* == '-') {
        byte.* = '_';
    };
    return key;
}
/// MCP SEP-837/OIDC registration type from canonical WHATWG redirect hosts.
pub fn applicationType(gpa: std.mem.Allocator, redirect_uris: []const []const u8) ![]const u8 {
    const urls = @import("../extensions/url_parser.zig");
    for (redirect_uris) |text| {
        var url = urls.parse(gpa, text, null) catch |err| {
            if (err == error.OutOfMemory) return err;
            continue;
        };
        defer url.deinit(gpa);
        if (!std.mem.eql(u8, url.scheme, "http") and !std.mem.eql(u8, url.scheme, "https")) return "native";
        if (url.host) |host| if (std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "[::1]") or std.mem.eql(u8, host, "::1")) return "native";
    }
    return "web";
}
/// Preserve arbitrary client metadata and explicit types; scope overrides only
/// when nonempty, matching upstream's dynamic-registration request body.
pub fn registrationBody(gpa: std.mem.Allocator, client_metadata: []const u8, scope: ?[]const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, client_metadata, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOAuthClientMetadata;
    const arena = parsed.arena.allocator();
    const redirects = parsed.value.object.get("redirect_uris") orelse return error.InvalidOAuthClientMetadata;
    if (redirects != .array) return error.InvalidOAuthClientMetadata;
    var values: std.ArrayList([]const u8) = .empty;
    defer values.deinit(gpa);
    for (redirects.array.items) |value| {
        if (value != .string) return error.InvalidOAuthClientMetadata;
        try values.append(gpa, value.string);
    }
    const explicit = parsed.value.object.get("application_type");
    if (explicit == null or explicit.? == .null) try parsed.value.object.put(arena, "application_type", .{ .string = try applicationType(gpa, values.items) });
    if (scope) |text| if (text.len > 0) try parsed.value.object.put(arena, "scope", .{ .string = text });
    return std.json.Stringify.valueAlloc(gpa, parsed.value, .{});
}
test "MCP registration type follows canonical loopback custom schemes and explicit overrides" {
    const gpa = std.testing.allocator;
    for ([_][]const u8{ "http://127.0.0.1:32123/cb", "http://localhost:123/cb", "http://[::1]:123/cb", "http://[0:0:0:0:0:0:0:1]/cb", "http://2130706433/cb", "myapp:/oauth", "mailto:owner@example.org" }) |uri| try std.testing.expectEqualStrings("native", try applicationType(gpa, &.{uri}));
    try std.testing.expectEqualStrings("web", try applicationType(gpa, &.{ "https://example.com/cb", "not a URL" }));
    try std.testing.expectEqualStrings("native", try applicationType(gpa, &.{ "https://example.com/cb", "myapp:/oauth" }));
    const body = try registrationBody(gpa, "{\"redirect_uris\":[\"http://localhost/cb\"],\"application_type\":\"web\",\"client_name\":\"fixture\",\"custom\":{\"retained\":true}}", "openid");
    defer gpa.free(body);
    const decoded = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer decoded.deinit();
    try std.testing.expectEqualStrings("web", decoded.value.object.get("application_type").?.string);
    try std.testing.expectEqualStrings("openid", decoded.value.object.get("scope").?.string);
    try std.testing.expect(decoded.value.object.get("custom").?.object.get("retained").?.bool);
}
fn registrationAllocationCase(gpa: std.mem.Allocator) !void {
    const body = try registrationBody(gpa, "{\"redirect_uris\":[\"http://[::1]/cb\",\"myapp:/oauth\"],\"custom\":{\"retained\":true}}", "openid profile");
    defer gpa.free(body);
}
test "MCP registration body releases every allocation failure and retained arbitrary metadata" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, registrationAllocationCase, .{});
}

test "MCP OAuth empty and null optionals are absent rather than expired" {
    var tokens = try parseTokens(std.testing.allocator, "{\"access_token\":\"fixture\",\"token_type\":\"Bearer\",\"expires_in\":null,\"scope\":\"\",\"refresh_token\":null,\"id_token\":\"\"}");
    defer tokens.deinit();
    try std.testing.expect(tokens.tokens.expires_in == null);
    try std.testing.expect(tokens.tokens.scope == null);
    try std.testing.expect(tokens.tokens.refresh_token == null);
    try std.testing.expect(tokens.tokens.id_token == null);
    try std.testing.expectError(error.InvalidOAuthString, parseTokens(std.testing.allocator, "{\"access_token\":\"\",\"token_type\":\"Bearer\"}"));
}

test "MCP OAuth rejects foreign and required missing authorization response issuers" {
    try validateResponseIssuer("https://issuer.example", null, false);
    try validateResponseIssuer("https://issuer.example", "https://issuer.example", true);
    try std.testing.expectError(error.OAuthIssuerMismatch, validateResponseIssuer("https://issuer.example", "https://other.example", false));
    try std.testing.expectError(error.OAuthIssuerMismatch, validateResponseIssuer("https://issuer.example", null, true));
    try validateDiscoveryIssuer("https://issuer.example/", "https://issuer.example");
}

test "MCP OAuth step-up unions granted scopes and credentials separate same URL accounts" {
    const combined = (try stepUpScope(std.testing.allocator, "read write", "write profile")).?;
    defer std.testing.allocator.free(combined);
    try std.testing.expectEqualStrings("read write profile", combined);
    try std.testing.expect((try stepUpScope(std.testing.allocator, "read", null)) == null);
    const first = try credentialKeyForNormalizedUrl(std.testing.allocator, "first-account", "https://mcp.example/");
    defer std.testing.allocator.free(first);
    const second = try credentialKeyForNormalizedUrl(std.testing.allocator, "second", "https://mcp.example/");
    defer std.testing.allocator.free(second);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expectEqualStrings("mcp__first_account|https://mcp.example/", first);
}
