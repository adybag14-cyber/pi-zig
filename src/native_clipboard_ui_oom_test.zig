//! Discover the two actual host UI allocation-failure regressions without
//! recursively admitting unrelated declarations or process fixtures.
comptime {
    _ = @import("extensions/js_runtime.zig");
}
