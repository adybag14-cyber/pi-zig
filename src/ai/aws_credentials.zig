//! Minimal native AWS shared-config credential discovery used by Bedrock.
//! Intentionally SDK-free: parses only the profile fields Pi needs and owns
//! every returned string so callers never retain slices into temporary files.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");

pub const OwnedProfile = struct {
    profile_name: []u8,
    access_key_id: ?[]u8 = null,
    secret_access_key: ?[]u8 = null,
    session_token: ?[]u8 = null,
    region: ?[]u8 = null,
    role_arn: ?[]u8 = null,
    web_identity_token_file: ?[]u8 = null,
    role_session_name: ?[]u8 = null,
    credential_process: ?[]u8 = null,
    ec2_metadata_service_endpoint: ?[]u8 = null,
    ec2_metadata_service_endpoint_mode: ?[]u8 = null,
    ec2_metadata_v1_disabled: ?bool = null,
    source_profile: ?[]u8 = null,
    credential_source: ?[]u8 = null,
    external_id: ?[]u8 = null,
    duration_seconds: ?u32 = null,

    pub fn deinit(self: *OwnedProfile, gpa: std.mem.Allocator) void {
        gpa.free(self.profile_name);
        if (self.access_key_id) |v| gpa.free(v);
        if (self.secret_access_key) |v| gpa.free(v);
        if (self.session_token) |v| gpa.free(v);
        if (self.region) |v| gpa.free(v);
        if (self.role_arn) |v| gpa.free(v);
        if (self.web_identity_token_file) |v| gpa.free(v);
        if (self.role_session_name) |v| gpa.free(v);
        if (self.credential_process) |v| gpa.free(v);
        if (self.ec2_metadata_service_endpoint) |v| gpa.free(v);
        if (self.ec2_metadata_service_endpoint_mode) |v| gpa.free(v);
        if (self.source_profile) |v| gpa.free(v);
        if (self.credential_source) |v| gpa.free(v);
        if (self.external_id) |v| gpa.free(v);
        self.* = undefined;
    }

    pub fn staticCredentials(self: *const OwnedProfile) ?bedrock.AwsCredentials {
        const access = self.access_key_id orelse return null;
        const secret = self.secret_access_key orelse return null;
        return .{ .access_key_id = access, .secret_access_key = secret, .session_token = self.session_token };
    }

    pub fn hasWebIdentity(self: *const OwnedProfile) bool {
        return self.role_arn != null and self.web_identity_token_file != null;
    }
};

pub fn selectedProfileName(environ: *const std.process.Environ.Map) []const u8 {
    return environ.get("AWS_PROFILE") orelse environ.get("AWS_DEFAULT_PROFILE") orelse "default";
}

pub fn loadSelectedProfile(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
) !?OwnedProfile {
    return loadProfileByName(gpa, io, environ, selectedProfileName(environ));
}

pub fn loadProfileByName(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    profile_name: []const u8,
) !?OwnedProfile {
    var out = OwnedProfile{ .profile_name = try gpa.dupe(u8, profile_name) };
    errdefer out.deinit(gpa);

    var found = false;
    // AWS shared credentials take precedence over credential values in config,
    // while config remains the normal source for region/role metadata. Merge
    // config first, then credentials.
    const config_path = try awsPath(gpa, environ, "AWS_CONFIG_FILE", "config");
    defer if (config_path) |p| gpa.free(p);
    if (config_path) |path| {
        if (try mergeFile(gpa, io, path, profile_name, true, &out)) found = true;
    }

    const credentials_path = try awsPath(gpa, environ, "AWS_SHARED_CREDENTIALS_FILE", "credentials");
    defer if (credentials_path) |p| gpa.free(p);
    if (credentials_path) |path| {
        if (try mergeFile(gpa, io, path, profile_name, false, &out)) found = true;
    }

    if (!found) {
        out.deinit(gpa);
        return null;
    }
    return out;
}

fn awsPath(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    override_name: []const u8,
    leaf: []const u8,
) !?[]u8 {
    if (environ.get(override_name)) |path| {
        if (std.mem.trim(u8, path, " \t\r\n").len != 0) return try gpa.dupe(u8, path);
    }
    const home = environ.get("HOME") orelse environ.get("USERPROFILE") orelse return null;
    return try std.fs.path.join(gpa, &.{ home, ".aws", leaf });
}

fn mergeFile(
    gpa: std.mem.Allocator,
    io: Io,
    path: []const u8,
    profile_name: []const u8,
    config_style: bool,
    out: *OwnedProfile,
) !bool {
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return false,
        else => return err,
    };
    defer gpa.free(raw);
    return try mergeIni(gpa, raw, profile_name, config_style, out);
}

pub fn mergeIni(
    gpa: std.mem.Allocator,
    raw: []const u8,
    profile_name: []const u8,
    config_style: bool,
    out: *OwnedProfile,
) !bool {
    var in_section = false;
    var saw_section = false;
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;
        if (line[0] == '[') {
            const close = std.mem.indexOfScalar(u8, line, ']') orelse {
                in_section = false;
                continue;
            };
            const section = std.mem.trim(u8, line[1..close], " \t");
            in_section = sectionMatches(section, profile_name, config_style);
            if (in_section) saw_section = true;
            continue;
        }
        if (!in_section) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        var value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
            value = value[1 .. value.len - 1];
        }
        if (std.ascii.eqlIgnoreCase(key, "aws_access_key_id")) {
            try replaceOwned(gpa, &out.access_key_id, value);
        } else if (std.ascii.eqlIgnoreCase(key, "aws_secret_access_key")) {
            try replaceOwned(gpa, &out.secret_access_key, value);
        } else if (std.ascii.eqlIgnoreCase(key, "aws_session_token") or std.ascii.eqlIgnoreCase(key, "aws_security_token")) {
            try replaceOwned(gpa, &out.session_token, value);
        } else if (std.ascii.eqlIgnoreCase(key, "region")) {
            try replaceOwned(gpa, &out.region, value);
        } else if (std.ascii.eqlIgnoreCase(key, "role_arn")) {
            try replaceOwned(gpa, &out.role_arn, value);
        } else if (std.ascii.eqlIgnoreCase(key, "web_identity_token_file")) {
            try replaceOwned(gpa, &out.web_identity_token_file, value);
        } else if (std.ascii.eqlIgnoreCase(key, "role_session_name")) {
            try replaceOwned(gpa, &out.role_session_name, value);
        } else if (std.ascii.eqlIgnoreCase(key, "credential_process")) {
            try replaceOwned(gpa, &out.credential_process, value);
        } else if (std.ascii.eqlIgnoreCase(key, "ec2_metadata_service_endpoint")) {
            try replaceOwned(gpa, &out.ec2_metadata_service_endpoint, value);
        } else if (std.ascii.eqlIgnoreCase(key, "ec2_metadata_service_endpoint_mode")) {
            try replaceOwned(gpa, &out.ec2_metadata_service_endpoint_mode, value);
        } else if (std.ascii.eqlIgnoreCase(key, "ec2_metadata_v1_disabled")) {
            out.ec2_metadata_v1_disabled = parseBool(value);
        } else if (std.ascii.eqlIgnoreCase(key, "source_profile")) {
            try replaceOwned(gpa, &out.source_profile, value);
        } else if (std.ascii.eqlIgnoreCase(key, "credential_source")) {
            try replaceOwned(gpa, &out.credential_source, value);
        } else if (std.ascii.eqlIgnoreCase(key, "external_id")) {
            try replaceOwned(gpa, &out.external_id, value);
        } else if (std.ascii.eqlIgnoreCase(key, "duration_seconds")) {
            out.duration_seconds = std.fmt.parseInt(u32, value, 10) catch null;
        }
    }
    return saw_section;
}

fn sectionMatches(section: []const u8, profile_name: []const u8, config_style: bool) bool {
    if (!config_style or std.mem.eql(u8, profile_name, "default")) return std.mem.eql(u8, section, profile_name);
    if (!std.mem.startsWith(u8, section, "profile ")) return false;
    return std.mem.eql(u8, std.mem.trim(u8, section["profile ".len..], " \t"), profile_name);
}

fn replaceOwned(gpa: std.mem.Allocator, slot: *?[]u8, value: []const u8) !void {
    if (slot.*) |old| gpa.free(old);
    slot.* = try gpa.dupe(u8, value);
}

fn parseBool(value: []const u8) ?bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or std.mem.eql(u8, value, "1")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or std.mem.eql(u8, value, "0")) return false;
    return null;
}

test "AWS shared credentials and config merge selected profile" {
    const gpa = std.testing.allocator;
    var p = OwnedProfile{ .profile_name = try gpa.dupe(u8, "research") };
    defer p.deinit(gpa);
    try std.testing.expect(try mergeIni(gpa, "[default]\naws_access_key_id=DEFAULT\n[research]\naws_access_key_id = AKIA_RESEARCH\naws_secret_access_key = secret\naws_session_token = session\n", "research", false, &p));
    try std.testing.expect(try mergeIni(gpa, "[default]\nregion=us-east-1\n[profile research]\nregion = eu-west-2\nrole_arn=arn:aws:iam::123:role/demo\nweb_identity_token_file=/tmp/token\nrole_session_name=pi-zig\n", "research", true, &p));
    try std.testing.expectEqualStrings("AKIA_RESEARCH", p.access_key_id.?);
    try std.testing.expectEqualStrings("secret", p.secret_access_key.?);
    try std.testing.expectEqualStrings("session", p.session_token.?);
    try std.testing.expectEqualStrings("eu-west-2", p.region.?);
    try std.testing.expect(p.hasWebIdentity());
}

test "default config section does not use profile prefix" {
    const gpa = std.testing.allocator;
    var p = OwnedProfile{ .profile_name = try gpa.dupe(u8, "default") };
    defer p.deinit(gpa);
    try std.testing.expect(try mergeIni(gpa, "[profile default]\nregion=wrong\n[default]\nregion=us-west-2\n", "default", true, &p));
    try std.testing.expectEqualStrings("us-west-2", p.region.?);
}
