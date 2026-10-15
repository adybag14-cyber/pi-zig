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
        extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
        extern "kernel32" fn GetFileInformationByHandle(w.HANDLE, *Information) callconv(.winapi) i32;
        extern "kernel32" fn GetFileInformationByHandleEx(w.HANDLE, c_int, *anyopaque, u32) callconv(.winapi) i32;
        extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
    };
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);
    // libuv's stat path preparation removes one trailing slash except the
    // drive root. Keep this distinct from resolvePath/normalizePath.
    if (wide.len > 1 and wide[wide.len - 2] != ':' and (wide[wide.len - 1] == '/' or wide[wide.len - 1] == '\\')) wide[wide.len - 1] = 0;
    // FILE_READ_ATTRIBUTES, all three sharing modes, OPEN_EXISTING, and
    // BACKUP_SEMANTICS allow directories. Omitting OPEN_REPARSE_POINT follows
    // symlinks, exactly as statSync (as opposed to lstatSync) does.
    const handle = Native.CreateFileW(wide.ptr, 0x80, 7, null, 3, 0x02000000, null);
    if (handle == w.INVALID_HANDLE_VALUE) return error.FileStatOpenFailed;
    defer _ = Native.CloseHandle(handle);
    var info: Native.Information = undefined;
    if (Native.GetFileInformationByHandle(handle, &info) == 0) return error.FileStatInformationFailed;
    var basic: Native.Basic = undefined;
    if (Native.GetFileInformationByHandleEx(handle, 0, &basic, @sizeOf(Native.Basic)) == 0) return error.FileStatInformationFailed;
    return .{
        .dev = info.volume_serial,
        .ino = (@as(u64, info.index_high) << 32) | info.index_low,
        // libuv reports zero for directories on Windows, regardless of their
        // implementation's directory stream allocation or EndOfFile value.
        .size = if (basic.attributes & 0x10 != 0) 0 else (@as(u64, info.size_high) << 32) | info.size_low,
        .mtime_ns = windowsNanoseconds(basic.modification),
        .ctime_ns = windowsNanoseconds(basic.change),
    };
}

fn windowsNanoseconds(ticks: i64) i128 {
    return (@as(i128, ticks) - 116444736000000000) * 100;
}

fn linuxStat(gpa: std.mem.Allocator, path: []const u8) !Stat {
    const linux = std.os.linux;
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: linux.Statx = undefined;
    const wanted: linux.STATX = .{ .INO = true, .SIZE = true, .MTIME = true, .CTIME = true };
    while (true) switch (std.posix.errno(linux.statx(linux.AT.FDCWD, terminated, 0, wanted, &info))) {
        .SUCCESS => break,
        .INTR => continue,
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
    };
}

fn posixStat(gpa: std.mem.Allocator, path: []const u8) !Stat {
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: std.c.Stat = undefined;
    while (true) switch (std.posix.errno(std.c.stat(terminated, &info))) {
        .SUCCESS => break,
        .INTR => continue,
        else => return error.FileStatFailed,
    };
    const mtime = info.mtime();
    const ctime = info.ctime();
    return .{
        .dev = unsignedInteger(info.dev),
        .ino = @intCast(info.ino),
        .size = @intCast(info.size),
        .mtime_ns = @as(i128, mtime.sec) * std.time.ns_per_s + mtime.nsec,
        .ctime_ns = @as(i128, ctime.sec) * std.time.ns_per_s + ctime.nsec,
    };
}

fn unsignedInteger(value: anytype) u64 {
    return if (@typeInfo(@TypeOf(value)).int.signedness == .signed) @bitCast(@as(i64, value)) else @intCast(value);
}
