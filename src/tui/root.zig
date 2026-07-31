//! TUI package: ANSI colors, render helpers, differential buffer.
const std = @import("std");

pub const ansi = @import("ansi.zig");
pub const render = @import("render.zig");
pub const diff = @import("diff.zig");
/// Expanded differential TUI widget/layout shards.
pub const generated = @import("generated_root.zig");
/// Product facade consuming all widget shards.
pub const product = @import("product.zig");

test {
    std.testing.refAllDecls(@This());
}
