const std = @import("std");
const photon = @import("photon_browser.zig");

fn expectSource(name: []const u8, bytes: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/photon-browser-source-byte-goldens.json"), .{});
    defer parsed.deinit();
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    for (parsed.value.object.get("results").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("file").?.string, name)) continue;
        try std.testing.expectEqualStrings(item.object.get("sourceSha256").?.string, &hex);
        return;
    }
    return error.MissingSourceImageGolden;
}
fn pixels(buffer: []u8) void {
    for (buffer, 0..) |*byte, index| byte.* = if (index % 4 == 3) (if (index % 11 != 0) 255 else 64) else @intCast((index * 37 + 23) % 256);
}
fn allocationOperation(gpa: std.mem.Allocator) !void {
    var rgba: [160]u8 = undefined;
    pixels(&rgba);
    var image = try photon.transform(gpa, .{ .rgba = .{ .bytes = &rgba, .dimensions = .{ .width = 8, .height = 5 } } }, .{ .resize = .{ .width = 6, .height = 3 } });
    defer image.deinit(gpa);
}
test "browser photon boundary matches all 24 genuine Source codec and Lanczos3 byte hashes" {
    const gpa = std.testing.allocator;
    for ([_]photon.Dimensions{ .{ .width = 1, .height = 1 }, .{ .width = 8, .height = 5 }, .{ .width = 32, .height = 24 } }) |dims| {
        const rgba = try gpa.alloc(u8, dims.width * dims.height * 4);
        defer gpa.free(rgba);
        pixels(rgba);
        const input: photon.Input = .{ .rgba = .{ .bytes = rgba, .dimensions = dims } };
        var png = try photon.transform(gpa, input, .{});
        defer png.deinit(gpa);
        try std.testing.expectEqual(dims, png.dimensions);
        var name: [128]u8 = undefined;
        try expectSource(try std.fmt.bufPrint(&name, "c033-{d}x{d}.png", .{ dims.width, dims.height }), png.bytes);
        for ([_]u32{ 80, 85, 70, 55, 40 }) |quality| {
            var jpeg = try photon.transform(gpa, input, .{ .format = .jpeg, .quality = quality });
            defer jpeg.deinit(gpa);
            try expectSource(try std.fmt.bufPrint(&name, "c033-{d}x{d}-q{d}.jpg", .{ dims.width, dims.height, quality }), jpeg.bytes);
        }
        var decoded = try photon.transform(gpa, .{ .encoded = png.bytes }, .{ .format = .rgba });
        defer decoded.deinit(gpa);
        try expectSource(try std.fmt.bufPrint(&name, "c033-{d}x{d}-decoded.rgba", .{ dims.width, dims.height }), decoded.bytes);
        var resized = try photon.transform(gpa, .{ .encoded = png.bytes }, .{ .format = .rgba, .resize = .{ .width = @max(1, dims.width * 3 / 4), .height = @max(1, dims.height * 3 / 4) } });
        defer resized.deinit(gpa);
        try expectSource(try std.fmt.bufPrint(&name, "c033-{d}x{d}-resized.rgba", .{ dims.width, dims.height }), resized.bytes);
    }
}
test "browser photon boundary releases every allocation failure and recovers from invalid input" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationOperation, .{});
    try std.testing.expectError(error.ImageCodecFailure, photon.transform(std.testing.allocator, .{ .encoded = "invalid image" }, .{}));
    try std.testing.expectError(error.InvalidImageInput, photon.transform(std.testing.allocator, .{ .rgba = .{ .bytes = "bad", .dimensions = .{ .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) } } }, .{}));
    try allocationOperation(std.testing.allocator);
}

const ConcurrentProbe = struct {
    failure: ?anyerror = null,
    fn run(self: *ConcurrentProbe) void {
        self.check() catch |cause| {
            self.failure = cause;
        };
    }
    fn check(_: *ConcurrentProbe) !void {
        var rgba: [160]u8 = undefined;
        pixels(&rgba);
        const input: photon.Input = .{ .rgba = .{ .bytes = &rgba, .dimensions = .{ .width = 8, .height = 5 } } };
        var baseline = std.testing.FailingAllocator.init(std.heap.page_allocator, .{});
        var initial = try photon.transform(baseline.allocator(), input, .{});
        initial.deinit(baseline.allocator());
        try std.testing.expectEqual(baseline.allocated_bytes, baseline.freed_bytes);
        for (0..baseline.allocations) |index| {
            var failing = std.testing.FailingAllocator.init(std.heap.page_allocator, .{ .fail_index = index });
            try std.testing.expectError(error.OutOfMemory, photon.transform(failing.allocator(), input, .{}));
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            try std.testing.expectError(error.ImageCodecFailure, photon.transform(std.heap.page_allocator, .{ .encoded = "invalid image" }, .{}));
            var recovered = try photon.transform(std.heap.page_allocator, input, .{});
            defer recovered.deinit(std.heap.page_allocator);
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(recovered.bytes, &digest, .{});
            const hex = std.fmt.bytesToHex(digest, .lower);
            try std.testing.expectEqualStrings("25687f3b640ce718c035ca22cec2c570af992c53b34a1f48f936b70fcc33fa56", &hex);
        }
    }
};
test "browser photon public boundary isolates concurrent callers across failures and recovery" {
    var first: ConcurrentProbe = .{};
    var second: ConcurrentProbe = .{};
    const a = try std.Thread.spawn(.{}, ConcurrentProbe.run, .{&first});
    const b = std.Thread.spawn(.{}, ConcurrentProbe.run, .{&second}) catch |cause| {
        a.join();
        return cause;
    };
    b.join();
    a.join();
    if (first.failure) |failure| return failure;
    if (second.failure) |failure| return failure;
}
