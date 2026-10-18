//! Linux native readiness only: sixteen clients, two eight-client epoll shards.
//! No Engine/VM/process allocator pointer enters a worker. Actual child status,
//! exec success/failure, pipe EOF and reaping remain owner transport operations.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const wake = @import("native_owner_wake.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const Lease = struct { slot: u8, generation: u64 };
pub const Interest = struct {
    fd: linux.fd_t,
    writable: bool = false,
    endpoint_generation: u64,
    operation_sequence: u64,
};
// stdin/stdout/stderr/exec-status/pidfd. Never infer exec success or output EOF
// from direct-child exit. Pidfd ownership is separately retained by its caller.
pub const Snapshot = struct { interests: [5]?Interest = .{null} ** 5, deadline_ms: ?u64 = null };
pub const Ready = struct { channels: u5 = 0, deadline: bool = false, immediate: bool = false, failure: ?anyerror = null, revision: u64 };
const Client = struct {
    generation: u64 = 0, revision: u64 = 0,
    reference: ?wake.Ref = null, snapshot: Snapshot = .{},
    ready: u5 = 0, deadline_ready: bool = false, immediate: bool = false,
    failure: ?anyerror = null,
};
const Candidate = struct { slot: u8, generation: u64, revision: u64, channel: u3, endpoint_generation: u64, operation_sequence: u64 };
const Record = struct {
    fd: linux.fd_t, flags: u32, token: u64,
    candidates: [40]Candidate = undefined, count: usize = 0,
};
const Shard = struct {
    epoll: ?linux.fd_t = null, control: ?linux.fd_t = null,
    records: [40]Record = undefined, count: usize = 0,
};
const State = struct {
    guard: Mutex = .{}, phase: enum { cold, ready, failed } = .cold,
    clients: [16]Client = @splat(Client{}), shards: [2]Shard = @splat(Shard{}),
    next_token: u64 = 0,
};
var state: State = .{};
pub fn monotonicMilliseconds() !u64 {
    var now: linux.timespec = undefined;
    if (linux.errno(linux.clock_gettime(.MONOTONIC, &now)) != .SUCCESS) return error.NativeLinuxChildClockFailed;
    if (now.sec < 0 or now.nsec < 0 or now.nsec >= 1000000000) return error.NativeLinuxChildClockInvalid;
    const seconds = std.math.mul(u64, @intCast(now.sec), 1000) catch return error.NativeLinuxChildClockOverflow;
    return std.math.add(u64, seconds, @as(u64, @intCast(now.nsec)) / 1000000) catch return error.NativeLinuxChildClockOverflow;
}
fn valid(lease: Lease) ?*Client {
    if (lease.slot >= state.clients.len) return null;
    const client = &state.clients[lease.slot];
    return if (client.reference != null and client.generation == lease.generation) client else null;
}
fn failLocked(failure: anyerror) void {
    state.phase = .failed;
    for (&state.clients) |*client| if (client.reference != null) { client.failure = failure; };
}
fn notifyFailures() void {
    var references: [16]?wake.Ref = .{null} ** 16;
    state.guard.lock();
    if (state.phase == .failed) for (state.clients, 0..) |client, index| { references[index] = client.reference; };
    state.guard.unlock();
    for (references) |reference| if (reference) |value| wake.notify(value);
}
fn controlLocked(shard_index: usize) !void {
    const one: u64 = 1;
    const result = linux.write(state.shards[shard_index].control.?, std.mem.asBytes(&one).ptr, @sizeOf(u64));
    switch (linux.errno(result)) {
        .SUCCESS => if (result != @sizeOf(u64)) return error.NativeLinuxChildControlShortWrite,
        .AGAIN => {}, // Existing eventfd readability already carries this work.
        .INTR => return error.NativeLinuxChildControlInterrupted,
        else => return error.NativeLinuxChildControlWriteFailed,
    }
}
fn initializeLocked() !void {
    if (state.phase == .ready) return;
    if (state.phase == .failed) return error.NativeLinuxChildReadinessFailed;
    // Partial initialization is terminal, not a source of replacement workers.
    // At most two native threads/four permanent descriptors survive host exit.
    errdefer failLocked(error.NativeLinuxChildReadinessInitializationFailed);
    for (&state.shards) |*shard| {
        const poll_fd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        if (linux.errno(poll_fd) != .SUCCESS) return error.NativeLinuxChildEpollCreateFailed;
        shard.epoll = @intCast(poll_fd);
        const event_fd = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
        if (linux.errno(event_fd) != .SUCCESS) return error.NativeLinuxChildEventfdCreateFailed;
        shard.control = @intCast(event_fd);
        var control: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .u64 = 0 } };
        if (linux.errno(linux.epoll_ctl(shard.epoll.?, linux.EPOLL.CTL_ADD, shard.control.?, &control)) != .SUCCESS) return error.NativeLinuxChildControlAttachFailed;
    }
    for (0..2) |index| {
        const thread = try std.Thread.spawn(.{ .stack_size = 128 * 1024, .allocator = std.heap.page_allocator }, run, .{index});
        thread.detach();
    }
    state.phase = .ready;
}
pub fn reserve(reference: wake.Ref) !Lease {
    if (builtin.os.tag != .linux) return error.RequiredLinuxChildReadiness;
    const retained = try wake.retain(reference); errdefer wake.release(retained);
    state.guard.lock(); defer state.guard.unlock();
    try initializeLocked();
    for (&state.clients, 0..) |*client, index| if (client.reference == null and client.generation != std.math.maxInt(u64)) {
        const generation = client.generation + 1;
        client.* = .{ .generation = generation, .reference = retained };
        return .{ .slot = @intCast(index), .generation = generation };
    };
    return error.NativeLinuxChildReadinessCapacity;
}
fn rebuildLocked(shard_index: usize) !void {
    const shard = &state.shards[shard_index];
    // epoll_wait may concurrently return copied events. Deleting registration
    // under the same guard BEFORE owner close/reset prevents registering a reused
    // numeric fd from an obsolete snapshot. Copied events need a new full token.
    for (shard.records[0..shard.count]) |record| {
        const status = linux.errno(linux.epoll_ctl(shard.epoll.?, linux.EPOLL.CTL_DEL, record.fd, null));
        if (status != .SUCCESS) return error.NativeLinuxChildEpollWithdrawFailed;
    }
    shard.count = 0;
    for (shard_index * 8..shard_index * 8 + 8) |index| {
        const client = &state.clients[index];
        if (client.reference == null) continue;
        for (client.snapshot.interests, 0..) |maybe_interest, channel| if (maybe_interest) |interest| {
            var record_index: usize = 0;
            while (record_index < shard.count and shard.records[record_index].fd != interest.fd) : (record_index += 1) {}
            if (record_index == shard.count) {
                if (state.next_token == std.math.maxInt(u64)) return error.NativeLinuxChildArmSequenceExhausted;
                state.next_token += 1;
                shard.records[record_index] = .{ .fd = interest.fd, .flags = 0, .token = state.next_token };
                shard.count += 1;
            }
            const record = &shard.records[record_index];
            record.flags |= if (interest.writable) linux.EPOLL.OUT else linux.EPOLL.IN;
            record.candidates[record.count] = .{ .slot = @intCast(index), .generation = client.generation, .revision = client.revision, .channel = @intCast(channel), .endpoint_generation = interest.endpoint_generation, .operation_sequence = interest.operation_sequence };
            record.count += 1;
        };
    }
    for (shard.records[0..shard.count]) |record| {
        var event: linux.epoll_event = .{ .events = record.flags | linux.EPOLL.ONESHOT, .data = .{ .u64 = record.token } };
        if (linux.errno(linux.epoll_ctl(shard.epoll.?, linux.EPOLL.CTL_ADD, record.fd, &event)) != .SUCCESS) return error.NativeLinuxChildEpollPublishFailed;
    }
    try controlLocked(shard_index);
}
pub fn publish(lease: Lease, snapshot: Snapshot) !void {
    errdefer notifyFailures();
    state.guard.lock(); defer state.guard.unlock();
    const client = valid(lease) orelse return error.NativeLinuxChildReadinessStale;
    if (state.phase != .ready) return error.NativeLinuxChildReadinessFailed;
    if (client.revision == std.math.maxInt(u64)) return error.NativeLinuxChildRevisionExhausted;
    for (snapshot.interests) |interest| if (interest) |value| if (value.fd < 0) return error.NativeLinuxChildInvalidInterest;
    // These bits belong to the superseded snapshot, not to the new revision.
    // Explicit owner-requested immediate work is independent and stays queued.
    client.ready = 0; client.deadline_ready = false;
    client.revision += 1; client.snapshot = snapshot;
    rebuildLocked(lease.slot / 8) catch |failure| { failLocked(failure); return failure; };
}
/// Native return acknowledges epoll removal and logical token invalidation.
/// No pipe duplicate keeps a hidden read/write endpoint alive after this call.
pub fn withdraw(lease: Lease) !void { try publish(lease, .{}); }
pub fn requestStep(lease: Lease) void {
    var reference: ?wake.Ref = null;
    state.guard.lock();
    if (valid(lease)) |client| { client.immediate = true; reference = client.reference; }
    state.guard.unlock();
    if (reference) |value| wake.notify(value);
}
pub fn takeReady(lease: Lease) ?Ready {
    state.guard.lock(); defer state.guard.unlock();
    const client = valid(lease) orelse return null;
    if (client.ready == 0 and !client.deadline_ready and !client.immediate and client.failure == null) return null;
    const result: Ready = .{ .channels = client.ready, .deadline = client.deadline_ready, .immediate = client.immediate, .failure = client.failure, .revision = client.revision };
    client.ready = 0; client.deadline_ready = false; client.immediate = false;
    return result;
}
/// Caller retains process/native-reaper ownership separately. Release never
/// closes a pidfd, reaps a child or claims that a pipe producer reached EOF.
pub fn releaseAfterWithdraw(lease: Lease) !void {
    try withdraw(lease);
    state.guard.lock();
    const client = valid(lease) orelse { state.guard.unlock(); return error.NativeLinuxChildReadinessStale; };
    const reference = client.reference.?; client.reference = null;
    state.guard.unlock(); wake.release(reference);
}
fn run(shard_index: usize) void {
    while (true) {
        var events: [41]linux.epoll_event = undefined;
        var references: [8]?wake.Ref = .{null} ** 8;
        state.guard.lock();
        if (state.phase == .failed) { state.guard.unlock(); return; }
        const shard = &state.shards[shard_index];
        const now = monotonicMilliseconds() catch |failure| { failLocked(failure); state.guard.unlock(); notifyFailures(); return; };
        var due: ?u64 = null;
        for (shard_index * 8..shard_index * 8 + 8) |index| if (state.clients[index].reference != null) {
            if (state.clients[index].snapshot.deadline_ms) |deadline| due = if (due) |prior| @min(prior, deadline) else deadline;
        };
        const timeout: i32 = if (due) |deadline| @intCast(@min(deadline -| now, std.math.maxInt(i32))) else -1;
        const fd = shard.epoll.?; state.guard.unlock();
        const count = linux.epoll_wait(fd, &events, events.len, timeout);
        switch (linux.errno(count)) { .SUCCESS => {}, .INTR => continue, else => { state.guard.lock(); failLocked(error.NativeLinuxChildEpollWaitFailed); state.guard.unlock(); notifyFailures(); return; } }
        state.guard.lock();
        if (state.phase == .failed) { state.guard.unlock(); return; }
        const arrived = monotonicMilliseconds() catch |failure| { failLocked(failure); state.guard.unlock(); notifyFailures(); return; };
        for (events[0..count]) |event| {
            if (event.data.u64 == 0) {
                var counter: u64 = undefined;
                const result = linux.read(shard.control.?, std.mem.asBytes(&counter).ptr, @sizeOf(u64));
                switch (linux.errno(result)) { .SUCCESS, .AGAIN, .INTR => {}, else => { failLocked(error.NativeLinuxChildControlReadFailed); } }
                continue;
            }
            for (shard.records[0..shard.count]) |record| if (record.token == event.data.u64) {
                for (record.candidates[0..record.count]) |candidate| {
                    const client = &state.clients[candidate.slot];
                    if (client.reference == null or client.generation != candidate.generation or client.revision != candidate.revision) continue;
                    const interest = client.snapshot.interests[candidate.channel] orelse continue;
                    if (interest.fd != record.fd or interest.endpoint_generation != candidate.endpoint_generation or interest.operation_sequence != candidate.operation_sequence) continue;
                    if (event.events & (linux.EPOLL.ERR | linux.EPOLL.HUP | (if (interest.writable) linux.EPOLL.OUT else linux.EPOLL.IN)) == 0) continue;
                    client.ready |= @as(u5, 1) << candidate.channel;
                    references[candidate.slot % 8] = client.reference;
                }
            };
        }
        for (shard_index * 8..shard_index * 8 + 8) |index| {
            const client = &state.clients[index];
            if (client.reference == null) continue;
            if (client.snapshot.deadline_ms) |deadline| if (deadline <= arrived) {
                client.snapshot.deadline_ms = null; client.deadline_ready = true;
                references[index % 8] = client.reference;
            };
        }
        const failed = state.phase == .failed;
        state.guard.unlock();
        if (failed) { notifyFailures(); return; }
        for (references) |reference| if (reference) |value| wake.notify(value);
    }
}

const ControlQuarantine = struct { lease: Lease, endpoints: [2]?linux.fd_t };
var control_quarantine: [2]?ControlQuarantine = .{null} ** 2;
fn cleanupPipeControl(lease: Lease, endpoints: [2]?linux.fd_t) void {
    if (releaseAfterWithdraw(lease)) |_| {
        for (endpoints) |maybe_fd| if (maybe_fd) |fd| { _ = linux.close(fd); };
    } else |_| {
        // Test failure retains explicit native ownership; never close a borrowed
        // integer after failed withdrawal. These controls run once per owned job.
        state.guard.lock();
        for (&control_quarantine) |*entry| if (entry.* == null) {
            entry.* = .{ .lease = lease, .endpoints = endpoints };
            state.guard.unlock();
            std.debug.panic("Linux epoll control cleanup retained ownership after failed withdrawal", .{});
        };
        state.guard.unlock();
        std.debug.panic("Linux epoll control quarantine capacity exhausted", .{});
    }
}
test "Linux epoll publishes real pipe readiness and withdrawal owns no hidden writer" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const Signal = @import("native_owner_signal.zig").Signal;
    var signal: Signal = .{};
    const reference = try wake.create(.{ .signal = &signal, .io = std.testing.io });
    defer { wake.detach(reference); wake.release(reference); }
    const lease = try reserve(reference);
    var lease_owned = true; errdefer if (lease_owned) cleanupPipeControl(lease, .{null, null});
    var descriptors: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&descriptors, .{ .CLOEXEC = true, .NONBLOCK = true })) != .SUCCESS) return error.TestPipeFailed;
    var owned: [2]?linux.fd_t = .{ descriptors[0], descriptors[1] };
    lease_owned = false; defer cleanupPipeControl(lease, owned);
    var snapshot: Snapshot = .{};
    snapshot.interests[1] = .{ .fd = descriptors[0], .endpoint_generation = 1, .operation_sequence = 1 };
    const observed = signal.observe();
    try publish(lease, snapshot);
    const payload = "actual";
    try std.testing.expectEqual(@as(usize, payload.len), linux.write(descriptors[1], payload.ptr, payload.len));
    try std.testing.expect(try signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } }));
    const ready = takeReady(lease) orelse return error.TestMissingNativeReadiness;
    try std.testing.expect(ready.channels & 2 != 0);
    try withdraw(lease);
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, payload.len), linux.read(descriptors[0], &buffer, buffer.len));
    owned[1] = null; _ = linux.close(descriptors[1]);
    try std.testing.expectEqual(@as(usize, 0), linux.read(descriptors[0], &buffer, buffer.len));
}

test "Linux epoll rearm discards old channel and deadline readiness but keeps immediate work" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const Signal = @import("native_owner_signal.zig").Signal;
    var signal: Signal = .{};
    const reference = try wake.create(.{ .signal = &signal, .io = std.testing.io });
    defer { wake.detach(reference); wake.release(reference); }
    const lease = try reserve(reference);
    var lease_owned = true; errdefer if (lease_owned) cleanupPipeControl(lease, .{null, null});
    var descriptors: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&descriptors, .{ .CLOEXEC = true, .NONBLOCK = true })) != .SUCCESS) return error.TestPipeFailed;
    lease_owned = false; defer cleanupPipeControl(lease, .{descriptors[0], descriptors[1]});
    var snapshot: Snapshot = .{};
    snapshot.interests[1] = .{ .fd = descriptors[0], .endpoint_generation = 1, .operation_sequence = 1 };
    var observed = signal.observe(); try publish(lease, snapshot);
    const payload = "x";
    try std.testing.expectEqual(@as(usize, 1), linux.write(descriptors[1], payload.ptr, payload.len));
    try std.testing.expect(try signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } }));
    // Leave actual channel readiness queued, withdraw, then drain the old data.
    requestStep(lease); try withdraw(lease);
    var byte: [1]u8 = undefined; try std.testing.expectEqual(@as(usize, 1), linux.read(descriptors[0], &byte, 1));
    snapshot.interests[1].?.endpoint_generation = 2; snapshot.interests[1].?.operation_sequence = 2;
    try publish(lease, snapshot);
    const immediate = takeReady(lease) orelse return error.TestMissingExplicitImmediate;
    try std.testing.expect(immediate.immediate and immediate.channels == 0 and !immediate.deadline);
    // Queue an actual elapsed deadline, then replace it without draining ready.
    observed = signal.observe(); try publish(lease, .{ .deadline_ms = try monotonicMilliseconds() });
    try std.testing.expect(try signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } }));
    try withdraw(lease);
    snapshot.deadline_ms = (try monotonicMilliseconds()) + 10000;
    try publish(lease, snapshot);
    try std.testing.expect(takeReady(lease) == null);
    // Descriptor cleanup must happen after an acknowledged withdrawal.
    try withdraw(lease);
}
