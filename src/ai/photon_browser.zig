//! External native codec draft. No interpreter or JS host is involved.
const std = @import("std");
const c = @cImport({
    @cInclude("photon_browser_native.h");
});
pub const Dimensions = struct { width: u32, height: u32 };
pub const Format = enum(c_uint) { rgba = 0, png = 1, jpeg = 2 };
pub const Input = union(enum) { encoded: []const u8, rgba: struct { bytes: []const u8, dimensions: Dimensions } };
pub const Options = struct {
    resize: ?Dimensions = null,
    format: Format = .png,
    quality: u32 = 80,
    memory_limit: usize = 0,
    output_limit: usize = std.math.maxInt(u32),
};
pub const Image = struct {
    bytes: []u8,
    dimensions: Dimensions,
    pub fn deinit(self: *Image, gpa: std.mem.Allocator) void {
        gpa.free(self.bytes);
        self.* = undefined;
    }
};
fn allocate(raw: ?*anyopaque, size: usize, alignment: usize) callconv(.c) ?*anyopaque {
    const gpa: *std.mem.Allocator = @ptrCast(@alignCast(raw.?));
    return gpa.rawAlloc(size, .fromByteUnits(alignment), @returnAddress());
}
fn release(raw: ?*anyopaque, pointer: ?*anyopaque, size: usize, alignment: usize) callconv(.c) void {
    const gpa: *std.mem.Allocator = @ptrCast(@alignCast(raw.?));
    const bytes: [*]u8 = @ptrCast(pointer.?);
    gpa.rawFree(bytes[0..size], .fromByteUnits(alignment), @returnAddress());
}
pub fn transform(gpa: std.mem.Allocator, input: Input, options: Options) !Image {
    var allocator = gpa;
    const bytes = switch (input) {
        .encoded => |encoded| encoded,
        .rgba => |rgba| rgba.bytes,
    };
    const original: Dimensions = switch (input) {
        .encoded => .{ .width = 0, .height = 0 },
        .rgba => |rgba| rgba.dimensions,
    };
    const resized = options.resize orelse Dimensions{ .width = 0, .height = 0 };
    if (options.resize != null and (resized.width == 0 or resized.height == 0)) return error.InvalidImageDimensions;
    const result = c.pi_photon_browser_transform(.{ .context = &allocator, .allocate = allocate, .release = release }, bytes.ptr, bytes.len, @intFromBool(input == .rgba), original.width, original.height, resized.width, resized.height, @intFromEnum(options.format), options.quality, options.memory_limit, options.output_limit);
    switch (result.status) {
        0 => {},
        1 => return error.OutOfMemory,
        2 => return error.ImageCodecFailure,
        3 => return error.InvalidImageInput,
        4 => return error.ReentrantImageCodec,
        else => return error.InvalidImageCodecResult,
    }
    if (result.data == null or result.length == 0) return error.InvalidImageCodecResult;
    return .{ .bytes = result.data[0..result.length], .dimensions = .{ .width = result.width, .height = result.height } };
}
