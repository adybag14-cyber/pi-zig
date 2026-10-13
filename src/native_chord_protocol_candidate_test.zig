//! Private protocol candidate records the tests the compiler actually selected.
test "native Chord protocol compiled inventory records actual selected tests" {
    const std = @import("std");
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHORD_PROTOCOL_COMPILED_TEST_INVENTORY={s}\n", .{encoded});
}
comptime {
    _ = @import("native_chord_codec_source_test.zig");
    _ = @import("native_chord_wire_source_test.zig");
}
