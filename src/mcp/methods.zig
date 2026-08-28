//! MCP methods used by the native client. No synthetic extension methods.
const std = @import("std");

pub const known = [_][]const u8{
    "initialize",
    "ping",
    "tools/list",
    "tools/call",
    "resources/list",
    "resources/read",
    "prompts/list",
    "prompts/get",
    "logging/setLevel",
    "completion/complete",
    "notifications/initialized",
    "notifications/cancelled",
    "notifications/progress",
};

pub fn isKnown(method: []const u8) bool {
    for (known) |m| if (std.mem.eql(u8, m, method)) return true;
    return false;
}

test "real MCP methods only" {
    try std.testing.expect(isKnown("tools/list"));
    try std.testing.expect(!isKnown("ext/method_14_0"));
}
