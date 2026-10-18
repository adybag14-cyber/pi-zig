//! Stable native stdio HANDLE capabilities. No Engine/VM/frontend pointer,
//! ambient guest-fd lookup, remote HANDLE serialization or guessed CRT alias.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
pub const Lease = struct { slot: u8, generation: u64 };
pub const Map = struct { slot: u8, generation: u64 };
pub const Mapping = struct { guest_fd: i32, generation: u64 };
pub const Child = struct { lease: Lease, handle: w.HANDLE, crt_flags: u8 };
const Slot = struct {
    generation: u64 = 0, phase: enum { free, live, uncertain } = .free,
    handle: ?w.HANDLE = null, crt_flags: u8 = 0,
    close_error: ?w.Win32Error = null,
};
const Entry = struct { mapping: Mapping, lease: Lease };
const MapSlot = struct { generation: u64 = 0, active: bool = false, next_mapping: u64 = 0, entries: [64]?Entry = .{null} ** 64 };
var gate: w.SRWLOCK = .{};
var slots: [64]Slot = @splat(Slot{});
var maps: [16]MapSlot = @splat(MapSlot{});
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
    extern "kernel32" fn DuplicateHandle(w.HANDLE, w.HANDLE, w.HANDLE, *w.HANDLE, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn GetFileType(w.HANDLE) callconv(.winapi) u32;
    extern "kernel32" fn SetLastError(u32) callconv(.winapi) void;
};
fn lock() void { api.AcquireSRWLockExclusive(&gate); }
fn unlock() void { api.ReleaseSRWLockExclusive(&gate); }
fn known(reference: Lease) !*Slot {
    if (reference.slot >= slots.len) return error.NativeWindowsStdioLeaseStale;
    const slot = &slots[reference.slot];
    if (slot.generation != reference.generation or slot.phase != .live) return error.NativeWindowsStdioLeaseStale;
    return slot;
}
fn knownMap(reference: Map) !*MapSlot {
    if (reference.slot >= maps.len) return error.NativeWindowsStdioMapStale;
    const map = &maps[reference.slot];
    if (!map.active or map.generation != reference.generation) return error.NativeWindowsStdioMapStale;
    return map;
}
fn flags(actual: w.HANDLE) !u8 {
    if (actual == w.INVALID_HANDLE_VALUE or @intFromPtr(actual) == std.math.maxInt(usize) - 1) return error.NativeWindowsStdioInvalidHandle;
    api.SetLastError(0);
    return switch (api.GetFileType(actual)) {
        1 => 0x01, // CRT FOPEN, actual disk file
        3 => 0x09, // CRT FOPEN|FPIPE
        2, 0x8000 => 0x41, // CRT FOPEN|FDEV (char/remote)
        0 => if (w.GetLastError() == .SUCCESS) 0x41 else error.NativeWindowsStdioInvalidHandle,
        else => error.NativeWindowsStdioFileTypeUnsupported,
    };
}
fn duplicateHeld(actual: w.HANDLE, crt_flags: u8, inheritable: bool) !Lease {
    // Reserve bounded ownership BEFORE DuplicateHandle. Guard serializes a
    // source lease against close/reuse; no CLOSE_SOURCE flag is ever passed.
    for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
        var copied: w.HANDLE = undefined; const current = api.GetCurrentProcess();
        if (api.DuplicateHandle(current, actual, current, &copied, 0, @intFromBool(inheritable), 2) == 0) return error.NativeWindowsStdioDuplicateFailed;
        slot.generation += 1; slot.phase = .live; slot.handle = copied; slot.crt_flags = crt_flags; slot.close_error = null;
        return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativeWindowsStdioLeaseCapacity;
}
fn releaseHeld(reference: Lease) !void {
    const slot = try known(reference);
    slot.phase = .uncertain;
    if (api.CloseHandle(slot.handle.?) == 0) { slot.close_error = w.GetLastError(); return error.NativeWindowsStdioCloseUncertain; }
    slot.handle = null; slot.phase = .free;
}
pub fn release(reference: Lease) !void { lock(); defer unlock(); try releaseHeld(reference); }
pub fn duplicateForChild(reference: Lease) !Child {
    lock(); defer unlock(); const source = try known(reference);
    const copy = try duplicateHeld(source.handle.?, source.crt_flags, true);
    const slot = &slots[copy.slot]; // freshly issued under this same native guard
    return .{ .lease = copy, .handle = slot.handle.?, .crt_flags = slot.crt_flags };
}
pub fn reserveMap() !Map {
    if (builtin.os.tag != .windows) return error.RequiredWindowsStdioHandles;
    lock(); defer unlock();
    for (&maps, 0..) |*map, index| if (!map.active and map.generation != std.math.maxInt(u64)) {
        map.generation += 1; map.active = true;
        return .{ .slot = @intCast(index), .generation = map.generation };
    };
    return error.NativeWindowsStdioMapCapacity;
}
/// The embedding must hold actual against close/reuse until this synchronous
/// duplicate returns. This is a trusted host entry, never a guest HANDLE API.
pub fn authorize(reference: Map, guest_fd: i32, actual: ?w.HANDLE) !Mapping {
    if (guest_fd < 0) return error.NativeWindowsStdioGuestDescriptorInvalid;
    const handle = actual orelse return error.NativeWindowsStdioInvalidHandle;
    lock(); defer unlock(); const map = try knownMap(reference);
    if (map.next_mapping == std.math.maxInt(u64)) return error.NativeWindowsStdioMappingExhausted;
    for (map.entries) |entry| if (entry) |row| { if (row.mapping.guest_fd == guest_fd) return error.NativeWindowsStdioDescriptorMapped; };
    for (&map.entries) |*entry| if (entry.* == null) {
        const lease = try duplicateHeld(handle, try flags(handle), false);
        map.next_mapping += 1; const mapping: Mapping = .{ .guest_fd = guest_fd, .generation = map.next_mapping };
        entry.* = .{ .mapping = mapping, .lease = lease }; return mapping;
    };
    return error.NativeWindowsStdioMapCapacity;
}
pub fn acquire(reference: Map, guest_fd: i32) !Lease {
    lock(); defer unlock(); const map = try knownMap(reference);
    for (map.entries) |entry| if (entry) |row| { if (row.mapping.guest_fd == guest_fd) {
        const source = try known(row.lease); return duplicateHeld(source.handle.?, source.crt_flags, false);
    } };
    return error.NativeWindowsStdioDescriptorNotAuthorized;
}
pub fn revoke(reference: Map, mapping: Mapping) !void {
    lock(); defer unlock(); const map = try knownMap(reference);
    for (&map.entries) |*entry| if (entry.*) |row| {
        if (row.mapping.guest_fd != mapping.guest_fd or row.mapping.generation != mapping.generation) continue;
        entry.* = null; return releaseHeld(row.lease);
    };
    return error.NativeWindowsStdioMappingStale;
}
pub fn releaseMap(reference: Map) !void {
    lock(); defer unlock(); const map = try knownMap(reference);
    var failure: ?anyerror = null;
    for (&map.entries) |*entry| if (entry.*) |row| { entry.* = null; releaseHeld(row.lease) catch |err| { failure = err; }; };
    map.active = false;
    if (failure) |err| return err;
}
pub const Diagnostics = struct { live: usize = 0, uncertain: usize = 0 };
pub fn diagnostics() Diagnostics {
    lock(); defer unlock(); var result: Diagnostics = .{};
    for (slots) |slot| switch (slot.phase) { .free => {}, .live => result.live += 1, .uncertain => result.uncertain += 1 };
    return result;
}
/// Actual three-handle CRT startup layout, not a fabricated Node fd table.
/// The caller retains all supplied child duplicates until CreateProcess returns.
pub const CrtStartup = struct {
    bytes: [4 + 3 + 3 * @sizeOf(usize)]u8,
    pub fn init(handles: [3]w.HANDLE, crt_flags: [3]u8) CrtStartup {
        var result: CrtStartup = undefined;
        std.mem.writeInt(u32, result.bytes[0..4], 3, .little);
        @memcpy(result.bytes[4..7], &crt_flags);
        for (handles, 0..) |handle, index| std.mem.writeInt(usize, result.bytes[7 + index * @sizeOf(usize) ..][0..@sizeOf(usize)], @intFromPtr(handle), .little);
        return result;
    }
};

test "actual Windows inherited handle copies survive map retirement with exact inherit flags" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const TestApi = struct {
        extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*w.SECURITY_ATTRIBUTES, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
        extern "kernel32" fn GetHandleInformation(w.HANDLE, *u32) callconv(.winapi) i32;
        extern "kernel32" fn WriteFile(w.HANDLE, [*]const u8, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    };
    const original = TestApi.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("NUL"), 0xc0000000, 3, null, 3, 0x80, null);
    try std.testing.expect(original != w.INVALID_HANDLE_VALUE); var original_owned = true;
    defer if (original_owned) { _ = api.CloseHandle(original); };
    const map = try reserveMap(); var map_owned = true;
    defer if (map_owned) releaseMap(map) catch @panic("owned Windows stdio map cleanup failed");
    _ = try authorize(map, 7, original);
    original_owned = false; try std.testing.expect(api.CloseHandle(original) != 0);
    const lease = try acquire(map, 7); var lease_owned = true;
    defer if (lease_owned) release(lease) catch @panic("owned Windows stdio lease cleanup failed");
    const parent_inheritable = observed: {
        lock(); defer unlock(); var observed_flags: u32 = 0;
        const parent = (try known(lease)).handle.?;
        if (TestApi.GetHandleInformation(parent, &observed_flags) == 0) return error.NativeWindowsStdioControlHandleInformation;
        break :observed observed_flags & 1 != 0;
    };
    try std.testing.expect(!parent_inheritable);
    const child = try duplicateForChild(lease); defer release(child.lease) catch @panic("owned Windows child duplicate cleanup failed");
    map_owned = false; try releaseMap(map);
    lease_owned = false; try release(lease);
    try std.testing.expectError(error.NativeWindowsStdioMapStale, acquire(map, 7));
    var attributes: u32 = 0;
    try std.testing.expect(TestApi.GetHandleInformation(child.handle, &attributes) != 0);
    try std.testing.expect(attributes & 1 != 0);
    var transferred: u32 = 0; const bytes = [_]u8{42};
    try std.testing.expect(TestApi.WriteFile(child.handle, &bytes, bytes.len, &transferred, null) != 0);
    try std.testing.expectEqual(@as(u32, 1), transferred);
    try std.testing.expectEqual(@as(u8, 0x41), child.crt_flags);
}
