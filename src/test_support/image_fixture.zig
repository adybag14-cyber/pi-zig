//! Independent structural image fixtures and PNG/JPEG dimension assertions.
const std = @import("std");
pub const Dimensions = struct { mime: []const u8, width: u32, height: u32 };
pub fn dimensions(bytes: []const u8) !Dimensions {
    if (bytes.len >= 24 and std.mem.startsWith(u8, bytes, "\x89PNG\r\n\x1a\n")) return .{ .mime = "image/png", .width = std.mem.readInt(u32, bytes[16..20], .big), .height = std.mem.readInt(u32, bytes[20..24], .big) };
    if (bytes.len >= 2 and bytes[0] == 0xff and bytes[1] == 0xd8) {
        var pos: usize = 2;
        while (pos + 3 < bytes.len) {
            if (bytes[pos] != 0xff) {
                pos += 1;
                continue;
            }
            while (pos < bytes.len and bytes[pos] == 0xff) pos += 1;
            if (pos >= bytes.len) break;
            const marker = bytes[pos];
            pos += 1;
            if (marker == 0xd8 or marker == 0xd9 or (marker >= 0xd0 and marker <= 0xd7)) continue;
            if (pos + 2 > bytes.len) break;
            const length = std.mem.readInt(u16, bytes[pos..][0..2], .big);
            if (length < 2 or length > bytes.len - pos) break;
            if (length >= 7 and (marker == 0xc0 or marker == 0xc1 or marker == 0xc2 or marker == 0xc3 or marker == 0xc5 or marker == 0xc6 or marker == 0xc7 or marker == 0xc9 or marker == 0xca or marker == 0xcb or marker == 0xcd or marker == 0xce or marker == 0xcf)) return .{ .mime = "image/jpeg", .width = std.mem.readInt(u16, bytes[pos + 5 ..][0..2], .big), .height = std.mem.readInt(u16, bytes[pos + 3 ..][0..2], .big) };
            pos += length;
        }
    }
    return error.UnsupportedImageOutput;
}
pub fn decode(gpa: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
    errdefer gpa.free(bytes);
    try std.base64.standard.Decoder.decode(bytes, encoded);
    return bytes;
}
pub fn assertDimensions(gpa: std.mem.Allocator, encoded: []const u8, w: u32, h: u32) !Dimensions {
    const bytes = try decode(gpa, encoded);
    defer gpa.free(bytes);
    const value = try dimensions(bytes);
    try std.testing.expectEqual(w, value.width);
    try std.testing.expectEqual(h, value.height);
    return value;
}
pub fn bmp(gpa: std.mem.Allocator) ![]u8 {
    const w: u32 = 32;
    const h: u32 = 16;
    const row: usize = 96;
    const pixel_bytes = row * h;
    const data = try gpa.alloc(u8, 54 + pixel_bytes);
    @memset(data, 0);
    @memcpy(data[0..2], "BM");
    std.mem.writeInt(u32, data[2..6], @intCast(data.len), .little);
    std.mem.writeInt(u32, data[10..14], 54, .little);
    std.mem.writeInt(u32, data[14..18], 40, .little);
    std.mem.writeInt(u32, data[18..22], w, .little);
    std.mem.writeInt(u32, data[22..26], h, .little);
    std.mem.writeInt(u16, data[26..28], 1, .little);
    std.mem.writeInt(u16, data[28..30], 24, .little);
    std.mem.writeInt(u32, data[34..38], @intCast(pixel_bytes), .little);
    for (0..h) |y| for (0..w) |x| {
        const off = 54 + y * row + x * 3;
        data[off] = @truncate(x * 9);
        data[off + 1] = @truncate(y * 17);
        data[off + 2] = @truncate((x + y) * 5);
    };
    return data;
}
pub fn exif(gpa: std.mem.Allocator, jpeg: []const u8) ![]u8 {
    if (jpeg.len < 2 or jpeg[0] != 0xff or jpeg[1] != 0xd8) return error.InvalidJpegFixture;
    const payload = "Exif\x00\x00II\x2a\x00\x08\x00\x00\x00\x01\x00\x12\x01\x03\x00\x01\x00\x00\x00\x06\x00\x00\x00\x00\x00\x00\x00";
    const result = try gpa.alloc(u8, jpeg.len + 4 + payload.len);
    @memcpy(result[0..2], jpeg[0..2]);
    @memcpy(result[2..4], "\xff\xe1");
    std.mem.writeInt(u16, result[4..6], payload.len + 2, .big);
    @memcpy(result[6..][0..payload.len], payload);
    @memcpy(result[6 + payload.len ..], jpeg[2..]);
    return result;
}
pub fn ancillary(gpa: std.mem.Allocator, png: []const u8) ![]u8 {
    const marker = std.mem.lastIndexOf(u8, png, "IEND") orelse return error.MissingPngEnd;
    if (marker < 4) return error.InvalidPngEnd;
    const insert = marker - 4;
    const payload_len = 4_000_000;
    const result = try gpa.alloc(u8, png.len + 12 + payload_len);
    @memcpy(result[0..insert], png[0..insert]);
    std.mem.writeInt(u32, result[insert..][0..4], payload_len, .big);
    @memcpy(result[insert + 4 ..][0..4], "piDA");
    const payload = result[insert + 8 ..][0..payload_len];
    @memset(payload, 'x');
    @memcpy(payload[0..14], "checkpoint174\x00");
    std.mem.writeInt(u32, result[insert + 8 + payload_len ..][0..4], std.hash.Crc32.hash(result[insert + 4 .. insert + 8 + payload_len]), .big);
    @memcpy(result[insert + 12 + payload_len ..], png[insert..]);
    return result;
}
