//! Durable's unsigned TIFF/RIFF offsets differ from the coding-agent parser.
const std = @import("std");
fn text(bytes: []const u8, at: usize, expected: []const u8) bool {
    return at <= bytes.len and expected.len <= bytes.len - at and std.mem.eql(u8, bytes[at..][0..expected.len], expected);
}
fn word(bytes: []const u8, at: usize, little: bool) u16 {
    return std.mem.readInt(u16, bytes[at..][0..2], if (little) .little else .big);
}
fn dword(bytes: []const u8, at: usize, little: bool) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], if (little) .little else .big);
}
fn start(bytes: []const u8) ?usize {
    if (text(bytes, 0, "\xff\xd8")) {
        var at: usize = 2;
        while (at <= bytes.len and bytes.len - at >= 4) {
            if (bytes[at] != 0xff) return null;
            if (bytes[at + 1] == 0xff) {
                at += 1;
                continue;
            }
            if (bytes[at + 1] == 0xe1 and text(bytes, at + 4, "Exif\x00\x00")) return at + 10;
            at += 2 + @as(usize, word(bytes, at + 2, false));
        }
    } else if (text(bytes, 0, "RIFF") and text(bytes, 8, "WEBP")) {
        var at: u64 = 12;
        while (at <= bytes.len and bytes.len - at >= 8) {
            const index: usize = @intCast(at);
            const size: u64 = dword(bytes, index + 4, true);
            if (text(bytes, index, "EXIF")) return index + (if (text(bytes, index + 8, "Exif\x00\x00")) @as(usize, 14) else 8);
            at += 8 + size + size % 2;
        }
    }
    return null;
}
pub fn read(bytes: []const u8) u8 {
    const tiff = start(bytes) orelse return 1;
    if (tiff > bytes.len or bytes.len - tiff < 8) return 1;
    const little = text(bytes, tiff, "II");
    const directory: u64 = @as(u64, tiff) + dword(bytes, tiff + 4, little);
    if (directory > bytes.len or bytes.len - directory < 2) return 1;
    const count = word(bytes, @intCast(directory), little);
    for (0..count) |i| {
        const entry = directory + 2 + i * 12;
        if (entry > bytes.len or bytes.len - entry < 12) return 1;
        const at: usize = @intCast(entry);
        if (word(bytes, at, little) == 0x112) {
            const value = word(bytes, at + 8, little);
            return if (value >= 1 and value <= 8) @intCast(value) else 1;
        }
    }
    return 1;
}
