//! Radius OAuth protocol helpers and refresh transport.
const std = @import("std");
const builtin = @import("builtin");
const net = std.Io.net;
const radius_config = @import("../ai/radius_config.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const storage = @import("storage.zig");
const pkce_mod = @import("pkce.zig");

pub const CLIENT_ID = "pi-gateway";
pub const SCOPE = "gateway offline_access";
pub const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";
pub const TOKEN_EXPIRY_SKEW_MS: i64 = 60_000;
pub const CALLBACK_HOST = "127.0.0.1";
pub const CALLBACK_PORT: u16 = 1456;
pub const CALLBACK_PATH = "/oauth/callback";
pub const REDIRECT_URI = "http://127.0.0.1:1456/oauth/callback";

pub const Pkce = pkce_mod.Pkce;

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

pub const Discovery = struct {
    authorization_endpoint: []u8,
    pub fn deinit(self: *Discovery, gpa: std.mem.Allocator) void {
        gpa.free(self.authorization_endpoint);
        self.* = undefined;
    }
};

pub const Token = struct {
    access: []u8,
    refresh: []u8,
    expires_ms: i64,
    scope: ?[]u8 = null,
    pub fn deinit(self: *Token, gpa: std.mem.Allocator) void {
        gpa.free(self.access);
        gpa.free(self.refresh);
        if (self.scope) |v| gpa.free(v);
        self.* = undefined;
    }
};

pub const DeviceAuthorization = struct {
    device_code: []u8,
    user_code: []u8,
    verification_uri: []u8,
    expires_in: u64,
    interval: u64 = 5,
    pub fn deinit(self: *DeviceAuthorization, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.user_code);
        gpa.free(self.verification_uri);
        self.* = undefined;
    }
};

pub const OAuthError = struct {
    code: ?[]u8 = null,
    description: ?[]u8 = null,
    pub fn deinit(self: *OAuthError, gpa: std.mem.Allocator) void {
        if (self.code) |v| gpa.free(v);
        if (self.description) |v| gpa.free(v);
        self.* = undefined;
    }
};

pub const TokenAttempt = union(enum) {
    complete: Token,
    pending,
    slow_down,
    expired,
    denied,
    oauth_error: OAuthError,

    pub fn deinit(self: *TokenAttempt, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*token| token.deinit(gpa),
            .oauth_error => |*err| err.deinit(gpa),
            else => {},
        }
        self.* = undefined;
    }
};

fn dupString(gpa: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) !?[]u8 {
    const value = obj.get(name) orelse return null;
    if (value != .string or value.string.len == 0) return null;
    return try gpa.dupe(u8, value.string);
}

fn positiveU64(value: std.json.Value) ?u64 {
    return switch (value) {
        .integer => |n| if (n > 0) @intCast(n) else null,
        .float => |n| if (n > 0 and std.math.isFinite(n)) @intFromFloat(n) else null,
        else => null,
    };
}

pub fn parseDiscovery(gpa: std.mem.Allocator, raw: []const u8) !Discovery {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRadiusOAuthDiscovery;
    return .{ .authorization_endpoint = (try dupString(gpa, parsed.value.object, "authorizationEndpoint")) orelse return error.InvalidRadiusOAuthDiscovery };
}

pub fn parseToken(gpa: std.mem.Allocator, raw: []const u8, now_ms: i64) !Token {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRadiusOAuthToken;
    const obj = parsed.value.object;
    const access = (try dupString(gpa, obj, "access_token")) orelse return error.InvalidRadiusOAuthToken;
    errdefer gpa.free(access);
    const refresh_value = (try dupString(gpa, obj, "refresh_token")) orelse return error.InvalidRadiusOAuthToken;
    errdefer gpa.free(refresh_value);
    const expires_value = obj.get("expires_in") orelse return error.InvalidRadiusOAuthToken;
    const expires_in = positiveU64(expires_value) orelse return error.InvalidRadiusOAuthToken;
    const scope = try dupString(gpa, obj, "scope");
    errdefer if (scope) |v| gpa.free(v);
    const raw_expiry = now_ms + @as(i64, @intCast(expires_in)) * 1000;
    return .{
        .access = access,
        .refresh = refresh_value,
        .expires_ms = @max(now_ms, raw_expiry - TOKEN_EXPIRY_SKEW_MS),
        .scope = scope,
    };
}

pub fn parseDeviceAuthorization(gpa: std.mem.Allocator, raw: []const u8) !DeviceAuthorization {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRadiusDeviceAuthorization;
    const obj = parsed.value.object;
    const device_code = (try dupString(gpa, obj, "device_code")) orelse return error.InvalidRadiusDeviceAuthorization;
    errdefer gpa.free(device_code);
    const user_code = (try dupString(gpa, obj, "user_code")) orelse return error.InvalidRadiusDeviceAuthorization;
    errdefer gpa.free(user_code);
    const verification_uri = (try dupString(gpa, obj, "verification_uri")) orelse return error.InvalidRadiusDeviceAuthorization;
    errdefer gpa.free(verification_uri);
    const expires_in = positiveU64(obj.get("expires_in") orelse return error.InvalidRadiusDeviceAuthorization) orelse return error.InvalidRadiusDeviceAuthorization;
    var interval: u64 = 5;
    if (obj.get("interval")) |value| interval = positiveU64(value) orelse interval;
    return .{
        .device_code = device_code,
        .user_code = user_code,
        .verification_uri = verification_uri,
        .expires_in = expires_in,
        .interval = interval,
    };
}

pub fn parseOAuthError(gpa: std.mem.Allocator, raw: []const u8) !OAuthError {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return .{ .description = if (raw.len > 0) try gpa.dupe(u8, raw) else null };
    defer parsed.deinit();
    if (parsed.value != .object) return .{ .description = if (raw.len > 0) try gpa.dupe(u8, raw) else null };
    return .{
        .code = try dupString(gpa, parsed.value.object, "error"),
        .description = try dupString(gpa, parsed.value.object, "error_description"),
    };
}

pub fn classifyTokenResponse(gpa: std.mem.Allocator, status: u16, raw: []const u8, now_ms: i64) !TokenAttempt {
    if (status >= 200 and status < 300) return .{ .complete = try parseToken(gpa, raw, now_ms) };
    var oauth_error = try parseOAuthError(gpa, raw);
    if (oauth_error.code) |code| {
        if (std.mem.eql(u8, code, "authorization_pending")) {
            oauth_error.deinit(gpa);
            return .pending;
        }
        if (std.mem.eql(u8, code, "slow_down")) {
            oauth_error.deinit(gpa);
            return .slow_down;
        }
        if (std.mem.eql(u8, code, "expired_token")) {
            oauth_error.deinit(gpa);
            return .expired;
        }
        if (std.mem.eql(u8, code, "access_denied")) {
            oauth_error.deinit(gpa);
            return .denied;
        }
    }
    return .{ .oauth_error = oauth_error };
}

pub fn nextPollIntervalMs(current_ms: u64, attempt: TokenAttempt) u64 {
    return switch (attempt) {
        .slow_down => @max(@as(u64, 1000), current_ms + 5000),
        else => @max(@as(u64, 1000), current_ms),
    };
}

fn formEncode(w: *std.Io.Writer, input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') try w.writeByte(c) else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

pub fn generatePkce(gpa: std.mem.Allocator, io: std.Io) !Pkce {
    return pkce_mod.generate(gpa, io);
}

pub fn generateState(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var raw: [16]u8 = undefined;
    try io.randomSecure(&raw);
    // RFC 4122 version 4 / variant 1, matching crypto.randomUUID() semantics.
    raw[6] = (raw[6] & 0x0f) | 0x40;
    raw[8] = (raw[8] & 0x3f) | 0x80;
    return std.fmt.allocPrint(gpa, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7], raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15] });
}

fn endpointWithoutQueryOrFragment(endpoint: []const u8) []const u8 {
    var end = endpoint.len;
    if (std.mem.indexOfScalar(u8, endpoint, '#')) |i| end = @min(end, i);
    if (std.mem.indexOfScalar(u8, endpoint[0..end], '?')) |i| end = @min(end, i);
    return endpoint[0..end];
}

pub fn buildAuthorizationUrl(gpa: std.mem.Allocator, authorization_endpoint: []const u8, challenge: []const u8, state: []const u8) ![]u8 {
    if (authorization_endpoint.len == 0 or challenge.len == 0 or state.len == 0) return error.InvalidRadiusOAuthAuthorization;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(endpointWithoutQueryOrFragment(authorization_endpoint));
    try out.writer.writeAll("?response_type=code&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&redirect_uri=");
    try formEncode(&out.writer, REDIRECT_URI);
    try out.writer.writeAll("&scope=");
    try formEncode(&out.writer, SCOPE);
    try out.writer.writeAll("&code_challenge=");
    try formEncode(&out.writer, challenge);
    try out.writer.writeAll("&code_challenge_method=S256&handoff=url&state=");
    try formEncode(&out.writer, state);
    return out.toOwnedSlice();
}

pub fn buildAuthorizationCodeForm(gpa: std.mem.Allocator, code: []const u8, verifier: []const u8) ![]u8 {
    if (code.len == 0 or verifier.len == 0) return error.InvalidRadiusOAuthAuthorizationCode;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=authorization_code&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&redirect_uri=");
    try formEncode(&out.writer, REDIRECT_URI);
    try out.writer.writeAll("&code=");
    try formEncode(&out.writer, code);
    try out.writer.writeAll("&code_verifier=");
    try formEncode(&out.writer, verifier);
    return out.toOwnedSlice();
}

fn decodeQueryValue(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const buf = try gpa.dupe(u8, raw);
    errdefer gpa.free(buf);
    for (buf) |*c| {
        if (c.* == '+') c.* = ' ';
    }
    const decoded = std.Uri.percentDecodeInPlace(buf);
    if (decoded.ptr == buf.ptr and decoded.len == buf.len) return buf;
    // std.Uri decodes backwards and returns a tail subslice; compact it before shrinking.
    std.mem.copyForwards(u8, buf[0..decoded.len], decoded);
    return gpa.realloc(buf, decoded.len);
}

fn queryValue(gpa: std.mem.Allocator, query: []const u8, key: []const u8) !?[]u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse pair.len;
        const raw_key = pair[0..eq];
        const raw_value = if (eq < pair.len) pair[eq + 1 ..] else "";
        const decoded_key = try decodeQueryValue(gpa, raw_key);
        defer gpa.free(decoded_key);
        if (std.mem.eql(u8, decoded_key, key)) return try decodeQueryValue(gpa, raw_value);
    }
    return null;
}

pub fn parseCallbackTarget(gpa: std.mem.Allocator, target: []const u8, expected_state: []const u8) !CallbackResult {
    const qmark = std.mem.indexOfScalar(u8, target, '?');
    const fragment = std.mem.indexOfScalar(u8, target, '#') orelse target.len;
    const path_end = if (qmark) |i| @min(i, fragment) else fragment;
    if (!std.mem.eql(u8, target[0..path_end], CALLBACK_PATH)) return error.RadiusOAuthCallbackRouteNotFound;
    const query = if (qmark) |i| target[i + 1 .. fragment] else "";
    const state = try queryValue(gpa, query, "state") orelse return error.RadiusOAuthStateMismatch;
    defer gpa.free(state);
    if (!std.mem.eql(u8, state, expected_state)) return error.RadiusOAuthStateMismatch;
    if (try queryValue(gpa, query, "error")) |oauth_error| {
        if (try queryValue(gpa, query, "error_description")) |description| {
            defer gpa.free(oauth_error);
            return .{ .oauth_error = description };
        }
        return .{ .oauth_error = oauth_error };
    }
    const code = try queryValue(gpa, query, "code") orelse return error.RadiusOAuthMissingAuthorizationCode;
    if (code.len == 0) {
        gpa.free(code);
        return error.RadiusOAuthMissingAuthorizationCode;
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
    if (!std.mem.startsWith(u8, line, "GET ")) return error.InvalidRadiusOAuthCallbackRequest;
    const rest = line[4..];
    const space = std.mem.indexOfScalar(u8, rest, ' ') orelse return error.InvalidRadiusOAuthCallbackRequest;
    if (space == 0) return error.InvalidRadiusOAuthCallbackRequest;
    return rest[0..space];
}

fn writeCallbackHttp(io: std.Io, stream: *net.Stream, status: u16, message: []const u8) !void {
    const status_text: []const u8 = switch (status) {
        200 => "OK",
        404 => "Not Found",
        else => "Bad Request",
    };
    const prefix = "<!doctype html><meta charset=utf-8><title>Radius OAuth</title><body><p>";
    const suffix = "</p><script>if(location.hash==='#close')window.close()</script></body>";
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
                error.RadiusOAuthCallbackRouteNotFound => {
                    try writeCallbackHttp(self.io, &stream, 404, "Callback route not found.");
                    continue;
                },
                error.RadiusOAuthStateMismatch => {
                    try writeCallbackHttp(self.io, &stream, 400, "OAuth state mismatch.");
                    continue;
                },
                error.RadiusOAuthMissingAuthorizationCode => {
                    try writeCallbackHttp(self.io, &stream, 400, "Missing authorization code.");
                    continue;
                },
                else => return err,
            };
            switch (result) {
                .code => {
                    try writeCallbackHttp(self.io, &stream, 200, "Signed in to Radius. You may now close this page.");
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

pub fn startCallbackServer(io: std.Io) !CallbackServer {
    var addr = try net.IpAddress.parseIp4(CALLBACK_HOST, CALLBACK_PORT);
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

pub fn requestAuthorizationCodeToken(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, code: []const u8, verifier: []const u8) !Token {
    return requestAuthorizationCodeTokenWithOptions(gpa, io, gateway, code, verifier, .{});
}

pub fn requestAuthorizationCodeTokenWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, code: []const u8, verifier: []const u8, options: bootstrap_http.Options) !Token {
    const body = try buildAuthorizationCodeForm(gpa, code, verifier);
    defer gpa.free(body);
    return tokenRequestWithOptions(gpa, io, gateway, body, options);
}

pub fn buildRefreshForm(gpa: std.mem.Allocator, refresh_token: []const u8) ![]u8 {
    if (refresh_token.len == 0) return error.InvalidRadiusRefreshToken;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=refresh_token&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&refresh_token=");
    try formEncode(&out.writer, refresh_token);
    return out.toOwnedSlice();
}

pub fn buildDeviceAuthorizationForm(gpa: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&scope=");
    try formEncode(&out.writer, SCOPE);
    return out.toOwnedSlice();
}

pub fn buildDeviceTokenForm(gpa: std.mem.Allocator, device_code: []const u8) ![]u8 {
    if (device_code.len == 0) return error.InvalidRadiusDeviceCode;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("grant_type=");
    try formEncode(&out.writer, DEVICE_GRANT);
    try out.writer.writeAll("&client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&device_code=");
    try formEncode(&out.writer, device_code);
    return out.toOwnedSlice();
}

fn postFormWithOptions(gpa: std.mem.Allocator, io: std.Io, url: []const u8, body_text: []const u8, options: bootstrap_http.Options) !struct { status: u16, body: []u8 } {
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .POST,
        .payload = body_text,
        .headers = &.{
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        },
        .options = options,
    });
    errdefer response.deinit(gpa);
    return .{ .status = response.status, .body = response.body };
}

pub fn requestDeviceAuthorization(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8) !DeviceAuthorization {
    return requestDeviceAuthorizationWithOptions(gpa, io, gateway, .{});
}

pub fn requestDeviceAuthorizationWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, options: bootstrap_http.Options) !DeviceAuthorization {
    const url = try radius_config.endpointUrl(gpa, gateway, "/v1/oauth/device");
    defer gpa.free(url);
    const form = try buildDeviceAuthorizationForm(gpa);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, url, form, options);
    defer gpa.free(response.body);
    if (response.status < 200 or response.status >= 300) return error.RadiusOAuthDeviceAuthorizationHttpError;
    return parseDeviceAuthorization(gpa, response.body);
}

pub fn requestDeviceTokenAttempt(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, device_code: []const u8) !TokenAttempt {
    return requestDeviceTokenAttemptWithOptions(gpa, io, gateway, device_code, .{});
}

pub fn requestDeviceTokenAttemptWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, device_code: []const u8, options: bootstrap_http.Options) !TokenAttempt {
    const url = try radius_config.endpointUrl(gpa, gateway, "/v1/oauth/token");
    defer gpa.free(url);
    const form = try buildDeviceTokenForm(gpa, device_code);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, url, form, options);
    defer gpa.free(response.body);
    return classifyTokenResponse(gpa, response.status, response.body, std.Io.Clock.real.now(io).toMilliseconds());
}

pub fn pollDeviceCode(
    gpa: std.mem.Allocator,
    io: std.Io,
    gateway: []const u8,
    device: *const DeviceAuthorization,
    abort_flag: ?*const bool,
) !Token {
    return pollDeviceCodeWithOptions(gpa, io, gateway, device, abort_flag, .{});
}

pub fn pollDeviceCodeWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    gateway: []const u8,
    device: *const DeviceAuthorization,
    abort_flag: ?*const bool,
    options_in: bootstrap_http.Options,
) !Token {
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    const deadline = std.Io.Clock.real.now(io).toMilliseconds() + @as(i64, @intCast(device.expires_in)) * 1000;
    var interval_ms: u64 = @max(@as(u64, 1000), device.interval * 1000);
    var saw_slow_down = false;
    while (std.Io.Clock.real.now(io).toMilliseconds() < deadline) {
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
        if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
        var attempt = try requestDeviceTokenAttemptWithOptions(gpa, io, gateway, device.device_code, options);
        switch (attempt) {
            .complete => |token| return token,
            .pending => {},
            .slow_down => {
                saw_slow_down = true;
                interval_ms = nextPollIntervalMs(interval_ms, .slow_down);
            },
            .expired => return error.DeviceAuthorizationExpired,
            .denied => return error.DeviceAuthorizationDenied,
            .oauth_error => {
                attempt.deinit(gpa);
                return error.RadiusOAuthTokenHttpError;
            },
        }
        attempt.deinit(gpa);
        const remaining = deadline - std.Io.Clock.real.now(io).toMilliseconds();
        if (remaining <= 0) break;
        const sleep_ms: u64 = @min(interval_ms, @as(u64, @intCast(remaining)));
        var elapsed: u64 = 0;
        while (elapsed < sleep_ms) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            const step = @min(@as(u64, 100), sleep_ms - elapsed);
            const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(step)), .clock = .real } };
            try timeout.sleep(io);
            elapsed += step;
        }
    }
    return if (saw_slow_down) error.DeviceFlowTimedOutAfterSlowDown else error.DeviceFlowTimedOut;
}

pub fn persistToken(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, provider_id: []const u8, token: *const Token) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth(provider_id, .{
        .refresh = token.refresh,
        .access = token.access,
        .expires = token.expires_ms,
        .scope = token.scope,
    });
}

fn tokenRequestWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, body_text: []const u8, options: bootstrap_http.Options) !Token {
    const url = try radius_config.endpointUrl(gpa, gateway, "/v1/oauth/token");
    defer gpa.free(url);
    const response = try postFormWithOptions(gpa, io, url, body_text, options);
    defer gpa.free(response.body);
    var attempt = try classifyTokenResponse(gpa, response.status, response.body, std.Io.Clock.real.now(io).toMilliseconds());
    switch (attempt) {
        .complete => |token| return token,
        else => {
            attempt.deinit(gpa);
            return error.RadiusOAuthTokenHttpError;
        },
    }
}

pub fn refresh(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, refresh_token: []const u8) !Token {
    return refreshWithOptions(gpa, io, gateway, refresh_token, .{});
}

pub fn refreshWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, refresh_token: []const u8, options: bootstrap_http.Options) !Token {
    const body = try buildRefreshForm(gpa, refresh_token);
    defer gpa.free(body);
    return tokenRequestWithOptions(gpa, io, gateway, body, options);
}

pub fn loadDiscovery(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8) !Discovery {
    return loadDiscoveryWithOptions(gpa, io, gateway, .{});
}

pub fn loadDiscoveryWithOptions(gpa: std.mem.Allocator, io: std.Io, gateway: []const u8, options: bootstrap_http.Options) !Discovery {
    const url = try radius_config.endpointUrl(gpa, gateway, "/v1/oauth");
    defer gpa.free(url);
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .GET,
        .headers = &.{.{ .name = "accept", .value = "application/json" }},
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.RadiusOAuthDiscoveryHttpError;
    return parseDiscovery(gpa, response.body);
}

test "Radius OAuth discovery/token/device protocol parses upstream shapes" {
    const gpa = std.testing.allocator;
    var discovery = try parseDiscovery(gpa, "{\"authorizationEndpoint\":\"https://login.example/authorize\"}");
    defer discovery.deinit(gpa);
    try std.testing.expectEqualStrings("https://login.example/authorize", discovery.authorization_endpoint);
    var token = try parseToken(gpa, "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":3600,\"scope\":\"gateway offline_access\"}", 1_000_000);
    defer token.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 4_540_000), token.expires_ms);
    var device = try parseDeviceAuthorization(gpa, "{\"device_code\":\"d\",\"user_code\":\"ABCD\",\"verification_uri\":\"https://login.example/device\",\"expires_in\":900,\"interval\":7}");
    defer device.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 7), device.interval);
}

test "Radius OAuth forms are percent encoded and exact" {
    const gpa = std.testing.allocator;
    const refresh_form = try buildRefreshForm(gpa, "r +/=x");
    defer gpa.free(refresh_form);
    try std.testing.expectEqualStrings("grant_type=refresh_token&client_id=pi-gateway&refresh_token=r%20%2B%2F%3Dx", refresh_form);
    const device_form = try buildDeviceAuthorizationForm(gpa);
    defer gpa.free(device_form);
    try std.testing.expectEqualStrings("client_id=pi-gateway&scope=gateway%20offline_access", device_form);
    const token_form = try buildDeviceTokenForm(gpa, "dev/code");
    defer gpa.free(token_form);
    try std.testing.expect(std.mem.indexOf(u8, token_form, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code") != null);
}

test "Radius device token classification follows RFC 8628 states" {
    const gpa = std.testing.allocator;
    const Tag = std.meta.Tag(TokenAttempt);
    const cases = [_]struct { raw: []const u8, tag: Tag }{
        .{ .raw = "{\"error\":\"authorization_pending\"}", .tag = .pending },
        .{ .raw = "{\"error\":\"slow_down\"}", .tag = .slow_down },
        .{ .raw = "{\"error\":\"expired_token\"}", .tag = .expired },
        .{ .raw = "{\"error\":\"access_denied\"}", .tag = .denied },
        .{ .raw = "{\"error\":\"invalid_client\",\"error_description\":\"bad\"}", .tag = .oauth_error },
    };
    for (cases) |case| {
        var attempt = try classifyTokenResponse(gpa, 400, case.raw, 1000);
        defer attempt.deinit(gpa);
        try std.testing.expectEqual(case.tag, std.meta.activeTag(attempt));
    }
    var complete = try classifyTokenResponse(gpa, 200, "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":120}", 1000);
    defer complete.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(complete) == .complete);
    try std.testing.expectEqual(@as(u64, 6000), nextPollIntervalMs(1000, .slow_down));
}

test "Radius persisted OAuth token preserves optional scope" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    var token = try parseToken(gpa, "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":120,\"scope\":\"gateway offline_access\"}", 1000);
    defer token.deinit(gpa);
    try persistToken(gpa, io, root, "radius-dev", &token);
    var store = try storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    var credential = (try store.read("radius-dev")).?;
    defer credential.deinit(gpa);
    try std.testing.expectEqualStrings("gateway offline_access", credential.oauth.scope.?);
}

test "Radius browser OAuth PKCE and callback protocol" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var pkce = try generatePkce(gpa, io);
    defer pkce.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 43), pkce.verifier.len);
    try std.testing.expectEqual(@as(usize, 43), pkce.challenge.len);
    try std.testing.expect(std.mem.indexOfAny(u8, pkce.verifier, "+/=") == null);
    const state = try generateState(gpa, io);
    defer gpa.free(state);
    try std.testing.expectEqual(@as(usize, 36), state.len);
    const url = try buildAuthorizationUrl(gpa, "https://login.example/authorize?old=1#frag", pkce.challenge, state);
    defer gpa.free(url);
    try std.testing.expect(std.mem.startsWith(u8, url, "https://login.example/authorize?response_type=code&client_id=pi-gateway"));
    try std.testing.expect(std.mem.indexOf(u8, url, "redirect_uri=http%3A%2F%2F127.0.0.1%3A1456%2Foauth%2Fcallback") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256&handoff=url&state=") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "old=1") == null);

    const form = try buildAuthorizationCodeForm(gpa, "a/b+c", pkce.verifier);
    defer gpa.free(form);
    try std.testing.expect(std.mem.indexOf(u8, form, "grant_type=authorization_code&client_id=pi-gateway") == 0);
    try std.testing.expect(std.mem.indexOf(u8, form, "code=a%2Fb%2Bc") != null);
    try std.testing.expect(std.mem.indexOf(u8, form, "code_verifier=") != null);

    const target = try std.fmt.allocPrint(gpa, "/oauth/callback?state={s}&code=abc%2F123", .{state});
    defer gpa.free(target);
    var callback = try parseCallbackTarget(gpa, target, state);
    defer callback.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(callback) == .code);
    try std.testing.expectEqualStrings("abc/123", callback.code);
}

test "Radius browser OAuth callback validates route state and errors" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.RadiusOAuthCallbackRouteNotFound, parseCallbackTarget(gpa, "/wrong?state=s&code=c", "s"));
    try std.testing.expectError(error.RadiusOAuthStateMismatch, parseCallbackTarget(gpa, "/oauth/callback?state=bad&code=c", "good"));
    try std.testing.expectError(error.RadiusOAuthMissingAuthorizationCode, parseCallbackTarget(gpa, "/oauth/callback?state=s", "s"));
    var callback = try parseCallbackTarget(gpa, "/oauth/callback?state=s&error=access_denied&error_description=No+thanks", "s");
    defer callback.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(callback) == .oauth_error);
    try std.testing.expectEqualStrings("No thanks", callback.oauth_error);
}

test "Radius callback HTTP request target parsing" {
    try std.testing.expectEqualStrings("/oauth/callback?state=x&code=y", try callbackTargetFromRequest("GET /oauth/callback?state=x&code=y HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"));
    try std.testing.expectError(error.InvalidRadiusOAuthCallbackRequest, callbackTargetFromRequest("POST /oauth/callback HTTP/1.1\r\n\r\n"));
}
