//! Native Kimi Code subscription OAuth (RFC 8628 device flow).
const std = @import("std");
const storage = @import("storage.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");

pub const CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098";
pub const DEFAULT_OAUTH_HOST = "https://auth.kimi.com";
pub const DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code";
pub const DEVICE_CODE_TIMEOUT_SECONDS: u64 = 15 * 60;
pub const DEFAULT_POLL_INTERVAL_SECONDS: u64 = 5;
pub const REFRESH_MAX_RETRIES: u32 = 3;
pub const REQUEST_TIMEOUT_MS: u64 = 30_000;
pub const API_BASE_URL = "https://api.kimi.com/coding";

pub const DeviceAuthorization = struct {
    device_code: []u8,
    user_code: []u8,
    verification_uri: []u8,
    verification_uri_complete: []u8,
    interval_seconds: u64,
    expires_in_seconds: u64,
    pub fn deinit(self: *DeviceAuthorization, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.user_code);
        gpa.free(self.verification_uri);
        gpa.free(self.verification_uri_complete);
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

pub const PollAttempt = union(enum) {
    complete: Token,
    pending,
    slow_down: ?u64,
    expired,
    denied,
    failed: []u8,
    pub fn deinit(self: *PollAttempt, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*v| v.deinit(gpa),
            .failed => |v| gpa.free(v),
            else => {},
        }
        self.* = undefined;
    }
};

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

pub fn oauthHost(environ: ?*const std.process.Environ.Map) []const u8 {
    if (environ) |env| {
        if (env.get("KIMI_CODE_OAUTH_HOST")) |v| if (std.mem.trim(u8, v, " \t\r\n").len > 0) return std.mem.trimEnd(u8, std.mem.trim(u8, v, " \t\r\n"), "/");
        if (env.get("KIMI_OAUTH_HOST")) |v| if (std.mem.trim(u8, v, " \t\r\n").len > 0) return std.mem.trimEnd(u8, std.mem.trim(u8, v, " \t\r\n"), "/");
    }
    return DEFAULT_OAUTH_HOST;
}

fn trustedHttpUrl(value: []const u8) bool {
    const uri = std.Uri.parse(value) catch return false;
    const scheme = uri.scheme;
    if (scheme.len == 0) return false;
    return std.ascii.eqlIgnoreCase(scheme, "https") or std.ascii.eqlIgnoreCase(scheme, "http");
}

pub fn buildDeviceAuthorizationForm(gpa: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    return out.toOwnedSlice();
}

pub fn buildDeviceTokenForm(gpa: std.mem.Allocator, device_code: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&device_code=");
    try formEncode(&out.writer, device_code);
    try out.writer.writeAll("&grant_type=");
    try formEncode(&out.writer, DEVICE_GRANT);
    return out.toOwnedSlice();
}

pub fn buildRefreshForm(gpa: std.mem.Allocator, refresh_token: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&grant_type=refresh_token&refresh_token=");
    try formEncode(&out.writer, refresh_token);
    return out.toOwnedSlice();
}

fn positiveSeconds(value: ?std.json.Value, fallback: u64) u64 {
    const v = value orelse return fallback;
    return switch (v) {
        .integer => |n| if (n > 0) @intCast(n) else fallback,
        .float => |n| if (n > 0 and std.math.isFinite(n)) @intFromFloat(n) else fallback,
        else => fallback,
    };
}

pub fn parseDeviceAuthorization(gpa: std.mem.Allocator, body: []const u8) !DeviceAuthorization {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidKimiDeviceAuthorization;
    const dc = parsed.value.object.get("device_code") orelse return error.InvalidKimiDeviceAuthorization;
    const uc = parsed.value.object.get("user_code") orelse return error.InvalidKimiDeviceAuthorization;
    const vu = parsed.value.object.get("verification_uri") orelse return error.InvalidKimiDeviceAuthorization;
    const vc = parsed.value.object.get("verification_uri_complete") orelse return error.InvalidKimiDeviceAuthorization;
    if (dc != .string or uc != .string or vu != .string or vc != .string or !trustedHttpUrl(vu.string) or !trustedHttpUrl(vc.string)) return error.InvalidKimiDeviceAuthorization;
    return .{
        .device_code = try gpa.dupe(u8, dc.string),
        .user_code = try gpa.dupe(u8, uc.string),
        .verification_uri = try gpa.dupe(u8, vu.string),
        .verification_uri_complete = try gpa.dupe(u8, vc.string),
        .interval_seconds = positiveSeconds(parsed.value.object.get("interval"), DEFAULT_POLL_INTERVAL_SECONDS),
        .expires_in_seconds = positiveSeconds(parsed.value.object.get("expires_in"), DEVICE_CODE_TIMEOUT_SECONDS),
    };
}

pub fn parseTokenResponse(gpa: std.mem.Allocator, body: []const u8, now_ms: i64) !Token {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidKimiToken;
    const av = parsed.value.object.get("access_token") orelse return error.InvalidKimiToken;
    const rv = parsed.value.object.get("refresh_token") orelse return error.InvalidKimiToken;
    const ev = parsed.value.object.get("expires_in") orelse return error.InvalidKimiToken;
    if (av != .string or av.string.len == 0 or rv != .string or rv.string.len == 0) return error.InvalidKimiToken;
    const seconds = positiveSeconds(ev, 0);
    if (seconds == 0) return error.InvalidKimiToken;
    return .{ .access = try gpa.dupe(u8, av.string), .refresh = try gpa.dupe(u8, rv.string), .expires_ms = now_ms + @as(i64, @intCast(seconds * 1000)) };
}

pub fn classifyPoll(gpa: std.mem.Allocator, status: u16, body: []const u8, now_ms: i64) !PollAttempt {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed (status {d})", .{status}) };
    defer parsed.deinit();
    if (status >= 200 and status < 300 and parsed.value == .object and parsed.value.object.get("access_token") != null)
        return .{ .complete = try parseTokenResponse(gpa, body, now_ms) };
    if (status >= 500) return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed with status {d}", .{status}) };
    if (parsed.value != .object) return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed (status {d})", .{status}) };
    const errv = parsed.value.object.get("error") orelse return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed (status {d})", .{status}) };
    if (errv != .string) return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed (status {d})", .{status}) };
    if (std.mem.eql(u8, errv.string, "authorization_pending")) return .pending;
    if (std.mem.eql(u8, errv.string, "slow_down")) return .{ .slow_down = if (parsed.value.object.get("interval")) |v| positiveSeconds(v, 0) else null };
    if (std.mem.eql(u8, errv.string, "expired_token")) return .expired;
    if (std.mem.eql(u8, errv.string, "access_denied")) return .denied;
    return .{ .failed = try std.fmt.allocPrint(gpa, "Kimi Code device token request failed (status {d}): {s}", .{ status, errv.string }) };
}

const HttpResponse = struct { status: u16, body: []u8 };

fn postFormWithOptions(gpa: std.mem.Allocator, io: std.Io, url: []const u8, form: []const u8, options_in: bootstrap_http.Options) !HttpResponse {
    const options = bootstrap_http.withDefaultTimeout(options_in, REQUEST_TIMEOUT_MS);
    var response = bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .POST,
        .payload = form,
        .headers = &.{
            .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
            .{ .name = "accept", .value = "application/json" },
        },
        .options = options,
    }) catch |err| switch (err) {
        error.ProviderRequestTimeout => return error.KimiOAuthRequestTimeout,
        else => return err,
    };
    errdefer response.deinit(gpa);
    return .{ .status = response.status, .body = response.body };
}

fn endpoint(gpa: std.mem.Allocator, host: []const u8, suffix: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}{s}", .{ std.mem.trimEnd(u8, host, "/"), suffix });
}

pub fn requestDeviceAuthorization(gpa: std.mem.Allocator, io: std.Io, host: []const u8) !DeviceAuthorization {
    return requestDeviceAuthorizationWithOptions(gpa, io, host, .{});
}

pub fn requestDeviceAuthorizationWithOptions(gpa: std.mem.Allocator, io: std.Io, host: []const u8, options: bootstrap_http.Options) !DeviceAuthorization {
    const url = try endpoint(gpa, host, "/api/oauth/device_authorization");
    defer gpa.free(url);
    const form = try buildDeviceAuthorizationForm(gpa);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, url, form, options);
    defer gpa.free(response.body);
    if (response.status < 200 or response.status >= 300) return error.KimiDeviceAuthorizationHttpError;
    return parseDeviceAuthorization(gpa, response.body);
}

pub fn pollDeviceOnce(gpa: std.mem.Allocator, io: std.Io, host: []const u8, device_code: []const u8) !PollAttempt {
    return pollDeviceOnceWithOptions(gpa, io, host, device_code, .{});
}

pub fn pollDeviceOnceWithOptions(gpa: std.mem.Allocator, io: std.Io, host: []const u8, device_code: []const u8, options: bootstrap_http.Options) !PollAttempt {
    const url = try endpoint(gpa, host, "/api/oauth/token");
    defer gpa.free(url);
    const form = try buildDeviceTokenForm(gpa, device_code);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, url, form, options);
    defer gpa.free(response.body);
    return classifyPoll(gpa, response.status, response.body, std.Io.Clock.real.now(io).toMilliseconds());
}

fn sleepMs(io: std.Io, ms: u64) !void {
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(ms)), .clock = .real } };
    try timeout.sleep(io);
}

pub fn pollDeviceCode(gpa: std.mem.Allocator, io: std.Io, host: []const u8, device: *const DeviceAuthorization, abort_flag: ?*const bool) !Token {
    return pollDeviceCodeWithOptions(gpa, io, host, device, abort_flag, .{});
}

pub fn pollDeviceCodeWithOptions(gpa: std.mem.Allocator, io: std.Io, host: []const u8, device: *const DeviceAuthorization, abort_flag: ?*const bool, options_in: bootstrap_http.Options) !Token {
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    var interval_ms = device.interval_seconds * 1000;
    const deadline = std.Io.Clock.real.now(io).toMilliseconds() + @as(i64, @intCast(device.expires_in_seconds * 1000));
    // Upstream intentionally waits before the first poll.
    while (true) {
        var waited: u64 = 0;
        while (waited < interval_ms) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            const step = @min(@as(u64, 100), interval_ms - waited);
            try sleepMs(io, step);
            waited += step;
            if (std.Io.Clock.real.now(io).toMilliseconds() >= deadline) return error.KimiDeviceFlowExpired;
        }
        var attempt = try pollDeviceOnceWithOptions(gpa, io, host, device.device_code, options);
        defer attempt.deinit(gpa);
        switch (attempt) {
            .complete => |*token| {
                const result = token.*;
                attempt = undefined;
                return result;
            },
            .pending => {},
            .slow_down => |suggested| interval_ms = if (suggested) |seconds| seconds * 1000 else interval_ms + 5000,
            .expired => return error.KimiDeviceFlowExpired,
            .denied => return error.KimiDeviceFlowDenied,
            .failed => return error.KimiDeviceFlowFailed,
        }
    }
}

pub fn refresh(gpa: std.mem.Allocator, io: std.Io, host: []const u8, refresh_token: []const u8) !Token {
    var options: bootstrap_http.Options = .{};
    options.policy.max_retries = REFRESH_MAX_RETRIES;
    return refreshWithOptions(gpa, io, host, refresh_token, options);
}

pub fn refreshWithOptions(gpa: std.mem.Allocator, io: std.Io, host: []const u8, refresh_token: []const u8, options: bootstrap_http.Options) !Token {
    const url = try endpoint(gpa, host, "/api/oauth/token");
    defer gpa.free(url);
    const form = try buildRefreshForm(gpa, refresh_token);
    defer gpa.free(form);
    const response = try postFormWithOptions(gpa, io, url, form, options);
    defer gpa.free(response.body);
    if (response.status >= 200 and response.status < 300) return parseTokenResponse(gpa, response.body, std.Io.Clock.real.now(io).toMilliseconds());
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, response.body, .{}) catch null;
    defer if (parsed) |*doc| doc.deinit();
    const invalid_grant = if (parsed) |doc| if (doc.value == .object) if (doc.value.object.get("error")) |v| v == .string and std.mem.eql(u8, v.string, "invalid_grant") else false else false else false;
    if (response.status == 401 or response.status == 403 or invalid_grant) return error.KimiRefreshUnauthorized;
    return error.KimiRefreshFailed;
}

pub fn persistCredential(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, token: *const Token) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("kimi-coding", .{ .refresh = token.refresh, .access = token.access, .expires = token.expires_ms });
}

test "Kimi OAuth host override precedence and trimming" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("KIMI_OAUTH_HOST", "https://old.example/");
    try std.testing.expectEqualStrings("https://old.example", oauthHost(&env));
    try env.put("KIMI_CODE_OAUTH_HOST", "https://new.example///");
    try std.testing.expectEqualStrings("https://new.example", oauthHost(&env));
}

test "Kimi device authorization validates trusted URLs and defaults intervals" {
    const gpa = std.testing.allocator;
    var d = try parseDeviceAuthorization(gpa, "{\"device_code\":\"d\",\"user_code\":\"U\",\"verification_uri\":\"https://www.kimi.com/code\",\"verification_uri_complete\":\"https://www.kimi.com/code?user_code=U\"}");
    defer d.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 5), d.interval_seconds);
    try std.testing.expectEqual(@as(u64, 900), d.expires_in_seconds);
    try std.testing.expectError(error.InvalidKimiDeviceAuthorization, parseDeviceAuthorization(gpa, "{\"device_code\":\"d\",\"user_code\":\"U\",\"verification_uri\":\"file:///tmp/x\",\"verification_uri_complete\":\"https://x\"}"));
}

test "Kimi forms and poll states match RFC 8628 contract" {
    const gpa = std.testing.allocator;
    const form = try buildDeviceTokenForm(gpa, "d +/");
    defer gpa.free(form);
    try std.testing.expect(std.mem.indexOf(u8, form, "device_code=d%20%2B%2F") != null);
    try std.testing.expect(std.mem.indexOf(u8, form, "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code") != null);
    var pending = try classifyPoll(gpa, 400, "{\"error\":\"authorization_pending\"}", 0);
    defer pending.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(pending) == .pending);
    var slow = try classifyPoll(gpa, 400, "{\"error\":\"slow_down\",\"interval\":9}", 0);
    defer slow.deinit(gpa);
    try std.testing.expectEqual(@as(?u64, 9), slow.slow_down);
    var denied = try classifyPoll(gpa, 400, "{\"error\":\"access_denied\"}", 0);
    defer denied.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(denied) == .denied);
}

test "Kimi token response uses exact expiry without skew" {
    const gpa = std.testing.allocator;
    var t = try parseTokenResponse(gpa, "{\"access_token\":\"a\",\"refresh_token\":\"r\",\"expires_in\":3600}", 1000);
    defer t.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 3_601_000), t.expires_ms);
}
