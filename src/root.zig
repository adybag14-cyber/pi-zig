//! pi-zig library root: full coding agent modules.
const std = @import("std");

pub const config = @import("config.zig");
pub const ai = @import("ai/root.zig");
pub const agent = @import("agent/root.zig");
pub const tui = @import("tui/root.zig");
pub const coding_agent = @import("coding_agent/root.zig");

pub const version = config.version;
pub const name = config.APP_NAME;
pub const identity = config.identity;

test {
    std.testing.refAllDecls(@This());
}
