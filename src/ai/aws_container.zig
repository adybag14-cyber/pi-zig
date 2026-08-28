//! AWS ECS/EKS container credential provider.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");
const web = @import("aws_web_identity.zig");
const bootstrap_http = @import("bootstrap_http.zig");

pub const OwnedConfig = struct {
    url: []u8,
    authorization: ?[]u8 = null,
    pub fn deinit(self: *OwnedConfig, gpa: std.mem.Allocator) void {
        gpa.free(self.url);
        if (self.authorization) |v| gpa.free(v);
        self.* = undefined;
    }
};

pub const OwnedContainerCredentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: []u8,
    expiration_unix: i64,
    pub fn deinit(self: *OwnedContainerCredentials, gpa: std.mem.Allocator) void {
        gpa.free(self.access_key_id);
        gpa.free(self.secret_access_key);
        gpa.free(self.session_token);
        self.* = undefined;
    }
    pub fn borrowed(self: *const OwnedContainerCredentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};

pub fn resolveConfig(gpa: std.mem.Allocator, io: Io, env: *const std.process.Environ.Map) !?OwnedConfig {
    var url: ?[]u8 = null;
    if (env.get("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")) |relative| {
        if (relative.len == 0 or relative[0] != '/') return error.InvalidContainerRelativeUri;
        url = try std.fmt.allocPrint(gpa, "http://169.254.170.2{s}", .{relative});
    } else if (env.get("AWS_CONTAINER_CREDENTIALS_FULL_URI")) |full| {
        if (!(std.ascii.startsWithIgnoreCase(full, "http://") or std.ascii.startsWithIgnoreCase(full, "https://"))) return error.InvalidContainerCredentialUri;
        url = try gpa.dupe(u8, full);
    } else return null;
    errdefer if (url) |v| gpa.free(v);

    var authorization: ?[]u8 = null;
    errdefer if (authorization) |v| gpa.free(v);
    if (env.get("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE")) |path| {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(16 * 1024));
        const trimmed = std.mem.trim(u8, raw, " \t\r\n");
        authorization = try gpa.dupe(u8, trimmed);
        gpa.free(raw);
    } else if (env.get("AWS_CONTAINER_AUTHORIZATION_TOKEN")) |token| {
        authorization = try gpa.dupe(u8, token);
    }
    return .{ .url = url.?, .authorization = authorization };
}

pub fn parseCredentialJson(gpa: std.mem.Allocator, raw: []const u8) !OwnedContainerCredentials {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidContainerCredentialResponse;
    if (parsed.value.object.get("Code")) |code| {
        if (code == .string and !std.ascii.eqlIgnoreCase(code.string, "Success")) return error.ContainerCredentialProviderError;
    }
    const access = parsed.value.object.get("AccessKeyId") orelse return error.InvalidContainerCredentialResponse;
    const secret = parsed.value.object.get("SecretAccessKey") orelse return error.InvalidContainerCredentialResponse;
    const token = parsed.value.object.get("Token") orelse parsed.value.object.get("SessionToken") orelse return error.InvalidContainerCredentialResponse;
    const expiration = parsed.value.object.get("Expiration") orelse return error.InvalidContainerCredentialResponse;
    if (access != .string or secret != .string or token != .string or expiration != .string) return error.InvalidContainerCredentialResponse;
    const a = try gpa.dupe(u8, access.string);
    errdefer gpa.free(a);
    const s = try gpa.dupe(u8, secret.string);
    errdefer gpa.free(s);
    const t = try gpa.dupe(u8, token.string);
    errdefer gpa.free(t);
    return .{ .access_key_id = a, .secret_access_key = s, .session_token = t, .expiration_unix = try web.parseRfc3339(expiration.string) };
}

pub fn fetchCredentials(gpa: std.mem.Allocator, io: Io, config: OwnedConfig) !OwnedContainerCredentials {
    return fetchCredentialsWithOptions(gpa, io, config, .{});
}

pub fn fetchCredentialsWithOptions(gpa: std.mem.Allocator, io: Io, config: OwnedConfig, options_in: bootstrap_http.Options) !OwnedContainerCredentials {
    // Container credentials are secrets commonly served by a link-local
    // endpoint. Never forward them through a global application proxy.
    var options = options_in;
    options.proxy = .{};
    var headers: [1]std.http.Header = undefined;
    const extra: []const std.http.Header = if (config.authorization) |token| blk: {
        headers[0] = .{ .name = "authorization", .value = token };
        break :blk headers[0..1];
    } else &.{};
    var response = try bootstrap_http.request(gpa, io, .{
        .url = config.url,
        .method = .GET,
        .headers = extra,
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return error.ContainerCredentialHttpError;
    return try parseCredentialJson(gpa, response.body);
}

test "container relative URI outranks full URI and token file outranks token env" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "token", .data = "Bearer file-token\n" });
    const token_path = try tmp.dir.realPathFileAlloc(std.testing.io, "token", gpa);
    defer gpa.free(token_path);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/abc");
    try env.put("AWS_CONTAINER_CREDENTIALS_FULL_URI", "http://localhost/wrong");
    try env.put("AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE", token_path);
    try env.put("AWS_CONTAINER_AUTHORIZATION_TOKEN", "Bearer wrong");
    var config = (try resolveConfig(gpa, std.testing.io, &env)).?;
    defer config.deinit(gpa);
    try std.testing.expectEqualStrings("http://169.254.170.2/v2/credentials/abc", config.url);
    try std.testing.expectEqualStrings("Bearer file-token", config.authorization.?);
}

test "container credential JSON parses expiry" {
    const gpa = std.testing.allocator;
    var c = try parseCredentialJson(gpa, "{\"Code\":\"Success\",\"AccessKeyId\":\"ASIA_ECS\",\"SecretAccessKey\":\"secret\",\"Token\":\"token\",\"Expiration\":\"2026-08-09T12:34:56Z\"}");
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("ASIA_ECS", c.access_key_id);
    try std.testing.expectEqual(@as(i64, 1786278896), c.expiration_unix);
}
