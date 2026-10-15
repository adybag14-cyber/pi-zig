//! SDK login cache and native DPoP refresh. Byte-only, bounded by the shared request Budget.
const std = @import("std");
const cache = @import("native_ai_aws_cache.zig");
const types = @import("native_ai_aws_types.zig");
const Budget = @import("native_ai_http_prepare.zig").Budget;
const Profile = @import("../ai/aws_credentials.zig").OwnedProfile;
const parseDate = @import("../ai/aws_web_identity.zig").parseRfc3339;
const Loaded = union(enum) { token: std.json.Parsed(std.json.Value), failure: types.Failure };
fn fail(a: std.mem.Allocator, message: []const u8, next: bool) !types.Result {
    return types.failure(a, "CredentialsProviderError", message, next);
}
fn property(value: std.json.Value, key: []const u8) std.json.Value {
    return if (value == .object) value.object.get(key) orelse .null else .null;
}
fn truthy(value: std.json.Value) bool {
    return switch (value) {
        .null => false,
        .bool => |v| v,
        .integer => |v| v != 0,
        .float => |v| v != 0 and !std.math.isNan(v),
        .string => |v| v.len != 0,
        else => true,
    };
}
fn expiration(value: std.json.Value) ?i64 {
    return if (types.string(property(value, "accessToken"), "expiresAt")) |text| parseDate(text) catch null else null;
}
fn load(a: std.mem.Allocator, io: std.Io, file: []const u8) !Loaded {
    var parsed = cache.read(a, io, file) catch |err| {
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        // The genuine Source gate records platform-specific file/JSON diagnostics.
        const message = try std.fmt.allocPrint(a, "Failed to load token from {s}: {s}", .{ file, @errorName(err) });
        defer a.free(message);
        return .{ .failure = try types.Failure.init(a, "CredentialsProviderError", message, false) };
    };
    errdefer parsed.deinit();
    var missing: std.ArrayList([]const u8) = .empty;
    defer missing.deinit(a);
    inline for (.{ "accessToken", "clientId", "refreshToken", "dpopKey" }) |key| if (!truthy(property(parsed.value, key))) try missing.append(a, key);
    if (!truthy(property(property(parsed.value, "accessToken"), "accountId"))) try missing.append(a, "accountId");
    if (missing.items.len > 0) {
        const fields = try std.mem.join(a, ", ", missing.items);
        defer a.free(fields);
        const message = try std.fmt.allocPrint(a, "Failed to load token from {s}: CredentialsProviderError: Token validation failed, missing fields: {s}", .{ file, fields });
        defer a.free(message);
        const failure = try types.Failure.init(a, "CredentialsProviderError", message, false);
        parsed.deinit();
        return .{ .failure = failure };
    }
    return .{ .token = parsed };
}
pub fn resolve(a: std.mem.Allocator, env: *const std.process.Environ.Map, profile: *const Profile, region: []const u8, now: i64, budget: Budget) !types.Result {
    _ = try budget.remaining();
    const file = try cache.path(a, env, .login, profile.login_session.?);
    defer a.free(file);
    var token = switch (try load(a, budget.io, file)) {
        .token => |value| value,
        .failure => |value| return .{ .failure = value },
    };
    defer token.deinit();
    const expiry = expiration(token.value);
    if (expiry == null or expiry.? - now > 300) return .{ .credentials = try types.fromJson(a, property(token.value, "accessToken"), expiry) };
    // The SDK rereads disk before refresh, retaining the earlier valid token if
    // another writer replaced it with an expired token.
    var disk: ?std.json.Parsed(std.json.Value) = switch (try load(a, budget.io, file)) {
        .token => |value| value,
        .failure => |value| failed: {
            var owned = value;
            owned.deinit(a);
            break :failed null;
        },
    };
    defer if (disk) |*owned| owned.deinit();
    var fresh = &token;
    if (disk) |*value| {
        const disk_expiry = expiration(value.value);
        if (!(disk_expiry != null and disk_expiry.? <= now and expiry.? > now)) fresh = value;
    }
    const fresh_expiry = expiration(fresh.value);
    if (fresh_expiry != null and fresh_expiry.? - now > 300) return .{ .credentials = try types.fromJson(a, property(fresh.value, "accessToken"), fresh_expiry) };
    const endpoint = if (env.get("AWS_ENDPOINT_URL_SIGNIN")) |override| try a.dupe(u8, override) else try std.fmt.allocPrint(a, "https://{s}.signin.aws.amazon.com", .{profile.region orelse region});
    defer a.free(endpoint);
    const url = try std.fmt.allocPrint(a, "{s}/v1/token", .{std.mem.trimEnd(u8, endpoint, "/")});
    defer a.free(url);
    // The interceptor loads the key again at request finalization.
    var proof_token = switch (try load(a, budget.io, file)) {
        .token => |value| value,
        .failure => |value| return .{ .failure = value },
    };
    defer proof_token.deinit();
    const proof = @import("native_ai_aws_dpop.zig").proof(a, budget.io, types.string(proof_token.value, "dpopKey") orelse "", "POST", url, now) catch |err| {
        _ = try budget.remaining();
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        const message = try std.fmt.allocPrint(a, "Failed to generate Dpop proof: {s}", .{@errorName(err)});
        defer a.free(message);
        return fail(a, message, false);
    };
    defer a.free(proof);
    // tokenInput is Smithy's HTTP payload binding; the wire body is the inner object.
    const body = try std.json.Stringify.valueAlloc(a, .{ .clientId = types.string(fresh.value, "clientId"), .refreshToken = types.string(fresh.value, "refreshToken"), .grantType = "refresh_token" }, .{});
    defer {
        @memset(body, 0);
        a.free(body);
    }
    var response = @import("../ai/bootstrap_http.zig").request(a, budget.io, .{ .url = url, .method = .POST, .payload = body, .headers = &.{ .{ .name = "content-type", .value = "application/json" }, .{ .name = "DPoP", .value = proof } }, .options = .{ .abort_flag = budget.abort_flag, .policy = .{ .max_retries = 0, .timeout_ms = (try budget.remaining()) orelse 15000 } } }) catch |err| {
        _ = try budget.remaining();
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        return fallback(a, fresh.value, fresh_expiry, now, @errorName(err));
    };
    defer {
        @memset(response.body, 0);
        response.deinit(a);
    }
    var parsed = std.json.parseFromSlice(std.json.Value, a, response.body, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return fallback(a, fresh.value, fresh_expiry, now, @errorName(err));
    };
    defer parsed.deinit();
    if (response.status >= 300) {
        const name = types.string(parsed.value, "__type") orelse types.string(parsed.value, "code") orelse "UnknownError";
        const code = if (std.mem.lastIndexOfScalar(u8, name, '#')) |index| name[index + 1 ..] else name;
        const service_message = types.string(parsed.value, "message") orelse types.string(parsed.value, "Message") orelse "UnknownError";
        if (std.mem.eql(u8, code, "AccessDeniedException")) {
            const kind = types.string(parsed.value, "error") orelse "";
            if (std.mem.eql(u8, kind, "TOKEN_EXPIRED")) return fail(a, "Your session has expired. Please reauthenticate.", false);
            if (std.mem.eql(u8, kind, "USER_CREDENTIALS_CHANGED")) return fail(a, "Unable to refresh credentials because of a change in your password. Please reauthenticate with your new password.", false);
            if (std.mem.eql(u8, kind, "INSUFFICIENT_PERMISSIONS")) return fail(a, "Unable to refresh credentials due to insufficient permissions. You may be missing permission for the 'CreateOAuth2Token' action.", false);
            const message = try std.fmt.allocPrint(a, "Failed to refresh token: {s}: {s}. Please re-authenticate using `aws login`", .{ code, service_message });
            defer a.free(message);
            return fail(a, message, false);
        }
        const message = try std.fmt.allocPrint(a, "{s}: {s}", .{ code, service_message });
        defer a.free(message);
        return fallback(a, fresh.value, fresh_expiry, now, message);
    }
    const access = property(parsed.value, "accessToken");
    const refresh = types.string(parsed.value, "refreshToken");
    var valid = refresh != null and refresh.?.len > 0;
    inline for (.{ "accessKeyId", "secretAccessKey", "sessionToken" }) |key| valid = valid and truthy(property(access, key));
    if (!valid) return fallback(a, fresh.value, fresh_expiry, now, "CredentialsProviderError: Token refresh response missing required fields");
    const seconds: i64 = switch (property(parsed.value, "expiresIn")) {
        .integer => |value| value,
        .float => |value| if (std.math.isFinite(value)) @intFromFloat(value) else 900,
        else => 900,
    };
    const new_expiration = try std.math.add(i64, now, seconds);
    const iso = try cache.iso(a, new_expiration);
    defer a.free(iso);
    const old_raw = try std.json.Stringify.valueAlloc(a, fresh.value, .{});
    defer {
        @memset(old_raw, 0);
        a.free(old_raw);
    }
    var updated = try std.json.parseFromSlice(std.json.Value, a, old_raw, .{ .allocate = .alloc_always });
    defer updated.deinit();
    const arena = updated.arena.allocator();
    const old_access = updated.value.object.getPtr("accessToken").?;
    inline for (.{ "accessKeyId", "secretAccessKey", "sessionToken" }) |key| try old_access.object.put(arena, key, .{ .string = try arena.dupe(u8, types.string(access, key).?) });
    try old_access.object.put(arena, "expiresAt", .{ .string = try arena.dupe(u8, iso) });
    try updated.value.object.put(arena, "refreshToken", .{ .string = try arena.dupe(u8, refresh.?) });
    _ = try budget.remaining();
    cache.write(a, budget.io, file, updated.value) catch |err| {
        _ = try budget.remaining();
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        // SDK save errors enter the same fallback using the pre-refresh token.
        return fallback(a, fresh.value, fresh_expiry, now, @errorName(err));
    };
    return .{ .credentials = try types.fromJson(a, property(updated.value, "accessToken"), new_expiration) };
}
fn fallback(a: std.mem.Allocator, value: std.json.Value, expiry: ?i64, now: i64, reason: []const u8) !types.Result {
    if (expiry != null and expiry.? > now) return .{ .credentials = try types.fromJson(a, property(value, "accessToken"), expiry) };
    const message = try std.fmt.allocPrint(a, "Failed to refresh token: {s}. Please re-authenticate using aws login", .{reason});
    defer a.free(message);
    return fail(a, message, true);
}
