//! Bounded direct console CloseHandle retirement for stdio duplicates. Source
//! uv_tty_init owns a duplicate HANDLE for fd0-2, not another CRT descriptor.
//! Native-only fixed tickets, one worker, canonical Wake. No VM scheduler.
const std = @import("std");
const w = std.os.windows;
const H = w.HANDLE;
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateEventW(?*anyopaque, i32, i32, ?[*:0]const u16) callconv(.winapi) ?H;
    extern "kernel32" fn SetEvent(H) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
    extern "kernel32" fn CloseHandle(H) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
};
const Reference = struct { slot: u8, generation: u64 };
pub const Ticket = Reference;
pub const Result = union(enum) { closed, failed: u32 };
pub const Limits = struct { pub const tickets = 16; pub const threads = 1; pub const stack_bytes = 128 * 1024; };
pub fn Pool(comptime Wake: type) type {
    return struct {
        pub const Ticket = Reference;
        const Phase = enum { free, reserved, associated, queued, running, completed, retained_failure };
        const Slot = struct {
            phase: Phase = .free, generation: u64 = 0, handle: ?H = null,
            owner_wake: ?Wake.Ref = null, worker_wake: ?Wake.Ref = null,
            result: Result = .closed, detached: bool = false,
        };
        var gate: w.SRWLOCK = .{};
        var slots: [Limits.tickets]Slot = .{.{}} ** Limits.tickets;
        var event: ?H = null;
        var initialized: bool = false;
        var initialization_failed: bool = false;
        var native_failure: ?u32 = null;
        fn lock() void { api.AcquireSRWLockExclusive(&gate); }
        fn unlock() void { api.ReleaseSRWLockExclusive(&gate); }
        fn valid(ticket: Ticket) !*Slot {
            if (ticket.slot >= slots.len) return error.NativeTtyCloseTicketMismatch;
            const slot = &slots[ticket.slot];
            if (slot.phase == .free or slot.generation != ticket.generation) return error.NativeTtyCloseTicketMismatch;
            return slot;
        }
        fn initialize() !void {
            if (initialization_failed or native_failure != null) return error.NativeTtyCloseWorkersUnavailable;
            if (initialized) return;
            errdefer initialization_failed = true;
            event = api.CreateEventW(null, 0, 0, null) orelse return error.NativeTtyCloseEventFailed;
            const thread = try std.Thread.spawn(.{ .stack_size = Limits.stack_bytes, .allocator = std.heap.page_allocator }, worker, .{});
            thread.detach(); initialized = true;
        }
        /// Reserve both native wake entitlements BEFORE DuplicateHandle.
        pub fn reserve(reference: Wake.Ref) !Ticket {
            lock(); defer unlock(); try initialize();
            for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
                const owner = try Wake.retain(reference); errdefer Wake.release(owner);
                const worker_ref = try Wake.retain(reference);
                const generation = slot.generation + 1;
                slot.* = .{ .phase = .reserved, .generation = generation, .owner_wake = owner, .worker_wake = worker_ref };
                return .{ .slot = @intCast(index), .generation = generation };
            };
            return error.NativeTtyCloseTicketCapacity;
        }
        /// Exclusive ownership transfer of the actual duplicate, without an
        /// extra CRT fd allocation or a borrowed File's independent close.
        pub fn associate(ticket: Ticket, owned_duplicate: H) !void {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase != .reserved) return error.NativeTtyCloseAlreadyAssociated;
            slot.handle = owned_duplicate; slot.phase = .associated;
        }
        pub fn releaseUnassociated(ticket: Ticket) !void {
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            if (slot.phase != .reserved) { unlock(); return error.NativeTtyCloseAlreadyAssociated; }
            const owner = slot.owner_wake.?; const worker_ref = slot.worker_wake.?;
            freeLocked(slot); unlock(); Wake.release(worker_ref); Wake.release(owner);
        }
        /// Caller proved every real read/write on this handle has retired.
        /// No cancellation/timeout request is accepted as that proof.
        pub fn submitAfterIo(ticket: Ticket) !void {
            lock(); defer unlock(); const slot = try valid(ticket);
            if (slot.phase == .associated) {
                slot.phase = .queued;
                if (api.SetEvent(event.?) == 0 and native_failure == null) native_failure = api.GetLastError();
            } else if (slot.phase == .reserved) return error.NativeTtyCloseNativeHandleRequired;
        }
        fn freeLocked(slot: *Slot) void { const generation = slot.generation; slot.* = .{ .generation = generation }; }
        pub fn poll(ticket: Ticket) !?Result {
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            if (slot.detached) { unlock(); return error.NativeTtyCloseOwnerDetached; }
            if (slot.phase == .retained_failure) { const result = slot.result; unlock(); return result; }
            if (slot.phase != .completed) {
                if (native_failure != null) { unlock(); return error.NativeTtyCloseWorkersUnavailable; }
                unlock(); return null;
            }
            const result = slot.result; const owner = slot.owner_wake.?;
            switch (result) { .closed => freeLocked(slot), .failed => { slot.phase = .retained_failure; slot.owner_wake = null; } }
            unlock(); Wake.release(owner); return result;
        }
        pub fn detachAfterIo(ticket: Ticket) !void {
            try submitAfterIo(ticket);
            lock(); const slot = valid(ticket) catch |err| { unlock(); return err; };
            slot.detached = true;
            if (slot.phase == .completed) {
                const owner = slot.owner_wake.?;
                switch (slot.result) { .closed => freeLocked(slot), .failed => { slot.phase = .retained_failure; slot.owner_wake = null; } }
                unlock(); Wake.release(owner); return;
            }
            unlock();
        }
        fn worker() void {
            while (true) {
                lock();
                if (native_failure != null) { unlock(); return; }
                var selected: ?usize = null;
                for (&slots, 0..) |*slot, index| if (slot.phase == .queued) { slot.phase = .running; selected = index; break; };
                if (selected == null) {
                    const ready = event.?; unlock();
                    const waited = api.WaitForSingleObject(ready, 0xffffffff);
                    if (waited != 0) { lock(); native_failure = if (waited == 0xffffffff) api.GetLastError() else waited; unlock(); return; }
                    continue;
                }
                const slot = &slots[selected.?];
                const handle = slot.handle.?;
                const worker_ref = slot.worker_wake.?; slot.worker_wake = null;
                unlock();
                // Exactly one call. False is uncertain, never permission to
                // retry a possibly recycled numeric HANDLE during teardown.
                const result: Result = if (api.CloseHandle(handle) != 0) .closed else .{ .failed = api.GetLastError() };
                lock(); slot.result = result; slot.phase = .completed;
                var owner: ?Wake.Ref = null;
                if (slot.detached) {
                    owner = slot.owner_wake;
                    switch (result) { .closed => freeLocked(slot), .failed => { slot.phase = .retained_failure; slot.owner_wake = null; } }
                }
                unlock();
                if (owner) |reference| Wake.release(reference);
                Wake.notify(worker_ref); Wake.release(worker_ref);
            }
        }
    };
}
