//! The candidate joins unchanged qualified suites and records compiler inventory.
test "native Chord delta compiled inventory records actual selected tests" {
    const std = @import("std");
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_DELTA_COMPILED_TEST_INVENTORY={s}\n", .{encoded});
}
comptime {
    _ = @import("native_chord_delta_diff_source_test.zig");
    _ = @import("native_chord_delta_tracker_source_test.zig");
    _ = @import("native_chord_delta_tracker_pieces_source_test.zig");
}
