//! Local llama/runtime package root.
const std = @import("std");

pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

test {
    std.testing.refAllDecls(@This());
}
