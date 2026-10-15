//! Byte-owned preparation failure; never contains a VM value or guest callback.
const std = @import("std");
pub const Owned = struct {
    name: []u8,
    message: []u8,
    try_next_link: ?bool = null,
    pub fn init(a: std.mem.Allocator, name: []const u8, message: []const u8, try_next_link: ?bool) !Owned {
        const owned_name = try a.dupe(u8, name);
        errdefer a.free(owned_name);
        return .{ .name = owned_name, .message = try a.dupe(u8, message), .try_next_link = try_next_link };
    }
    pub fn deinit(self: *Owned, a: std.mem.Allocator) void {
        @memset(self.message, 0);
        a.free(self.name);
        a.free(self.message);
        self.* = undefined;
    }
};
