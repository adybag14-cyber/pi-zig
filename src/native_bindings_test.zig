//! Keep extension and TUI dependencies inside the same src package boundary.
test {
    _ = @import("extensions/native_bindings.zig");
}
