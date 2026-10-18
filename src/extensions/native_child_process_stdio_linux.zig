//! Native descriptor capability ownership. No VM/Engine/allocator pointers and
//! no implicit mapping of a framed worker's descriptors to frontend stdio.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const capacity = 64;
pub const Lease = struct { slot: u8, generation: u64 };
const Slot = struct {
    generation: u64 = 0,
    phase: enum { free, live, uncertain } = .free,
    fd: ?linux.fd_t = null,
    close_errno: ?linux.E = null,
};
var gate: Mutex = .{};
var slots: [capacity]Slot = @splat(Slot{});
fn known(lease: Lease) !*Slot {
    if (lease.slot >= slots.len) return error.NativeStdioLeaseStale;
    const slot = &slots[lease.slot];
    if (slot.generation != lease.generation or slot.phase != .live) return error.NativeStdioLeaseStale;
    return slot;
}
fn duplicateRaw(fd: linux.fd_t) !linux.fd_t {
    // >=3 excludes collision with child stdin/stdout/stderr during dup setup.
    const copied = linux.fcntl(fd, linux.F.DUPFD_CLOEXEC, 3);
    return switch (linux.errno(copied)) {
        .SUCCESS => @intCast(copied),
        .BADF => error.NativeStdioDescriptorBadFile,
        .MFILE, .NFILE => error.NativeStdioDescriptorLimit,
        else => error.NativeStdioDescriptorDuplicateFailed,
    };
}
fn duplicateIntoSlot(fd: linux.fd_t) !Lease {
    // gate held; admission is reserved before touching the OS descriptor table.
    for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
        const copied = try duplicateRaw(fd);
        slot.generation += 1; slot.phase = .live; slot.fd = copied; slot.close_errno = null;
        return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativeStdioLeaseCapacity;
}
/// Trusted embedding entry only: actual_fd must be held against concurrent
/// close/reuse by the embedding until this synchronous duplication returns.
/// Guest numeric values are admitted only by an explicit HostMap below.
pub fn duplicateHostDescriptor(actual_fd: linux.fd_t) !Lease {
    if (builtin.os.tag != .linux) return error.RequiredLinuxStdioDescriptor;
    gate.lock(); defer gate.unlock(); return duplicateIntoSlot(actual_fd);
}
pub fn duplicate(lease: Lease) !Lease {
    gate.lock(); defer gate.unlock(); return duplicateIntoSlot((try known(lease)).fd.?);
}
/// Factory owns the returned CLOEXEC descriptor outright and closes it after
/// clone/preparation rollback. No raw borrowed descriptor escapes the guard.
pub fn duplicateForChild(lease: Lease) !linux.fd_t {
    gate.lock(); defer gate.unlock(); return duplicateRaw((try known(lease)).fd.?);
}
/// One close attempt only. An uncertain close permanently charges the native
/// slot with its diagnostic; its numeric value is never retried or reused here.
pub fn release(lease: Lease) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(lease);
    const status = linux.errno(linux.close(slot.fd.?));
    if (status != .SUCCESS) {
        slot.phase = .uncertain; slot.close_errno = status;
        return error.NativeStdioDescriptorCloseUncertain;
    }
    slot.fd = null; slot.phase = .free;
}
pub const Diagnostics = struct { live: usize = 0, uncertain: usize = 0 };
pub fn diagnostics() Diagnostics {
    gate.lock(); defer gate.unlock(); var result: Diagnostics = .{};
    for (slots) |slot| switch (slot.phase) { .free => {}, .live => result.live += 1, .uncertain => result.uncertain += 1 };
    return result;
}
pub const Mapping = struct { guest_fd: i32, generation: u64 };
const Entry = struct { mapping: Mapping, lease: Lease };
const HostMap = struct {
    guard: Mutex = .{},
    generation: u64 = 0,
    entries: [capacity]?Entry = .{null} ** capacity,
    /// Map owns a real duplicate, independent of the caller's original fd.
    /// Caller supplies actual authority; this never discovers a frontend fd.
    pub fn add(self: *HostMap, guest_fd: i32, actual_fd: linux.fd_t) !Mapping {
        if (guest_fd < 0) return error.NativeStdioGuestDescriptorInvalid;
        self.guard.lock(); defer self.guard.unlock();
        if (self.generation == std.math.maxInt(u64)) return error.NativeStdioMapGenerationExhausted;
        for (self.entries) |entry| if (entry) |value| { if (value.mapping.guest_fd == guest_fd) return error.NativeStdioGuestDescriptorMapped; };
        for (&self.entries) |*entry| if (entry.* == null) {
            const lease = try duplicateHostDescriptor(actual_fd);
            self.generation += 1;
            const mapping: Mapping = .{ .guest_fd = guest_fd, .generation = self.generation };
            entry.* = .{ .mapping = mapping, .lease = lease }; return mapping;
        };
        return error.NativeStdioMapCapacity;
    }
    pub fn acquire(self: *HostMap, guest_fd: i32) !Lease {
        self.guard.lock(); defer self.guard.unlock();
        for (self.entries) |entry| if (entry) |value| { if (value.mapping.guest_fd == guest_fd) return duplicate(value.lease); };
        return error.NativeStdioDescriptorNotAuthorized;
    }
    pub fn remove(self: *HostMap, mapping: Mapping) !void {
        self.guard.lock(); defer self.guard.unlock();
        for (&self.entries) |*entry| if (entry.*) |value| {
            if (value.mapping.guest_fd != mapping.guest_fd or value.mapping.generation != mapping.generation) continue;
            // Native lease release records uncertain ownership before this
            // map entry disappears. Its numeric fd is never closed twice.
            entry.* = null; return release(value.lease);
        };
        return error.NativeStdioMapStale;
    }
};
/// Canonical native map identity, safe to retain in a VM module without any
/// embedding stack pointer. A removed map fails closed under its generation.
pub const Map = struct { slot: u8, generation: u64 };
const MapSlot = struct { generation: u64 = 0, active: bool = false, map: HostMap = .{} };
var maps_gate: Mutex = .{};
var maps: [16]MapSlot = @splat(MapSlot{});
fn knownMap(reference: Map) !*HostMap {
    if (reference.slot >= maps.len) return error.NativeStdioMapStale;
    const slot = &maps[reference.slot];
    if (!slot.active or slot.generation != reference.generation) return error.NativeStdioMapStale;
    return &slot.map;
}
pub fn reserveMap() !Map {
    if (builtin.os.tag != .linux) return error.RequiredLinuxStdioDescriptor;
    maps_gate.lock(); defer maps_gate.unlock();
    for (&maps, 0..) |*slot, index| if (!slot.active and slot.generation != std.math.maxInt(u64)) {
        slot.generation += 1; slot.active = true;
        return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativeStdioMapCapacity;
}
pub fn authorize(reference: Map, guest_fd: i32, actual_fd: linux.fd_t) !Mapping {
    maps_gate.lock(); defer maps_gate.unlock(); return (try knownMap(reference)).add(guest_fd, actual_fd);
}
pub fn acquire(reference: Map, guest_fd: i32) !Lease {
    maps_gate.lock(); defer maps_gate.unlock(); return (try knownMap(reference)).acquire(guest_fd);
}
pub fn revoke(reference: Map, mapping: Mapping) !void {
    maps_gate.lock(); defer maps_gate.unlock(); return (try knownMap(reference)).remove(mapping);
}
pub fn releaseMap(reference: Map) !void {
    maps_gate.lock(); defer maps_gate.unlock(); const map = try knownMap(reference);
    var failure: ?anyerror = null;
    for (&map.entries) |*entry| if (entry.*) |value| {
        entry.* = null; release(value.lease) catch |err| { failure = err; };
    };
    // Each removed entry was either physically closed or preserved in an
    // uncertain native pool slot before releasing the map generation.
    maps[reference.slot].active = false;
    if (failure) |err| return err;
}

test "authorized actual descriptor duplicates survive map removal and reject stale mappings" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const raw = linux.open("/dev/null", .{ .ACCMODE = .WRONLY, .CLOEXEC = true }, 0);
    try std.testing.expect(linux.errno(raw) == .SUCCESS);
    const actual: linux.fd_t = @intCast(raw); var original_owned = true;
    defer if (original_owned) { _ = linux.close(actual); };
    var map: HostMap = .{};
    const mapping = try map.add(9, actual); var mapped = true;
    defer if (mapped) map.remove(mapping) catch @panic("owned descriptor map cleanup failed");
    original_owned = false;
    try std.testing.expect(linux.errno(linux.close(actual)) == .SUCCESS);
    const lease = try map.acquire(9); defer release(lease) catch @panic("owned descriptor lease cleanup failed");
    try map.remove(mapping); mapped = false;
    try std.testing.expectError(error.NativeStdioMapStale, map.remove(mapping));
    try std.testing.expectError(error.NativeStdioDescriptorNotAuthorized, map.acquire(9));
    const child_fd = try duplicateForChild(lease); defer _ = linux.close(child_fd);
    const byte = [_]u8{42}; try std.testing.expectEqual(@as(usize, 1), linux.write(child_fd, &byte, byte.len));
}

test "stable native map ticket removal cannot authorize a reused map generation" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const first = try reserveMap(); var first_owned = true;
    defer if (first_owned) releaseMap(first) catch @panic("owned first stdio map cleanup failed");
    try releaseMap(first); first_owned = false;
    const later = try reserveMap(); defer releaseMap(later) catch @panic("owned later stdio map cleanup failed");
    try std.testing.expectEqual(first.slot, later.slot);
    try std.testing.expect(first.generation != later.generation);
    try std.testing.expectError(error.NativeStdioMapStale, acquire(first, 0));
    try std.testing.expectError(error.NativeStdioDescriptorNotAuthorized, acquire(later, 0));
}
