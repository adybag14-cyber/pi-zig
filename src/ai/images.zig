//! Image helpers: detect mime, load file as base64 for multimodal messages.
const std = @import("std");
const Io = std.Io;

pub fn detectMime(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".png") or std.mem.endsWith(u8, path, ".PNG")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg") or std.mem.endsWith(u8, path, ".JPG")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".webp")) return "image/webp";
    return "application/octet-stream";
}

/// Load image file and return base64 (caller frees).
pub fn loadBase64(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024));
    defer gpa.free(data);
    const enc = std.base64.standard.Encoder;
    const out_len = enc.calcSize(data.len);
    const out = try gpa.alloc(u8, out_len);
    _ = enc.encode(out, data);
    return out;
}

test "detectMime" {
    try std.testing.expectEqualStrings("image/png", detectMime("a/b/c.PNG"));
    try std.testing.expectEqualStrings("image/jpeg", detectMime("x.jpg"));
}
