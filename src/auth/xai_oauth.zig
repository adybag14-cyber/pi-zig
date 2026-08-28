//! Native xAI OAuth device-code flow for Grok/X subscriptions.
const std = @import("std");
const storage = @import("storage.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

pub const CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828";
pub const SCOPE = "openid profile email offline_access grok-cli:access api:access";
pub const DEVICE_CODE_URL = "https://auth.x.ai/oauth2/device/code";
pub const TOKEN_URL = "https://auth.x.ai/oauth2/token";
pub const REFRESH_SKEW_MS: i64 = 5 * 60 * 1000;
pub const DEFAULT_TOKEN_LIFETIME_SECONDS: u64 = 3600;
pub const DEFAULT_POLL_INTERVAL_SECONDS: u64 = 5;
const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";

pub const DeviceAuthorization = struct {
    device_code: []u8,
    user_code: []u8,
    verification_uri: []u8,
    verification_uri_complete: ?[]u8 = null,
    interval_seconds: ?u64 = null,
    expires_in_seconds: u64,
    pub fn deinit(self: *DeviceAuthorization, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.user_code);
        gpa.free(self.verification_uri);
        if (self.verification_uri_complete) |value| gpa.free(value);
        self.* = undefined;
    }
    pub fn browserUri(self: *const DeviceAuthorization) []const u8 {
        return self.verification_uri_complete orelse self.verification_uri;
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

pub const PollAttempt = union(enum) {
    complete: Token,
    pending,
    slow_down: ?u64,
    denied,
    expired,
    failed: []u8,
    pub fn deinit(self: *PollAttempt, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*token| token.deinit(gpa),
            .failed => |message| gpa.free(message),
            else => {},
        }
        self.* = undefined;
    }
};

fn formEncode(w: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') try w.writeByte(c) else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}
fn field(w: *std.Io.Writer, first: *bool, name: []const u8, value: []const u8) !void {
    if (!first.*) try w.writeByte('&');
    first.* = false;
    try formEncode(w, name);
    try w.writeByte('=');
    try formEncode(w, value);
}

pub fn buildDeviceAuthorizationForm(gpa: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    try field(&out.writer, &first, "client_id", CLIENT_ID);
    try field(&out.writer, &first, "scope", SCOPE);
    try field(&out.writer, &first, "referrer", "pi");
    return out.toOwnedSlice();
}
pub fn buildDeviceTokenForm(gpa: std.mem.Allocator, device_code: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    try field(&out.writer, &first, "grant_type", DEVICE_GRANT);
    try field(&out.writer, &first, "client_id", CLIENT_ID);
    try field(&out.writer, &first, "device_code", device_code);
    return out.toOwnedSlice();
}
pub fn buildRefreshForm(gpa: std.mem.Allocator, refresh_token: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    try field(&out.writer, &first, "grant_type", "refresh_token");
    try field(&out.writer, &first, "client_id", CLIENT_ID);
    try field(&out.writer, &first, "refresh_token", refresh_token);
    return out.toOwnedSlice();
}

fn requiredString(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.InvalidXaiOAuthResponse;
    if (value != .string or value.string.len == 0) return error.InvalidXaiOAuthResponse;
    return value.string;
}
fn positiveSeconds(value: std.json.Value, fallback: u64) u64 {
    return switch (value) {
        .integer => |n| if (n > 0) @intCast(n) else fallback,
        .float => |n| if (n > 0 and std.math.isFinite(n)) @intFromFloat(n) else fallback,
        else => fallback,
    };
}
fn validateHttps(raw: []const u8) !void {
    const uri = std.Uri.parse(raw) catch return error.UntrustedXaiVerificationUri;
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "https")) return error.UntrustedXaiVerificationUri;
}

pub fn parseDeviceAuthorization(gpa: std.mem.Allocator, body: []const u8) !DeviceAuthorization {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidXaiOAuthResponse;
    const device = try requiredString(parsed.value.object, "device_code");
    const user = try requiredString(parsed.value.object, "user_code");
    const verify = try requiredString(parsed.value.object, "verification_uri");
    try validateHttps(verify);
    const expires_v = parsed.value.object.get("expires_in") orelse return error.InvalidXaiOAuthResponse;
    const expires = positiveSeconds(expires_v, 0);
    if (expires == 0) return error.InvalidXaiOAuthResponse;
    var complete: ?[]u8 = null;
    errdefer if (complete) |v| gpa.free(v);
    if (parsed.value.object.get("verification_uri_complete")) |value| if (value == .string and value.string.len > 0) {
        try validateHttps(value.string);
        complete = try gpa.dupe(u8, value.string);
    };
    const interval: ?u64 = if (parsed.value.object.get("interval")) |value| blk: {
        const seconds = positiveSeconds(value, 0);
        break :blk if (seconds > 0) seconds else null;
    } else null;
    return .{ .device_code = try gpa.dupe(u8, device), .user_code = try gpa.dupe(u8, user), .verification_uri = try gpa.dupe(u8, verify), .verification_uri_complete = complete, .interval_seconds = interval, .expires_in_seconds = expires };
}

pub fn parseTokenResponse(gpa: std.mem.Allocator, body: []const u8, now_ms: i64, previous_refresh: ?[]const u8) !Token {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidXaiOAuthResponse;
    const access = try requiredString(parsed.value.object, "access_token");
    const refresh_source: []const u8 = if (parsed.value.object.get("refresh_token")) |value|
        if (value == .string and value.string.len > 0) value.string else return error.InvalidXaiOAuthResponse
    else
        previous_refresh orelse return error.InvalidXaiOAuthResponse;
    const lifetime = if (parsed.value.object.get("expires_in")) |value| positiveSeconds(value, 0) else DEFAULT_TOKEN_LIFETIME_SECONDS;
    if (lifetime == 0) return error.InvalidXaiOAuthResponse;
    return .{
        .access = try gpa.dupe(u8, access),
        .refresh = try gpa.dupe(u8, refresh_source),
        .expires_ms = now_ms + @as(i64, @intCast(lifetime * 1000)) - REFRESH_SKEW_MS,
    };
}

fn errorPair(gpa: std.mem.Allocator, object: std.json.ObjectMap, action: []const u8, status: u16) ![]u8 {
    const error_value = if (object.get("error")) |v| if (v == .string) v.string else "" else "";
    const description = if (object.get("error_description")) |v| if (v == .string) v.string else "" else "";
    if (error_value.len > 0 and description.len > 0) return std.fmt.allocPrint(gpa, "xAI OAuth {s} failed (HTTP {d}): {s}: {s}", .{ action, status, error_value, description });
    if (error_value.len > 0) return std.fmt.allocPrint(gpa, "xAI OAuth {s} failed (HTTP {d}): {s}", .{ action, status, error_value });
    if (description.len > 0) return std.fmt.allocPrint(gpa, "xAI OAuth {s} failed (HTTP {d}): {s}", .{ action, status, description });
    return std.fmt.allocPrint(gpa, "xAI OAuth {s} failed (HTTP {d})", .{ action, status });
}

pub fn classifyPoll(gpa: std.mem.Allocator, status: u16, body: []const u8, now_ms: i64) !PollAttempt {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .failed = try std.fmt.allocPrint(gpa, "xAI OAuth returned invalid JSON (HTTP {d})", .{status}) };
    defer parsed.deinit();
    if (status >= 200 and status < 300) return .{ .complete = try parseTokenResponse(gpa, body, now_ms, null) };
    if (parsed.value != .object) return .{ .failed = try std.fmt.allocPrint(gpa, "xAI OAuth device token polling failed (HTTP {d})", .{status}) };
    const err = if (parsed.value.object.get("error")) |v| if (v == .string) v.string else "" else "";
    if (std.mem.eql(u8, err, "authorization_pending")) return .pending;
    if (std.mem.eql(u8, err, "slow_down")) return .{ .slow_down = if (parsed.value.object.get("interval")) |v| blk: {
        const n = positiveSeconds(v, 0);
        break :blk if (n > 0) n else null;
    } else null };
    if (std.mem.eql(u8, err, "access_denied") or std.mem.eql(u8, err, "authorization_denied")) return .denied;
    if (std.mem.eql(u8, err, "expired_token")) return .expired;
    return .{ .failed = try errorPair(gpa, parsed.value.object, "device token polling", status) };
}

const HttpResponse = struct { status: u16, body: []u8 };

fn postFormWithOptions(gpa: std.mem.Allocator, io: std.Io, url: []const u8, form: []const u8, options: bootstrap_http.Options) !HttpResponse {
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .POST,
        .payload = form,
        .headers = &.{
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        },
        .options = options,
    });
    errdefer response.deinit(gpa);
    return .{ .status = response.status, .body = response.body };
}

pub fn requestDeviceAuthorization(gpa: std.mem.Allocator, io: std.Io) !DeviceAuthorization {
    return requestDeviceAuthorizationWithOptions(gpa, io, .{});
}

pub fn requestDeviceAuthorizationWithOptions(gpa: std.mem.Allocator, io: std.Io, options: bootstrap_http.Options) !DeviceAuthorization {
    const form = try buildDeviceAuthorizationForm(gpa);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, DEVICE_CODE_URL, form, options);
    defer gpa.free(response.body);
    if (response.status < 200 or response.status >= 300) {
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.body, .{}) catch return error.XaiDeviceAuthorizationFailed;
        defer parsed.deinit();
        if (parsed.value != .object) return error.XaiDeviceAuthorizationFailed;
        const detail = try errorPair(gpa, parsed.value.object, "device authorization", response.status);
        defer gpa.free(detail);
        return error.XaiDeviceAuthorizationFailed;
    }
    return parseDeviceAuthorization(gpa, response.body);
}

fn sleepMs(io: std.Io, ms: u64) !void {
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(ms)), .clock = .real } };
    try timeout.sleep(io);
}

pub fn pollDeviceCode(gpa: std.mem.Allocator, io: std.Io, device: *const DeviceAuthorization, abort_flag: ?*const bool) !Token {
    return pollDeviceCodeWithOptions(gpa, io, device, abort_flag, .{});
}

pub fn pollDeviceCodeWithOptions(gpa: std.mem.Allocator, io: std.Io, device: *const DeviceAuthorization, abort_flag: ?*const bool, options_in: bootstrap_http.Options) !Token {
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    var interval_ms = (device.interval_seconds orelse DEFAULT_POLL_INTERVAL_SECONDS) * 1000;
    const deadline = std.Io.Clock.real.now(io).toMilliseconds() + @as(i64, @intCast(device.expires_in_seconds * 1000));
    while (true) {
        var waited: u64 = 0;
        while (waited < interval_ms) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            const step = @min(@as(u64, 100), interval_ms - waited);
            try sleepMs(io, step);
            waited += step;
            if (std.Io.Clock.real.now(io).toMilliseconds() >= deadline) return error.XaiDeviceCodeExpired;
        }
        const form = try buildDeviceTokenForm(gpa, device.device_code);
        defer gpa.free(form);
        const response = try postFormWithOptions(gpa, io, TOKEN_URL, form, options);
        defer gpa.free(response.body);
        var attempt = try classifyPoll(gpa, response.status, response.body, std.Io.Clock.real.now(io).toMilliseconds());
        defer attempt.deinit(gpa);
        switch (attempt) {
            .complete => |*token| {
                const result = token.*;
                attempt = undefined;
                return result;
            },
            .pending => {},
            .slow_down => |suggested| interval_ms = if (suggested) |seconds| seconds * 1000 else interval_ms + 5000,
            .denied => return error.XaiDeviceAuthorizationDenied,
            .expired => return error.XaiDeviceCodeExpired,
            .failed => return error.XaiDeviceTokenPollingFailed,
        }
    }
}

pub fn refresh(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8) !Token {
    return refreshWithOptions(gpa, io, refresh_token, .{});
}

pub fn refreshWithOptions(gpa: std.mem.Allocator, io: std.Io, refresh_token: []const u8, options: bootstrap_http.Options) !Token {
    const form = try buildRefreshForm(gpa, refresh_token);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, TOKEN_URL, form, options);
    defer gpa.free(response.body);
    if (response.status < 200 or response.status >= 300) return error.XaiOAuthRefreshFailed;
    return parseTokenResponse(gpa, response.body, std.Io.Clock.real.now(io).toMilliseconds(), refresh_token);
}

pub fn persistCredential(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, token: *const Token) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("xai", .{ .refresh = token.refresh, .access = token.access, .expires = token.expires_ms });
}

test "xAI OAuth forms use exact client scope referrer and device grant" {
    const gpa = std.testing.allocator;
    const device = try buildDeviceAuthorizationForm(gpa);
    defer gpa.free(device);
    try std.testing.expect(std.mem.indexOf(u8, device, "client_id=b1a00492-073a-47ea-816f-4c329264a828") != null);
    try std.testing.expect(std.mem.indexOf(u8, device, "offline_access") != null);
    try std.testing.expect(std.mem.indexOf(u8, device, "referrer=pi") != null);
    const poll = try buildDeviceTokenForm(gpa, "d +/");
    defer gpa.free(poll);
    try std.testing.expect(std.mem.indexOf(u8, poll, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code") != null);
    try std.testing.expect(std.mem.indexOf(u8, poll, "device_code=d%20%2B%2F") != null);
}

test "xAI OAuth device response requires https and defaults zero interval" {
    const gpa = std.testing.allocator;
    var device = try parseDeviceAuthorization(gpa, "{\"device_code\":\"d\",\"user_code\":\"U\",\"verification_uri\":\"https://accounts.x.ai/oauth2/device\",\"expires_in\":900,\"interval\":0}");
    defer device.deinit(gpa);
    try std.testing.expect(device.interval_seconds == null);
    try std.testing.expectEqualStrings(device.verification_uri, device.browserUri());
    try std.testing.expectError(error.UntrustedXaiVerificationUri, parseDeviceAuthorization(gpa, "{\"device_code\":\"d\",\"user_code\":\"U\",\"verification_uri\":\"file:///etc/passwd\",\"expires_in\":900}"));
}

test "xAI OAuth token expiry skew and refresh preservation match upstream" {
    const gpa = std.testing.allocator;
    var token = try parseTokenResponse(gpa, "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":21600}", 1000, null);
    defer token.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 1000 + 21_600_000 - 300_000), token.expires_ms);
    var preserved = try parseTokenResponse(gpa, "{\"access_token\":\"b\"}", 1000, "old-r");
    defer preserved.deinit(gpa);
    try std.testing.expectEqualStrings("old-r", preserved.refresh);
    try std.testing.expectEqual(@as(i64, 1000 + 3_600_000 - 300_000), preserved.expires_ms);
}

test "xAI OAuth poll classification handles pending slowdown denial and expiry" {
    const gpa = std.testing.allocator;
    var pending = try classifyPoll(gpa, 400, "{\"error\":\"authorization_pending\"}", 0);
    defer pending.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(pending) == .pending);
    var slow = try classifyPoll(gpa, 400, "{\"error\":\"slow_down\",\"interval\":10}", 0);
    defer slow.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 10), slow.slow_down);
    var denied = try classifyPoll(gpa, 400, "{\"error\":\"authorization_denied\"}", 0);
    defer denied.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(denied) == .denied);
    var expired = try classifyPoll(gpa, 400, "{\"error\":\"expired_token\"}", 0);
    defer expired.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(expired) == .expired);
}
