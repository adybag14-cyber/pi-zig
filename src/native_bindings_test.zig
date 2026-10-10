//! Keep extension and TUI dependencies inside the same src package boundary.
test {
    _ = @import("extensions/native_bindings.zig");
    _ = @import("extensions/native_group.zig");
    _ = @import("extensions/native_sdk_tools.zig");
    _ = @import("widget_array_oracle_test.zig");
}
