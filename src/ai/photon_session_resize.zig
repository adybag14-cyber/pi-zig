//! Persistent Photon strategy. Public worker/options binding remains separate.
const std = @import("std");
const p = @import("photon_session.zig");
const c = p.operations;
const orientation = @import("photon_session_orientation.zig");
const exif = @import("photon_exif.zig");
pub const Options = struct { max_width: f64 = 2000, max_height: f64 = 2000, max_bytes: f64 = 4.5 * 1024 * 1024, jpeg_quality: f64 = 80, exif_orientation: ?u8 = null };
pub const Image = struct {
    data: []u8,
    mime_type: []u8,
    original_width: f64,
    original_height: f64,
    width: f64,
    height: f64,
    was_resized: bool,
    pub fn deinit(self: *Image, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.free(self.mime_type);
    }
};
pub const Outcome = union(enum) { image: Image, none, failure: p.Failure };
const Context = struct {
    session: *p.Session,
    original: ?u32 = null,
    scaled: ?u32 = null,
    fn call(self: *Context, op: p.Operation, handle: u32, input: ?[]const u8, w: u32, h: u32, quality: u32) !p.Reply {
        return self.session.checked(self.session.call(op, handle, input, w, h, quality));
    }
};
fn uint32(value: f64) u32 {
    if (!std.math.isFinite(value) or value == 0) return 0;
    return @intFromFloat(@mod(@trunc(value), 4294967296.0));
}
fn encode(allocator: std.mem.Allocator, bytes: []const u8, mime: []const u8, dimensions: p.Reply, width: f64, height: f64, resized: bool) !Image {
    const data = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    errdefer allocator.free(data);
    _ = std.base64.standard.Encoder.encode(data, bytes);
    return .{ .data = data, .mime_type = try allocator.dupe(u8, mime), .original_width = @floatFromInt(dimensions.width), .original_height = @floatFromInt(dimensions.height), .width = width, .height = height, .was_resized = resized };
}
fn freeOutcome(allocator: std.mem.Allocator, outcome: *Outcome) void {
    switch (outcome.*) {
        .image => |*image| image.deinit(allocator),
        .failure => |*failure| failure.deinit(allocator),
        .none => {},
    }
}
pub fn resize(allocator: std.mem.Allocator, bytes: []const u8, mime: []const u8, options: Options) !Outcome {
    const session = p.Session.init(allocator) catch |err| return if (err == error.OutOfMemory) err else .none;
    defer session.deinit();
    var ctx: Context = .{ .session = session };
    var body_error: ?anyerror = null;
    var result = attempt(&ctx, bytes, mime, options) catch |err| blk: {
        body_error = err;
        break :blk Outcome.none;
    };
    // The inner finally runs before the catch; outer image.free runs after it.
    // Preserve real Rust cleanup exceptions even when resize itself was caught.
    // A failed inner tryEncodings finally is caught by the outer catch.
    if (ctx.scaled) |image| {
        const cleanup = session.invoke(c.PI_SESSION_FREE, image, null, 0, 0, 0) catch |err| {
            freeOutcome(allocator, &result);
            return err;
        };
        switch (cleanup) {
            .value => |reply| session.freeReply(reply),
            .failure => |failure| {
                var owned = failure;
                owned.deinit(allocator);
            },
        }
    }
    for ([_]?u32{ctx.original}) |handle| if (handle) |image| {
        const cleanup = session.invoke(c.PI_SESSION_FREE, image, null, 0, 0, 0) catch |err| {
            freeOutcome(allocator, &result);
            return err;
        };
        switch (cleanup) {
            .value => |reply| session.freeReply(reply),
            .failure => |failure| {
                freeOutcome(allocator, &result);
                result = .{ .failure = failure };
                body_error = null;
            },
        }
    };
    if (body_error) |cause| if (cause == error.OutOfMemory) {
        freeOutcome(allocator, &result);
        return error.OutOfMemory;
    };
    return result;
}
fn attempt(ctx: *Context, bytes: []const u8, mime: []const u8, options: Options) !Outcome {
    const allocator = ctx.session.gpa;
    const raw = try ctx.call(c.PI_SESSION_DECODE, 0, bytes, 0, 0, 0);
    // applyExifOrientation can throw before Source assigns its outer image.
    const chosen = try orientation.apply(ctx.session, raw.image, options.exif_orientation orelse exif.read(bytes));
    ctx.original = chosen;
    if (chosen != raw.image) _ = try ctx.call(c.PI_SESSION_FREE, raw.image, null, 0, 0, 0);
    const dimensions = try ctx.call(c.PI_SESSION_PIXELS, chosen, null, 0, 0, 0);
    defer ctx.session.freeReply(dimensions);
    const ow: f64 = @floatFromInt(dimensions.width);
    const oh: f64 = @floatFromInt(dimensions.height);
    if (ow <= options.max_width and oh <= options.max_height and @as(f64, @floatFromInt(std.base64.standard.Encoder.calcSize(bytes.len))) < options.max_bytes)
        return .{ .image = try encode(allocator, bytes, if (mime.len == 0) "image/png" else mime, dimensions, ow, oh, false) };
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
        for (qualities[0..quality_count]) |previous| if (previous == quality or (std.math.isNan(previous) and std.math.isNan(quality))) {
            duplicate = true;
        };
        if (!duplicate) {
            qualities[quality_count] = quality;
            quality_count += 1;
        }
    }
    while (true) {
        const scaled = try ctx.call(c.PI_SESSION_RESIZE, chosen, null, uint32(width), uint32(height), 0);
        ctx.scaled = scaled.image;
        var candidates: [6]p.Reply = undefined;
        var count: usize = 0;
        defer for (candidates[0..count]) |candidate| ctx.session.freeReply(candidate);
        candidates[count] = try ctx.call(c.PI_SESSION_PNG, scaled.image, null, 0, 0, 0);
        count += 1;
        for (qualities[0..quality_count]) |quality| {
            candidates[count] = try ctx.call(c.PI_SESSION_JPEG, scaled.image, null, 0, 0, uint32(quality));
            count += 1;
        }
        var selected: ?Image = null;
        for (candidates[0..count], 0..) |candidate, index| {
            if (@as(f64, @floatFromInt(std.base64.standard.Encoder.calcSize(candidate.length))) < options.max_bytes) {
                selected = try encode(allocator, candidate.bytes[0..candidate.length], if (index == 0) "image/png" else "image/jpeg", dimensions, width, height, true);
                break;
            }
        }
        errdefer if (selected) |*image| image.deinit(allocator);
        ctx.scaled = null;
        _ = try ctx.call(c.PI_SESSION_FREE, scaled.image, null, 0, 0, 0);
        if (selected) |image| return .{ .image = image };
        if (width == 1 and height == 1) break;
        const next_width = if (width == 1) 1 else @max(1, @floor(width * 0.75));
        const next_height = if (height == 1) 1 else @max(1, @floor(height * 0.75));
        if (next_width == width and next_height == height) break;
        width = next_width;
        height = next_height;
    }
    return .none;
}
