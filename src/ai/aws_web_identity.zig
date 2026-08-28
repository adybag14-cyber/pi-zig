//! Native AWS STS AssumeRoleWithWebIdentity provider for Bedrock.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");
const shared = @import("aws_credentials.zig");
const bootstrap_http = @import("bootstrap_http.zig");

pub const Config = struct {
    role_arn: []const u8,
    token_file: []const u8,
    session_name: []const u8 = "pi-zig",
    endpoint: []const u8 = "https://sts.amazonaws.com",
};

pub const OwnedTemporaryCredentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: []u8,
    expiration_unix: i64,

    pub fn deinit(self: *OwnedTemporaryCredentials, gpa: std.mem.Allocator) void {
        gpa.free(self.access_key_id);
        gpa.free(self.secret_access_key);
        gpa.free(self.session_token);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedTemporaryCredentials) bedrock.AwsCredentials {
        return .{
            .access_key_id = self.access_key_id,
            .secret_access_key = self.secret_access_key,
            .session_token = self.session_token,
        };
    }
};

pub fn resolveConfig(
    environ: *const std.process.Environ.Map,
    profile: ?*const shared.OwnedProfile,
) ?Config {
    const role = environ.get("AWS_ROLE_ARN") orelse blk: {
        if (profile) |p| if (p.role_arn) |v| break :blk v;
        return null;
    };
    const token_file = environ.get("AWS_WEB_IDENTITY_TOKEN_FILE") orelse blk: {
        if (profile) |p| if (p.web_identity_token_file) |v| break :blk v;
        return null;
    };
    const session_name = environ.get("AWS_ROLE_SESSION_NAME") orelse blk: {
        if (profile) |p| if (p.role_session_name) |v| break :blk v;
        break :blk "pi-zig";
    };
    const endpoint = environ.get("AWS_ENDPOINT_URL_STS") orelse "https://sts.amazonaws.com";
    return .{ .role_arn = role, .token_file = token_file, .session_name = session_name, .endpoint = endpoint };
}

pub fn buildAssumeRoleBody(
    gpa: std.mem.Allocator,
    role_arn: []const u8,
    session_name: []const u8,
    token: []const u8,
) ![]u8 {
    if (role_arn.len == 0 or token.len < 4 or session_name.len < 2 or session_name.len > 64) return error.InvalidWebIdentityConfig;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("Action=AssumeRoleWithWebIdentity&Version=2011-06-15&RoleArn=");
    try formEncode(&out.writer, role_arn);
    try out.writer.writeAll("&RoleSessionName=");
    try formEncode(&out.writer, session_name);
    try out.writer.writeAll("&WebIdentityToken=");
    try formEncode(&out.writer, token);
    return out.toOwnedSlice();
}

fn formEncode(w: *std.Io.Writer, input: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try w.writeByte(c);
        } else if (c == ' ') {
            try w.writeByte('+');
        } else {
            try w.writeByte('%');
            try w.writeByte(hex[c >> 4]);
            try w.writeByte(hex[c & 0x0f]);
        }
    }
}

pub fn parseAssumeRoleResponse(gpa: std.mem.Allocator, xml: []const u8) !OwnedTemporaryCredentials {
    if (tagValue(xml, "Error")) |_| {
        const code = tagValue(xml, "Code") orelse "UnknownError";
        if (std.mem.eql(u8, code, "InvalidIdentityToken")) return error.InvalidIdentityToken;
        if (std.mem.eql(u8, code, "ExpiredToken")) return error.ExpiredWebIdentityToken;
        if (std.mem.eql(u8, code, "AccessDenied")) return error.WebIdentityAccessDenied;
        return error.StsWebIdentityError;
    }
    const access_raw = tagValue(xml, "AccessKeyId") orelse return error.InvalidStsResponse;
    const secret_raw = tagValue(xml, "SecretAccessKey") orelse return error.InvalidStsResponse;
    const token_raw = tagValue(xml, "SessionToken") orelse return error.InvalidStsResponse;
    const expiration_raw = tagValue(xml, "Expiration") orelse return error.InvalidStsResponse;

    const access = try xmlDecode(gpa, access_raw);
    errdefer gpa.free(access);
    const secret = try xmlDecode(gpa, secret_raw);
    errdefer gpa.free(secret);
    const session_token = try xmlDecode(gpa, token_raw);
    errdefer gpa.free(session_token);
    const expiration_text = try xmlDecode(gpa, expiration_raw);
    defer gpa.free(expiration_text);
    return .{
        .access_key_id = access,
        .secret_access_key = secret,
        .session_token = session_token,
        .expiration_unix = try parseRfc3339(expiration_text),
    };
}

fn tagValue(xml: []const u8, tag: []const u8) ?[]const u8 {
    var open_buf: [96]u8 = undefined;
    var close_buf: [96]u8 = undefined;
    const open = std.fmt.bufPrint(&open_buf, "<{s}>", .{tag}) catch return null;
    const close = std.fmt.bufPrint(&close_buf, "</{s}>", .{tag}) catch return null;
    const start0 = std.mem.indexOf(u8, xml, open) orelse return null;
    const start = start0 + open.len;
    const end_rel = std.mem.indexOf(u8, xml[start..], close) orelse return null;
    return xml[start .. start + end_rel];
}

fn xmlDecode(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] != '&') {
            try out.append(gpa, input[i]);
            i += 1;
            continue;
        }
        const rest = input[i..];
        const entity: struct { text: []const u8, value: u8 } = if (std.mem.startsWith(u8, rest, "&amp;"))
            .{ .text = "&amp;", .value = '&' }
        else if (std.mem.startsWith(u8, rest, "&lt;"))
            .{ .text = "&lt;", .value = '<' }
        else if (std.mem.startsWith(u8, rest, "&gt;"))
            .{ .text = "&gt;", .value = '>' }
        else if (std.mem.startsWith(u8, rest, "&quot;"))
            .{ .text = "&quot;", .value = '"' }
        else if (std.mem.startsWith(u8, rest, "&apos;"))
            .{ .text = "&apos;", .value = '\'' }
        else {
            try out.append(gpa, input[i]);
            i += 1;
            continue;
        };
        try out.append(gpa, entity.value);
        i += entity.text.len;
    }
    return out.toOwnedSlice(gpa);
}

pub fn parseRfc3339(text: []const u8) !i64 {
    if (text.len < 20) return error.InvalidExpiration;
    const year = try std.fmt.parseInt(i64, text[0..4], 10);
    if (text[4] != '-') return error.InvalidExpiration;
    const month = try std.fmt.parseInt(i64, text[5..7], 10);
    if (text[7] != '-') return error.InvalidExpiration;
    const day = try std.fmt.parseInt(i64, text[8..10], 10);
    if (text[10] != 'T' and text[10] != 't' and text[10] != ' ') return error.InvalidExpiration;
    const hour = try std.fmt.parseInt(i64, text[11..13], 10);
    if (text[13] != ':') return error.InvalidExpiration;
    const minute = try std.fmt.parseInt(i64, text[14..16], 10);
    if (text[16] != ':') return error.InvalidExpiration;
    const second = try std.fmt.parseInt(i64, text[17..19], 10);
    if (month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 60) return error.InvalidExpiration;

    var pos: usize = 19;
    if (pos < text.len and text[pos] == '.') {
        pos += 1;
        const frac_start = pos;
        while (pos < text.len and std.ascii.isDigit(text[pos])) pos += 1;
        if (pos == frac_start) return error.InvalidExpiration;
    }
    var offset_seconds: i64 = 0;
    if (pos >= text.len) return error.InvalidExpiration;
    if (text[pos] == 'Z' or text[pos] == 'z') {
        pos += 1;
    } else if (text[pos] == '+' or text[pos] == '-') {
        const sign: i64 = if (text[pos] == '+') 1 else -1;
        if (pos + 6 > text.len or text[pos + 3] != ':') return error.InvalidExpiration;
        const oh = try std.fmt.parseInt(i64, text[pos + 1 .. pos + 3], 10);
        const om = try std.fmt.parseInt(i64, text[pos + 4 .. pos + 6], 10);
        if (oh > 23 or om > 59) return error.InvalidExpiration;
        offset_seconds = sign * (oh * 3600 + om * 60);
        pos += 6;
    } else return error.InvalidExpiration;
    if (pos != text.len) return error.InvalidExpiration;

    const days = daysFromCivil(year, month, day);
    return days * 86400 + hour * 3600 + minute * 60 + @min(second, 59) - offset_seconds;
}

fn daysFromCivil(year_in: i64, month: i64, day: i64) i64 {
    var y = year_in;
    y -= if (month <= 2) 1 else 0;
    const era = @divFloor(y, 400);
    const yoe = y - era * 400;
    const mp = month + (if (month > 2) @as(i64, -3) else 9);
    const doy = @divFloor(153 * mp + 2, 5) + day - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

pub fn assumeRole(
    gpa: std.mem.Allocator,
    io: Io,
    config: Config,
) !OwnedTemporaryCredentials {
    return assumeRoleWithOptions(gpa, io, config, .{});
}

pub fn assumeRoleWithOptions(
    gpa: std.mem.Allocator,
    io: Io,
    config: Config,
    options: bootstrap_http.Options,
) !OwnedTemporaryCredentials {
    const raw_token = try std.Io.Dir.cwd().readFileAlloc(io, config.token_file, gpa, .limited(32 * 1024));
    defer gpa.free(raw_token);
    const token = std.mem.trim(u8, raw_token, " \t\r\n");
    const body = try buildAssumeRoleBody(gpa, config.role_arn, config.session_name, token);
    defer gpa.free(body);

    var response = try bootstrap_http.request(gpa, io, .{
        .url = config.endpoint,
        .method = .POST,
        .payload = body,
        .headers = &.{.{ .name = "content-type", .value = "application/x-www-form-urlencoded" }},
        .options = options,
    });
    defer response.deinit(gpa);
    if (response.status < 200 or response.status >= 300) {
        // STS returns structured XML errors; use those when available without
        // retaining the OIDC token or raw response body in error messages.
        return parseAssumeRoleResponse(gpa, response.body) catch return error.StsWebIdentityHttpError;
    }
    return try parseAssumeRoleResponse(gpa, response.body);
}

test "STS web identity form encodes sensitive parameters" {
    const gpa = std.testing.allocator;
    const body = try buildAssumeRoleBody(gpa, "arn:aws:iam::123:role/a b", "pi-zig", "eyJ.a+b/c=");
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "RoleArn=arn%3Aaws%3Aiam%3A%3A123%3Arole%2Fa+b") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "WebIdentityToken=eyJ.a%2Bb%2Fc%3D") != null);
}

test "STS web identity XML parses owned temporary credentials" {
    const gpa = std.testing.allocator;
    var creds = try parseAssumeRoleResponse(gpa, "<AssumeRoleWithWebIdentityResponse><AssumeRoleWithWebIdentityResult><Credentials>" ++
        "<AccessKeyId>ASIA&amp;TEST</AccessKeyId><SecretAccessKey>secret</SecretAccessKey>" ++
        "<SessionToken>token</SessionToken><Expiration>2026-08-09T12:34:56Z</Expiration>" ++
        "</Credentials></AssumeRoleWithWebIdentityResult></AssumeRoleWithWebIdentityResponse>");
    defer creds.deinit(gpa);
    try std.testing.expectEqualStrings("ASIA&TEST", creds.access_key_id);
    try std.testing.expectEqual(@as(i64, 1786278896), creds.expiration_unix);
}

test "RFC3339 expiration handles fractions and offsets" {
    try std.testing.expectEqual(@as(i64, 1786278896), try parseRfc3339("2026-08-09T12:34:56.999Z"));
    try std.testing.expectEqual(@as(i64, 1786278896), try parseRfc3339("2026-08-09T13:34:56+01:00"));
}

test "web identity environment overrides profile" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_ROLE_ARN", "arn:aws:iam::1:role/env");
    try env.put("AWS_WEB_IDENTITY_TOKEN_FILE", "/env/token");
    var profile = shared.OwnedProfile{
        .profile_name = try gpa.dupe(u8, "p"),
        .role_arn = try gpa.dupe(u8, "arn:aws:iam::1:role/profile"),
        .web_identity_token_file = try gpa.dupe(u8, "/profile/token"),
    };
    defer profile.deinit(gpa);
    const config = resolveConfig(&env, &profile).?;
    try std.testing.expectEqualStrings("arn:aws:iam::1:role/env", config.role_arn);
    try std.testing.expectEqualStrings("/env/token", config.token_file);
}
