const std = @import("std");
pub const tests = @import("durable/powershell_tests.zig");
test {
    std.testing.refAllDecls(@This());
}
