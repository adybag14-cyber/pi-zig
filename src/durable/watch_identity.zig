//! Filesystem identity includes the device as well as its inode/file index.
const std = @import("std");
const builtin = @import("builtin");
pub const Identity = struct { device: u64, inode: std.Io.File.INode };
const HANDLE = std.os.windows.HANDLE;
const FileTime = extern struct { low: u32, high: u32 };
const HandleInfo = extern struct {
    attributes: u32,
    creation: FileTime,
    access: FileTime,
    write: FileTime,
    volume_serial: u32,
    size_high: u32,
    size_low: u32,
    links: u32,
    index_high: u32,
    index_low: u32,
};
extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*anyopaque, u32, u32, ?HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn GetFileInformationByHandle(HANDLE, *HandleInfo) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(HANDLE) callconv(.winapi) i32;
pub fn query(gpa: std.mem.Allocator, path: []const u8, follow: bool, fallback: std.Io.File.INode) !Identity {
    if (builtin.os.tag == .windows) {
        const encoded = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
        defer gpa.free(encoded);
        const handle = CreateFileW(encoded, 0, 7, null, 3, 0x02000000 | @as(u32, if (follow) 0 else 0x00200000), null);
        if (handle == std.os.windows.INVALID_HANDLE_VALUE) return .{ .device = 0, .inode = fallback };
        defer _ = CloseHandle(handle);
        var information: HandleInfo = undefined;
        if (GetFileInformationByHandle(handle, &information) == 0) return .{ .device = 0, .inode = fallback };
        return .{ .device = information.volume_serial, .inode = @bitCast((@as(u64, information.index_high) << 32) | information.index_low) };
    }
    const encoded = try gpa.dupeZ(u8, path);
    defer gpa.free(encoded);
    if (builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var information: linux.Statx = undefined;
        const result = linux.statx(linux.AT.FDCWD, encoded, if (follow) 0 else linux.AT.SYMLINK_NOFOLLOW, .{ .INO = true }, &information);
        if (linux.errno(result) != .SUCCESS or !information.mask.INO) return .{ .device = 0, .inode = fallback };
        const major: u64 = information.dev_major;
        const minor: u64 = information.dev_minor;
        const device = ((major & 0xfff) << 8) | (minor & 0xff) | ((minor & ~@as(u64, 0xff)) << 12) | ((major & ~@as(u64, 0xfff)) << 32);
        return .{ .device = device, .inode = @bitCast(information.ino) };
    }
    if (builtin.os.tag == .macos) {
        var information: std.c.Stat = undefined;
        if (std.c.fstatat(std.c.AT.FDCWD, encoded, &information, if (follow) 0 else std.c.AT.SYMLINK_NOFOLLOW) != 0) return .{ .device = 0, .inode = fallback };
        return .{ .device = @as(u32, @bitCast(information.dev)), .inode = @bitCast(information.ino) };
    }
    return .{ .device = 0, .inode = fallback };
}

test "durable watch physical device and inode identity survives rename and distinguishes a retained replacement" {
    if (builtin.os.tag != .linux and builtin.os.tag != .windows and builtin.os.tag != .macos) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "first" });
    defer gpa.free(path);
    const retained = try std.fs.path.join(gpa, &.{ buffer[0..length], "retained" });
    defer gpa.free(retained);
    try tmp.dir.writeFile(io, .{ .sub_path = "first", .data = "old-file" });
    const stat = try tmp.dir.statFile(io, "first", .{});
    const first = try query(gpa, path, true, stat.inode);
    try std.testing.expectEqual(stat.inode, first.inode);
    try std.testing.expect(first.device != 0);
    try tmp.dir.rename("first", tmp.dir, "retained", io);
    try std.testing.expectEqualDeep(first, try query(gpa, retained, true, 0));
    try tmp.dir.writeFile(io, .{ .sub_path = "first", .data = "replacement" });
    const replacement = try query(gpa, path, true, 0);
    try std.testing.expectEqual(first.device, replacement.device);
    try std.testing.expect(first.inode != replacement.inode);
}
