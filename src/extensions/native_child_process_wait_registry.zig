//! Windows-first bounded native readiness. No Engine/VM or transport pointer
//! enters a wait snapshot. Permanent endpoint events are borrowed; process wait
//! duplicates are closed only by the shard after its wait has returned.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
const wake = @import("native_owner_wake.zig");
pub const Lease = struct { slot: u8, generation: u64 };
pub const Event = struct { handle: w.HANDLE, endpoint_generation: u64, operation_sequence: u64 };
pub const Snapshot = struct { events: [3]?Event = .{ null, null, null }, exited: bool = false, deadline_ms: ?u64 = null };
pub const Mask = packed struct(u16) { input: bool = false, stdout: bool = false, stderr: bool = false, child_exit: bool = false, deadline: bool = false, immediate: bool = false, retired: bool = false, failure: bool = false, padding: u8 = 0 };
pub const Ready = struct { mask: Mask, revision: u64, failure: ?anyerror = null };
pub const Tag = struct { endpoint_generation: u64 = 0, operation_sequence: u64 = 0, arm_epoch: u64 = 0 };
const Phase = enum { free, reserved, attached, retiring, reaping, retired };
const Client = struct {
    generation: u64 = 0, revision: u64 = 0, phase: Phase = .free,
    wake_ref: ?wake.Ref = null, process: ?w.HANDLE = null,
    snapshot: Snapshot = .{}, tags: [4]Tag = @splat(Tag{}),
    armed: [4]bool = .{ false, false, false, false }, deadline_armed: bool = false,
    ready: u16 = 0, failure: ?anyerror = null, detached: bool = false,
};
const Registry = struct {
    gate: w.SRWLOCK = .{}, clients: [16]Client = @splat(Client{}),
    controls: [2]?w.HANDLE = .{ null, null }, phase: enum { cold, ready, failed } = .cold,
    arm_epoch: u64 = 0,
};
var registry: Registry = .{};
fn lock() void { api.AcquireSRWLockExclusive(&registry.gate); }
fn unlock() void { api.ReleaseSRWLockExclusive(&registry.gate); }
fn valid(lease: Lease) ?*Client {
    if (lease.slot >= registry.clients.len) return null;
    const client = &registry.clients[lease.slot];
    return if (client.phase != .free and client.generation == lease.generation) client else null;
}
fn bits(mask: Mask) u16 { return @bitCast(mask); }
fn failLocked(failure: anyerror) void {
    registry.phase = .failed;
    for (&registry.clients) |*client| if (client.phase != .free) { client.failure = failure; client.ready |= bits(.{ .failure = true }); };
    for (registry.controls) |event| if (event) |handle| { _ = api.SetEvent(handle); };
}
fn notifyFailures() void {
    var references: [16]?wake.Ref = .{null} ** 16;
    lock();
    if (registry.phase == .failed) for (&registry.clients, 0..) |*client, index| { references[index] = client.wake_ref; };
    unlock();
    for (references) |reference| if (reference) |value| wake.notify(value);
}
fn control(index: usize) !void {
    if (api.SetEvent(registry.controls[index / 8].?) == 0) { failLocked(error.NativeChildReadinessWakeFailed); return error.NativeChildReadinessWakeFailed; }
}
fn initialize() !void {
    if (registry.phase == .failed) return error.NativeChildReadinessFailed;
    if (registry.phase == .ready) return;
    // Failure is terminal for admission. Partially created native resources stay
    // capped until host exit; no retry creates replacement workers or handles.
    errdefer { registry.phase = .failed; for (registry.controls) |event| if (event) |handle| { _ = api.SetEvent(handle); }; }
    for (&registry.controls) |*event| event.* = api.CreateEventW(null, 1, 0, null) orelse return error.NativeChildReadinessEventFailed;
    for (0..2) |shard| {
        const thread = try std.Thread.spawn(.{ .stack_size = 128 * 1024, .allocator = std.heap.page_allocator }, run, .{shard});
        thread.detach();
    }
    registry.phase = .ready;
}
pub fn reserve(reference: wake.Ref) !Lease {
    if (builtin.os.tag != .windows) return error.RequiredNativePosixChildReadiness;
    const retained = try wake.retain(reference);
    errdefer wake.release(retained);
    lock(); defer unlock();
    try initialize();
    for (&registry.clients, 0..) |*client, index| if (client.phase == .free and client.generation != std.math.maxInt(u64)) {
        const generation = client.generation + 1;
        client.* = .{ .generation = generation, .phase = .reserved, .wake_ref = retained };
        return .{ .slot = @intCast(index), .generation = generation };
    };
    return error.NativeChildReadinessCapacity;
}
/// Before any transport step/control that can reset/retire/reuse an endpoint.
/// This invalidates even a local wait snapshot not yet rebuilt by its worker.
pub fn withdraw(lease: Lease) !void {
    errdefer notifyFailures();
    lock(); defer unlock();
    const client = valid(lease) orelse return error.NativeChildReadinessStale;
    if (client.revision == std.math.maxInt(u64)) return error.NativeChildWatchRevisionExhausted;
    client.revision += 1;
    client.armed = .{ false, false, false, false };
    client.deadline_armed = false;
    try control(lease.slot);
}
pub fn attachProcess(lease: Lease, original: w.HANDLE) !void {
    var duplicate: w.HANDLE = undefined;
    const current = api.GetCurrentProcess();
    if (api.DuplicateHandle(current, original, current, &duplicate, 0x00100000, 0, 0) == 0) return error.NativeChildProcessWaitDuplicateFailed;
    errdefer w.CloseHandle(duplicate);
    lock(); defer unlock();
    const client = valid(lease) orelse return error.NativeChildReadinessStale;
    if (client.phase != .reserved or client.process != null) return error.NativeChildReadinessAlreadyAttached;
    client.process = duplicate;
    client.phase = .attached;
}
/// Real failed-launch pipes have no process handle to duplicate or await.
/// Endpoint-only admission still consumes one of the same sixteen clients.
pub fn attachEndpoints(lease: Lease) !void {
    lock(); defer unlock();
    const client = valid(lease) orelse return error.NativeChildReadinessStale;
    if (client.phase != .reserved or client.process != null) return error.NativeChildReadinessAlreadyAttached;
    client.phase = .attached;
}
pub fn publish(lease: Lease, snapshot: Snapshot) !void {
    errdefer notifyFailures();
    lock(); defer unlock();
    const client = valid(lease) orelse return error.NativeChildReadinessStale;
    if (registry.phase != .ready) return error.NativeChildReadinessFailed;
    if (client.phase != .attached) return error.NativeChildReadinessNotAttached;
    if (client.revision == std.math.maxInt(u64) or registry.arm_epoch > std.math.maxInt(u64) - 4) return error.NativeChildWatchRevisionExhausted;
    client.revision += 1;
    client.snapshot = snapshot;
    for (snapshot.events, 0..) |maybe_event, channel| {
        client.armed[channel] = maybe_event != null;
        if (maybe_event) |event| {
            registry.arm_epoch += 1;
            client.tags[channel] = .{ .endpoint_generation = event.endpoint_generation, .operation_sequence = event.operation_sequence, .arm_epoch = registry.arm_epoch };
        }
    }
    client.armed[3] = !snapshot.exited and client.process != null;
    if (client.armed[3]) {
        registry.arm_epoch += 1;
        client.tags[3] = .{ .endpoint_generation = client.generation, .operation_sequence = 1, .arm_epoch = registry.arm_epoch };
    }
    client.deadline_armed = snapshot.deadline_ms != null;
    try control(lease.slot);
}
pub fn requestStep(lease: Lease) void {
    var reference: ?wake.Ref = null;
    lock();
    if (valid(lease)) |client| if (!client.detached) {
        client.ready |= bits(.{ .immediate = true });
        reference = client.wake_ref;
    };
    unlock();
    if (reference) |value| wake.notify(value);
}
pub fn takeReady(lease: Lease) ?Ready {
    lock(); defer unlock();
    const client = valid(lease) orelse return null;
    if (client.ready == 0 or client.detached) return null;
    const result: Ready = .{ .mask = @bitCast(client.ready), .revision = client.revision, .failure = client.failure };
    client.ready = 0;
    return result;
}
pub fn retireObserved(lease: Lease) !void {
    errdefer notifyFailures();
    lock(); defer unlock();
    const client = valid(lease) orelse return error.NativeChildReadinessStale;
    client.phase = .retiring;
    client.armed = .{ false, false, false, false };
    client.deadline_armed = false;
    if (client.revision == std.math.maxInt(u64)) return error.NativeChildWatchRevisionExhausted;
    client.revision += 1;
    try control(lease.slot);
}
/// Nonblocking teardown. If attach duplication failed, transfer the original
/// process handle here after signaling; otherwise the existing duplicate waits.
pub fn detachForShutdown(lease: Lease, original: ?w.HANDLE) void {
    var close_original: ?w.HANDLE = null;
    lock();
    if (valid(lease)) |client| {
        client.detached = true;
        client.ready = 0;
        client.armed = .{ false, false, false, false };
        client.deadline_armed = false;
        client.revision +|= 1;
        if (client.process == null) client.process = original else close_original = original;
        client.phase = if (client.process != null) .reaping else .retiring;
        control(lease.slot) catch {};
    } else close_original = original;
    unlock();
    if (close_original) |handle| w.CloseHandle(handle);
    notifyFailures();
}
pub fn releaseRetired(lease: Lease) bool {
    var reference: ?wake.Ref = null;
    lock();
    const client = valid(lease) orelse { unlock(); return false; };
    if (client.phase != .retired or client.process != null) { unlock(); return false; }
    reference = client.wake_ref;
    client.wake_ref = null;
    client.phase = .free;
    unlock();
    if (reference) |value| wake.release(value);
    return true;
}
const Candidate = struct { index: usize, generation: u64, revision: u64, channel: usize, tag: Tag, wait_index: usize };
fn sameTag(a: Tag, b: Tag) bool { return a.endpoint_generation == b.endpoint_generation and a.operation_sequence == b.operation_sequence and a.arm_epoch == b.arm_epoch; }
fn uniqueHandle(handles: *[33]w.HANDLE, count: *usize, handle: w.HANDLE) usize {
    for (handles[0..count.*], 0..) |existing, index| if (existing == handle) return index;
    const index = count.*;
    std.debug.assert(index < handles.len);
    handles[index] = handle;
    count.* += 1;
    return index;
}
fn run(shard: usize) void {
    while (true) {
        var handles: [33]w.HANDLE = undefined;
        var candidates: [32]Candidate = undefined;
        var count: usize = 1;
        var candidate_count: usize = 0;
        var notifications: [8]?wake.Ref = .{null} ** 8;
        var releases: [8]?wake.Ref = .{null} ** 8;
        var deadline: ?u64 = null;
        lock();
        if (registry.phase == .failed) { unlock(); return; }
        handles[0] = registry.controls[shard].?;
        if (api.ResetEvent(handles[0]) == 0) { failLocked(error.NativeChildReadinessResetFailed); unlock(); notifyFailures(); return; }
        for (shard * 8..shard * 8 + 8) |index| {
            const client = &registry.clients[index];
            if (client.phase == .retiring) {
                if (client.process) |handle| w.CloseHandle(handle);
                client.process = null;
                if (client.detached) {
                    releases[index % 8] = client.wake_ref;
                    client.wake_ref = null;
                    client.phase = .free;
                } else {
                    client.phase = .retired;
                    client.ready |= bits(.{ .retired = true });
                    notifications[index % 8] = client.wake_ref;
                }
                continue;
            }
            if (client.phase != .attached and client.phase != .reaping) continue;
            if (client.phase == .attached) {
                if (client.deadline_armed) {
                    if (client.snapshot.deadline_ms) |due| deadline = if (deadline) |prior| @min(prior, due) else due;
                }
                for (client.snapshot.events, 0..) |maybe_event, channel| if (maybe_event) |event| if (client.armed[channel]) {
                    candidates[candidate_count] = .{ .index = index, .generation = client.generation, .revision = client.revision, .channel = channel, .tag = client.tags[channel], .wait_index = uniqueHandle(&handles, &count, event.handle) };
                    candidate_count += 1;
                };
            }
            if (client.process) |handle| if (client.phase == .reaping or client.armed[3]) {
                candidates[candidate_count] = .{ .index = index, .generation = client.generation, .revision = client.revision, .channel = 3, .tag = client.tags[3], .wait_index = uniqueHandle(&handles, &count, handle) };
                candidate_count += 1;
            };
        }
        unlock();
        for (notifications) |maybe_ref| if (maybe_ref) |reference| wake.notify(reference);
        for (releases) |maybe_ref| if (maybe_ref) |reference| wake.release(reference);
        const now = api.GetTickCount64();
        const timeout: u32 = if (deadline) |due| @intCast(@min(due -| now, 0xfffffffe)) else 0xffffffff;
        const selected = api.WaitForMultipleObjects(@intCast(count), &handles, 0, timeout);
        notifications = .{null} ** 8;
        releases = .{null} ** 8;
        lock();
        if (selected == 0xffffffff) {
            failLocked(error.NativeChildReadinessWaitFailed);
            for (shard * 8..shard * 8 + 8) |index| {
                const client = &registry.clients[index];
                if (client.phase != .free) { client.failure = error.NativeChildReadinessWaitFailed; client.ready |= bits(.{ .failure = true }); notifications[index % 8] = client.wake_ref; }
            }
        } else if (selected == 0x102) {
            const reached = api.GetTickCount64();
            for (shard * 8..shard * 8 + 8) |index| {
                const client = &registry.clients[index];
                if (client.phase == .attached and client.deadline_armed) if (client.snapshot.deadline_ms) |due| if (due <= reached) {
                    client.deadline_armed = false;
                    client.ready |= bits(.{ .deadline = true });
                    notifications[index % 8] = client.wake_ref;
                };
            }
        } else if (selected < count) {
            // Deduplicated HANDLE can represent several stale/current candidate
            // interests. Fan out only to matching full captured identities.
            for (candidates[0..candidate_count]) |candidate| if (candidate.wait_index == selected) {
                const client = &registry.clients[candidate.index];
                if (client.generation != candidate.generation or client.revision != candidate.revision) continue;
                if (client.phase == .reaping and candidate.channel == 3) {
                    w.CloseHandle(client.process.?);
                    client.process = null;
                    releases[candidate.index % 8] = client.wake_ref;
                    client.wake_ref = null;
                    client.phase = .free;
                    continue;
                }
                if (client.phase != .attached or !client.armed[candidate.channel] or !sameTag(client.tags[candidate.channel], candidate.tag)) continue;
                client.armed[candidate.channel] = false;
                client.ready |= @as(u16, 1) << @intCast(candidate.channel);
                notifications[candidate.index % 8] = client.wake_ref;
            };
        } else failLocked(error.NativeChildReadinessUnexpectedWaitStatus);
        const failed = registry.phase == .failed;
        unlock();
        for (notifications) |maybe_ref| if (maybe_ref) |reference| wake.notify(reference);
        for (releases) |maybe_ref| if (maybe_ref) |reference| wake.release(reference);
        if (failed) { notifyFailures(); return; }
    }
}
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateEventW(?*w.SECURITY_ATTRIBUTES, i32, i32, ?[*:0]const u16) callconv(.winapi) ?w.HANDLE;
    extern "kernel32" fn SetEvent(w.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn ResetEvent(w.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn WaitForMultipleObjects(u32, [*]const w.HANDLE, i32, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
    extern "kernel32" fn DuplicateHandle(w.HANDLE, w.HANDLE, w.HANDLE, *w.HANDLE, u32, i32, u32) callconv(.winapi) i32;
};
