//! Bounded native console reads. No Engine, JS, Task, Io backend or GPA pointer
//! enters a worker. Actual owner/wake lifetimes are injected canonical modules.
//! Source-only/unselected; normal-line ReadConsoleW and real raw input records.
const std = @import("std");
const w = std.os.windows;
const H = w.HANDLE;
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?H;
    extern "kernel32" fn SetEvent(H) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
    extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn ReadConsoleW(H, [*]u16, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
    extern "kernel32" fn ReadConsoleInputW(H, *InputRecord, u32, *u32) callconv(.winapi) i32;
    extern "kernel32" fn CancelSynchronousIo(H) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
};
pub const KeyEvent = extern struct { down: i32, repeats: u16, virtual_key: u16, scan_code: u16, character: u16, modifiers: u32 };
pub const InputRecord = extern struct { kind: u16, payload: extern union { key: KeyEvent, storage: [4]u32 } };
const ReadTicket = struct { slot: u8, generation: u64 };
pub const Ticket = ReadTicket;
pub const Limits = struct { pub const tickets = 16; pub const read_threads = 2; pub const cancel_threads = 1; pub const stack_bytes = 128 * 1024; pub const line_units = 8192 / 3; };
pub const Mode = enum { line, raw_records };
pub const Outcome = union(enum) { cancelled_before_call, failed: u32, line: u32, record: u32 };
pub const Completion = struct { outcome: Outcome, cancellation_requested: bool, cancellation_error: ?u32, quarantined: bool };
/// Lifetime is the actual native console-lease registry: Ref is a bounded
/// slot/generation; retain/release never reach the VM. beginReadIo returns a
/// genuine owned console HANDLE; retireReadIo releases its exact in-flight use.
/// Wake is the one canonical native_owner_wake facade, not a new scheduler.
pub fn Pool(comptime Wake: type, comptime Lifetime: type) type {
    return struct {
        pub const Ticket = ReadTicket;
        const Phase = enum { free, reserved, queued, running, returned, completed };
        const Slot = struct {
            phase: Phase = .free, generation: u64 = 0,
            owner: ?Lifetime.Ref = null, io_admitted: bool = false,
            handle: ?H = null, mode: Mode = .line,
            units: [Limits.line_units]u16 = undefined, record: InputRecord = undefined,
            outcome: Outcome = .cancelled_before_call,
            references: [3]?Wake.Ref = .{ null, null, null },
            worker: ?u8 = null, arm: u64 = 0,
            cancel_requested: bool = false, cancel_started_ms: ?u64 = null,
            cancel_error: ?u32 = null, cancel_call_active: bool = false,
            quarantined: bool = false, detached: bool = false,
        };
        const Worker = struct { event: ?H = null, thread: ?H = null, current: ?ReadTicket = null, arm: u64 = 0 };
        var gate: w.SRWLOCK = .{};
        var slots: [Limits.tickets]Slot = .{Slot{}} ** Limits.tickets;
        var workers: [Limits.read_threads]Worker = .{Worker{}} ** Limits.read_threads;
        var cancel_event: ?H = null;
        var initialized: bool = false;
        var initialization_failed: bool = false;
        var native_failure: ?u32 = null;
        fn lock() void { api.AcquireSRWLockExclusive(&gate); }
        fn unlock() void { api.ReleaseSRWLockExclusive(&gate); }
        fn valid(ticket: ReadTicket) !*Slot {
            if (ticket.slot >= slots.len) return error.NativeTtyReadTicketMismatch;
            const slot = &slots[ticket.slot];
            if (slot.phase == .free or slot.generation != ticket.generation) return error.NativeTtyReadTicketMismatch;
            return slot;
        }
        fn same(a: ReadTicket, b: ReadTicket) bool { return a.slot == b.slot and a.generation == b.generation; }
        fn signal(event: H) void { if (api.SetEvent(event) == 0 and native_failure == null) native_failure = api.GetLastError(); }
        fn releaseReferences(references: [3]?Wake.Ref) void { for (references) |reference| if (reference) |value| Wake.release(value); }
        fn initialize() !void {
            if (initialization_failed or native_failure != null) return error.NativeTtyReadWorkersUnavailable;
            if (initialized) return;
            errdefer initialization_failed = true;
            for (&workers) |*worker| worker.event = api.CreateEventW(null, 0, 0, null) orelse return error.NativeTtyReadEventFailed;
            cancel_event = api.CreateEventW(null, 0, 0, null) orelse return error.NativeTtyReadEventFailed;
            for (&workers, 0..) |*worker, index| {
                const thread = try std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, readWorker, .{index});
                var control: H = undefined;
                const current = api.GetCurrentProcess();
                const duplicated = api.DuplicateHandle(current, thread.getHandle(), current, &control, 1, 0, 0) != 0;
                thread.detach();
                if (!duplicated) return error.NativeTtyReadThreadControlFailed;
                worker.thread = control;
            }
            const canceller = try std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, cancelWorker, .{});
            canceller.detach(); initialized = true;
        }
        pub fn reserve(reference: Wake.Ref, owner: Lifetime.Ref) !ReadTicket {
            lock(); defer unlock(); try initialize();
            for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
                var references: [3]?Wake.Ref = .{ null, null, null };
                errdefer releaseReferences(references);
                for (&references) |*item| item.* = try Wake.retain(reference);
                const native_owner = try Lifetime.retain(owner);
                const generation = slot.generation + 1;
                slot.* = .{ .phase = .reserved, .generation = generation, .references = references, .owner = native_owner };
                return .{ .slot = @intCast(index), .generation = generation };
            };
            return error.NativeTtyReadTicketCapacity;
        }
        pub fn submit(ticket: ReadTicket, mode: Mode) !void {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase != .reserved) return error.NativeTtyReadAlreadySubmitted;
            slot.handle = try Lifetime.beginReadIo(slot.owner.?);
            slot.io_admitted = true; slot.mode = mode; slot.phase = .queued;
            for (workers) |worker| signal(worker.event.?);
        }
        pub fn requestCancel(ticket: ReadTicket) !void {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase == .completed) return;
            if (!slot.cancel_requested) { slot.cancel_requested = true; slot.cancel_started_ms = api.GetTickCount64(); }
            if (slot.phase == .reserved or slot.phase == .queued) slot.phase = .returned;
            signal(cancel_event.?);
            for (workers) |worker| signal(worker.event.?);
        }
        /// Immediate native cancellation-request result for synchronous mode
        /// changes. This is never a completion/retirement acknowledgement.
        /// CancelSynchronousIo returns immediately; a successful request or
        /// NOT_FOUND gap still leaves the recurring exact-arm canceller active.
        pub fn cancelNow(ticket: ReadTicket) !?u32 {
            try requestCancel(ticket);
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            if (slot.phase != .running or slot.cancel_call_active) { unlock(); return null; }
            const worker = slot.worker.?;
            if (workers[worker].current == null or !same(workers[worker].current.?, ticket) or workers[worker].arm != slot.arm) { unlock(); return error.NativeTtyReadArmMismatch; }
            slot.cancel_call_active = true;
            const thread = workers[worker].thread.?;
            unlock();
            const cancelled = api.CancelSynchronousIo(thread) != 0;
            const failure = if (cancelled) @as(u32, 0) else api.GetLastError();
            lock(); slot.cancel_call_active = false;
            if (!cancelled and failure != 1168 and slot.cancel_error == null) slot.cancel_error = failure;
            signal(cancel_event.?); unlock();
            return if (cancelled or failure == 1168) null else failure;
        }
        pub fn poll(ticket: ReadTicket) !?Completion {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.detached) return error.NativeTtyReadOwnerDetached;
            if (slot.phase != .completed) {
                if (native_failure != null) return error.NativeTtyReadWorkersUnavailable;
                return null;
            }
            return .{ .outcome = slot.outcome, .cancellation_requested = slot.cancel_requested, .cancellation_error = slot.cancel_error, .quarantined = slot.quarantined };
        }
        /// Copy before release; storage belongs to this generation until then.
        pub fn lineUnits(ticket: ReadTicket) ![]const u16 {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase != .completed or slot.detached) return error.NativeTtyReadCompletionRequired;
            return switch (slot.outcome) { .line => |count| slot.units[0..count], else => error.NativeTtyReadNotLine };
        }
        pub fn inputRecord(ticket: ReadTicket) !InputRecord {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase != .completed or slot.detached) return error.NativeTtyReadCompletionRequired;
            return switch (slot.outcome) { .record => |count| if (count == 1) slot.record else error.NativeTtyReadNoRecord, else => error.NativeTtyReadNotRecord };
        }
        const Retired = struct { owner: Lifetime.Ref, io_admitted: bool, references: [3]?Wake.Ref };
        fn freeLocked(slot: *Slot) Retired {
            const value: Retired = .{ .owner = slot.owner.?, .io_admitted = slot.io_admitted, .references = slot.references };
            const generation = slot.generation; slot.* = .{ .generation = generation }; return value;
        }
        fn retireNative(value: Retired) void {
            if (value.io_admitted) Lifetime.retireReadIo(value.owner);
            Lifetime.release(value.owner); releaseReferences(value.references);
        }
        pub fn releaseCompleted(ticket: ReadTicket) !void {
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            if (slot.phase != .completed) { unlock(); return error.NativeTtyReadCompletionRequired; }
            const retired = freeLocked(slot); unlock(); retireNative(retired);
        }
        pub fn releaseUnsubmitted(ticket: ReadTicket) !void {
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            if (slot.phase != .reserved) { unlock(); return error.NativeTtyReadAlreadySubmitted; }
            const retired = freeLocked(slot); unlock(); retireNative(retired);
        }
        /// No VM root/Engine reference is retained. Native ownership remains
        /// until the actual syscall and exact canceller arm both retire.
        pub fn detach(ticket: ReadTicket) !void {
            try requestCancel(ticket);
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            slot.detached = true;
            if (slot.phase == .completed) { const retired = freeLocked(slot); unlock(); retireNative(retired); return; }
            unlock();
        }
        fn readWorker(index: usize) void {
            while (true) {
                lock();
                if (native_failure != null) { unlock(); return; }
                var selected: ?usize = null;
                for (&slots, 0..) |*slot, i| if (slot.phase == .queued) { selected = i; break; };
                if (selected == null) {
                    const event = workers[index].event.?; unlock();
                    const waited = api.WaitForSingleObject(event, 0xffffffff);
                    if (waited != 0) { lock(); native_failure = if (waited == 0xffffffff) api.GetLastError() else waited; unlock(); return; }
                    continue;
                }
                const slot = &slots[selected.?];
                const ticket: ReadTicket = .{ .slot = @intCast(selected.?), .generation = slot.generation };
                if (workers[index].arm == std.math.maxInt(u64)) { native_failure = 534; unlock(); return; }
                workers[index].arm += 1; workers[index].current = ticket;
                slot.worker = @intCast(index); slot.arm = workers[index].arm; slot.phase = .running;
                const cancelled = slot.cancel_requested;
                const handle = slot.handle.?; const mode = slot.mode;
                unlock();
                var count: u32 = 0;
                const outcome: Outcome = if (cancelled) .cancelled_before_call else if (mode == .line) line: {
                    if (api.ReadConsoleW(handle, &slot.units, slot.units.len, &count, null) == 0) break :line .{ .failed = api.GetLastError() };
                    break :line .{ .line = count };
                } else raw: {
                    if (api.ReadConsoleInputW(handle, &slot.record, 1, &count) == 0) break :raw .{ .failed = api.GetLastError() };
                    break :raw .{ .record = count };
                };
                lock(); slot.outcome = outcome; slot.phase = .returned;
                // A cancellation call still targeting this arm fences worker
                // reuse. Its return must be observed before completion/reuse.
                if (!slot.cancel_call_active) {
                    workers[index].current = null; slot.worker = null; slot.phase = .completed;
                    const reference = slot.references[1].?; slot.references[1] = null;
                    const retired = if (slot.detached) freeLocked(slot) else null;
                    unlock(); Wake.notify(reference); Wake.release(reference);
                    if (retired) |value| retireNative(value);
                } else {
                    signal(cancel_event.?); unlock();
                    // Native canceller will release this worker arm. Do not
                    // take another ticket while an old Cancel call can hit it.
                    while (true) {
                        lock(); const still_owned = workers[index].current != null; unlock();
                        if (!still_owned) break;
                        _ = api.WaitForSingleObject(workers[index].event.?, 1);
                    }
                }
            }
        }
        fn cancelWorker() void {
            while (true) {
                var active = false;
                for (0..slots.len) |index| {
                    lock(); const slot = &slots[index];
                    if (!slot.cancel_requested or slot.phase == .free or slot.phase == .completed) { unlock(); continue; }
                    active = true;
                    if (api.GetTickCount64() -| slot.cancel_started_ms.? >= 250) slot.quarantined = true;
                    // cancelNow may own the same exact arm on the VM owner.
                    // Do not issue a second Cancel call or release its returned
                    // worker until that real call has itself returned.
                    if (slot.cancel_call_active) { unlock(); continue; }
                    if (slot.phase == .returned) {
                        // Includes cancelled-before-submit; no worker/kernel
                        // operation can exist if worker is null.
                        if (slot.worker) |worker| { workers[worker].current = null; signal(workers[worker].event.?); slot.worker = null; }
                        slot.cancel_call_active = false; slot.phase = .completed;
                        const reference = slot.references[2].?; slot.references[2] = null;
                        const retired = if (slot.detached) freeLocked(slot) else null;
                        unlock(); Wake.notify(reference); Wake.release(reference);
                        if (retired) |value| retireNative(value);
                        continue;
                    }
                    if (slot.phase != .running) { unlock(); continue; }
                    const worker = slot.worker.?;
                    const ticket: ReadTicket = .{ .slot = @intCast(index), .generation = slot.generation };
                    if (workers[worker].current == null or !same(workers[worker].current.?, ticket) or workers[worker].arm != slot.arm) { unlock(); continue; }
                    slot.cancel_call_active = true;
                    const thread = workers[worker].thread.?;
                    unlock();
                    const cancelled = api.CancelSynchronousIo(thread) != 0;
                    const failure = if (cancelled) @as(u32, 0) else api.GetLastError();
                    lock();
                    // Worker cannot change the arm while cancel_call_active.
                    slot.cancel_call_active = false;
                    if (!cancelled and failure != 1168 and slot.cancel_error == null) slot.cancel_error = failure;
                    // NOT_FOUND is never completion. If the call had not yet
                    // entered ReadConsole, repeat on the same fenced arm until
                    // real return;250ms changes diagnostics/quarantine only.
                    if (slot.phase == .returned) signal(cancel_event.?);
                    unlock();
                }
                const waited = api.WaitForSingleObject(cancel_event.?, if (active) 1 else 0xffffffff);
                if (waited != 0 and waited != 258) { lock(); native_failure = if (waited == 0xffffffff) api.GetLastError() else waited; unlock(); return; }
            }
        }
    };
}
