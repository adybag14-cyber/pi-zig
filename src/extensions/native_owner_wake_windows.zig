//! Native completion wake lifetime, shared by child readiness and close packets.
//! Ref contains no Engine/VM/backend pointer. Sink access is guarded until detach.
const std = @import("std");
const builtin = @import("builtin");
const owner_signal = @import("native_owner_signal.zig");
const w = std.os.windows;
pub const Ref = struct { slot: u8, generation: u64 };
pub const Sink = struct {
    signal: *owner_signal.Signal,
    io: std.Io,
    // Only a reviewed native event publisher may be supplied. Never a VM call.
    host_notify: ?*const fn (?*anyopaque) void = null,
    host_context: ?*anyopaque = null,
};
const Slot = struct { guard: w.SRWLOCK = .{}, generation: u64 = 0, references: u32 = 0, sink: ?Sink = null };
var slots: [16]Slot = .{Slot{}} ** 16;
var creation_guard: w.SRWLOCK = .{};
pub fn create(sink: Sink) !Ref {
    if (builtin.os.tag != .windows) return error.NativeOwnerWakePlatformRequired;
    api.AcquireSRWLockExclusive(&creation_guard);
    defer api.ReleaseSRWLockExclusive(&creation_guard);
    for (&slots, 0..) |*slot, index| {
        api.AcquireSRWLockExclusive(&slot.guard);
        if (slot.references == 0 and slot.generation != std.math.maxInt(u64)) {
            slot.generation += 1;
            slot.references = 1;
            slot.sink = sink;
            const result: Ref = .{ .slot = @intCast(index), .generation = slot.generation };
            api.ReleaseSRWLockExclusive(&slot.guard);
            return result;
        }
        api.ReleaseSRWLockExclusive(&slot.guard);
    }
    return error.NativeOwnerWakeCapacity;
}
pub fn retain(reference: Ref) !Ref {
    if (reference.slot >= slots.len) return error.NativeOwnerWakeStale;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation != reference.generation or slot.references == 0 or slot.sink == null) return error.NativeOwnerWakeDetached;
    if (slot.references == std.math.maxInt(u32)) return error.NativeOwnerWakeReferenceLimit;
    slot.references += 1;
    return reference;
}
pub fn notify(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation != reference.generation or slot.references == 0) return;
    if (slot.sink) |sink| {
        sink.signal.notify(sink.io);
        if (sink.host_notify) |publish| publish(sink.host_context);
    }
}
/// Owner installs a genuine native host publisher after module activation.
/// Detached native references cannot restore an Engine/transport sink. Publish
/// once on attachment so readiness produced before host binding is not lost.
pub fn bindHost(reference: Ref, publish: *const fn (?*anyopaque) void, context: ?*anyopaque) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation != reference.generation or slot.references == 0) return;
    if (slot.sink) |*sink| {
        sink.host_notify = publish;
        sink.host_context = context;
        sink.signal.notify(sink.io);
        publish(context);
    }
}
pub fn detachHost(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation != reference.generation or slot.references == 0) return;
    if (slot.sink) |*sink| { sink.host_notify = null; sink.host_context = null; }
}
pub fn detach(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation == reference.generation) slot.sink = null;
}
pub fn release(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    api.AcquireSRWLockExclusive(&slot.guard);
    defer api.ReleaseSRWLockExclusive(&slot.guard);
    if (slot.generation != reference.generation or slot.references == 0) return;
    slot.references -= 1;
    if (slot.references == 0) slot.sink = null;
}
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
};
