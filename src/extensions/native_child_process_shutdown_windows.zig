//! Actual named-pipe peer-consumption shutdown, separate from write/close acks.
//! Fixed native-only tickets/workers. No Engine, JS, Task, allocator or Io backend
//! pointer reaches a worker. Selection/integration awaits independent review.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
const H = w.HANDLE;
const wake = @import("native_owner_wake.zig");
const waits = @import("native_child_process_wait_registry.zig");
const input = @import("native_child_process_stdin_windows.zig");
pub const Ticket = struct { index: u8, generation: u64 };
pub const Limits = struct { pub const tickets = 16; pub const flush_threads = 2; pub const cancel_threads = 1; pub const stack_bytes = 128 * 1024; };
pub const Outcome = union(enum) { flushed, failed: u32, cancelled_before_call };
pub const Completion = struct { outcome: Outcome, cancellation_requested: bool, cancellation_error: ?u32, was_quarantined: bool };
pub const Pending = struct { event: H, generation: u64 };
const Phase = enum { free, reserved, associated, queued, running, completed };
const Slot = struct {
    phase: Phase = .free, generation: u64 = 0,
    event: ?H = null, pipe: ?H = null,
    endpoint_generation: u64 = 0, original_handle: ?H = null,
    lease: waits.Lease = .{ .slot = 0, .generation = 0 },
    references: [3]?wake.Ref = .{ null, null, null },
    worker: ?u8 = null, thread_arm: u64 = 0,
    flush_returned: bool = false, outcome: Outcome = .cancelled_before_call,
    cancel_requested: bool = false, cancel_started: bool = false, cancel_done: bool = false,
    cancel_at: ?u64 = null, cancel_error: ?u32 = null,
    quarantined: bool = false, detached: bool = false, close_error: ?u32 = null,
};
const Worker = struct { thread: ?H = null, event: ?H = null, current: ?Ticket = null, arm: u64 = 0 };
const Release = [3]?wake.Ref;
var gate: w.SRWLOCK = .{};
var slots: [Limits.tickets]Slot = @splat(Slot{});
var workers: [Limits.flush_threads]Worker = @splat(Worker{});
var cancel_event: ?H = null;
var initialized: bool = false;
var failure: ?u32 = null;
fn lock() void { api.AcquireSRWLockExclusive(&gate); }
fn unlock() void { api.ReleaseSRWLockExclusive(&gate); }
fn lastError() u32 { return @intFromEnum(w.GetLastError()); }
fn valid(ticket: Ticket) !*Slot {
    if (ticket.index >= slots.len) return error.NativePipeShutdownTicketMismatch;
    const slot = &slots[ticket.index];
    if (slot.phase == .free or slot.generation != ticket.generation) return error.NativePipeShutdownTicketMismatch;
    return slot;
}
fn same(a: Ticket, b: Ticket) bool { return a.index == b.index and a.generation == b.generation; }
fn signal(event: H) void { if (api.SetEvent(event) == 0 and failure == null) failure = lastError(); }
fn releaseReferences(references: Release) void { for (references) |reference| if (reference) |value| wake.release(value); }
fn initialize() !void {
    if (builtin.os.tag != .windows) return error.RequiredWindowsPipeShutdown;
    if (failure != null) return error.NativePipeShutdownWorkersUnavailable;
    if (initialized) return;
    // All events and duplicated control handles are bounded process-lifetime
    // state. Partial initialization is terminal admission failure, never retried.
    errdefer if (failure == null) { failure = 1; };
    for (&slots) |*slot| slot.event = api.CreateEventW(null, 1, 0, null) orelse return error.NativePipeShutdownEventFailed;
    for (&workers) |*worker| worker.event = api.CreateEventW(null, 0, 0, null) orelse return error.NativePipeShutdownEventFailed;
    cancel_event = api.CreateEventW(null, 0, 0, null) orelse return error.NativePipeShutdownEventFailed;
    for (&workers, 0..) |*worker, index| {
        const thread = try std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, flushWorker, .{index});
        var control: H = undefined;
        const current = api.GetCurrentProcess();
        const duplicated = api.DuplicateHandle(current, thread.getHandle(), current, &control, 0x0001, 0, 0) != 0; // THREAD_TERMINATE, only for CancelSynchronousIo
        thread.detach();
        if (!duplicated) return error.NativePipeShutdownThreadControlFailed;
        worker.thread = control;
    }
    const canceller = try std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, cancelWorker, .{});
    canceller.detach(); initialized = true;
}
/// Reserve all three native wake entitlements BEFORE pipe creation/admission.
/// Late detach never requires attached-only retain from a retiring Engine.
pub fn reserve(reference: wake.Ref, lease: waits.Lease) !Ticket {
    lock(); defer unlock(); try initialize();
    for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
        var references: Release = .{ null, null, null };
        errdefer releaseReferences(references);
        for (&references) |*item| item.* = try wake.retain(reference);
        if (api.ResetEvent(slot.event.?) == 0) return error.NativePipeShutdownEventFailed;
        const event = slot.event; const generation = slot.generation + 1;
        slot.* = .{ .phase = .reserved, .generation = generation, .event = event, .references = references, .lease = lease };
        return .{ .index = @intCast(index), .generation = generation };
    };
    return error.NativePipeShutdownTicketCapacity;
}
/// Associate the actual secured server slot; no worker borrows this pointer.
/// A duplicate pins the same pipe instance even if Engine shutdown retires the
/// original write slot. Only the duplicate is owned/closed by this pool.
pub fn associate(ticket: Ticket, endpoint: *input.Slot) !void {
    lock(); defer unlock(); const slot = try valid(ticket);
    if (slot.phase != .reserved or endpoint.endpoint == null or endpoint.generation == 0) return error.NativePipeShutdownAssociationMismatch;
    var flags: u32 = 0;
    if (api.GetNamedPipeInfo(endpoint.endpoint.?, &flags, null, null, null) == 0 or flags & 1 == 0) return error.NativePipeShutdownServerEndpointRequired;
    var duplicate: H = undefined; const current = api.GetCurrentProcess();
    if (api.DuplicateHandle(current, endpoint.endpoint.?, current, &duplicate, 0, 0, 2) == 0) return error.NativePipeShutdownDuplicateFailed;
    slot.pipe = duplicate; slot.original_handle = endpoint.endpoint; slot.endpoint_generation = endpoint.generation; slot.phase = .associated;
}
/// Caller has stopped write admission and consumed every real write ack. Never
/// start FlushFileBuffers while its actual overlapped WriteFile is pending.
pub fn submitAfterWrites(ticket: Ticket, endpoint: *input.Slot) !void {
    lock(); defer unlock(); const slot = try valid(ticket);
    if (slot.phase != .associated or slot.original_handle != endpoint.endpoint or slot.endpoint_generation != endpoint.generation or endpoint.pending) return error.NativePipeShutdownWritesStillOwned;
    slot.phase = .queued;
    for (workers) |worker| signal(worker.event.?);
}
pub fn pending(ticket: Ticket) !?Pending {
    lock(); defer unlock(); const slot = try valid(ticket);
    return switch (slot.phase) { .queued, .running => .{ .event = slot.event.?, .generation = slot.generation }, else => null };
}
/// Pure publication to the native cancellation worker. Owner never calls the
/// possibly blocking disconnect/flush, waits for a worker, or destroys its handle.
pub fn cancel(ticket: Ticket) !void {
    lock(); defer unlock(); const slot = try valid(ticket);
    if (slot.phase == .completed) return;
    if (slot.phase == .reserved) return error.NativePipeShutdownNotAssociated;
    if (!slot.cancel_requested) { slot.cancel_requested = true; slot.cancel_at = api.GetTickCount64(); }
    if (slot.phase == .associated) slot.phase = .queued;
    signal(cancel_event.?); for (workers) |worker| signal(worker.event.?);
}
/// Actual retirement deadline is diagnostic/quarantine only. It is never a
/// successful flush, endpoint absence, or permission to free worker storage.
pub fn markQuarantined(ticket: Ticket) !void {
    lock(); defer unlock(); const slot = try valid(ticket);
    const started = slot.cancel_at orelse return error.NativePipeShutdownCancellationRequired;
    if (slot.phase != .completed and api.GetTickCount64() -| started >= 250) slot.quarantined = true;
}
pub fn poll(ticket: Ticket) !?Completion {
    lock(); defer unlock(); const slot = try valid(ticket);
    if (slot.detached) return error.NativePipeShutdownOwnerDetached;
    if (slot.close_error != null) return error.NativePipeShutdownCloseRetained;
    if (slot.phase != .completed and failure != null) return error.NativePipeShutdownWorkersUnavailable;
    if (slot.phase != .completed) return null;
    return .{ .outcome = slot.outcome, .cancellation_requested = slot.cancel_requested, .cancellation_error = slot.cancel_error, .was_quarantined = slot.quarantined };
}
fn freeLocked(slot: *Slot) !Release {
    // A failed close is retained uncertainty. A later detach/release must never
    // retry that numeric handle after it may have been recycled by the kernel.
    if (slot.close_error != null) return error.NativePipeShutdownCloseRetained;
    if (slot.pipe) |handle| {
        if (api.CloseHandle(handle) == 0) { slot.close_error = lastError(); return error.NativePipeShutdownCloseRetained; }
        slot.pipe = null;
    }
    const references = slot.references; const event = slot.event; const generation = slot.generation;
    slot.* = .{ .event = event, .generation = generation }; return references;
}
pub fn releaseUnassociated(ticket: Ticket) !void {
    lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
    if (slot.phase != .reserved) { unlock(); return error.NativePipeShutdownAlreadyAssociated; }
    const references = freeLocked(slot) catch |err| { unlock(); return err; }; unlock(); releaseReferences(references);
}
/// Owner must withdraw/ack every borrowed pending-event snapshot before release.
/// Actual completion proves both the flush call and cancellation worker retired.
pub fn releaseCompletedAfterWithdraw(ticket: Ticket) !void {
    lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
    if (slot.phase != .completed) { unlock(); return error.NativePipeShutdownCompletionRequired; }
    const references = freeLocked(slot) catch |err| { unlock(); return err; }; unlock(); releaseReferences(references);
}
pub fn detach(ticket: Ticket) !void {
    lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
    slot.detached = true;
    if (slot.phase == .reserved or slot.phase == .completed) {
        const references = freeLocked(slot) catch |err| { unlock(); return err; }; unlock(); releaseReferences(references); return;
    }
    if (!slot.cancel_requested) { slot.cancel_requested = true; slot.cancel_at = api.GetTickCount64(); }
    if (slot.phase == .associated) slot.phase = .queued;
    signal(cancel_event.?); for (workers) |worker| signal(worker.event.?); unlock();
}
fn completeLocked(slot: *Slot) Release {
    if (!slot.flush_returned or (slot.cancel_requested and !slot.cancel_done)) return .{ null, null, null };
    slot.phase = .completed;
    if (slot.worker) |index| {
        workers[index].current = null; signal(workers[index].event.?);
    }
    signal(slot.event.?);
    if (slot.detached) return freeLocked(slot) catch .{ null, null, null };
    return .{ null, null, null };
}
fn notify(reference: wake.Ref, lease: waits.Lease) void {
    // Real completion/progress also queues the native child ready mask. An OS
    // event publication failure must not silently strand an attached owner.
    waits.requestStep(lease); wake.notify(reference); wake.release(reference);
}
fn flushWorker(index: usize) void {
    while (true) {
        lock();
        if (failure != null) { unlock(); return; }
        var selected: ?usize = null;
        if (workers[index].current == null) for (&slots, 0..) |*slot, i| if (slot.phase == .queued) {
            if (workers[index].arm == std.math.maxInt(u64)) { failure = 1; break; }
            workers[index].arm += 1; slot.thread_arm = workers[index].arm;
            slot.worker = @intCast(index); slot.phase = .running;
            workers[index].current = .{ .index = @intCast(i), .generation = slot.generation }; selected = i; break;
        };
        if (selected == null) {
            const event = workers[index].event.?; unlock();
            if (api.WaitForSingleObject(event, 0xffffffff) != 0) { lock(); failure = lastError(); unlock(); return; }
            continue;
        }
        const slot = &slots[selected.?]; const pipe = slot.pipe.?; const cancelled = slot.cancel_requested;
        const reference = slot.references[1].?; slot.references[1] = null; const lease = slot.lease;
        unlock();
        const outcome: Outcome = if (cancelled) .cancelled_before_call else if (api.FlushFileBuffers(pipe) != 0) .flushed else .{ .failed = lastError() };
        lock(); slot.outcome = outcome; slot.flush_returned = true;
        const releases = completeLocked(slot); unlock(); releaseReferences(releases); notify(reference, lease);
    }
}
fn cancelWorker() void {
    while (true) {
        lock();
        if (failure != null) { unlock(); return; }
        var selected: ?usize = null;
        for (&slots, 0..) |*slot, index| if (slot.cancel_requested and !slot.cancel_started and slot.phase != .completed and slot.phase != .free) { slot.cancel_started = true; selected = index; break; };
        if (selected == null) {
            const event = cancel_event.?; unlock();
            if (api.WaitForSingleObject(event, 0xffffffff) != 0) { lock(); failure = lastError(); unlock(); return; }
            continue;
        }
        const slot = &slots[selected.?]; const pipe = slot.pipe.?;
        const reference = slot.references[2].?; slot.references[2] = null; const lease = slot.lease;
        // The worker cannot advance to another ticket until cancel_done. Hold
        // this guard across CancelSynchronousIo so it cannot target its next job.
        if (slot.worker) |index| if (!slot.flush_returned) {
            const current = workers[index].current;
            if (current != null and same(current.?, .{ .index = @intCast(selected.?), .generation = slot.generation }) and workers[index].arm == slot.thread_arm) {
                if (api.CancelSynchronousIo(workers[index].thread.?) == 0) {
                    const code = lastError(); if (code != 1168) slot.cancel_error = code; // NOT_FOUND is not completion
                }
            }
        };
        unlock();
        // Sticky cancellation on this UNIQUE server instance closes the gap
        // where CancelSynchronousIo found no request just before Flush entered.
        // Only explicit cancel/detach reaches here; normal finish never discards.
        const disconnected = api.DisconnectNamedPipe(pipe) != 0;
        const disconnect_error = if (disconnected) @as(u32, 0) else lastError();
        lock();
        if (!disconnected and disconnect_error != 233 and disconnect_error != 109 and slot.cancel_error == null) slot.cancel_error = disconnect_error;
        slot.cancel_done = true;
        const releases = completeLocked(slot); unlock(); releaseReferences(releases); notify(reference, lease);
    }
}
pub const Snapshot = struct { reserved: usize = 0, active: usize = 0, completed: usize = 0, quarantined: usize = 0, detached: usize = 0, retained_close_failures: usize = 0, cancellation_failures: usize = 0, worker_failure: ?u32 = null };
pub fn snapshot() Snapshot {
    lock(); defer unlock(); var result: Snapshot = .{ .worker_failure = failure };
    for (slots) |slot| if (slot.phase != .free) {
        result.reserved += 1; if (slot.phase == .queued or slot.phase == .running) result.active += 1;
        if (slot.phase == .completed) result.completed += 1;
        result.quarantined += @intFromBool(slot.quarantined and slot.phase != .completed); result.detached += @intFromBool(slot.detached); result.retained_close_failures += @intFromBool(slot.close_error != null);
        result.cancellation_failures += @intFromBool(slot.cancel_error != null);
    };
    return result;
}
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateEventW(?*w.SECURITY_ATTRIBUTES, i32, i32, ?[*:0]const u16) callconv(.winapi) ?H;
    extern "kernel32" fn SetEvent(H) callconv(.winapi) i32;
    extern "kernel32" fn ResetEvent(H) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetNamedPipeInfo(H, ?*u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn FlushFileBuffers(H) callconv(.winapi) i32;
    extern "kernel32" fn CancelSynchronousIo(H) callconv(.winapi) i32;
    extern "kernel32" fn DisconnectNamedPipe(H) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(H) callconv(.winapi) i32;
};
