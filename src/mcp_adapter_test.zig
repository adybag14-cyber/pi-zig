const std = @import("std");
pub const tests = @import("mcp/stdio_process_test.zig");
test {
    std.testing.refAllDecls(@This());
}
