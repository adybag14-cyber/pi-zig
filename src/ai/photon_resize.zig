//! External resize-strategy draft; worker/product integration remains open.
const std = @import("std");
const photon = @import("photon_native.zig");
const orientation = @import("photon_orientation.zig");
const exif = @import("photon_exif.zig");
pub const Options = struct {
    max_width: f64 = 2000,
    max_height: f64 = 2000,
    max_bytes: f64 = 4.5 * 1024 * 1024,
    jpeg_quality: f64 = 80,
    exif_orientation: ?u8 = null,
};
pub const Result = struct {
    data: []u8,
    mime_type: []u8,
    original_width: f64,
    original_height: f64,
    width: f64,
    height: f64,
    was_resized: bool,
    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
        gpa.free(self.mime_type);
        self.* = undefined;
    }
};
fn toUint32(value: f64) u32 {
    if (!std.math.isFinite(value) or value == 0) return 0;
    const reduced = @mod(@trunc(value), 4294967296.0);
    return @intFromFloat(reduced);
}
fn encode(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, original: photon.Dimensions, width: f64, height: f64, resized: bool) !Result {
    const data = try gpa.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    errdefer gpa.free(data);
    _ = std.base64.standard.Encoder.encode(data, bytes);
    return .{ .data = data, .mime_type = try gpa.dupe(u8, mime), .original_width = @floatFromInt(original.width), .original_height = @floatFromInt(original.height), .width = width, .height = height, .was_resized = resized };
}
pub fn resize(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, options: Options) !?Result {
    return attempt(gpa, bytes, mime, options) catch |cause| switch (cause) {
        error.ImageCodecFailure, error.InvalidImageInput, error.InvalidImageDimensions => null,
        else => return cause,
    };
}
fn attempt(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, options: Options) !?Result {
    var original = try photon.transform(gpa, .{ .encoded = bytes }, .{ .format = .rgba });
    defer original.deinit(gpa);
    try orientation.apply(gpa, &original, options.exif_orientation orelse exif.read(bytes));
    const ow: f64 = @floatFromInt(original.dimensions.width);
    const oh: f64 = @floatFromInt(original.dimensions.height);
    if (ow <= options.max_width and oh <= options.max_height and @as(f64, @floatFromInt(std.base64.standard.Encoder.calcSize(bytes.len))) < options.max_bytes) {
        return try encode(gpa, bytes, if (mime.len == 0) "image/png" else mime, original.dimensions, ow, oh, false);
    }
    var width = ow;
    var height = oh;
    if (width > options.max_width) {
        height = @floor(height * options.max_width / width + 0.5);
        width = options.max_width;
    }
    if (height > options.max_height) {
        width = @floor(width * options.max_height / height + 0.5);
        height = options.max_height;
    }
    var qualities: [5]f64 = undefined;
    var quality_count: usize = 0;
    for ([_]f64{ options.jpeg_quality, 85, 70, 55, 40 }) |quality| {
        var duplicate = false;
        for (qualities[0..quality_count]) |previous| if (previous == quality) {
            duplicate = true;
        };
        if (!duplicate) {
            qualities[quality_count] = quality;
            quality_count += 1;
        }
    }
    while (true) {
        var scaled = try photon.transform(gpa, .{ .rgba = .{ .bytes = original.bytes, .dimensions = original.dimensions } }, .{ .format = .rgba, .resize = .{ .width = toUint32(width), .height = toUint32(height) } });
        defer scaled.deinit(gpa);
        var candidates: [6]photon.Image = undefined;
        var count: usize = 0;
        defer for (candidates[0..count]) |*candidate| candidate.deinit(gpa);
        const input: photon.Input = .{ .rgba = .{ .bytes = scaled.bytes, .dimensions = scaled.dimensions } };
        candidates[count] = try photon.transform(gpa, input, .{ .format = .png });
        count += 1;
        for (qualities[0..quality_count]) |quality| {
            candidates[count] = try photon.transform(gpa, input, .{ .format = .jpeg, .quality = toUint32(quality) });
            count += 1;
        }
        // Upstream builds every encoding first, then selects the first fitting
        // candidate. Do not skip later failures merely because PNG would fit.
        for (candidates[0..count], 0..) |candidate, index| {
            if (@as(f64, @floatFromInt(std.base64.standard.Encoder.calcSize(candidate.bytes.len))) < options.max_bytes) {
                return try encode(gpa, candidate.bytes, if (index == 0) "image/png" else "image/jpeg", original.dimensions, width, height, true);
            }
        }
        if (width == 1 and height == 1) break;
        const next_width = if (width == 1) 1 else @max(1, @floor(width * 0.75));
        const next_height = if (height == 1) 1 else @max(1, @floor(height * 0.75));
        if (next_width == width and next_height == height) break;
        width = next_width;
        height = next_height;
    }
    return null;
}
