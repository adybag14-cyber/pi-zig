//! App identity, paths (~/.pi/agent), and env var names.
const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

pub const APP_NAME = "pi";
pub const CONFIG_DIR_NAME = ".pi";
pub const AGENT_DIR_NAME = "agent";
pub const version = "0.2.0";
pub const identity = "pi (pi-zig) coding agent " ++ version;

pub const ENV_AGENT_DIR = "PI_AGENT_DIR";
pub const ENV_SESSION_DIR = "PI_SESSION_DIR";
pub const ENV_MOCK_SCRIPT = "PI_MOCK_SCRIPT";
pub const ENV_MODEL = "PI_MODEL";
pub const ENV_API_KEY = "PI_API_KEY";
pub const ENV_OPENAI_KEY = "OPENAI_API_KEY";
pub const ENV_ANTHROPIC_KEY = "ANTHROPIC_API_KEY";
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

/// Session storage directory for a project cwd (hash under agent dir sessions/).
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
    // Simple stable folder name from cwd (sanitized)
    var hash: u64 = 14695981039346656037;
    for (cwd) |c| {
        hash ^= c;
        hash *%= 1099511628211;
    }
    const leaf = try std.fmt.allocPrint(gpa, "{x}", .{hash});
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
