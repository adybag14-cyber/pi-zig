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
    return readMode(gpa, path, true);
}

/// Actual FOLLOWED metadata for a binding-prepared path, or its owned system
/// failure, before any handle or path cleanup can replace thread-local error
/// state. Windows input is already namespaced. This byte-only producer
/// adds no public filesystem/permission authority. Allocation/encoding/unsupported
/// metadata failures remain native errors, never invented OS errno numbers.
pub const FollowResult = union(enum) {
    metadata: Stat,
    windows_error: u32,
    posix_error: u32,
};
pub fn readWithStatus(gpa: std.mem.Allocator, path: []const u8) !FollowResult {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    if (builtin.os.tag == .windows) return switch (try @import("native_node_fs_stat_windows.zig").read(gpa, path, true)) {
        .metadata => |info| .{ .metadata = info },
        .windows_error => |code| .{ .windows_error = code },
    };
    if (builtin.os.tag != .linux) return error.RequiredNativeFollowStatPlatform;
    var failure: ?u32 = null;
    const info = linuxStatStatus(gpa, path, true, &failure) catch |err| {
        if (failure) |code| return .{ .posix_error = code };
        return err;
    };
    return .{ .metadata = info };
}
pub const LinkStatusResult = union(enum) { metadata: Stat, windows_error: u32, posix_error: u32 };
/// Separate no-follow status for a binding-prepared path; it cannot be passed
/// as a FollowResult by mistake. Windows input is already namespaced.
pub fn readLinkWithStatus(gpa: std.mem.Allocator, path: []const u8) !LinkStatusResult {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    if (builtin.os.tag == .windows) return switch (try @import("native_node_fs_stat_windows.zig").read(gpa, path, false)) {
        .metadata => |info| .{ .metadata = info },
        .windows_error => |code| .{ .windows_error = code },
    };
    if (builtin.os.tag != .linux) return error.RequiredNativeLinkStatPlatform;
    var failure: ?u32 = null;
    const info = linuxStatStatus(gpa, path, false, &failure) catch |err| {
        if (failure) |code| return .{ .posix_error = code };
        return err;
    };
    return .{ .metadata = info };
}
/// Own the original native target allocation independently of its string view.
/// Linux libuv keeps its path-limit buffer until the binding consumes the bytes.
pub const LinkBytes = struct {
    storage: []u8,
    length: usize,
    pub fn slice(self: LinkBytes) []const u8 { return self.storage[0..self.length]; }
    pub fn deinit(self: LinkBytes, gpa: std.mem.Allocator) void { gpa.free(self.storage); }
};
pub const ReadLinkBytesResult = union(enum) { bytes: LinkBytes, windows_error: u32, posix_error: u32 };
/// Actual readlink operation with owned target storage and latched raw status.
/// Input is the binding-prepared path (already namespaced on Windows). Handles
/// never escape the synchronous native owner.
pub fn readLinkBytesWithStatus(gpa: std.mem.Allocator, path: []const u8) !ReadLinkBytesResult {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    if (builtin.os.tag == .windows) {
        const w = std.os.windows;
        const Native = struct {
            extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
            extern "kernel32" fn DeviceIoControl(w.HANDLE, u32, ?*anyopaque, u32, *anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
        };
        const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
        defer gpa.free(wide);
        // fs__readlink uses access=0/share=0, OPEN_REPARSE_POINT|BACKUP_SEMANTICS.
        const handle = Native.CreateFileW(wide.ptr, 0, 0, null, 3, 0x00200000 | 0x02000000, null);
        if (handle == w.INVALID_HANDLE_VALUE) return .{ .windows_error = @intFromEnum(w.GetLastError()) };
        defer w.CloseHandle(handle);
        var buffer: [16384]u8 align(8) = undefined;
        var count: u32 = 0;
        if (Native.DeviceIoControl(handle, 0x000900a8, null, 0, &buffer, buffer.len, &count, null) == 0)
            return .{ .windows_error = @intFromEnum(w.GetLastError()) };
        if (count > buffer.len) return error.FileStatFieldsUnavailable;
        const target = (try windowsLinkTarget(buffer[0..count])) orelse return .{ .windows_error = 1464 };
        const units = try gpa.alloc(u16, target.len / 2);
        defer gpa.free(units);
        for (units, 0..) |*item, index| item.* = unit(target, index);
        const bytes = try std.unicode.wtf16LeToWtf8Alloc(gpa, units);
        return .{ .bytes = .{ .storage = bytes, .length = bytes.len } };
    } else if (builtin.os.tag == .linux) {
        const Native = struct {
            extern "c" fn pathconf([*:0]const u8, c_int) callconv(.c) c_long;
        };
        const terminated = try gpa.dupeZ(u8, path);
        defer gpa.free(terminated);
        while (true) {
            // _PC_PATH_MAX is 4 in the pinned Linux libc headers. The libuv
            // fallback is PATH_MAX (4096 on Linux), not a growing link limit.
            const configured = Native.pathconf(terminated.ptr, 4);
            const capacity: usize = if (configured == -1) 4096 else @intCast(configured);
            var bytes = try gpa.alloc(u8, capacity);
            errdefer gpa.free(bytes);
            const rc = std.os.linux.readlink(terminated.ptr, bytes.ptr, bytes.len);
            const code = std.os.linux.errno(rc);
            if (code != .SUCCESS) {
                gpa.free(bytes);
                if (code == .INTR) continue;
                return .{ .posix_error = @intFromEnum(code) };
            }
            if (rc == bytes.len) bytes = try gpa.realloc(bytes, bytes.len + 1);
            bytes[rc] = 0;
            return .{ .bytes = .{ .storage = bytes, .length = rc } };
        }
    }
    return error.RequiredNativeReadlinkPlatform;
}

/// Actual final-component link metadata, including broken links. This is not
/// a stat alias: each OS receives its native no-follow request.
pub const LinkResult = union(enum) { metadata: Stat, windows_error: u32 };
/// Own the actual Win32 failure number before handle/allocation cleanup. The
/// JS lstat owner translates this code; no thread-local GetLastError survives.
pub fn readLink(gpa: std.mem.Allocator, path: []const u8) !LinkResult {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    if (builtin.os.tag != .windows) return .{ .metadata = try readMode(gpa, path, false) };
    var failure: ?u32 = null;
    const value = windowsStat(gpa, path, false, &failure) catch |err| {
        if (failure) |code| {
            if (code == 1464 or code == 4390) {
                // libuv's retry applies to any lstat failure with these codes.
                // windowsStat already closed the first handle on this catch.
                failure = null;
                const target = windowsStat(gpa, path, true, &failure) catch |retry_err| {
                    if (failure) |retry_code| return .{ .windows_error = retry_code };
                    return retry_err;
                };
                return .{ .metadata = target };
            }
            return .{ .windows_error = code };
        }
        return err;
    };
    return .{ .metadata = value };
}
fn readMode(gpa: std.mem.Allocator, path: []const u8, follow: bool) !Stat {
    // Node validates embedded NULs before entering the OS, including Buffer
    // paths. Never allow a native sentinel to silently truncate such a path.
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    return switch (builtin.os.tag) {
        .windows => windowsStat(gpa, path, follow, null),
        .linux => linuxStat(gpa, path, follow),
        else => posixStat(gpa, path, follow),
    };
}

fn windowsStat(gpa: std.mem.Allocator, path: []const u8, follow: bool, failure: ?*?u32) !Stat {
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
    // BACKUP_SEMANTICS allows directories. OPEN_REPARSE_POINT addresses the
    // final link itself for lstat; all parent components retain OS traversal.
    const handle = Native.CreateFileW(wide.ptr, 0x80, 7, null, 3, 0x02000000 | (if (follow) @as(u32, 0) else 0x00200000), null);
    if (handle == w.INVALID_HANDLE_VALUE) {
        const code = w.GetLastError();
        if (failure) |slot| slot.* = @intFromEnum(code);
        return switch (code) {
            .FILE_NOT_FOUND, .PATH_NOT_FOUND => error.FileNotFound,
            .ACCESS_DENIED => error.AccessDenied,
            else => error.FileStatOpenFailed,
        };
    }
    defer _ = Native.CloseHandle(handle);
    var info: Native.Information = undefined;
    if (Native.GetFileInformationByHandle(handle, &info) == 0) return windowsFailure(failure);
    var basic: Native.Basic = undefined;
    if (Native.GetFileInformationByHandleEx(handle, 0, &basic, @sizeOf(Native.Basic)) == 0) return windowsFailure(failure);
    var standard: Native.Standard = undefined;
    if (Native.GetFileInformationByHandleEx(handle, 1, &standard, @sizeOf(Native.Standard)) == 0) return windowsFailure(failure);
    const directory = basic.attributes & 0x10 != 0;
    const link_length = if (!follow and basic.attributes & 0x400 != 0) try windowsLinkLength(handle, failure) else null;
    // libuv retries non-link reparse tags (including volume mount points)
    // with ordinary stat, rather than reporting every reparse point as a link.
    if (!follow and basic.attributes & 0x400 != 0 and link_length == null) {
        // One retry owner only: return through the deferred close, then let
        // readLink perform its single follow request. That follow cannot retry
        // itself when it fails with another unsupported/not-reparse code.
        if (failure) |slot| slot.* = 1464;
        return error.FileStatInformationFailed;
    }
    return .{
        .dev = info.volume_serial,
        .ino = (@as(u64, info.index_high) << 32) | info.index_low,
        // libuv reports zero for directories on Windows, regardless of their
        // implementation's directory stream allocation or EndOfFile value.
        .size = if (link_length) |length| length else if (directory) 0 else (@as(u64, info.size_high) << 32) | info.size_low,
        .mtime_ns = windowsNanoseconds(basic.modification),
        .ctime_ns = windowsNanoseconds(basic.change),
        .atime_ns = windowsNanoseconds(basic.access),
        .birthtime_ns = windowsNanoseconds(basic.creation),
        // Pinned libuv applies 0666/0444 on Windows, including directories;
        // it does not add execute bits merely because this is a directory.
        .mode = (if (link_length != null) @as(u32, 0o120000) else if (directory) @as(u32, 0o040000) else 0o100000) | 0o444 | (if (basic.attributes & 1 == 0) @as(u32, 0o222) else 0),
        .nlink = info.links,
        .blksize = 4096,
        .blocks = @intCast(@divTrunc(standard.allocation_size, 512)),
    };
}

/// Node24's bundled libuv fs__readlink_handle semantics. The actual kernel
/// payload selects the link kind and supplies the decoded WTF-8 target length.
/// null means libuv's ERROR_SYMLINK_NOT_SUPPORTED/NOT_A_REPARSE_POINT retry.
fn windowsFailure(failure: ?*?u32) anyerror!Stat {
    const code: u32 = @intFromEnum(std.os.windows.GetLastError());
    if (failure) |slot| slot.* = code;
    return error.FileStatInformationFailed;
}
pub const WindowsLinkLength = union(enum) { length: u64, windows_error: u32 };
fn windowsLinkLength(handle: std.os.windows.HANDLE, failure: ?*?u32) !?u64 {
    return switch (try windowsLinkLengthWithStatus(handle)) {
        .length => |length| length,
        .windows_error => |code| blk: {
            if (code == 4390 or code == 1464) break :blk null;
            if (failure) |slot| slot.* = code;
            return error.FileStatInformationFailed;
        },
    };
}
pub fn windowsLinkLengthWithStatus(handle: std.os.windows.HANDLE) !WindowsLinkLength {
    const Native = struct {
        extern "kernel32" fn DeviceIoControl(std.os.windows.HANDLE, u32, ?*anyopaque, u32, *anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    };
    var buffer: [16384]u8 align(8) = undefined;
    var count: u32 = 0;
    if (Native.DeviceIoControl(handle, 0x000900a8, null, 0, &buffer, buffer.len, &count, null) == 0) {
        return .{ .windows_error = @intFromEnum(std.os.windows.GetLastError()) };
    }
    if (count > buffer.len) return error.FileStatFieldsUnavailable;
    const target = (try windowsLinkTarget(buffer[0..count])) orelse return .{ .windows_error = 1464 };
    var size: u64 = 0;
    var index: usize = 0;
    while (index < target.len / 2) : (index += 1) {
        const first = unit(target, index);
        if (first >= 0xd800 and first <= 0xdbff and index + 1 < target.len / 2 and unit(target, index + 1) >= 0xdc00 and unit(target, index + 1) <= 0xdfff) {
            size += 4; index += 1;
        } else size += if (first < 0x80) @as(u64, 1) else if (first < 0x800) 2 else 3;
    }
    return .{ .length = size };
}
fn windowsLinkTarget(bytes: []u8) !?[]u8 {
    if (bytes.len < 8) return error.FileStatFieldsUnavailable;
    const tag = std.mem.readInt(u32, bytes[0..4], .little);
    const length = std.mem.readInt(u16, bytes[4..6], .little);
    if (@as(usize, length) + 8 > bytes.len) return error.FileStatFieldsUnavailable;
    const data = bytes[0 .. @as(usize, length) + 8];
    var target: []u8 = undefined;
    switch (tag) {
        0xa000000c, 0xa0000003 => {
            const base: usize = if (tag == 0xa000000c) 20 else 16;
            if (data.len < base) return error.FileStatFieldsUnavailable;
            const offset = std.mem.readInt(u16, data[8..10], .little);
            const size = std.mem.readInt(u16, data[10..12], .little);
            if (offset % 2 != 0 or size % 2 != 0 or @as(usize, offset) + size > data.len - base) return error.FileStatFieldsUnavailable;
            target = data[base + offset ..][0..size];
            if (tag == 0xa0000003) {
                // Only drive-letter junctions count; volume GUID mount points
                // are intentionally followed by libuv's retry, not branded.
                if (!ntDriveTarget(target)) return null;
                target = target[8..];
            } else if (ntPrefix(target)) {
                if (ntDriveTarget(target)) target = target[8..] else if (target.len >= 16 and
                    lowerUnit(unit(target, 4)) == 'u' and lowerUnit(unit(target, 5)) == 'n' and
                    lowerUnit(unit(target, 6)) == 'c' and unit(target, 7) == '\\') {
                    // libuv changes the old C to a backslash after removing
                    // six units. Both are one WTF-8 byte, so length is equal.
                    target = target[12..];
                    target[0] = '\\'; target[1] = 0;
                }
            }
        },
        0x8000001b => {
            if (data.len < 12 or std.mem.readInt(u32, data[8..12], .little) < 3) return null;
            var start: usize = 12;
            for (0..2) |_| {
                const end = wideStringEnd(data, start) orelse return error.FileStatFieldsUnavailable;
                if (end == start) return null;
                start = end + 2;
            }
            const end = wideStringEnd(data, start) orelse return error.FileStatFieldsUnavailable;
            target = data[start..end];
            if (target.len < 6 or !asciiDrive(unit(target, 0)) or unit(target, 1) != ':' or unit(target, 2) != '\\') return null;
        },
        else => return null,
    }
    return target;
}
fn unit(bytes: []const u8, index: usize) u16 { return std.mem.readInt(u16, bytes[index * 2 ..][0..2], .little); }
fn lowerUnit(value: u16) u16 { return if (value >= 'A' and value <= 'Z') value + 32 else value; }
fn asciiDrive(value: u16) bool { return lowerUnit(value) >= 'a' and lowerUnit(value) <= 'z'; }
fn ntPrefix(bytes: []const u8) bool { return bytes.len >= 8 and unit(bytes, 0) == '\\' and unit(bytes, 1) == '?' and unit(bytes, 2) == '?' and unit(bytes, 3) == '\\'; }
fn ntDriveTarget(bytes: []const u8) bool { return ntPrefix(bytes) and bytes.len >= 12 and asciiDrive(unit(bytes, 4)) and unit(bytes, 5) == ':' and (bytes.len == 12 or unit(bytes, 6) == '\\'); }
fn wideStringEnd(bytes: []const u8, start: usize) ?usize {
    var index = start;
    while (index + 1 < bytes.len) : (index += 2) if (std.mem.readInt(u16, bytes[index..][0..2], .little) == 0) return index;
    return null;
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

fn linuxStat(gpa: std.mem.Allocator, path: []const u8, follow: bool) !Stat {
    return linuxStatStatus(gpa, path, follow, null);
}
var status_statx_disabled: std.atomic.Value(bool) = .init(false);
fn linuxStatStatus(gpa: std.mem.Allocator, path: []const u8, follow: bool, failure: ?*?u32) !Stat {
    if (failure != null and status_statx_disabled.load(.monotonic)) return posixStatStatus(gpa, path, follow, failure);
    const linux = std.os.linux;
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: linux.Statx = undefined;
    var wanted = linux.STATX.BASIC_STATS;
    wanted.BTIME = true;
    while (true) {
        const rc = linux.statx(linux.AT.FDCWD, terminated, if (follow) 0 else linux.AT.SYMLINK_NOFOLLOW, wanted, &info);
        const code = linux.errno(rc);
        // libuv explicitly handles a nonzero/errno-zero statx result (observed
        // on filtered kernels). Never consume uninitialized fields in the new
        // status entry; preserve the legacy read path's existing behavior.
        if (failure != null and rc != 0 and code == .SUCCESS) {
            status_statx_disabled.store(true, .monotonic);
            return posixStatStatus(gpa, path, follow, failure);
        }
        switch (code) {
        .SUCCESS => break,
        .INTR => continue,
        .NOENT => return statFailure(failure, code, error.FileNotFound),
        .ACCES => return statFailure(failure, code, error.AccessDenied),
        .NOTDIR => return statFailure(failure, code, error.NotDir),
        .INVAL, .PERM, .NOSYS, .OPNOTSUPP => {
            // libuv falls back when statx is unavailable/filtered/unsupported.
            // Keep the older stat.read path separate from this new lstat seam.
            if (failure != null) status_statx_disabled.store(true, .monotonic);
            if (!follow or failure != null) return posixStatStatus(gpa, path, follow, failure);
            return error.FileStatFailed;
        },
        else => return statFailure(failure, code, error.FileStatFailed),
        }
    }
    if (failure == null and (!info.mask.INO or !info.mask.SIZE or !info.mask.MTIME or !info.mask.CTIME)) return error.FileStatFieldsUnavailable;
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
        .birthtime_ns = if (failure != null or info.mask.BTIME) @as(i128, info.btime.sec) * std.time.ns_per_s + info.btime.nsec else @as(i128, info.ctime.sec) * std.time.ns_per_s + info.ctime.nsec,
        .mode = info.mode,
        .nlink = info.nlink,
        .uid = info.uid,
        .gid = info.gid,
        .rdev = (@as(u64, info.rdev_minor) & 0xff) | ((@as(u64, info.rdev_major) & 0xfff) << 8) | ((@as(u64, info.rdev_minor) & ~@as(u64, 0xff)) << 12) | ((@as(u64, info.rdev_major) & ~@as(u64, 0xfff)) << 32),
        .blksize = info.blksize,
        .blocks = info.blocks,
    };
}

fn posixStat(gpa: std.mem.Allocator, path: []const u8, follow: bool) !Stat {
    return posixStatStatus(gpa, path, follow, null);
}
fn statFailure(failure: ?*?u32, code: anytype, err: anyerror) anyerror!Stat {
    if (failure) |slot| slot.* = @intFromEnum(code);
    return err;
}
fn posixStatStatus(gpa: std.mem.Allocator, path: []const u8, follow: bool, failure: ?*?u32) !Stat {
    const terminated = try gpa.dupeZ(u8, path);
    defer gpa.free(terminated);
    var info: std.c.Stat = undefined;
    while (true) {
        const code = std.posix.errno(if (follow) std.c.stat(terminated, &info) else std.c.fstatat(std.c.AT.FDCWD, terminated, &info, std.c.AT.SYMLINK_NOFOLLOW));
        switch (code) {
        .SUCCESS => break,
        .INTR => continue,
        .NOENT => return statFailure(failure, code, error.FileNotFound),
        .ACCES => return statFailure(failure, code, error.AccessDenied),
        .NOTDIR => return statFailure(failure, code, error.NotDir),
        else => return statFailure(failure, code, error.FileStatFailed),
        }
    }
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
