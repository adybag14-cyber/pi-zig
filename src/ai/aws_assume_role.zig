//! Native STS AssumeRole support for AWS shared profiles.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");
const web = @import("aws_web_identity.zig");
const bootstrap_http = @import("bootstrap_http.zig");

pub const Options = struct {
    role_arn: []const u8,
    role_session_name: []const u8 = "pi-zig",
    external_id: ?[]const u8 = null,
    duration_seconds: ?u32 = null,
    region: []const u8 = "us-east-1",
};

pub const OwnedAssumedCredentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: []u8,
    expiration_unix: i64,
    pub fn deinit(self: *OwnedAssumedCredentials, gpa: std.mem.Allocator) void {
        gpa.free(self.access_key_id);
        gpa.free(self.secret_access_key);
        gpa.free(self.session_token);
        self.* = undefined;
    }
    pub fn borrowed(self: *const OwnedAssumedCredentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};

pub fn endpointForRegion(gpa: std.mem.Allocator, region: []const u8) ![]u8 {
    const suffix = if (std.mem.startsWith(u8, region, "cn-")) "amazonaws.com.cn" else "amazonaws.com";
    return try std.fmt.allocPrint(gpa, "https://sts.{s}.{s}", .{ region, suffix });
}

pub fn buildAssumeRoleBody(gpa: std.mem.Allocator, options: Options) ![]u8 {
    if (options.role_arn.len == 0 or options.role_session_name.len < 2 or options.role_session_name.len > 64) return error.InvalidAssumeRoleConfig;
    if (options.duration_seconds) |d| if (d < 900 or d > 43200) return error.InvalidAssumeRoleDuration;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("Action=AssumeRole&Version=2011-06-15&RoleArn=");
    try formEncode(&out.writer, options.role_arn);
    try out.writer.writeAll("&RoleSessionName=");
    try formEncode(&out.writer, options.role_session_name);
    if (options.external_id) |external| {
        try out.writer.writeAll("&ExternalId=");
        try formEncode(&out.writer, external);
    }
    if (options.duration_seconds) |duration| try out.writer.print("&DurationSeconds={d}", .{duration});
    return out.toOwnedSlice();
}

fn formEncode(w: *std.Io.Writer, input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') try w.writeByte(c) else if (c == ' ') try w.writeByte('+') else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

pub fn parseAssumeRoleResponse(gpa: std.mem.Allocator, xml: []const u8) !OwnedAssumedCredentials {
    if (tagValue(xml, "Error")) |_| {
        const code = tagValue(xml, "Code") orelse "UnknownError";
        if (std.mem.eql(u8, code, "AccessDenied")) return error.AssumeRoleAccessDenied;
        return error.AssumeRoleStsError;
    }
    const access = tagValue(xml, "AccessKeyId") orelse return error.InvalidAssumeRoleResponse;
    const secret = tagValue(xml, "SecretAccessKey") orelse return error.InvalidAssumeRoleResponse;
    const token = tagValue(xml, "SessionToken") orelse return error.InvalidAssumeRoleResponse;
    const expiration = tagValue(xml, "Expiration") orelse return error.InvalidAssumeRoleResponse;
    const a = try gpa.dupe(u8, access);
    errdefer gpa.free(a);
    const s = try gpa.dupe(u8, secret);
    errdefer gpa.free(s);
    const t = try gpa.dupe(u8, token);
    errdefer gpa.free(t);
    return .{ .access_key_id = a, .secret_access_key = s, .session_token = t, .expiration_unix = try web.parseRfc3339(expiration) };
}

fn tagValue(xml: []const u8, tag: []const u8) ?[]const u8 {
    var ob: [96]u8 = undefined;
    var cb: [96]u8 = undefined;
    const open = std.fmt.bufPrint(&ob, "<{s}>", .{tag}) catch return null;
    const close = std.fmt.bufPrint(&cb, "</{s}>", .{tag}) catch return null;
    const start0 = std.mem.indexOf(u8, xml, open) orelse return null;
    const start = start0 + open.len;
    const end = std.mem.indexOf(u8, xml[start..], close) orelse return null;
    return xml[start .. start + end];
}

pub fn assumeRole(gpa: std.mem.Allocator, io: Io, source: bedrock.AwsCredentials, options: Options, now_unix: i64) !OwnedAssumedCredentials {
    return assumeRoleWithHttpOptions(gpa, io, source, options, now_unix, .{});
}

pub fn assumeRoleWithHttpOptions(gpa: std.mem.Allocator, io: Io, source: bedrock.AwsCredentials, options: Options, now_unix: i64, http_options: bootstrap_http.Options) !OwnedAssumedCredentials {
    const endpoint = try endpointForRegion(gpa, options.region);
    defer gpa.free(endpoint);
    const body = try buildAssumeRoleBody(gpa, options);
    defer gpa.free(body);
    const content_type = "application/x-www-form-urlencoded; charset=utf-8";
    var signed = try bedrock.signAwsRequestForService(gpa, "POST", endpoint, body, source, options.region, "sts", content_type, now_unix);
    defer signed.deinit(gpa);
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer headers.deinit(gpa);
    try headers.append(gpa, .{ .name = "content-type", .value = content_type });
    try headers.append(gpa, .{ .name = "authorization", .value = signed.authorization });
    try headers.append(gpa, .{ .name = "x-amz-date", .value = signed.amz_date[0..] });
    if (source.session_token) |token| try headers.append(gpa, .{ .name = "x-amz-security-token", .value = token });
    var response = try bootstrap_http.request(gpa, io, .{
        .url = endpoint,
        .method = .POST,
        .payload = body,
        .headers = headers.items,
        .options = http_options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) return parseAssumeRoleResponse(gpa, response.body) catch return error.AssumeRoleHttpError;
    return try parseAssumeRoleResponse(gpa, response.body);
}

test "AssumeRole body includes role metadata" {
    const gpa = std.testing.allocator;
    const body = try buildAssumeRoleBody(gpa, .{ .role_arn = "arn:aws:iam::123:role/cross account", .external_id = "customer 42", .duration_seconds = 3600 });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "RoleArn=arn%3Aaws%3Aiam%3A%3A123%3Arole%2Fcross+account") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "ExternalId=customer+42") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "DurationSeconds=3600") != null);
}

test "AssumeRole endpoint respects China partition" {
    const url = try endpointForRegion(std.testing.allocator, "cn-north-1");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://sts.cn-north-1.amazonaws.com.cn", url);
}

test "AssumeRole XML parses temporary credentials" {
    const gpa = std.testing.allocator;
    var c = try parseAssumeRoleResponse(gpa, "<AssumeRoleResponse><AssumeRoleResult><Credentials><AccessKeyId>ASIA_ROLE</AccessKeyId><SecretAccessKey>secret</SecretAccessKey><SessionToken>token</SessionToken><Expiration>2026-08-09T12:34:56Z</Expiration></Credentials></AssumeRoleResult></AssumeRoleResponse>");
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("ASIA_ROLE", c.access_key_id);
    try std.testing.expectEqual(@as(i64, 1786278896), c.expiration_unix);
}
