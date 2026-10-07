//! Keep system-theme and TUI math replay in one source package boundary.
test {
    _ = @import("themes/system_theme.zig");
    _ = @import("themes/theme.zig");
}
