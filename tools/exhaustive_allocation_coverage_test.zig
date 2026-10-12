const std = @import("std");
const coverage = @import("exhaustive_allocation_coverage.zig");
const graphs = coverage.graphs;

// Unit marker data exercises ingestion; it is not a hosted VM qualification.
fn fixture(gpa: std.mem.Allocator, range: usize, shards: usize, delta: usize) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    for (graphs, 0..) |graph, slot| {
        const total = 127 + slot * 11 + delta;
        const first = total * range / shards;
        const end = total * (range + 1) / shards;
        try output.writer.print("EXHAUSTIVE_ALLOCATION_BASELINE {s} total={d}\nEXHAUSTIVE_ALLOCATION_RANGE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ graph, total, graph, range, shards, first, end, total });
        for (first..end) |index| try output.writer.print("EXHAUSTIVE_ALLOCATION_INDEX_BEGIN {s} {d}\nEXHAUSTIVE_ALLOCATION_INDEX_COMPLETE {s} {d}\n", .{ graph, index, graph, index });
        try output.writer.print("EXHAUSTIVE_ALLOCATION_COMPLETE {s} {d}/{d} range=[{d},{d}) total={d}\n", .{ graph, range, shards, first, end, total });
    }
    return output.toOwnedSlice();
}

test "exhaustive runtime ingestion covers all six graphs and every index across eight groups" {
    const gpa = std.testing.allocator;
    var ends: [graphs.len]usize = @splat(0);
    for (0..8) |group| {
        var state = try coverage.State.init(64, group, 8);
        while (state.next < state.end) {
            const range = state.next;
            const log = try fixture(gpa, range, 64, 0);
            defer gpa.free(log);
            const rows = try state.ingest(gpa, log, range);
            for (rows, 0..) |row, graph| {
                try std.testing.expectEqual(ends[graph], row.start);
                ends[graph] = row.end;
            }
        }
    }
    for (ends, 0..) |end, graph| try std.testing.expectEqual(@as(usize, 127 + graph * 11), end);
    var full = try coverage.State.init(1, 0, 1);
    const log = try fixture(gpa, 0, 1, 0);
    defer gpa.free(log);
    const rows = try full.ingest(gpa, log, 0);
    for (rows) |row| {
        try std.testing.expectEqual(@as(usize, 0), row.start);
        try std.testing.expectEqual(row.total, row.end);
    }
}

test "exhaustive runtime ingestion rejects baseline-only missing duplicated and changed universes" {
    const gpa = std.testing.allocator;
    var state = try coverage.State.init(64, 1, 8);
    try std.testing.expectError(error.MissingAllocationCompletion, state.ingest(gpa, "EXHAUSTIVE_ALLOCATION_BASELINE codemode-host total=127\n", 8));
    const first = try fixture(gpa, 8, 64, 0);
    defer gpa.free(first);
    const missing = try std.mem.replaceOwned(u8, gpa, first, "EXHAUSTIVE_ALLOCATION_BASELINE codemode-host total=127\n", "");
    defer gpa.free(missing);
    try std.testing.expectError(error.MissingAllocationBaseline, state.ingest(gpa, missing, 8));
    const duplicate = try std.mem.concat(gpa, u8, &.{ first, "EXHAUSTIVE_ALLOCATION_BASELINE codemode-host total=127\n" });
    defer gpa.free(duplicate);
    try std.testing.expectError(error.DuplicateAllocationBaseline, state.ingest(gpa, duplicate, 8));
    _ = try state.ingest(gpa, first, 8);
    const changed = try fixture(gpa, 9, 64, 1);
    defer gpa.free(changed);
    try std.testing.expectError(error.AllocationUniverseChanged, state.ingest(gpa, changed, 9));
}

test "exhaustive runtime ingestion refuses omitted and repeated individual failure indices" {
    const gpa = std.testing.allocator;
    var state = try coverage.State.init(64, 1, 8);
    const first = try fixture(gpa, 8, 64, 0);
    defer gpa.free(first);
    const missing = try std.mem.replaceOwned(u8, gpa, first, "EXHAUSTIVE_ALLOCATION_INDEX_COMPLETE codemode-host 16\n", "");
    defer gpa.free(missing);
    try std.testing.expectError(error.MissingAllocationIndex, state.ingest(gpa, missing, 8));
    const duplicate = try std.mem.concat(gpa, u8, &.{ first, "EXHAUSTIVE_ALLOCATION_INDEX_BEGIN codemode-host 15\nEXHAUSTIVE_ALLOCATION_INDEX_COMPLETE codemode-host 15\n" });
    defer gpa.free(duplicate);
    try std.testing.expectError(error.IncorrectAllocationIndexOrder, state.ingest(gpa, duplicate, 8));
    const bad_baseline = try std.mem.replaceOwned(u8, gpa, first, "EXHAUSTIVE_ALLOCATION_BASELINE codemode-host total=127", "EXHAUSTIVE_ALLOCATION_BASELINE codemode-host total=128");
    defer gpa.free(bad_baseline);
    try std.testing.expectError(error.AllocationBaselineChanged, state.ingest(gpa, bad_baseline, 8));
}

test "exhaustive runtime ingestion rejects genuine failed macOS allocation timeout output" {
    var state = try coverage.State.init(64, 0, 8);
    try std.testing.expectError(error.MissingAllocationCompletion, state.ingest(std.testing.allocator, @embedFile("fixtures/exhaustive-macos-debug-a3b96ad-timeouts.log"), 0));
}
