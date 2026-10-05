//! Native local platform paths and Bash selection, without probe processes.
const std = @import("std");
const builtin = @import("builtin");
pub const ShellConfig = struct {
    program: []u8,
    command_on_stdin: bool = false,
    pub fn deinit(self: *ShellConfig, gpa: std.mem.Allocator) void {
        gpa.free(self.program);
        self.* = undefined;
    }
};
fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}
fn legacyWsl(path: []const u8) bool {
    if (builtin.os.tag != .windows or path.len < 3 or !std.ascii.isAlphabetic(path[0]) or path[1] != ':') return false;
    const endings = [_][]const u8{ "\\windows\\system32\\bash.exe", "\\windows\\sysnative\\bash.exe" };
    for (endings) |ending| {
        if (path.len - 2 != ending.len) continue;
        var matches = true;
        for (path[2..], ending) |actual, expected| if (std.ascii.toLower(if (actual == '/') '\\' else actual) != expected) {
            matches = false;
            break;
        };
        if (matches) return true;
    }
    return false;
}
pub fn shellConfig(gpa: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, custom: ?[]const u8) !ShellConfig {
    if (custom) |path| {
        if (!exists(io, path)) return error.ShellUnavailable;
        return .{ .program = try gpa.dupe(u8, path), .command_on_stdin = legacyWsl(path) };
    }
    if (builtin.os.tag == .windows) {
        for ([_][]const u8{ "ProgramFiles", "ProgramFiles(x86)" }) |name| if (environ.get(name)) |root| {
            const path = try std.fs.path.join(gpa, &.{ root, "Git", "bin", "bash.exe" });
            if (exists(io, path)) return .{ .program = path };
            gpa.free(path);
        };
    } else if (exists(io, "/bin/bash")) return .{ .program = try gpa.dupe(u8, "/bin/bash") };
    if (environ.get("PATH")) |path| {
        var entries = std.mem.splitScalar(u8, path, if (builtin.os.tag == .windows) ';' else ':');
        while (entries.next()) |entry| {
            if (entry.len == 0) continue;
            const candidate = try std.fs.path.join(gpa, &.{ std.mem.trim(u8, entry, "\""), if (builtin.os.tag == .windows) "bash.exe" else "bash" });
            if (exists(io, candidate)) return .{ .program = candidate, .command_on_stdin = legacyWsl(candidate) };
            gpa.free(candidate);
        }
    }
    if (builtin.os.tag == .windows) return error.ShellUnavailable;
    return .{ .program = try gpa.dupe(u8, "sh") };
}
pub fn home(environ: *const std.process.Environ.Map) ?[]const u8 {
    return if (builtin.os.tag == .windows) environ.get("USERPROFILE") orelse environ.get("HOME") else environ.get("HOME");
}
pub fn resolveProgram(gpa: std.mem.Allocator, io: std.Io, program: []const u8, cwd: []const u8, environ: *const std.process.Environ.Map) ![]u8 {
    if (program.len == 0 or std.mem.indexOfScalar(u8, program, 0) != null) return error.ProgramNotFound;
    if (std.mem.indexOfAny(u8, program, if (builtin.os.tag == .windows) "/\\" else "/") != null or std.fs.path.isAbsolute(program)) return std.fs.path.resolve(gpa, &.{ cwd, program });
    const path = environ.get("PATH") orelse if (builtin.os.tag == .windows) "" else "/usr/bin:/bin";
    var entries = std.mem.splitScalar(u8, path, if (builtin.os.tag == .windows) ';' else ':');
    while (entries.next()) |entry| {
        const directory = std.mem.trim(u8, entry, "\"");
        const candidate = try std.fs.path.resolve(gpa, &.{ cwd, directory, program });
        errdefer gpa.free(candidate);
        if (exists(io, candidate)) return candidate;
        if (builtin.os.tag == .windows) {
            for ([_][]const u8{ ".exe", ".com" }) |extension| {
                const qualified = try std.fmt.allocPrint(gpa, "{s}{s}", .{ candidate, extension });
                if (exists(io, qualified)) {
                    gpa.free(candidate);
                    return qualified;
                }
                gpa.free(qualified);
            }
        }
        gpa.free(candidate);
    }
    return error.ProgramNotFound;
}
pub fn tempDirectory(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ![]u8 {
    const path = if (builtin.os.tag == .windows) environ.get("TEMP") orelse environ.get("TMP") orelse "C:\\Windows\\Temp" else environ.get("TMPDIR") orelse environ.get("TMP") orelse environ.get("TEMP") orelse "/tmp";
    return gpa.dupe(u8, path);
}
test "durable platform startup picks inherited home temp paths and rejects unavailable custom shells" {
    const gpa = std.testing.allocator;
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("HOME", "/native-home");
    try environ.put("USERPROFILE", "C:\\native-home");
    try environ.put("TMP", "/native-tmp");
    const temp = try tempDirectory(gpa, &environ);
    defer gpa.free(temp);
    try std.testing.expectEqualStrings("/native-tmp", temp);
    try std.testing.expect(home(&environ) != null);
    try std.testing.expectError(error.ShellUnavailable, shellConfig(gpa, std.testing.io, &environ, "/pi-durable-missing-shell"));
}
