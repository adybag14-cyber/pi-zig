const std = @import("std");
const pieces = @import("extensions/native_chord_delta_tracker_pieces.zig");
const Items = []const []const u8;
fn encodePlan(tree: *pieces.Tree, base_length: usize, sources: []const Items) ![]u8 {
    const allocator = std.testing.allocator;
    var plan = try tree.plan(base_length);
    defer plan.deinit();
    const current = try tree.pieces();
    defer allocator.free(current);
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeByte('[');
    var emitted = false;
    for (plan.removes.items) |remove| {
        if (emitted) try writer.writeByte(',');
        try writer.print("[\"p\",[],{d},{d},[]]", .{ remove.start, remove.length });
        emitted = true;
    }
    if (plan.permutation) |permutation| {
        if (emitted) try writer.writeByte(',');
        const encoded = try std.json.Stringify.valueAlloc(allocator, permutation, .{});
        defer allocator.free(encoded);
        try writer.print("[\"m\",[],{s}]", .{encoded});
        emitted = true;
    }
    for (plan.inserts.items) |insert| {
        if (emitted) try writer.writeByte(',');
        try writer.print("[\"p\",[],{d},0,[", .{insert.logical});
        var item_emitted = false;
        for (current[insert.first..insert.end]) |piece| {
            for (0..piece.length) |offset| {
                if (item_emitted) try writer.writeByte(',');
                try writer.writeAll(sources[piece.source.?][piece.index(offset)]);
                item_emitted = true;
            }
        }
        try writer.writeAll("]]");
        emitted = true;
    }
    try writer.writeByte(']');
    return output.toOwnedSlice();
}
fn sourceStructural(cases: []const std.json.Value, name: []const u8) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try output.writer.writeByte('[');
    var emitted = false;
    for (cases) |case| {
        if (!std.mem.eql(u8, case.object.get("name").?.string, name)) continue;
        const ops = case.object.get("result").?.object.get("ops").?.array.items;
        for (ops) |op| {
            const tag = op.array.items[0].string;
            if (!std.mem.eql(u8, tag, "p") and !std.mem.eql(u8, tag, "m")) continue;
            if (emitted) try output.writer.writeByte(',');
            const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, op, .{});
            defer std.testing.allocator.free(encoded);
            try output.writer.writeAll(encoded);
            emitted = true;
        }
        try output.writer.writeByte(']');
        return output.toOwnedSlice();
    }
    return error.MissingOriginalTrackerCase;
}
test "native Chord tracker piece plans match seven genuine original tracker structural batches" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("extensions/fixtures/chord-delta-tracker-original-19cb.json"), .{});
    defer parsed.deinit();
    const cases = parsed.value.object.get("cases").?.array.items;
    const names = [_][]const u8{ "push-pop", "shift-unshift", "splice", "array-length-grow", "array-length-shrink", "array-reverse", "array-sort" };
    const lengths = [_]usize{ 2, 3, 5, 2, 4, 3, 3 };
    for (names, lengths, 0..) |name, base_length, scenario| {
        var tree = try pieces.Tree.init(std.testing.allocator, base_length);
        defer tree.deinit();
        var inserted: Items = &.{};
        switch (scenario) {
            0 => {
                inserted = &.{"{\"x\":3}"};
                try tree.replace(2, 0, &.{.{ .source = 0, .start = 0, .length = 1 }});
                try tree.replace(2, 1, &.{});
            },
            1 => {
                inserted = &.{ "8", "9" };
                try tree.replace(0, 1, &.{});
                try tree.replace(0, 0, &.{.{ .source = 0, .start = 0, .length = 2 }});
            },
            2 => {
                inserted = &.{ "8", "9", "10" };
                try tree.replace(1, 2, &.{.{ .source = 0, .start = 0, .length = 3 }});
            },
            3 => {
                inserted = &.{ "null", "null", "null" };
                try tree.replace(2, 0, &.{.{ .source = 0, .start = 0, .length = 3 }});
            },
            4 => try tree.replace(2, 2, &.{}),
            5 => try tree.reverse(),
            6 => try tree.replace(0, 3, &.{ .{ .start = 1, .length = 1 }, .{ .start = 2, .length = 1 }, .{ .start = 0, .length = 1 } }),
            else => unreachable,
        }
        const actual = try encodePlan(&tree, base_length, &.{inserted});
        defer std.testing.allocator.free(actual);
        const expected = try sourceStructural(cases, name);
        defer std.testing.allocator.free(expected);
        try std.testing.expectEqualStrings(expected, actual);
    }
}
test "native Chord tracker canonical array index and clamp controls" {
    for ([_][]const u8{ "", "00", "01", "-1", "1.0", "4294967295", "x" }) |key| try std.testing.expectEqual(@as(?usize, null), pieces.arrayIndex(key));
    try std.testing.expectEqual(@as(?usize, 0), pieces.arrayIndex("0"));
    try std.testing.expectEqual(@as(?usize, 4294967294), pieces.arrayIndex("4294967294"));
    try std.testing.expectEqual(@as(usize, 0), pieces.clampIndex(-std.math.inf(f64), 10));
    try std.testing.expectEqual(@as(usize, 10), pieces.clampIndex(std.math.inf(f64), 10));
    try std.testing.expectEqual(@as(usize, 7), pieces.clampIndex(-3, 10));
    try std.testing.expectEqual(@as(f64, 0), pieces.integerOrInfinity(std.math.nan(f64)));
}
