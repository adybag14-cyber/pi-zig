//! Standalone portable durable foundation test root.
const std = @import("std");
pub const durable = @import("durable/root.zig");
test {
    std.testing.refAllDecls(durable);
}
