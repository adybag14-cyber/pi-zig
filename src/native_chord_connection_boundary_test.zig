//! Reuse the existing private-native-identity and actual V8 weak-reference tests unchanged.
test "native Chord connection boundary inventory records actual selected identity and weakref tests" {
    const std = @import("std");
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_CONNECTION_BOUNDARY_INVENTORY={s}\n", .{encoded});
}
comptime {
    _ = @import("extensions/native_tui_alt_source_test.zig");
    _ = @import("native_weakref_test.zig");
}
