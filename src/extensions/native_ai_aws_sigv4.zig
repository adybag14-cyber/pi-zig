//! SigV4 canonicalization for finalized Converse HTTP requests and custom headers.
const std = @import("std");
const bedrock = @import("../ai/bedrock.zig");
pub const Result = struct {
    authorization: []u8,
    amz_date: [16]u8,
    payload_hash: [64]u8,
    pub fn deinit(self: *Result, a: std.mem.Allocator) void {
        a.free(self.authorization);
        self.* = undefined;
    }
};
fn unsigned(name: []const u8) bool {
    for ([_][]const u8{ "authorization", "cache-control", "connection", "expect", "from", "keep-alive", "max-forwards", "pragma", "referer", "te", "trailer", "transfer-encoding", "upgrade", "user-agent", "x-amzn-trace-id" }) |value| if (std.ascii.eqlIgnoreCase(name, value)) return true;
    return std.ascii.startsWithIgnoreCase(name, "proxy-") or std.ascii.startsWithIgnoreCase(name, "sec-");
}
fn normalize(a: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var whitespace = false;
    for (std.mem.trim(u8, value, " \t\r\n")) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            whitespace = true;
        } else {
            if (whitespace) try out.append(a, ' ');
            whitespace = false;
            try out.append(a, byte);
        }
    }
    return out.toOwnedSlice(a);
}
pub fn sign(a: std.mem.Allocator, method: []const u8, url: []const u8, payload: []const u8, headers: []const std.http.Header, credentials: bedrock.AwsCredentials, region: []const u8, now: i64) !Result {
    // The established signer supplies the AWS calendar encoding and payload hash.
    var base = try bedrock.signAwsRequest(a, method, url, payload, credentials, region, now);
    defer base.deinit(a);
    const scheme = std.mem.indexOf(u8, url, "://") orelse return error.InvalidBedrockUrl;
    const start = scheme + 3;
    const path_start = std.mem.indexOfScalarPos(u8, url, start, '/') orelse url.len;
    const authority = url[start..path_start];
    const path = if (path_start < url.len) url[path_start..] else "/";
    if (std.mem.indexOfAny(u8, path, "?#") != null) return error.UnsupportedAwsQueryString;
    var canonical: std.StringHashMap([]u8) = .init(a);
    defer {
        var entries = canonical.iterator();
        while (entries.next()) |entry| {
            a.free(entry.key_ptr.*);
            a.free(entry.value_ptr.*);
        }
        canonical.deinit();
    }
    for (headers) |header| {
        if (unsigned(header.name)) continue;
        const name = try std.ascii.allocLowerString(a, header.name);
        errdefer a.free(name);
        const value = try normalize(a, header.value);
        errdefer a.free(value);
        const old = try canonical.getOrPut(name);
        if (old.found_existing) {
            a.free(name);
            a.free(old.value_ptr.*);
        }
        old.value_ptr.* = value;
    }
    try put(a, &canonical, "host", authority);
    try put(a, &canonical, "x-amz-date", &base.amz_date);
    try put(a, &canonical, "x-amz-content-sha256", &base.payload_hash);
    if (credentials.session_token) |token| try put(a, &canonical, "x-amz-security-token", token);
    const names = try a.alloc([]const u8, canonical.count());
    defer a.free(names);
    var key_iterator = canonical.keyIterator();
    var n: usize = 0;
    while (key_iterator.next()) |key| : (n += 1) names[n] = key.*;
    std.mem.sort([]const u8, names, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    var canonical_headers: std.Io.Writer.Allocating = .init(a);
    defer canonical_headers.deinit();
    for (names) |name| try canonical_headers.writer.print("{s}:{s}\n", .{ name, canonical.get(name).? });
    const signed_names = try std.mem.join(a, ";", names);
    defer a.free(signed_names);
    // Smithy normalizes path segments and double-escapes non-unreserved bytes.
    var segments: std.ArrayList([]const u8) = .empty;
    defer segments.deinit(a);
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) continue;
        if (std.mem.eql(u8, part, "..")) {
            if (segments.items.len != 0) _ = segments.pop();
        } else try segments.append(a, part);
    }
    var canonical_path: std.Io.Writer.Allocating = .init(a);
    defer canonical_path.deinit();
    if (std.mem.startsWith(u8, path, "/")) try canonical_path.writer.writeByte('/');
    for (segments.items, 0..) |segment, i| {
        if (i != 0) try canonical_path.writer.writeByte('/');
        for (segment) |byte| if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "-_.~", byte) != null) {
            try canonical_path.writer.writeByte(byte);
        } else try canonical_path.writer.print("%{X:0>2}", .{byte});
    }
    if (segments.items.len != 0 and std.mem.endsWith(u8, path, "/")) try canonical_path.writer.writeByte('/');
    const request = try std.fmt.allocPrint(a, "{s}\n{s}\n\n{s}\n{s}\n{s}", .{ method, canonical_path.written(), canonical_headers.written(), signed_names, base.payload_hash });
    defer a.free(request);
    var request_digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(request, &request_digest, .{});
    const scope = try std.fmt.allocPrint(a, "{s}/{s}/bedrock/aws4_request", .{ base.amz_date[0..8], region });
    defer a.free(scope);
    const signing = try std.fmt.allocPrint(a, "AWS4-HMAC-SHA256\n{s}\n{s}\n{s}", .{ base.amz_date, scope, std.fmt.bytesToHex(request_digest, .lower) });
    defer a.free(signing);
    const secret = try std.fmt.allocPrint(a, "AWS4{s}", .{credentials.secret_access_key});
    defer {
        @memset(secret, 0);
        a.free(secret);
    }
    const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
    var date_key: [32]u8 = undefined;
    var region_key: [32]u8 = undefined;
    var service_key: [32]u8 = undefined;
    var signing_key: [32]u8 = undefined;
    var signature: [32]u8 = undefined;
    defer {
        @memset(&date_key, 0);
        @memset(&region_key, 0);
        @memset(&service_key, 0);
        @memset(&signing_key, 0);
    }
    Hmac.create(&date_key, base.amz_date[0..8], secret);
    Hmac.create(&region_key, region, &date_key);
    Hmac.create(&service_key, "bedrock", &region_key);
    Hmac.create(&signing_key, "aws4_request", &service_key);
    Hmac.create(&signature, signing, &signing_key);
    return .{ .authorization = try std.fmt.allocPrint(a, "AWS4-HMAC-SHA256 Credential={s}/{s}, SignedHeaders={s}, Signature={s}", .{ credentials.access_key_id, scope, signed_names, std.fmt.bytesToHex(signature, .lower) }), .amz_date = base.amz_date, .payload_hash = base.payload_hash };
}
fn put(a: std.mem.Allocator, map: *std.StringHashMap([]u8), name: []const u8, value: []const u8) !void {
    const owned_name = try a.dupe(u8, name);
    errdefer a.free(owned_name);
    const owned_value = try normalize(a, value);
    errdefer a.free(owned_value);
    const entry = try map.getOrPut(owned_name);
    if (entry.found_existing) {
        a.free(owned_name);
        a.free(entry.value_ptr.*);
    }
    entry.value_ptr.* = owned_value;
}
