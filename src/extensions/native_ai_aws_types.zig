//! Owned byte results shared by credential providers and HTTP preparation.
const std = @import("std");
const bedrock = @import("../ai/bedrock.zig");
pub const Failure = @import("native_ai_http_failure.zig").Owned;
pub const Credentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: ?[]u8 = null,
    expiration_unix: ?i64 = null,
    account_id: ?[]u8 = null,
    credential_scope: ?[]u8 = null,
    pub fn deinit(self: *Credentials, a: std.mem.Allocator) void {
        @memset(self.secret_access_key, 0);
        a.free(self.access_key_id);
        a.free(self.secret_access_key);
        if (self.session_token) |token| {
            @memset(token, 0);
            a.free(token);
        }
        if (self.account_id) |value| a.free(value);
        if (self.credential_scope) |value| a.free(value);
        self.* = undefined;
    }
    pub fn borrowed(self: *const Credentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};
pub const Result = union(enum) {
    credentials: Credentials,
    failure: Failure,
    pub fn deinit(self: *Result, a: std.mem.Allocator) void {
        switch (self.*) {
            .credentials => |*value| value.deinit(a),
            .failure => |*value| value.deinit(a),
        }
        self.* = undefined;
    }
};
pub fn failure(a: std.mem.Allocator, name: []const u8, message: []const u8, try_next: ?bool) !Result {
    return .{ .failure = try Failure.init(a, name, message, try_next) };
}
pub fn fromJson(a: std.mem.Allocator, value: std.json.Value, expiration: ?i64) !Credentials {
    const access = string(value, "accessKeyId") orelse return error.InvalidAwsCredentialResponse;
    const secret = string(value, "secretAccessKey") orelse return error.InvalidAwsCredentialResponse;
    var result = Credentials{ .access_key_id = try a.dupe(u8, access), .secret_access_key = undefined };
    errdefer a.free(result.access_key_id);
    result.secret_access_key = try a.dupe(u8, secret);
    errdefer {
        @memset(result.secret_access_key, 0);
        a.free(result.secret_access_key);
    }
    result.session_token = if (string(value, "sessionToken")) |token| try a.dupe(u8, token) else null;
    errdefer if (result.session_token) |token| {
        @memset(token, 0);
        a.free(token);
    };
    result.account_id = if (string(value, "accountId")) |account| try a.dupe(u8, account) else null;
    errdefer if (result.account_id) |account| a.free(account);
    result.credential_scope = if (string(value, "credentialScope")) |scope| try a.dupe(u8, scope) else null;
    result.expiration_unix = expiration;
    return result;
}
pub fn string(value: std.json.Value, key: []const u8) ?[]const u8 {
    const found = if (value == .object) value.object.get(key) orelse return null else return null;
    return if (found == .string) found.string else null;
}
