//! The original failure allocator and probe body, with complete bounded ranges.
const std = @import("std");
pub const Family = enum { codemode, worker, tui };
pub const Range = struct { index: usize, shards: usize, start: usize, end: usize, total: usize };

pub fn partition(total: usize, index: usize, shards: usize) !Range {
    if (shards == 0 or shards > 4096 or index >= shards) return error.InvalidAllocationShard;
    return .{ .index = index, .shards = shards, .start = @intCast(@as(u128, total) * index / shards), .end = @intCast(@as(u128, total) * (@as(u128, index) + 1) / shards), .total = total };
}

fn optionalEnv(comptime name: []const u8) !?[]u8 {
    return std.testing.environ.getAlloc(std.heap.page_allocator, name) catch |cause| switch (cause) {
        error.EnvironmentVariableMissing => null,
        else => return cause,
    };
}

pub fn check(comptime family: Family, comptime label: []const u8, comptime body: anytype, args: anytype) !void {
    var shard: usize = 0;
    var shards: usize = 1;
    const unified = try optionalEnv("PI_EXHAUSTIVE_ALLOCATION_SHARD");
    defer if (unified) |text| std.heap.page_allocator.free(text);
    const legacy: ?[]u8 = if (unified == null) switch (family) {
        .codemode => try optionalEnv("PI_CODEMODE_ALLOCATION_SHARD"),
        .tui => try optionalEnv("PI_TUI_ALLOCATION_SHARD"),
        .worker => null,
    } else null;
    defer if (legacy) |text| std.heap.page_allocator.free(text);
    if (unified orelse legacy) |text| {
        const count = if (unified != null)
            try std.testing.environ.getAlloc(std.heap.page_allocator, "PI_EXHAUSTIVE_ALLOCATION_SHARDS")
        else switch (family) {
            .codemode => try std.testing.environ.getAlloc(std.heap.page_allocator, "PI_CODEMODE_ALLOCATION_SHARDS"),
            .tui => try std.testing.environ.getAlloc(std.heap.page_allocator, "PI_TUI_ALLOCATION_SHARDS"),
            .worker => unreachable,
        };
        defer std.heap.page_allocator.free(count);
        shard = try std.fmt.parseInt(usize, text, 10);
        shards = try std.fmt.parseInt(usize, count, 10);
    }
    try run(std.testing.allocator, family, label, body, args, shard, shards);
}

pub fn run(backing: std.mem.Allocator, comptime family: Family, comptime label: []const u8, comptime body: anytype, args: anytype, shard: usize, shards: usize) !void {
    // Same unlimited baseline and fail_index universe as the standard exhaustive
    // checker. This is not a baseline-only mode and bypasses no allocation.
    _ = try partition(0, shard, shards);
    var baseline = std.testing.FailingAllocator.init(backing, .{});
    try @call(.auto, body, .{baseline.allocator()} ++ args);
    if (baseline.allocated_bytes != baseline.freed_bytes) return error.MemoryLeakDetected;
    const range = try partition(baseline.alloc_index, shard, shards);
    std.debug.print("EXHAUSTIVE_ALLOCATION_BASELINE {s} total={d}\n", .{ label, range.total });
    std.debug.print("EXHAUSTIVE_ALLOCATION_RANGE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ label, shard, shards, range.start, range.end, range.total });
    switch (family) {
        .codemode => std.debug.print("CODEMODE_SHARD {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, shards, range.start, range.end, range.total, label }),
        .tui => std.debug.print("TUI_ALLOCATION_RANGE {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, shards, range.start, range.end, range.total, label }),
        .worker => {},
    }
    for (range.start..range.end) |index| {
        std.debug.print("EXHAUSTIVE_ALLOCATION_INDEX_BEGIN {s} {d}\n", .{ label, index });
        var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = index });
        if (@call(.auto, body, .{failing.allocator()} ++ args)) |_| {
            if (failing.has_induced_failure) return error.SwallowedOutOfMemoryError;
            return error.NondeterministicMemoryUsage;
        } else |cause| {
            if (cause != error.OutOfMemory) return cause;
            if (failing.allocated_bytes != failing.freed_bytes) return error.MemoryLeakDetected;
        }
        std.debug.print("EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE {s} {d}\n", .{ label, index });
    }
    std.debug.print("EXHAUSTIVE_ALLOCATION_COMPLETE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ label, shard, shards, range.start, range.end, range.total });
    // Preserve older independent diagnostic workflows' complete receipt format.
    switch (family) {
        .codemode => std.debug.print("CODEMODE_SHARD_COMPLETE {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, shards, range.start, range.end, range.total, label }),
        .tui => std.debug.print("TUI_ALLOCATION_COMPLETE {d}/{d} range=[{d},{d}) total={d} label={s}\n", .{ shard, shards, range.start, range.end, range.total, label }),
        .worker => {},
    }
}
