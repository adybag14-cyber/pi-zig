//! Verify actual compiled inventory and a complete successful IPC test run.
const std = @import("std");
const scope = @import("native_composed_scope.zig");
const marker = "COMPOSED_NATIVE_TEST_INVENTORY=";
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
        };
        if (matches != 1) {
            std.debug.print("Composed coverage missing or ambiguous Source test: {s}\n", .{name});
            return error.MissingNamedTestCoverage;
        }
    }
    const complete = try std.fmt.allocPrint(gpa, "run test {d} pass ({d} total)", .{ parsed.value.len, parsed.value.len });
    defer gpa.free(complete);
    if (std.mem.indexOf(u8, log, complete) == null) return error.IncompleteTestExecution;
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
}
