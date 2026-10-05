//! Native daemon metadata, including POSIX device/inode identity across renames.
const std = @import("std");
const builtin = @import("builtin");
pub const Kind = enum { file, directory, symlink, other };
pub const Info = struct {
    name: []u8,
    kind: Kind,
    size: u64,
    mtimeSec: i64,
    mtimeNsec: i64,
    dev: u64,
    ino: u64,
    pub fn deinit(self: *Info, gpa: std.mem.Allocator) void {
        gpa.free(self.name);
    }
};
fn fromMode(mode: u32) Kind {
    return switch (mode & 0o170000) {
        0o100000 => .file,
        0o040000 => .directory,
        0o120000 => .symlink,
        else => .other,
    };
}
fn errnoError(code: anytype) anyerror {
    return switch (code) {
        .NOENT => error.FileNotFound,
        .ACCES => error.AccessDenied,
        .PERM => error.PermissionDenied,
        .NOTDIR => error.NotDir,
        .BADF => error.BadFileDescriptor,
        .LOOP => error.SymLinkLoop,
        .NAMETOOLONG => error.NameTooLong,
        .NOMEM => error.SystemResources,
        .INVAL => error.InvalidArgument,
        else => error.Unexpected,
    };
}
fn nativeInfo(gpa: std.mem.Allocator, io: std.Io, path: []const u8, file: ?std.Io.File) !Info {
    const name = try gpa.dupe(u8, std.fs.path.basename(path));
    errdefer gpa.free(name);
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const Native = struct {
            const Time = extern struct { low: u32, high: u32 };
            const Information = extern struct { attributes: u32, creation: Time, access: Time, write: Time, volume: u32, size_high: u32, size_low: u32, links: u32, index_high: u32, index_low: u32 };
            extern "kernel32" fn GetFileInformationByHandle(handle: windows.HANDLE, info: *Information) callconv(.winapi) windows.BOOL;
        };
        const opened = if (file == null) try @import("../durable/filesystem.zig").openWindowsNoFollow(io, gpa, path, 0x80) else null;
        defer if (opened) |value| value.close(io);
        const handle = file orelse opened.?;
        const stat = try handle.stat(io);
        var native: Native.Information = undefined;
        if (Native.GetFileInformationByHandle(handle.handle, &native) == .FALSE) return error.Unexpected;
        const creation = (@as(u64, native.creation.high) << 32) | native.creation.low;
        const time = stat.mtime.nanoseconds;
        return .{ .name = name, .kind = switch (stat.kind) {
            .file => .file,
            .directory => .directory,
            .sym_link => .symlink,
            else => .other,
        }, .size = stat.size, .mtimeSec = @intCast(@divFloor(time, std.time.ns_per_s)), .mtimeNsec = @intCast(@mod(time, std.time.ns_per_s)), .dev = 0, .ino = creation };
    }
    if (builtin.os.tag == .linux) {
        const linux = std.os.linux;
        var stat: linux.Statx = undefined;
        const terminated = if (file == null) try gpa.dupeZ(u8, path) else null;
        defer if (terminated) |value| gpa.free(value);
        while (true) {
            const rc = linux.statx(if (file) |value| value.handle else linux.AT.FDCWD, if (terminated) |value| value.ptr else "", if (file != null) linux.AT.EMPTY_PATH else linux.AT.SYMLINK_NOFOLLOW, .{ .TYPE = true, .SIZE = true, .MTIME = true, .INO = true }, &stat);
            switch (linux.errno(rc)) {
                .SUCCESS => break,
                .INTR => continue,
                else => |code| return errnoError(code),
            }
        }
        if (!stat.mask.TYPE or !stat.mask.SIZE or !stat.mask.MTIME or !stat.mask.INO) return error.IncompleteRemoteMetadata;
        const major: u64 = stat.dev_major;
        const minor: u64 = stat.dev_minor;
        const device = (minor & 0xff) | ((major & 0xfff) << 8) | ((minor & ~@as(u64, 0xff)) << 12) | ((major & ~@as(u64, 0xfff)) << 32);
        return .{ .name = name, .kind = fromMode(stat.mode), .size = stat.size, .mtimeSec = stat.mtime.sec, .mtimeNsec = stat.mtime.nsec, .dev = device, .ino = stat.ino };
    }
    var stat: std.posix.Stat = undefined;
    const terminated = if (file == null) try gpa.dupeZ(u8, path) else null;
    defer if (terminated) |value| gpa.free(value);
    while (true) {
        const rc = if (file) |value| std.posix.system.fstat(value.handle, &stat) else std.posix.system.fstatat(std.posix.AT.FDCWD, terminated.?.ptr, &stat, std.posix.AT.SYMLINK_NOFOLLOW);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break,
            .INTR => continue,
            else => |code| return errnoError(code),
        }
    }
    const modified = stat.mtime();
    return .{ .name = name, .kind = fromMode(stat.mode), .size = @intCast(stat.size), .mtimeSec = modified.sec, .mtimeNsec = modified.nsec, .dev = @intCast(@as(std.meta.Int(.unsigned, @bitSizeOf(@TypeOf(stat.dev))), @bitCast(stat.dev))), .ino = stat.ino };
}
pub fn lstat(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Info {
    return nativeInfo(gpa, io, path, null);
}
pub fn fstat(gpa: std.mem.Allocator, io: std.Io, path: []const u8, file: std.Io.File) !Info {
    return nativeInfo(gpa, io, path, file);
}
test "remote metadata uses retained file identity across rename and distinguishes directories" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "before", .data = "remote-identity" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    const path = try std.fs.path.join(gpa, &.{ buffer[0..length], "before" });
    defer gpa.free(path);
    const file = try tmp.dir.openFile(io, "before", .{});
    defer file.close(io);
    var before = try lstat(gpa, io, path);
    defer before.deinit(gpa);
    try std.testing.expectEqual(Kind.file, before.kind);
    try std.testing.expectEqual(@as(u64, 15), before.size);
    try std.testing.expect(before.mtimeNsec >= 0 and before.mtimeNsec < std.time.ns_per_s);
    try tmp.dir.rename("before", tmp.dir, "after", io);
    var retained = try fstat(gpa, io, path, file);
    defer retained.deinit(gpa);
    try std.testing.expectEqual(before.ino, retained.ino);
    try std.testing.expectEqual(before.dev, retained.dev);
    if (builtin.os.tag != .windows) try std.testing.expect(before.ino != 0);
    var directory = try lstat(gpa, io, buffer[0..length]);
    defer directory.deinit(gpa);
    try std.testing.expectEqual(Kind.directory, directory.kind);
    try std.testing.expectError(error.FileNotFound, lstat(gpa, io, path));
}
