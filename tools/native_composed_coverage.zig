//! Verify actual compiled inventory and a complete successful IPC test run.
const std = @import("std");
const scope = @import("native_composed_scope.zig");
const marker = "COMPOSED_NATIVE_TEST_INVENTORY=";
const allocation_marker = "COMMAND_GPA_SHARD=";
pub fn verifyAllocationShards(gpa: std.mem.Allocator, log: []const u8) !usize {
    const Range = struct { index: usize, shards: usize, begin: usize, end: usize, total: usize };
    var offset: usize = 0;
    var seen: u8 = 0;
    var total: ?usize = null;
    while (std.mem.indexOfPos(u8, log, offset, allocation_marker)) |start| {
        const rest = log[start + allocation_marker.len ..];
        const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const parsed = try std.json.parseFromSlice(Range, gpa, std.mem.trim(u8, rest[0..end], "\r\n "), .{});
        defer parsed.deinit();
        const range = parsed.value;
        if (range.shards != 8 or range.index >= 8 or range.total == 0) return error.InvalidAllocationShard;
        const bit = @as(u8, 1) << @as(u3, @intCast(range.index));
        if (seen & bit != 0) return error.DuplicateAllocationShard;
        seen |= bit;
        if (total) |count| {
            if (count != range.total) return error.AllocationUniverseDrift;
        } else total = range.total;
        const expected_begin = range.total / 8 * range.index + range.total % 8 * range.index / 8;
        const expected_end = range.total / 8 * (range.index + 1) + range.total % 8 * (range.index + 1) / 8;
        if (range.begin != expected_begin or range.end != expected_end) return error.IncompleteAllocationRange;
        offset = start + allocation_marker.len + end;
    }
    if (seen != 255) return error.IncompleteAllocationShardCoverage;
    return total.?;
}
pub fn verifyLog(gpa: std.mem.Allocator, wanted: []const []const u8, log: []const u8) !usize {
    const start = std.mem.indexOf(u8, log, marker) orelse return error.MissingCompiledTestInventory;
    const rest = log[start + marker.len ..];
    if (std.mem.indexOf(u8, rest, marker) != null) return error.DuplicateCompiledTestInventory;
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const parsed = try std.json.parseFromSlice([]const []const u8, gpa, std.mem.trim(u8, rest[0..end], "\r\n "), .{});
    defer parsed.deinit();
    if (parsed.value.len == 0 or wanted.len == 0) return error.EmptyTestCoverage;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(gpa);
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    defer covered.deinit(gpa);
    for (parsed.value) |name| {
        const item = try seen.getOrPut(gpa, name);
        if (item.found_existing) return error.DuplicateCompiledTestName;
    }
    for (wanted) |name| {
        const suffix = try std.fmt.allocPrint(gpa, ".test.{s}", .{name});
        defer gpa.free(suffix);
        var matches: usize = 0;
        for (parsed.value) |actual| if (std.mem.endsWith(u8, actual, suffix)) {
            matches += 1;
            try covered.put(gpa, actual, {});
        };
        if (matches != 1) {
            std.debug.print("Composed coverage missing or ambiguous Source test: {s}\n", .{name});
            return error.MissingNamedTestCoverage;
        }
    }
    for (parsed.value) |name| if (std.mem.indexOf(u8, name, ".test.") != null and !covered.contains(name)) {
        std.debug.print("Composed named test has no Source inventory entry: {s}\n", .{name});
        return error.UnmappedNamedTestCoverage;
    };
    const complete = try std.fmt.allocPrint(gpa, "run test {d} pass ({d} total)", .{ parsed.value.len, parsed.value.len });
    defer gpa.free(complete);
    if (std.mem.indexOf(u8, log, complete) == null) return error.IncompleteTestExecution;
    for (wanted) |name| if (std.mem.startsWith(u8, name, "Command Source exhaustive host allocation cleanup shard ")) {
        _ = try verifyAllocationShards(gpa, log);
        break;
    };
    return parsed.value.len;
}
pub fn verify(gpa: std.mem.Allocator, io: std.Io, root: []const u8, log_path: []const u8, writer: *std.Io.Writer) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var wanted: std.ArrayList([]const u8) = .empty;
    for (scope.source_files) |relative| {
        const path = try std.fs.path.join(allocator, &.{ root, relative });
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(4 * 1024 * 1024));
        const bytes = try allocator.dupeZ(u8, raw);
        var tokenizer = std.zig.Tokenizer.init(bytes);
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof) break;
            if (token.tag != .keyword_test) continue;
            const name_token = tokenizer.next();
            if (name_token.tag != .string_literal) continue;
            const name = try std.zig.string_literal.parseAlloc(allocator, bytes[name_token.loc.start..name_token.loc.end]);
            for (scope.filters) |filter| if (std.mem.indexOf(u8, name, filter) != null) {
                try wanted.append(allocator, name);
                break;
            };
        }
    }
    const log = try std.Io.Dir.cwd().readFileAlloc(io, log_path, allocator, .limited(16 * 1024 * 1024));
    const compiled = try verifyLog(allocator, wanted.items, log);
    try writer.print("composed_named_tests={d} compiled_tests={d} missing=0 complete_execution=true\n", .{ wanted.items.len, compiled });
}
test "composed coverage rejects missing duplicated and unexecuted compiled cases" {
    const allocator = std.testing.allocator;
    const wanted = [_][]const u8{"actual case"};
    const positive = marker ++ "[\"fixture.test.actual case\"]\n+- run test 1 pass (1 total)\n";
    try std.testing.expectEqual(@as(usize, 1), try verifyLog(allocator, &wanted, positive));
    try std.testing.expectError(error.MissingCompiledTestInventory, verifyLog(allocator, &wanted, "Build Summary: success"));
    try std.testing.expectError(error.DuplicateCompiledTestInventory, verifyLog(allocator, &wanted, positive ++ positive));
    try std.testing.expectError(error.DuplicateCompiledTestName, verifyLog(allocator, &wanted, marker ++ "[\"fixture.test.actual case\",\"fixture.test.actual case\"]\n"));
    try std.testing.expectError(error.MissingNamedTestCoverage, verifyLog(allocator, &wanted, marker ++ "[\"fixture.test.other\"]\n+- run test 1 pass (1 total)\n"));
    try std.testing.expectError(error.IncompleteTestExecution, verifyLog(allocator, &wanted, marker ++ "[\"fixture.test.actual case\"]\n+- run test 0 pass (1 total)\n"));
    try std.testing.expectError(error.UnmappedNamedTestCoverage, verifyLog(allocator, &wanted, marker ++ "[\"fixture.test.actual case\",\"other.test.hidden case\"]\n+- run test 2 pass (2 total)\n"));
}
test "composed allocation coverage rejects omitted duplicate and incomplete failure ranges" {
    const gpa = std.testing.allocator;
    var log: std.ArrayList(u8) = .empty;
    defer log.deinit(gpa);
    for (0..8) |index| {
        const row = try std.fmt.allocPrint(gpa, allocation_marker ++ "{{\"index\":{d},\"shards\":8,\"begin\":{d},\"end\":{d},\"total\":17}}\n", .{ index, 17 * index / 8, 17 * (index + 1) / 8 });
        defer gpa.free(row);
        try log.appendSlice(gpa, row);
    }
    try std.testing.expectEqual(@as(usize, 17), try verifyAllocationShards(gpa, log.items));
    try std.testing.expectError(error.IncompleteAllocationShardCoverage, verifyAllocationShards(gpa, ""));
    try std.testing.expectError(error.IncompleteAllocationRange, verifyAllocationShards(gpa, allocation_marker ++ "{\"index\":0,\"shards\":8,\"begin\":1,\"end\":2,\"total\":17}\n"));
    try std.testing.expectError(error.AllocationUniverseDrift, verifyAllocationShards(gpa, allocation_marker ++ "{\"index\":0,\"shards\":8,\"begin\":0,\"end\":2,\"total\":17}\n" ++ allocation_marker ++ "{\"index\":1,\"shards\":8,\"begin\":2,\"end\":4,\"total\":18}\n"));
    try log.appendSlice(gpa, allocation_marker ++ "{\"index\":0,\"shards\":8,\"begin\":0,\"end\":2,\"total\":17}\n");
    try std.testing.expectError(error.DuplicateAllocationShard, verifyAllocationShards(gpa, log.items));
}
