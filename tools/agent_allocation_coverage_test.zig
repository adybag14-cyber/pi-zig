const std = @import("std");
const coverage = @import("agent_allocation_coverage.zig");
const graphs = coverage.graphs;
const State = coverage.State;
fn fixture(gpa: std.mem.Allocator, range: usize, shards: usize, total_delta: usize) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    try output.writer.writeAll("Build Summary: 2/2 steps succeeded; 28/28 tests passed\n");
    for (graphs, 0..) |graph, index| {
        const total = 127 + index * 11 + total_delta;
        const first = total * range / shards;
        const end = total * (range + 1) / shards;
        for (first..end) |allocation| {
            try output.writer.print("SDK_ALLOCATION_INDEX_BEGIN {s} {d}\nSDK_ALLOCATION_INDEX_COMPLETE {s} {d}\n", .{ graph, allocation, graph, allocation });
        }
        try output.writer.print("SDK_ALLOCATION_COMPLETE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ graph, range, shards, first, end, total });
    }
    return output.toOwnedSlice();
}

test "Agent runtime marker ingestion covers every macOS group without a global zero prerequisite" {
    const gpa = std.testing.allocator;
    for (0..8) |group| {
        var state = try State.init(64, group, 8);
        while (state.next < state.end) {
            const range = state.next;
            const log = try fixture(gpa, range, 64, 0);
            defer gpa.free(log);
            const rows = try state.ingest(gpa, log, range);
            for (rows, 0..) |row, graph| {
                try std.testing.expectEqual(range, row.range);
                try std.testing.expectEqual(@as(usize, 127 + graph * 11), state.totals[graph].?);
            }
        }
        try std.testing.expectEqual((group + 1) * 8, state.next);
    }
    var single = try State.init(8, 0, 1);
    while (single.next < single.end) {
        const log = try fixture(gpa, single.next, 8, 0);
        defer gpa.free(log);
        _ = try single.ingest(gpa, log, single.next);
    }
}

test "Agent runtime marker ingestion accepts genuine hosted macOS group three range twenty four" {
    var state = try State.init(64, 3, 8);
    const rows = try state.ingest(std.testing.allocator, @embedFile("fixtures/agent-range24-macos-debug-070367.log"), 24);
    try std.testing.expectEqual(@as(usize, 918), rows[0].total);
    try std.testing.expectEqual(@as(usize, 344), rows[0].start);
    try std.testing.expectEqual(@as(usize, 358), rows[0].end);
    try std.testing.expectEqual(@as(usize, 3791), rows[4].total);
}

test "Agent runtime marker ingestion rejects changed universes missing duplicate and reordered runtime indices" {
    const gpa = std.testing.allocator;
    const first = try fixture(gpa, 8, 64, 0);
    defer gpa.free(first);
    var state = try State.init(64, 1, 8);
    _ = try state.ingest(gpa, first, 8);
    const changed = try fixture(gpa, 9, 64, 1);
    defer gpa.free(changed);
    try std.testing.expectError(error.AllocationUniverseChanged, state.ingest(gpa, changed, 9));
    const duplicate = try std.mem.concat(gpa, u8, &.{ first, "SDK_ALLOCATION_COMPLETE agent-complete-metadata 8/64 range=[15,17) total=127\n" });
    defer gpa.free(duplicate);
    state = try State.init(64, 1, 8);
    try std.testing.expectError(error.DuplicateAllocationCompletion, state.ingest(gpa, duplicate, 8));
    const missing = try std.mem.replaceOwned(u8, gpa, first, "SDK_ALLOCATION_INDEX_COMPLETE agent-complete-metadata 15\n", "");
    defer gpa.free(missing);
    try std.testing.expectError(error.IncorrectAllocationIndexOrder, state.ingest(gpa, missing, 8));
    const reordered = try std.mem.replaceOwned(u8, gpa, first, "SDK_ALLOCATION_INDEX_BEGIN agent-complete-metadata 15", "SDK_ALLOCATION_INDEX_BEGIN agent-complete-metadata 16");
    defer gpa.free(reordered);
    try std.testing.expectError(error.IncorrectAllocationIndexOrder, state.ingest(gpa, reordered, 8));
    try std.testing.expectError(error.IncompleteAgentTestInventory, state.ingest(gpa, "", 8));
}
