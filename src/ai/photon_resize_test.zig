const std = @import("std");
const resize_mod = @import("photon_resize.zig");
fn number(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |v| @floatFromInt(v),
        .float => |v| v,
        .null => std.math.nan(f64),
        else => unreachable,
    };
}
fn allocationOperation(gpa: std.mem.Allocator) !void {
    const input = @embedFile("fixtures/photon-source-8x5.png");
    var result = (try resize_mod.resize(gpa, input, "image/png", .{ .max_width = 4, .max_height = 3, .exif_orientation = 6 })) orelse return error.ExpectedResizedImage;
    defer result.deinit(gpa);
}
test "resize strategy releases decoded oriented scaled and every encoded candidate on all allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationOperation, .{});
}
test "resize strategy matches every field and encoded byte of twenty actual Source results" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/photon-resize-core-c5-source.json"), .{});
    defer parsed.deinit();
    for (parsed.value.object.get("rows").?.array.items) |row| {
        const encoded = row.object.get("input").?.string;
        const input = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
        defer gpa.free(input);
        try std.base64.standard.Decoder.decode(input, encoded);
        var options: resize_mod.Options = .{};
        const source_options = row.object.get("options").?.object;
        if (source_options.get("maxWidth")) |v| options.max_width = number(v);
        if (source_options.get("maxHeight")) |v| options.max_height = number(v);
        if (source_options.get("maxBytes")) |v| options.max_bytes = number(v);
        if (source_options.get("jpegQuality")) |v| options.jpeg_quality = number(v);
        if (row.object.get("nanMaxBytes").?.bool) options.max_bytes = std.math.nan(f64);
        var actual = try resize_mod.resize(gpa, input, row.object.get("mime").?.string, options);
        defer if (actual) |*image| image.deinit(gpa);
        const expected = row.object.get("result").?;
        if ((expected != .null) != (actual != null)) std.debug.print("Source resize case {s}\n", .{row.object.get("name").?.string});
        try std.testing.expectEqual(expected != .null, actual != null);
        if (actual) |image| {
            try std.testing.expectEqualStrings(expected.object.get("data").?.string, image.data);
            try std.testing.expectEqualStrings(expected.object.get("mimeType").?.string, image.mime_type);
            try std.testing.expectEqual(number(expected.object.get("originalWidth").?), image.original_width);
            try std.testing.expectEqual(number(expected.object.get("originalHeight").?), image.original_height);
            try std.testing.expectEqual(number(expected.object.get("width").?), image.width);
            try std.testing.expectEqual(number(expected.object.get("height").?), image.height);
            try std.testing.expectEqual(expected.object.get("wasResized").?.bool, image.was_resized);
        }
    }
}
