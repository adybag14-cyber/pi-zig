const std = @import("std");
pub const tests = @import("mcp/runtime_tests.zig");
test {
    std.testing.refAllDecls(@This());
}
