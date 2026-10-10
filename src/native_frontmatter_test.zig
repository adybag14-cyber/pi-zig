const std = @import("std");
const frontmatter = @import("coding_agent/frontmatter.zig");
const fixture = @embedFile("extensions/fixtures/sdk-frontmatter-source-461.json");
test "native frontmatter replays all 73 Source461 acceptance body and complete error observations" {
    const gpa = std.testing.allocator;
    var source = try std.json.parseFromSlice(std.json.Value, gpa, fixture, .{});
    defer source.deinit();
    var failed: usize = 0;
    var accepted: usize = 0;
    var rejected: usize = 0;
    const rows = source.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 73), rows.len);
    for (rows) |row| {
        const label = row.object.get("id").?.string;
        if (row.object.get("body") != null) accepted += 1 else rejected += 1;
        var actual = frontmatter.parse(gpa, row.object.get("content").?.string) catch |err| {
            std.debug.print("Source461 {s} native error {s}\n", .{ label, @errorName(err) });
            failed += 1;
            continue;
        };
        defer actual.deinit();
        if (row.object.get("body")) |expected| {
            if (actual.frontmatter.diagnostic) |diagnostic| {
                std.debug.print("Source461 {s} expected valid; native {s}: {s} pos{d}\n", .{ label, diagnostic.name, diagnostic.message, diagnostic.offset });
                failed += 1;
            } else if (!std.mem.eql(u8, expected.string, actual.body)) {
                std.debug.print("Source461 {s} body mismatch expected={s} actual={s}\n", .{ label, expected.string, actual.body });
                failed += 1;
            }
        } else {
            const expected = row.object.get("error").?.object;
            const diagnostic = actual.frontmatter.diagnostic orelse {
                std.debug.print("Source461 {s} malformed input was accepted\n", .{label});
                failed += 1;
                continue;
            };
            const message = try frontmatter.pretty(gpa, actual.yaml_source orelse "", diagnostic);
            defer gpa.free(message);
            const code = expected.get("code").?;
            const code_matches = if (code == .null) diagnostic.code == null else diagnostic.code != null and std.mem.eql(u8, code.string, diagnostic.code.?);
            const positions = expected.get("pos").?;
            const positions_match = positions == .null or (diagnostic.offset == positions.array.items[0].integer and diagnostic.end == positions.array.items[1].integer);
            if (!std.mem.eql(u8, expected.get("name").?.string, diagnostic.name) or !code_matches or !positions_match or !std.mem.eql(u8, expected.get("message").?.string, message)) {
                std.debug.print("Source461 {s} expected={s}; native name={s}, code={s},pos{d},{d},message={s}\n", .{ label, expected.get("message").?.string, diagnostic.name, diagnostic.code orelse "<null>", diagnostic.offset, diagnostic.end, message });
                failed += 1;
            }
        }
    }
    std.debug.print("Source461 complete coverage accepted{d} rejected{d} total{d} mismatches{d}\n", .{ accepted, rejected, rows.len, failed });
    try std.testing.expectEqual(@as(usize, 51), accepted);
    try std.testing.expectEqual(@as(usize, 22), rejected);
    try std.testing.expectEqual(@as(usize, 0), failed);
}
fn graphCase(allocator: std.mem.Allocator) !void {
    var result = try frontmatter.parse(allocator, "---\nroot: &root {self: *root, values: [true, 001, 0x2a, 0o7, 3.5, .nan, .inf, null, \"42\", \"\x00\"]}\ncopy: *root\n---\nbody");
    defer result.deinit();
    try std.testing.expect(result.frontmatter.diagnostic == null);
    const root = result.frontmatter.root.?.data.mapping;
    try std.testing.expectEqual(@as(usize, 2), root.len);
    try std.testing.expect(root[0].value == root[1].value);
    const anchored = root[0].value;
    try std.testing.expect(anchored.data.mapping[0].value == anchored);
    const values = anchored.data.mapping[1].value.data.sequence;
    try std.testing.expect(values[0].data.boolean);
    try std.testing.expectEqual(@as(f64, 1), values[1].data.number);
    try std.testing.expectEqual(@as(f64, 42), values[2].data.number);
    try std.testing.expectEqual(@as(f64, 7), values[3].data.number);
    try std.testing.expectEqual(@as(f64, 3.5), values[4].data.number);
    try std.testing.expect(std.math.isNan(values[5].data.number));
    try std.testing.expect(std.math.isPositiveInf(values[6].data.number));
    try std.testing.expect(values[7].data == .null);
    try std.testing.expectEqualStrings("42", values[8].data.string);
    try std.testing.expectEqualSlices(u8, "\x00", values[9].data.string);
}
test "native frontmatter full schema and cyclic alias identity survive every host allocation failure" {
    try graphCase(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, graphCase, .{});
}
