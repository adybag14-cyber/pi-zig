//! Standalone CLI integration gate for the bounded durable reader.
const std = @import("std");
pub const tools = @import("agent/tools.zig");
test {
    std.testing.refAllDecls(tools);
}
