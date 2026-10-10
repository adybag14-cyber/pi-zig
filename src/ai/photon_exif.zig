//! Source-compatible JPEG/WebP orientation metadata, with forward-progress
//! bounds for malformed RIFF chunk lengths instead of an unbounded scan.
const std = @import("std");
fn byte(bytes: []const u8, index: i64) u8 {
    if (index < 0 or index >= bytes.len) return 0;
    return bytes[@intCast(index)];
}
fn word(bytes: []const u8, at: i64, little: bool) u16 {
    const a: u16 = byte(bytes, at);
    const b: u16 = byte(bytes, at + 1);
    return if (little) a | (b << 8) else (a << 8) | b;
}
fn dword(bytes: []const u8, at: i64, little: bool) i64 {
    const a: u32 = word(bytes, at, little);
    const b: u32 = word(bytes, at + 2, little);
    const value: u32 = if (little) a | (b << 16) else (a << 16) | b;
    // Upstream's little-endian bitwise result is signed; its big-endian
    // branch explicitly uses >>>0. Preserve that observable distinction.
    return if (little) @as(i32, @bitCast(value)) else value;
}
fn exifHeader(bytes: []const u8, at: i64) bool {
    const expected = "Exif\x00\x00";
    for (expected, 0..) |value, index| if (byte(bytes, at + @as(i64, @intCast(index))) != value) return false;
    return true;
}
fn tiff(bytes: []const u8, start: i64) u8 {
    if (start + 8 > bytes.len) return 1;
    const little = word(bytes, start, false) == 0x4949;
    const first = start + dword(bytes, start + 4, little);
    if (first + 2 > bytes.len) return 1;
    const count = word(bytes, first, little);
    for (0..count) |index| {
        const entry = first + 2 + @as(i64, @intCast(index)) * 12;
        if (entry + 12 > bytes.len) return 1;
        if (word(bytes, entry, little) == 0x112) {
            const value = word(bytes, entry + 8, little);
            return if (value >= 1 and value <= 8) @intCast(value) else 1;
        }
    }
    return 1;
}
pub fn read(bytes: []const u8) u8 {
    if (bytes.len >= 2 and bytes[0] == 0xff and bytes[1] == 0xd8) {
        var offset: i64 = 2;
        while (offset < bytes.len - 1) {
            if (byte(bytes, offset) != 0xff) return 1;
            const marker = byte(bytes, offset + 1);
            if (marker == 0xff) {
                offset += 1;
                continue;
            }
            if (marker == 0xe1) {
                if (offset + 4 >= bytes.len) return 1;
                const data = offset + 4;
                if (data + 6 > bytes.len) return 1;
                if (exifHeader(bytes, data)) return tiff(bytes, data + 6);
            }
            if (offset + 4 > bytes.len) return 1;
            offset += 2 + @as(i64, word(bytes, offset + 2, false));
        }
    } else if (bytes.len >= 12 and std.mem.eql(u8, bytes[0..4], "RIFF") and std.mem.eql(u8, bytes[8..12], "WEBP")) {
        var offset: i64 = 12;
        while (offset >= 0 and offset + 8 <= bytes.len) {
            const size = dword(bytes, offset + 4, true);
            const data = offset + 8;
            const begin: usize = @intCast(offset);
            if (std.mem.eql(u8, bytes[begin..][0..4], "EXIF")) {
                if (data + size > bytes.len) return 1;
                return tiff(bytes, if (size >= 6 and exifHeader(bytes, data)) data + 6 else data);
            }
            const next = data + size + @rem(size, 2);
            if (next <= offset) return 1;
            offset = next;
        }
    }
    return 1;
}

test "metadata reader matches sixteen actual Source little and big endian orientations" {
    const gpa = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/photon-exif-c5-source.json"), .{});
    defer parsed.deinit();
    for (parsed.value.object.get("rows").?.array.items) |row| {
        const encoded = row.object.get("metadata").?.string;
        const bytes = try gpa.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(encoded));
        defer gpa.free(bytes);
        try std.base64.standard.Decoder.decode(bytes, encoded);
        try std.testing.expectEqual(row.object.get("orientation").?.integer, read(bytes));
    }
}
test "malformed RIFF chunks cannot stall the orientation scan" {
    const bytes = [_]u8{ 'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P', 'J', 'U', 'N', 'K', 0xf8, 0xff, 0xff, 0xff };
    try std.testing.expectEqual(@as(u8, 1), read(&bytes));
}
