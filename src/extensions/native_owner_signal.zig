//! A native publication wakes its VM owner without waiting for the polling
//! interval. An epoch closes the race between the last pump and arming a wait.
const std = @import("std");
pub const Signal = struct {
    event: std.Io.Event = .unset,
    epoch: std.atomic.Value(u64) = .init(0),
    // Owner-only counters support failure diagnosis without retaining VM data.
    waits: u64 = 0,
    raced: u64 = 0,
    timeouts: u64 = 0,
    measure_wait: bool = false,
    blocked_ms: i64 = 0,

    pub fn observe(self: *const Signal) u64 {
        return self.epoch.load(.acquire);
    }
    /// Call after publishing work. This method invokes no VM operation and
    /// may be used by any leased worker while the owning Engine remains live.
    pub fn notify(self: *Signal, io: std.Io) void {
        _ = self.epoch.fetchAdd(1, .release);
        self.event.set(io);
    }
    /// The owner is the only waiter. Reset before checking the epoch: work
    /// published before or during the reset must not lose its wakeup.
    fn arm(self: *Signal, observed: u64) bool {
        self.event.reset();
        return self.observe() == observed;
    }
    pub fn waitAfter(self: *Signal, io: std.Io, observed: u64, timeout: std.Io.Timeout) !bool {
        self.waits += 1;
        if (!self.arm(observed)) {
            self.raced += 1;
            return true;
        }
        const began = if (self.measure_wait) std.Io.Clock.awake.now(io).toMilliseconds() else null;
        defer if (began) |start| {
            self.blocked_ms += std.Io.Clock.awake.now(io).toMilliseconds() - start;
        };
        self.event.waitTimeout(io, timeout) catch |err| switch (err) {
            error.Timeout => {
                self.timeouts += 1;
                return false;
            },
            else => return err,
        };
        return true;
    }
};

test "native owner notification arriving before wait arming cannot be reset away" {
    var signal: Signal = .{};
    const observed = signal.observe();
    signal.notify(std.testing.io);
    try std.testing.expect(!signal.arm(observed));
    try std.testing.expectEqual(observed + 1, signal.observe());
    // The consumed notification does not make later idle waits spin.
    try std.testing.expect(signal.arm(signal.observe()));
    try std.testing.expect(!signal.event.isSet());
}

test "native owner notification arriving after arming remains visible to the wait" {
    var signal: Signal = .{};
    const observed = signal.observe();
    try std.testing.expect(signal.arm(observed));
    signal.notify(std.testing.io);
    try signal.event.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } });
    try std.testing.expectEqual(observed + 1, signal.observe());
}

test "native owner worker publication is acquired before the owner resumes" {
    const Fixture = struct {
        signal: Signal = .{},
        gate: std.Io.Event = .unset,
        published: std.atomic.Value(u32) = .init(0),
        fn worker(self: *@This()) void {
            self.gate.waitUncancelable(std.testing.io);
            self.published.store(47, .monotonic);
            self.signal.notify(std.testing.io);
        }
    };
    var fixture: Fixture = .{};
    const worker = try std.Thread.spawn(.{}, Fixture.worker, .{&fixture});
    defer worker.join();
    const observed = fixture.signal.observe();
    fixture.gate.set(std.testing.io);
    try std.testing.expect(try fixture.signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .fromSeconds(1), .clock = .awake } }));
    try std.testing.expectEqual(@as(u32, 47), fixture.published.load(.acquire));
}

test "native owner timeout keeps the timer fallback without inventing a publication" {
    var signal: Signal = .{};
    const observed = signal.observe();
    try std.testing.expect(!try signal.waitAfter(std.testing.io, observed, .{ .duration = .{ .raw = .zero, .clock = .awake } }));
    try std.testing.expectEqual(observed, signal.observe());
}
