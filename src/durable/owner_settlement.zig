//! A worker retains its ORIGINAL Session line until the owner acknowledges its
//! post-Transaction cache settlement. No JS values cross this channel. Closing
//! queued requests releases their workers; an admitted owner callback keeps its
//! lease until it returns, even when close reenters that callback.
const std = @import("std");
pub const Lease = struct { owner_generation: u64, worker_thread: std.Thread.Id, line_epoch: u32, success: bool };
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
