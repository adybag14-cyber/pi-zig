//! Source-equivalent synchronous native exec decision, with an owned host
//! resource deadline. No VM entry/tick/early public result and no timer polling.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const owner = @import("native_child_process_owned_linux.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
const clock = @import("native_child_process_epoll_linux.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const maximum_budget_ms = 10_000;
pub const Cancellation = struct { slot: u8, generation: u64 };
const Slot = struct {
    generation: u64 = 0, fd: ?linux.fd_t = null,
    phase: enum { free, admitted, failed } = .free,
    waiting: bool = false, cancelled: bool = false,
    references: u32 = 0,
};
var gate: Mutex = .{};
var slots: [16]Slot = @splat(Slot{});
fn known(reference: Cancellation) !*Slot {
    if (reference.slot >= slots.len) return error.NativeLinuxSpawnCancellationStale;
    const slot = &slots[reference.slot];
    if (slot.generation != reference.generation or slot.phase != .admitted) return error.NativeLinuxSpawnCancellationStale;
    return slot;
}
/// Permanent eventfd per bounded slot. It cannot be closed beneath ppoll or
/// reused under an old cancellation generation. No Engine/thread pointer stored.
pub fn reserveCancellation() !Cancellation {
    if (builtin.os.tag != .linux) return error.RequiredLinuxChildReadiness;
    gate.lock(); defer gate.unlock();
    for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
        if (slot.fd == null) {
            const fd = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
            if (linux.errno(fd) != .SUCCESS) { slot.phase = .failed; return error.NativeLinuxSpawnCancellationCreateFailed; }
            slot.fd = @intCast(fd);
        }
        var value: u64 = 0;
        const count = linux.read(slot.fd.?, std.mem.asBytes(&value).ptr, @sizeOf(u64));
        switch (linux.errno(count)) {
            .SUCCESS => if (count != @sizeOf(u64)) { slot.phase = .failed; return error.NativeLinuxSpawnCancellationDrainFailed; },
            .AGAIN => {},
            else => { slot.phase = .failed; return error.NativeLinuxSpawnCancellationDrainFailed; },
        }
        slot.generation += 1; slot.phase = .admitted; slot.cancelled = false; slot.references = 1;
        return .{ .slot = @intCast(index), .generation = slot.generation };
    };
    return error.NativeLinuxSpawnCancellationCapacity;
}
pub fn cancel(reference: Cancellation) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(reference);
    slot.cancelled = true; const one: u64 = 1;
    const count = linux.write(slot.fd.?, std.mem.asBytes(&one).ptr, @sizeOf(u64));
    switch (linux.errno(count)) {
        .SUCCESS => if (count != @sizeOf(u64)) return error.NativeLinuxSpawnCancellationWakeFailed,
        .AGAIN => {},
        else => return error.NativeLinuxSpawnCancellationWakeFailed,
    }
}
pub fn releaseCancellation(reference: Cancellation) !void {
    gate.lock(); defer gate.unlock(); const slot = try known(reference);
    if (slot.waiting) return error.NativeLinuxSpawnCancellationBorrowed;
    std.debug.assert(slot.references != 0);
    slot.references -= 1;
    if (slot.references == 0) { slot.phase = .free; slot.cancelled = false; }
}
pub fn retainCancellation(reference: Cancellation) !Cancellation {
    gate.lock(); defer gate.unlock(); const slot = try known(reference);
    if (slot.references == std.math.maxInt(u32)) return error.NativeLinuxSpawnCancellationReferenceLimit;
    slot.references += 1; return reference;
}
pub fn cancellationRequested(reference: Cancellation) !bool { gate.lock(); defer gate.unlock(); return (try known(reference)).cancelled; }
fn beginWait(reference: Cancellation) !linux.fd_t {
    gate.lock(); defer gate.unlock(); const slot = try known(reference);
    if (slot.waiting) return error.NativeLinuxSpawnCancellationBorrowed;
    slot.waiting = true; return slot.fd.?;
}
fn endWait(reference: Cancellation) void {
    gate.lock(); defer gate.unlock(); const slot = known(reference) catch unreachable;
    std.debug.assert(slot.waiting); slot.waiting = false;
}
fn cancelled(reference: Cancellation) bool { return cancellationRequested(reference) catch true; }
pub const Testing = if (builtin.is_test) struct {
    pub const WaitBorrow = struct {
        reference: Cancellation, fd: linux.fd_t,
        pub fn end(self: @This()) void { endWait(self.reference); }
    };
    pub fn borrowWait(reference: Cancellation) !WaitBorrow { return .{ .reference = reference, .fd = try beginWait(reference) }; }
} else struct {};
pub const Deadline = struct { started_ms: u64, expires_ms: u64 };
/// Called BEFORE clone/pre-exec setup, so one host budget covers admission and
/// the status/reap handshake. Public options.timeout is a separate Source timer.
pub fn startDeadline(budget_ms: u32) !Deadline {
    if (budget_ms == 0 or budget_ms > maximum_budget_ms) return error.NativeLinuxSpawnHandshakeBudget;
    const now = try clock.monotonicMilliseconds();
    return .{ .started_ms = now, .expires_ms = std.math.add(u64, now, budget_ms) catch return error.NativeLinuxSpawnHandshakeBudget };
}
pub const Uncertainty = union(enum) { cancelled, deadline, failure: anyerror };
pub const Decision = union(enum) {
    exec_channel_closed,
    // The genuine child setup/exec errno record AND actual pidfd reap observed.
    exec_failed_reaped: spawn.Failure,
    // Caller STILL owns actual ticket/endpoints and any known failure record.
    uncertain: struct { reason: Uncertainty, known_failure: ?spawn.Failure = null },
};
fn uncertain(reason: Uncertainty, failure: ?spawn.Failure) Decision { return .{ .uncertain = .{ .reason = reason, .known_failure = failure } }; }
/// Caller has withdrawn all external borrowed arms. Sole owner thread may block
/// only in ppoll on actual readiness/cancel, never run guest callbacks/jobs. All
/// returns preserve caller ownership; uncertain is not a Node errno/result.
pub fn awaitDecision(actual: *owner.Owned, deadline: Deadline, cancellation: Cancellation) Decision {
    var failure: ?spawn.Failure = null;
    if (deadline.expires_ms <= deadline.started_ms or deadline.expires_ms - deadline.started_ms > maximum_budget_ms) return uncertain(.{ .failure = error.NativeLinuxSpawnHandshakeBudget }, null);
    if (actual.detached or !actual.ticket.charged or actual.ticket.watch.owner != std.Thread.getCurrentId() or actual.ticket.watch.epoll != null) return uncertain(.{ .failure = error.NativeLinuxChildTicketOwnerThreadRequired }, null);
    if (actual.ticket.parent_mask_restore_errno != null) return uncertain(.{ .failure = error.NativeLinuxChildParentMaskRecoveryRequired }, null);
    const cancel_fd = beginWait(cancellation) catch |err| return uncertain(.{ .failure = err }, null);
    defer endWait(cancellation);
    while (true) {
        if (cancelled(cancellation)) return uncertain(.cancelled, failure);
        const now = clock.monotonicMilliseconds() catch |err| return uncertain(.{ .failure = err }, failure);
        if (now >= deadline.expires_ms) return uncertain(.deadline, failure);
        if (failure == null) {
            const status = actual.takeLaunchAfterWithdraw() catch |err| return uncertain(.{ .failure = err }, null);
            switch (status) { .pending => {}, .channel_closed => return .exec_channel_closed, .failed => |value| failure = value }
        }
        if (failure) |value| {
            if (actual.observeExitAfterWithdraw() catch |err| return uncertain(.{ .failure = err }, failure)) |_| return .{ .exec_failed_reaped = value };
        }
        const target = if (failure != null) actual.ticket.watch.pidfd else actual.ticket.exec_status_fd;
        const fd = target orelse return uncertain(.{ .failure = error.NativeLinuxSpawnHandshakeDescriptorMissing }, failure);
        var descriptors = [_]linux.pollfd{ .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }, .{ .fd = cancel_fd, .events = linux.POLL.IN, .revents = 0 } };
        const wait_now = clock.monotonicMilliseconds() catch |err| return uncertain(.{ .failure = err }, failure);
        if (wait_now < deadline.started_ms) return uncertain(.{ .failure = error.NativeLinuxSpawnHandshakeClockRegressed }, failure);
        if (wait_now >= deadline.expires_ms) return uncertain(.deadline, failure);
        const remaining = deadline.expires_ms - wait_now;
        var timeout: linux.timespec = .{ .sec = @intCast(remaining / 1000), .nsec = @intCast((remaining % 1000) * 1_000_000) };
        const count = linux.ppoll(&descriptors, descriptors.len, &timeout, null);
        switch (linux.errno(count)) { .SUCCESS => {}, .INTR => continue, else => return uncertain(.{ .failure = error.NativeLinuxSpawnHandshakeWaitFailed }, failure) }
        for (descriptors) |descriptor| if (descriptor.revents & linux.POLL.NVAL != 0) return uncertain(.{ .failure = error.NativeLinuxSpawnHandshakeInvalidDescriptor }, failure);
        // Readiness, EINTR and timeout all return through real status/cancel/
        // monotonic checks. No interval tick, sleep or fabricated EOF is used.
    }
}

test "Linux spawn cancellation caps, borrowed wait lifetime and stale generations" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var references: [16]Cancellation = undefined; var count: usize = 0;
    defer for (references[0..count]) |reference| releaseCancellation(reference) catch @panic("owned spawn cancellation cleanup failed");
    for (&references) |*reference| { reference.* = try reserveCancellation(); count += 1; }
    try std.testing.expectError(error.NativeLinuxSpawnCancellationCapacity, reserveCancellation());
    {
        const reference = references[15]; const fd = try beginWait(reference);
        defer endWait(reference);
        try std.testing.expectError(error.NativeLinuxSpawnCancellationBorrowed, releaseCancellation(reference));
        try cancel(reference); try std.testing.expect(cancelled(reference));
        var descriptors = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
        var zero: linux.timespec = .{ .sec = 0, .nsec = 0 };
        const ready = linux.ppoll(&descriptors, descriptors.len, &zero, null);
        try std.testing.expectEqual(linux.E.SUCCESS, linux.errno(ready));
        try std.testing.expectEqual(@as(usize, 1), ready);
        try std.testing.expect(descriptors[0].revents & linux.POLL.IN != 0);
    }
    const old = references[15]; try releaseCancellation(old); count -= 1;
    const current = try reserveCancellation(); defer releaseCancellation(current) catch @panic("owned spawn cancellation successor cleanup failed");
    try std.testing.expectEqual(old.slot, current.slot);
    try std.testing.expect(old.generation != current.generation);
    try std.testing.expect(!cancelled(current));
    try std.testing.expectError(error.NativeLinuxSpawnCancellationStale, cancel(old));
}
