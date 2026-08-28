//! Native OpenAI Codex (ChatGPT Plus/Pro) OAuth protocol helpers.
//! Network/UI orchestration is layered on top so the protocol is independently testable.
const std = @import("std");
const builtin = @import("builtin");
const net = std.Io.net;
const pkce_mod = @import("pkce.zig");
const storage = @import("storage.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

pub const CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
pub const AUTH_BASE_URL = "https://auth.openai.com";
pub const AUTHORIZE_URL = AUTH_BASE_URL ++ "/oauth/authorize";
pub const TOKEN_URL = AUTH_BASE_URL ++ "/oauth/token";
pub const REDIRECT_URI = "http://localhost:1455/auth/callback";
pub const CALLBACK_PORT: u16 = 1455;
pub const CALLBACK_PATH = "/auth/callback";
pub const DEVICE_USER_CODE_URL = AUTH_BASE_URL ++ "/api/accounts/deviceauth/usercode";
pub const DEVICE_TOKEN_URL = AUTH_BASE_URL ++ "/api/accounts/deviceauth/token";
pub const DEVICE_VERIFICATION_URI = AUTH_BASE_URL ++ "/codex/device";
pub const DEVICE_REDIRECT_URI = AUTH_BASE_URL ++ "/deviceauth/callback";
pub const DEVICE_CODE_TIMEOUT_SECONDS: u64 = 15 * 60;
pub const SCOPE = "openid profile email offline_access";
pub const JWT_CLAIM_PATH = "https://api.openai.com/auth";

pub const Pkce = pkce_mod.Pkce;

pub const AuthorizationFlow = struct {
    verifier: []u8,
    state: []u8,
    url: []u8,

    pub fn deinit(self: *AuthorizationFlow, gpa: std.mem.Allocator) void {
        gpa.free(self.verifier);
        gpa.free(self.state);
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
    account_id: []u8,

    pub fn deinit(self: *Token, gpa: std.mem.Allocator) void {
        gpa.free(self.access);
        gpa.free(self.refresh);
        gpa.free(self.account_id);
        self.* = undefined;
    }
};

pub const DeviceAuthInfo = struct {
    device_auth_id: []u8,
    user_code: []u8,
    interval_seconds: u64,

    pub fn deinit(self: *DeviceAuthInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.device_auth_id);
        gpa.free(self.user_code);
        self.* = undefined;
    }
};

pub const DeviceLoginResult = struct { device: DeviceAuthInfo, token: Token };

pub const DeviceTokenSuccess = struct {
    authorization_code: []u8,
    code_verifier: []u8,

    pub fn deinit(self: *DeviceTokenSuccess, gpa: std.mem.Allocator) void {
        gpa.free(self.authorization_code);
        gpa.free(self.code_verifier);
        self.* = undefined;
    }
};

pub const DevicePollAttempt = union(enum) {
    complete: DeviceTokenSuccess,
    pending,
    slow_down,
    failed: []u8,

    pub fn deinit(self: *DevicePollAttempt, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*value| value.deinit(gpa),
            .failed => |message| gpa.free(message),
            else => {},
        }
        self.* = undefined;
    }
};

fn formEncode(w: *std.Io.Writer, input: []const u8) !void {
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
    for (buf) |*c| if (c.* == '+') {
        c.* = ' ';
    };
    const decoded = std.Uri.percentDecodeInPlace(buf);
    if (decoded.ptr == buf.ptr and decoded.len == buf.len) return buf;
    std.mem.copyForwards(u8, buf[0..decoded.len], decoded);
    return gpa.realloc(buf, decoded.len);
}

fn queryValue(gpa: std.mem.Allocator, query: []const u8, key: []const u8) !?[]u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const decoded_key = try decodeQueryValue(gpa, pair[0..eq]);
        defer gpa.free(decoded_key);
        if (!std.mem.eql(u8, decoded_key, key)) continue;
        const value = try decodeQueryValue(gpa, if (eq < pair.len) pair[eq + 1 ..] else "");
        return @as(?[]u8, value);
    }
    return null;
}

fn queryFromUrlLike(value: []const u8) ?[]const u8 {
    const qmark = std.mem.indexOfScalar(u8, value, '?') orelse return null;
    const fragment = std.mem.indexOfScalarPos(u8, value, qmark + 1, '#') orelse value.len;
    return value[qmark + 1 .. fragment];
}

/// Accepts a redirect URL, `code#state`, a query string, or a raw code.
pub fn parseAuthorizationInput(gpa: std.mem.Allocator, input: []const u8) !AuthorizationInput {
    const value = std.mem.trim(u8, input, " \t\r\n");
    if (value.len == 0) return .{};

    if (queryFromUrlLike(value)) |query| {
        return .{
            .code = try queryValue(gpa, query, "code"),
            .state = try queryValue(gpa, query, "state"),
        };
    }

    if (std.mem.indexOfScalar(u8, value, '#')) |hash| {
        return .{
            .code = if (hash > 0) try gpa.dupe(u8, value[0..hash]) else null,
            .state = if (hash + 1 < value.len) try gpa.dupe(u8, value[hash + 1 ..]) else null,
        };
    }

    if (std.mem.indexOf(u8, value, "code=") != null) {
        return .{
            .code = try queryValue(gpa, value, "code"),
            .state = try queryValue(gpa, value, "state"),
        };
    }

    return .{ .code = try gpa.dupe(u8, value) };
}

pub fn buildAuthorizationUrl(
    gpa: std.mem.Allocator,
    challenge: []const u8,
    state: []const u8,
    originator: []const u8,
) ![]u8 {
    if (challenge.len == 0 or state.len == 0) return error.InvalidOpenAICodexAuthorization;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(AUTHORIZE_URL ++ "?response_type=code&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&redirect_uri=");
    try formEncode(&out.writer, REDIRECT_URI);
    try out.writer.writeAll("&scope=");
    try formEncode(&out.writer, SCOPE);
    try out.writer.writeAll("&code_challenge=");
    try formEncode(&out.writer, challenge);
    try out.writer.writeAll("&code_challenge_method=S256&state=");
    try formEncode(&out.writer, state);
    try out.writer.writeAll("&id_token_add_organizations=true&codex_cli_simplified_flow=true&originator=");
    try formEncode(&out.writer, if (originator.len > 0) originator else "pi");
    return out.toOwnedSlice();
}

pub fn createAuthorizationFlow(gpa: std.mem.Allocator, io: std.Io, originator: []const u8) !AuthorizationFlow {
    var pair = try pkce_mod.generate(gpa, io);
    defer pair.deinit(gpa);
    const state = try pkce_mod.generateHexState(gpa, io);
    errdefer gpa.free(state);
    return .{
        .verifier = try gpa.dupe(u8, pair.verifier),
        .state = state,
        .url = try buildAuthorizationUrl(gpa, pair.challenge, state, originator),
    };
}

pub fn buildAuthorizationCodeForm(gpa: std.mem.Allocator, code: []const u8, verifier: []const u8, redirect_uri: []const u8) ![]u8 {
    if (code.len == 0 or verifier.len == 0 or redirect_uri.len == 0) return error.InvalidOpenAICodexAuthorizationCode;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=authorization_code&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&code=");
    try formEncode(&out.writer, code);
    try out.writer.writeAll("&code_verifier=");
    try formEncode(&out.writer, verifier);
    try out.writer.writeAll("&redirect_uri=");
    try formEncode(&out.writer, redirect_uri);
    return out.toOwnedSlice();
}

pub fn buildRefreshForm(gpa: std.mem.Allocator, refresh_token: []const u8) ![]u8 {
    if (refresh_token.len == 0) return error.InvalidOpenAICodexRefreshToken;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=refresh_token&refresh_token=");
    try formEncode(&out.writer, refresh_token);
    try out.writer.writeAll("&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    return out.toOwnedSlice();
}

pub fn buildDeviceUserCodeJson(gpa: std.mem.Allocator) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"client_id\":\"{s}\"}}", .{CLIENT_ID});
}

pub fn buildDevicePollJson(gpa: std.mem.Allocator, device_auth_id: []const u8, user_code: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"device_auth_id\":");
    try std.json.Stringify.value(device_auth_id, .{}, &out.writer);
    try out.writer.writeAll(",\"user_code\":");
    try std.json.Stringify.value(user_code, .{}, &out.writer);
    try out.writer.writeByte('}');
    return out.toOwnedSlice();
}

fn dupRequiredString(gpa: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) ![]u8 {
    const value = obj.get(name) orelse return error.InvalidOpenAICodexResponse;
    if (value != .string or value.string.len == 0) return error.InvalidOpenAICodexResponse;
    return gpa.dupe(u8, value.string);
}

pub fn parseDeviceAuthInfo(gpa: std.mem.Allocator, raw: []const u8) !DeviceAuthInfo {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenAICodexDeviceCode;
    const id = try dupRequiredString(gpa, parsed.value.object, "device_auth_id");
    errdefer gpa.free(id);
    const code = try dupRequiredString(gpa, parsed.value.object, "user_code");
    errdefer gpa.free(code);
    const interval_value = parsed.value.object.get("interval") orelse return error.InvalidOpenAICodexDeviceCode;
    const interval: u64 = switch (interval_value) {
        .integer => |n| if (n >= 0) @intCast(n) else return error.InvalidOpenAICodexDeviceCode,
        .float => |n| if (n >= 0 and std.math.isFinite(n)) @intFromFloat(n) else return error.InvalidOpenAICodexDeviceCode,
        .string => |s| std.fmt.parseUnsigned(u64, std.mem.trim(u8, s, " \t\r\n"), 10) catch return error.InvalidOpenAICodexDeviceCode,
        else => return error.InvalidOpenAICodexDeviceCode,
    };
    return .{ .device_auth_id = id, .user_code = code, .interval_seconds = interval };
}

fn errorCodeFromBody(gpa: std.mem.Allocator, raw: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const error_value = parsed.value.object.get("error") orelse return null;
    return switch (error_value) {
        .string => |s| if (s.len > 0) try gpa.dupe(u8, s) else null,
        .object => |obj| blk: {
            const code = obj.get("code") orelse break :blk null;
            if (code != .string or code.string.len == 0) break :blk null;
            break :blk try gpa.dupe(u8, code.string);
        },
        else => null,
    };
}

pub fn classifyDevicePoll(gpa: std.mem.Allocator, status: u16, raw: []const u8) !DevicePollAttempt {
    if (status >= 200 and status < 300) {
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch
            return .{ .failed = try gpa.dupe(u8, "Invalid OpenAI Codex device auth token response") };
        defer parsed.deinit();
        if (parsed.value != .object) return .{ .failed = try gpa.dupe(u8, "Invalid OpenAI Codex device auth token response") };
        const auth_code = dupRequiredString(gpa, parsed.value.object, "authorization_code") catch
            return .{ .failed = try gpa.dupe(u8, "Invalid OpenAI Codex device auth token response") };
        errdefer gpa.free(auth_code);
        const verifier = dupRequiredString(gpa, parsed.value.object, "code_verifier") catch {
            gpa.free(auth_code);
            return .{ .failed = try gpa.dupe(u8, "Invalid OpenAI Codex device auth token response") };
        };
        return .{ .complete = .{ .authorization_code = auth_code, .code_verifier = verifier } };
    }

    // OpenAI currently uses both statuses as "not approved yet" responses.
    if (status == 403 or status == 404) return .pending;

    const code = try errorCodeFromBody(gpa, raw);
    defer if (code) |v| gpa.free(v);
    if (code) |v| {
        if (std.mem.eql(u8, v, "deviceauth_authorization_pending")) return .pending;
        if (std.mem.eql(u8, v, "slow_down")) return .slow_down;
    }
    return .{ .failed = try std.fmt.allocPrint(gpa, "OpenAI Codex device auth failed with status {d}{s}{s}", .{
        status,
        if (raw.len > 0) ": " else "",
        raw,
    }) };
}

fn decodeBase64Url(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoder = std.base64.url_safe_no_pad.Decoder;
    const size = decoder.calcSizeForSlice(input) catch return error.InvalidOpenAICodexJwt;
    const out = try gpa.alloc(u8, size);
    errdefer gpa.free(out);
    decoder.decode(out, input) catch return error.InvalidOpenAICodexJwt;
    return out;
}

pub fn extractAccountId(gpa: std.mem.Allocator, access_token: []const u8) ![]u8 {
    const first = std.mem.indexOfScalar(u8, access_token, '.') orelse return error.InvalidOpenAICodexJwt;
    const tail = access_token[first + 1 ..];
    const second = std.mem.indexOfScalar(u8, tail, '.') orelse return error.InvalidOpenAICodexJwt;
    if (std.mem.indexOfScalar(u8, tail[second + 1 ..], '.') != null) return error.InvalidOpenAICodexJwt;
    const payload = try decodeBase64Url(gpa, tail[0..second]);
    defer gpa.free(payload);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, payload, .{}) catch return error.InvalidOpenAICodexJwt;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenAICodexJwt;
    const auth = parsed.value.object.get(JWT_CLAIM_PATH) orelse return error.MissingOpenAICodexAccountId;
    if (auth != .object) return error.MissingOpenAICodexAccountId;
    const id = auth.object.get("chatgpt_account_id") orelse return error.MissingOpenAICodexAccountId;
    if (id != .string or id.string.len == 0) return error.MissingOpenAICodexAccountId;
    return gpa.dupe(u8, id.string);
}

pub fn parseToken(gpa: std.mem.Allocator, raw: []const u8, now_ms: i64) !Token {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidOpenAICodexToken;
    const access = try dupRequiredString(gpa, parsed.value.object, "access_token");
    errdefer gpa.free(access);
    const refresh_value = try dupRequiredString(gpa, parsed.value.object, "refresh_token");
    errdefer gpa.free(refresh_value);
    const expires_value = parsed.value.object.get("expires_in") orelse return error.InvalidOpenAICodexToken;
    const expires_in: i64 = switch (expires_value) {
        .integer => |n| if (n >= 0) n else return error.InvalidOpenAICodexToken,
        .float => |n| if (n >= 0 and std.math.isFinite(n)) @intFromFloat(n) else return error.InvalidOpenAICodexToken,
        else => return error.InvalidOpenAICodexToken,
    };
    const account_id = extractAccountId(gpa, access) catch return error.MissingOpenAICodexAccountId;
    return .{
        .access = access,
        .refresh = refresh_value,
        .expires_ms = now_ms + expires_in * 1000,
        .account_id = account_id,
    };
}

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
    if (!std.mem.eql(u8, target[0..path_end], CALLBACK_PATH)) return error.OpenAICodexCallbackRouteNotFound;
    const query = if (qmark) |i| target[i + 1 .. fragment] else "";
    const state = try queryValue(gpa, query, "state") orelse return error.OpenAICodexStateMismatch;
    defer gpa.free(state);
    if (!std.mem.eql(u8, state, expected_state)) return error.OpenAICodexStateMismatch;
    if (try queryValue(gpa, query, "error")) |oauth_error| {
        if (try queryValue(gpa, query, "error_description")) |description| {
            gpa.free(oauth_error);
            return .{ .oauth_error = description };
        }
        return .{ .oauth_error = oauth_error };
    }
    const code = try queryValue(gpa, query, "code") orelse return error.OpenAICodexMissingAuthorizationCode;
    if (code.len == 0) {
        gpa.free(code);
        return error.OpenAICodexMissingAuthorizationCode;
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
    while (!@atomicLoad(bool, flag, .acquire)) {
        if (!callbackSleepMs(io, 25)) return false;
    }
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
            if (aborted) return error.LoginCancelled;
            return error.Canceled;
        },
    }
}

fn callbackTargetFromRequest(raw: []const u8) ![]const u8 {
    const line_end = std.mem.indexOf(u8, raw, "\r\n") orelse std.mem.indexOfScalar(u8, raw, '\n') orelse raw.len;
    const line = raw[0..line_end];
    if (!std.mem.startsWith(u8, line, "GET ")) return error.InvalidOpenAICodexCallbackRequest;
    const rest = line[4..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return error.InvalidOpenAICodexCallbackRequest;
    if (space == 0) return error.InvalidOpenAICodexCallbackRequest;
    return rest[0..space];
}

fn writeCallbackHttp(io: std.Io, stream: *net.Stream, status: u16, message: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        404 => "Not Found",
        500 => "Internal Server Error",
        else => "Bad Request",
    };
    const prefix = "<!doctype html><meta charset=utf-8><title>OpenAI Codex OAuth</title><body><p>";
    const suffix = "</p></body>";
    const length = prefix.len + message.len + suffix.len;
    var wbuf: [1024]u8 = undefined;
    var writer = stream.writer(io, &wbuf);
    try writer.interface.print("HTTP/1.1 {d} {s}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, status_text, length });
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
        callback_loop: while (true) {
            var stream = try acceptCallback(&self.listener, self.io, abort_flag);
            defer stream.close(self.io);
            var raw: [8192]u8 = undefined;
            var reader = stream.reader(self.io, &raw);
            const request_line = reader.interface.takeDelimiterInclusive('\n') catch {
                writeCallbackHttp(self.io, &stream, 400, "Invalid OAuth callback request.") catch {};
                continue :callback_loop;
            };
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
            const result = parseCallbackTarget(gpa, target, expected_state) catch |err| switch (err) {
                error.OpenAICodexCallbackRouteNotFound => {
                    try writeCallbackHttp(self.io, &stream, 404, "Callback route not found.");
                    continue;
                },
                error.OpenAICodexStateMismatch => {
                    try writeCallbackHttp(self.io, &stream, 400, "State mismatch.");
                    continue;
                },
                error.OpenAICodexMissingAuthorizationCode => {
                    try writeCallbackHttp(self.io, &stream, 400, "Missing authorization code.");
                    continue;
                },
                else => return err,
            };
            switch (result) {
                .code => {
                    try writeCallbackHttp(self.io, &stream, 200, "OpenAI authentication completed. You can close this window.");
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
    const normalized_host = if (std.ascii.eqlIgnoreCase(host, "localhost")) "127.0.0.1" else host;
    var addr = net.IpAddress.parse(normalized_host, CALLBACK_PORT) catch return error.InvalidOpenAICodexCallbackHost;
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

const HttpResponse = struct { status: u16, body: []u8 };

fn httpRequestWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    method: std.http.Method,
    content_type: []const u8,
    payload: []const u8,
    options: bootstrap_http.Options,
) !HttpResponse {
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = method,
        .payload = payload,
        .headers = &.{
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "content-type", .value = content_type },
        },
        .options = options,
    });
    errdefer response.deinit(gpa);
    return .{ .status = response.status, .body = response.body };
}

fn tokenHttpWithOptions(gpa: std.mem.Allocator, io: std.Io, form: []const u8, operation: []const u8, options: bootstrap_http.Options) !Token {
    const response = try httpRequestWithOptions(gpa, io, TOKEN_URL, .POST, "application/x-www-form-urlencoded", form, options);
    defer gpa.free(response.body);
    if (response.status < 200 or response.status >= 300) {
        _ = operation;
        return error.OpenAICodexTokenHttpError;
    }
    return parseToken(gpa, response.body, std.Io.Clock.real.now(io).toMilliseconds());
}

pub fn exchangeAuthorizationCodeWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    code: []const u8,
    verifier: []const u8,
    redirect_uri: []const u8,
    options: bootstrap_http.Options,
) !Token {
    const form = try buildAuthorizationCodeForm(gpa, code, verifier, redirect_uri);
    defer gpa.free(form);
    return tokenHttpWithOptions(gpa, io, form, "exchange", options);
}

pub fn exchangeAuthorizationCode(
    gpa: std.mem.Allocator,
    io: std.Io,
    code: []const u8,
    verifier: []const u8,
    redirect_uri: []const u8,
) !Token {
    return exchangeAuthorizationCodeWithOptions(gpa, io, code, verifier, redirect_uri, .{});
}

pub fn refreshWithOptions(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8, options: bootstrap_http.Options) !Token {
    const form = try buildRefreshForm(gpa, refresh_token);
    defer gpa.free(form);
    return tokenHttpWithOptions(gpa, io, form, "refresh", options);
}

pub fn refresh(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8) !Token {
    return refreshWithOptions(gpa, io, refresh_token, .{});
}

pub fn requestDeviceAuthorizationWithOptions(gpa: std.mem.Allocator, io: std.Io, options: bootstrap_http.Options) !DeviceAuthInfo {
    const payload = try buildDeviceUserCodeJson(gpa);
    defer gpa.free(payload);
    const response = try httpRequestWithOptions(gpa, io, DEVICE_USER_CODE_URL, .POST, "application/json", payload, options);
    defer gpa.free(response.body);
    if (response.status == 404) return error.OpenAICodexDeviceCodeUnavailable;
    if (response.status < 200 or response.status >= 300) return error.OpenAICodexDeviceCodeHttpError;
    return parseDeviceAuthInfo(gpa, response.body);
}

pub fn requestDeviceAuthorization(gpa: std.mem.Allocator, io: std.Io) !DeviceAuthInfo {
    return requestDeviceAuthorizationWithOptions(gpa, io, .{});
}

pub fn requestDevicePollWithOptions(gpa: std.mem.Allocator, io: std.Io, device: *const DeviceAuthInfo, options: bootstrap_http.Options) !DevicePollAttempt {
    const payload = try buildDevicePollJson(gpa, device.device_auth_id, device.user_code);
    defer gpa.free(payload);
    const response = try httpRequestWithOptions(gpa, io, DEVICE_TOKEN_URL, .POST, "application/json", payload, options);
    defer gpa.free(response.body);
    return classifyDevicePoll(gpa, response.status, response.body);
}

pub fn requestDevicePoll(gpa: std.mem.Allocator, io: std.Io, device: *const DeviceAuthInfo) !DevicePollAttempt {
    return requestDevicePollWithOptions(gpa, io, device, .{});
}

fn sleepMs(io: std.Io, ms: u64) !void {
    const bounded: i64 = @intCast(@min(ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(bounded), .clock = .real } };
    try timeout.sleep(io);
}

pub fn nextDevicePollIntervalMs(current_ms: u64, attempt: DevicePollAttempt) u64 {
    return switch (attempt) {
        .slow_down => @max(@as(u64, 1000), current_ms + 5000),
        else => @max(@as(u64, 1000), current_ms),
    };
}

pub fn pollDeviceCodeWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    device: *const DeviceAuthInfo,
    abort_flag: ?*const bool,
    options_in: bootstrap_http.Options,
) !DeviceTokenSuccess {
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    const started = std.Io.Clock.real.now(io).toMilliseconds();
    const deadline = started + @as(i64, @intCast(DEVICE_CODE_TIMEOUT_SECONDS)) * 1000;
    var interval_ms: u64 = @max(@as(u64, 1000), device.interval_seconds * 1000);
    var saw_slow_down = false;

    // Upstream polls immediately, then waits between incomplete attempts.
    while (std.Io.Clock.real.now(io).toMilliseconds() < deadline) {
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
        var attempt = try requestDevicePollWithOptions(gpa, io, device, options);
        switch (attempt) {
            .complete => |success| return success,
            .pending => {},
            .slow_down => {
                saw_slow_down = true;
                interval_ms = nextDevicePollIntervalMs(interval_ms, .slow_down);
            },
            .failed => {
                attempt.deinit(gpa);
                return error.OpenAICodexDeviceAuthFailed;
            },
        }
        attempt.deinit(gpa);

        const remaining = deadline - std.Io.Clock.real.now(io).toMilliseconds();
        if (remaining <= 0) break;
        const delay = @min(interval_ms, @as(u64, @intCast(remaining)));
        var elapsed: u64 = 0;
        while (elapsed < delay) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            const slice = @min(@as(u64, 100), delay - elapsed);
            try sleepMs(io, slice);
            elapsed += slice;
        }
    }
    return if (saw_slow_down) error.DeviceFlowTimedOutAfterSlowDown else error.DeviceFlowTimedOut;
}

pub fn pollDeviceCode(
    gpa: std.mem.Allocator,
    io: std.Io,
    device: *const DeviceAuthInfo,
    abort_flag: ?*const bool,
) !DeviceTokenSuccess {
    return pollDeviceCodeWithOptions(gpa, io, device, abort_flag, .{});
}

pub fn loginDeviceCodeWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    abort_flag: ?*const bool,
    options: bootstrap_http.Options,
) !DeviceLoginResult {
    var device = try requestDeviceAuthorizationWithOptions(gpa, io, options);
    errdefer device.deinit(gpa);
    var success = try pollDeviceCodeWithOptions(gpa, io, &device, abort_flag, options);
    defer success.deinit(gpa);
    const token = try exchangeAuthorizationCodeWithOptions(gpa, io, success.authorization_code, success.code_verifier, DEVICE_REDIRECT_URI, options);
    return .{ .device = device, .token = token };
}

pub fn loginDeviceCode(
    gpa: std.mem.Allocator,
    io: std.Io,
    abort_flag: ?*const bool,
) !DeviceLoginResult {
    return loginDeviceCodeWithOptions(gpa, io, abort_flag, .{});
}

pub fn persistToken(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, token: *const Token) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("openai-codex", .{
        .refresh = token.refresh,
        .access = token.access,
        .expires = token.expires_ms,
        .account_id = token.account_id,
    });
}

test "Codex callback target validates route state code and OAuth errors" {
    const gpa = std.testing.allocator;
    var ok = try parseCallbackTarget(gpa, "/auth/callback?code=abc%2F1&state=expected", "expected");
    defer ok.deinit(gpa);
    try std.testing.expectEqualStrings("abc/1", ok.code);
    try std.testing.expectError(error.OpenAICodexCallbackRouteNotFound, parseCallbackTarget(gpa, "/wrong?code=a&state=expected", "expected"));
    try std.testing.expectError(error.OpenAICodexStateMismatch, parseCallbackTarget(gpa, "/auth/callback?code=a&state=wrong", "expected"));
    try std.testing.expectError(error.OpenAICodexMissingAuthorizationCode, parseCallbackTarget(gpa, "/auth/callback?state=expected", "expected"));
    var denied = try parseCallbackTarget(gpa, "/auth/callback?state=expected&error=access_denied&error_description=No%20thanks", "expected");
    defer denied.deinit(gpa);
    try std.testing.expectEqualStrings("No thanks", denied.oauth_error);
}

test "Codex callback host respects PI_OAUTH_CALLBACK_HOST" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PI_OAUTH_CALLBACK_HOST", "127.0.0.2");
    try std.testing.expectEqualStrings("127.0.0.2", callbackHost(&env));
    try std.testing.expectEqualStrings("127.0.0.1", callbackHost(null));
}

fn b64urlJsonAlloc(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    return pkce_mod.base64UrlNoPadAlloc(gpa, raw);
}

fn makeTestJwt(gpa: std.mem.Allocator, account: []const u8) ![]u8 {
    const header = try b64urlJsonAlloc(gpa, "{\"alg\":\"none\"}");
    defer gpa.free(header);
    const payload_json = try std.fmt.allocPrint(gpa, "{{\"{s}\":{{\"chatgpt_account_id\":\"{s}\"}}}}", .{ JWT_CLAIM_PATH, account });
    defer gpa.free(payload_json);
    const payload = try b64urlJsonAlloc(gpa, payload_json);
    defer gpa.free(payload);
    return std.fmt.allocPrint(gpa, "{s}.{s}.sig", .{ header, payload });
}

test "Codex browser flow uses exact upstream PKCE authorization parameters" {
    const gpa = std.testing.allocator;
    var pair = try pkce_mod.generate(gpa, std.testing.io);
    defer pair.deinit(gpa);
    const state = try pkce_mod.generateHexState(gpa, std.testing.io);
    defer gpa.free(state);
    const url = try buildAuthorizationUrl(gpa, pair.challenge, state, "pi");
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, AUTHORIZE_URL ++ "?response_type=code"));
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=app_EMoamEEZ73f0CkXaXp7hrann") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "scope=openid%20profile%20email%20offline_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "id_token_add_organizations=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "codex_cli_simplified_flow=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "originator=pi") != null);
}

test "Codex authorization input accepts redirect query hash pair and raw code" {
    const gpa = std.testing.allocator;
    var url = try parseAuthorizationInput(gpa, " http://localhost:1455/auth/callback?code=a%2Fb&state=s%20t ");
    defer url.deinit(gpa);
    try std.testing.expectEqualStrings("a/b", url.code.?);
    try std.testing.expectEqualStrings("s t", url.state.?);

    var pair = try parseAuthorizationInput(gpa, "code-1#state-1");
    defer pair.deinit(gpa);
    try std.testing.expectEqualStrings("code-1", pair.code.?);
    try std.testing.expectEqualStrings("state-1", pair.state.?);

    var query = try parseAuthorizationInput(gpa, "code=q&state=r");
    defer query.deinit(gpa);
    try std.testing.expectEqualStrings("q", query.code.?);

    var raw = try parseAuthorizationInput(gpa, "just-the-code");
    defer raw.deinit(gpa);
    try std.testing.expectEqualStrings("just-the-code", raw.code.?);
}

test "Codex token parser extracts ChatGPT account id and absolute expiry" {
    const gpa = std.testing.allocator;
    const jwt = try makeTestJwt(gpa, "acct-456");
    defer gpa.free(jwt);
    const body = try std.fmt.allocPrint(gpa, "{{\"access_token\":\"{s}\",\"refresh_token\":\"refresh-token\",\"expires_in\":3600}}", .{jwt});
    defer gpa.free(body);
    var token = try parseToken(gpa, body, 1_000);
    defer token.deinit(gpa);
    try std.testing.expectEqualStrings("acct-456", token.account_id);
    try std.testing.expectEqual(@as(i64, 3_601_000), token.expires_ms);
}

test "Codex exchange refresh and device request bodies match upstream" {
    const gpa = std.testing.allocator;
    const exchange = try buildAuthorizationCodeForm(gpa, "c +/=", "v/1", REDIRECT_URI);
    defer gpa.free(exchange);
    try std.testing.expectEqualStrings(
        "grant_type=authorization_code&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code=c%20%2B%2F%3D&code_verifier=v%2F1&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback",
        exchange,
    );
    const refresh_form = try buildRefreshForm(gpa, "r +/=");
    defer gpa.free(refresh_form);
    try std.testing.expectEqualStrings("grant_type=refresh_token&refresh_token=r%20%2B%2F%3D&client_id=app_EMoamEEZ73f0CkXaXp7hrann", refresh_form);
    const user_code = try buildDeviceUserCodeJson(gpa);
    defer gpa.free(user_code);
    try std.testing.expectEqualStrings("{\"client_id\":\"app_EMoamEEZ73f0CkXaXp7hrann\"}", user_code);
}

test "Codex device auth accepts string interval and 403 404 pending semantics" {
    const gpa = std.testing.allocator;
    var device = try parseDeviceAuthInfo(gpa, "{\"device_auth_id\":\"d\",\"user_code\":\"ABCD-1234\",\"interval\":\"5\"}");
    defer device.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 5), device.interval_seconds);

    var a = try classifyDevicePoll(gpa, 403, "{\"error\":\"access_denied\"}");
    defer a.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(a) == .pending);
    var b = try classifyDevicePoll(gpa, 404, "not ready");
    defer b.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(b) == .pending);
    var c = try classifyDevicePoll(gpa, 400, "{\"error\":{\"code\":\"deviceauth_authorization_pending\"}}");
    defer c.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(c) == .pending);
    var d = try classifyDevicePoll(gpa, 429, "{\"error\":\"slow_down\"}");
    defer d.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(d) == .slow_down);
}

test "Codex successful device poll owns authorization code and verifier" {
    const gpa = std.testing.allocator;
    var attempt = try classifyDevicePoll(gpa, 200, "{\"authorization_code\":\"oauth-code\",\"code_verifier\":\"device-code-verifier\"}");
    defer attempt.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(attempt) == .complete);
    try std.testing.expectEqualStrings("oauth-code", attempt.complete.authorization_code);
    try std.testing.expectEqualStrings("device-code-verifier", attempt.complete.code_verifier);
}

test "Codex device polling uses immediate minimum cadence and slow down increment" {
    try std.testing.expectEqual(@as(u64, 1000), nextDevicePollIntervalMs(0, .pending));
    try std.testing.expectEqual(@as(u64, 6000), nextDevicePollIntervalMs(1000, .slow_down));
    try std.testing.expectEqual(@as(u64, 10_000), nextDevicePollIntervalMs(10_000, .pending));
}

test "Codex token persistence keeps accountId" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    var token = Token{
        .access = try gpa.dupe(u8, "access"),
        .refresh = try gpa.dupe(u8, "refresh"),
        .expires_ms = 1234,
        .account_id = try gpa.dupe(u8, "acct-99"),
    };
    defer token.deinit(gpa);
    try persistToken(gpa, io, path_buf[0..n], &token);
    var store = try storage.AuthStorage.init(gpa, io, path_buf[0..n]);
    defer store.deinit();
    var credential = (try store.read("openai-codex")).?;
    defer credential.deinit(gpa);
    try std.testing.expectEqualStrings("acct-99", credential.oauth.account_id.?);
}
