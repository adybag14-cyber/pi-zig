// Copyright Joyent, Inc. and other Node contributors. MIT; retained libuv LICENSE.
//! Node24's actual libuv Windows stat path, handle and directory fallback.
//! Each unsuccessful native operation owns its numeric result before a handle
//! closes. This module does not dispatch through guest objects or callbacks.
const std = @import("std");
const w = std.os.windows;
const raw = @import("native_file_stat.zig");
const paths = @import("native_node_package_path.zig");
pub const Result = union(enum) { metadata: raw.Stat, windows_error: u32 };

const Basic = extern struct { creation: i64, access: i64, modification: i64, change: i64, attributes: u32 };
const Standard = extern struct { allocation: i64, end: i64, links: u32, delete_pending: u8, directory: u8 };
const Name = extern struct { length: u32, value: [1]u16 };
const All = extern struct {
    basic: Basic, standard: Standard, index: i64, ea_size: u32, access: u32,
    position: i64, mode: u32, alignment: u32, name: Name,
};
const Device = extern struct { kind: u32, characteristics: u32 };
const Volume = extern struct { creation: i64, serial: u32, label_length: u32, supports_objects: u8, label: [1]u16 };
const Directory = extern struct {
    next: u32, index: u32, creation: i64, access: i64, modification: i64, change: i64,
    end: i64, allocation: i64, attributes: u32, name_length: u32, ea_size: u32,
    file_id: i64, name: [1]u16,
};
/// FILE_STAT_BASIC_INFORMATION, including fields beyond the subset consumed by
/// fs__stat_assign_statbuf. Their actual ABI positions are retained.
const Information = extern struct {
    file_id: i64, creation: i64, access: i64, modification: i64, change: i64,
    allocation: i64, end: i64, attributes: u32, reparse_tag: u32, links: u32,
    device: u32, characteristics: u32, reserved: u32, serial: i64, file_id_128: [16]u8,
};
comptime {
    // These buffers are written by the actual NT APIs, including their trailing
    // variable-length fields. Reject an ABI layout that could corrupt storage.
    if (@sizeOf(Basic) != 40 or @sizeOf(Standard) != 24 or
        @sizeOf(All) != 104 or @offsetOf(All, "name") != 96 or
        @sizeOf(Device) != 8 or @sizeOf(Volume) != 24 or
        @offsetOf(Volume, "label") != 18 or @sizeOf(Directory) != 88 or
        @offsetOf(Directory, "file_id") != 72 or @offsetOf(Directory, "name") != 80 or
        @sizeOf(Information) != 104 or @offsetOf(Information, "serial") != 80 or
        @offsetOf(Information, "file_id_128") != 88)
        @compileError("The Node Windows stat buffers require the pinned NT ABI.");
}
const GetByName = *const fn ([*:0]const u16, c_int, *anyopaque, u32) callconv(.winapi) i32;
const OnceCallback = *const fn (*usize, ?*anyopaque, ?*?*anyopaque) callconv(.winapi) i32;
const Native = struct {
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
    extern "kernel32" fn GetModuleHandleA([*:0]const u8) callconv(.winapi) ?w.HANDLE;
    extern "kernel32" fn GetProcAddress(w.HANDLE, [*:0]const u8) callconv(.winapi) ?*const anyopaque;
    extern "kernel32" fn InitOnceExecuteOnce(*usize, OnceCallback, ?*anyopaque, ?*?*anyopaque) callconv(.winapi) i32;
    extern "ntdll" fn RtlNtStatusToDosError(w.NTSTATUS) callconv(.winapi) u32;
};
var api_once: usize = 0;
var get_by_name: ?GetByName = null;
fn initializeApi(_: *usize, _: ?*anyopaque, _: ?*?*anyopaque) callconv(.winapi) i32 {
    // Same optional already-loaded API-set probe as pinned uv__winapi_init.
    // GetModuleHandle does not create a library reference or an owned handle.
    if (Native.GetModuleHandleA("api-ms-win-core-file-l2-1-4.dll")) |module| {
        if (Native.GetProcAddress(module, "GetFileInformationByName")) |function| {
            get_by_name = @ptrCast(function);
        }
    }
    return 1;
}
fn lastError() u32 { return @intFromEnum(w.GetLastError()); }
fn failedStatus(status: w.NTSTATUS) bool { return @intFromEnum(status) >> 30 == 3; }
fn statusFailure(status: w.NTSTATUS) Result { return .{ .windows_error = Native.RtlNtStatusToDosError(status) }; }
fn ioBlock() w.IO_STATUS_BLOCK { return .{ .u = .{ .Status = @enumFromInt(0) }, .Information = 0 }; }
fn nanoseconds(ticks: i64) i128 { return (@as(i128, ticks) - 116444736000000000) * 100; }
fn nullDevice() raw.Stat {
    return .{ .dev = 0, .ino = 0, .size = 0, .mtime_ns = 0, .ctime_ns = 0,
        .mode = 0o020666, .nlink = 1, .blksize = 4096, .rdev = @as(u64, 0x15) << 16 };
}
fn metadata(info: Information, follow: bool) raw.Stat {
    const link = !follow and info.attributes & 0x400 != 0;
    const directory = info.attributes & 0x10 != 0;
    return .{
        .dev = @as(u32, @truncate(@as(u64, @bitCast(info.serial)))),
        .ino = @bitCast(info.file_id),
        .size = if (link or !directory) @bitCast(info.end) else 0,
        .mtime_ns = nanoseconds(info.modification), .ctime_ns = nanoseconds(info.change),
        .atime_ns = nanoseconds(info.access), .birthtime_ns = nanoseconds(info.creation),
        .mode = @as(u32, if (link) 0o120000 else if (directory) 0o040000 else 0o100000) |
            @as(u32, if (info.attributes & 1 != 0) 0o444 else 0o666),
        .nlink = info.links, .blksize = 4096,
        .blocks = @as(u64, @bitCast(info.allocation)) >> 9,
    };
}
const Fast = union(enum) { metadata: raw.Stat, windows_error: u32, slow };
fn fast(path: [*:0]const u16, follow: bool) !Fast {
    if (Native.InitOnceExecuteOnce(&api_once, initializeApi, null, null) == 0)
        return error.NativeFilesystemApiInitializationFailed;
    const call = get_by_name orelse return .slow;
    var info: Information = undefined;
    if (call(path, 3, &info, @sizeOf(Information)) == 0) {
        const code = lastError();
        return switch (code) { 2, 3, 21, 67 => .{ .windows_error = code }, else => .slow };
    }
    if (info.attributes & 0x400 != 0) return .slow;
    return .{ .metadata = if (info.device == 0x15) nullDevice() else metadata(info, follow) };
}
fn handleMetadata(handle: w.HANDLE, follow: bool) !Result {
    var device: Device = undefined;
    var io = ioBlock();
    var status = w.ntdll.NtQueryVolumeInformationFile(handle, &io, &device, @sizeOf(Device), .Device);
    // NT warning statuses, including a short variable-length buffer, are valid.
    if (failedStatus(status)) return statusFailure(status);
    if (device.kind == 0x15) return .{ .metadata = nullDevice() };
    var file: All = undefined;
    status = w.ntdll.NtQueryInformationFile(handle, &io, &file, @sizeOf(All), .All);
    if (failedStatus(status)) return statusFailure(status);
    var volume: Volume = undefined;
    status = w.ntdll.NtQueryVolumeInformationFile(handle, &io, &volume, @sizeOf(Volume), .Volume);
    var info: Information = std.mem.zeroes(Information);
    if (@intFromEnum(io.u.Status) == 0xc0000002) {
        info.serial = 0;
    } else if (failedStatus(status)) {
        return statusFailure(status);
    } else info.serial = volume.serial;
    info.device = device.kind;
    info.attributes = file.basic.attributes;
    info.links = file.standard.links;
    info.file_id = file.index;
    info.creation = file.basic.creation;
    info.access = file.basic.access;
    info.modification = file.basic.modification;
    info.change = file.basic.change;
    info.allocation = file.standard.allocation;
    if (!follow and file.basic.attributes & 0x400 != 0) {
        const target = try raw.windowsLinkLengthWithStatus(handle);
        switch (target) {
            .length => |length| info.end = @bitCast(length),
            .windows_error => |code| return .{ .windows_error = code },
        }
    } else info.end = file.standard.end;
    return .{ .metadata = metadata(info, follow) };
}
fn directoryMetadata(path: [:0]u16, follow: bool, original_error: u32) Result {
    var split = path.len;
    var includes_name = false;
    while (split > 0 and path[split - 1] != '\\' and path[split - 1] != '/' and path[split - 1] != ':') {
        if (path[split - 1] != '.') includes_name = true;
        split -= 1;
    }
    var restore: ?struct { at: usize, unit: u16 } = null;
    defer if (restore) |saved| { path[saved.at] = saved.unit; };
    var directory: [*:0]const u16 = path.ptr;
    if (split == 0 and includes_name) {
        directory = &[_:0]u16{'.'};
    } else if (split > 0 and (path[split - 1] == '\\' or path[split - 1] == '/')) {
        if (!includes_name) split = path.len else {
            restore = .{ .at = split - 1, .unit = path[split - 1] };
            path[split - 1] = 0;
        }
    } else split = path.len;
    const filename = std.mem.sliceTo(path.ptr + split, 0);
    for (filename) |unit| switch (unit) {
        '*', '?', '>', '<', '"' => return .{ .windows_error = 123 },
        else => {},
    };
    const handle = Native.CreateFileW(directory, 1, 7, null, 3, 0x02000000, null);
    if (handle == w.INVALID_HANDLE_VALUE) return .{ .windows_error = lastError() };
    defer w.CloseHandle(handle);
    // Actual uv__RtlUnicodeStringInit limit and STATUS_INVALID_PARAMETER.
    if (filename.len > 0x7fff) return statusFailure(@enumFromInt(0xc000000d));
    const mask = w.UNICODE_STRING.init(filename);
    var io = ioBlock();
    var entry: Directory = undefined;
    var status = w.ntdll.NtQueryDirectoryFile(handle, null, null, null, &io, &entry,
        @sizeOf(Directory), .IdFullDirectory, w.BOOLEAN.TRUE, &mask, w.BOOLEAN.TRUE);
    const code = @intFromEnum(status);
    if (code & 0x80000000 != 0 and code != 0x80000005) {
        if (code == 0x80000006) return .{ .windows_error = 3 };
        return statusFailure(status);
    }
    var info: Information = std.mem.zeroes(Information);
    info.attributes = entry.attributes;
    info.creation = entry.creation;
    info.access = entry.access;
    info.modification = entry.modification;
    if (entry.attributes & 0x400 != 0) {
        if (follow) return .{ .windows_error = original_error };
        // The access-denied directory fallback has no link handle. Pinned
        // libuv reports zero length for its lstat reparse entry.
    } else {
        info.end = entry.end;
        info.allocation = entry.allocation;
    }
    info.change = entry.change;
    info.file_id = entry.file_id;
    var volume: Volume = undefined;
    status = w.ntdll.NtQueryVolumeInformationFile(handle, &io, &volume, @sizeOf(Volume), .Volume);
    if (@intFromEnum(io.u.Status) == 0xc0000002) {
        info.serial = 0;
    } else if (failedStatus(status)) {
        return statusFailure(status);
    } else info.serial = volume.serial;
    var device: Device = undefined;
    status = w.ntdll.NtQueryVolumeInformationFile(handle, &io, &device, @sizeOf(Device), .Device);
    if (failedStatus(status)) return statusFailure(status);
    info.device = device.kind;
    info.links = 1;
    return .{ .metadata = metadata(info, follow) };
}
fn once(path: [:0]u16, follow: bool) !Result {
    switch (try fast(path.ptr, follow)) {
        .metadata => |info| return .{ .metadata = info },
        .windows_error => |code| return .{ .windows_error = code },
        .slow => {},
    }
    const flags: u32 = 0x02000000 | (if (follow) @as(u32, 0) else 0x00200000);
    const handle = Native.CreateFileW(path.ptr, 0x80, 7, null, 3, flags, null);
    if (handle == w.INVALID_HANDLE_VALUE) {
        const code = lastError();
        if (code != 5 and code != 32) return .{ .windows_error = code };
        return directoryMetadata(path, follow, code);
    }
    defer w.CloseHandle(handle);
    return handleMetadata(handle, follow);
}
/// Separate real stat/lstat result with the exact one follow retry for an
/// unsupported/non-reparse link. The first owner closes before that retry.
pub fn read(gpa: std.mem.Allocator, path: []const u8, follow: bool) !Result {
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidFileStatPath;
    const namespaced = try paths.namespaced(gpa, path);
    defer gpa.free(namespaced);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, namespaced);
    defer gpa.free(wide);
    var length = wide.len;
    if (length > 1 and wide[length - 2] != ':' and (wide[length - 1] == '\\' or wide[length - 1] == '/')) {
        length -= 1;
        wide[length] = 0;
    }
    const prepared = wide[0..length :0];
    const first = try once(prepared, follow);
    if (!follow) {
        switch (first) {
            .windows_error => |code| {
                if (code == 1464 or code == 4390) return once(prepared, true);
            },
            .metadata => {},
        }
    }
    return first;
}
