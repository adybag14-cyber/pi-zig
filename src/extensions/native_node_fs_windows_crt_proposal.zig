//! Isolated, UNSELECTED Windows CRT ownership proposal. Nothing imports this
//! file and both external-call entry points fail closed until explicit review.
//! No C or Engine source changes are part of this proposal.
const std = @import("std");
pub const selected_after_independent_review = false;
const crt = struct {
    extern "c" fn _open_osfhandle(handle: isize, flags: c_int) c_int;
    extern "c" fn _close(fd: c_int) c_int;
};
pub const O_WRONLY: c_int = 0x0001;
pub const O_APPEND: c_int = 0x0008;
pub const O_NOINHERIT: c_int = 0x0080;
pub const O_BINARY: c_int = 0x8000;
pub const OpenKind = enum { w, wx, a, ax };
pub const Mapping = struct { native: std.Io.Dir.CreateFileOptions, association_flags: c_int, append: bool };
pub fn mapping(kind: OpenKind) Mapping {
    const append = kind == .a or kind == .ax;
    return .{ .native = .{ .truncate = !append, .exclusive = kind == .wx or kind == .ax }, .association_flags = O_WRONLY | O_BINARY | O_NOINHERIT | (if (append) O_APPEND else @as(c_int, 0)), .append = append };
}
pub const Reservation = struct { index: usize, generation: u64 };
pub const FailureRecord = struct { fd: c_int, original_handle: std.Io.File.Handle, generation: u64, errno: c_int };
const Slot = union(enum) { free, reserved: u64, closing: struct { generation: u64, fd: c_int, attempt: u64, claimed: bool = false }, failed: FailureRecord };
// Reserve before opening a native handle. Failed close can then retain bounded
// native-only uncertainty without allocating, retaining Engine, or losing it
// during VM teardown. No retry/CloseHandle is authorized by these records.
var registry_gate: std.atomic.Value(bool) = .init(false);
var registry_slots: [64]Slot = @splat(.free);
var registry_generation: u64 = 0;
var registry_close_attempt: u64 = 0;
fn lock() void { while (registry_gate.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint(); }
fn unlock() void { registry_gate.store(false, .release); }
pub fn reserveBeforeOpen() !Reservation {
    lock(); defer unlock();
    for (&registry_slots, 0..) |*slot, index| if (slot.* == .free) {
        if (registry_generation == std.math.maxInt(u64)) return error.NativeCrtGenerationExhausted;
        registry_generation += 1; slot.* = .{ .reserved = registry_generation }; return .{ .index = index, .generation = registry_generation };
    };
    return error.NativeCrtFailedCloseCapacity;
}
pub fn releaseReservation(reservation: Reservation) void {
    lock(); defer unlock(); const slot = &registry_slots[reservation.index]; std.debug.assert((slot.* == .reserved and slot.reserved == reservation.generation) or (slot.* == .closing and slot.closing.generation == reservation.generation and slot.closing.claimed)); slot.* = .free;
}
fn retainFailure(reservation: Reservation, record: FailureRecord) void {
    lock(); defer unlock(); const slot = &registry_slots[reservation.index]; std.debug.assert(slot.* == .closing and slot.closing.generation == reservation.generation and slot.closing.claimed); slot.* = .{ .failed = record };
}
fn reserveClose(reservation: Reservation, fd: c_int) !u64 {
    lock(); defer unlock(); const slot = &registry_slots[reservation.index]; if (slot.* != .reserved or slot.reserved != reservation.generation) return error.NativeCrtCloseGenerationMismatch; if (registry_close_attempt == std.math.maxInt(u64)) return error.NativeCrtGenerationExhausted; registry_close_attempt += 1; slot.* = .{ .closing = .{ .generation = reservation.generation, .fd = fd, .attempt = registry_close_attempt } }; return registry_close_attempt;
}
fn claimClose(reservation: Reservation, fd: c_int, attempt: u64) !void {
    lock(); defer unlock(); const slot = &registry_slots[reservation.index]; if (slot.* != .closing or slot.closing.generation != reservation.generation or slot.closing.fd != fd or slot.closing.attempt != attempt) return error.NativeCrtCloseGenerationMismatch; if (slot.closing.claimed) return error.NativeCrtCloseAlreadyAttempted; slot.closing.claimed = true;
}
fn rollbackClose(reservation: Reservation, attempt: u64) !void {
    lock(); defer unlock(); const slot = &registry_slots[reservation.index]; if (slot.* != .closing or slot.closing.generation != reservation.generation or slot.closing.attempt != attempt or slot.closing.claimed) return error.NativeCrtCloseExecutionUncertain; slot.* = .{ .reserved = reservation.generation };
}
pub const NativeOwned = struct { file: ?std.Io.File, reservation: Reservation, last_association_errno: ?c_int = null };
pub const Phase = enum { owned, closing_wait, closing_submitted, close_failed, closed };
pub const Close = union(enum) { pending_io, submit: ClosePacket, already_submitted, closed, failed: c_int };
const WorkerResult = union(enum) { closed, failed: c_int };
pub const ClosePacket = struct {
    fd: c_int,
    generation: u64,
    reservation: Reservation,
    attempt: u64,
    result: WorkerResult = .closed,
    done: std.atomic.Value(bool) = .init(false),
    // This native packet, not Lease, enters a worker. It has no Engine, File
    // ownership, guest roots or owner-state pointer. Call exactly once.
    pub fn run(self: *ClosePacket) !void {
        if (!selected_after_independent_review) return error.RequiredIndependentWindowsCrtOwnershipReview;
        // Claim in native pre-reserved storage before the external call. Even
        // an accidentally copied packet cannot issue a second close or close a
        // descriptor reused by a later reservation generation.
        try claimClose(self.reservation, self.fd, self.attempt);
        const result = crt._close(self.fd);
        self.result = if (result == 0) .closed else .{ .failed = std.c._errno().* };
        self.done.store(true, .release);
    }
};
pub const Lease = struct {
    fd: c_int,
    // Private borrowed view only. It never owns an independent close after
    // successful _open_osfhandle. Only write/sync operations may use this view.
    borrowed_view: std.Io.File,
    generation: u64,
    reservation: Reservation,
    in_flight: usize = 0,
    phase: Phase = .owned,
    close_errno: ?c_int = null,
    close_attempt: u64 = 0,
    pub fn startIo(self: *Lease, expected_generation: u64) !void {
        if (self.phase != .owned or self.generation != expected_generation) return error.NativeCrtLeaseRetired;
        self.in_flight += 1;
    }
    pub fn retiredIo(self: *Lease, expected_generation: u64) void {
        std.debug.assert(self.generation == expected_generation and self.in_flight > 0);
        self.in_flight -= 1;
    }
    /// VM OWNER ONLY. Admission freezes before worker submission. A worker
    /// never reads/mutates plain Lease fields and cannot race a new startIo.
    pub fn beginClose(self: *Lease) !Close {
        if (!selected_after_independent_review) return error.RequiredIndependentWindowsCrtOwnershipReview;
        if (self.phase == .closed) return .closed;
        if (self.phase == .close_failed) return .{ .failed = self.close_errno.? };
        if (self.phase == .closing_submitted) return .already_submitted;
        if (self.phase == .owned) self.phase = .closing_wait;
        if (self.in_flight != 0) return .pending_io;
        self.close_attempt = try reserveClose(self.reservation, self.fd); self.phase = .closing_submitted;
        return .{ .submit = .{ .fd = self.fd, .generation = self.generation, .reservation = self.reservation, .attempt = self.close_attempt } };
    }
    /// Only the owner applies the result, after acquiring actual completion.
    pub fn publishClose(self: *Lease, packet: *const ClosePacket) !Close {
        if (!packet.done.load(.acquire)) return error.NativeCrtCloseNotCompleted;
        if (self.phase != .closing_submitted or self.in_flight != 0 or packet.fd != self.fd or packet.generation != self.generation or packet.attempt != self.close_attempt or packet.reservation.index != self.reservation.index or packet.reservation.generation != self.reservation.generation) return error.NativeCrtCloseGenerationMismatch;
        switch (packet.result) {
            .closed => { self.phase = .closed; releaseReservation(self.reservation); return .closed; },
            .failed => |errno| {
                retainFailure(self.reservation, .{ .fd = self.fd, .original_handle = self.borrowed_view.handle, .generation = self.generation, .errno = errno });
                self.close_errno = errno; self.phase = .close_failed; return .{ .failed = errno };
            },
        }
    }
    /// A rejected submission is not a kernel close. Roll back only when the
    /// worker was provably never scheduled; never after uncertain execution.
    pub fn rollbackUnsubmittedClose(self: *Lease, packet: *const ClosePacket) !void {
        std.debug.assert(self.phase == .closing_submitted and self.in_flight == 0); if (packet.fd != self.fd or packet.generation != self.generation or packet.attempt != self.close_attempt) return error.NativeCrtCloseGenerationMismatch; try rollbackClose(self.reservation, packet.attempt); self.phase = .closing_wait;
    }
};
pub fn associate(native: *NativeOwned, kind: OpenKind) !Lease {
    if (!selected_after_independent_review) return error.RequiredIndependentWindowsCrtOwnershipReview;
    if (@import("builtin").os.tag != .windows) return error.WindowsOnly;
    const file = native.file orelse return error.NativeFileOwnershipRequired;
    const descriptor = crt._open_osfhandle(@bitCast(@intFromPtr(file.handle)), mapping(kind).association_flags);
    if (descriptor < 0) {
        native.last_association_errno = std.c._errno().*;
        // No transfer occurred: native.file still owns the original handle.
        // The caller's exact rollback closes it once, matching Node24 libuv's
        // failed _open_osfhandle path. It does not call _close(-1).
        return error.NativeCrtAssociationFailed;
    }
    native.file = null;
    return .{ .fd = descriptor, .borrowed_view = file, .generation = native.reservation.generation, .reservation = native.reservation };
}
