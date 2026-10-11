//! Compile the real VM suites once. Keep their original assertions, fixtures and
//! per-test Engine lifetimes; shared-process execution also checks cleanup.
test "composed native coverage inventory records the actual compiled test names" {
    const std = @import("std");
    const functions = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, functions.len);
    defer std.testing.allocator.free(names);
    for (functions, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("COMPOSED_NATIVE_TEST_INVENTORY={s}\n", .{encoded});
}
comptime {
    _ = @import("native_sdk_queue_order_test.zig");
    _ = @import("native_localecompare_binding_source_test.zig");
    _ = @import("native_localecompare_coercion_edge_source_test.zig");
    _ = @import("native_localecompare_lifecycle_source_test.zig");
    _ = @import("extension_engine_test.zig");
    _ = @import("native_durable_ea_retention_test.zig");
    _ = @import("native_durable_e6_input_entry_test.zig");
    _ = @import("native_physical_stdio_test.zig");
    _ = @import("native_image_resize_options_test.zig");
    _ = @import("native_image_resize_strategy_test.zig");
    _ = @import("native_command_autocomplete_source_test.zig");
    _ = @import("native_durable_owner_settlement_test.zig");
}
