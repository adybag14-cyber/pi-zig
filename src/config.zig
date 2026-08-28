//! App identity, paths (~/.pi/agent), and env var names.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

pub const APP_NAME = "pi";
pub const CONFIG_DIR_NAME = ".pi";
pub const AGENT_DIR_NAME = "agent";
pub const version = "1.0.0";
/// Upstream Pi release whose public behavior this checkpoint targets.
pub const upstream_version = "0.84.1";
pub const upstream_package_name = "@earendil-works/pi-coding-agent";
pub const identity = "pi (pi-zig) coding agent " ++ version;

pub const ENV_AGENT_DIR = "PI_AGENT_DIR";
pub const ENV_SESSION_DIR = "PI_SESSION_DIR";
pub const ENV_MOCK_SCRIPT = "PI_MOCK_SCRIPT";
pub const ENV_MODEL = "PI_MODEL";
pub const ENV_API_KEY = "PI_API_KEY";
pub const ENV_OPENAI_KEY = "OPENAI_API_KEY";
pub const ENV_ANTHROPIC_KEY = "ANTHROPIC_API_KEY";
pub const ENV_ANTHROPIC_AUTH_TOKEN = "ANTHROPIC_AUTH_TOKEN";
pub const ENV_ANTHROPIC_OAUTH_TOKEN = "ANTHROPIC_OAUTH_TOKEN";
pub const ENV_GOOGLE_KEY = "GOOGLE_API_KEY";
pub const ENV_GEMINI_KEY = "GEMINI_API_KEY";
pub const ENV_OPENAI_BASE = "OPENAI_BASE_URL";
pub const ENV_PROVIDER = "PI_PROVIDER";

/// Resolve home directory from env map (USERPROFILE on Windows, HOME elsewhere).
pub fn homeDir(environ: *const std.process.Environ.Map) ?[]const u8 {
    if (builtin.os.tag == .windows) {
        if (environ.get("USERPROFILE")) |h| return h;
        if (environ.get("HOME")) |h| return h;
        return null;
    }
    return environ.get("HOME");
}

/// ~/.pi
pub fn configDir(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ![]u8 {
    const home = homeDir(environ) orelse return error.NoHomeDir;
    return try std.fs.path.join(gpa, &.{ home, CONFIG_DIR_NAME });
}

/// ~/.pi/agent (or PI_AGENT_DIR)
pub fn agentDir(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ![]u8 {
    if (environ.get(ENV_AGENT_DIR)) |d| return try gpa.dupe(u8, d);
    const home = homeDir(environ) orelse return error.NoHomeDir;
    return try std.fs.path.join(gpa, &.{ home, CONFIG_DIR_NAME, AGENT_DIR_NAME });
}

/// Original Pi session-directory encoding: an absolute cwd is stripped of its
/// leading separator, path separators/drive colons become '-', and the result
/// is fenced with `--`. Keeping this human-readable layout is important for
/// upstream resume interoperability.
pub fn encodedSessionLeaf(gpa: std.mem.Allocator, cwd: []const u8) ![]u8 {
    const start: usize = if (cwd.len > 0 and (cwd[0] == '/' or cwd[0] == '\\')) 1 else 0;
    var out = try gpa.alloc(u8, 4 + cwd.len - start);
    var index: usize = 0;
    out[index] = '-';
    out[index + 1] = '-';
    index += 2;
    for (cwd[start..]) |byte| {
        out[index] = switch (byte) {
            '/', '\\', ':' => '-',
            else => byte,
        };
        index += 1;
    }
    out[index] = '-';
    out[index + 1] = '-';
    return out[0 .. index + 2];
}

/// Pre-checkpoint-145 Pi-Zig used an FNV hash. Startup migration uses this
/// helper to recover those sessions into the canonical upstream directory.
pub fn legacyHashedSessionLeaf(gpa: std.mem.Allocator, cwd: []const u8) ![]u8 {
    var hash: u64 = 14695981039346656037;
    for (cwd) |c| {
        hash ^= c;
        hash *%= 1099511628211;
    }
    return std.fmt.allocPrint(gpa, "{x}", .{hash});
}

/// Session storage directory for a project cwd.
pub fn sessionDirForCwd(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    override_dir: ?[]const u8,
) ![]u8 {
    if (override_dir) |d| return try gpa.dupe(u8, d);
    if (environ.get(ENV_SESSION_DIR)) |d| return try gpa.dupe(u8, d);
    const agent = try agentDir(gpa, environ);
    defer gpa.free(agent);
    const leaf = try encodedSessionLeaf(gpa, cwd);
    defer gpa.free(leaf);
    return try std.fs.path.join(gpa, &.{ agent, "sessions", leaf });
}

pub fn ensureDir(io: Io, path: []const u8) !void {
    std.Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

test "identity contains version" {
    try std.testing.expect(std.mem.indexOf(u8, identity, version) != null);
    try std.testing.expect(std.mem.indexOf(u8, identity, "pi") != null);
}

test "session directory leaf matches upstream and retains legacy hash helper" {
    const gpa = std.testing.allocator;
    const unix = try encodedSessionLeaf(gpa, "/home/alice/project");
    defer gpa.free(unix);
    try std.testing.expectEqualStrings("--home-alice-project--", unix);
    const windows = try encodedSessionLeaf(gpa, "C:\\Users\\Alice\\repo");
    defer gpa.free(windows);
    try std.testing.expectEqualStrings("--C--Users-Alice-repo--", windows);
    const legacy = try legacyHashedSessionLeaf(gpa, "/home/alice/project");
    defer gpa.free(legacy);
    try std.testing.expect(legacy.len > 0);
}
