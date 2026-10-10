//! Optional Durable image processor using its exact Photon browser 0.3.3 codec.
const std = @import("std");
const photon = @import("../ai/photon_browser.zig");
const orientation = @import("../ai/photon_orientation.zig");
const exif = @import("photon_exif.zig");
const processor = @import("image_processor.zig");
pub fn capability() processor.Processor {
    return .{ .prepare = prepare };
}
fn base64Length(bytes: []const u8) f64 {
    return @floatFromInt(std.base64.standard.Encoder.calcSize(bytes.len));
}
fn encode(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, source_mime: []const u8, resized: ?processor.Resize) !processor.Prepared {
    const data = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    errdefer gpa.free(data);
    _ = std.base64.standard.Encoder.encode(data, bytes);
    const owned_mime = try gpa.dupe(u8, mime);
    errdefer gpa.free(owned_mime);
    return .{ .data = data, .mimeType = owned_mime, .resized = resized, .convertedFrom = if (std.mem.eql(u8, mime, source_mime)) null else try gpa.dupe(u8, source_mime) };
}
pub fn prepare(_: ?*anyopaque, gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, limits: processor.Limits) !?processor.Prepared {
    return attempt(gpa, bytes, mime, limits) catch |cause| switch (cause) {
        error.ImageCodecFailure, error.InvalidImageInput, error.InvalidImageDimensions => null,
        else => return cause,
    };
}
fn attempt(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, limits: processor.Limits) !?processor.Prepared {
    const position = exif.read(bytes);
    var original = try photon.transform(gpa, .{ .encoded = bytes }, .{ .format = .rgba });
    defer original.deinit(gpa);
    const decoded_width: f64 = @floatFromInt(original.dimensions.width);
    const decoded_height: f64 = @floatFromInt(original.dimensions.height);
    if (processor.inlineType(mime) and position == 1 and decoded_width <= limits.maxWidth and decoded_height <= limits.maxHeight and base64Length(bytes) <= limits.maxBytes) return try encode(gpa, bytes, mime, mime, null);
    try orientation.apply(gpa, &original, position);
    const width: f64 = @floatFromInt(original.dimensions.width);
    const height: f64 = @floatFromInt(original.dimensions.height);
    // Math.min/Math.max propagate NaN. The resulting zero WASM dimensions trap.
    if (std.math.isNan(limits.maxWidth) or std.math.isNan(limits.maxHeight)) return null;
    const scale = @min(1, limits.maxWidth / width, limits.maxHeight / height);
    var target_width = @max(1, @floor(width * scale + 0.5));
    var target_height = @max(1, @floor(height * scale + 0.5));
    while (true) {
        const same = target_width == width and target_height == height;
        var scaled: ?photon.Image = null;
        defer if (scaled) |*value| value.deinit(gpa);
        if (!same) scaled = try photon.transform(gpa, .{ .rgba = .{ .bytes = original.bytes, .dimensions = original.dimensions } }, .{ .format = .rgba, .resize = .{ .width = @intFromFloat(target_width), .height = @intFromFloat(target_height) } });
        const chosen = if (scaled) |value| value else original;
        const input: photon.Input = .{ .rgba = .{ .bytes = chosen.bytes, .dimensions = chosen.dimensions } };
        const jpeg_first = std.mem.eql(u8, mime, "image/jpeg");
        const qualities = [_]u32{ 80, 70, 55, 40 };
        for (0..5) |i| {
            const png = if (jpeg_first) i == 4 else i == 0;
            const quality = if (png) 80 else qualities[if (jpeg_first) i else i - 1];
            var candidate = try photon.transform(gpa, input, .{ .format = if (png) .png else .jpeg, .quality = quality });
            defer candidate.deinit(gpa);
            if (base64Length(candidate.bytes) <= limits.maxBytes) return try encode(gpa, candidate.bytes, if (png) "image/png" else "image/jpeg", mime, if (same) null else .{ .from = .{ .width = width, .height = height }, .to = .{ .width = target_width, .height = target_height } });
        }
        if (target_width == 1 and target_height == 1) return null;
        target_width = @max(1, @floor(target_width * 0.75));
        target_height = @max(1, @floor(target_height * 0.75));
    }
}
