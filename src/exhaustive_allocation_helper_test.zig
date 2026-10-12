const std = @import("std");
const sweep = @import("test_support/exhaustive_allocation_shards.zig");

test "exhaustive partitions run every original failure index once with the original allocator" {
    const Probe = struct {
        calls: usize = 0,
        success: usize = 0,
        failures: [3]usize = @splat(0),
        fn run(gpa: std.mem.Allocator, self: *@This()) !void {
            self.calls += 1;
            inline for (.{ 17, 31, 53 }, 0..) |size, index| {
                const memory = gpa.alloc(u8, size) catch |cause| {
                    self.failures[index] += 1;
                    return cause;
                };
                defer gpa.free(memory);
                @memset(memory, 42);
            }
            self.success += 1;
        }
    };
    var probe: Probe = .{};
    for (0..8) |index| try sweep.run(std.testing.allocator, .worker, "helper-unit", Probe.run, .{&probe}, index, 8);
    try std.testing.expectEqual(@as(usize, 11), probe.calls);
    try std.testing.expectEqual(@as(usize, 8), probe.success);
    for (probe.failures) |count| try std.testing.expectEqual(@as(usize, 1), count);
    probe = .{};
    try sweep.run(std.testing.allocator, .worker, "helper-unit", Probe.run, .{&probe}, 0, 1);
    try std.testing.expectEqual(@as(usize, 4), probe.calls);
    try std.testing.expectEqual(@as(usize, 1), probe.success);
    for (probe.failures) |count| try std.testing.expectEqual(@as(usize, 1), count);
}

test "exhaustive partitions retain swallowed OOM and nondeterministic allocation failures" {
    const Swallow = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const memory = gpa.alloc(u8, 8) catch return;
            defer gpa.free(memory);
        }
    };
    try std.testing.expectError(error.SwallowedOutOfMemoryError, sweep.run(std.testing.allocator, .worker, "helper-swallow", Swallow.run, .{}, 0, 1));
    const Vary = struct {
        fn run(gpa: std.mem.Allocator, calls: *usize) !void {
            calls.* += 1;
            if (calls.* > 1) return;
            const memory = try gpa.alloc(u8, 8);
            defer gpa.free(memory);
        }
    };
    var calls: usize = 0;
    try std.testing.expectError(error.NondeterministicMemoryUsage, sweep.run(std.testing.allocator, .worker, "helper-vary", Vary.run, .{&calls}, 0, 1));
}

test "exhaustive partitions cover nondivisible universes and reject invalid controls" {
    var previous: usize = 0;
    for (0..64) |index| {
        const range = try sweep.partition(3791, index, 64);
        try std.testing.expectEqual(previous, range.start);
        try std.testing.expect(range.end >= range.start);
        previous = range.end;
    }
    try std.testing.expectEqual(@as(usize, 3791), previous);
    try std.testing.expectError(error.InvalidAllocationShard, sweep.partition(17, 0, 0));
    try std.testing.expectError(error.InvalidAllocationShard, sweep.partition(17, 8, 8));
}
