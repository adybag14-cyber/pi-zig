//! Image helpers used by the CLI, session layer, and provider adapters.
//!
//! File extensions are not trusted for CLI attachments. `detectSupportedMime`
//! mirrors Pi's upstream magic-byte sniffer so renamed binary files are handled
//! correctly and malformed/APNG/JPEG-LS payloads are not sent as inline images.
const std = @import("std");
const Io = std.Io;

pub const sniff_bytes: usize = 4100;
const png_signature = [_]u8{ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a };

/// Detect a provider-supported inline image by its bytes, not its filename.
/// Returns a static MIME string or null for malformed/unsupported input.
pub fn detectSupportedMime(buffer: []const u8) ?[]const u8 {
    if (startsWith(buffer, &.{ 0xff, 0xd8, 0xff })) {
        // JPEG-LS uses FF D8 FF F7 and is not accepted by Pi's inline adapters.
        if (buffer.len > 3 and buffer[3] == 0xf7) return null;
        return "image/jpeg";
    }
    if (startsWith(buffer, &png_signature)) {
        if (!isPng(buffer) or isAnimatedPng(buffer)) return null;
        return "image/png";
    }
    if (startsWithAscii(buffer, 0, "GIF")) return "image/gif";
    if (startsWithAscii(buffer, 0, "RIFF") and startsWithAscii(buffer, 8, "WEBP")) return "image/webp";
    if (startsWithAscii(buffer, 0, "BM") and isBmp(buffer)) return "image/bmp";
    return null;
}

/// Extension-only compatibility helper retained for callers that do not yet
/// have the bytes. New attachment code should prefer `detectSupportedMime`.
pub fn detectMime(path: []const u8) []const u8 {
    if (endsWithAsciiIgnoreCase(path, ".png")) return "image/png";
    if (endsWithAsciiIgnoreCase(path, ".jpg") or endsWithAsciiIgnoreCase(path, ".jpeg")) return "image/jpeg";
    if (endsWithAsciiIgnoreCase(path, ".gif")) return "image/gif";
    if (endsWithAsciiIgnoreCase(path, ".webp")) return "image/webp";
    if (endsWithAsciiIgnoreCase(path, ".bmp")) return "image/bmp";
    return "application/octet-stream";
}

/// Load a file and return standard-padded base64 (caller frees).
pub fn loadBase64(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024));
    defer gpa.free(data);
    return encodeBase64(gpa, data);
}

pub fn encodeBase64(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const enc = std.base64.standard.Encoder;
    const out = try gpa.alloc(u8, enc.calcSize(bytes.len));
    _ = enc.encode(out, bytes);
    return out;
}

fn isPng(buffer: []const u8) bool {
    return buffer.len >= 16 and readU32Be(buffer, png_signature.len) == 13 and startsWithAscii(buffer, 12, "IHDR");
}

fn isAnimatedPng(buffer: []const u8) bool {
    var offset: usize = png_signature.len;
    while (offset + 8 <= buffer.len) {
        const chunk_len_u32 = readU32Be(buffer, offset);
        const chunk_len: usize = @intCast(chunk_len_u32);
        const chunk_type_offset = offset + 4;
        if (startsWithAscii(buffer, chunk_type_offset, "acTL")) return true;
        if (startsWithAscii(buffer, chunk_type_offset, "IDAT")) return false;

        const after_header = std.math.add(usize, offset, 8) catch return false;
        const after_data = std.math.add(usize, after_header, chunk_len) catch return false;
        const next = std.math.add(usize, after_data, 4) catch return false; // CRC
        if (next <= offset or next > buffer.len) return false;
        offset = next;
    }
    return false;
}

fn isBmp(buffer: []const u8) bool {
    if (buffer.len < 26) return false;
    const declared_file_size = readU32Le(buffer, 2);
    const pixel_data_offset = readU32Le(buffer, 10);
    const dib_header_size = readU32Le(buffer, 14);
    if (declared_file_size != 0 and declared_file_size < 26) return false;
    if (@as(u64, pixel_data_offset) < @as(u64, 14) + dib_header_size) return false;
    if (declared_file_size != 0 and pixel_data_offset >= declared_file_size) return false;

    var color_planes: u16 = 0;
    var bits_per_pixel: u16 = 0;
    if (dib_header_size == 12) {
        color_planes = readU16Le(buffer, 22);
        bits_per_pixel = readU16Le(buffer, 24);
    } else if (dib_header_size >= 40 and dib_header_size <= 124) {
        if (buffer.len < 30) return false;
        color_planes = readU16Le(buffer, 26);
        bits_per_pixel = readU16Le(buffer, 28);
    } else return false;

    if (color_planes != 1) return false;
    return switch (bits_per_pixel) {
        1, 4, 8, 16, 24, 32 => true,
        else => false,
    };
}

fn readU16Le(buffer: []const u8, offset: usize) u16 {
    if (offset + 2 > buffer.len) return 0;
    return @as(u16, buffer[offset]) | (@as(u16, buffer[offset + 1]) << 8);
}

fn readU32Be(buffer: []const u8, offset: usize) u32 {
    if (offset + 4 > buffer.len) return 0;
    return (@as(u32, buffer[offset]) << 24) |
        (@as(u32, buffer[offset + 1]) << 16) |
        (@as(u32, buffer[offset + 2]) << 8) |
        @as(u32, buffer[offset + 3]);
}

fn readU32Le(buffer: []const u8, offset: usize) u32 {
    if (offset + 4 > buffer.len) return 0;
    return @as(u32, buffer[offset]) |
        (@as(u32, buffer[offset + 1]) << 8) |
        (@as(u32, buffer[offset + 2]) << 16) |
        (@as(u32, buffer[offset + 3]) << 24);
}

fn startsWith(buffer: []const u8, bytes: []const u8) bool {
    return buffer.len >= bytes.len and std.mem.eql(u8, buffer[0..bytes.len], bytes);
}

fn startsWithAscii(buffer: []const u8, offset: usize, text: []const u8) bool {
    return offset <= buffer.len and text.len <= buffer.len - offset and std.mem.eql(u8, buffer[offset .. offset + text.len], text);
}

fn endsWithAsciiIgnoreCase(input: []const u8, suffix: []const u8) bool {
    if (suffix.len > input.len) return false;
    const tail = input[input.len - suffix.len ..];
    for (tail, suffix) |a, b| if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    return true;
}

test "detectSupportedMime recognizes supported magic bytes" {
    const png = [_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 'I', 'H', 'D', 'R' };
    try std.testing.expectEqualStrings("image/png", detectSupportedMime(&png).?);
    try std.testing.expectEqualStrings("image/jpeg", detectSupportedMime(&.{ 0xff, 0xd8, 0xff, 0xe0 }).?);
    try std.testing.expectEqualStrings("image/gif", detectSupportedMime("GIF89a").?);
    try std.testing.expectEqualStrings("image/webp", detectSupportedMime("RIFF0000WEBP").?);
}

test "detectSupportedMime rejects JPEG-LS and animated PNG" {
    try std.testing.expect(detectSupportedMime(&.{ 0xff, 0xd8, 0xff, 0xf7 }) == null);
    var apng = [_]u8{0} ** (8 + 25 + 12);
    @memcpy(apng[0..8], &png_signature);
    apng[11] = 13;
    @memcpy(apng[12..16], "IHDR");
    // Next chunk begins after 4-byte length, 4-byte type, 13-byte data, 4-byte CRC.
    @memcpy(apng[37..41], "acTL");
    try std.testing.expect(detectSupportedMime(&apng) == null);
}

test "detectSupportedMime validates BMP structure" {
    var bmp = [_]u8{0} ** 54;
    bmp[0] = 'B';
    bmp[1] = 'M';
    bmp[2] = 100;
    bmp[10] = 54;
    bmp[14] = 40;
    bmp[26] = 1;
    bmp[28] = 24;
    try std.testing.expectEqualStrings("image/bmp", detectSupportedMime(&bmp).?);
    bmp[26] = 2;
    try std.testing.expect(detectSupportedMime(&bmp) == null);
}

test "detectMime remains case insensitive" {
    try std.testing.expectEqualStrings("image/png", detectMime("a/b/c.PNG"));
    try std.testing.expectEqualStrings("image/jpeg", detectMime("x.JPEG"));
    try std.testing.expectEqualStrings("image/bmp", detectMime("x.BmP"));
}

test "base64 encoding" {
    const out = try encodeBase64(std.testing.allocator, "hello");
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("aGVsbG8=", out);
}
