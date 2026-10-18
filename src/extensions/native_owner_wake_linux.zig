//! Linux native completion wake lifetime, shared by child readiness/close packets.
//! Ref contains no Engine/VM/backend pointer. Sink access is guarded until detach.
const std = @import("std");
const builtin = @import("builtin");
const owner_signal = @import("native_owner_signal.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const Ref = struct { slot: u8, generation: u64 };
pub const Sink = struct {
    signal: *owner_signal.Signal,
    io: std.Io,
    // Only a reviewed native event publisher may be supplied. Never a VM call.
    host_notify: ?*const fn (?*anyopaque) void = null,
    host_context: ?*anyopaque = null,
};
const Slot = struct { guard: Mutex = .{}, generation: u64 = 0, references: u32 = 0, sink: ?Sink = null };
var slots: [16]Slot = @splat(Slot{});
var creation_guard: Mutex = .{};
pub fn create(sink: Sink) !Ref {
    if (builtin.os.tag != .linux) return error.NativeOwnerWakePlatformRequired;
    creation_guard.lock();
    defer creation_guard.unlock();
    for (&slots, 0..) |*slot, index| {
        slot.guard.lock();
        if (slot.references == 0 and slot.generation != std.math.maxInt(u64)) {
            slot.generation += 1;
            slot.references = 1;
            slot.sink = sink;
            const result: Ref = .{ .slot = @intCast(index), .generation = slot.generation };
            slot.guard.unlock();
            return result;
        }
        slot.guard.unlock();
    }
    return error.NativeOwnerWakeCapacity;
}
pub fn retain(reference: Ref) !Ref {
    if (reference.slot >= slots.len) return error.NativeOwnerWakeStale;
    const slot = &slots[reference.slot];
    slot.guard.lock();
    defer slot.guard.unlock();
    if (slot.generation != reference.generation or slot.references == 0 or slot.sink == null) return error.NativeOwnerWakeDetached;
    if (slot.references == std.math.maxInt(u32)) return error.NativeOwnerWakeReferenceLimit;
    slot.references += 1;
    return reference;
}
pub fn notify(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    slot.guard.lock();
    defer slot.guard.unlock();
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
    slot.guard.lock();
    defer slot.guard.unlock();
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
    slot.guard.lock();
    defer slot.guard.unlock();
    if (slot.generation != reference.generation or slot.references == 0) return;
    if (slot.sink) |*sink| { sink.host_notify = null; sink.host_context = null; }
}
pub fn detach(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    slot.guard.lock();
    defer slot.guard.unlock();
    if (slot.generation == reference.generation) slot.sink = null;
}
pub fn release(reference: Ref) void {
    if (reference.slot >= slots.len) return;
    const slot = &slots[reference.slot];
    slot.guard.lock();
    defer slot.guard.unlock();
    if (slot.generation != reference.generation or slot.references == 0) return;
    slot.references -= 1;
    if (slot.references == 0) slot.sink = null;
}

test "Linux wake detach preserves native references without restoring an owner sink" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var signal: owner_signal.Signal = .{};
    const reference = try create(.{ .signal = &signal, .io = std.testing.io });
    const worker = try retain(reference);
    const observed = signal.observe();
    detach(reference);
    try std.testing.expectError(error.NativeOwnerWakeDetached, retain(reference));
    notify(worker);
    try std.testing.expectEqual(observed, signal.observe());
    release(reference); release(worker);
    const next = try create(.{ .signal = &signal, .io = std.testing.io });
    defer { detach(next); release(next); }
    try std.testing.expectEqual(reference.slot, next.slot);
    try std.testing.expect(next.generation != reference.generation);
    notify(reference); release(reference);
    try std.testing.expectEqual(observed, signal.observe());
    notify(next);
    try std.testing.expectEqual(observed + 1, signal.observe());
}
