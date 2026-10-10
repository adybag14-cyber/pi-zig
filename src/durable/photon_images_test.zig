const std = @import("std");
const durable = @import("photon_images.zig");
const model = @import("image_processor.zig");
const exif = @import("photon_exif.zig");
fn number(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        else => unreachable,
    };
}
fn allocationCase(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8) !void {
    var result = try durable.prepare(null, gpa, bytes, mime, .{ .maxWidth = 4 });
    defer if (result) |*value| value.deinit(gpa);
    try std.testing.expect(result != null);
}
test "Durable image preparation frees every codec and result allocation on failure" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/photon-durable-c5-source.json"), .{});
    defer parsed.deinit();
    const encoded = parsed.value.object.get("rows").?.array.items[0].object.get("bytes").?.string;
    const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
    defer gpa.free(bytes);
    try std.base64.standard.Decoder.decode(bytes, encoded);
    try std.testing.checkAllAllocationFailures(gpa, allocationCase, .{ bytes, "image/bmp" });
}
test "Durable prepare equals actual c5 Source complete results for thirty eight cases" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/photon-durable-c5-source.json"), .{});
    defer parsed.deinit();
    const rows = parsed.value.object.get("rows").?.array.items;
    try std.testing.expectEqual(@as(usize, 38), rows.len);
    for (rows) |row| {
        const data = row.object.get("bytes").?.string;
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(data));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, data);
        const source_limits = row.object.get("limits").?.object;
        var limits: model.Limits = undefined;
        inline for (.{ "maxWidth", "maxHeight", "maxBytes" }) |key| {
            @field(limits, key) = if (row.object.get("nonfinite").?.object.get(key)) |v| if (std.mem.eql(u8, v.string, "NaN")) std.math.nan(f64) else if (std.mem.eql(u8, v.string, "-Infinity")) -std.math.inf(f64) else std.math.inf(f64) else number(source_limits.get(key).?);
        }
        try std.testing.expectEqual(row.object.get("orientation").?.integer, exif.read(bytes));
        var actual = try durable.prepare(null, gpa, bytes, row.object.get("mimeType").?.string, limits);
        defer if (actual) |*value| value.deinit(gpa);
        const expected = row.object.get("result").?;
        if (expected == .null) {
            try std.testing.expect(actual == null);
            continue;
        }
        if (actual == null) {
            std.debug.print("Unexpected null: {s}\n", .{row.object.get("name").?.string});
            return error.UnexpectedNull;
        }
        try std.testing.expectEqualStrings(expected.object.get("data").?.string, actual.?.data);
        try std.testing.expectEqualStrings(expected.object.get("mimeType").?.string, actual.?.mimeType);
        if (expected.object.get("convertedFrom")) |converted| try std.testing.expectEqualStrings(converted.string, actual.?.convertedFrom.?) else try std.testing.expect(actual.?.convertedFrom == null);
        if (expected.object.get("resized")) |resized| {
            const value = actual.?.resized orelse return error.MissingResize;
            try std.testing.expectEqual(number(resized.object.get("from").?.object.get("width").?), value.from.width);
            try std.testing.expectEqual(number(resized.object.get("from").?.object.get("height").?), value.from.height);
            try std.testing.expectEqual(number(resized.object.get("to").?.object.get("width").?), value.to.width);
            try std.testing.expectEqual(number(resized.object.get("to").?.object.get("height").?), value.to.height);
        } else try std.testing.expect(actual.?.resized == null);
    }
}
