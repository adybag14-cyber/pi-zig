//! One absolute timeout budget survives spurious timed-event wakes.
const std = @import("std");
/// A shared event cannot be reset while another ticket is still waiting. An
/// epoch plus a futex comparison makes simultaneous ticket waits independent
/// without allocating one wake object per retained request.
pub fn changed(io: std.Io, epoch: *std.atomic.Value(u32), observed: u32, deadline: std.Io.Timestamp) !void {
    if (epoch.load(.acquire) != observed) return;
    if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.Timeout;
    try io.futexWaitTimeout(u32, &epoch.raw, observed, .{ .deadline = .{ .raw = deadline, .clock = .awake } });
    if (epoch.load(.acquire) == observed and std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.Timeout;
}
const Waiter = struct {
    context: ?*anyopaque = null,
    now: *const fn (?*anyopaque, std.Io) std.Io.Timestamp = currentTime,
    wait: *const fn (?*anyopaque, std.Io, *std.Io.Event, std.Io.Timestamp) anyerror!void = waitEvent,
    fn currentTime(_: ?*anyopaque, io: std.Io) std.Io.Timestamp {
        return std.Io.Clock.awake.now(io);
    }
    fn waitEvent(_: ?*anyopaque, io: std.Io, event: *std.Io.Event, deadline: std.Io.Timestamp) !void {
        try event.waitTimeout(io, .{ .deadline = .{ .raw = deadline, .clock = .awake } });
    }
};
pub fn wake(io: std.Io, event: *std.Io.Event, deadline: std.Io.Timestamp) !void {
    return wakeWith(io, event, deadline, .{});
}
fn wakeWith(io: std.Io, event: *std.Io.Event, deadline: std.Io.Timestamp, waiter: Waiter) !void {
    // A different ticket may reset this shared event after its wake. Always
    // return to the caller's protected reply/sync predicate after a wake;
    // waiting for the event bit again could hide an already-queued reply.
    waiter.wait(waiter.context, io, event, deadline) catch |err| switch (err) {
        error.Timeout => if (waiter.now(waiter.context, io).nanoseconds >= deadline.nanoseconds) return err,
        else => return err,
    };
}
test "native daemon event waits tolerate spurious Timeout preserve absolute expiry and propagate cancellation" {
    const Peer = struct {
        calls: usize = 0,
        nanos: i96 = 0,
        settle: bool,
        cancel: bool = false,
        consumed_wake: bool = false,
        fn now(raw: ?*anyopaque, _: std.Io) std.Io.Timestamp {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return .{ .nanoseconds = self.nanos };
        }
        fn wait(raw: ?*anyopaque, io: std.Io, event: *std.Io.Event, deadline: std.Io.Timestamp) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(@as(i96, 100), deadline.nanoseconds);
            self.calls += 1;
            if (self.cancel) return error.Canceled;
            if (self.consumed_wake) return;
            self.nanos += 40;
            if (self.settle and self.calls == 2) event.set(io);
            return error.Timeout;
        }
    };
    var peer: Peer = .{ .settle = true };
    var event: std.Io.Event = .unset;
    while (!event.isSet()) try wakeWith(std.testing.io, &event, .{ .nanoseconds = 100 }, .{ .context = &peer, .now = Peer.now, .wait = Peer.wait });
    try std.testing.expectEqual(@as(usize, 2), peer.calls);
    var expired: Peer = .{ .settle = false };
    var unset: std.Io.Event = .unset;
    for (0..2) |_| try wakeWith(std.testing.io, &unset, .{ .nanoseconds = 100 }, .{ .context = &expired, .now = Peer.now, .wait = Peer.wait });
    try std.testing.expectError(error.Timeout, wakeWith(std.testing.io, &unset, .{ .nanoseconds = 100 }, .{ .context = &expired, .now = Peer.now, .wait = Peer.wait }));
    try std.testing.expectEqual(@as(usize, 3), expired.calls);
    var canceled: Peer = .{ .settle = false, .cancel = true };
    try std.testing.expectError(error.Canceled, wakeWith(std.testing.io, &unset, .{ .nanoseconds = 100 }, .{ .context = &canceled, .now = Peer.now, .wait = Peer.wait }));
    var consumed: Peer = .{ .settle = false, .consumed_wake = true };
    try wakeWith(std.testing.io, &unset, .{ .nanoseconds = 100 }, .{ .context = &consumed, .now = Peer.now, .wait = Peer.wait });
    try std.testing.expectEqual(@as(usize, 1), consumed.calls);
    try std.testing.expect(!unset.isSet());
}
