//! Byte-only SSO token cache, OIDC refresh, and GetRoleCredentials chain.
//! Exact SDK error strings remain subject to the controlled genuine Source gate.
const std = @import("std");
const cache = @import("native_ai_aws_cache.zig");
const types = @import("native_ai_aws_types.zig");
const Profile = @import("../ai/aws_credentials.zig").OwnedProfile;
const Budget = @import("native_ai_http_prepare.zig").Budget;
const http = @import("../ai/bootstrap_http.zig");
const parseDate = @import("../ai/aws_web_identity.zig").parseRfc3339;
const refresh_message = "To refresh this SSO session run 'aws sso login' with the corresponding profile.";
const legacy_message = "To refresh this SSO session run aws sso login with the corresponding profile.";
var refresh_mutex: std.Io.Mutex = .init;
var refresh_attempts: std.StringHashMapUnmanaged(i64) = .empty;

fn fail(a: std.mem.Allocator, message: []const u8) !types.Result {
    return types.failure(a, "CredentialsProviderError", message, false);
}
fn expired(a: std.mem.Allocator) !types.Result {
    return fail(a, "The SSO session associated with this profile has expired. " ++ legacy_message);
}
fn tokenExpired(a: std.mem.Allocator) !types.Result {
    return fail(a, "Token is expired. " ++ refresh_message);
}
fn request(a: std.mem.Allocator, budget: Budget, url: []const u8, method: std.http.Method, payload: ?[]const u8, headers: []const std.http.Header) !http.Response {
    return http.request(a, budget.io, .{ .url = url, .method = method, .payload = payload, .headers = headers, .options = .{ .abort_flag = budget.abort_flag, .policy = .{ .max_retries = 0, .timeout_ms = (try budget.remaining()) orelse 15000 } } });
}
fn canRefresh(io: std.Io, session: []const u8, now: i64) !bool {
    try refresh_mutex.lock(io);
    defer refresh_mutex.unlock(io);
    if (refresh_attempts.get(session)) |previous| if (now - previous < 30) return false;
    const a = std.heap.page_allocator;
    const owned = try a.dupe(u8, session);
    errdefer a.free(owned);
    const entry = try refresh_attempts.getOrPut(a, session);
    if (!entry.found_existing) entry.key_ptr.* = owned else a.free(owned);
    entry.value_ptr.* = now;
    return true;
}
fn recentRefresh(io: std.Io, session: []const u8, now: i64) !bool {
    try refresh_mutex.lock(io);
    defer refresh_mutex.unlock(io);
    return if (refresh_attempts.get(session)) |previous| now - previous < 30 else false;
}
fn missingKey(a: std.mem.Allocator, key: []const u8, for_refresh: bool) !types.Result {
    const message = try std.fmt.allocPrint(a, "Value not present for '{s}' in SSO Token{s}. {s}", .{ key, if (for_refresh) ". Cannot refresh" else "", refresh_message });
    defer a.free(message);
    return fail(a, message);
}
fn invalidProfile(a: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, profile: *const Profile) !types.Result {
    const section_name = if (std.mem.eql(u8, profile.profile_name, "default")) try a.dupe(u8, "default") else try std.fmt.allocPrint(a, "profile {s}", .{profile.profile_name});
    defer a.free(section_name);
    var fields = try cache.section(a, io, env, section_name);
    defer if (fields) |*owned| cache.deinitFields(a, owned);
    const keys = if (fields) |owned| try std.mem.join(a, ", ", owned.keys()) else try a.dupe(u8, "");
    defer a.free(keys);
    const message = try std.fmt.allocPrint(a, "Profile is configured with invalid SSO credentials. Required parameters \"sso_account_id\", \"sso_region\", \"sso_role_name\", \"sso_start_url\". Got {s}\nReference: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html", .{keys});
    defer a.free(message);
    return fail(a, message);
}
pub fn resolve(a: std.mem.Allocator, env: *const std.process.Environ.Map, profile: *const Profile, now: i64, budget: Budget) !types.Result {
    _ = try budget.remaining();
    var session_fields: ?cache.Fields = null;
    defer if (session_fields) |*owned| cache.deinitFields(a, owned);
    var region = profile.sso_region;
    var start_url = profile.sso_start_url;
    if (profile.sso_session) |session| {
        const name = try std.fmt.allocPrint(a, "sso-session {s}", .{session});
        defer a.free(name);
        session_fields = try cache.section(a, budget.io, env, name);
        if (session_fields == null) return types.failure(a, "TypeError", "Cannot read properties of undefined (reading 'sso_region')", null);
        region = session_fields.?.get("sso_region");
        start_url = session_fields.?.get("sso_start_url");
    }
    if (region == null or region.?.len == 0 or start_url == null or start_url.?.len == 0 or profile.sso_account_id == null or profile.sso_account_id.?.len == 0 or profile.sso_role_name == null or profile.sso_role_name.?.len == 0) return invalidProfile(a, budget.io, env, profile);
    const file = try cache.path(a, env, .sso, profile.sso_session orelse start_url.?);
    defer a.free(file);
    var token = cache.read(a, budget.io, file) catch |err| {
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        if (profile.sso_session == null) return fail(a, "The SSO session associated with this profile is invalid. " ++ legacy_message);
        const message = try std.fmt.allocPrint(a, "The SSO session token associated with profile={s} was not found or is invalid. {s}", .{ profile.profile_name, refresh_message });
        defer a.free(message);
        return fail(a, message);
    };
    defer token.deinit();
    var access = types.string(token.value, "accessToken");
    const expires = types.string(token.value, "expiresAt");
    if (profile.sso_session != null) {
        if (access == null) return missingKey(a, "accessToken", false);
        if (expires == null) return missingKey(a, "expiresAt", false);
    }
    var expiration = if (expires) |value| parseDate(value) catch null else null;
    var refreshed: ?std.json.Parsed(std.json.Value) = null;
    defer if (refreshed) |*owned| owned.deinit();
    if (profile.sso_session) |session| {
        if (expiration == null or expiration.? - now <= 300) {
            if (try recentRefresh(budget.io, session, now)) {
                if (expiration != null and expiration.? < now) return tokenExpired(a);
            } else {
                inline for (.{ "clientId", "clientSecret", "refreshToken" }) |key| if (token.value != .object or !token.value.object.contains(key)) return missingKey(a, key, true);
                if (try canRefresh(budget.io, session, now)) {
                    refreshed = try refresh(a, env, &token, region.?, file, now, budget);
                    if (refreshed) |value| {
                        access = types.string(value.value, "accessToken");
                        expiration = parseDate(types.string(value.value, "expiresAt").?) catch null;
                    } else if (expiration != null and expiration.? < now) return tokenExpired(a);
                } else if (expiration != null and expiration.? < now) return tokenExpired(a);
            }
        }
    }
    if (expiration != null and expiration.? <= now) return expired(a);
    const endpoint = if (env.get("AWS_ENDPOINT_URL_SSO")) |override| try a.dupe(u8, override) else try std.fmt.allocPrint(a, "https://portal.sso.{s}.amazonaws.com", .{region.?});
    defer a.free(endpoint);
    const account = try encode(a, profile.sso_account_id.?);
    defer a.free(account);
    const role = try encode(a, profile.sso_role_name.?);
    defer a.free(role);
    const url = try std.fmt.allocPrint(a, "{s}/federation/credentials?account_id={s}&role_name={s}", .{ std.mem.trimEnd(u8, endpoint, "/"), account, role });
    defer a.free(url);
    var response = try request(a, budget, url, .GET, null, &.{.{ .name = "x-amz-sso_bearer_token", .value = access orelse "" }});
    defer {
        @memset(response.body, 0);
        response.deinit(a);
    }
    var parsed = try std.json.parseFromSlice(std.json.Value, a, response.body, .{});
    defer parsed.deinit();
    if (response.status >= 300) return serviceFailure(a, parsed.value);
    const credentials = if (parsed.value == .object) parsed.value.object.get("roleCredentials") orelse .null else .null;
    const expiration_value = if (credentials == .object) credentials.object.get("expiration") orelse .null else .null;
    const expiration_ms: ?i64 = switch (expiration_value) {
        .integer => |value| value,
        .float => |value| if (std.math.isFinite(value)) @intFromFloat(value) else null,
        else => null,
    };
    inline for (.{ "accessKeyId", "secretAccessKey", "sessionToken" }) |key| if (types.string(credentials, key) == null or types.string(credentials, key).?.len == 0) return fail(a, "SSO returns an invalid temporary credential.");
    if (expiration_ms == null or expiration_ms.? == 0) return fail(a, "SSO returns an invalid temporary credential.");
    _ = try budget.remaining();
    var result = try types.fromJson(a, credentials, @divFloor(expiration_ms.?, 1000));
    // The installed SDK RoleCredentials schema has exactly four members;
    // unknown accountId/credentialScope wire fields are not exposed.
    if (result.account_id) |value| a.free(value);
    if (result.credential_scope) |value| a.free(value);
    result.account_id = null;
    result.credential_scope = null;
    return .{ .credentials = result };
}
fn refresh(a: std.mem.Allocator, env: *const std.process.Environ.Map, token: *std.json.Parsed(std.json.Value), region: []const u8, file: []const u8, now: i64, budget: Budget) !?std.json.Parsed(std.json.Value) {
    const body = try std.json.Stringify.valueAlloc(a, .{ .clientId = types.string(token.value, "clientId"), .clientSecret = types.string(token.value, "clientSecret"), .grantType = "refresh_token", .refreshToken = types.string(token.value, "refreshToken") }, .{});
    defer {
        @memset(body, 0);
        a.free(body);
    }
    const endpoint = if (env.get("AWS_ENDPOINT_URL_SSO_OIDC")) |override| try a.dupe(u8, override) else try std.fmt.allocPrint(a, "https://oidc.{s}.amazonaws.com", .{region});
    defer a.free(endpoint);
    const url = try std.fmt.allocPrint(a, "{s}/token", .{std.mem.trimEnd(u8, endpoint, "/")});
    defer a.free(url);
    var response = request(a, budget, url, .POST, body, &.{.{ .name = "content-type", .value = "application/json" }}) catch |err| {
        _ = try budget.remaining();
        if (err == error.OutOfMemory or err == error.Canceled) return err;
        return null;
    };
    defer {
        @memset(response.body, 0);
        response.deinit(a);
    }
    if (response.status >= 300) return null;
    var parsed = std.json.parseFromSlice(std.json.Value, a, response.body, .{ .allocate = .alloc_always }) catch |err| {
        if (err == error.OutOfMemory) return err;
        return null;
    };
    defer parsed.deinit();
    const access = types.string(parsed.value, "accessToken") orelse return null;
    const expires = if (parsed.value == .object) parsed.value.object.get("expiresIn") orelse return null else return null;
    const seconds = switch (expires) {
        .integer => |value| value,
        .float => |value| if (std.math.isFinite(value)) @as(i64, @intFromFloat(value)) else return null,
        else => return null,
    };
    const expiration = try cache.iso(a, std.math.add(i64, now, seconds) catch return null);
    defer a.free(expiration);
    const arena = token.arena.allocator();
    try token.value.object.put(arena, "accessToken", .{ .string = try arena.dupe(u8, access) });
    try token.value.object.put(arena, "expiresAt", .{ .string = try arena.dupe(u8, expiration) });
    if (types.string(parsed.value, "refreshToken")) |value| try token.value.object.put(arena, "refreshToken", .{ .string = try arena.dupe(u8, value) }) else _ = token.value.object.swapRemove("refreshToken");
    _ = try budget.remaining();
    cache.write(a, budget.io, file, token.value) catch |err| {
        if (err == error.Canceled) return err;
    };
    const raw = try std.json.Stringify.valueAlloc(a, token.value, .{});
    defer {
        @memset(raw, 0);
        a.free(raw);
    }
    return try std.json.parseFromSlice(std.json.Value, a, raw, .{ .allocate = .alloc_always });
}
fn serviceFailure(a: std.mem.Allocator, value: std.json.Value) !types.Result {
    const name = types.string(value, "__type") orelse types.string(value, "code") orelse "UnknownError";
    const message = types.string(value, "message") orelse types.string(value, "Message") orelse "UnknownError";
    const text = try std.fmt.allocPrint(a, "{s}: {s}", .{ name, message });
    defer a.free(text);
    return fail(a, text);
}
fn encode(a: std.mem.Allocator, text: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(a);
    const hex = "0123456789ABCDEF";
    for (text) |byte| if (std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "-_.!~*'()", byte) != null) {
        try result.append(a, byte);
    } else {
        try result.appendSlice(a, &.{ '%', hex[byte >> 4], hex[byte & 15] });
    };
    return result.toOwnedSlice(a);
}
