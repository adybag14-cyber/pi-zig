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

fn quotedUnitsCase(allocator: std.mem.Allocator) !void {
    // Genuine Source481 unicode-halves values are compared as UTF16, without
    // parsing its escaped lone-surrogate JSON through a scalar-only decoder.
    var result = try frontmatter.parse(allocator, "---\nhigh: \"\\ud83e\"\nlow: \"\\udd8a\"\nadjacent: \"\\ud83e\\u0041\"\npair: \"\\ud83e\\udd8a\"\n---\nbody");
    defer result.deinit();
    try std.testing.expect(result.frontmatter.diagnostic == null);
    const entries = result.frontmatter.root.?.data.mapping;
    const expected = [_][]const u16{ &.{0xd83e}, &.{0xdd8a}, &.{ 0xd83e, 'A' }, &.{ 0xd83e, 0xdd8a } };
    try std.testing.expectEqual(expected.len, entries.len);
    for (entries, expected) |entry, units| {
        const actual = try std.unicode.wtf8ToWtf16LeAlloc(allocator, entry.value.data.string);
        defer allocator.free(actual);
        try std.testing.expectEqualSlices(u16, units, actual);
    }
}
test "native frontmatter preserves Source481 escaped isolated UTF16 units through allocation failure" {
    try quotedUnitsCase(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, quotedUnitsCase, .{});
}

test "native frontmatter reports Source481 composition error before unresolved alias conversion" {
    var result = try frontmatter.parse(std.testing.allocator, "---\na: *missing\na: 2\n---\nbody");
    defer result.deinit();
    const failure = result.frontmatter.diagnostic orelse return error.ExpectedDuplicateKey;
    try std.testing.expectEqualStrings("YAMLParseError", failure.name);
    try std.testing.expectEqualStrings("DUPLICATE_KEY", failure.code.?);
    try std.testing.expectEqual(@as(usize, 12), failure.offset);
    try std.testing.expectEqual(@as(usize, 13), failure.end);
    const message = try frontmatter.pretty(std.testing.allocator, result.yaml_source.?, failure);
    defer std.testing.allocator.free(message);
    try std.testing.expectEqualStrings("Map keys must be unique at line 2, column 1:\n\na: *missing\na: 2\n^\n", message);
}

test "native frontmatter preserves Source481 set pairs and ordered map value types" {
    const gpa = std.testing.allocator;
    var result = try frontmatter.parse(gpa, "---\nset: !!set {a: null, b: ~}\npairs: !!pairs [a, {b: 2}, {}]\nomap: !!omap [{a: 1}, {b: 2}]\n---\nbody");
    defer result.deinit();
    try std.testing.expect(result.frontmatter.diagnostic == null);
    const entries = result.frontmatter.root.?.data.mapping;
    const set = entries[0].value.data.set;
    try std.testing.expectEqual(@as(usize, 2), set.len);
    try std.testing.expectEqualStrings("a", set[0].data.string);
    try std.testing.expectEqualStrings("b", set[1].data.string);
    const pairs = entries[1].value.data.sequence;
    try std.testing.expectEqual(@as(usize, 3), pairs.len);
    try std.testing.expectEqualStrings("a", pairs[0].data.mapping[0].key.data.string);
    try std.testing.expect(pairs[0].data.mapping[0].value.data == .null);
    try std.testing.expectEqualStrings("b", pairs[1].data.mapping[0].key.data.string);
    try std.testing.expectEqual(@as(f64, 2), pairs[1].data.mapping[0].value.data.number);
    try std.testing.expectEqualStrings("", pairs[2].data.mapping[0].key.data.string);
    try std.testing.expect(pairs[2].data.mapping[0].value.data == .null);
    const ordered = entries[2].value.data.ordered_mapping;
    try std.testing.expectEqual(@as(usize, 2), ordered.len);
    try std.testing.expectEqualStrings("a", ordered[0].key.data.string);
    try std.testing.expectEqual(@as(f64, 1), ordered[0].value.data.number);
    try std.testing.expectEqualStrings("b", ordered[1].key.data.string);
    try std.testing.expectEqual(@as(f64, 2), ordered[1].value.data.number);
}

test "native frontmatter rejects Source481 invalid typed collections at their tag range" {
    const Case = struct { yaml: []const u8, message: []const u8, end: usize };
    for ([_]Case{
        .{ .yaml = "items: !!set {a: 1}", .message = "Set items must all have null values", .end = 12 },
        .{ .yaml = "items: !!pairs [{a: 1, b: 2}]", .message = "Each pair must have its own sequence indicator", .end = 14 },
        .{ .yaml = "items: !!omap [{a: 1}, {a: 2}]", .message = "Ordered maps must not include duplicate keys: a", .end = 13 },
    }) |case| {
        const content = try std.fmt.allocPrint(std.testing.allocator, "---\n{s}\n---\nbody", .{case.yaml});
        defer std.testing.allocator.free(content);
        var result = try frontmatter.parse(std.testing.allocator, content);
        defer result.deinit();
        const diagnostic = result.frontmatter.diagnostic orelse return error.ExpectedTagError;
        try std.testing.expectEqualStrings("TAG_RESOLVE_FAILED", diagnostic.code.?);
        try std.testing.expectEqualStrings(case.message, diagnostic.message);
        try std.testing.expectEqual(@as(usize, 7), diagnostic.offset);
        try std.testing.expectEqual(case.end, diagnostic.end);
    }
}

test "native frontmatter preserves Source481 explicit merge and rejects nonmapping sources" {
    var result = try frontmatter.parse(std.testing.allocator, "---\ndefaults: &defaults {a: 1, b: 2}\nitem: {!!merge <<: *defaults, b: 3}\n---\nbody");
    defer result.deinit();
    try std.testing.expect(result.frontmatter.diagnostic == null);
    const entries = result.frontmatter.root.?.data.mapping;
    const defaults = entries[0].value.data.mapping;
    const item = entries[1].value.data.mapping;
    try std.testing.expectEqual(@as(usize, 2), item.len);
    try std.testing.expectEqualStrings("a", item[0].key.data.string);
    try std.testing.expectEqual(@as(f64, 1), item[0].value.data.number);
    try std.testing.expectEqualStrings("b", item[1].key.data.string);
    try std.testing.expectEqual(@as(f64, 3), item[1].value.data.number);
    try std.testing.expectEqual(@as(f64, 2), defaults[1].value.data.number);
    var invalid = try frontmatter.parse(std.testing.allocator, "---\nitem: {!!merge <<: [1]}\n---\nbody");
    defer invalid.deinit();
    const failure = invalid.frontmatter.diagnostic orelse return error.ExpectedMergeError;
    try std.testing.expectEqualStrings("Error", failure.name);
    try std.testing.expect(failure.code == null);
    try std.testing.expectEqualStrings("Merge sources must be maps or map aliases", failure.message);
}

test "native frontmatter compares all 21 genuine Source481 values and complete errors losslessly" {
    try @import("native_yaml_values_test.zig").exercise(std.testing.allocator);
}

fn collectionKeyCase(allocator: std.mem.Allocator) !void {
    var result = try frontmatter.parse(allocator, "---\n? [a, b]\n: value\n? {a: b}\n: second\n---\nbody");
    defer result.deinit();
    try std.testing.expect(result.frontmatter.diagnostic == null);
    const entries = result.frontmatter.root.?.data.mapping;
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqualStrings("[ a, b ]", entries[0].key.data.string);
    try std.testing.expectEqualStrings("value", entries[0].value.data.string);
    try std.testing.expectEqualStrings("{ a: b }", entries[1].key.data.string);
    try std.testing.expectEqualStrings("second", entries[1].value.data.string);
}
test "native frontmatter releases Source481 native collection key rendering on every host allocation failure" {
    try collectionKeyCase(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectionKeyCase, .{});
}

test "native frontmatter compares all 24 genuine Source489 value and error edge observations" {
    try @import("native_yaml_values_test.zig").exerciseEdges(std.testing.allocator);
}
