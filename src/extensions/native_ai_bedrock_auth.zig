//! Source Bedrock auth precedence on VM thread; byte-only credential/signing hook.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const prep = @import("native_ai_http_prepare.zig");
pub fn configure(s: *Scope, dependencies: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const result = try s.object();
    const env_module = try s.get(dependencies, "env");
    const scoped_env = try v.optional(s, options, "env");
    const env = try s.object();
    // Snapshot only credential-chain inputs, never arbitrary process state.
    inline for (.{ "AWS_REGION", "AWS_DEFAULT_REGION", "AWS_PROFILE", "AWS_DEFAULT_PROFILE", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_CONFIG_FILE", "AWS_SHARED_CREDENTIALS_FILE", "AWS_ROLE_ARN", "AWS_WEB_IDENTITY_TOKEN_FILE", "AWS_ROLE_SESSION_NAME", "AWS_ENDPOINT_URL_STS", "AWS_ENDPOINT_URL_SSO", "AWS_ENDPOINT_URL_SSO_OIDC", "AWS_ENDPOINT_URL_SIGNIN", "AWS_LOGIN_CACHE_DIRECTORY", "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "AWS_CONTAINER_CREDENTIALS_FULL_URI", "AWS_CONTAINER_AUTHORIZATION_TOKEN", "AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", "AWS_EC2_METADATA_DISABLED", "AWS_EC2_METADATA_SERVICE_ENDPOINT", "AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE", "AWS_EC2_METADATA_V1_DISABLED", "HOME", "USERPROFILE" }) |key| {
        const value = try s.invoke(env_module, "getProviderEnvValue", &.{try s.text(key)});
        if (!c.JS_IsUndefined(value)) try s.put(env, key, value);
    }
    // Source passes scoped static keys explicitly to the SDK; the SDK's
    // remaining default chain reads ambient environment, not options.env.
    inline for (.{ "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN" }) |key| {
        const value = try s.invoke(env_module, "getProviderEnvValue", &.{ try s.text(key), scoped_env });
        if (!c.JS_IsUndefined(value)) try s.put(env, key, value);
    }
    const option_profile = try v.optional(s, options, "profile");
    const scoped_profile = try v.optional(s, scoped_env, "AWS_PROFILE");
    const profile = if (s.truthy(option_profile)) option_profile else scoped_profile;
    try s.put(result, "profile", if (s.truthy(profile)) profile else c.pi_js_undefined());
    try s.put(result, "env", env);
    const skip = try s.invoke(env_module, "getProviderEnvValue", &.{ try s.text("AWS_BEDROCK_SKIP_AUTH"), scoped_env });
    try s.put(result, "skipAuth", c.pi_js_bool(s.engine.context, @intFromBool(try v.eq(s, skip, "1"))));
    var bearer = try v.optional(s, options, "bearerToken");
    if (!s.truthy(bearer)) bearer = try v.optional(s, options, "apiKey");
    if (!s.truthy(bearer)) bearer = try s.invoke(env_module, "getProviderEnvValue", &.{ try s.text("AWS_BEARER_TOKEN_BEDROCK"), scoped_env });
    try s.put(result, "bearerToken", if (s.truthy(bearer) and !try v.eq(s, skip, "1")) bearer else c.pi_js_undefined());
    // The SDK separately tests key presence in ambient process.env. Empty
    // values still select httpBearerAuth even when Source's truthy lookup
    // omitted its configured token (genuine credential Source25).
    const process_env = try v.optional(s, try s.global("process"), "env");
    const bearer_key = try s.text("AWS_BEARER_TOKEN_BEDROCK");
    if (!v.nullish(process_env) and try v.js.hasKey(s.engine, process_env, bearer_key)) {
        try s.put(result, "sdkBearerSelected", c.pi_js_bool(s.engine.context, 1));
        try s.put(result, "sdkBearerToken", try s.own(try v.js.getKey(s.engine, process_env, bearer_key)));
    }
    var region = try @import("native_ai_bedrock_request.zig").configuredRegion(s, options);
    const base = try s.get(model, "baseUrl");
    const ambient_profile = try s.invoke(env_module, "getProviderEnvValue", &.{try s.text("AWS_PROFILE")});
    const endpoint_region = try standardRegion(s, base);
    const explicit_endpoint = !s.truthy(endpoint_region) or (!s.truthy(region) and !s.truthy(ambient_profile));
    const arn_regex = try literal(s, "^arn:aws(?:-[a-z0-9-]+)?:bedrock:([a-z0-9-]+):");
    const arn = try s.invoke(try s.get(model, "id"), "match", &.{arn_regex});
    if (s.truthy(arn)) region = try v.at(s, arn, 1) else if (!s.truthy(region) and s.truthy(endpoint_region) and explicit_endpoint) region = endpoint_region;
    // Profile region is resolved by native credentials preparation when no region is pinned.
    if (!s.truthy(region) and !s.truthy(ambient_profile)) region = try s.text("us-east-1");
    try s.put(result, "region", region);
    try s.put(result, "baseUrl", if (explicit_endpoint) base else c.pi_js_undefined());
    try s.put(result, "modelId", try s.get(model, "id"));
    return result;
}
fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn standardRegion(s: *Scope, base: c.JSValue) !c.JSValue {
    if (!s.truthy(base)) return c.pi_js_undefined();
    const generation = s.engine.native_allocation_generation;
    return standardRegionUnsafe(s, base) catch |err| {
        try @import("native_ai_partial_json.zig").discard(s.engine, err, generation);
        return c.pi_js_undefined();
    };
}
fn standardRegionUnsafe(s: *Scope, base: c.JSValue) !c.JSValue {
    const url = try s.own(try v.js.builtin(s.engine, "URL", &.{base}));
    const hostname = try s.invoke(try s.get(url, "hostname"), "toLowerCase", &.{});
    const match = try s.invoke(hostname, "match", &.{try literal(s, "^bedrock-runtime(?:-fips)?\\.([a-z0-9-]+)\\.amazonaws\\.com(?:\\.cn)?$")});
    return if (v.nullish(match)) c.pi_js_undefined() else v.at(s, match, 1);
}
fn field(object: std.json.Value, name: []const u8) ?[]const u8 {
    const value = if (object == .object) object.object.get(name) orelse return null else return null;
    return if (value == .string) value.string else null;
}
pub fn prepare(a: std.mem.Allocator, request: prep.View, data: []const u8, budget: prep.Budget) !prep.Prepared {
    // The central HTTP worker supervises this complete byte-only chain with
    // native_ai_http_prepare_run; provider subrequests consume the same Budget.
    _ = try budget.remaining();
    var parsed = try std.json.parseFromSlice(std.json.Value, a, data, .{});
    defer parsed.deinit();
    const input = parsed.value;
    var env: std.process.Environ.Map = .init(a);
    defer env.deinit();
    if (input.object.get("env")) |values| if (values == .object) {
        var entries = values.object.iterator();
        while (entries.next()) |entry| if (entry.value_ptr.* == .string) try env.put(entry.key_ptr.*, entry.value_ptr.string);
    };
    var profile_config = if (field(input, "region") == null) try @import("../ai/aws_credentials.zig").loadProfileByName(a, budget.io, &env, field(input, "profile") orelse env.get("AWS_PROFILE") orelse "default") else null;
    defer if (profile_config) |*profile| profile.deinit(a);
    const region = field(input, "region") orelse (if (profile_config) |profile| profile.region else null) orelse return error.MissingBedrockRegion;
    const base = if (field(input, "baseUrl")) |url| try a.dupe(u8, url) else try std.fmt.allocPrint(a, "https://bedrock-runtime.{s}.{s}", .{ region, if (std.mem.startsWith(u8, region, "cn-")) "amazonaws.com.cn" else "amazonaws.com" });
    defer a.free(base);
    const url = try @import("../ai/bedrock.zig").buildConverseStreamUrl(a, base, field(input, "modelId") orelse return error.MissingBedrockModelId);
    errdefer a.free(url);
    const now: i64 = @intCast(@divFloor(std.Io.Clock.real.now(budget.io).toMilliseconds(), 1000));
    const skip = if (input.object.get("skipAuth")) |value| value == .bool and value.bool else false;
    const sdk_bearer_selected = if (input.object.get("sdkBearerSelected")) |value| value == .bool and value.bool else false;
    const bearer_token = field(input, "bearerToken") orelse if (sdk_bearer_selected) field(input, "sdkBearerToken") else null;
    if (sdk_bearer_selected and (bearer_token == null or bearer_token.?.len == 0)) {
        var failure = try @import("native_ai_http_failure.zig").Owned.init(a, "Error", "request could not be signed with `token` since the `token` is not defined", null);
        errdefer failure.deinit(a);
        _ = try budget.remaining();
        return .{ .url = url, .headers = try a.alloc(std.http.Header, 0), .failure = failure };
    }
    if (bearer_token) |bearer| {
        const value = try std.fmt.allocPrint(a, "Bearer {s}", .{bearer});
        defer a.free(value);
        const headers = try a.alloc(std.http.Header, 1);
        errdefer a.free(headers);
        const name = try a.dupe(u8, "authorization");
        errdefer a.free(name);
        headers[0] = .{ .name = name, .value = try a.dupe(u8, value) };
        return .{ .headers = headers, .url = url };
    }
    var credentials = if (skip) @import("native_ai_aws_credentials.zig").Credentials{ .access_key_id = try a.dupe(u8, "dummy-access-key"), .secret_access_key = try a.dupe(u8, "dummy-secret-key") } else credentials: {
        var result = try @import("native_ai_aws_credentials.zig").resolveResult(a, budget.io, &env, field(input, "profile"), region, now, budget);
        switch (result) {
            .credentials => |value| break :credentials value,
            .failure => |value| {
                errdefer result.deinit(a);
                _ = try budget.remaining();
                return .{ .url = url, .headers = try a.alloc(std.http.Header, 0), .failure = value };
            },
        }
    };
    defer credentials.deinit(a);
    var signed = try @import("native_ai_aws_sigv4.zig").sign(a, @tagName(request.method), url, request.payload, request.headers, credentials.borrowed(), region, now);
    defer signed.deinit(a);
    var headers: std.ArrayList(std.http.Header) = .empty;
    errdefer {
        for (headers.items) |header| {
            a.free(header.name);
            a.free(header.value);
        }
        headers.deinit(a);
    }
    try add(a, &headers, "authorization", signed.authorization);
    try add(a, &headers, "x-amz-date", &signed.amz_date);
    try add(a, &headers, "x-amz-content-sha256", &signed.payload_hash);
    if (credentials.session_token) |token| try add(a, &headers, "x-amz-security-token", token);
    _ = try budget.remaining();
    return .{ .headers = try headers.toOwnedSlice(a), .url = url };
}
fn add(a: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    const owned_name = try a.dupe(u8, name);
    errdefer a.free(owned_name);
    const owned_value = try a.dupe(u8, value);
    errdefer a.free(owned_value);
    try headers.append(a, .{ .name = owned_name, .value = owned_value });
}
