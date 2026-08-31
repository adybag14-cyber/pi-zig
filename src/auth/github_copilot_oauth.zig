//! Native GitHub Copilot OAuth/device-flow protocol and token routing helpers.
const std = @import("std");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const providers = @import("../ai/providers.zig");
const retry = @import("../ai/retry.zig");

pub const CLIENT_ID = "Iv1.b507a08c87ecfe98";
pub const DEFAULT_DOMAIN = "github.com";
pub const COPILOT_API_VERSION = "2026-06-01";
pub const USER_AGENT = "GitHubCopilotChat/0.35.0";
pub const EDITOR_VERSION = "vscode/1.107.0";
pub const EDITOR_PLUGIN_VERSION = "copilot-chat/0.35.0";
pub const INTEGRATION_ID = "vscode-chat";
pub const TOKEN_EXPIRY_SKEW_MS: i64 = 5 * 60 * 1000;

pub const Urls = struct {
    device_code: []u8,
    access_token: []u8,
    copilot_token: []u8,

    pub fn deinit(self: *Urls, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.access_token);
        gpa.free(self.copilot_token);
        self.* = undefined;
    }
};

pub const DeviceCode = struct {
    device_code: []u8,
    user_code: []u8,
    verification_uri: []u8,
    interval_seconds: u64 = 5,
    expires_in_seconds: u64,

    pub fn deinit(self: *DeviceCode, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.user_code);
        gpa.free(self.verification_uri);
        self.* = undefined;
    }
};

pub const DevicePollAttempt = union(enum) {
    complete: []u8,
    pending,
    slow_down: ?u64,
    failed: []u8,

    pub fn deinit(self: *DevicePollAttempt, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .complete, .failed => |value| gpa.free(value),
            else => {},
        }
        self.* = undefined;
    }
};

pub const CopilotCredential = struct {
    /// Long-lived GitHub access token obtained from the device flow.
    refresh: []u8,
    /// Short-lived GitHub Copilot API token.
    access: []u8,
    expires_ms: i64,
    enterprise_domain: ?[]u8 = null,
    available_model_ids: [][]u8 = &.{},

    pub fn deinit(self: *CopilotCredential, gpa: std.mem.Allocator) void {
        gpa.free(self.refresh);
        gpa.free(self.access);
        if (self.enterprise_domain) |value| gpa.free(value);
        for (self.available_model_ids) |id| gpa.free(id);
        if (self.available_model_ids.len > 0) gpa.free(self.available_model_ids);
        self.* = undefined;
    }
};

pub const LoginResult = struct { device: DeviceCode, credential: CopilotCredential };

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

pub fn normalizeDomain(gpa: std.mem.Allocator, input: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return null;
    const value = if (std.mem.indexOf(u8, trimmed, "://") != null)
        try gpa.dupe(u8, trimmed)
    else
        try std.fmt.allocPrint(gpa, "https://{s}", .{trimmed});
    defer gpa.free(value);
    const uri = std.Uri.parse(value) catch return error.InvalidGitHubEnterpriseDomain;
    var host_buf: [std.Io.net.HostName.max_len]u8 = undefined;
    const host = uri.getHost(&host_buf) catch return error.InvalidGitHubEnterpriseDomain;
    if (host.bytes.len == 0) return error.InvalidGitHubEnterpriseDomain;
    return try gpa.dupe(u8, host.bytes);
}

pub fn getUrls(gpa: std.mem.Allocator, domain: []const u8) !Urls {
    if (domain.len == 0) return error.InvalidGitHubEnterpriseDomain;
    return .{
        .device_code = try std.fmt.allocPrint(gpa, "https://{s}/login/device/code", .{domain}),
        .access_token = try std.fmt.allocPrint(gpa, "https://{s}/login/oauth/access_token", .{domain}),
        .copilot_token = try std.fmt.allocPrint(gpa, "https://api.{s}/copilot_internal/v2/token", .{domain}),
    };
}

pub fn buildDeviceCodeForm(gpa: std.mem.Allocator) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&scope=read%3Auser");
    return out.toOwnedSlice();
}

pub fn buildAccessTokenForm(gpa: std.mem.Allocator, device_code: []const u8) ![]u8 {
    if (device_code.len == 0) return error.InvalidGitHubDeviceCode;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("client_id=");
    try formEncode(&out.writer, CLIENT_ID);
    try out.writer.writeAll("&device_code=");
    try formEncode(&out.writer, device_code);
    try out.writer.writeAll("&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code");
    return out.toOwnedSlice();
}

fn requiredString(gpa: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) ![]u8 {
    const value = obj.get(name) orelse return error.InvalidGitHubOAuthResponse;
    if (value != .string or value.string.len == 0) return error.InvalidGitHubOAuthResponse;
    return gpa.dupe(u8, value.string);
}

fn nonNegativeU64(value: std.json.Value) !u64 {
    return switch (value) {
        .integer => |n| if (n >= 0) @intCast(n) else error.InvalidGitHubOAuthResponse,
        .float => |n| if (n >= 0 and std.math.isFinite(n)) @intFromFloat(n) else error.InvalidGitHubOAuthResponse,
        else => error.InvalidGitHubOAuthResponse,
    };
}

fn validateVerificationUri(raw: []const u8) !void {
    const uri = std.Uri.parse(raw) catch return error.UntrustedGitHubVerificationUri;
    if (!(std.ascii.eqlIgnoreCase(uri.scheme, "https") or std.ascii.eqlIgnoreCase(uri.scheme, "http")))
        return error.UntrustedGitHubVerificationUri;
    if (uri.host == null) return error.UntrustedGitHubVerificationUri;
}

pub fn parseDeviceCode(gpa: std.mem.Allocator, raw: []const u8) !DeviceCode {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGitHubDeviceCodeResponse;
    const obj = parsed.value.object;
    const device_code = requiredString(gpa, obj, "device_code") catch return error.InvalidGitHubDeviceCodeResponse;
    errdefer gpa.free(device_code);
    const user_code = requiredString(gpa, obj, "user_code") catch return error.InvalidGitHubDeviceCodeResponse;
    errdefer gpa.free(user_code);
    const verification_uri = requiredString(gpa, obj, "verification_uri") catch return error.InvalidGitHubDeviceCodeResponse;
    errdefer gpa.free(verification_uri);
    validateVerificationUri(verification_uri) catch return error.UntrustedGitHubVerificationUri;
    const expires_value = obj.get("expires_in") orelse return error.InvalidGitHubDeviceCodeResponse;
    const expires_in = nonNegativeU64(expires_value) catch return error.InvalidGitHubDeviceCodeResponse;
    const interval = if (obj.get("interval")) |value| nonNegativeU64(value) catch return error.InvalidGitHubDeviceCodeResponse else 5;
    return .{
        .device_code = device_code,
        .user_code = user_code,
        .verification_uri = verification_uri,
        .interval_seconds = interval,
        .expires_in_seconds = expires_in,
    };
}

fn errorMessage(gpa: std.mem.Allocator, error_code: []const u8, description: ?[]const u8) ![]u8 {
    return if (description) |desc|
        std.fmt.allocPrint(gpa, "Device flow failed: {s}: {s}", .{ error_code, desc })
    else
        std.fmt.allocPrint(gpa, "Device flow failed: {s}", .{error_code});
}

pub fn classifyAccessTokenResponse(gpa: std.mem.Allocator, raw: []const u8) !DevicePollAttempt {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch
        return .{ .failed = try gpa.dupe(u8, "Invalid device token response") };
    defer parsed.deinit();
    if (parsed.value != .object) return .{ .failed = try gpa.dupe(u8, "Invalid device token response") };
    const obj = parsed.value.object;
    if (obj.get("access_token")) |value| if (value == .string and value.string.len > 0)
        return .{ .complete = try gpa.dupe(u8, value.string) };
    const err_value = obj.get("error") orelse return .{ .failed = try gpa.dupe(u8, "Invalid device token response") };
    if (err_value != .string or err_value.string.len == 0) return .{ .failed = try gpa.dupe(u8, "Invalid device token response") };
    if (std.mem.eql(u8, err_value.string, "authorization_pending")) return .pending;
    if (std.mem.eql(u8, err_value.string, "slow_down")) {
        const override = if (obj.get("interval")) |value| nonNegativeU64(value) catch null else null;
        return .{ .slow_down = override };
    }
    const description = if (obj.get("error_description")) |value| if (value == .string) value.string else null else null;
    return .{ .failed = try errorMessage(gpa, err_value.string, description) };
}

pub fn nextPollIntervalSeconds(current: u64, attempt: DevicePollAttempt) u64 {
    return switch (attempt) {
        .slow_down => |override| override orelse current + 5,
        else => current,
    };
}

pub fn baseUrlFromToken(gpa: std.mem.Allocator, token: []const u8) !?[]u8 {
    var fields = std.mem.splitScalar(u8, token, ';');
    while (fields.next()) |field| {
        if (!std.mem.startsWith(u8, field, "proxy-ep=")) continue;
        const host = std.mem.trim(u8, field["proxy-ep=".len..], " \t\r\n");
        if (host.len == 0) return null;
        const api_host = if (std.mem.startsWith(u8, host, "proxy.")) host["proxy.".len..] else host;
        return try std.fmt.allocPrint(gpa, "https://api.{s}", .{api_host});
    }
    return null;
}

pub fn getBaseUrl(gpa: std.mem.Allocator, token: ?[]const u8, enterprise_domain: ?[]const u8) ![]u8 {
    if (token) |value| if (try baseUrlFromToken(gpa, value)) |url| return url;
    if (enterprise_domain) |domain| return std.fmt.allocPrint(gpa, "https://copilot-api.{s}", .{domain});
    return gpa.dupe(u8, "https://api.individual.githubcopilot.com");
}

pub fn parseCopilotToken(
    gpa: std.mem.Allocator,
    raw: []const u8,
    github_access_token: []const u8,
    enterprise_domain: ?[]const u8,
) !CopilotCredential {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCopilotTokenResponse;
    const access = requiredString(gpa, parsed.value.object, "token") catch return error.InvalidCopilotTokenResponse;
    errdefer gpa.free(access);
    const exp_value = parsed.value.object.get("expires_at") orelse return error.InvalidCopilotTokenResponse;
    const exp_seconds = nonNegativeU64(exp_value) catch return error.InvalidCopilotTokenResponse;
    const refresh = try gpa.dupe(u8, github_access_token);
    errdefer gpa.free(refresh);
    const enterprise = if (enterprise_domain) |domain| try gpa.dupe(u8, domain) else null;
    const exp_ms_u = std.math.mul(u64, exp_seconds, 1000) catch return error.InvalidCopilotTokenResponse;
    if (exp_ms_u > std.math.maxInt(i64)) return error.InvalidCopilotTokenResponse;
    return .{
        .refresh = refresh,
        .access = access,
        .expires_ms = @as(i64, @intCast(exp_ms_u)) - TOKEN_EXPIRY_SKEW_MS,
        .enterprise_domain = enterprise,
    };
}

fn asObject(value: std.json.Value) ?std.json.ObjectMap {
    return if (value == .object) value.object else null;
}

fn modelSupportsTools(obj: std.json.ObjectMap) bool {
    if (obj.get("capabilities")) |caps_value| if (asObject(caps_value)) |caps| {
        if (caps.get("supports")) |supports_value| if (asObject(supports_value)) |supports| {
            if (supports.get("tool_calls")) |tools| if (tools == .bool and !tools.bool) return false;
        };
    };
    return true;
}

fn pickerEnabled(obj: std.json.ObjectMap) bool {
    const value = obj.get("model_picker_enabled") orelse return false;
    return value == .bool and value.bool;
}

fn policyState(obj: std.json.ObjectMap) ?[]const u8 {
    const policy_value = obj.get("policy") orelse return null;
    const policy = asObject(policy_value) orelse return null;
    const state = policy.get("state") orelse return null;
    return if (state == .string) state.string else null;
}

fn knownCopilotModel(model_id: []const u8) bool {
    for (providers.known_models) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot") and std.mem.eql(u8, model.id, model_id)) return true;
    }
    return false;
}

fn freeModelIds(gpa: std.mem.Allocator, ids: [][]u8) void {
    for (ids) |id| gpa.free(id);
    if (ids.len > 0) gpa.free(ids);
}

pub const CopilotModelCatalog = struct {
    available_model_ids: [][]u8 = &.{},
    policy_model_ids: [][]u8 = &.{},

    pub fn deinit(self: *CopilotModelCatalog, gpa: std.mem.Allocator) void {
        freeModelIds(gpa, self.available_model_ids);
        freeModelIds(gpa, self.policy_model_ids);
        self.* = undefined;
    }
};

/// Parse the account-specific Copilot model catalog using the exact upstream
/// picker, tool-capability, and policy rules. Only the Individual endpoint is
/// allowed to fall back to explicit enabled policies when every picker flag is
/// false; enterprise/business accounts retain strict picker semantics.
pub fn parseCopilotModelCatalog(gpa: std.mem.Allocator, raw: []const u8, allow_policy_fallback: bool) !CopilotModelCatalog {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCopilotModelsResponse;
    const data = parsed.value.object.get("data") orelse return error.InvalidCopilotModelsResponse;
    if (data != .array) return error.InvalidCopilotModelsResponse;

    var picker_count: usize = 0;
    for (data.array.items) |item| {
        if (item != .object or !modelSupportsTools(item.object)) continue;
        const id = item.object.get("id") orelse continue;
        if (id != .string or id.string.len == 0) continue;
        const state = policyState(item.object);
        if (pickerEnabled(item.object) and (state == null or !std.mem.eql(u8, state.?, "disabled"))) picker_count += 1;
    }
    const use_policy_fallback = allow_policy_fallback and picker_count == 0;

    var available: std.ArrayList([]u8) = .empty;
    var policies: std.ArrayList([]u8) = .empty;
    errdefer {
        for (available.items) |id| gpa.free(id);
        available.deinit(gpa);
        for (policies.items) |id| gpa.free(id);
        policies.deinit(gpa);
    }
    for (data.array.items) |item| {
        if (item != .object or !modelSupportsTools(item.object)) continue;
        const id = item.object.get("id") orelse continue;
        if (id != .string or id.string.len == 0) continue;
        const picker = pickerEnabled(item.object);
        const state = policyState(item.object);
        const selectable = picker and (state == null or !std.mem.eql(u8, state.?, "disabled"));
        const fallback_enabled = use_policy_fallback and state != null and std.mem.eql(u8, state.?, "enabled");
        if (selectable or fallback_enabled) try available.append(gpa, try gpa.dupe(u8, id.string));
        const needs_policy = state != null and std.mem.eql(u8, state.?, "unconfigured") and knownCopilotModel(id.string) and (picker or use_policy_fallback);
        if (needs_policy) try policies.append(gpa, try gpa.dupe(u8, id.string));
    }
    return .{
        .available_model_ids = if (available.items.len > 0) try available.toOwnedSlice(gpa) else blk: {
            available.deinit(gpa);
            break :blk &.{};
        },
        .policy_model_ids = if (policies.items.len > 0) try policies.toOwnedSlice(gpa) else blk: {
            policies.deinit(gpa);
            break :blk &.{};
        },
    };
}

pub fn parseAvailableModelIds(gpa: std.mem.Allocator, raw: []const u8) ![][]u8 {
    const catalog = try parseCopilotModelCatalog(gpa, raw, false);
    freeModelIds(gpa, catalog.policy_model_ids);
    return catalog.available_model_ids;
}

const HttpResponse = struct {
    status: u16,
    body: []u8,
    provider: retry.ProviderResponseMeta,
};

fn httpRequestWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    method: std.http.Method,
    payload: ?[]const u8,
    headers: []const std.http.Header,
    options: bootstrap_http.Options,
) !HttpResponse {
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = method,
        .payload = payload,
        .headers = headers,
        .options = options,
    });
    errdefer response.deinit(gpa);
    return .{
        .status = response.status,
        .body = response.body,
        .provider = response.provider,
    };
}

fn requireOk(response: HttpResponse) !void {
    if (response.status < 200 or response.status >= 300) return error.GitHubCopilotHttpError;
}

fn boundedCopilotOptions(options: bootstrap_http.Options, remaining_ms: ?u64) bootstrap_http.Options {
    var bounded = options;
    // The Copilot login transport gives each discovery/policy request a five
    // second ceiling. Retries are managed here so only HTTP 429 is repeated.
    bounded.policy.max_retries = 0;
    const request_ceiling = if (remaining_ms) |remaining| @min(@as(u64, 5_000), remaining) else 5_000;
    bounded.policy.timeout_ms = if (bounded.policy.timeout_ms) |configured|
        @min(configured, request_ceiling)
    else
        request_ceiling;
    bounded.policy.max_retry_delay_ms = @min(bounded.policy.max_retry_delay_ms, 5_000);
    return bounded;
}

/// Copilot's account model endpoints have a deliberately smaller retry budget
/// than ordinary model traffic: retry only 429 responses, at most twice, and
/// never wait past the five-second login budget. The normal refresh path calls
/// this with zero retries and therefore performs exactly one bounded request.
fn copilotRequestWithRateLimitRetry(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    method: std.http.Method,
    payload: ?[]const u8,
    headers: []const std.http.Header,
    options: bootstrap_http.Options,
    max_retries: usize,
    max_elapsed_ms: u64,
) !HttpResponse {
    const started = std.Io.Clock.real.now(io).toMilliseconds();
    var retry_index: usize = 0;
    while (true) {
        const now = std.Io.Clock.real.now(io).toMilliseconds();
        const elapsed: u64 = @intCast(@max(@as(i64, 0), now - started));
        const remaining = if (max_elapsed_ms > 0) max_elapsed_ms -| elapsed else null;
        if (remaining != null and remaining.? == 0) return error.ProviderRequestTimeout;
        const response = try httpRequestWithOptions(gpa, io, url, method, payload, headers, boundedCopilotOptions(options, remaining));
        if (response.status != 429 or retry_index >= max_retries) return response;

        var policy = options.policy;
        policy.max_retry_delay_ms = @min(policy.max_retry_delay_ms, 5_000);
        const delay_ms = retry.providerDelayMs(io, policy, retry_index, response.provider.retry_after_ms) catch return response;
        if (max_elapsed_ms > 0) {
            const after_request = std.Io.Clock.real.now(io).toMilliseconds();
            const consumed: u64 = @intCast(@max(@as(i64, 0), after_request - started));
            const budget_left = max_elapsed_ms -| consumed;
            if (delay_ms >= budget_left) return response;
        }
        gpa.free(response.body);
        if (!retry.waitProvider(io, delay_ms, options.abort_flag)) return error.ProviderRequestAborted;
        retry_index += 1;
    }
}

pub fn requestDeviceCode(gpa: std.mem.Allocator, io: std.Io, enterprise_domain: ?[]const u8) !DeviceCode {
    return requestDeviceCodeWithOptions(gpa, io, enterprise_domain, .{});
}

pub fn requestDeviceCodeWithOptions(gpa: std.mem.Allocator, io: std.Io, enterprise_domain: ?[]const u8, options: bootstrap_http.Options) !DeviceCode {
    const domain = enterprise_domain orelse DEFAULT_DOMAIN;
    var urls = try getUrls(gpa, domain);
    defer urls.deinit(gpa);
    const form = try buildDeviceCodeForm(gpa);
    defer gpa.free(form);
    const headers = [_]std.http.Header{
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        .{ .name = "user-agent", .value = USER_AGENT },
    };
    const response = try httpRequestWithOptions(gpa, io, urls.device_code, .POST, form, &headers, options);
    defer gpa.free(response.body);
    try requireOk(response);
    return parseDeviceCode(gpa, response.body);
}

pub fn requestGitHubAccessTokenAttempt(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    device: *const DeviceCode,
) !DevicePollAttempt {
    return requestGitHubAccessTokenAttemptWithOptions(gpa, io, enterprise_domain, device, .{});
}

pub fn requestGitHubAccessTokenAttemptWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    device: *const DeviceCode,
    options: bootstrap_http.Options,
) !DevicePollAttempt {
    const domain = enterprise_domain orelse DEFAULT_DOMAIN;
    var urls = try getUrls(gpa, domain);
    defer urls.deinit(gpa);
    const form = try buildAccessTokenForm(gpa, device.device_code);
    defer gpa.free(form);
    const headers = [_]std.http.Header{
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "content-type", .value = "application/x-www-form-urlencoded" },
        .{ .name = "user-agent", .value = USER_AGENT },
    };
    const response = try httpRequestWithOptions(gpa, io, urls.access_token, .POST, form, &headers, options);
    defer gpa.free(response.body);
    try requireOk(response);
    return classifyAccessTokenResponse(gpa, response.body);
}

fn sleepMs(io: std.Io, ms: u64) !void {
    const bounded: i64 = @intCast(@min(ms, @as(u64, @intCast(std.math.maxInt(i64)))));
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(bounded), .clock = .real } };
    try timeout.sleep(io);
}

pub fn pollGitHubAccessToken(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    device: *const DeviceCode,
    abort_flag: ?*const bool,
) ![]u8 {
    return pollGitHubAccessTokenWithOptions(gpa, io, enterprise_domain, device, abort_flag, .{});
}

pub fn pollGitHubAccessTokenWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    device: *const DeviceCode,
    abort_flag: ?*const bool,
    options_in: bootstrap_http.Options,
) ![]u8 {
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    const started = std.Io.Clock.real.now(io).toMilliseconds();
    const expires_ms: i64 = @intCast(@min(device.expires_in_seconds * 1000, @as(u64, @intCast(std.math.maxInt(i64)))));
    const deadline = started + expires_ms;
    var interval_seconds = if (device.interval_seconds > 0) device.interval_seconds else 5;

    // GitHub device flow waits before the first poll.
    while (std.Io.Clock.real.now(io).toMilliseconds() < deadline) {
        var elapsed: u64 = 0;
        const delay = interval_seconds * 1000;
        while (elapsed < delay) {
            if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
            const slice = @min(@as(u64, 100), delay - elapsed);
            try sleepMs(io, slice);
            elapsed += slice;
        }
        if (abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
        if (options.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return error.LoginCancelled;
        var attempt = try requestGitHubAccessTokenAttemptWithOptions(gpa, io, enterprise_domain, device, options);
        switch (attempt) {
            .complete => |token| return token,
            .pending => {},
            .slow_down => |override| interval_seconds = override orelse interval_seconds + 5,
            .failed => {
                attempt.deinit(gpa);
                return error.GitHubDeviceFlowFailed;
            },
        }
        attempt.deinit(gpa);
    }
    return error.GitHubDeviceFlowExpired;
}

fn copilotHeaders(authorization: []const u8, include_api_version: bool) [7]std.http.Header {
    return .{
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "authorization", .value = authorization },
        .{ .name = "user-agent", .value = USER_AGENT },
        .{ .name = "editor-version", .value = EDITOR_VERSION },
        .{ .name = "editor-plugin-version", .value = EDITOR_PLUGIN_VERSION },
        .{ .name = "copilot-integration-id", .value = INTEGRATION_ID },
        .{ .name = "x-github-api-version", .value = if (include_api_version) COPILOT_API_VERSION else "" },
    };
}

pub fn refreshAccessToken(
    gpa: std.mem.Allocator,
    io: std.Io,
    github_access_token: []const u8,
    enterprise_domain: ?[]const u8,
) !CopilotCredential {
    return refreshAccessTokenWithOptions(gpa, io, github_access_token, enterprise_domain, .{});
}

pub fn refreshAccessTokenWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    github_access_token: []const u8,
    enterprise_domain: ?[]const u8,
    options: bootstrap_http.Options,
) !CopilotCredential {
    const domain = enterprise_domain orelse DEFAULT_DOMAIN;
    var urls = try getUrls(gpa, domain);
    defer urls.deinit(gpa);
    const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{github_access_token});
    defer gpa.free(authorization);
    const all_headers = copilotHeaders(authorization, false);
    const response = try httpRequestWithOptions(gpa, io, urls.copilot_token, .GET, null, all_headers[0..6], options);
    defer gpa.free(response.body);
    try requireOk(response);
    return parseCopilotToken(gpa, response.body, github_access_token, enterprise_domain);
}

pub fn fetchAvailableModelIds(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
) ![][]u8 {
    return fetchAvailableModelIdsWithOptions(gpa, io, copilot_token, enterprise_domain, .{});
}

pub fn fetchAvailableModelIdsWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    options: bootstrap_http.Options,
) ![][]u8 {
    const catalog = try fetchModelCatalogWithOptions(gpa, io, copilot_token, enterprise_domain, options, 0, 0);
    freeModelIds(gpa, catalog.policy_model_ids);
    return catalog.available_model_ids;
}

fn fetchModelCatalogWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    options: bootstrap_http.Options,
    max_retries: usize,
    max_elapsed_ms: u64,
) !CopilotModelCatalog {
    const base = try getBaseUrl(gpa, copilot_token, enterprise_domain);
    defer gpa.free(base);
    const url = try std.fmt.allocPrint(gpa, "{s}/models", .{std.mem.trimEnd(u8, base, "/")});
    defer gpa.free(url);
    const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{copilot_token});
    defer gpa.free(authorization);
    const headers = copilotHeaders(authorization, true);
    const response = try copilotRequestWithRateLimitRetry(gpa, io, url, .GET, null, &headers, options, max_retries, max_elapsed_ms);
    defer gpa.free(response.body);
    try requireOk(response);
    const allow_policy_fallback = std.mem.eql(u8, std.mem.trimEnd(u8, base, "/"), "https://api.individual.githubcopilot.com");
    return parseCopilotModelCatalog(gpa, response.body, allow_policy_fallback);
}

pub fn enableModel(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    model_id: []const u8,
) !bool {
    return enableModelWithOptions(gpa, io, copilot_token, enterprise_domain, model_id, .{});
}

pub fn enableModelWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    model_id: []const u8,
    options: bootstrap_http.Options,
) !bool {
    const base = try getBaseUrl(gpa, copilot_token, enterprise_domain);
    defer gpa.free(base);
    const url = try std.fmt.allocPrint(gpa, "{s}/models/{s}/policy", .{ std.mem.trimEnd(u8, base, "/"), model_id });
    defer gpa.free(url);
    const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{copilot_token});
    defer gpa.free(authorization);
    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
        .{ .name = "authorization", .value = authorization },
        .{ .name = "user-agent", .value = USER_AGENT },
        .{ .name = "editor-version", .value = EDITOR_VERSION },
        .{ .name = "editor-plugin-version", .value = EDITOR_PLUGIN_VERSION },
        .{ .name = "copilot-integration-id", .value = INTEGRATION_ID },
        .{ .name = "openai-intent", .value = "chat-policy" },
        .{ .name = "x-interaction-type", .value = "chat-policy" },
    };
    const response = copilotRequestWithRateLimitRetry(gpa, io, url, .POST, "{\"state\":\"enabled\"}", &headers, options, 2, 5_000) catch |err| switch (err) {
        error.ProviderRequestAborted, error.ProviderRequestTimeout => return err,
        else => return false,
    };
    defer gpa.free(response.body);
    if (response.status == 429) return error.CopilotPolicyRateLimited;
    return response.status >= 200 and response.status < 300;
}

pub fn enableModels(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    model_ids: []const []const u8,
) !void {
    return enableModelsWithOptions(gpa, io, copilot_token, enterprise_domain, model_ids, .{});
}

pub fn enableModelsWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    model_ids: []const []const u8,
    options: bootstrap_http.Options,
) !void {
    for (model_ids) |model_id| {
        _ = enableModelWithOptions(gpa, io, copilot_token, enterprise_domain, model_id, options) catch |err| switch (err) {
            error.CopilotPolicyRateLimited => break,
            error.ProviderRequestAborted, error.ProviderRequestTimeout => return err,
            else => continue,
        };
    }
}

fn containsModelId(ids: []const []u8, wanted: []const u8) bool {
    for (ids) |id| if (std.mem.eql(u8, id, wanted)) return true;
    return false;
}

/// Discover the account catalog before enabling policies, then enable only
/// known tool-capable models whose account state is `unconfigured`. Successful
/// policy updates are folded into the original available list without a second
/// discovery request, matching the current upstream login behavior.
pub fn discoverAndEnableAvailableModelIdsWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    copilot_token: []const u8,
    enterprise_domain: ?[]const u8,
    options: bootstrap_http.Options,
) ![][]u8 {
    var catalog = try fetchModelCatalogWithOptions(gpa, io, copilot_token, enterprise_domain, options, 2, 5_000);
    defer catalog.deinit(gpa);
    var result: std.ArrayList([]u8) = .empty;
    errdefer {
        for (result.items) |id| gpa.free(id);
        result.deinit(gpa);
    }
    for (catalog.available_model_ids) |id| try result.append(gpa, try gpa.dupe(u8, id));
    for (catalog.policy_model_ids) |model_id| {
        const enabled = enableModelWithOptions(gpa, io, copilot_token, enterprise_domain, model_id, options) catch |err| switch (err) {
            error.CopilotPolicyRateLimited => break,
            error.ProviderRequestAborted, error.ProviderRequestTimeout => return err,
            else => false,
        };
        if (enabled and !containsModelId(result.items, model_id)) try result.append(gpa, try gpa.dupe(u8, model_id));
    }
    if (result.items.len == 0) {
        result.deinit(gpa);
        return &.{};
    }
    return result.toOwnedSlice(gpa);
}

pub fn refreshCredential(
    gpa: std.mem.Allocator,
    io: std.Io,
    github_access_token: []const u8,
    enterprise_domain: ?[]const u8,
) !CopilotCredential {
    return refreshCredentialWithOptions(gpa, io, github_access_token, enterprise_domain, .{});
}

pub fn refreshCredentialWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    github_access_token: []const u8,
    enterprise_domain: ?[]const u8,
    options: bootstrap_http.Options,
) !CopilotCredential {
    var credential = try refreshAccessTokenWithOptions(gpa, io, github_access_token, enterprise_domain, options);
    errdefer credential.deinit(gpa);
    credential.available_model_ids = try fetchAvailableModelIdsWithOptions(gpa, io, credential.access, enterprise_domain, options);
    return credential;
}

pub fn login(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    abort_flag: ?*const bool,
    models_to_enable: []const []const u8,
) !LoginResult {
    return loginWithOptions(gpa, io, enterprise_domain, abort_flag, models_to_enable, .{});
}

pub fn loginWithOptions(
    gpa: std.mem.Allocator,
    io: std.Io,
    enterprise_domain: ?[]const u8,
    abort_flag: ?*const bool,
    models_to_enable: []const []const u8,
    options_in: bootstrap_http.Options,
) !LoginResult {
    // Retained for source compatibility with the 0.84.1 Zig API. Current
    // upstream derives the safe policy list from the authenticated account
    // catalog instead of enabling a caller-supplied list eagerly.
    _ = models_to_enable;
    var options = options_in;
    if (options.abort_flag == null) {
        if (abort_flag) |flag| {
            options.abort_flag = @constCast(flag);
        }
    }
    var device = try requestDeviceCodeWithOptions(gpa, io, enterprise_domain, options);
    errdefer device.deinit(gpa);
    const github_access = try pollGitHubAccessTokenWithOptions(gpa, io, enterprise_domain, &device, abort_flag, options);
    defer gpa.free(github_access);
    var credential = try refreshAccessTokenWithOptions(gpa, io, github_access, enterprise_domain, options);
    errdefer credential.deinit(gpa);
    credential.available_model_ids = try discoverAndEnableAvailableModelIdsWithOptions(gpa, io, credential.access, enterprise_domain, options);
    return .{ .device = device, .credential = credential };
}

pub fn persistCredential(gpa: std.mem.Allocator, io: std.Io, agent_dir: []const u8, credential: *const CopilotCredential) !void {
    const storage = @import("storage.zig");
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("github-copilot", .{
        .refresh = credential.refresh,
        .access = credential.access,
        .expires = credential.expires_ms,
        .enterprise_url = credential.enterprise_domain,
        .available_model_ids = credential.available_model_ids,
        .available_model_ids_present = true,
    });
}

test "GitHub Copilot normalizes enterprise domain and builds endpoints" {
    const gpa = std.testing.allocator;
    const domain = (try normalizeDomain(gpa, " https://company.ghe.com/path ")).?;
    defer gpa.free(domain);
    try std.testing.expectEqualStrings("company.ghe.com", domain);
    var urls = try getUrls(gpa, domain);
    defer urls.deinit(gpa);
    try std.testing.expectEqualStrings("https://company.ghe.com/login/device/code", urls.device_code);
    try std.testing.expectEqualStrings("https://api.company.ghe.com/copilot_internal/v2/token", urls.copilot_token);
}

test "GitHub Copilot device forms and response validation match upstream" {
    const gpa = std.testing.allocator;
    const form = try buildDeviceCodeForm(gpa);
    defer gpa.free(form);
    try std.testing.expectEqualStrings("client_id=Iv1.b507a08c87ecfe98&scope=read%3Auser", form);
    const poll = try buildAccessTokenForm(gpa, "dev +/=");
    defer gpa.free(poll);
    try std.testing.expect(std.mem.indexOf(u8, poll, "device_code=dev%20%2B%2F%3D") != null);
    var device = try parseDeviceCode(gpa, "{\"device_code\":\"d\",\"user_code\":\"ABCD\",\"verification_uri\":\"https://github.com/login/device\",\"interval\":2,\"expires_in\":900}");
    defer device.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 2), device.interval_seconds);
    try std.testing.expectError(error.UntrustedGitHubVerificationUri, parseDeviceCode(gpa, "{\"device_code\":\"d\",\"user_code\":\"ABCD\",\"verification_uri\":\"file:///tmp/x\",\"expires_in\":900}"));
}

test "GitHub Copilot device poll handles pending slow down and completion" {
    const gpa = std.testing.allocator;
    var pending = try classifyAccessTokenResponse(gpa, "{\"error\":\"authorization_pending\"}");
    defer pending.deinit(gpa);
    try std.testing.expect(std.meta.activeTag(pending) == .pending);
    var slow = try classifyAccessTokenResponse(gpa, "{\"error\":\"slow_down\",\"interval\":12}");
    defer slow.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 12), nextPollIntervalSeconds(5, slow));
    var complete = try classifyAccessTokenResponse(gpa, "{\"access_token\":\"ghu_token\"}");
    defer complete.deinit(gpa);
    try std.testing.expectEqualStrings("ghu_token", complete.complete);
}

test "GitHub Copilot token derives endpoint and safety-skewed expiry" {
    const gpa = std.testing.allocator;
    var credential = try parseCopilotToken(gpa, "{\"token\":\"tid=1;exp=2;proxy-ep=proxy.business.githubcopilot.com;\",\"expires_at\":2000000000}", "gh-access", null);
    defer credential.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 2_000_000_000_000 - TOKEN_EXPIRY_SKEW_MS), credential.expires_ms);
    const base = try getBaseUrl(gpa, credential.access, null);
    defer gpa.free(base);
    try std.testing.expectEqualStrings("https://api.business.githubcopilot.com", base);
    const enterprise = try getBaseUrl(gpa, null, "company.ghe.com");
    defer gpa.free(enterprise);
    try std.testing.expectEqualStrings("https://copilot-api.company.ghe.com", enterprise);
}

test "GitHub Copilot model availability filters disabled picker and no-tool models" {
    const gpa = std.testing.allocator;
    const raw =
        "{\"data\":[" ++
        "{\"id\":\"good\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"enabled\"},\"capabilities\":{\"supports\":{\"tool_calls\":true}}}," ++
        "{\"id\":\"disabled\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"disabled\"}}," ++
        "{\"id\":\"hidden\",\"model_picker_enabled\":false}," ++
        "{\"id\":\"no-tools\",\"model_picker_enabled\":true,\"capabilities\":{\"supports\":{\"tool_calls\":false}}}" ++
        "]}";
    const ids = try parseAvailableModelIds(gpa, raw);
    defer {
        for (ids) |id| gpa.free(id);
        gpa.free(ids);
    }
    try std.testing.expectEqual(@as(usize, 1), ids.len);
    try std.testing.expectEqualStrings("good", ids[0]);
}

test "GitHub Copilot account catalog selects only safe unconfigured known policies" {
    const gpa = std.testing.allocator;
    const raw =
        "{\"data\":[" ++
        "{\"id\":\"gpt-5.4\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"unconfigured\"},\"capabilities\":{\"supports\":{\"tool_calls\":true}}}," ++
        "{\"id\":\"already\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"enabled\"}}," ++
        "{\"id\":\"unknown-future\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"unconfigured\"}}," ++
        "{\"id\":\"disabled\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"disabled\"}}," ++
        "{\"id\":\"no-tools\",\"model_picker_enabled\":true,\"policy\":{\"state\":\"unconfigured\"},\"capabilities\":{\"supports\":{\"tool_calls\":false}}}" ++
        "]}";
    var catalog = try parseCopilotModelCatalog(gpa, raw, false);
    defer catalog.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 3), catalog.available_model_ids.len);
    try std.testing.expectEqualStrings("gpt-5.4", catalog.available_model_ids[0]);
    try std.testing.expectEqualStrings("already", catalog.available_model_ids[1]);
    try std.testing.expectEqualStrings("unknown-future", catalog.available_model_ids[2]);
    try std.testing.expectEqual(@as(usize, 1), catalog.policy_model_ids.len);
    try std.testing.expectEqualStrings("gpt-5.4", catalog.policy_model_ids[0]);
}

test "GitHub Copilot Individual fallback honors enabled and known policy models" {
    const gpa = std.testing.allocator;
    const raw =
        "{\"data\":[" ++
        "{\"id\":\"enabled-account\",\"model_picker_enabled\":false,\"policy\":{\"state\":\"enabled\"}}," ++
        "{\"id\":\"grok-4.6\",\"model_picker_enabled\":false,\"policy\":{\"state\":\"unconfigured\"}}," ++
        "{\"id\":\"unknown\",\"model_picker_enabled\":false,\"policy\":{\"state\":\"unconfigured\"}}" ++
        "]}";
    var strict = try parseCopilotModelCatalog(gpa, raw, false);
    defer strict.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), strict.available_model_ids.len);
    try std.testing.expectEqual(@as(usize, 0), strict.policy_model_ids.len);

    var individual = try parseCopilotModelCatalog(gpa, raw, true);
    defer individual.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), individual.available_model_ids.len);
    try std.testing.expectEqualStrings("enabled-account", individual.available_model_ids[0]);
    try std.testing.expectEqual(@as(usize, 1), individual.policy_model_ids.len);
    try std.testing.expectEqualStrings("grok-4.6", individual.policy_model_ids[0]);
}
