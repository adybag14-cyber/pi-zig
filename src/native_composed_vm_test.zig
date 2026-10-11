//! Compile the real VM suites once. Keep their original assertions, fixtures and
//! per-test Engine lifetimes; shared-process execution also checks cleanup.
comptime {
    _ = @import("native_sdk_queue_order_test.zig");
    _ = @import("native_localecompare_binding_source_test.zig");
    _ = @import("native_localecompare_coercion_edge_source_test.zig");
    _ = @import("native_localecompare_lifecycle_source_test.zig");
    _ = @import("extension_engine_test.zig");
    _ = @import("native_durable_ea_retention_test.zig");
    _ = @import("native_physical_stdio_test.zig");
    _ = @import("native_image_resize_options_test.zig");
    _ = @import("native_image_resize_strategy_test.zig");
    _ = @import("native_command_autocomplete_source_test.zig");
    _ = @import("native_durable_owner_settlement_test.zig");
}
