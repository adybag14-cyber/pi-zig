//! ExecutionEnv path resolution, including home and file-URL conveniences.
const std = @import("std");
const builtin = @import("builtin");
const file_urls = @import("../extensions/file_urls.zig");
pub fn absoluteCwd(gpa: std.mem.Allocator, io: std.Io, input: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(input)) return std.fs.path.resolve(gpa, &.{input});
    const process_cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(process_cwd);
    return std.fs.path.resolve(gpa, &.{ process_cwd, input });
}
pub fn resolve(gpa: std.mem.Allocator, cwd: []const u8, input: []const u8, home: ?[]const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, input, 0) != null) return error.InvalidPath;
    var normalized: ?[]u8 = null;
    defer if (normalized) |path| gpa.free(path);
    if (home) |directory| {
        if (std.mem.eql(u8, input, "~")) normalized = try gpa.dupe(u8, directory) else if (std.mem.startsWith(u8, input, "~/") or (builtin.os.tag == .windows and std.mem.startsWith(u8, input, "~\\"))) normalized = try std.fs.path.join(gpa, &.{ directory, input[2..] });
    }
    if (normalized == null and std.mem.startsWith(u8, input, "file://")) normalized = file_urls.toPath(gpa, input, builtin.os.tag == .windows) catch |err| if (err == error.OutOfMemory) return err else null;
    return std.fs.path.resolve(gpa, &.{ cwd, normalized orelse input });
}
