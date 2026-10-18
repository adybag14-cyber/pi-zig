//! Bounded Engine-independent reap transfer for genuine clone3 child tickets.
//! One native worker/epoll/eventfd, sixteen stable tickets. No VM, allocator,
//! std.Io backend, callback, numeric-PID wait/signal or timer polling is retained.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const spawn = @import("native_child_process_spawn_linux.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const Admission = enum { queued, retained_failure };
const Slot = struct {
    generation: u64 = 0, ticket: ?spawn.NativeReapTicket = null,
    token: u64 = 0, failure: ?anyerror = null,
};
const Registry = struct {
    guard: Mutex = .{}, slots: [16]Slot = @splat(Slot{}),
    phase: enum { cold, ready, failed } = .cold,
    epoll: ?linux.fd_t = null, control: ?linux.fd_t = null,
    next_token: u64 = 0, reaped: u64 = 0,
    failure: ?anyerror = null,
};
var registry: Registry = .{};
fn failedLocked(failure: anyerror) void {
    registry.phase = .failed; registry.failure = failure;
    for (&registry.slots) |*slot| if (slot.ticket != null and slot.failure == null) { slot.failure = failure; };
}
fn initializeLocked() !void {
    if (registry.phase == .ready) return;
    if (registry.phase == .failed) return error.NativeLinuxChildReaperFailed;
    errdefer failedLocked(error.NativeLinuxChildReaperInitializationFailed);
    const poll_fd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
    if (linux.errno(poll_fd) != .SUCCESS) return error.NativeLinuxChildReaperEpollFailed;
    registry.epoll = @intCast(poll_fd);
    const control_fd = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
    if (linux.errno(control_fd) != .SUCCESS) return error.NativeLinuxChildReaperControlFailed;
    registry.control = @intCast(control_fd);
    var event: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .u64 = 0 } };
    if (linux.errno(linux.epoll_ctl(registry.epoll.?, linux.EPOLL.CTL_ADD, registry.control.?, &event)) != .SUCCESS) return error.NativeLinuxChildReaperControlFailed;
    const thread = try std.Thread.spawn(.{ .allocator = std.heap.page_allocator, .stack_size = 128 * 1024 }, run, .{});
    thread.detach(); registry.phase = .ready;
}
/// Errors before the move leave Ticket intact on the exact calling owner. Once
/// moved, even initialization/control failure retains it in native static storage
/// and returns retained_failure, never a false reap/absence acknowledgement.
pub fn adoptAfterWithdraw(ticket: *spawn.Ticket) !Admission {
    return adoptOwned(ticket, null);
}
pub fn adoptWithEndpointsAfterWithdraw(ticket: *spawn.Ticket, endpoints: *[3]?linux.fd_t) !Admission {
    return adoptOwned(ticket, endpoints);
}
fn adoptOwned(ticket: *spawn.Ticket, endpoints: ?*[3]?linux.fd_t) !Admission {
    if (builtin.os.tag != .linux) return error.RequiredLinuxChildReaper;
    registry.guard.lock(); defer registry.guard.unlock();
    var available: ?*Slot = null;
    for (&registry.slots) |*slot| if (slot.ticket == null and slot.generation != std.math.maxInt(u64)) { available = slot; break; };
    const slot = available orelse return error.NativeLinuxChildReaperCapacity;
    // A failed init cannot strand the sole ticket in freed VM storage: transfer
    // first into the bounded slot, then try to start the process-lifetime worker.
    var moved = try ticket.moveToNativeReaperAfterWithdraw();
    if (endpoints) |owned| { moved.endpoints = owned.*; owned.* = .{null} ** 3; }
    slot.generation += 1; slot.ticket = moved; slot.failure = null; slot.token = 0;
    initializeLocked() catch |failure| { slot.failure = failure; return .retained_failure; };
    const one: u64 = 1;
    const result = linux.write(registry.control.?, std.mem.asBytes(&one).ptr, @sizeOf(u64));
    switch (linux.errno(result)) {
        .SUCCESS => if (result != @sizeOf(u64)) { failedLocked(error.NativeLinuxChildReaperControlFailed); return .retained_failure; },
        .AGAIN => {},
        else => { failedLocked(error.NativeLinuxChildReaperControlFailed); return .retained_failure; },
    }
    return .queued;
}
fn armLocked(slot: *Slot) !void {
    const ticket = &slot.ticket.?;
    if (!ticket.claimed) try ticket.claimOnWorker();
    if (ticket.watch.reaped or ticket.watch.epoll != null) return;
    if (registry.next_token == std.math.maxInt(u64)) return error.NativeLinuxChildReaperArmExhausted;
    registry.next_token += 1; slot.token = registry.next_token;
    _ = try ticket.watch.arm(registry.epoll.?, slot.token);
}
fn finishLocked(slot: *Slot) !void {
    const ticket = &slot.ticket.?;
    if (ticket.watch.epoll != null) try ticket.watch.disarmAfterWithdraw();
    const reaped = if (ticket.watch.reaped) true else ticket.reapReady() catch |failure| interrupted: {
        if (failure == error.NativeChildPidfdReapInterrupted) break :interrupted false;
        return failure;
    };
    if (!reaped) {
        // An interrupted nonblocking status read is not child exit. Rearm the
        // actual pidfd rather than substitute a numeric PID wait or sleep loop.
        try armLocked(slot); return;
    }
    try ticket.closeReaped();
    slot.ticket = null; slot.failure = null; slot.token = 0;
    registry.reaped +|= 1;
}
fn run() void {
    while (true) {
        registry.guard.lock();
        if (registry.phase == .failed) { registry.guard.unlock(); return; }
        for (&registry.slots) |*slot| if (slot.ticket != null and slot.failure == null) {
            armLocked(slot) catch |failure| { slot.failure = failure; continue; };
            if (slot.ticket.?.watch.reaped) finishLocked(slot) catch |failure| { slot.failure = failure; };
        };
        const fd = registry.epoll.?; registry.guard.unlock();
        var events: [17]linux.epoll_event = undefined;
        const count = linux.epoll_wait(fd, &events, events.len, -1);
        switch (linux.errno(count)) { .SUCCESS => {}, .INTR => continue, else => { registry.guard.lock(); failedLocked(error.NativeLinuxChildReaperWaitFailed); registry.guard.unlock(); return; } }
        registry.guard.lock();
        if (registry.phase == .failed) { registry.guard.unlock(); return; }
        for (events[0..count]) |event| {
            if (event.data.u64 == 0) {
                var counter: u64 = undefined;
                const status = linux.errno(linux.read(registry.control.?, std.mem.asBytes(&counter).ptr, @sizeOf(u64)));
                if (status != .SUCCESS and status != .AGAIN and status != .INTR) failedLocked(error.NativeLinuxChildReaperControlFailed);
                continue;
            }
            for (&registry.slots) |*slot| if (slot.ticket != null and slot.failure == null and slot.token == event.data.u64) {
                finishLocked(slot) catch |failure| { slot.failure = failure; };
                break;
            };
        }
        registry.guard.unlock();
    }
}
pub const Snapshot = struct { owned: usize = 0, retained_failures: usize = 0, reaped: u64, worker_failure: ?anyerror };
pub fn snapshot() Snapshot {
    registry.guard.lock(); defer registry.guard.unlock();
    var result: Snapshot = .{ .reaped = registry.reaped, .worker_failure = registry.failure };
    for (registry.slots) |slot| if (slot.ticket != null) { result.owned += 1; if (slot.failure != null) result.retained_failures += 1; };
    return result;
}
