const std = @import("std");
const c = @cImport({
    @cInclude("session_browser_api.h");
});
const Owner = struct {
    allocator: std.mem.Allocator,
    fn allocate(context: ?*anyopaque, size: usize, alignment: usize) callconv(.c) ?*anyopaque {
        const self: *Owner = @ptrCast(@alignCast(context.?));
        return self.allocator.rawAlloc(size, .fromByteUnits(alignment), @returnAddress());
    }
    fn release(context: ?*anyopaque, pointer: ?*anyopaque, size: usize, alignment: usize) callconv(.c) void {
        const self: *Owner = @ptrCast(@alignCast(context.?));
        const bytes: [*]u8 = @ptrCast(pointer.?);
        self.allocator.rawFree(bytes[0..size], .fromByteUnits(alignment), @returnAddress());
    }
    fn callbacks(self: *Owner) c.PiImageAllocator {
        return .{ .context = self, .allocate = allocate, .release = release };
    }
};
test "both real codec versions coexist, reject wrong dispatch, and survive sibling release" {
    var owner: Owner = .{ .allocator = std.testing.allocator };
    const node = c.pi_session_create(owner.callbacks(), 32 * 1024 * 1024);
    try std.testing.expectEqual(@as(c_int, 0), node.status);
    var node_open = true;
    defer if (node_open) std.debug.assert(c.pi_session_destroy(node.session) == 0);
    const browser = c.pi_browser_session_create(owner.callbacks(), 32 * 1024 * 1024);
    try std.testing.expectEqual(@as(c_int, 0), browser.status);
    defer std.debug.assert(c.pi_browser_session_destroy(browser.session) == 0);
    try std.testing.expectEqual(@as(c_int, 5), c.pi_session_destroy(browser.session));
    try std.testing.expectEqual(@as(c_int, 5), c.pi_browser_session_destroy(node.session));
    try std.testing.expectEqual(@as(c_int, 5), c.pi_session_call(browser.session, c.PI_SESSION_PIXELS, 0, null, 0, 0, 0, 0, 4096).status);
    try std.testing.expectEqual(@as(c_int, 5), c.pi_browser_session_call(node.session, c.PI_SESSION_PIXELS, 0, null, 0, 0, 0, 0, 4096).status);
    const rgba = [_]u8{ 20, 80, 160, 255 } ** 4;
    const first = c.pi_session_call(node.session, c.PI_SESSION_RGBA, 0, &rgba, rgba.len, 2, 2, 0, 4096);
    try std.testing.expectEqual(@as(c_int, 0), first.status);
    const second = c.pi_browser_session_call(browser.session, c.PI_SESSION_RGBA, 0, &rgba, rgba.len, 2, 2, 0, 4096);
    try std.testing.expectEqual(@as(c_int, 0), second.status);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_session_destroy(node.session));
    node_open = false;
    const encoded = c.pi_browser_session_call(browser.session, c.PI_SESSION_PNG, second.image, null, 0, 0, 0, 0, 4096);
    defer if (encoded.bytes != null) owner.allocator.free(encoded.bytes[0..encoded.length]);
    defer if (encoded.message != null) owner.allocator.free(encoded.message[0..encoded.message_length]);
    try std.testing.expectEqual(@as(c_int, 0), encoded.status);
    try std.testing.expect(encoded.length > 8);
    try std.testing.expectEqualSlices(u8, &.{ 137, 80, 78, 71, 13, 10, 26, 10 }, encoded.bytes[0..8]);
    try std.testing.expectEqual(@as(c_int, 0), c.pi_browser_session_call(browser.session, c.PI_SESSION_FREE, second.image, null, 0, 0, 0, 0, 4096).status);
}
