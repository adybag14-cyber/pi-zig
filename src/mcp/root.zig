//! Model Context Protocol client.
const std = @import("std");
pub const client = @import("client.zig");
pub const methods = @import("methods.zig");
pub const McpClient = client.McpClient;
pub const McpTool = client.McpTool;
test {
    std.testing.refAllDecls(@This());
}
