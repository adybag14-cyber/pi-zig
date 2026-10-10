//! Import the actual implementation at comptime so filters discover its tests
//! independently of which public root test bodies Zig analyzes lazily.
comptime {
    _ = @import("extensions/native_durable_tasks.zig");
    _ = @import("extensions/native_durable_harness.zig");
}
