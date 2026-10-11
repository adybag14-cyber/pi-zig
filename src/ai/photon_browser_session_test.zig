const std = @import("std");
const c = @cImport({
    @cInclude("session_browser_api.h");
});
const Session = struct {
    gpa: std.mem.Allocator,
    raw: *c.PiPhotonSession,
    fn allocate(context: ?*anyopaque, length: usize, alignment: usize) callconv(.c) ?*anyopaque {
        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(context.?));
        return allocator.rawAlloc(length, .fromByteUnits(alignment), @returnAddress());
    }
    fn release(context: ?*anyopaque, pointer: ?*anyopaque, length: usize, alignment: usize) callconv(.c) void {
        const allocator: *std.mem.Allocator = @ptrCast(@alignCast(context.?));
        const bytes: [*]u8 = @ptrCast(pointer.?);
        allocator.rawFree(bytes[0..length], .fromByteUnits(alignment), @returnAddress());
    }
    fn init(gpa: std.mem.Allocator) !*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        const created = c.pi_browser_session_create(.{ .context = &self.gpa, .allocate = allocate, .release = release }, 32 * 1024 * 1024);
        if (created.status != 0) return if (created.status == 1) error.OutOfMemory else error.CodecSessionCreationFailed;
        self.raw = created.session.?;
        return self;
    }
    fn deinit(self: *Session) void {
        const gpa = self.gpa;
        std.debug.assert(c.pi_browser_session_destroy(self.raw) == 0);
        gpa.destroy(self);
    }
    fn call(self: *Session, op: c.enum_PiSessionOperation, handle: u32, input: ?[]const u8, width: u32, height: u32, quality: u32) c.PiSessionReply {
        return c.pi_browser_session_call(self.raw, op, handle, if (input) |bytes| bytes.ptr else null, if (input) |bytes| bytes.len else 0, width, height, quality, std.math.maxInt(u32));
    }
    fn checked(self: *Session, reply: c.PiSessionReply) !c.PiSessionReply {
        if (reply.status == 0) return reply;
        self.freeReply(reply);
        return if (reply.status == 1) error.OutOfMemory else error.CodecSessionOperationFailed;
    }
    fn freeReply(self: *Session, reply: c.PiSessionReply) void {
        if (reply.bytes != null) self.gpa.free(reply.bytes[0..reply.length]);
        if (reply.message != null) self.gpa.free(reply.message[0..reply.message_length]);
    }
};
fn pixels(bytes: []u8) void {
    for (bytes, 0..) |*value, index| value.* = if (index % 4 == 3) (if (index % 11 != 0) 255 else 64) else @intCast((index * 37 + 23) % 256);
}
fn golden(name: []const u8, bytes: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/photon-browser-source-byte-goldens.json"), .{});
    defer parsed.deinit();
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    for (parsed.value.object.get("results").?.array.items) |item| {
        if (!std.mem.eql(u8, name, item.object.get("file").?.string)) continue;
        try std.testing.expectEqualStrings(item.object.get("sourceSha256").?.string, &actual);
        return;
    }
    return error.MissingGolden;
}
test "persistent C sessions match all twenty four actual codec output hashes" {
    const gpa = std.testing.allocator;
    for ([_][2]u32{ .{ 1, 1 }, .{ 8, 5 }, .{ 32, 24 } }) |dims| {
        const session = try Session.init(gpa);
        defer session.deinit();
        const rgba = try gpa.alloc(u8, dims[0] * dims[1] * 4);
        defer gpa.free(rgba);
        pixels(rgba);
        const image = try session.checked(session.call(c.PI_SESSION_RGBA, 0, rgba, dims[0], dims[1], 0));
        const png = try session.checked(session.call(c.PI_SESSION_PNG, image.image, null, 0, 0, 0));
        defer session.freeReply(png);
        var name: [128]u8 = undefined;
        try golden(try std.fmt.bufPrint(&name, "c033-{d}x{d}.png", .{ dims[0], dims[1] }), png.bytes[0..png.length]);
        for ([_]u32{ 80, 85, 70, 55, 40 }) |quality| {
            const jpeg = try session.checked(session.call(c.PI_SESSION_JPEG, image.image, null, 0, 0, quality));
            defer session.freeReply(jpeg);
            try golden(try std.fmt.bufPrint(&name, "c033-{d}x{d}-q{d}.jpg", .{ dims[0], dims[1], quality }), jpeg.bytes[0..jpeg.length]);
        }
        const decoded = try session.checked(session.call(c.PI_SESSION_DECODE, 0, png.bytes[0..png.length], 0, 0, 0));
        const decoded_pixels = try session.checked(session.call(c.PI_SESSION_PIXELS, decoded.image, null, 0, 0, 0));
        defer session.freeReply(decoded_pixels);
        try golden(try std.fmt.bufPrint(&name, "c033-{d}x{d}-decoded.rgba", .{ dims[0], dims[1] }), decoded_pixels.bytes[0..decoded_pixels.length]);
        const scaled = try session.checked(session.call(c.PI_SESSION_RESIZE, decoded.image, null, @max(1, dims[0] * 3 / 4), @max(1, dims[1] * 3 / 4), 0));
        const scaled_pixels = try session.checked(session.call(c.PI_SESSION_PIXELS, scaled.image, null, 0, 0, 0));
        defer session.freeReply(scaled_pixels);
        try golden(try std.fmt.bufPrint(&name, "c033-{d}x{d}-resized.rgba", .{ dims[0], dims[1] }), scaled_pixels.bytes[0..scaled_pixels.length]);
        _ = try session.checked(session.call(c.PI_SESSION_FREE, scaled.image, null, 0, 0, 0));
        _ = try session.checked(session.call(c.PI_SESSION_FREE, decoded.image, null, 0, 0, 0));
        _ = try session.checked(session.call(c.PI_SESSION_FREE, image.image, null, 0, 0, 0));
    }
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const session = try Session.init(gpa);
    defer session.deinit();
    var rgba: [160]u8 = undefined;
    pixels(&rgba);
    const image = try session.checked(session.call(c.PI_SESSION_RGBA, 0, &rgba, 8, 5, 0));
    const scaled = try session.checked(session.call(c.PI_SESSION_RESIZE, image.image, null, 6, 3, 0));
    const encoded = try session.checked(session.call(c.PI_SESSION_PNG, scaled.image, null, 0, 0, 0));
    defer session.freeReply(encoded);
    _ = try session.checked(session.call(c.PI_SESSION_FREE, scaled.image, null, 0, 0, 0));
    _ = try session.checked(session.call(c.PI_SESSION_FREE, image.image, null, 0, 0, 0));
}
test "persistent session releases every allocation failure and recovers with a fresh session" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    try allocationCase(std.testing.allocator);
}
test "real Rust cleanup error survives trap and whole module release without a hardcoded error" {
    const gpa = std.testing.allocator;
    const session = try Session.init(gpa);
    var rgba: [160]u8 = undefined;
    pixels(&rgba);
    const image = try session.checked(session.call(c.PI_SESSION_RGBA, 0, &rgba, 8, 5, 0));
    const failed = session.call(c.PI_SESSION_RESIZE, image.image, null, std.math.maxInt(u32), std.math.maxInt(u32), 0);
    session.freeReply(failed);
    try std.testing.expectEqual(@as(c_int, 2), failed.status);
    const freed = session.call(c.PI_SESSION_FREE, image.image, null, 0, 0, 0);
    defer if (freed.message != null) gpa.free(freed.message[0..freed.message_length]);
    session.deinit();
    try std.testing.expectEqual(@as(c_int, 2), freed.status);
    try std.testing.expectEqualStrings("attempted to take ownership of Rust value while it was borrowed", freed.message[0..freed.message_length]);
    try allocationCase(gpa);
}
test "persistent session rejects cross thread calls without retiring the owner" {
    const session = try Session.init(std.testing.allocator);
    defer session.deinit();
    const Probe = struct {
        session: *Session,
        status: c_int = 0,
        fn run(self: *@This()) void {
            self.status = self.session.call(c.PI_SESSION_PIXELS, 0, null, 0, 0, 0).status;
        }
    };
    var probe: Probe = .{ .session = session };
    const thread = try std.Thread.spawn(.{}, Probe.run, .{&probe});
    thread.join();
    try std.testing.expectEqual(@as(c_int, 5), probe.status);
}

test "zero sized resize exposes an empty pixel vector with no hidden allocation" {
    const session = try Session.init(std.testing.allocator);
    defer session.deinit();
    var rgba: [160]u8 = undefined;
    pixels(&rgba);
    const image = try session.checked(session.call(c.PI_SESSION_RGBA, 0, &rgba, 8, 5, 0));
    const scaled = try session.checked(session.call(c.PI_SESSION_RESIZE, image.image, null, 0, 0, 0));
    const empty = try session.checked(session.call(c.PI_SESSION_PIXELS, scaled.image, null, 0, 0, 0));
    defer session.freeReply(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.length);
    try std.testing.expect(empty.bytes == null);
    _ = try session.checked(session.call(c.PI_SESSION_FREE, scaled.image, null, 0, 0, 0));
    _ = try session.checked(session.call(c.PI_SESSION_FREE, image.image, null, 0, 0, 0));
}
