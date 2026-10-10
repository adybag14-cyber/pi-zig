//! Fail closed unless every named allocation sweep completes every range.
const std = @import("std");
const labels = [_][]const u8{ "codemode-host", "codemode-workers", "codemode-discovery", "codemode-adapter", "codemode-models" };
const Record = struct { total: u64, start: u64, end: u64 };
const Coverage = struct {
    count: usize,
    records: [labels.len][64]?Record = @splat(@splat(null)),
    fn ingest(self: *Coverage, bytes: []const u8) !void {
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |line| {
            const generic = "CODEMODE_SHARD_COMPLETE ";
            const model = "SDK_ALLOCATION_COMPLETE codemode-models ";
            const found_generic = std.mem.indexOf(u8, line, generic);
            const found_model = std.mem.indexOf(u8, line, model);
            const tail = if (found_generic) |at| line[at + generic.len ..] else if (found_model) |at| line[at + model.len ..] else continue;
            var tokens = std.mem.tokenizeAny(u8, tail, " \t\r");
            const partition = tokens.next() orelse return error.InvalidAllocationReceipt;
            const slash = std.mem.indexOfScalar(u8, partition, '/') orelse return error.InvalidAllocationReceipt;
            const shard = try std.fmt.parseInt(usize, partition[0..slash], 10);
            const count = try std.fmt.parseInt(usize, partition[slash + 1 ..], 10);
            if (count != self.count or shard >= count) return error.InvalidAllocationPartition;
            const range = tokens.next() orelse return error.InvalidAllocationReceipt;
            if (!std.mem.startsWith(u8, range, "range=[") or !std.mem.endsWith(u8, range, ")")) return error.InvalidAllocationReceipt;
            const comma = std.mem.indexOfScalar(u8, range, ',') orelse return error.InvalidAllocationReceipt;
            const start = try std.fmt.parseInt(u64, range[7..comma], 10);
            const end = try std.fmt.parseInt(u64, range[comma + 1 .. range.len - 1], 10);
            const total_text = tokens.next() orelse return error.InvalidAllocationReceipt;
            if (!std.mem.startsWith(u8, total_text, "total=")) return error.InvalidAllocationReceipt;
            const total = try std.fmt.parseInt(u64, total_text[6..], 10);
            const label = if (found_model != null) "codemode-models" else blk: {
                const text = tokens.next() orelse return error.MissingAllocationLabel;
                if (!std.mem.startsWith(u8, text, "label=")) return error.MissingAllocationLabel;
                break :blk text[6..];
            };
            const label_index = for (labels, 0..) |expected, index| {
                if (std.mem.eql(u8, expected, label)) break index;
            } else return error.UnknownAllocationLabel;
            if (self.records[label_index][shard] != null) return error.DuplicateAllocationReceipt;
            self.records[label_index][shard] = .{ .total = total, .start = start, .end = end };
        }
    }
    fn verify(self: *const Coverage) !void {
        for (labels, 0..) |label, index| {
            var total: ?u64 = null;
            for (0..self.count) |shard| {
                const record = self.records[index][shard] orelse return error.MissingAllocationReceipt;
                if (record.total == 0) return error.EmptyAllocationSweep;
                if (total) |known| {
                    if (known != record.total) return error.AllocationTotalChanged;
                } else total = record.total;
                const start = @as(u128, record.total) * shard / self.count;
                const end = @as(u128, record.total) * (shard + 1) / self.count;
                if (record.start != start or record.end != end) return error.NonExhaustiveAllocationRange;
            }
            std.debug.print("ALLOCATION_COVERAGE {s} all [0,{d}) indices verified across {d} shards\n", .{ label, total.?, self.count });
        }
    }
};
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) return error.ExpectedShardCountAndLogFiles;
    const count = try std.fmt.parseInt(usize, args[1], 10);
    if (count == 0 or count > 64 or args.len != count + 2) return error.InvalidCoverageArguments;
    var coverage: Coverage = .{ .count = count };
    for (args[2..]) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 * 1024 * 1024));
        defer init.gpa.free(bytes);
        try coverage.ingest(bytes);
    }
    try coverage.verify();
    std.debug.print("ALLOCATION_COVERAGE_COMPLETE labels={d} shards={d}\n", .{ labels.len, count });
}

test "coverage rejects missing duplicated changed or noncontiguous ranges" {
    var coverage: Coverage = .{ .count = 2 };
    try std.testing.expectError(error.MissingAllocationReceipt, coverage.verify());
    for (0..labels.len) |index| {
        coverage.records[index][0] = .{ .total = 5, .start = 0, .end = 2 };
        coverage.records[index][1] = .{ .total = 5, .start = 2, .end = 5 };
    }
    try coverage.verify();
    try std.testing.expectError(error.DuplicateAllocationReceipt, coverage.ingest("CODEMODE_SHARD_COMPLETE 0/2 range=[0,2) total=5 label=codemode-host\n"));
    coverage.records[0][1].?.total = 6;
    try std.testing.expectError(error.AllocationTotalChanged, coverage.verify());
    coverage.records[0][1] = .{ .total = 5, .start = 3, .end = 5 };
    try std.testing.expectError(error.NonExhaustiveAllocationRange, coverage.verify());
    coverage.records[0][1] = null;
    try std.testing.expectError(error.MissingAllocationReceipt, coverage.verify());
}
test "coverage parses both real completion marker formats and rejects unknown labels" {
    var coverage: Coverage = .{ .count = 2 };
    try coverage.ingest("log prefix CODEMODE_SHARD_COMPLETE 0/2 range=[0,2) total=5 label=codemode-host\r\nSDK_ALLOCATION_COMPLETE codemode-models 1/2 range=[2,5) total=5\n");
    try std.testing.expectEqual(@as(u64, 2), coverage.records[0][0].?.end);
    try std.testing.expectEqual(@as(u64, 5), coverage.records[4][1].?.end);
    try std.testing.expectError(error.UnknownAllocationLabel, coverage.ingest("CODEMODE_SHARD_COMPLETE 1/2 range=[2,5) total=5 label=new-unknown-sweep\n"));
}
