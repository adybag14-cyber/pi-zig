//! Contiguous exhaustive allocation coverage for bounded hosted test jobs.
const std = @import("std");
pub fn check(comptime body: anytype) !void {
    return checkNamed("codemode", body);
}
pub fn checkNamed(comptime label: []const u8, comptime body: anytype) !void {
    const shard_text = std.testing.environ.getAlloc(std.heap.page_allocator, "PI_CODEMODE_ALLOCATION_SHARD") catch |cause| {
        if (cause == error.EnvironmentVariableMissing) return std.testing.checkAllAllocationFailures(std.testing.allocator, body, .{});
        return cause;
    };
    defer std.heap.page_allocator.free(shard_text);
    const count_text = try std.testing.environ.getAlloc(std.heap.page_allocator, "PI_CODEMODE_ALLOCATION_SHARDS");
    defer std.heap.page_allocator.free(count_text);
    const shard = try std.fmt.parseInt(usize, shard_text, 10);
    const count = try std.fmt.parseInt(usize, count_text, 10);
    if (count == 0 or shard >= count) return error.InvalidAllocationShard;
    var baseline = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try body(baseline.allocator());
    try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
    const total = baseline.alloc_index;
    const start: usize = @intCast(@as(u128, total) * shard / count);
    const end: usize = @intCast(@as(u128, total) * (@as(u128, shard) + 1) / count);
    std.debug.print("CODEMODE_SHARD {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, count, start, end, total, label });
    for (start..end) |index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = index });
        if (body(failing.allocator())) |_| {
            if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
            return error.NondeterministicMemoryUsage;
        } else |cause| {
            if (cause != error.OutOfMemory) return cause;
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        }
    }
    std.debug.print("CODEMODE_SHARD_COMPLETE {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, count, start, end, total, label });
}
