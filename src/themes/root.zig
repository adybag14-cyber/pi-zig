//! Theme parsing/render helpers.
const std = @import("std");
pub const theme = @import("theme.zig");
pub const Theme = theme.Theme;
pub const registry = @import("registry.zig");
pub const Registry = registry.Registry;
pub const parse = theme.parse;
pub const loadFile = theme.loadFile;
pub const wrap = theme.wrap;
test {
    std.testing.refAllDecls(@This());
}
