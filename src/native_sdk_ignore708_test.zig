//! Prepared, unrun standalone test root; metadata is unknown until compilation.
comptime {
    _=@import("extensions/native_sdk_ignore708_test.zig");
    _=@import("extensions/native_sdk_ignore708_cleanup_test.zig");
}
