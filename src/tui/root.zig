//! TUI package: ANSI colors and simple render helpers.
const std = @import("std");

pub const ansi = @import("ansi.zig");
pub const render = @import("render.zig");

test {
    std.testing.refAllDecls(@This());
}
