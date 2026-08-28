//! Native EC2 Instance Metadata Service (IMDS) credential provider.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");
const shared = @import("aws_credentials.zig");
const web = @import("aws_web_identity.zig");
const bootstrap_http = @import("bootstrap_http.zig");

pub const Config = struct {
    endpoint: []const u8,
    v1_disabled: bool = false,
};

pub const OwnedImdsCredentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: []u8,
    expiration_unix: i64,
    pub fn deinit(self: *OwnedImdsCredentials, gpa: std.mem.Allocator) void {
        gpa.free(self.access_key_id);
        gpa.free(self.secret_access_key);
        gpa.free(self.session_token);
        self.* = undefined;
    }
    pub fn borrowed(self: *const OwnedImdsCredentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};

pub fn metadataDisabled(env: *const std.process.Environ.Map) bool {
    return if (env.get("AWS_EC2_METADATA_DISABLED")) |v| truthy(v) else false;
}

pub fn resolveConfig(env: *const std.process.Environ.Map, profile: ?*const shared.OwnedProfile) !Config {
    if (metadataDisabled(env)) return error.Ec2MetadataDisabled;
    if (env.get("AWS_EC2_METADATA_SERVICE_ENDPOINT")) |endpoint| {
        try validateEndpoint(endpoint);
        return .{ .endpoint = endpoint, .v1_disabled = resolveV1Disabled(env, profile) };
    }
    if (profile) |p| if (p.ec2_metadata_service_endpoint) |endpoint| {
        try validateEndpoint(endpoint);
        return .{ .endpoint = endpoint, .v1_disabled = resolveV1Disabled(env, profile) };
    };
    const mode = env.get("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE") orelse if (profile) |p| p.ec2_metadata_service_endpoint_mode orelse "IPv4" else "IPv4";
    const endpoint = if (std.ascii.eqlIgnoreCase(mode, "IPv6"))
        "http://[fd00:ec2::254]"
    else if (std.ascii.eqlIgnoreCase(mode, "IPv4"))
        "http://169.254.169.254"
    else
        return error.InvalidEc2MetadataEndpointMode;
    return .{ .endpoint = endpoint, .v1_disabled = resolveV1Disabled(env, profile) };
}

fn resolveV1Disabled(env: *const std.process.Environ.Map, profile: ?*const shared.OwnedProfile) bool {
    if (env.get("AWS_EC2_METADATA_V1_DISABLED")) |v| return truthy(v);
    if (profile) |p| if (p.ec2_metadata_v1_disabled) |v| return v;
    return false;
}

fn truthy(v: []const u8) bool {
    return std.ascii.eqlIgnoreCase(v, "true") or std.mem.eql(u8, v, "1");
}

fn validateEndpoint(endpoint: []const u8) !void {
    if (!(std.ascii.startsWithIgnoreCase(endpoint, "http://") or std.ascii.startsWithIgnoreCase(endpoint, "https://"))) return error.InvalidEc2MetadataEndpoint;
}

pub fn shouldFallbackToV1(status: u16, v1_disabled: bool) bool {
    if (v1_disabled) return false;
    return status == 403 or status == 404 or status == 405;
}

pub fn validateRoleName(raw: []const u8) ![]const u8 {
    const role = std.mem.trim(u8, raw, " \t\r\n");
    if (role.len == 0 or role.len > 256) return error.InvalidImdsRoleName;
    for (role) |c| {
        if (c <= 0x20 or c == '/' or c == '\\' or c == '?' or c == '#') return error.InvalidImdsRoleName;
    }
    return role;
}

pub fn parseCredentialJson(gpa: std.mem.Allocator, raw: []const u8) !OwnedImdsCredentials {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidImdsCredentialResponse;
    if (parsed.value.object.get("Code")) |code| {
        if (code != .string or !std.ascii.eqlIgnoreCase(code.string, "Success")) return error.ImdsCredentialProviderError;
    }
    const access = parsed.value.object.get("AccessKeyId") orelse return error.InvalidImdsCredentialResponse;
    const secret = parsed.value.object.get("SecretAccessKey") orelse return error.InvalidImdsCredentialResponse;
    const token = parsed.value.object.get("Token") orelse return error.InvalidImdsCredentialResponse;
    const expiration = parsed.value.object.get("Expiration") orelse return error.InvalidImdsCredentialResponse;
    if (access != .string or secret != .string or token != .string or expiration != .string) return error.InvalidImdsCredentialResponse;
    const a = try gpa.dupe(u8, access.string);
    errdefer gpa.free(a);
    const s = try gpa.dupe(u8, secret.string);
    errdefer gpa.free(s);
    const t = try gpa.dupe(u8, token.string);
    errdefer gpa.free(t);
    return .{ .access_key_id = a, .secret_access_key = s, .session_token = t, .expiration_unix = try web.parseRfc3339(expiration.string) };
}

const TokenMode = union(enum) { v2: []u8, v1 };

fn metadataOptions(options_in: bootstrap_http.Options) bootstrap_http.Options {
    var options = options_in;
    // IMDS credentials and the IMDSv2 token must never be exposed to a global
    // HTTP proxy. Retry, timeout, and cancellation policy are still inherited.
    options.proxy = .{};
    return options;
}

fn fetchTokenWithOptions(gpa: std.mem.Allocator, io: Io, config: Config, options_in: bootstrap_http.Options) !TokenMode {
    const url = try std.fmt.allocPrint(gpa, "{s}/latest/api/token", .{std.mem.trimEnd(u8, config.endpoint, "/")});
    defer gpa.free(url);
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .PUT,
        .headers = &.{.{ .name = "x-aws-ec2-metadata-token-ttl-seconds", .value = "21600" }},
        .options = metadataOptions(options_in),
    });
    defer response.deinit(gpa);
    if (response.status == 200) {
        const token = std.mem.trim(u8, response.body, " \t\r\n");
        if (token.len == 0) return error.InvalidImdsV2Token;
        return .{ .v2 = try gpa.dupe(u8, token) };
    }
    if (shouldFallbackToV1(response.status, config.v1_disabled)) return .v1;
    return error.ImdsV2TokenRequestFailed;
}

fn fetchTextWithOptions(gpa: std.mem.Allocator, io: Io, url: []const u8, token: ?[]const u8, options_in: bootstrap_http.Options) ![]u8 {
    var header: [1]std.http.Header = undefined;
    const extra: []const std.http.Header = if (token) |t| blk: {
        header[0] = .{ .name = "x-aws-ec2-metadata-token", .value = t };
        break :blk header[0..1];
    } else &.{};
    var response = try bootstrap_http.request(gpa, io, .{
        .url = url,
        .method = .GET,
        .headers = extra,
        .options = metadataOptions(options_in),
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.ImdsHttpError;
    return try gpa.dupe(u8, response.body);
}

pub fn fetchCredentials(gpa: std.mem.Allocator, io: Io, config: Config) !OwnedImdsCredentials {
    return fetchCredentialsWithOptions(gpa, io, config, .{});
}

pub fn fetchCredentialsWithOptions(gpa: std.mem.Allocator, io: Io, config: Config, options: bootstrap_http.Options) !OwnedImdsCredentials {
    const mode = try fetchTokenWithOptions(gpa, io, config, options);
    defer switch (mode) {
        .v2 => |token| gpa.free(token),
        .v1 => {},
    };
    const token: ?[]const u8 = switch (mode) {
        .v2 => |v| v,
        .v1 => null,
    };
    const root = std.mem.trimEnd(u8, config.endpoint, "/");
    const role_url = try std.fmt.allocPrint(gpa, "{s}/latest/meta-data/iam/security-credentials/", .{root});
    defer gpa.free(role_url);
    const role_raw = try fetchTextWithOptions(gpa, io, role_url, token, options);
    defer gpa.free(role_raw);
    const role = try validateRoleName(role_raw);
    const cred_url = try std.fmt.allocPrint(gpa, "{s}/latest/meta-data/iam/security-credentials/{s}", .{ root, role });
    defer gpa.free(cred_url);
    const credential_raw = try fetchTextWithOptions(gpa, io, cred_url, token, options);
    defer gpa.free(credential_raw);
    return try parseCredentialJson(gpa, credential_raw);
}

test "IMDS config supports IPv6 and profile v1 disable" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_EC2_METADATA_SERVICE_ENDPOINT_MODE", "IPv6");
    var p = shared.OwnedProfile{ .profile_name = try gpa.dupe(u8, "default"), .ec2_metadata_v1_disabled = true };
    defer p.deinit(gpa);
    const cfg = try resolveConfig(&env, &p);
    try std.testing.expectEqualStrings("http://[fd00:ec2::254]", cfg.endpoint);
    try std.testing.expect(cfg.v1_disabled);
}

test "IMDSv1 fallback is limited to token 403 404 405" {
    try std.testing.expect(shouldFallbackToV1(403, false));
    try std.testing.expect(shouldFallbackToV1(404, false));
    try std.testing.expect(shouldFallbackToV1(405, false));
    try std.testing.expect(!shouldFallbackToV1(500, false));
    try std.testing.expect(!shouldFallbackToV1(403, true));
}

test "IMDS validates role names and credentials" {
    try std.testing.expectEqualStrings("MyRole", try validateRoleName(" MyRole\n"));
    try std.testing.expectError(error.InvalidImdsRoleName, validateRoleName("bad/role"));
    const gpa = std.testing.allocator;
    var c = try parseCredentialJson(gpa, "{\"Code\":\"Success\",\"AccessKeyId\":\"ASIA_IMDS\",\"SecretAccessKey\":\"secret\",\"Token\":\"token\",\"Expiration\":\"2026-08-09T12:34:56Z\"}");
    defer c.deinit(gpa);
    try std.testing.expectEqual(@as(i64, 1786278896), c.expiration_unix);
}
