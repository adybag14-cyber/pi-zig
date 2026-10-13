//! Discover shared timer and allocation-identity controls independently of the
//! AuthStorage test filter. Imports inside excluded test bodies are not roots.
comptime {
    _ = @import("extensions/timers.zig");
    _ = @import("extensions/engine.zig");
}
