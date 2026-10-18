//! Public Process descriptor entitlement, separate from actual Driver reaping.
//! Only a genuine pidfd may bind; no numeric PID is opened, waited or signaled.
const std = @import("std");
const linux = std.os.linux;
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
const AtomicTicket = @import("native_child_process_spawn_linux.zig").Ticket;
const MaskRecovery = @import("native_child_process_spawn_linux.zig").MaskRecovery;
pub const Ticket = struct { slot: u8, generation: u64 };
const Slot = struct {
    generation: u64 = 0,
    phase: enum { free, reserved, open, uncertain } = .free,
    fd: ?linux.fd_t = null,
    recovery: MaskRecovery = .{},
    recovery_borrowed: bool = false,
};
var gate: Mutex = .{};
var slots: [16]Slot = .{.{}} ** 16;
fn known(ticket: Ticket) !*Slot {
    if (ticket.slot >= slots.len) return error.NativePublicProcessHandleTicket;
    const slot = &slots[ticket.slot];
    if (slot.phase == .free or slot.generation != ticket.generation) return error.NativePublicProcessHandleTicket;
    return slot;
}
pub fn reserve() !Ticket {
    if (@import("builtin").os.tag != .linux) return error.RequiredLinuxChildReadiness;
    gate.lock(); defer gate.unlock();
    for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
        slot.generation += 1; slot.phase = .reserved;
        return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativePublicProcessHandleCapacity;
}
/// Takes the genuine private atomic child ticket, never a guest numeric fd.
/// The ticket keeps exclusive reap authority; this duplicate never calls waitid
/// or sends even a probe signal, and retains no borrowed pointer after return.
pub fn bind(ticket: Ticket, actual: *const AtomicTicket) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(ticket);
    if (slot.phase != .reserved) return error.NativePublicProcessHandleAlreadyBound;
    if (slot.recovery_borrowed or slot.recovery.original != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
    if (!actual.charged or actual.watch.owner != std.Thread.getCurrentId()) return error.NativePublicPidfdRequired;
    if (actual.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
    const pidfd = actual.watch.pidfd orelse return error.NativePublicPidfdRequired;
    const duplicate = linux.fcntl(pidfd, linux.F.DUPFD_CLOEXEC, 3);
    if (linux.errno(duplicate) != .SUCCESS) return error.NativePublicProcessHandleDuplicateFailed;
    slot.fd = @intCast(duplicate); slot.phase = .open;
}
/// Failed clone may leave no child but still own a mandatory exact-thread mask
/// recovery. Move it into this PRE-RESERVED native slot before a host fatal exit;
/// VM holder collection cannot silently drop the sole recovery entitlement.
pub fn holdParentMaskRecovery(ticket: Ticket, recovery: *MaskRecovery) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(ticket);
    if (slot.recovery_borrowed or slot.phase != .reserved or slot.fd != null or slot.recovery.original != null) return error.NativePublicMaskRecoverySlotNotEmpty;
    if (recovery.original == null or recovery.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildParentMaskRecoveryRequired;
    slot.recovery = recovery.*;
    recovery.original = null; recovery.failure = null;
}
pub fn restoreParentMask(ticket: Ticket) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(ticket);
    if (slot.recovery_borrowed) return error.NativePublicMaskRecoveryBorrowed;
    try slot.recovery.restore();
}
pub const RecoveryBorrow = struct {
    ticket: Ticket, recovery: *MaskRecovery,
    pub fn release(self: RecoveryBorrow) !void {
        gate.lock(); defer gate.unlock(); const slot = try known(self.ticket);
        if (!slot.recovery_borrowed or self.recovery != &slot.recovery) return error.NativePublicMaskRecoveryBorrowed;
        slot.recovery_borrowed = false;
    }
};
/// Stable pre-reserved native storage. No stack-local saved mask can disappear
/// on clone failure; close/reuse is forbidden until this native borrow ends.
pub fn borrowParentRecovery(ticket: Ticket) !RecoveryBorrow {
    gate.lock(); defer gate.unlock(); const slot = try known(ticket);
    if (slot.recovery_borrowed or slot.phase != .reserved or slot.recovery.original != null) return error.NativePublicMaskRecoverySlotNotEmpty;
    slot.recovery_borrowed = true; return .{ .ticket = ticket, .recovery = &slot.recovery };
}
/// No waiter borrows this public duplicate. Close it once, preserving the
/// Driver's independent pidfd/reap entitlement. Linux EINTR releases the fd;
/// other close uncertainty retains a bounded charged slot, never retries/reuses.
pub fn close(ticket: Ticket) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(ticket);
    if (slot.recovery_borrowed) return error.NativePublicMaskRecoveryBorrowed;
    try slot.recovery.restore();
    if (slot.phase == .uncertain) return error.NativePublicProcessHandleCloseUncertain;
    if (slot.fd) |fd| {
        slot.phase = .uncertain;
        const result = linux.errno(linux.close(fd));
        if (result != .SUCCESS and result != .INTR) return error.NativePublicProcessHandleCloseUncertain;
        slot.fd = null;
    }
    slot.phase = .free;
}
test "Linux public pidfd record reserves only bounded genuine ownership" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    var tickets: [16]Ticket = undefined; var count: usize = 0;
    defer for (tickets[0..count]) |ticket| close(ticket) catch @panic("owned Linux public handle cleanup failed");
    for (&tickets) |*ticket| { ticket.* = try reserve(); count += 1; }
    try std.testing.expectError(error.NativePublicProcessHandleCapacity, reserve());
    {
        const borrowed = try borrowParentRecovery(tickets[0]);
        defer borrowed.release() catch @panic("owned parent mask recovery borrow cleanup failed");
        try std.testing.expectError(error.NativePublicMaskRecoveryBorrowed, close(tickets[0]));
        try std.testing.expect(borrowed.recovery.original == null);
    }
    const old = tickets[15]; try close(old); count -= 1;
    const current = try reserve(); defer close(current) catch @panic("owned Linux public handle successor cleanup failed");
    try std.testing.expectEqual(old.slot, current.slot);
    try std.testing.expect(old.generation != current.generation);
    try std.testing.expectError(error.NativePublicProcessHandleTicket, close(old));
}
