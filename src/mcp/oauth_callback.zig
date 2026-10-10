//! Native callback correlation and server-specific client metadata identities.
const std = @import("std");
const urls = @import("../extensions/url_parser.zig");
const params = @import("../extensions/url_search_params.zig");
const json = @import("protocol.zig").json;
pub const Response = struct {
    code: ?[]u8 = null,
    issuer: ?[]u8 = null,
    state: ?[]u8 = null,
    rejection: ?[]u8 = null,
    pub fn deinit(self: *Response, gpa: std.mem.Allocator) void {
        if (self.code) |value| gpa.free(value);
        if (self.issuer) |value| gpa.free(value);
        if (self.state) |value| gpa.free(value);
        if (self.rejection) |value| gpa.free(value);
    }
};
fn first(pairs: []const params.Pair, name: []const u8) ?[]const u8 {
    for (pairs) |pair| if (std.mem.eql(u8, pair.name, name)) return pair.value;
    return null;
}
pub fn parsePasted(gpa: std.mem.Allocator, input: []const u8, state: []const u8, redirect_uri: []const u8) !Response {
    var url = urls.parse(gpa, std.mem.trim(u8, input, " \t\r\n"), null) catch |cause| {
        if (cause == error.OutOfMemory) return cause;
        return error.ExpectedFullOAuthRedirectUrl;
    };
    defer url.deinit(gpa);
    var expected = try urls.parse(gpa, redirect_uri, null);
    defer expected.deinit(gpa);
    const origin = try urls.origin(gpa, url);
    defer gpa.free(origin);
    const expected_origin = try urls.origin(gpa, expected);
    defer gpa.free(expected_origin);
    if (!std.mem.eql(u8, origin, expected_origin) or !std.mem.eql(u8, url.path, expected.path)) return error.OAuthUnexpectedRedirectUri;
    var pairs = try params.parse(gpa, url.query orelse "");
    defer params.freePairs(gpa, &pairs);
    if (first(pairs.items, "error")) |failure| if (failure.len != 0) return .{ .rejection = try gpa.dupe(u8, first(pairs.items, "error_description") orelse failure) };
    const actual_state = first(pairs.items, "state") orelse return error.OAuthCallbackStateMismatch;
    if (!std.mem.eql(u8, actual_state, state)) return error.OAuthCallbackStateMismatch;
    const code = first(pairs.items, "code") orelse return error.OAuthCallbackCodeMissing;
    if (code.len == 0) return error.OAuthCallbackCodeMissing;
    var result: Response = .{ .code = try gpa.dupe(u8, code) };
    errdefer result.deinit(gpa);
    if (first(pairs.items, "iss")) |issuer| result.issuer = try gpa.dupe(u8, issuer);
    return result;
}
pub fn errorMessage(cause: anyerror) []const u8 {
    return switch (cause) {
        error.ExpectedFullOAuthRedirectUrl => "Expected the full redirect URL from the browser address bar",
        error.OAuthUnexpectedRedirectUri => "The redirect URL does not match this sign-in's redirect URI",
        error.OAuthCallbackStateMismatch => "The redirect URL belongs to a different sign-in",
        error.OAuthCallbackCodeMissing => "The redirect URL does not contain an authorization code",
        error.OAuthCimdUnsupported => "The authorization server does not support Client ID Metadata Documents for public clients; remove oauth.clientRegistration \"cimd\"",
        else => @errorName(cause),
    };
}
pub fn callbackId(gpa: std.mem.Allocator, server_url: []const u8) ![]u8 {
    var record = try urls.parse(gpa, server_url, null);
    defer record.deinit(gpa);
    if (record.fragment) |fragment| gpa.free(fragment);
    record.fragment = null;
    const normalized = try urls.serialize(gpa, record);
    defer gpa.free(normalized);
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(normalized, &hash, .{});
    const id = try gpa.alloc(u8, 12);
    _ = std.base64.url_safe_no_pad.Encoder.encode(id, hash[0..9]);
    return id;
}
pub const ClientMetadata = struct {
    url: []u8,
    redirect_uri: []u8,
    pub fn deinit(self: *ClientMetadata, gpa: std.mem.Allocator) void {
        gpa.free(self.url);
        gpa.free(self.redirect_uri);
    }
};
pub fn clientMetadata(gpa: std.mem.Allocator, server_url: []const u8, redirect_uri: []const u8, metadata: json.Value) !ClientMetadata {
    const supported = json.get(metadata, "client_id_metadata_document_supported") orelse return error.OAuthCimdUnsupported;
    if (supported != .bool or !supported.bool) return error.OAuthCimdUnsupported;
    const methods = json.get(metadata, "token_endpoint_auth_methods_supported") orelse return error.OAuthCimdUnsupported;
    var no_secret = false;
    if (methods == .array) for (methods.array.items) |method| {
        if (method == .string and std.mem.eql(u8, method.string, "none")) no_secret = true;
    };
    if (!no_secret) return error.OAuthCimdUnsupported;
    const issuer_response = json.get(metadata, "authorization_response_iss_parameter_supported");
    if (issuer_response != null and issuer_response.? == .bool and issuer_response.?.bool) {
        const url = try gpa.dupe(u8, "https://pi.dev/oauth/client.json");
        errdefer gpa.free(url);
        return .{ .url = url, .redirect_uri = try gpa.dupe(u8, redirect_uri) };
    }
    const id = try callbackId(gpa, server_url);
    defer gpa.free(id);
    var record = try urls.parse(gpa, redirect_uri, null);
    defer record.deinit(gpa);
    const path = try std.fmt.allocPrint(gpa, "/callback/{s}", .{id});
    gpa.free(record.path);
    record.path = path;
    const document = try std.fmt.allocPrint(gpa, "https://pi.dev/oauth/{s}/client.json", .{id});
    errdefer gpa.free(document);
    return .{ .url = document, .redirect_uri = try urls.serialize(gpa, record) };
}

test "mcp.runtime OAuth pasted callback separates exact URI state issuer and denial" {
    const gpa = std.testing.allocator;
    var result = try parsePasted(gpa, "http://localhost:1234/callback?code=first&code=second&state=owned&iss=https%3A%2F%2Fissuer.example", "owned", "http://localhost:1234/callback");
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("first", result.code.?);
    try std.testing.expectEqualStrings("https://issuer.example", result.issuer.?);
    try std.testing.expectError(error.OAuthUnexpectedRedirectUri, parsePasted(gpa, "http://127.0.0.1:1234/callback?state=owned&code=c", "owned", "http://localhost:1234/callback"));
    try std.testing.expectError(error.OAuthCallbackStateMismatch, parsePasted(gpa, "http://localhost:1234/callback?state=other&code=c", "owned", "http://localhost:1234/callback"));
    try std.testing.expectError(error.OAuthCallbackCodeMissing, parsePasted(gpa, "http://localhost:1234/callback?state=owned", "owned", "http://localhost:1234/callback"));
    var rejected = try parsePasted(gpa, "http://localhost:1234/callback?error=access_denied&error_description=cancelled", "owned", "http://localhost:1234/callback");
    defer rejected.deinit(gpa);
    try std.testing.expectEqualStrings("cancelled", rejected.rejection.?);
}

test "mcp.runtime OAuth server specific CIMD routes normalize URL and ignore fragment" {
    const gpa = std.testing.allocator;
    const first_id = try callbackId(gpa, "https://SERVICE.example:443/mcp#one");
    defer gpa.free(first_id);
    const same_id = try callbackId(gpa, "https://service.example/mcp#two");
    defer gpa.free(same_id);
    try std.testing.expectEqualStrings(first_id, same_id);
    var metadata = try json.Owned.parse(gpa, "{\"client_id_metadata_document_supported\":true,\"token_endpoint_auth_methods_supported\":[\"none\"]}");
    defer metadata.deinit();
    var result = try clientMetadata(gpa, "https://service.example/mcp", "http://localhost:1234/callback", metadata.value);
    defer result.deinit(gpa);
    try std.testing.expect(std.mem.startsWith(u8, result.redirect_uri, "http://localhost:1234/callback/"));
    try std.testing.expect(std.mem.indexOf(u8, result.url, first_id) != null);
}

test "mcp.runtime OAuth callback and CIMD replay actual original helper captures" {
    const gpa = std.testing.allocator;
    var capture = try json.Owned.parse(gpa, @embedFile("fixtures/oauth-callback-7fb.json"));
    defer capture.deinit();
    for (json.get(capture.value, "responses").?.array.items) |row| {
        const input = try @import("protocol.zig").text(row, "input");
        var result = parsePasted(gpa, input, "owned", "http://localhost:1234/callback") catch |cause| {
            try std.testing.expectEqualStrings(try @import("protocol.zig").text(row, "error"), errorMessage(cause));
            continue;
        };
        defer result.deinit(gpa);
        if (result.rejection) |message| {
            try std.testing.expectEqualStrings(try @import("protocol.zig").text(row, "error"), message);
        } else {
            const expected = json.get(row, "result").?;
            try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "code"), result.code.?);
            try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "iss"), result.issuer.?);
        }
    }
    const id = try callbackId(gpa, "https://SERVICE.example:443/mcp#one");
    defer gpa.free(id);
    try std.testing.expectEqualStrings(try @import("protocol.zig").text(capture.value, "callbackId"), id);
    for ([_]bool{ false, true }) |issuer| {
        var metadata = try json.Owned.parse(gpa, if (issuer) "{\"client_id_metadata_document_supported\":true,\"token_endpoint_auth_methods_supported\":[\"none\"],\"authorization_response_iss_parameter_supported\":true}" else "{\"client_id_metadata_document_supported\":true,\"token_endpoint_auth_methods_supported\":[\"none\"]}");
        defer metadata.deinit();
        var result = try clientMetadata(gpa, "https://service.example/mcp", "http://localhost:1234/callback", metadata.value);
        defer result.deinit(gpa);
        const expected = json.get(capture.value, if (issuer) "cimdIssuer" else "cimd").?;
        try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "url"), result.url);
        try std.testing.expectEqualStrings(try @import("protocol.zig").text(expected, "redirectUrl"), result.redirect_uri);
    }
}
