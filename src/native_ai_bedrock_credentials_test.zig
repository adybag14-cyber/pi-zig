const std = @import("std");
const credentials = @import("extensions/native_ai_aws_credentials.zig");
const types = @import("extensions/native_ai_aws_types.zig");
const cache = @import("extensions/native_ai_aws_cache.zig");
const fixture = @import("ai/http_fixture.zig");
const a = std.testing.allocator;
fn field(value: std.json.Value, key: []const u8) std.json.Value {
    return value.object.get(key) orelse .null;
}
fn text(value: std.json.Value, key: []const u8) []const u8 {
    return field(value, key).string;
}
fn replace(input: []const u8, before: []const u8, after: []const u8) ![]u8 {
    return std.mem.replaceOwned(u8, a, input, before, after);
}
fn decode64(value: []const u8) ![]u8 {
    const codec = std.base64.url_safe_no_pad.Decoder;
    const result = try a.alloc(u8, try codec.calcSizeForSlice(value));
    errdefer a.free(result);
    try codec.decode(result, value);
    return result;
}
fn checkDpop(expected: std.json.Value, actual: fixture.Captured, source_origin: []const u8, native_origin: []const u8) !void {
    const token = for (actual.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "dpop")) break header.value;
    } else return error.MissingActualDpopHeader;
    const first = std.mem.indexOfScalar(u8, token, '.') orelse return error.InvalidActualDpopHeader;
    const last = std.mem.lastIndexOfScalar(u8, token, '.').?;
    const header_bytes = try decode64(token[0..first]);
    defer a.free(header_bytes);
    var header = try std.json.parseFromSlice(std.json.Value, a, header_bytes, .{});
    defer header.deinit();
    const expected_header = field(field(expected, "dpop"), "header");
    const header_json = try std.json.Stringify.valueAlloc(a, expected_header, .{});
    defer a.free(header_json);
    try std.testing.expectEqualStrings(header_json, header_bytes);
    const payload_bytes = try decode64(token[first + 1 .. last]);
    defer a.free(payload_bytes);
    var payload = try std.json.parseFromSlice(std.json.Value, a, payload_bytes, .{});
    defer payload.deinit();
    const expected_payload = field(field(expected, "dpop"), "payload");
    try std.testing.expectEqualStrings(text(expected_payload, "htm"), text(payload.value, "htm"));
    const uri = try replace(text(expected_payload, "htu"), source_origin, native_origin);
    defer a.free(uri);
    try std.testing.expectEqualStrings(uri, text(payload.value, "htu"));
    try std.testing.expectEqual(field(expected_payload, "iat").integer, field(payload.value, "iat").integer);
    const uuid = text(payload.value, "jti");
    try std.testing.expectEqual(@as(usize, 36), uuid.len);
    try std.testing.expectEqual(@as(u8, '4'), uuid[14]);
    try std.testing.expect(std.mem.indexOfScalar(u8, "89ab", uuid[19]) != null);
    const jwk = field(expected_header, "jwk");
    const x = try decode64(text(jwk, "x"));
    defer a.free(x);
    const y = try decode64(text(jwk, "y"));
    defer a.free(y);
    try std.testing.expectEqual(@as(usize, 32), x.len);
    try std.testing.expectEqual(@as(usize, 32), y.len);
    var public: [65]u8 = undefined;
    public[0] = 4;
    @memcpy(public[1..33], x);
    @memcpy(public[33..65], y);
    const signature = try decode64(token[last + 1 ..]);
    defer a.free(signature);
    try std.testing.expectEqual(@as(usize, 64), signature.len);
    const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;
    try Ecdsa.Signature.fromBytes(signature[0..64].*).verify(token[0..last], try Ecdsa.PublicKey.fromSec1(&public));
}
fn project(result: *const types.Credentials) ![]u8 {
    const expiration = if (result.expiration_unix) |unix| try cache.iso(a, unix) else null;
    defer if (expiration) |owned| a.free(owned);
    var object: std.json.ObjectMap = .init(a);
    defer object.deinit();
    try object.put("accessKeyId", .{ .string = result.access_key_id });
    try object.put("secretAccessKey", .{ .string = result.secret_access_key });
    if (result.session_token) |value| try object.put("sessionToken", .{ .string = value });
    if (expiration) |value| try object.put("expiration", .{ .string = value });
    if (result.account_id) |value| try object.put("accountId", .{ .string = value });
    if (result.credential_scope) |value| try object.put("credentialScope", .{ .string = value });
    return std.json.Stringify.valueAlloc(a, std.json.Value{ .object = object }, .{});
}
fn bodyFor(kind: []const u8, path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "/federation/credentials")) return "{\"roleCredentials\":{\"accessKeyId\":\"FAKE_SSO_ACCESS\",\"secretAccessKey\":\"fake-sso-secret\",\"sessionToken\":\"fake-sso-session\",\"expiration\":1893459600000,\"accountId\":\"123456789012\"}}";
    if (std.mem.eql(u8, path, "/token")) return if (std.mem.eql(u8, kind, "sso_refresh_fallback")) "{\"error\":\"invalid_grant\",\"message\":\"fixture refresh rejected\"}" else "{\"accessToken\":\"fake-sso-refreshed\",\"refreshToken\":\"fake-refresh-2\",\"expiresIn\":3600,\"tokenType\":\"Bearer\"}";
    return if (std.mem.eql(u8, kind, "login_refresh_denied")) "{\"__type\":\"AccessDeniedException\",\"error\":\"TOKEN_EXPIRED\",\"message\":\"fixture denied\"}" else "{\"accessToken\":{\"accessKeyId\":\"FAKE_LOGIN_REFRESH_ACCESS\",\"secretAccessKey\":\"fake-login-refresh-secret\",\"sessionToken\":\"fake-login-refresh-session\"},\"refreshToken\":\"fake-login-refresh-2\",\"expiresIn\":3600}";
}
test "native AI Bedrock credentials compare21 actual Source25 results and typed errors using only owned fake files" {
    var source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock-credentials25-5ab.json"), .{});
    defer source.deinit();
    const rows = field(source.value, "rows").array.items;
    try std.testing.expectEqual(@as(usize, 25), rows.len);
    try std.testing.expectEqual(@as(usize, 0), field(source.value, "blocked").array.items.len);
    var compared: usize = 0;
    for (rows) |row| {
        const kind = text(row, "kind");
        if (std.mem.startsWith(u8, kind, "token_env") or std.mem.eql(u8, kind, "facade_empty_bearer_env") or std.mem.eql(u8, kind, "facade_absent_bearer_sigv4")) continue;
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        const home = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        defer a.free(home);
        const original_home = text(row, "home");
        for (field(row, "beforeOwnedFiles").array.items) |initial| {
            const destination = try replace(text(initial, "path"), original_home, home);
            defer a.free(destination);
            const contents = try replace(text(initial, "contents"), original_home, home);
            defer {
                @memset(contents, 0);
                a.free(contents);
            }
            if (std.fs.path.dirname(destination)) |parent| try std.Io.Dir.cwd().createDirPath(std.testing.io, parent);
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = destination, .data = contents });
        }
        var env: std.process.Environ.Map = .init(a);
        defer env.deinit();
        try env.put("HOME", home);
        try env.put("USERPROFILE", home);
        try env.put("AWS_EC2_METADATA_DISABLED", "true");
        const config = try std.fs.path.join(a, &.{ home, "config" });
        defer a.free(config);
        try env.put("AWS_CONFIG_FILE", config);
        const shared = try std.fs.path.join(a, &.{ home, "credentials" });
        defer a.free(shared);
        try env.put("AWS_SHARED_CREDENTIALS_FILE", shared);
        const login = try std.fs.path.join(a, &.{ home, "login-cache" });
        defer a.free(login);
        try env.put("AWS_LOGIN_CACHE_DIRECTORY", login);
        const requests = field(row, "requests").array.items;
        var plans: std.ArrayList(fixture.Reply) = .empty;
        defer plans.deinit(a);
        var expected_headers: std.ArrayList([]std.http.Header) = .empty;
        defer {
            for (expected_headers.items) |headers| a.free(headers);
            expected_headers.deinit(a);
        }
        for (requests) |request| {
            var headers: std.ArrayList(std.http.Header) = .empty;
            errdefer headers.deinit(a);
            var entries = field(request, "headers").object.iterator();
            while (entries.next()) |entry| {
                // Bind Host to the owned origin; capture and cryptographically
                // verify the actual wire DPoP instead of comparing randomness.
                if (std.mem.eql(u8, entry.key_ptr.*, "dpop")) continue;
                try headers.append(a, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
            }
            const owned = try headers.toOwnedSlice(a);
            try expected_headers.append(a, owned);
            const path = text(request, "path");
            try plans.append(a, .{ .path = path, .body = bodyFor(kind, path), .status = if (std.mem.eql(u8, kind, "sso_refresh_fallback") and std.mem.eql(u8, path, "/token")) .bad_request else if (std.mem.eql(u8, kind, "login_refresh_denied")) .forbidden else .ok, .expected_request_headers = owned, .capture_request_headers = true });
        }
        const server = if (requests.len != 0) try fixture.PlanServer.init(a, std.testing.io, plans.items) else null;
        defer if (server) |owned| owned.deinit();
        const endpoint = if (server) |owned| try owned.url(a, "") else try a.dupe(u8, "http://127.0.0.1:1");
        defer a.free(endpoint);
        for (expected_headers.items) |headers| for (headers) |*header| {
            if (std.ascii.eqlIgnoreCase(header.name, "host")) header.value = endpoint["http://".len..];
        };
        try env.put("AWS_ENDPOINT_URL_SSO", endpoint);
        try env.put("AWS_ENDPOINT_URL_SSO_OIDC", endpoint);
        try env.put("AWS_ENDPOINT_URL_SIGNIN", endpoint);
        const ambient_static = std.mem.eql(u8, kind, "facade_ambient_profile_static_override");
        if (std.mem.startsWith(u8, kind, "facade")) {
            try env.put("AWS_ACCESS_KEY_ID", "FAKE_SCOPED_ACCESS");
            try env.put("AWS_SECRET_ACCESS_KEY", "fake-scoped-secret");
            if (ambient_static) try env.put("AWS_PROFILE", "fixture");
        }
        var aborted = false;
        const start = std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        const budget = @import("extensions/native_ai_http_prepare.zig").Budget{ .io = std.testing.io, .abort_flag = &aborted, .deadline_ms = start + 10000 };
        const now = @divFloor(field(row, "now").integer, 1000);
        var result = if (std.mem.startsWith(u8, kind, "facade") or std.mem.eql(u8, kind, "default_missing")) try credentials.resolveResult(a, std.testing.io, &env, if (ambient_static) null else "fixture", "eu-west-2", now, budget) else try credentials.resolveIniResult(a, std.testing.io, &env, "fixture", "eu-west-2", now, budget);
        defer result.deinit(a);
        if (field(row, "error") != .null) {
            try std.testing.expect(result == .failure);
            const expected = field(row, "error");
            try std.testing.expectEqualStrings(text(expected, "name"), result.failure.name);
            // Bind only this fixture's owned home prefix. The original SDK
            // message and raw inspection remain immutable in Source25.
            const message = try replace(text(expected, "message"), original_home, home);
            defer a.free(message);
            try std.testing.expectEqualStrings(message, result.failure.message);
            const next = field(expected, "tryNextLink");
            try std.testing.expectEqual(if (next == .null) @as(?bool, null) else next.bool, result.failure.try_next_link);
        } else {
            try std.testing.expect(result == .credentials);
            const expected = if (field(row, "resolved") != .null) field(row, "resolved") else field(row, "result");
            const expected_json = try std.json.Stringify.valueAlloc(a, expected, .{});
            defer a.free(expected_json);
            const actual_json = try project(&result.credentials);
            defer {
                @memset(actual_json, 0);
                a.free(actual_json);
            }
            try std.testing.expectEqualStrings(expected_json, actual_json);
        }
        if (server) |owned| {
            try owned.finish();
            try std.testing.expectEqual(requests.len, owned.captured.items.len);
            for (requests, owned.captured.items) |expected, actual| {
                try std.testing.expectEqualStrings(text(expected, "method"), @tagName(actual.method));
                try std.testing.expectEqualStrings(text(expected, "path"), actual.path);
                if (field(expected, "dpop") != .null) try checkDpop(expected, actual, text(row, "endpoint"), endpoint);
                if (field(expected, "body") != .null) {
                    const body = try std.json.Stringify.valueAlloc(a, field(expected, "body"), .{});
                    defer a.free(body);
                    try std.testing.expectEqualStrings(body, actual.payload);
                } else try std.testing.expectEqual(@as(usize, 0), actual.payload.len);
            }
        }
        for (field(row, "cacheFiles").array.items) |expected| {
            const path = try replace(text(expected, "path"), original_home, home);
            defer a.free(path);
            const actual = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1024 * 1024));
            defer {
                @memset(actual, 0);
                a.free(actual);
            }
            try std.testing.expectEqualStrings(text(expected, "contents"), actual);
        }
        compared += 1;
    }
    try std.testing.expectEqual(@as(usize, 21), compared);
}
test "native AI Bedrock empty ambient bearer preparation preserves the genuine Source25 signer failure before HTTP" {
    var source = try std.json.parseFromSlice(std.json.Value, a, @embedFile("extensions/fixtures/ai-bedrock-credentials25-5ab.json"), .{});
    defer source.deinit();
    const row = for (field(source.value, "rows").array.items) |value| {
        if (std.mem.eql(u8, text(value, "kind"), "facade_empty_bearer_env")) break value;
    } else unreachable;
    var aborted = false;
    var prepared = try @import("extensions/native_ai_bedrock_auth.zig").prepare(a, .{ .method = .POST, .url = "http://127.0.0.1:1", .payload = "{}", .headers = &.{} }, "{\"env\":{},\"region\":\"eu-west-2\",\"baseUrl\":\"http://127.0.0.1:1\",\"modelId\":\"fixture\",\"sdkBearerSelected\":true,\"sdkBearerToken\":\"\"}", .{ .io = std.testing.io, .abort_flag = &aborted, .deadline_ms = null });
    defer prepared.deinit(a);
    try std.testing.expect(prepared.failure != null);
    try std.testing.expectEqualStrings(text(field(row, "result"), "errorMessage"), prepared.failure.?.message);
    try std.testing.expectEqualStrings("Error", prepared.failure.?.name);
    try std.testing.expectEqual(@as(?bool, null), prepared.failure.?.try_next_link);
}
