//! Discover shared timer and allocation-identity controls independently of the
//! AuthStorage test filter. Imports inside excluded test bodies are not roots.
comptime {
    _ = @import("extensions/timers.zig");
    _ = @import("extensions/engine.zig");
}

test "native authentication selected timer inventory" {
    const std = @import("std");
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(bytes);
    std.debug.print("AUTH_TIMER_TEST_INVENTORY={s}\n", .{bytes});
}
