//! Model Context Protocol client.
const std = @import("std");
pub const client = @import("client.zig");
pub const methods = @import("methods.zig");
pub const oauth = @import("oauth.zig");
pub const McpClient = client.McpClient;
pub const McpTool = client.McpTool;
pub const protocol = @import("protocol.zig");
pub const session = @import("session.zig");
pub const transport = @import("transport.zig");
pub const stdio_transport = @import("stdio_transport.zig");
pub const http_transport = @import("http_transport.zig");
pub const sse = @import("sse.zig");
pub const connection = @import("connection.zig");
pub const capabilities = @import("capabilities.zig");
pub const config = @import("config.zig");
pub const content = @import("content.zig");
test {
    std.testing.refAllDecls(@This());
}
pub const configured = @import("configured.zig");
