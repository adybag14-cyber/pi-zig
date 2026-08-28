//! Native Anthropic Claude Pro/Max OAuth protocol helpers.
const std = @import("std");
const builtin = @import("builtin");
const net = std.Io.net;
const pkce = @import("pkce.zig");
const storage = @import("storage.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

pub const CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
pub const AUTHORIZE_URL = "https://claude.ai/oauth/authorize";
pub const TOKEN_URL = "https://platform.claude.com/v1/oauth/token";
pub const CALLBACK_PORT: u16 = 53692;
pub const CALLBACK_PATH = "/callback";
pub const REDIRECT_URI = "http://localhost:53692/callback";
pub const SCOPES = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload";
pub const EXPIRY_SKEW_MS: i64 = 5 * 60 * 1000;

pub const AuthorizationFlow = struct {
    verifier: []u8,
    url: []u8,
    pub fn deinit(self: *AuthorizationFlow, gpa: std.mem.Allocator) void {
        gpa.free(self.verifier);
        gpa.free(self.url);
        self.* = undefined;
    }
};

pub const AuthorizationInput = struct {
    code: ?[]u8 = null,
    state: ?[]u8 = null,
    pub fn deinit(self: *AuthorizationInput, gpa: std.mem.Allocator) void {
        if (self.code) |v| gpa.free(v);
        if (self.state) |v| gpa.free(v);
        self.* = undefined;
    }
};

pub const Token = struct {
    access: []u8,
    refresh: []u8,
    expires_ms: i64,
    pub fn deinit(self: *Token, gpa: std.mem.Allocator) void {
        gpa.free(self.access);
        gpa.free(self.refresh);
        self.* = undefined;
    }
};

fn urlEncode(w: *std.Io.Writer, input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') try w.writeByte(c) else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

fn decodeQueryValue(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const buf = try gpa.dupe(u8, raw);
    errdefer gpa.free(buf);
    for (buf) |*c| if (c.* == '+') {
        c.* = ' ';
    };
    const decoded = std.Uri.percentDecodeInPlace(buf);
    if (decoded.ptr != buf.ptr) std.mem.copyForwards(u8, buf[0..decoded.len], decoded);
    return gpa.realloc(buf, decoded.len);
}

fn queryValue(gpa: std.mem.Allocator, query: []const u8, key: []const u8) !?[]u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const decoded_key = try decodeQueryValue(gpa, pair[0..eq]);
        defer gpa.free(decoded_key);
        if (!std.mem.eql(u8, decoded_key, key)) continue;
        return try decodeQueryValue(gpa, if (eq < pair.len) pair[eq + 1 ..] else "");
    }
    return null;
}

pub fn parseAuthorizationInput(gpa: std.mem.Allocator, input: []const u8) !AuthorizationInput {
    const value = std.mem.trim(u8, input, " \t\r\n");
    if (value.len == 0) return .{};
    if (std.mem.indexOfScalar(u8, value, '?')) |q| {
        const end = std.mem.indexOfScalarPos(u8, value, q + 1, '#') orelse value.len;
        const query = value[q + 1 .. end];
        return .{ .code = try queryValue(gpa, query, "code"), .state = try queryValue(gpa, query, "state") };
    }
    if (std.mem.indexOfScalar(u8, value, '#')) |hash| return .{
        .code = if (hash > 0) try gpa.dupe(u8, value[0..hash]) else null,
        .state = if (hash + 1 < value.len) try gpa.dupe(u8, value[hash + 1 ..]) else null,
    };
    if (std.mem.indexOf(u8, value, "code=") != null) return .{
        .code = try queryValue(gpa, value, "code"),
        .state = try queryValue(gpa, value, "state"),
    };
    return .{ .code = try gpa.dupe(u8, value) };
}

pub fn buildAuthorizationUrl(gpa: std.mem.Allocator, challenge: []const u8, verifier: []const u8) ![]u8 {
    if (challenge.len == 0 or verifier.len == 0) return error.InvalidAnthropicAuthorization;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(AUTHORIZE_URL ++ "?code=true&client_id=");
    try urlEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&response_type=code&redirect_uri=");
    try urlEncode(&out.writer, REDIRECT_URI);
    try out.writer.writeAll("&scope=");
    try urlEncode(&out.writer, SCOPES);
    try out.writer.writeAll("&code_challenge=");
    try urlEncode(&out.writer, challenge);
    try out.writer.writeAll("&code_challenge_method=S256&state=");
    try urlEncode(&out.writer, verifier);
    return out.toOwnedSlice();
}

pub fn createAuthorizationFlow(gpa: std.mem.Allocator, io: std.Io) !AuthorizationFlow {
    var pair = try pkce.generate(gpa, io);
    defer pair.deinit(gpa);
    return .{ .verifier = try gpa.dupe(u8, pair.verifier), .url = try buildAuthorizationUrl(gpa, pair.challenge, pair.verifier) };
}

fn writeJsonString(w: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, w);
}

pub fn buildAuthorizationCodeJson(gpa: std.mem.Allocator, code: []const u8, state: []const u8, verifier: []const u8, redirect_uri: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"grant_type\":\"authorization_code\",\"client_id\":");
    try writeJsonString(&out.writer, CLIENT_ID);
    try out.writer.writeAll(",\"code\":");
    try writeJsonString(&out.writer, code);
    try out.writer.writeAll(",\"state\":");
    try writeJsonString(&out.writer, state);
    try out.writer.writeAll(",\"redirect_uri\":");
    try writeJsonString(&out.writer, redirect_uri);
    try out.writer.writeAll(",\"code_verifier\":");
    try writeJsonString(&out.writer, verifier);
    try out.writer.writeByte('}');
    return out.toOwnedSlice();
}

pub fn buildRefreshJson(gpa: std.mem.Allocator, refresh_token: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"grant_type\":\"refresh_token\",\"client_id\":");
    try writeJsonString(&out.writer, CLIENT_ID);
    try out.writer.writeAll(",\"refresh_token\":");
    try writeJsonString(&out.writer, refresh_token);
    try out.writer.writeByte('}');
    return out.toOwnedSlice();
}

pub fn parseTokenResponse(gpa: std.mem.Allocator, body: []const u8, now_ms: i64) !Token {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidAnthropicOAuthToken;
    const access_v = parsed.value.object.get("access_token") orelse return error.InvalidAnthropicOAuthToken;
    const refresh_v = parsed.value.object.get("refresh_token") orelse return error.InvalidAnthropicOAuthToken;
    const expires_v = parsed.value.object.get("expires_in") orelse return error.InvalidAnthropicOAuthToken;
    if (access_v != .string or refresh_v != .string) return error.InvalidAnthropicOAuthToken;
    const seconds: i64 = switch (expires_v) {
        .integer => |v| v,
        .float => |v| @intFromFloat(v),
        else => return error.InvalidAnthropicOAuthToken,
    };
    if (seconds <= 0) return error.InvalidAnthropicOAuthToken;
    return .{
        .access = try gpa.dupe(u8, access_v.string),
        .refresh = try gpa.dupe(u8, refresh_v.string),
        .expires_ms = now_ms + seconds * 1000 - EXPIRY_SKEW_MS,
    };
}

fn postJsonWithOptions(gpa: std.mem.Allocator, io: std.Io, body: []const u8, options: bootstrap_http.Options) ![]u8 {
    var response = try bootstrap_http.request(gpa, io, .{
        .url = TOKEN_URL,
        .method = .POST,
        .payload = body,
        .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "accept", .value = "application/json" } },
        .options = options,
    });
    errdefer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.AnthropicOAuthHttpError;
    return response.body;
}

pub fn exchangeAuthorizationCodeWithOptions(gpa: std.mem.Allocator, io: std.Io, code: []const u8, state: []const u8, verifier: []const u8, redirect_uri: []const u8, options: bootstrap_http.Options) !Token {
    const request_body = try buildAuthorizationCodeJson(gpa, code, state, verifier, redirect_uri);
    defer gpa.free(request_body);
    const body = try postJsonWithOptions(gpa, io, request_body, options);
    defer gpa.free(body);
    return parseTokenResponse(gpa, body, std.Io.Clock.real.now(io).toMilliseconds());
}

pub fn exchangeAuthorizationCode(gpa: std.mem.Allocator, io: std.Io, code: []const u8, state: []const u8, verifier: []const u8, redirect_uri: []const u8) !Token {
    return exchangeAuthorizationCodeWithOptions(gpa, io, code, state, verifier, redirect_uri, .{});
}

pub fn refreshWithOptions(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8, options: bootstrap_http.Options) !Token {
    const request_body = try buildRefreshJson(gpa, refresh_token);
    defer gpa.free(request_body);
    const body = try postJsonWithOptions(gpa, io, request_body, options);
    defer gpa.free(body);
    return parseTokenResponse(gpa, body, std.Io.Clock.real.now(io).toMilliseconds());
}

pub fn refresh(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8) !Token {
    return refreshWithOptions(gpa, io, refresh_token, .{});
}

pub const CallbackResult = union(enum) {
    code: []u8,
    oauth_error: []u8,
    pub fn deinit(self: *CallbackResult, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .code => |v| gpa.free(v),
            .oauth_error => |v| gpa.free(v),
        }
        self.* = undefined;
    }
};

pub fn callbackHost(environ: ?*const std.process.Environ.Map) []const u8 {
    if (environ) |env| if (env.get("PI_OAUTH_CALLBACK_HOST")) |value| {
        const trimmed = std.mem.trim(u8, value, " \t\r\n");
        if (trimmed.len > 0) return trimmed;
    };
    return "127.0.0.1";
}

pub fn parseCallbackTarget(gpa: std.mem.Allocator, target: []const u8, expected_state: []const u8) !CallbackResult {
    const qmark = std.mem.indexOfScalar(u8, target, '?');
    const fragment = std.mem.indexOfScalar(u8, target, '#') orelse target.len;
    const path_end = if (qmark) |i| @min(i, fragment) else fragment;
    if (!std.mem.eql(u8, target[0..path_end], CALLBACK_PATH)) return error.AnthropicOAuthCallbackRouteNotFound;
    const query = if (qmark) |i| target[i + 1 .. fragment] else "";
    if (try queryValue(gpa, query, "error")) |oauth_error| {
        if (try queryValue(gpa, query, "error_description")) |description| {
            gpa.free(oauth_error);
            return .{ .oauth_error = description };
        }
        return .{ .oauth_error = oauth_error };
    }
    const state = try queryValue(gpa, query, "state") orelse return error.AnthropicOAuthStateMismatch;
    defer gpa.free(state);
    if (!std.mem.eql(u8, state, expected_state)) return error.AnthropicOAuthStateMismatch;
    const code = try queryValue(gpa, query, "code") orelse return error.AnthropicOAuthMissingAuthorizationCode;
    if (code.len == 0) {
        gpa.free(code);
        return error.AnthropicOAuthMissingAuthorizationCode;
    }
    return .{ .code = code };
}

fn callbackSleepMs(io: std.Io, timeout_ms: u64) bool {
    const duration_ms: i64 = @intCast(@min(timeout_ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(duration_ms), .clock = .real } };
    timeout.sleep(io) catch return false;
    return true;
}
fn callbackWatchAbort(io: std.Io, flag: *const bool) bool {
    while (!@atomicLoad(bool, flag, .acquire)) if (!callbackSleepMs(io, 25)) return false;
    return true;
}
fn acceptCallbackTask(listener: *net.Server, io: std.Io) anyerror!net.Stream {
    return listener.accept(io);
}
fn acceptCallback(listener: *net.Server, io: std.Io, abort_flag: ?*const bool) !net.Stream {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
    if (abort_flag == null) return listener.accept(io);
    const Race = union(enum) { accepted: anyerror!net.Stream, aborted: bool };
    var queue: [2]Race = undefined;
    var select = std.Io.Select(Race).init(io, &queue);
    select.async(.accepted, acceptCallbackTask, .{ listener, io });
    select.async(.aborted, callbackWatchAbort, .{ io, abort_flag.? });
    const winner = try select.await();
    switch (winner) {
        .accepted => |result| {
            while (select.cancel()) |_| {}
            return result;
        },
        .aborted => |aborted| {
            while (select.cancel()) |_| {}
            return if (aborted) error.LoginCancelled else error.Canceled;
        },
    }
}
fn callbackTargetFromRequest(raw: []const u8) ![]const u8 {
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
    const line = raw[0..line_end];
    if (!std.mem.startsWith(u8, line, "GET ")) return error.InvalidAnthropicOAuthCallbackRequest;
    const rest = line[4..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return error.InvalidAnthropicOAuthCallbackRequest;
    if (space == 0) return error.InvalidAnthropicOAuthCallbackRequest;
    return rest[0..space];
}
fn writeCallbackHttp(io: std.Io, stream: *net.Stream, status: u16, message: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "Bad Request",
    };
    const prefix = "<!doctype html><meta charset=utf-8><title>Anthropic OAuth</title><body><p>";
    const suffix = "</p></body>";
    var wbuf: [1024]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    try writer.interface.print("HTTP/1.1 {d} {s}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, status_text, prefix.len + message.len + suffix.len });
    try writer.interface.writeAll(prefix);
    try writer.interface.writeAll(message);
    try writer.interface.writeAll(suffix);
    try writer.interface.flush();
}

pub const CallbackServer = struct {
    io: std.Io,
    listener: net.Server,
    pub fn deinit(self: *CallbackServer) void {
        self.listener.deinit(self.io);
        self.* = undefined;
    }
    pub fn wait(self: *CallbackServer, gpa: std.mem.Allocator, expected_state: []const u8, abort_flag: ?*const bool) !CallbackResult {
        while (true) {
            var stream = try acceptCallback(&self.listener, self.io, abort_flag);
            defer stream.close(self.io);
            var raw: [8192]u8 = undefined;
            const deadline: std.Io.Timeout = .{ .deadline = .fromNow(self.io, .{ .raw = .fromSeconds(10), .clock = .awake }) };
            const message = stream.socket.receiveTimeout(self.io, &raw, deadline) catch {
                writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                continue;
            };
            const target = callbackTargetFromRequest(message.data) catch {
                writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                continue;
            };
            const result = parseCallbackTarget(gpa, target, expected_state) catch |err| switch (err) {
                error.AnthropicOAuthCallbackRouteNotFound => {
                    try writeCallbackHttp(self.io, &stream, 404, "Callback route not found.");
                    continue;
                },
                error.AnthropicOAuthStateMismatch => {
                    try writeCallbackHttp(self.io, &stream, 400, "State mismatch.");
                    continue;
                },
                error.AnthropicOAuthMissingAuthorizationCode => {
                    try writeCallbackHttp(self.io, &stream, 400, "Missing authorization code.");
                    continue;
                },
                else => return err,
            };
            switch (result) {
                .code => {
                    try writeCallbackHttp(self.io, &stream, 200, "Anthropic authentication completed. You can close this window.");
                    return result;
                },
                .oauth_error => {
                    try writeCallbackHttp(self.io, &stream, 400, result.oauth_error);
                    return result;
                },
            }
        }
    }
};

pub fn startCallbackServer(io: std.Io, host: []const u8) !CallbackServer {
    const normalized = if (std.ascii.eqlIgnoreCase(host, "localhost")) "127.0.0.1" else host;
    var addr = net.IpAddress.parse(normalized, CALLBACK_PORT) catch return error.InvalidAnthropicOAuthCallbackHost;
    addr.setPort(CALLBACK_PORT);
    return .{ .io = io, .listener = try addr.listen(io, .{ .reuse_address = true }) };
}

pub fn openBrowser(io: std.Io, url: []const u8) !void {
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .windows => &.{ "cmd.exe", "/d", "/c", "start", "", url },
        .macos => &.{ "open", url },
        else => &.{ "xdg-open", url },
    };
    var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    _ = try child.wait(io);
}

pub fn persistCredential(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, token: *const Token) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("anthropic", .{ .refresh = token.refresh, .access = token.access, .expires = token.expires_ms });
}

pub fn isOAuthAccessToken(value: []const u8) bool {
    return std.mem.indexOf(u8, value, "sk-ant-oat") != null;
}

test "Anthropic OAuth authorization URL uses verifier as state and exact scopes" {
    const gpa = std.testing.allocator;
    const url = try buildAuthorizationUrl(gpa, "challenge+slash/", "verifier-state");
    defer gpa.free(url);
    try std.testing.expect(std.mem.indexOf(u8, url, "https://claude.ai/oauth/authorize?") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A53692%2Fcallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge%2Bslash%2F") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=verifier-state") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "user%3Ainference") != null);
}

test "Anthropic OAuth manual authorization input accepts redirect code state and raw code" {
    const gpa = std.testing.allocator;
    var redirect = try parseAuthorizationInput(gpa, "http://localhost:53692/callback?code=c%2B1&state=s%2F1");
    defer redirect.deinit(gpa);
    try std.testing.expectEqualStrings("c+1", redirect.code.?);
    try std.testing.expectEqualStrings("s/1", redirect.state.?);
    var hash = try parseAuthorizationInput(gpa, "abc#state-x");
    defer hash.deinit(gpa);
    try std.testing.expectEqualStrings("abc", hash.code.?);
    try std.testing.expectEqualStrings("state-x", hash.state.?);
    var raw = try parseAuthorizationInput(gpa, " raw-code \n");
    defer raw.deinit(gpa);
    try std.testing.expectEqualStrings("raw-code", raw.code.?);
    try std.testing.expect(raw.state == null);
}

test "Anthropic OAuth exchange and refresh JSON omit refresh scope" {
    const gpa = std.testing.allocator;
    const exchange = try buildAuthorizationCodeJson(gpa, "code", "state", "verifier", REDIRECT_URI);
    defer gpa.free(exchange);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, exchange, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("authorization_code", parsed.value.object.get("grant_type").?.string);
    try std.testing.expectEqualStrings("state", parsed.value.object.get("state").?.string);
    const refresh_json = try buildRefreshJson(gpa, "refresh-token");
    defer gpa.free(refresh_json);
    var refresh_parsed = try std.json.parseFromSlice(std.json.Value, gpa, refresh_json, .{});
    defer refresh_parsed.deinit();
    try std.testing.expectEqualStrings("refresh_token", refresh_parsed.value.object.get("grant_type").?.string);
    try std.testing.expect(refresh_parsed.value.object.get("scope") == null);
}

test "Anthropic OAuth token parsing applies five minute expiry skew" {
    const gpa = std.testing.allocator;
    var token = try parseTokenResponse(gpa, "{\"access_token\":\"sk-ant-oat-a\",\"refresh_token\":\"r\",\"expires_in\":3600}", 1_000_000);
    defer token.deinit(gpa);
    try std.testing.expectEqualStrings("sk-ant-oat-a", token.access);
    try std.testing.expectEqual(@as(i64, 1_000_000 + 3_600_000 - 300_000), token.expires_ms);
}

test "Anthropic callback target validates exact route state and OAuth errors" {
    const gpa = std.testing.allocator;
    var ok = try parseCallbackTarget(gpa, "/callback?code=abc%2F1&state=expected", "expected");
    defer ok.deinit(gpa);
    try std.testing.expectEqualStrings("abc/1", ok.code);
    try std.testing.expectError(error.AnthropicOAuthCallbackRouteNotFound, parseCallbackTarget(gpa, "/wrong?code=a&state=expected", "expected"));
    try std.testing.expectError(error.AnthropicOAuthStateMismatch, parseCallbackTarget(gpa, "/callback?code=a&state=wrong", "expected"));
    var denied = try parseCallbackTarget(gpa, "/callback?error=access_denied&error_description=No%20thanks", "expected");
    defer denied.deinit(gpa);
    try std.testing.expectEqualStrings("No thanks", denied.oauth_error);
}

test "Anthropic callback host respects PI_OAUTH_CALLBACK_HOST" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PI_OAUTH_CALLBACK_HOST", "127.0.0.2");
    try std.testing.expectEqualStrings("127.0.0.2", callbackHost(&env));
    try std.testing.expectEqualStrings("127.0.0.1", callbackHost(null));
}
