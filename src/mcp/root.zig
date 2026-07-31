//! MCP package root: client + generated method surface.
const std = @import("std");

pub const client = @import("client.zig");
pub const generated = @import("generated_root.zig");
pub const methods_all = @import("methods_all.zig");

pub const McpClient = client.McpClient;
pub const McpTool = client.McpTool;

test {
    std.testing.refAllDecls(@This());
}
