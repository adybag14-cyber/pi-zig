//! Public Process handle entitlement, separate from the Driver's native reap
//! entitlement. Closing this real duplicate stops public exit delivery without
//! signaling a child or abandoning the Driver's exact wait/reap ownership.
const std = @import("std");
const w = std.os.windows;
pub const Ticket = struct { slot: u8, generation: u64 };
const Slot = struct {
    generation: u64 = 0,
    phase: enum { free, reserved, open, uncertain } = .free,
    handle: ?w.HANDLE = null,
};
var gate: w.SRWLOCK = .{};
var slots: [16]Slot = .{.{}} ** 16;
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
    extern "kernel32" fn DuplicateHandle(w.HANDLE, w.HANDLE, w.HANDLE, *w.HANDLE, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(w.HANDLE) callconv(.winapi) i32;
};
fn lock() void { api.AcquireSRWLockExclusive(&gate); }
fn unlock() void { api.ReleaseSRWLockExclusive(&gate); }
fn known(ticket: Ticket) !*Slot {
    if (ticket.slot >= slots.len) return error.NativePublicProcessHandleTicket;
    const slot = &slots[ticket.slot];
    if (slot.phase == .free or slot.generation != ticket.generation) return error.NativePublicProcessHandleTicket;
    return slot;
}
/// Reserve before native launch, including all admission failures. No worker or
/// waiter borrows this duplicate; it never appears in a wait array.
pub fn reserve() !Ticket {
    lock(); defer unlock();
    for (&slots, 0..) |*slot, index| if (slot.phase == .free) {
        slot.generation +%= 1; if (slot.generation == 0) slot.generation = 1;
        slot.phase = .reserved; return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativePublicProcessHandleCapacity;
}
pub fn bind(ticket: Ticket, actual: w.HANDLE) !void {
    lock(); defer unlock(); const slot = try known(ticket);
    if (slot.phase != .reserved) return error.NativePublicProcessHandleAlreadyBound;
    const current = api.GetCurrentProcess(); var duplicate: w.HANDLE = undefined;
    if (api.DuplicateHandle(current, actual, current, &duplicate, 0, 0, 2) == 0) return error.NativePublicProcessHandleDuplicateFailed;
    slot.handle = duplicate; slot.phase = .open;
}
/// Reserved records have genuine memory-only close. Open records close their
/// own real duplicate; a failed close quarantines the numeric entitlement and
/// permanently charges its slot. Never retry an uncertain numeric HANDLE.
pub fn close(ticket: Ticket) !void {
    lock(); defer unlock(); const slot = try known(ticket);
    if (slot.phase == .uncertain) return error.NativePublicProcessHandleCloseUncertain;
    if (slot.handle) |handle| {
        slot.phase = .uncertain;
        if (api.CloseHandle(handle) == 0) return error.NativePublicProcessHandleCloseUncertain;
        slot.handle = null;
    }
    slot.phase = .free;
}

test "public native handle admission and exact stale entitlement" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    var tickets: [16]Ticket = undefined; var count: usize = 0;
    defer for (tickets[0..count]) |ticket| close(ticket) catch @panic("owned public handle cleanup failed");
    for (&tickets) |*ticket| { ticket.* = try reserve(); count += 1; }
    try std.testing.expectError(error.NativePublicProcessHandleCapacity, reserve());
    // A real duplicate of this job's process handle; no new process is started
    // and no original/borrowed process identity is closed or signaled.
    try bind(tickets[15], api.GetCurrentProcess());
    const retired = tickets[15]; try close(retired); count -= 1;
    try std.testing.expectError(error.NativePublicProcessHandleTicket, close(retired));
    const successor = try reserve();
    defer close(successor) catch @panic("owned successor handle cleanup failed");
    try std.testing.expectEqual(retired.slot, successor.slot);
    try std.testing.expect(retired.generation != successor.generation);
    try std.testing.expectError(error.NativePublicProcessHandleTicket, bind(retired, api.GetCurrentProcess()));
}
