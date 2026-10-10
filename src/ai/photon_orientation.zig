//! Native pixel orientation; source comparisons are captured outside the repo.
const std = @import("std");
const photon = @import("photon_native.zig");

pub fn apply(gpa: std.mem.Allocator, image: *photon.Image, orientation: u8) !void {
    const w: usize = image.dimensions.width;
    const h: usize = image.dimensions.height;
    const count = std.math.mul(usize, w, h) catch return error.InvalidImageDimensions;
    const length = std.math.mul(usize, count, 4) catch return error.InvalidImageDimensions;
    if (length != image.bytes.len) return error.InvalidImageDimensions;
    switch (orientation) {
        2, 3, 4 => {
            if (orientation != 4) for (0..h) |y| {
                for (0..w / 2) |x| {
                    const left = (y * w + x) * 4;
                    const right = (y * w + w - 1 - x) * 4;
                    for (0..4) |channel| std.mem.swap(u8, &image.bytes[left + channel], &image.bytes[right + channel]);
                }
            };
            if (orientation != 2) for (0..h / 2) |y| {
                for (0..w) |x| {
                    const top = (y * w + x) * 4;
                    const bottom = ((h - 1 - y) * w + x) * 4;
                    for (0..4) |channel| std.mem.swap(u8, &image.bytes[top + channel], &image.bytes[bottom + channel]);
                }
            };
        },
        5...8 => {
            const pixels = try gpa.alloc(u8, length);
            for (0..h) |y| {
                for (0..w) |x| {
                    const source = (y * w + x) * 4;
                    const destination = (switch (orientation) {
                        5 => x * h + y,
                        6 => x * h + h - 1 - y,
                        7 => (w - 1 - x) * h + h - 1 - y,
                        8 => (w - 1 - x) * h + y,
                        else => unreachable,
                    }) * 4;
                    @memcpy(pixels[destination..][0..4], image.bytes[source..][0..4]);
                }
            }
            gpa.free(image.bytes);
            image.bytes = pixels;
            image.dimensions = .{ .width = @intCast(h), .height = @intCast(w) };
        },
        else => {},
    }
}

test "pixel orientations match all sixteen actual Source TIFF-order cases" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/photon-exif-c5-source.json"), .{});
    defer parsed.deinit();
    for (parsed.value.object.get("rows").?.array.items) |row| {
        const bytes = try gpa.alloc(u8, 160);
        var image: photon.Image = .{ .bytes = bytes, .dimensions = .{ .width = 8, .height = 5 } };
        defer image.deinit(gpa);
        for (bytes, 0..) |*byte, index| byte.* = if (index % 4 == 3) (if (index % 11 != 0) 255 else 64) else @intCast((index * 37 + 23) % 256);
        try apply(gpa, &image, @intCast(row.object.get("orientation").?.integer));
        try std.testing.expectEqual(row.object.get("width").?.integer, image.dimensions.width);
        try std.testing.expectEqual(row.object.get("height").?.integer, image.dimensions.height);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(image.bytes, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        try std.testing.expectEqualStrings(row.object.get("sha256").?.string, &hex);
    }
}
