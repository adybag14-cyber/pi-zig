//! Exact newly created temporary resources, handed to the result's owner.
const std = @import("std");
const paths = @import("path.zig");
pub const File = struct { file: std.Io.File, path: []u8 };
fn uuid(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var bytes: [16]u8 = undefined;
    try io.randomSecure(&bytes);
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    const hex = std.fmt.bytesToHex(bytes, .lower);
    return std.fmt.allocPrint(gpa, "{s}-{s}-{s}-{s}-{s}", .{ hex[0..8], hex[8..12], hex[12..16], hex[16..20], hex[20..32] });
}
pub fn directory(gpa: std.mem.Allocator, io: std.Io, root: []const u8, prefix: []const u8) ![]u8 {
    const base = try paths.absoluteCwd(gpa, io, root);
    defer gpa.free(base);
    if (std.mem.indexOfScalar(u8, prefix, 0) != null) return error.InvalidTempPrefix;
    for (0..20) |_| {
        const id = try uuid(gpa, io);
        defer gpa.free(id);
        const name = try std.fmt.allocPrint(gpa, "{s}{s}", .{ prefix, id });
        defer gpa.free(name);
        const joined = try std.fs.path.join(gpa, &.{ base, name });
        defer gpa.free(joined);
        const path = try paths.absoluteCwd(gpa, io, joined);
        var transferred = false;
        defer if (!transferred) gpa.free(path);
        std.Io.Dir.cwd().createDir(io, path, .default_dir) catch |err| {
            if (err == error.PathAlreadyExists) continue;
            return err;
        };
        transferred = true;
        return path;
    }
    return error.TempNameCollisionLimit;
}
pub fn file(gpa: std.mem.Allocator, io: std.Io, root: []const u8, prefix: []const u8, suffix: []const u8) !File {
    if (std.mem.indexOfScalar(u8, prefix, 0) != null or std.mem.indexOfScalar(u8, suffix, 0) != null) return error.InvalidTempPrefix;
    const dir = try directory(gpa, io, root, "tmp-");
    defer gpa.free(dir);
    // This exact directory was just created by this call, under the checked
    // absolute root, and no path has yet escaped to a caller on failure.
    errdefer std.Io.Dir.cwd().deleteTree(io, dir) catch {};
    const id = try uuid(gpa, io);
    defer gpa.free(id);
    const name = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ prefix, id, suffix });
    defer gpa.free(name);
    const joined = try std.fs.path.join(gpa, &.{ dir, name });
    defer gpa.free(joined);
    const path = try paths.absoluteCwd(gpa, io, joined);
    errdefer gpa.free(path);
    const opened = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true });
    return .{ .file = opened, .path = path };
}
