//! Functional foundation gates only; exhaustive host/VM allocation gates separate.
comptime {
    _ = @import("native_highlight_legacy32_function_test.zig");
    _ = @import("native_highlight_core_b45_test.zig");
    _ = @import("native_highlight_scope_test.zig");
    _ = @import("native_highlight_core_profile_test.zig");
}
