const std = @import("std");
comptime {
    _ = @import("coding_agent/clipboard.zig");
    _ = @import("mcp/codemode_source.zig");
}
test "latest Pi 1.2 selected inventory" {
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(bytes);
    std.debug.print("LATEST12_TEST_INVENTORY={s}\n", .{bytes});
}
