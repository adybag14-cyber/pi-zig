//! The five kernel fields consumed by actual Source utils/paths.ts.
//! std.Io.File.Stat deliberately omits the device number. Read the native
//! metadata instead of substituting an inode, a path hash, or creation time.
const std = @import("std");
const builtin = @import("builtin");

pub const Stat = struct {
    dev: u64,
    ino: u64,
    size: u64,
    mtime_ns: i128,
    ctime_ns: i128,
    atime_ns: i128 = 0,
    birthtime_ns: i128 = 0,
    mode: u32 = 0,
    nlink: u64 = 0,
    uid: u64 = 0,
    gid: u64 = 0,
    rdev: u64 = 0,
    blksize: u64 = 0,
    blocks: u64 = 0,
};

pub fn read(gpa: std.mem.Allocator, path: []const u8) !Stat {
    // Node validates embedded NULs before entering the OS, including Buffer
    // paths. Never allow a native sentinel to silently truncate such a path.
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    return switch (builtin.os.tag) {
        .windows => windowsStat(gpa, path),
        .linux => linuxStat(gpa, path),
        else => posixStat(gpa, path),
    };
}

fn windowsStat(gpa: std.mem.Allocator, path: []const u8) !Stat {
    const w = std.os.windows;
    const Native = struct {
        const FileTime = extern struct { low: u32, high: u32 };
        const Information = extern struct {
            attributes: u32,
            creation: FileTime,
            access: FileTime,
            modification: FileTime,
            volume_serial: u32,
            size_high: u32,
            size_low: u32,
            links: u32,
            index_high: u32,
            index_low: u32,
        };
        const Basic = extern struct {
            creation: i64,
            access: i64,
            modification: i64,
            change: i64,
            attributes: u32,
        };
        const Standard = extern struct { allocation_size: i64, end_of_file: i64, links: u32, delete_pending: u8, directory: u8 };
        extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
        extern "kernel32" fn GetFileInformationByHandle(w.HANDLE, *Information) callconv(.winapi) i32;
        extern "kernel32" fn GetFileInformationByHandleEx(w.HANDLE, c_int, *anyopaque, u32) callconv(.winapi) i32;
        extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
    };
    const namespaced = try windowsNamespacedPath(gpa, path);
    defer gpa.free(namespaced);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, namespaced);
    defer gpa.free(wide);
    // libuv's stat path preparation removes one trailing slash except the
    // drive root. Keep this distinct from resolvePath/normalizePath.
    if (wide.len > 1 and wide[wide.len - 2] != ':' and (wide[wide.len - 1] == '/' or wide[wide.len - 1] == '\\')) wide[wide.len - 1] = 0;
    // FILE_READ_ATTRIBUTES, all three sharing modes, OPEN_EXISTING, and
    // BACKUP_SEMANTICS allow directories. Omitting OPEN_REPARSE_POINT follows
    // symlinks, exactly as statSync (as opposed to lstatSync) does.
    const handle = Native.CreateFileW(wide.ptr, 0x80, 7, null, 3, 0x02000000, null);
    if (handle == w.INVALID_HANDLE_VALUE) return switch (w.GetLastError()) {
        .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.FileNotFound,
        .ACCESS_DENIED => error.AccessDenied,
        else => error.FileStatOpenFailed,
    };
    defer _ = Native.CloseHandle(handle);
    var info: Native.Information = undefined;
    if (Native.GetFileInformationByHandle(handle, &info) == 0) return error.FileStatInformationFailed;
    var basic: Native.Basic = undefined;
    if (Native.GetFileInformationByHandleEx(handle, 0, &basic, @sizeOf(Native.Basic)) == 0) return error.FileStatInformationFailed;
    var standard: Native.Standard = undefined;
    if (Native.GetFileInformationByHandleEx(handle, 1, &standard, @sizeOf(Native.Standard)) == 0) return error.FileStatInformationFailed;
    const directory = basic.attributes & 0x10 != 0;
    return .{
        .dev = info.volume_serial,
        .ino = (@as(u64, info.index_high) << 32) | info.index_low,
        // libuv reports zero for directories on Windows, regardless of their
        // implementation's directory stream allocation or EndOfFile value.
        .size = if (basic.attributes & 0x10 != 0) 0 else (@as(u64, info.size_high) << 32) | info.size_low,
        .mtime_ns = windowsNanoseconds(basic.modification),
        .ctime_ns = windowsNanoseconds(basic.change),
        .atime_ns = windowsNanoseconds(basic.access),
        .birthtime_ns = windowsNanoseconds(basic.creation),
        .mode = (if (directory) @as(u32, 0o040111) else @as(u32, 0o100000)) | 0o444 | (if (basic.attributes & 1 == 0) @as(u32, 0o222) else 0),
        .nlink = info.links,
        .blksize = 4096,
        .blocks = @intCast(@divTrunc(standard.allocation_size, 512)),
    };
}

/// Node's fs binding applies path.toNamespacedPath before libuv's stat call.
/// Lexical resolution must preserve trailing spaces/dots: GetFullPathNameW
/// on the user's complete path would silently trim a different filename.
/// Only use it to obtain the real current directory (including drive-relative
/// directories), then resolve the supplied components without Win32 trimming.
pub fn windowsNamespacedPath(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    if (path.len == 0 or std.mem.startsWith(u8, path, "\\\\?\\") or std.mem.startsWith(u8, path, "\\\\.\\")) return gpa.dupe(u8, path);
    const Native = struct {
        extern "kernel32" fn GetFullPathNameW([*:0]const u16, u32, [*]u16, ?*?[*]u16) callconv(.winapi) u32;
    };
    var current: [std.os.windows.PATH_MAX_WIDE:0]u16 = undefined;
    var drive_directory = [_:0]u16{ '.', 0, 0, 0 };
    const drive_relative = path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path.len == 2 or (path[2] != '\\' and path[2] != '/'));
    if (drive_relative) {
        drive_directory[0] = path[0];
        drive_directory[1] = ':';
        drive_directory[2] = '.';
    }
    const count = Native.GetFullPathNameW(&drive_directory, current.len, &current, null);
    if (count == 0 or count >= current.len) return error.FileStatPathResolutionFailed;
    const cwd = try std.unicode.wtf16LeToWtf8Alloc(gpa, current[0..count]);
    defer gpa.free(cwd);
    const absolute = try std.fs.path.resolveWindows(gpa, &.{ cwd, path });
    defer gpa.free(absolute);
    if (absolute.len >= 3 and absolute[1] == ':' and absolute[2] == '\\') return std.fmt.allocPrint(gpa, "\\\\?\\{s}", .{absolute});
    if (std.mem.startsWith(u8, absolute, "\\\\") and absolute.len > 2 and absolute[2] != '?' and absolute[2] != '.') return std.fmt.allocPrint(gpa, "\\\\?\\UNC\\{s}", .{absolute[2..]});
    return gpa.dupe(u8, path);
}

fn windowsNanoseconds(ticks: i64) i128 {
    return (@as(i128, ticks) - 116444736000000000) * 100;
}

fn linuxStat(gpa: std.mem.Allocator, path: []const u8) !Stat {
    const linux = std.os.linux;
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: linux.Statx = undefined;
    var wanted = linux.STATX.BASIC_STATS;
    wanted.BTIME = true;
    while (true) switch (linux.errno(linux.statx(linux.AT.FDCWD, terminated, 0, wanted, &info))) {
        .SUCCESS => break,
        .INTR => continue,
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        .NOTDIR => return error.NotDir,
        else => return error.FileStatFailed,
    };
    if (!info.mask.INO or !info.mask.SIZE or !info.mask.MTIME or !info.mask.CTIME) return error.FileStatFieldsUnavailable;
    // Linux dev_t uses glibc's makedev encoding, not major:minor text and not
    // stx_mnt_id. Its full unsigned integer is the Node BigInt dev field.
    const major: u64 = info.dev_major;
    const minor: u64 = info.dev_minor;
    return .{
        .dev = (minor & 0xff) | ((major & 0xfff) << 8) | ((minor & ~@as(u64, 0xff)) << 12) | ((major & ~@as(u64, 0xfff)) << 32),
        .ino = info.ino,
        .size = info.size,
        .mtime_ns = @as(i128, info.mtime.sec) * std.time.ns_per_s + info.mtime.nsec,
        .ctime_ns = @as(i128, info.ctime.sec) * std.time.ns_per_s + info.ctime.nsec,
        .atime_ns = @as(i128, info.atime.sec) * std.time.ns_per_s + info.atime.nsec,
        .birthtime_ns = if (info.mask.BTIME) @as(i128, info.btime.sec) * std.time.ns_per_s + info.btime.nsec else @as(i128, info.ctime.sec) * std.time.ns_per_s + info.ctime.nsec,
        .mode = info.mode,
        .nlink = info.nlink,
        .uid = info.uid,
        .gid = info.gid,
        .rdev = (@as(u64, info.rdev_minor) & 0xff) | ((@as(u64, info.rdev_major) & 0xfff) << 8) | ((@as(u64, info.rdev_minor) & ~@as(u64, 0xff)) << 12) | ((@as(u64, info.rdev_major) & ~@as(u64, 0xfff)) << 32),
        .blksize = info.blksize,
        .blocks = info.blocks,
    };
}

fn posixStat(gpa: std.mem.Allocator, path: []const u8) !Stat {
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: std.c.Stat = undefined;
    while (true) switch (std.posix.errno(std.c.stat(terminated, &info))) {
        .SUCCESS => break,
        .INTR => continue,
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        .NOTDIR => return error.NotDir,
        else => return error.FileStatFailed,
    };
    const mtime = info.mtime();
    const ctime = info.ctime();
    const atime = info.atime();
    const birthtime = if (@hasDecl(std.c.Stat, "birthtime")) info.birthtime() else ctime;
    return .{
        .dev = unsignedInteger(info.dev),
        .ino = @intCast(info.ino),
        .size = @intCast(info.size),
        .mtime_ns = @as(i128, mtime.sec) * std.time.ns_per_s + mtime.nsec,
        .ctime_ns = @as(i128, ctime.sec) * std.time.ns_per_s + ctime.nsec,
        .atime_ns = @as(i128, atime.sec) * std.time.ns_per_s + atime.nsec,
        .birthtime_ns = @as(i128, birthtime.sec) * std.time.ns_per_s + birthtime.nsec,
        .mode = @intCast(info.mode),
        .nlink = @intCast(info.nlink),
        .uid = @intCast(info.uid),
        .gid = @intCast(info.gid),
        .rdev = unsignedInteger(info.rdev),
        .blksize = @intCast(info.blksize),
        .blocks = @intCast(info.blocks),
    };
}

fn unsignedInteger(value: anytype) u64 {
    return if (@typeInfo(@TypeOf(value)).int.signedness == .signed) @bitCast(@as(i64, value)) else @intCast(value);
}
