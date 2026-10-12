//! Complete failure indices, retaining legacy diagnostic environment controls.
const exhaustive = @import("exhaustive_allocation_shards.zig");
pub fn check(comptime body: anytype) !void {
    return checkNamed("codemode", body);
}
pub fn checkNamed(comptime label: []const u8, comptime body: anytype) !void {
    return exhaustive.check(.codemode, label, body, .{});
}
