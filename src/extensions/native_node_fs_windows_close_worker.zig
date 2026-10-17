//! Bounded native-only close worker, intentionally unselected. Instantiate once
//! with the shared native_owner_wake module after its independent review.
//! No worker stores Engine, Task, guest roots, allocator or std.Io backend.
const std = @import("std");
const builtin = @import("builtin");
const crt = @import("native_node_fs_windows_crt_proposal.zig");
const H = std.os.windows.HANDLE;
extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?H;
extern "kernel32" fn SetEvent(H) callconv(.winapi) i32;
extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
pub const Ticket = struct { index: u8, generation: u64 };
pub const Limits = struct { pub const tickets = 64; pub const threads = 2; pub const stack_bytes = 128 * 1024; };
/// Wake contract: Ref is {slot:u8,generation:u64}; retain/notify/release only
/// touch fixed native state. detach clears sinks before Engine/backend release.
/// This injection shares FS wake lifetime; it does not implement a scheduler.
pub fn Pool(comptime Wake: type) type {
    return struct {
        const Phase = enum { free, reserved, queued, running, completed };
        const Slot = struct {
            phase: Phase = .free,
            generation: u64 = 0,
            wake: ?Wake.Ref = null, // one slot-owned reference until exact retirement
            worker_wake: ?Wake.Ref = null, // pre-open entitlement, transferable after detach
            packet: ?crt.ClosePacket = null,
            original_handle: ?H = null,
            detached: bool = false,
            worker_failure: ?anyerror = null,
            qualification_admission: bool = false,
        };
        var gate: std.atomic.Value(bool) = .init(false);
        var slots: [Limits.tickets]Slot = @splat(.{});
        var next_generation: u64 = 0;
        var events: [Limits.threads]?H = @splat(null);
        var started: usize = 0;
        var initialization_failed: bool = false;
        var wait_failure: ?u32 = null;
        var wake_failure: ?u32 = null;
        pub const Snapshot = struct {
            workers_started: usize = 0, reserved: usize = 0, queued: usize = 0,
            running: usize = 0, completed: usize = 0, detached: usize = 0,
            retained_failures: usize = 0, initialization_failed: bool = false,
            wait_failure: ?u32 = null, wake_failure: ?u32 = null,
        };
        fn lock() void { while (gate.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint(); }
        fn unlock() void { gate.store(false, .release); }
        fn get(ticket: Ticket) !*Slot {
            if (ticket.index >= slots.len) return error.NativeCrtCloseTicketMismatch;
            const slot = &slots[ticket.index];
            if (slot.phase == .free or slot.generation != ticket.generation) return error.NativeCrtCloseTicketMismatch;
            return slot;
        }
        pub fn snapshot() Snapshot {
            lock(); defer unlock(); var result: Snapshot = .{ .workers_started = started, .initialization_failed = initialization_failed, .wait_failure = wait_failure, .wake_failure = wake_failure };
            for (&slots) |*slot| {
                switch (slot.phase) { .free => {}, .reserved => result.reserved += 1, .queued => result.queued += 1, .running => result.running += 1, .completed => result.completed += 1 }
                if (slot.detached) result.detached += 1;
                if (slot.worker_failure != null) result.retained_failures += 1;
            }
            return result;
        }
        fn initialize() !void {
            if (builtin.os.tag != .windows) return error.WindowsOnly;
            if (initialization_failed or wait_failure != null or wake_failure != null) return error.NativeCrtCloseWorkersUnavailable;
            if (started == Limits.threads) return;
            // Initialize before any file open. A partial failure leaves only
            // bounded process-lifetime native events/threads and rejects all
            // admission. No replacement thread or unbounded retry is created.
            for (0..Limits.threads) |i| {
                events[i] = CreateEventW(null, 0, 0, null) orelse { initialization_failed = true; return error.NativeCrtCloseEventFailed; };
                const thread = std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, worker, .{i}) catch |err| { initialization_failed = true; return err; };
                started += 1; thread.detach();
            }
        }
        /// Reserve BEFORE opening/associating a descriptor. The native CRT
        /// failed-close reservation must also have been obtained before open.
        pub fn reserve(wake: Wake.Ref) !Ticket {
            if (!crt.selected_after_independent_review) return error.RequiredIndependentWindowsCrtOwnershipReview;
            return reserveOwned(wake, false);
        }
        /// Same fixed slots/workers and wake type, explicit trusted native
        /// target admission only. Never instantiate a second qualification Pool.
        pub fn reserveForQualification(wake: Wake.Ref) !Ticket {
            return reserveOwned(wake, true);
        }
        fn reserveOwned(wake: Wake.Ref, qualification: bool) !Ticket {
            lock(); defer unlock(); try initialize();
            for (&slots, 0..) |*slot, index| if (slot.phase == .free) {
                if (next_generation == std.math.maxInt(u64)) return error.NativeCrtCloseTicketGenerationExhausted;
                const retained = try Wake.retain(wake); errdefer Wake.release(retained);
                // Both entitlements precede open. Controller.stop may detach
                // the sink before shutdown queues this file's actual close;
                // attached-only admission must never be requested at that time.
                const worker_wake = try Wake.retain(wake); next_generation += 1;
                slot.* = .{ .phase = .reserved, .generation = next_generation, .wake = retained, .worker_wake = worker_wake, .qualification_admission = qualification };
                return .{ .index = @intCast(index), .generation = next_generation };
            };
            return error.NativeCrtCloseTicketCapacity;
        }
        /// Only for a never-associated native handle whose rollback is complete.
        pub fn releaseUnassociated(ticket: Ticket) !void {
            lock(); const slot = get(ticket) catch |err| { unlock(); return err; };
            if (slot.phase != .reserved or slot.packet != null) { unlock(); return error.NativeCrtCloseAlreadySubmitted; }
            const wake = slot.wake.?; const worker_wake = slot.worker_wake.?;
            slot.* = .{}; unlock(); Wake.release(worker_wake); Wake.release(wake);
        }
        /// VM-owner only. beginClose freezes IO immediately. A pending IO
        /// acknowledgement returns false; call again only after actual IO retires.
        pub fn submit(ticket: Ticket, lease: *crt.Lease) !bool {
            lock(); defer unlock(); const slot = try get(ticket);
            if (slot.qualification_admission != lease.qualification_admission) return error.NativeCrtCloseQualificationMismatch;
            if (slot.phase != .reserved) return true; // never duplicate a queued close
            std.debug.assert(slot.worker_wake != null);
            switch (try lease.beginClose()) {
                .pending_io => return false,
                .submit => |packet| { slot.packet = packet; slot.original_handle = lease.borrowed_view.handle; slot.phase = .queued; },
                else => return error.NativeCrtCloseTicketLeaseMismatch,
            }
            // The pre-open second reference belongs to the queued worker and
            // survives owner/sink detachment. No new attached-only retain occurs
            // during shutdown. No fallible operation can roll back
            // the packet after this publication: execution may already begin.
            for (events) |event| if (SetEvent(event.?) == 0) { wake_failure = GetLastError(); };
            return true;
        }
        /// Owner publishes actual completion, then releases the ticket. A
        /// worker failure retains the ticket; it cannot imply descriptor closure.
        pub fn poll(ticket: Ticket, lease: *crt.Lease) !?crt.Close {
            lock(); const slot = get(ticket) catch |err| { unlock(); return err; };
            if (slot.detached) { unlock(); return error.NativeCrtCloseOwnerDetached; }
            if (slot.phase != .completed) { unlock(); return null; }
            if (slot.worker_failure) |err| { unlock(); return err; }
            const result = lease.publishClose(&slot.packet.?) catch |err| { unlock(); return err; };
            const wake = slot.wake.?; slot.* = .{}; unlock(); Wake.release(wake); return result;
        }
        /// Called only after outstanding borrowed-file IO has actually retired.
        /// No join/timeout/cancel is an acknowledgement of _close. Once queued,
        /// native fixed storage owns retirement even when the VM stops waiting.
        pub fn detach(ticket: Ticket, lease: *crt.Lease) !void {
            if (!try submit(ticket, lease)) return error.NativeCrtCloseStillHasBorrowedIo;
            lock(); const slot = get(ticket) catch |err| { unlock(); return err; }; slot.detached = true;
            if (slot.phase != .completed or slot.worker_failure != null) { unlock(); return; }
            slot.packet.?.retireDetached(slot.original_handle.?) catch |err| { slot.worker_failure = err; unlock(); return err; };
            const wake = slot.wake.?; slot.* = .{}; unlock(); Wake.release(wake);
        }
        fn worker(index: usize) void {
            while (true) {
                lock(); var selected: ?usize = null;
                for (&slots, 0..) |*slot, i| if (slot.phase == .queued) { slot.phase = .running; selected = i; break; };
                if (selected == null) {
                    const event = events[index].?; unlock();
                    const waited = WaitForSingleObject(event, 0xffffffff);
                    if (waited != 0) { lock(); wait_failure = if (waited == 0xffffffff) GetLastError() else waited; unlock(); return; }
                    continue;
                }
                const slot = &slots[selected.?]; const wake = slot.worker_wake.?;
                const qualification = slot.qualification_admission;
                slot.worker_wake = null; unlock();
                // This entitlement was retained by reserve before file open.
                const failure: ?anyerror = if (if (qualification) slot.packet.?.runForQualification() else slot.packet.?.run()) |_| null else |err| err;
                lock(); slot.worker_failure = failure; slot.phase = .completed;
                if (slot.detached and failure == null) {
                    slot.packet.?.retireDetached(slot.original_handle.?) catch |err| { slot.worker_failure = err; unlock(); Wake.notify(wake); Wake.release(wake); continue; };
                    const slot_wake = slot.wake.?; slot.* = .{}; unlock(); Wake.release(slot_wake);
                } else unlock();
                // run release-published packet.done before this wake. The slot
                // may already be consumed/reused; this captured generation's
                // independent native wake reference prevents stale owner access.
                Wake.notify(wake); Wake.release(wake);
            }
        }
    };
}

test "same qualified close pool observes actual worker acknowledgement and rejects mixed lease admission" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const Wake = @import("native_owner_wake.zig");
    const TestPool = Pool(Wake);
    var signal: @import("native_owner_signal.zig").Signal = .{};
    const reference = try Wake.create(.{ .signal = &signal, .io = std.testing.io });
    defer { Wake.detach(reference); Wake.release(reference); }
    try std.testing.expectError(error.RequiredIndependentWindowsCrtOwnershipReview, TestPool.reserve(reference));
    const reservation = try crt.reserveBeforeOpen();
    var reservation_owned = true; defer if (reservation_owned) crt.releaseReservation(reservation);
    const ticket = try TestPool.reserveForQualification(reference);
    var lease: ?crt.Lease = null;
    var ticket_owned = true;
    defer if (ticket_owned) {
        if (lease) |*actual| TestPool.detach(ticket, actual) catch @panic("owned qualified worker retirement failed")
        else TestPool.releaseUnassociated(ticket) catch @panic("owned worker reservation release failed");
    };
    const file = try std.Io.Dir.cwd().openFile(std.testing.io, "NUL", .{ .mode = .read_write });
    var native: crt.NativeOwned = .{ .file = file, .reservation = reservation };
    defer if (native.file) |owned| owned.close(std.testing.io);
    lease = try crt.associateForQualification(&native, .w); reservation_owned = false;
    // Negative DATA projection of the same actual descriptor, never an owner:
    // submit must reject it BEFORE freezing/changing either native entitlement.
    var wrong_admission = lease.?; wrong_admission.qualification_admission = false;
    try std.testing.expectError(error.NativeCrtCloseQualificationMismatch, TestPool.submit(ticket, &wrong_admission));
    try std.testing.expect(lease.?.phase == .owned);
    try std.testing.expect(try TestPool.submit(ticket, &lease.?));
    const deadline = std.Io.Clock.awake.now(std.testing.io).toMilliseconds() + 1000;
    while (true) {
        const observed = signal.observe();
        if (try TestPool.poll(ticket, &lease.?)) |result| {
            ticket_owned = false;
            try std.testing.expect(result == .closed and lease.?.phase == .closed);
            break;
        }
        const remaining = deadline - std.Io.Clock.awake.now(std.testing.io).toMilliseconds();
        if (remaining <= 0) return error.QualifiedCrtCloseControlDeadline;
        _ = try signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromMilliseconds(@intCast(remaining)), .clock = .awake } });
    }
}
