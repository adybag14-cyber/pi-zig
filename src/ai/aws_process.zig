//! Native AWS credential_process provider.
const std = @import("std");
const Io = std.Io;
const bedrock = @import("bedrock.zig");
const web = @import("aws_web_identity.zig");

pub const OwnedProcessCredentials = struct {
    access_key_id: []u8,
    secret_access_key: []u8,
    session_token: ?[]u8 = null,
    expiration_unix: ?i64 = null,

    pub fn deinit(self: *OwnedProcessCredentials, gpa: std.mem.Allocator) void {
        gpa.free(self.access_key_id);
        gpa.free(self.secret_access_key);
        if (self.session_token) |v| gpa.free(v);
        self.* = undefined;
    }

    pub fn borrowed(self: *const OwnedProcessCredentials) bedrock.AwsCredentials {
        return .{ .access_key_id = self.access_key_id, .secret_access_key = self.secret_access_key, .session_token = self.session_token };
    }
};

pub fn parseCredentialProcessJson(gpa: std.mem.Allocator, raw: []const u8) !OwnedProcessCredentials {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCredentialProcessOutput;
    const version = parsed.value.object.get("Version") orelse return error.InvalidCredentialProcessOutput;
    if (version != .integer or version.integer != 1) return error.UnsupportedCredentialProcessVersion;
    const access = parsed.value.object.get("AccessKeyId") orelse return error.InvalidCredentialProcessOutput;
    const secret = parsed.value.object.get("SecretAccessKey") orelse return error.InvalidCredentialProcessOutput;
    if (access != .string or secret != .string or access.string.len == 0 or secret.string.len == 0) return error.InvalidCredentialProcessOutput;
    var session_token: ?[]u8 = null;
    errdefer if (session_token) |v| gpa.free(v);
    if (parsed.value.object.get("SessionToken")) |v| {
        if (v != .string) return error.InvalidCredentialProcessOutput;
        session_token = try gpa.dupe(u8, v.string);
    }
    var expiration: ?i64 = null;
    if (parsed.value.object.get("Expiration")) |v| {
        if (v != .string) return error.InvalidCredentialProcessOutput;
        expiration = try web.parseRfc3339(v.string);
    }
    return .{
        .access_key_id = try gpa.dupe(u8, access.string),
        .secret_access_key = try gpa.dupe(u8, secret.string),
        .session_token = session_token,
        .expiration_unix = expiration,
    };
}

pub fn splitCommand(gpa: std.mem.Allocator, command: []const u8) ![][]u8 {
    var argv: std.ArrayList([]u8) = .empty;
    errdefer {
        for (argv.items) |arg| gpa.free(arg);
        argv.deinit(gpa);
    }
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(gpa);
    var quote: ?u8 = null;
    var i: usize = 0;
    while (i < command.len) : (i += 1) {
        const c = command[i];
        if (quote) |q| {
            if (c == q) {
                quote = null;
            } else if (c == '\\' and q == '"' and i + 1 < command.len and (command[i + 1] == '"' or command[i + 1] == '\\')) {
                i += 1;
                try current.append(gpa, command[i]);
            } else {
                try current.append(gpa, c);
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
        } else if (std.ascii.isWhitespace(c)) {
            if (current.items.len != 0) {
                try argv.append(gpa, try gpa.dupe(u8, current.items));
                current.clearRetainingCapacity();
            }
        } else {
            try current.append(gpa, c);
        }
    }
    if (quote != null) return error.UnterminatedCredentialProcessQuote;
    if (current.items.len != 0) try argv.append(gpa, try gpa.dupe(u8, current.items));
    if (argv.items.len == 0) return error.EmptyCredentialProcess;
    return try argv.toOwnedSlice(gpa);
}

pub fn freeArgv(gpa: std.mem.Allocator, argv: [][]u8) void {
    for (argv) |arg| gpa.free(arg);
    gpa.free(argv);
}

pub fn runCredentialProcess(gpa: std.mem.Allocator, io: Io, command: []const u8) !OwnedProcessCredentials {
    const owned_argv = try splitCommand(gpa, command);
    defer freeArgv(gpa, owned_argv);
    const argv: []const []const u8 = owned_argv;
    const result = try std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(8 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(15), .clock = .real } },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.CredentialProcessFailed,
        else => return error.CredentialProcessFailed,
    }
    return try parseCredentialProcessJson(gpa, result.stdout);
}

test "credential_process parses Version 1 JSON" {
    const gpa = std.testing.allocator;
    var c = try parseCredentialProcessJson(gpa, "{\"Version\":1,\"AccessKeyId\":\"AKIA_PROCESS\",\"SecretAccessKey\":\"secret\",\"SessionToken\":\"session\",\"Expiration\":\"2026-08-09T12:34:56Z\"}");
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("AKIA_PROCESS", c.access_key_id);
    try std.testing.expectEqual(@as(?i64, 1786278896), c.expiration_unix);
}

test "credential_process command parser preserves quoted arguments" {
    const gpa = std.testing.allocator;
    const argv = try splitCommand(gpa, "\"/opt/AWS Helper/bin/cred\" --profile 'research team' --json");
    defer freeArgv(gpa, argv);
    try std.testing.expectEqual(@as(usize, 4), argv.len);
    try std.testing.expectEqualStrings("/opt/AWS Helper/bin/cred", argv[0]);
    try std.testing.expectEqualStrings("research team", argv[2]);
}

test "credential_process rejects unsupported versions" {
    try std.testing.expectError(error.UnsupportedCredentialProcessVersion, parseCredentialProcessJson(std.testing.allocator, "{\"Version\":2,\"AccessKeyId\":\"a\",\"SecretAccessKey\":\"b\"}"));
}
