//! Optional owned image preparation capability. No processor is selected by
//! default; read can pass inline formats through using their header limits.
const std = @import("std");
pub const Limits = struct { maxWidth: f64 = 2000, maxHeight: f64 = 2000, maxBytes: f64 = 4.5 * 1024 * 1024 };
pub const Dimensions = struct { width: f64, height: f64 };
pub const Resize = struct { from: Dimensions, to: Dimensions };
pub const Prepared = struct {
    data: []u8,
    mimeType: []u8,
    resized: ?Resize = null,
    convertedFrom: ?[]u8 = null,
    pub fn deinit(self: *Prepared, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
        gpa.free(self.mimeType);
        if (self.convertedFrom) |value| gpa.free(value);
        self.* = undefined;
    }
};
pub const Processor = struct {
    context: ?*anyopaque = null,
    /// The caller owns every returned allocation, including conversion notes.
    prepare: *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8, Limits) anyerror!?Prepared,
};
pub const Model = struct { vision: bool = true, limits: Limits = .{} };
pub fn inlineType(mime: []const u8) bool {
    for ([_][]const u8{ "image/png", "image/jpeg", "image/gif", "image/webp" }) |accepted| if (std.mem.eql(u8, accepted, mime)) return true;
    return false;
}
fn be16(bytes: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, bytes[at..][0..2], .big);
}
fn le16(bytes: []const u8, at: usize) u16 {
    return std.mem.readInt(u16, bytes[at..][0..2], .little);
}
fn be32(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .big);
}
fn le32(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
pub fn dimensions(bytes: []const u8, mime: []const u8) ?Dimensions {
    if (std.mem.eql(u8, mime, "image/png")) return if (bytes.len < 24) null else .{ .width = @floatFromInt(be32(bytes, 16)), .height = @floatFromInt(be32(bytes, 20)) };
    if (std.mem.eql(u8, mime, "image/gif")) return if (bytes.len < 10) null else .{ .width = @floatFromInt(le16(bytes, 6)), .height = @floatFromInt(le16(bytes, 8)) };
    if (std.mem.eql(u8, mime, "image/webp")) {
        if (bytes.len < 30) return null;
        if (std.mem.eql(u8, bytes[12..16], "VP8 ")) return .{ .width = @floatFromInt(le16(bytes, 26) & 0x3fff), .height = @floatFromInt(le16(bytes, 28) & 0x3fff) };
        if (std.mem.eql(u8, bytes[12..16], "VP8L")) {
            const bits = le32(bytes, 21);
            return .{ .width = @floatFromInt((bits & 0x3fff) + 1), .height = @floatFromInt(((bits >> 14) & 0x3fff) + 1) };
        }
        if (std.mem.eql(u8, bytes[12..16], "VP8X")) return .{ .width = @floatFromInt(@as(u32, le16(bytes, 24)) + (@as(u32, bytes[26]) << 16) + 1), .height = @floatFromInt(@as(u32, le16(bytes, 27)) + (@as(u32, bytes[29]) << 16) + 1) };
        return null;
    }
    if (std.mem.eql(u8, mime, "image/jpeg")) {
        var offset: usize = 2;
        while (offset + 9 <= bytes.len) {
            if (bytes[offset] != 0xff) return null;
            const marker = bytes[offset + 1];
            if (marker == 0xff) {
                offset += 1;
                continue;
            }
            if (marker >= 0xc0 and marker <= 0xcf and marker != 0xc4 and marker != 0xc8 and marker != 0xcc) return .{ .width = @floatFromInt(be16(bytes, offset + 7)), .height = @floatFromInt(be16(bytes, offset + 5)) };
            offset += 2 + @as(usize, be16(bytes, offset + 2));
        }
    }
    return null;
}
