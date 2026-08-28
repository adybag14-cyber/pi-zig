//! pi-zig library root: native Zig implementations only.
const std = @import("std");

pub const config = @import("config.zig");
pub const ai = @import("ai/root.zig");
pub const agent = @import("agent/root.zig");
pub const tui = @import("tui/root.zig");
pub const coding_agent = @import("coding_agent/root.zig");

pub const mcp = @import("mcp/root.zig");
pub const server = @import("server/root.zig");
pub const storage = @import("storage/root.zig");
pub const auth = @import("auth/root.zig");
pub const extensions = @import("extensions/root.zig");
pub const themes = @import("themes/root.zig");
pub const evals = @import("evals/root.zig");
pub const protocol = @import("protocol/root.zig");
pub const telemetry = @import("telemetry/root.zig");
pub const client = @import("client/root.zig");

pub const version = config.version;
pub const name = config.APP_NAME;
pub const identity = config.identity;

test {
    std.testing.refAllDecls(@This());
}
