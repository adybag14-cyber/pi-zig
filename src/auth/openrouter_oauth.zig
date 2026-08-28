//! Native OpenRouter OAuth PKCE helpers.
//!
//! OpenRouter exchanges a short-lived authorization code for a permanent
//! user-controlled API key. Browser login uses a one-shot loopback callback
//! on an OS-assigned ephemeral port and a random UUID callback path.
const std = @import("std");
const builtin = @import("builtin");
const net = std.Io.net;
const pkce = @import("pkce.zig");
const storage = @import("storage.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

pub const AUTHORIZE_URL = "https://openrouter.ai/auth";
pub const TOKEN_URL = "https://openrouter.ai/api/v1/auth/keys";
pub const LOGIN_TIMEOUT_MS: u64 = 5 * 60 * 1000;
pub const TOKEN_EXCHANGE_TIMEOUT_MS: u64 = 30_000;
pub const EXPIRES_NEVER_MS: i64 = 9_007_199_254_740_991;

pub const Token = struct {
    access: []u8,
    expires_ms: i64 = EXPIRES_NEVER_MS,

    pub fn deinit(self: *Token, gpa: std.mem.Allocator) void {
        gpa.free(self.access);
        self.* = undefined;
    }
};

pub const AuthorizationInput = struct {
    code: ?[]u8 = null,
    pub fn deinit(self: *AuthorizationInput, gpa: std.mem.Allocator) void {
        if (self.code) |value| gpa.free(value);
        self.* = undefined;
    }
};

pub const CallbackResult = union(enum) {
    code: []u8,
    oauth_error: []u8,

    pub fn deinit(self: *CallbackResult, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .code => |value| gpa.free(value),
            .oauth_error => |value| gpa.free(value),
        }
        self.* = undefined;
    }
};

pub const ExchangeOutcome = union(enum) {
    complete: Token,
    failed: []u8,

    pub fn deinit(self: *ExchangeOutcome, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*token| token.deinit(gpa),
            .failed => |message| gpa.free(message),
        }
        self.* = undefined;
    }
};

fn urlEncode(w: *std.Io.Writer, input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try w.writeByte(c);
        } else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

fn decodeQueryValue(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const buf = try gpa.dupe(u8, raw);
    errdefer gpa.free(buf);
    for (buf) |*c| {
        if (c.* == '+') c.* = ' ';
    }
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

pub fn callbackHost(env: ?*const std.process.Environ.Map) []const u8 {
    if (env) |values| if (values.get("PI_OAUTH_CALLBACK_HOST")) |value| if (value.len > 0) return value;
    return "127.0.0.1";
}

pub fn generateCallbackPath(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    const uuid = try pkce.generateUuidV4(gpa, io);
    defer gpa.free(uuid);
    return std.fmt.allocPrint(gpa, "/oauth/callback/{s}", .{uuid});
}

pub fn buildAuthorizationUrl(gpa: std.mem.Allocator, callback_url: []const u8, challenge: []const u8) ![]u8 {
    if (callback_url.len == 0 or challenge.len == 0) return error.InvalidOpenRouterAuthorization;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(AUTHORIZE_URL ++ "?callback_url=");
    try urlEncode(&out.writer, callback_url);
    try out.writer.writeAll("&code_challenge=");
    try urlEncode(&out.writer, challenge);
    try out.writer.writeAll("&code_challenge_method=S256");
    return out.toOwnedSlice();
}

pub fn parseAuthorizationInput(gpa: std.mem.Allocator, input: []const u8) !AuthorizationInput {
    const value = std.mem.trim(u8, input, " \t\r\n");
    if (value.len == 0) return .{};
    if (std.mem.indexOfScalar(u8, value, '?')) |qmark| {
        const end = std.mem.indexOfScalarPos(u8, value, qmark + 1, '#') orelse value.len;
        return .{ .code = try queryValue(gpa, value[qmark + 1 .. end], "code") };
    }
    if (std.mem.indexOf(u8, value, "code=") != null) return .{ .code = try queryValue(gpa, value, "code") };
    return .{ .code = try gpa.dupe(u8, value) };
}

pub fn buildExchangeJson(gpa: std.mem.Allocator, code: []const u8, verifier: []const u8) ![]u8 {
    if (code.len == 0 or verifier.len == 0) return error.InvalidOpenRouterAuthorizationCode;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"code\":");
    try std.json.Stringify.value(code, .{}, &out.writer);
    try out.writer.writeAll(",\"code_verifier\":");
    try std.json.Stringify.value(verifier, .{}, &out.writer);
    try out.writer.writeAll(",\"code_challenge_method\":\"S256\"}");
    return out.toOwnedSlice();
}

fn objectString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return if (value == .string and value.string.len > 0) value.string else null;
}

fn errorDetail(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;
    if (objectString(value.object, "error_description")) |detail| return detail;
    if (objectString(value.object, "message")) |detail| return detail;
    if (objectString(value.object, "error")) |detail| return detail;
    if (value.object.get("error")) |nested| if (nested == .object) return objectString(nested.object, "message");
    return null;
}

pub fn parseExchangeResponse(gpa: std.mem.Allocator, status: u16, body: []const u8) !ExchangeOutcome {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch {
        if (status >= 200 and status < 300) return error.OpenRouterOAuthInvalidJson;
        return .{ .failed = try std.fmt.allocPrint(gpa, "OpenRouter OAuth key exchange failed (HTTP {d})", .{status}) };
    };
    defer parsed.deinit();
    if (status < 200 or status >= 300) {
        if (errorDetail(parsed.value)) |detail|
            return .{ .failed = try std.fmt.allocPrint(gpa, "OpenRouter OAuth key exchange failed (HTTP {d}): {s}", .{ status, detail }) };
        return .{ .failed = try std.fmt.allocPrint(gpa, "OpenRouter OAuth key exchange failed (HTTP {d})", .{status}) };
    }
    if (parsed.value != .object) return error.OpenRouterOAuthInvalidJson;
    const key = objectString(parsed.value.object, "key") orelse return error.OpenRouterOAuthMissingKey;
    return .{ .complete = .{ .access = try gpa.dupe(u8, key) } };
}

pub fn parseCallbackTarget(gpa: std.mem.Allocator, target: []const u8, expected_path: []const u8) !CallbackResult {
    const qmark = std.mem.indexOfScalar(u8, target, '?');
    const hash = std.mem.indexOfScalar(u8, target, '#') orelse target.len;
    const path_end = @min(qmark orelse target.len, hash);
    if (!std.mem.eql(u8, target[0..path_end], expected_path)) return error.OpenRouterOAuthCallbackRouteNotFound;
    const query = if (qmark) |index| target[index + 1 .. hash] else "";
    if (try queryValue(gpa, query, "error")) |oauth_error| {
        if (try queryValue(gpa, query, "error_description")) |description| {
            gpa.free(oauth_error);
            return .{ .oauth_error = description };
        }
        return .{ .oauth_error = oauth_error };
    }
    const code = try queryValue(gpa, query, "code") orelse return error.OpenRouterOAuthMissingAuthorizationCode;
    if (code.len == 0) {
        gpa.free(code);
        return error.OpenRouterOAuthMissingAuthorizationCode;
    }
    return .{ .code = code };
}

const HttpResponse = struct { status: u16, body: []u8 };

fn postJsonWithOptions(gpa: std.mem.Allocator, io: std.Io, payload: []const u8, options_in: bootstrap_http.Options) !HttpResponse {
    const options = bootstrap_http.withDefaultTimeout(options_in, TOKEN_EXCHANGE_TIMEOUT_MS);
    var response = bootstrap_http.request(gpa, io, .{
        .url = TOKEN_URL,
        .method = .POST,
        .payload = payload,
        .headers = &.{
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "content-type", .value = "application/json" },
        },
        .options = options,
    }) catch |err| switch (err) {
        error.ProviderRequestTimeout => return error.OpenRouterOAuthTokenExchangeTimeout,
        else => return err,
    };
    errdefer response.deinit(gpa);
    return .{ .status = response.status, .body = response.body };
}

pub fn exchangeAuthorizationCodeWithOptions(gpa: std.mem.Allocator, io: std.Io, code: []const u8, verifier: []const u8, options: bootstrap_http.Options) !ExchangeOutcome {
    const payload = try buildExchangeJson(gpa, code, verifier);
    defer gpa.free(payload);
    const response = try postJsonWithOptions(gpa, io, payload, options);
    defer gpa.free(response.body);
    return parseExchangeResponse(gpa, response.status, response.body);
}

pub fn exchangeAuthorizationCode(gpa: std.mem.Allocator, io: std.Io, code: []const u8, verifier: []const u8) !ExchangeOutcome {
    return exchangeAuthorizationCodeWithOptions(gpa, io, code, verifier, .{});
}

fn callbackTargetFromRequest(raw: []const u8) ![]const u8 {
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
    const line = raw[0..line_end];
    if (!std.mem.startsWith(u8, line, "GET ")) return error.InvalidOpenRouterOAuthCallbackRequest;
    const rest = line[4..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return error.InvalidOpenRouterOAuthCallbackRequest;
    if (space == 0) return error.InvalidOpenRouterOAuthCallbackRequest;
    return rest[0..space];
}

fn writeCallbackHttp(io: std.Io, stream: *net.Stream, status: u16, message: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        404 => "Not Found",
        409 => "Conflict",
        502 => "Bad Gateway",
        else => "Bad Request",
    };
    const prefix = "<!doctype html><meta charset=utf-8><title>OpenRouter OAuth</title><body><p>";
    const suffix = "</p></body>";
    var wbuf: [1024]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    try writer.interface.print("HTTP/1.1 {d} {s}\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, status_text, prefix.len + message.len + suffix.len });
    try writer.interface.writeAll(prefix);
    try writer.interface.writeAll(message);
    try writer.interface.writeAll(suffix);
    try writer.interface.flush();
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
fn acceptCallback(listener: *net.Server, io: std.Io, abort_flag: ?*const bool, timeout_ms: u64) !net.Stream {
    if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
    const Race = union(enum) { accepted: anyerror!net.Stream, aborted: bool, timeout: bool };
    var queue: [3]Race = undefined;
    var select = std.Io.Select(Race).init(io, &queue);
    select.async(.accepted, acceptCallbackTask, .{ listener, io });
    if (abort_flag) |flag| select.async(.aborted, callbackWatchAbort, .{ io, flag });
    select.async(.timeout, callbackSleepMs, .{ io, timeout_ms });
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
        .timeout => |expired| {
            while (select.cancel()) |_| {}
            return if (expired) error.OpenRouterOAuthLoginTimeout else error.Canceled;
        },
    }
}

pub const CallbackServer = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    listener: net.Server,
    callback_path: []u8,
    callback_url: []u8,
    started_ms: i64,
    claimed: bool = false,

    pub fn deinit(self: *CallbackServer) void {
        self.listener.deinit(self.io);
        self.gpa.free(self.callback_path);
        self.gpa.free(self.callback_url);
        self.* = undefined;
    }

    /// Wait for one valid callback code. Wrong routes remain retryable. A valid
    /// code claims this server so subsequent callbacks receive HTTP 409.
    pub fn waitCode(self: *CallbackServer, abort_flag: ?*const bool) !CallbackResult {
        const deadline_ms = self.started_ms + @as(i64, @intCast(LOGIN_TIMEOUT_MS));
        callback_loop: while (true) {
            const now_ms = std.Io.Clock.real.now(self.io).toMilliseconds();
            if (now_ms >= deadline_ms) return error.OpenRouterOAuthLoginTimeout;
            const remaining_ms: u64 = @intCast(deadline_ms - now_ms);
            var stream = try acceptCallback(&self.listener, self.io, abort_flag, remaining_ms);
            defer stream.close(self.io);
            var raw: [8192]u8 = undefined;
            var reader = stream.reader(self.io, &raw);
            const request_line = reader.interface.takeDelimiterInclusive('\n') catch {
                writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                continue :callback_loop;
            };
            // Consume the bounded request headers before closing the Windows
            // TCP stream. Leaving unread request bytes can turn an otherwise
            // successful HTTP response into an abortive connection reset.
            while (true) {
                const header_line = reader.interface.takeDelimiterInclusive('\n') catch {
                    writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                    continue :callback_loop;
                };
                if (std.mem.eql(u8, header_line, "\r\n") or std.mem.eql(u8, header_line, "\n")) break;
            }
            const target = callbackTargetFromRequest(request_line) catch {
                writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                continue :callback_loop;
            };
            if (self.claimed) {
                try writeCallbackHttp(self.io, &stream, 409, "This OAuth callback has already been used.");
                continue;
            }
            const result = parseCallbackTarget(self.gpa, target, self.callback_path) catch |err| switch (err) {
                error.OpenRouterOAuthCallbackRouteNotFound => {
                    try writeCallbackHttp(self.io, &stream, 404, "OAuth callback route not found.");
                    continue;
                },
                error.OpenRouterOAuthMissingAuthorizationCode => {
                    try writeCallbackHttp(self.io, &stream, 400, "OpenRouter returned no authorization code.");
                    continue;
                },
                else => return err,
            };
            switch (result) {
                .code => {
                    self.claimed = true;
                    try writeCallbackHttp(self.io, &stream, 200, "OpenRouter authorization code received. You may close this page.");
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

pub fn startCallbackServer(gpa: std.mem.Allocator, io: std.Io, host: []const u8) !CallbackServer {
    const normalized = if (std.ascii.eqlIgnoreCase(host, "localhost")) "127.0.0.1" else host;
    const callback_path = try generateCallbackPath(gpa, io);
    errdefer gpa.free(callback_path);
    var addr = net.IpAddress.parse(normalized, 0) catch return error.InvalidOpenRouterOAuthCallbackHost;
    addr.setPort(0);
    var listener = try addr.listen(io, .{ .reuse_address = true });
    errdefer listener.deinit(io);
    const port = listener.socket.address.getPort();
    if (port == 0) return error.OpenRouterOAuthCallbackPortUnavailable;
    const bracketed = std.mem.indexOfScalar(u8, normalized, ':') != null;
    const callback_url = if (bracketed)
        try std.fmt.allocPrint(gpa, "http://[{s}]:{d}{s}", .{ normalized, port, callback_path })
    else
        try std.fmt.allocPrint(gpa, "http://{s}:{d}{s}", .{ normalized, port, callback_path });
    return .{ .gpa = gpa, .io = io, .listener = listener, .callback_path = callback_path, .callback_url = callback_url, .started_ms = std.Io.Clock.real.now(io).toMilliseconds() };
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
    try store.setOAuth("openrouter", .{ .refresh = @constCast(""), .access = token.access, .expires = token.expires_ms });
}

test "OpenRouter OAuth authorization URL uses callback PKCE and no state" {
    const gpa = std.testing.allocator;
    const url = try buildAuthorizationUrl(gpa, "http://127.0.0.1:54321/oauth/callback/a-b", "challenge+/=");
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, AUTHORIZE_URL ++ "?"));
    try std.testing.expect(std.mem.indexOf(u8, url, "callback_url=http%3A%2F%2F127.0.0.1%3A54321%2Foauth%2Fcallback%2Fa-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge%2B%2F%3D") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "state=") == null);
}

test "OpenRouter OAuth manual input accepts redirect query params and raw code" {
    const gpa = std.testing.allocator;
    var redirect = try parseAuthorizationInput(gpa, " http://127.0.0.1/cb?code=c%2B1 ");
    defer redirect.deinit(gpa);
    try std.testing.expectEqualStrings("c+1", redirect.code.?);
    var params = try parseAuthorizationInput(gpa, "foo=1&code=manual%2Fcode");
    defer params.deinit(gpa);
    try std.testing.expectEqualStrings("manual/code", params.code.?);
    var raw = try parseAuthorizationInput(gpa, " bare-code \n");
    defer raw.deinit(gpa);
    try std.testing.expectEqualStrings("bare-code", raw.code.?);
    var empty = try parseAuthorizationInput(gpa, " \t\n");
    defer empty.deinit(gpa);
    try std.testing.expect(empty.code == null);
}

test "OpenRouter OAuth exchange JSON and permanent key parsing match upstream" {
    const gpa = std.testing.allocator;
    const payload = try buildExchangeJson(gpa, "auth-code", "verifier");
    defer gpa.free(payload);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, payload, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("auth-code", parsed.value.object.get("code").?.string);
    try std.testing.expectEqualStrings("verifier", parsed.value.object.get("code_verifier").?.string);
    try std.testing.expectEqualStrings("S256", parsed.value.object.get("code_challenge_method").?.string);
    var outcome = try parseExchangeResponse(gpa, 200, "{\"key\":\"sk-or-test\"}");
    defer outcome.deinit(gpa);
    try std.testing.expectEqualStrings("sk-or-test", outcome.complete.access);
    try std.testing.expectEqual(EXPIRES_NEVER_MS, outcome.complete.expires_ms);
    try std.testing.expectError(error.OpenRouterOAuthMissingKey, parseExchangeResponse(gpa, 200, "{\"user_id\":\"u\"}"));
}

test "OpenRouter OAuth exchange errors preserve upstream detail priority" {
    const gpa = std.testing.allocator;
    var nested = try parseExchangeResponse(gpa, 403, "{\"error\":{\"message\":\"invalid code\"}}");
    defer nested.deinit(gpa);
    try std.testing.expectEqualStrings("OpenRouter OAuth key exchange failed (HTTP 403): invalid code", nested.failed);
    var desc = try parseExchangeResponse(gpa, 401, "{\"message\":\"message\",\"error_description\":\"description\"}");
    defer desc.deinit(gpa);
    try std.testing.expectEqualStrings("OpenRouter OAuth key exchange failed (HTTP 401): description", desc.failed);
    try std.testing.expectError(error.OpenRouterOAuthInvalidJson, parseExchangeResponse(gpa, 200, "not-json"));
}

test "OpenRouter OAuth callback path is UUIDv4 and callback parsing validates route" {
    const gpa = std.testing.allocator;
    const path = try generateCallbackPath(gpa, std.testing.io);
    defer gpa.free(path);
    try std.testing.expect(std.mem.startsWith(u8, path, "/oauth/callback/"));
    const uuid = path["/oauth/callback/".len..];
    try std.testing.expectEqual(@as(usize, 36), uuid.len);
    try std.testing.expectEqual(@as(u8, '4'), uuid[14]);
    var ok = try parseCallbackTarget(gpa, "/oauth/callback/test?code=a%2Fb", "/oauth/callback/test");
    defer ok.deinit(gpa);
    try std.testing.expectEqualStrings("a/b", ok.code);
    try std.testing.expectError(error.OpenRouterOAuthCallbackRouteNotFound, parseCallbackTarget(gpa, "/wrong?code=a", "/oauth/callback/test"));
    var denied = try parseCallbackTarget(gpa, "/oauth/callback/test?error=access_denied&error_description=No%20thanks", "/oauth/callback/test");
    defer denied.deinit(gpa);
    try std.testing.expectEqualStrings("No thanks", denied.oauth_error);
    try std.testing.expectEqualStrings(
        "/oauth/callback/test?code=a%2Fb",
        try callbackTargetFromRequest("GET /oauth/callback/test?code=a%2Fb HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"),
    );
}

test "OpenRouter OAuth callback host defaults and honors override" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PI_OAUTH_CALLBACK_HOST", "127.0.0.2");
    try std.testing.expectEqualStrings("127.0.0.2", callbackHost(&env));
    try std.testing.expectEqualStrings("127.0.0.1", callbackHost(null));
}
