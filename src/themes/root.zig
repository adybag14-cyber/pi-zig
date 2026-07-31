//! Themes package root: theme parser + generated palettes.
const std = @import("std");

pub const theme = @import("theme.zig");
pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

pub const Theme = theme.Theme;
pub const parse = theme.parse;
pub const loadFile = theme.loadFile;
pub const wrap = theme.wrap;

test {
    std.testing.refAllDecls(@This());
}
