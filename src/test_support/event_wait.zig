//! Predicate event wait: timed futex wakes may be spurious on any platform.
const std = @import("std");
pub const Waiter = struct {
    context: ?*anyopaque = null,
    now_fn: *const fn (?*anyopaque, std.Io) i64 = now,
    wait_fn: *const fn (?*anyopaque, *std.Io.Event, std.Io, i64) anyerror!void = wait,
    fn now(_: ?*anyopaque, io: std.Io) i64 {
        return std.Io.Clock.awake.now(io).toMilliseconds();
    }
    fn wait(_: ?*anyopaque, event: *std.Io.Event, io: std.Io, remaining: i64) !void {
        try event.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(remaining), .clock = .awake } });
    }
};

pub fn untilSet(io: std.Io, event: *std.Io.Event, timeout_ms: i64) !void {
    return untilSetWith(io, event, timeout_ms, .{});
}

fn untilSetWith(io: std.Io, event: *std.Io.Event, timeout_ms: i64, waiter: Waiter) !void {
    const deadline = waiter.now_fn(waiter.context, io) +| timeout_ms;
    while (!event.isSet()) {
        const remaining = deadline - waiter.now_fn(waiter.context, io);
        if (remaining <= 0) return error.Timeout;
        waiter.wait_fn(waiter.context, event, io, remaining) catch |err| switch (err) {
            error.Timeout => continue,
            else => return err,
        };
    }
}

test "event predicate retries spurious wakes with one absolute budget and preserves genuine timeout" {
    const Probe = struct {
        timestamp: i64 = 100,
        calls: usize = 0,
        remaining: [3]i64 = @splat(0),
        settle: bool,
        fn now(context: ?*anyopaque, _: std.Io) i64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return self.timestamp;
        }
        fn wait(context: ?*anyopaque, event: *std.Io.Event, io: std.Io, remaining: i64) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.remaining[self.calls] = remaining;
            self.calls += 1;
            if (self.settle and self.calls == 2) {
                event.set(io);
                return;
            }
            self.timestamp += 40;
            return error.Timeout;
        }
    };
    var completed: Probe = .{ .settle = true };
    var event: std.Io.Event = .unset;
    try untilSetWith(std.testing.io, &event, 100, .{ .context = &completed, .now_fn = Probe.now, .wait_fn = Probe.wait });
    try std.testing.expectEqual(@as(usize, 2), completed.calls);
    try std.testing.expectEqual(@as(i64, 100), completed.remaining[0]);
    try std.testing.expectEqual(@as(i64, 60), completed.remaining[1]);
    var expired: Probe = .{ .settle = false };
    var unset: std.Io.Event = .unset;
    try std.testing.expectError(error.Timeout, untilSetWith(std.testing.io, &unset, 100, .{ .context = &expired, .now_fn = Probe.now, .wait_fn = Probe.wait }));
    try std.testing.expectEqual(@as(usize, 3), expired.calls);
    try std.testing.expectEqual(@as(i64, 20), expired.remaining[2]);
}
