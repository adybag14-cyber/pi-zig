//! Exhaustive SDK failure indices, optionally partitioned for hosted runners.
const std = @import("std");

pub fn check(comptime label: []const u8, comptime body: anytype, args: anytype) !void {
    var shard: usize = 0;
    var count: usize = 1;
    const shard_text: ?[]u8 = std.testing.environ.getAlloc(std.heap.page_allocator, "PI_SDK_ALLOCATION_SHARD") catch |cause| switch (cause) {
        error.EnvironmentVariableMissing => null,
        else => return cause,
    };
    defer if (shard_text) |text| std.heap.page_allocator.free(text);
    if (shard_text) |text| {
        const count_text = try std.testing.environ.getAlloc(std.heap.page_allocator, "PI_SDK_ALLOCATION_SHARDS");
        defer std.heap.page_allocator.free(count_text);
        shard = try std.fmt.parseInt(usize, text, 10);
        count = try std.fmt.parseInt(usize, count_text, 10);
    }
    if (count == 0 or shard >= count) return error.InvalidSdkAllocationShard;
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try @call(.auto, body, .{baseline.allocator()} ++ args);
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    const total = baseline.alloc_index;
    const start: usize = @intCast(@as(u128, total) * shard / count);
    const end: usize = @intCast(@as(u128, total) * (@as(u128, shard) + 1) / count);
    const trace: ?[]u8 = std.testing.environ.getAlloc(std.heap.page_allocator, "PI_SDK_ALLOCATION_TRACE") catch |cause| switch (cause) {
        error.EnvironmentVariableMissing => null,
        else => return cause,
    };
    defer if (trace) |value| std.heap.page_allocator.free(value);
    std.debug.print("SDK_ALLOCATION_RANGE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ label, shard, count, start, end, total });
    for (start..end) |index| {
        if (trace != null) std.debug.print("SDK_ALLOCATION_INDEX_BEGIN {s} {d}\n", .{ label, index });
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        if (@call(.auto, body, .{failing.allocator()} ++ args)) |_| {
            if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
            return error.NondeterministicMemoryUsage;
        } else |cause| {
            if (cause != error.OutOfMemory) return cause;
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
        if (trace != null) std.debug.print("SDK_ALLOCATION_INDEX_COMPLETE {s} {d}\n", .{ label, index });
    }
    std.debug.print("SDK_ALLOCATION_COMPLETE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ label, shard, count, start, end, total });
}
