//! OAuth device-code / API-key auth surface (pi-ai auth package subset).
//! Full browser OAuth requires OS browser launch; device-code flow is offline-testable.
const std = @import("std");
const Io = std.Io;
const storage = @import("storage.zig");

pub const DeviceCodeResponse = struct {
    device_code: []const u8,
    user_code: []const u8,
    verification_uri: []const u8,
    expires_in: u64 = 900,
    interval: u64 = 5,

    pub fn deinit(self: *DeviceCodeResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.device_code);
        gpa.free(self.user_code);
        gpa.free(self.verification_uri);
        self.* = undefined;
    }
};

pub const TokenResponse = struct {
    access_token: []const u8,
    refresh_token: []const u8 = "",
    token_type: []const u8 = "Bearer",
    expires_in: u64 = 3600,

    pub fn deinit(self: *TokenResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.access_token);
        if (self.refresh_token.len > 0) gpa.free(self.refresh_token);
        if (self.token_type.len > 0 and !std.mem.eql(u8, self.token_type, "Bearer")) gpa.free(self.token_type);
        self.* = undefined;
    }
};

/// Parse device-code JSON (unit-testable without network).
pub fn parseDeviceCodeResponse(gpa: std.mem.Allocator, json_text: []const u8) !DeviceCodeResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;
    const dc = parsed.value.object.get("device_code") orelse return error.InvalidResponse;
    const uc = parsed.value.object.get("user_code") orelse return error.InvalidResponse;
    const vu = parsed.value.object.get("verification_uri") orelse parsed.value.object.get("verification_uri_complete") orelse return error.InvalidResponse;
    if (dc != .string or uc != .string or vu != .string) return error.InvalidResponse;
    var exp: u64 = 900;
    if (parsed.value.object.get("expires_in")) |v| {
        if (v == .integer) exp = @intCast(v.integer);
    }
    var interval: u64 = 5;
    if (parsed.value.object.get("interval")) |v| {
        if (v == .integer) interval = @intCast(v.integer);
    }
    return .{
        .device_code = try gpa.dupe(u8, dc.string),
        .user_code = try gpa.dupe(u8, uc.string),
        .verification_uri = try gpa.dupe(u8, vu.string),
        .expires_in = exp,
        .interval = interval,
    };
}

pub fn parseTokenResponse(gpa: std.mem.Allocator, json_text: []const u8) !TokenResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;
    const at = parsed.value.object.get("access_token") orelse return error.InvalidResponse;
    if (at != .string) return error.InvalidResponse;
    var rt: []const u8 = "";
    if (parsed.value.object.get("refresh_token")) |v| {
        if (v == .string) rt = try gpa.dupe(u8, v.string);
    }
    return .{
        .access_token = try gpa.dupe(u8, at.string),
        .refresh_token = rt,
    };
}

/// Store OAuth tokens in upstream-compatible `agent_dir/auth.json`.
/// `expires` is absolute Unix epoch milliseconds, matching pi-ai OAuthCredential.
pub fn saveTokens(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, provider: []const u8, token: TokenResponse) !void {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    const now_ns = std.Io.Clock.real.now(io).nanoseconds;
    const now_ms: i64 = @intCast(@divTrunc(now_ns, std.time.ns_per_ms));
    const expires_ms = now_ms + @as(i64, @intCast(token.expires_in)) * std.time.ms_per_s;
    const credential = storage.OAuthCredential{
        .refresh = @constCast(token.refresh_token),
        .access = @constCast(token.access_token),
        .expires = expires_ms,
    };
    try store.setOAuth(provider, credential);
}

/// Load the access token from `auth.json`. For migration only, an old
/// `oauth_<provider>.json` file is still accepted if no canonical credential exists.
pub fn loadAccessToken(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8, provider: []const u8) !?[]u8 {
    var store = try storage.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    if (try store.read(provider)) |credential_value| {
        var credential = credential_value;
        defer credential.deinit(gpa);
        switch (credential) {
            .oauth => |oauth_credential| return try gpa.dupe(u8, oauth_credential.access),
            .api_key => |api_key| if (api_key.key) |key| return try gpa.dupe(u8, key),
        }
    }

    // Legacy pi-zig token-file fallback. New writes never use this path.
    const path = try std.fmt.allocPrint(gpa, "{s}/oauth_{s}.json", .{ agent_dir, provider });
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024)) catch return null;
    defer gpa.free(raw);
    var tok = parseTokenResponse(gpa, raw) catch return null;
    defer tok.deinit(gpa);
    return try gpa.dupe(u8, tok.access_token);
}

test "parse device code and token responses" {
    const gpa = std.testing.allocator;
    var dc = try parseDeviceCodeResponse(gpa,
        \\{"device_code":"dev","user_code":"ABCD-EFGH","verification_uri":"https://example.com/device","expires_in":600,"interval":5}
    );
    defer dc.deinit(gpa);
    try std.testing.expectEqualStrings("ABCD-EFGH", dc.user_code);
    try std.testing.expectEqual(@as(u64, 600), dc.expires_in);

    var tok = try parseTokenResponse(gpa,
        \\{"access_token":"sk-abc","refresh_token":"rt-1","token_type":"Bearer"}
    );
    defer tok.deinit(gpa);
    try std.testing.expectEqualStrings("sk-abc", tok.access_token);
}

test "OAuth save uses canonical auth json" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];

    const token = TokenResponse{
        .access_token = "access-canonical",
        .refresh_token = "refresh-canonical",
        .expires_in = 3600,
    };
    try saveTokens(gpa, io, agent_dir, "custom-oauth", token);
    const access = (try loadAccessToken(gpa, io, agent_dir, "custom-oauth")).?;
    defer gpa.free(access);
    try std.testing.expectEqualStrings("access-canonical", access);

    const auth_path = try std.fs.path.join(gpa, &.{ agent_dir, "auth.json" });
    defer gpa.free(auth_path);
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, auth_path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "custom-oauth") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"type\": \"oauth\"") != null);
}
