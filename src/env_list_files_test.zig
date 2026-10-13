//! Selected Env listing tests expose the actual compiler-selected inventory.
const std = @import("std");
const builtin = @import("builtin");
test "listFiles actual compiled inventory" {
    const names = try std.testing.allocator.alloc([]const u8, builtin.test_functions.len);
    defer std.testing.allocator.free(names);
    for (builtin.test_functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("\nENV_LIST_FILES_TEST_INVENTORY={s}\n", .{encoded});
}
comptime {
    _ = @import("env/list_files_test.zig");
    _ = @import("durable/list_ignore.zig");
}
