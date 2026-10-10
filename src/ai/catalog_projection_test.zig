const std = @import("std");
const catalog = @import("catalog_tool");

test "native catalog projection preserves all existing model metadata" {
    const projected = try catalog.render(std.testing.allocator, @embedFile("catalog_source.json"));
    defer std.testing.allocator.free(projected);
    try std.testing.expectEqualStrings(@embedFile("catalog_generated.zig"), projected);
}
