//! A worker retains its ORIGINAL Session line until the owner acknowledges its
//! owner settlement. A dedicated caller may instead retain its still-active
//! Transaction for pre-Storage cleanup. No JS values cross this channel. Closing
//! queued requests releases their workers; an admitted owner callback keeps its
//! lease until it returns, even when close reenters that callback.
const std = @import("std");
pub const Cleanup = struct {
    transaction: *@import("session.zig").Transaction,
    record: @import("backend/json.zig").Value,
    outcome: @import("backend/json.zig").Value,
};
pub const FaultMessage = struct {
    transaction: *@import("session.zig").Transaction,
    invocation_key: usize,
    task_id: u64,
    phase_generation: u64,
    message: ?@import("backend/json.zig").Owned = null,
};
pub const StorageHook = enum { before, after };
pub const Assembly = struct { transaction: *@import("session.zig").Transaction, hook: StorageHook, native_frame: ?*const anyopaque = null };
pub const Lease = struct { owner_generation: u64, worker_thread: std.Thread.Id, line_epoch: u32, success: bool, cleanup: ?*const Cleanup = null, fault_message: ?*FaultMessage = null, assembly: ?*const Assembly = null };
pub const Dispatch = *const fn (?*anyopaque, Lease) anyerror!void;
pub const Notify = struct { context: ?*anyopaque = null, call: ?*const fn (?*anyopaque) void = null };
const Request = struct {
    lease: Lease,
    done: std.Io.Event = .unset,
    mutex: std.Io.Mutex = .init,
    failure: ?anyerror = null,
    refs: std.atomic.Value(usize) = .init(2),
    fn settle(self: *Request, io: std.Io, failure: ?anyerror) void {
        self.mutex.lockUncancelable(io);
        self.failure = failure;
        self.done.set(io);
        self.mutex.unlock(io);
    }
    fn release(self: *Request) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) std.heap.page_allocator.destroy(self);
    }
};
pub const Channel = struct {
    io: std.Io,
    owner: std.Thread.Id,
    generation: u64,
    notify: Notify,
    mutex: std.Io.Mutex = .init,
    queue: std.ArrayList(*Request) = .empty,
    active: usize = 0,
    calls: std.atomic.Value(usize) = .init(0),
    closed: bool = false,
    pub fn init(io: std.Io, generation: u64, notify: Notify) Channel {
        return .{ .io = io, .owner = std.Thread.getCurrentId(), .generation = generation, .notify = notify };
    }
    pub fn deinit(self: *Channel) void {
        std.debug.assert(std.Thread.getCurrentId() == self.owner);
        self.close();
        std.debug.assert(self.active == 0 and self.calls.load(.acquire) == 0);
        self.queue.deinit(std.heap.page_allocator);
    }
    pub fn pending(self: *Channel) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.queue.items.len;
    }
    pub fn close(self: *Channel) void {
        std.debug.assert(std.Thread.getCurrentId() == self.owner);
        self.mutex.lockUncancelable(self.io);
        if (self.closed) {
            self.mutex.unlock(self.io);
            return;
        }
        self.closed = true;
        for (self.queue.items) |request| {
            request.settle(self.io, error.OwnerSettlementClosed);
            request.release();
        }
        self.queue.clearRetainingCapacity();
        self.mutex.unlock(self.io);
        // Do not acknowledge an active callback here. Its worker must retain
        // the line until that owner's last tracker/getter access has unwound.
        if (self.notify.call) |notify| notify(self.notify.context);
    }
    pub fn call(self: *Channel, lease: Lease) !void {
        if (std.Thread.getCurrentId() == self.owner) return error.OwnerSettlementCallOnOwner;
        if (lease.worker_thread != std.Thread.getCurrentId()) return error.OwnerSettlementWrongWorker;
        const request = try std.heap.page_allocator.create(Request);
        request.* = .{ .lease = lease };
        var queued = false;
        errdefer if (!queued) std.heap.page_allocator.destroy(request);
        self.mutex.lockUncancelable(self.io);
        if (self.closed) {
            self.mutex.unlock(self.io);
            return error.OwnerSettlementClosed;
        }
        self.queue.append(std.heap.page_allocator, request) catch |err| {
            self.mutex.unlock(self.io);
            return err;
        };
        queued = true;
        _ = self.calls.fetchAdd(1, .acq_rel);
        self.mutex.unlock(self.io);
        defer _ = self.calls.fetchSub(1, .acq_rel);
        defer request.release();
        if (self.notify.call) |notify| notify(self.notify.context);
        request.done.waitUncancelable(self.io);
        request.mutex.lockUncancelable(self.io);
        defer request.mutex.unlock(self.io);
        if (request.failure) |failure| return failure;
    }
    pub fn drain(self: *Channel, dispatch: Dispatch, context: ?*anyopaque) !bool {
        if (std.Thread.getCurrentId() != self.owner) return error.OwnerSettlementDrainOnWorker;
        var worked = false;
        while (true) {
            self.mutex.lockUncancelable(self.io);
            if (self.queue.items.len == 0) {
                self.mutex.unlock(self.io);
                return worked;
            }
            const request = self.queue.orderedRemove(0);
            self.mutex.unlock(self.io);
            self.active += 1;
            defer {
                self.active -= 1;
                request.release();
            }
            worked = true;
            if (request.lease.owner_generation != self.generation) {
                request.settle(self.io, error.StaleSettlementOwnerGeneration);
                continue;
            }
            dispatch(context, request.lease) catch |err| {
                request.settle(self.io, err);
                continue;
            };
            request.settle(self.io, null);
        }
    }
};

test "owner settlement assembly hooks retain sealed original line and restore before failure or reentrant close ACK" {
    for ([_]enum { normal, before_failure, after_failure, reentrant_close }{ .normal, .before_failure, .after_failure, .reentrant_close }) |mode| try assemblyExercise(@intFromEnum(mode));
}
fn assemblyExercise(mode: u8) !void {
    const backend = @import("backend/root.zig");
    const session_mod = @import("session.zig");
    var memory = try backend.memory.Memory.init(std.testing.allocator);
    defer memory.deinit();
    var session = session_mod.Session.init(std.testing.allocator, std.testing.io, .{ .memory = &memory });
    defer session.deinit();
    var channel = Channel.init(std.testing.io, 91, .{});
    defer channel.deinit();
    const Probe = struct {
        session: *session_mod.Session,
        channel: *Channel,
        mode: u8,
        tx: ?*session_mod.Transaction = null,
        failure: ?anyerror = null,
        done: std.atomic.Value(bool) = .init(false),
        before: bool = false,
        after: bool = false,
        active_control: bool = false,
        restored: bool = true,
        epoch: ?u32 = null,
        fn request(self: *@This(), hook: StorageHook) !void {
            var frame: Assembly = .{ .transaction = self.tx.?, .hook = hook };
            defer self.restored = self.restored and self.tx.?.ownerThread == std.Thread.getCurrentId();
            try self.channel.call(.{ .owner_generation = 91, .worker_thread = std.Thread.getCurrentId(), .line_epoch = self.session.line_epoch.load(.acquire), .success = true, .assembly = &frame });
        }
        fn beforeStorage(raw: ?*anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return self.request(.before);
        }
        fn afterStorage(raw: ?*anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return self.request(.after);
        }
        fn operation(raw: ?*anyopaque, tx: *session_mod.Transaction, _: @import("types.zig").Context) !backend.json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.tx = tx.retain();
            var frame: Assembly = .{ .transaction = tx, .hook = .before };
            const worker = std.Thread.getCurrentId();
            const epoch = self.session.line_epoch.load(.acquire);
            try std.testing.expectError(error.OwnerSettlementWrongWorker, self.channel.call(.{ .owner_generation = 91, .worker_thread = self.channel.owner, .line_epoch = epoch, .success = true, .assembly = &frame }));
            try std.testing.expectError(error.StaleSettlementOwnerGeneration, self.channel.call(.{ .owner_generation = 90, .worker_thread = worker, .line_epoch = epoch, .success = true, .assembly = &frame }));
            try std.testing.expectError(error.StaleTransactionOwnerLine, self.channel.call(.{ .owner_generation = 91, .worker_thread = worker, .line_epoch = epoch +% 1, .success = true, .assembly = &frame }));
            try self.request(.before); // Active Tx must reject sealed delegation.
            _ = try tx.createRootConversation();
            tx.before_storage = beforeStorage;
            tx.before_storage_context = self;
            tx.after_storage = afterStorage;
            tx.after_storage_context = self;
            return .null;
        }
        fn run(self: *@This()) void {
            defer self.done.store(true, .release);
            var result = self.session.commit(operation, self, .{}, .{}) catch |err| {
                self.failure = err;
                return;
            };
            result.deinit();
        }
        fn owner(raw: ?*anyopaque, lease: Lease) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const tx = lease.assembly.?.transaction;
            if (self.session.line_epoch.load(.acquire) != lease.line_epoch) return error.StaleTransactionOwnerLine;
            try std.testing.expectEqual(lease.worker_thread, self.session.ownerThread.load(.acquire));
            try std.testing.expect(self.session.mutex.tryLock());
            self.session.mutex.unlock(self.session.io);
            try std.testing.expect(self.session.storage.backend_mutex.tryLock());
            self.session.storage.backend_mutex.unlock(self.session.io);
            if (tx.active) {
                try std.testing.expectError(error.TransactionNotSealed, tx.delegateAssemblyOwner(self.channel.owner, lease.worker_thread, lease.line_epoch));
                self.active_control = true;
                return;
            }
            self.epoch = lease.line_epoch;
            try std.testing.expectError(error.WrongDelegatedTransactionOwner, tx.delegateAssemblyOwner(lease.worker_thread, lease.worker_thread, lease.line_epoch));
            try std.testing.expectError(error.StaleTransactionOwnerLine, tx.delegateAssemblyOwner(self.channel.owner, lease.worker_thread, lease.line_epoch +% 1));
            try std.testing.expectError(error.TransactionClosed, tx.delegateOwner(self.channel.owner, lease.worker_thread, lease.line_epoch));
            const execution = try tx.delegateAssemblyOwner(self.channel.owner, lease.worker_thread, lease.line_epoch);
            defer execution.restore();
            try std.testing.expect(!tx.active);
            try std.testing.expectError(error.TransactionClosed, tx.createRootConversation());
            if (lease.assembly.?.hook == .before) {
                try std.testing.expect(tx.committed_seq == null);
                self.before = true;
                if (self.mode == 1) return error.OriginalAssemblyHookFailure;
                if (self.mode == 3) self.channel.close();
            } else {
                try std.testing.expect(tx.committed_seq != null and self.before);
                self.after = true;
                if (self.mode == 2) return error.OriginalAssemblyHookFailure;
            }
        }
    };
    var probe: Probe = .{ .session = &session, .channel = &channel, .mode = mode };
    const worker = try std.Thread.spawn(.{}, Probe.run, .{&probe});
    var joined = false;
    defer if (!joined) {
        channel.close();
        worker.join();
    };
    while (!probe.done.load(.acquire)) {
        _ = try channel.drain(Probe.owner, &probe);
        try std.testing.io.sleep(.fromMilliseconds(1), .awake);
    }
    worker.join();
    joined = true;
    const tx = probe.tx orelse return error.MissingAssemblyTransaction;
    defer tx.release();
    try std.testing.expect(probe.restored and probe.active_control and probe.before);
    try std.testing.expect(!tx.active and session.ownerThread.load(.acquire) == 0);
    try std.testing.expect(session.line_epoch.load(.acquire) != probe.epoch.?);
    try std.testing.expectEqual(mode != 1 and mode != 3, probe.after);
    if (mode == 0) try std.testing.expect(probe.failure == null) else try std.testing.expectEqual(if (mode == 3) error.OwnerSettlementClosed else error.OriginalAssemblyHookFailure, probe.failure.?);
    try std.testing.expectEqual(@as(usize, if (mode == 1) 0 else 1), memory.state.rows.count());
    try std.testing.expectEqual(@as(usize, 0), channel.active);
    try std.testing.expectEqual(@as(usize, 0), channel.calls.load(.acquire));
}

test "owner settlement cleanup retains an active original Transaction until owner mutation and reentrant close finish" {
    try cleanupExecutionExercise(false);
    try cleanupExecutionExercise(true);
}
fn cleanupExecutionExercise(reject: bool) !void {
    const backend = @import("backend/root.zig");
    const session_mod = @import("session.zig");
    var store = try backend.memory.Memory.init(std.testing.allocator);
    defer store.deinit();
    var session = session_mod.Session.init(std.testing.allocator, std.testing.io, .{ .memory = &store });
    defer session.deinit();
    var channel = Channel.init(std.testing.io, 77, .{});
    defer channel.deinit();
    const Probe = struct {
        session: *session_mod.Session,
        channel: *Channel,
        returned: std.atomic.Value(bool) = .init(false),
        failure: ?anyerror = null,
        reject: bool,
        restored: bool = false,
        fn operation(raw: ?*anyopaque, tx: *session_mod.Transaction, _: @import("types.zig").Context) !backend.json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var frame: Cleanup = .{ .transaction = tx.retain(), .record = .null, .outcome = .null };
            defer frame.transaction.release();
            self.channel.call(.{ .owner_generation = 77, .worker_thread = std.Thread.getCurrentId(), .line_epoch = self.session.line_epoch.load(.acquire), .success = true, .cleanup = &frame }) catch |err| {
                self.restored = tx.active and tx.ownerThread == std.Thread.getCurrentId() and self.session.ownerThread.load(.acquire) == std.Thread.getCurrentId();
                return err;
            };
            self.restored = tx.active and tx.ownerThread == std.Thread.getCurrentId() and self.session.ownerThread.load(.acquire) == std.Thread.getCurrentId();
            return .null;
        }
        fn run(self: *@This()) void {
            var result = self.session.commit(operation, self, .{}, .{}) catch |err| {
                self.failure = err;
                self.returned.store(true, .release);
                return;
            };
            result.deinit();
            self.returned.store(true, .release);
        }
        fn owner(raw: ?*anyopaque, lease: Lease) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const tx = lease.cleanup.?.transaction;
            try std.testing.expect(tx.active and tx.session == self.session);
            try std.testing.expectEqual(lease.worker_thread, self.session.ownerThread.load(.acquire));
            try std.testing.expectEqual(lease.line_epoch, self.session.line_epoch.load(.acquire));
            try std.testing.expect(self.session.mutex.tryLock());
            self.session.mutex.unlock(self.session.io);
            try std.testing.expect(self.session.storage.backend_mutex.tryLock());
            self.session.storage.backend_mutex.unlock(self.session.io);
            try std.testing.expectError(error.WrongDelegatedTransactionOwner, tx.delegateOwner(lease.worker_thread, lease.worker_thread, lease.line_epoch));
            try std.testing.expectError(error.StaleTransactionOwnerLine, tx.delegateOwner(std.Thread.getCurrentId(), lease.worker_thread, lease.line_epoch +% 1));
            const execution = try tx.delegateOwner(std.Thread.getCurrentId(), lease.worker_thread, lease.line_epoch);
            defer execution.restore();
            _ = try tx.createRootConversation();
            self.channel.close();
            try std.testing.expect(tx.active);
            try std.testing.expect(!self.returned.load(.acquire));
            if (self.reject) return error.OriginalCleanupFailure;
        }
    };
    var probe: Probe = .{ .session = &session, .channel = &channel, .reject = reject };
    const worker = try std.Thread.spawn(.{}, Probe.run, .{&probe});
    defer worker.join();
    while (channel.pending() == 0 and !probe.returned.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(try channel.drain(Probe.owner, &probe));
    while (!probe.returned.load(.acquire)) std.atomic.spinLoopHint();
    try std.testing.expect(probe.restored);
    if (reject) {
        try std.testing.expectEqual(error.OriginalCleanupFailure, probe.failure.?);
    } else {
        if (probe.failure) |err| std.debug.print("Actual active cleanup worker error: {s}\n", .{@errorName(err)});
        try std.testing.expect(probe.failure == null);
    }
    try std.testing.expectEqual(@as(usize, if (reject) 0 else 1), store.state.rows.count());
}

test "owner settlement keeps admitted worker lease through reentrant close and rejects stale owners" {
    const io = std.testing.io;
    var channel = Channel.init(io, 7, .{});
    defer channel.deinit();
    const Worker = struct {
        channel: *Channel,
        generation: u64,
        completed: std.atomic.Value(bool) = .init(false),
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            self.channel.call(.{ .owner_generation = self.generation, .worker_thread = std.Thread.getCurrentId(), .line_epoch = 3, .success = true }) catch |err| {
                self.failure = err;
            };
            self.completed.store(true, .release);
        }
    };
    const Owner = struct {
        fn dispatch(raw: ?*anyopaque, lease: Lease) !void {
            const worker: *Worker = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(@as(u32, 3), lease.line_epoch);
            worker.channel.close();
            try std.testing.expect(!worker.completed.load(.acquire));
        }
    };
    var worker: Worker = .{ .channel = &channel, .generation = 7 };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (channel.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    _ = try channel.drain(Owner.dispatch, &worker);
    thread.join();
    try std.testing.expect(worker.completed.load(.acquire));
    try std.testing.expect(worker.failure == null);

    var stale_channel = Channel.init(io, 7, .{});
    defer stale_channel.deinit();
    worker = .{ .channel = &stale_channel, .generation = 6 };
    const stale_thread = try std.Thread.spawn(.{}, Worker.run, .{&worker});
    while (stale_channel.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    _ = try stale_channel.drain(Owner.dispatch, &worker);
    stale_thread.join();
    try std.testing.expectEqual(error.StaleSettlementOwnerGeneration, worker.failure.?);
}

test "owner settlement original line acknowledges before a newer worker holds the next publication" {
    const session_mod = @import("session.zig");
    const backend = @import("backend/root.zig");
    const types = @import("types.zig");
    const io = std.testing.io;
    var store = try backend.memory.Memory.init(std.testing.allocator);
    defer store.deinit();
    var session = session_mod.Session.init(std.testing.allocator, io, .{ .memory = &store });
    defer session.deinit();
    var channel = Channel.init(io, 41, .{});
    defer channel.deinit();
    const State = struct {
        session: *session_mod.Session,
        channel: *Channel,
        newer_entered: std.Io.Event = .unset,
        release_newer: std.Io.Event = .unset,
        owner_settled: usize = 0,
        first_epoch: ?u32 = null,
        first_transaction: ?*session_mod.Transaction = null,
        second_transaction: ?*session_mod.Transaction = null,
        first_failure: ?anyerror = null,
        second_failure: ?anyerror = null,
        owner_failure: ?anyerror = null,
        fn commitFirst(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !backend.json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.first_transaction = tx.retain();
            return .null;
        }
        fn commitSecond(raw: ?*anyopaque, tx: *session_mod.Transaction, _: types.Context) !backend.json.Value {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.second_transaction = tx.retain();
            self.newer_entered.set(self.session.io);
            // This newer real Transaction retains the next mutation line until
            // the owner releases its publication. Owner must never reacquire it
            // to finish cache work belonging to the previous operation.
            self.release_newer.waitUncancelable(self.session.io);
            return .null;
        }
        fn first(self: *@This()) void {
            var result = self.session.commit(commitFirst, self, .{}, .{}) catch |err| {
                self.first_failure = err;
                return;
            };
            result.deinit();
        }
        fn second(self: *@This()) void {
            var result = self.session.commit(commitSecond, self, .{}, .{}) catch |err| {
                self.second_failure = err;
                return;
            };
            result.deinit();
        }
        fn after(raw: ?*anyopaque, success: bool) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try self.channel.call(.{ .owner_generation = 41, .worker_thread = std.Thread.getCurrentId(), .line_epoch = self.session.line_epoch.load(.acquire), .success = success });
        }
        fn noOp(_: ?*anyopaque, _: *session_mod.Transaction, _: types.Context) !backend.json.Value {
            return .null;
        }
        fn settle(raw: ?*anyopaque, lease: Lease) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.settleOwned(lease) catch |err| {
                self.owner_failure = err;
                return err;
            };
        }
        fn settleOwned(self: *@This(), lease: Lease) !void {
            try std.testing.expect(lease.success);
            try std.testing.expectEqual(lease.worker_thread, self.session.ownerThread.load(.acquire));
            try std.testing.expectEqual(lease.line_epoch, self.session.line_epoch.load(.acquire));
            try std.testing.expect(self.session.mutex.tryLock());
            self.session.mutex.unlock(self.session.io);
            try std.testing.expect(self.channel.mutex.tryLock());
            self.channel.mutex.unlock(self.session.io);
            try std.testing.expect((try self.session.tryRead(noOp, null, .{}, .{})) == null);
            if (self.owner_settled == 0) {
                try std.testing.expect(!self.first_transaction.?.active);
                self.first_epoch = lease.line_epoch;
            } else {
                try std.testing.expect(!self.second_transaction.?.active);
                try std.testing.expect(self.first_epoch.? != lease.line_epoch);
            }
            self.owner_settled += 1;
        }
    };
    var state: State = .{ .session = &session, .channel = &channel };
    session.owner_settlement = .{ .callback = State.after, .context = &state };
    const first = try std.Thread.spawn(.{}, State.first, .{&state});
    var first_joined = false;
    var second_thread: ?std.Thread = null;
    var second_joined = false;
    defer {
        state.release_newer.set(io);
        channel.close();
        if (!first_joined) first.join();
        if (!second_joined) if (second_thread) |thread| thread.join();
        if (state.first_transaction) |tx| tx.release();
        if (state.second_transaction) |tx| tx.release();
        session.owner_settlement = null;
    }
    while (channel.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    second_thread = try std.Thread.spawn(.{}, State.second, .{&state});
    try std.testing.expect(try channel.drain(State.settle, &state));
    if (state.owner_failure) |err| return err;
    state.newer_entered.waitUncancelable(io);
    first.join();
    first_joined = true;
    try std.testing.expect(state.first_failure == null);
    try std.testing.expectEqual(@as(usize, 1), state.owner_settled);
    try std.testing.expect(state.second_transaction.?.active);
    // The owner has already completed the first settlement although a newer
    // worker now owns the line and awaits an owner-side publication release.
    try std.testing.expect((try session.tryRead(State.noOp, null, .{}, .{})) == null);
    state.release_newer.set(io);
    while (channel.pending() == 0) try io.sleep(.fromMilliseconds(1), .awake);
    try std.testing.expect(try channel.drain(State.settle, &state));
    if (state.owner_failure) |err| return err;
    second_thread.?.join();
    second_joined = true;
    try std.testing.expect(state.second_failure == null);
    try std.testing.expectEqual(@as(usize, 2), state.owner_settled);
    try std.testing.expectEqual(@as(std.Thread.Id, 0), session.ownerThread.load(.acquire));
}
