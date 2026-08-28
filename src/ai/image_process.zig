//! Bounded inline-image normalization for CLI attachments and tool results.
//!
//! The native path keeps already-safe PNG/JPEG/GIF/WebP payloads byte-for-byte.
//! BMP and images that exceed provider dimensions/base64 limits are converted
//! through an optional process-isolated ImageMagick backend. The executable is
//! discovered explicitly (`PI_IMAGE_CONVERTER`) or from PATH; Pi itself keeps no
//! hard image-library dependency and never passes untrusted input through a
//! shell. Temporary files are private, bounded, and removed after each request.
const std = @import("std");
const builtin = @import("builtin");
const image_magic = @import("images.zig");
const Io = std.Io;

pub const default_max_width: u32 = 2000;
pub const default_max_height: u32 = 2000;
/// 4.5 MiB of base64 text, preserving headroom below Anthropic's 5 MiB limit.
pub const default_max_base64_bytes: usize = 4_718_592;
pub const default_jpeg_quality: u8 = 80;
pub const default_max_input_dimension: u32 = 100_000;
pub const default_max_input_pixels: u64 = 400_000_000;

pub const Dimensions = struct {
    width: u32,
    height: u32,
};

pub const Inspection = struct {
    mime_type: []const u8,
    dimensions: Dimensions,
    /// EXIF orientation for JPEG/WebP. Other formats use 1.
    orientation: u8 = 1,

    pub fn orientedDimensions(self: Inspection) Dimensions {
        return if (self.orientation >= 5 and self.orientation <= 8)
            .{ .width = self.dimensions.height, .height = self.dimensions.width }
        else
            self.dimensions;
    }
};

pub const Options = struct {
    auto_resize: bool = true,
    max_width: u32 = default_max_width,
    max_height: u32 = default_max_height,
    max_base64_bytes: usize = default_max_base64_bytes,
    jpeg_quality: u8 = default_jpeg_quality,
    /// Explicit ImageMagick executable used by deterministic tests/private installs.
    converter_path: ?[]const u8 = null,
    environ: ?*const std.process.Environ.Map = null,
    temp_dir: ?[]const u8 = null,
    timeout_seconds: u32 = 60,
    max_input_dimension: u32 = default_max_input_dimension,
    max_input_pixels: u64 = default_max_input_pixels,
};

pub const ProcessedImage = struct {
    data_b64: []u8,
    mime_type: []u8,
    original_width: u32,
    original_height: u32,
    width: u32,
    height: u32,
    was_resized: bool,
    was_converted: bool,
    orientation_normalized: bool,
    converted_from: ?[]u8 = null,

    pub fn deinit(self: *ProcessedImage, gpa: std.mem.Allocator) void {
        gpa.free(self.data_b64);
        gpa.free(self.mime_type);
        if (self.converted_from) |value| gpa.free(value);
        self.* = undefined;
    }

    /// Original-compatible text notes appended beside normalized attachments.
    pub fn formatHints(self: ProcessedImage, gpa: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        if (self.converted_from) |from| {
            try out.writer.print("[Image converted from {s} to {s}.]", .{ from, self.mime_type });
        }
        if (self.was_resized) {
            if (out.written().len > 0) try out.writer.writeByte('\n');
            const scale = @as(f64, @floatFromInt(self.original_width)) / @as(f64, @floatFromInt(@max(self.width, 1)));
            try out.writer.print(
                "[Image: original {d}x{d}, displayed at {d}x{d}. Multiply coordinates by {d:.2} to map to original image.]",
                .{ self.original_width, self.original_height, self.width, self.height, scale },
            );
        }
        return out.toOwnedSlice();
    }
};

pub fn inspect(bytes: []const u8) ?Inspection {
    const sniff_len = @min(bytes.len, image_magic.sniff_bytes);
    const mime = image_magic.detectSupportedMime(bytes[0..sniff_len]) orelse return null;
    const dims = dimensionsFor(bytes, mime) orelse return null;
    return .{
        .mime_type = mime,
        .dimensions = dims,
        .orientation = if (std.mem.eql(u8, mime, "image/jpeg") or std.mem.eql(u8, mime, "image/webp")) exifOrientation(bytes, mime) else 1,
    };
}

/// Normalize an image for inline provider delivery.
///
/// Returns null when bytes are not a supported image or a required conversion
/// cannot be completed. Callers intentionally differ: read/@file omit unsafe
/// images, whereas arbitrary tool-result normalization retains the original.
pub fn processBytes(
    gpa: std.mem.Allocator,
    io: Io,
    bytes: []const u8,
    options: Options,
) !?ProcessedImage {
    const info = inspect(bytes) orelse return null;
    const oriented = info.orientedDimensions();
    if (oriented.width == 0 or oriented.height == 0) return null;
    if (oriented.width > options.max_input_dimension or oriented.height > options.max_input_dimension) return null;
    if (@as(u64, oriented.width) * @as(u64, oriented.height) > options.max_input_pixels) return null;
    if (options.max_width == 0 or options.max_height == 0 or options.max_base64_bytes == 0) return null;

    const provider_supported = !std.mem.eql(u8, info.mime_type, "image/bmp");
    const encoded_size = std.base64.standard.Encoder.calcSize(bytes.len);
    const within_dimensions = oriented.width <= options.max_width and oriented.height <= options.max_height;
    const within_bytes = encoded_size < options.max_base64_bytes;

    // With resizing disabled, upstream still converts unsupported inline BMP,
    // but preserves supported provider formats regardless of dimensions.
    if (!options.auto_resize and provider_supported) {
        return try originalResult(gpa, bytes, info.mime_type, oriented);
    }

    // Match upstream: provider-native images already within byte/dimension
    // limits remain byte-for-byte, including EXIF orientation metadata. The
    // orientation-adjusted dimensions are still used for limit checks. Pixel
    // orientation is normalized only when a resize/re-encode is required.
    if (provider_supported and within_dimensions and within_bytes) {
        return try originalResult(gpa, bytes, info.mime_type, oriented);
    }

    const converter = (try resolveConverter(gpa, io, options)) orelse return null;
    defer gpa.free(converter);
    return try convertWithImageMagick(gpa, io, converter, bytes, info, options);
}

fn originalResult(gpa: std.mem.Allocator, bytes: []const u8, mime: []const u8, dims: Dimensions) !ProcessedImage {
    return .{
        .data_b64 = try image_magic.encodeBase64(gpa, bytes),
        .mime_type = try gpa.dupe(u8, canonicalMime(mime)),
        .original_width = dims.width,
        .original_height = dims.height,
        .width = dims.width,
        .height = dims.height,
        .was_resized = false,
        .was_converted = false,
        .orientation_normalized = false,
    };
}

fn canonicalMime(mime: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(mime, "image/jpg")) return "image/jpeg";
    return mime;
}

fn fitDimensions(original: Dimensions, max_width: u32, max_height: u32) Dimensions {
    var width: u64 = original.width;
    var height: u64 = original.height;
    if (width > max_width) {
        height = @max(@as(u64, 1), (height * max_width + width / 2) / width);
        width = max_width;
    }
    if (height > max_height) {
        width = @max(@as(u64, 1), (width * max_height + height / 2) / height);
        height = max_height;
    }
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

fn nextDimensions(current: Dimensions) Dimensions {
    return .{
        .width = if (current.width <= 1) 1 else @max(@as(u32, 1), @as(u32, @intCast((@as(u64, current.width) * 3) / 4))),
        .height = if (current.height <= 1) 1 else @max(@as(u32, 1), @as(u32, @intCast((@as(u64, current.height) * 3) / 4))),
    };
}

var temp_counter: std.atomic.Value(u64) = .init(1);

fn convertWithImageMagick(
    gpa: std.mem.Allocator,
    io: Io,
    converter: []const u8,
    bytes: []const u8,
    info: Inspection,
    options: Options,
) !?ProcessedImage {
    const temp_root = try tempRoot(gpa, options);
    defer gpa.free(temp_root);
    const stamp = std.Io.Clock.real.now(io).toMilliseconds();
    const counter = temp_counter.fetchAdd(1, .monotonic);
    const thread_id = std.Thread.getCurrentId();
    const dir_name = try std.fmt.allocPrint(gpa, ".pi-image-{d}-{x}-{x}", .{ stamp, thread_id, counter });
    defer gpa.free(dir_name);
    const work_dir = try std.fs.path.join(gpa, &.{ temp_root, dir_name });
    defer gpa.free(work_dir);
    std.Io.Dir.cwd().createDirPath(io, work_dir) catch return null;
    defer std.Io.Dir.cwd().deleteTree(io, work_dir) catch {};

    const input_path = try std.fs.path.join(gpa, &.{ work_dir, "input.img" });
    defer gpa.free(input_path);
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = input_path, .data = bytes }) catch return null;

    const original = info.orientedDimensions();
    const provider_supported = !std.mem.eql(u8, info.mime_type, "image/bmp");
    var current = if (options.auto_resize) fitDimensions(original, options.max_width, options.max_height) else original;
    const quality_candidates = [_]u8{ options.jpeg_quality, 85, 70, 55, 40 };

    while (true) {
        if (try renderCandidate(gpa, io, converter, input_path, work_dir, current, .png, options, 0)) |candidate| {
            // A provider-native input reaches the backend only because resize
            // policy was triggered. A BMP PNG candidate at unchanged dimensions
            // is merely the mandatory compatibility conversion.
            const resized = provider_supported or current.width != original.width or current.height != original.height;
            return @as(?ProcessedImage, try finishCandidate(gpa, candidate, info, original, current, resized));
        }
        var seen: [101]bool = [_]bool{false} ** 101;
        for (quality_candidates) |quality_raw| {
            const quality: u8 = @min(quality_raw, 100);
            if (seen[quality]) continue;
            seen[quality] = true;
            if (try renderCandidate(gpa, io, converter, input_path, work_dir, current, .jpeg, options, quality)) |candidate| {
                // JPEG is attempted only after the same-size PNG exceeded the
                // payload ceiling, so this is a resize-policy result even when
                // the dimensions themselves did not need reduction.
                return @as(?ProcessedImage, try finishCandidate(gpa, candidate, info, original, current, true));
            }
        }

        if (!options.auto_resize or (current.width == 1 and current.height == 1)) break;
        const next = nextDimensions(current);
        if (next.width == current.width and next.height == current.height) break;
        current = next;
    }
    return null;
}

const CandidateFormat = enum { png, jpeg };
const Candidate = struct {
    bytes: []u8,
    mime_type: []const u8,
};

fn finishCandidate(
    gpa: std.mem.Allocator,
    candidate: Candidate,
    info: Inspection,
    original: Dimensions,
    current: Dimensions,
    was_resized: bool,
) !ProcessedImage {
    defer gpa.free(candidate.bytes);
    const output_mime = candidate.mime_type;
    const converted = !std.mem.eql(u8, canonicalMime(info.mime_type), output_mime);
    return .{
        .data_b64 = try image_magic.encodeBase64(gpa, candidate.bytes),
        .mime_type = try gpa.dupe(u8, output_mime),
        .original_width = original.width,
        .original_height = original.height,
        .width = current.width,
        .height = current.height,
        .was_resized = was_resized,
        .was_converted = converted,
        .orientation_normalized = info.orientation != 1,
        .converted_from = if (converted) try gpa.dupe(u8, info.mime_type) else null,
    };
}

fn renderCandidate(
    gpa: std.mem.Allocator,
    io: Io,
    converter: []const u8,
    input_path: []const u8,
    work_dir: []const u8,
    dims: Dimensions,
    format: CandidateFormat,
    options: Options,
    quality: u8,
) !?Candidate {
    const extension = if (format == .png) "png" else "jpg";
    const output_name = try std.fmt.allocPrint(gpa, "candidate-{d}x{d}-{d}.{s}", .{ dims.width, dims.height, quality, extension });
    defer gpa.free(output_name);
    const output_path = try std.fs.path.join(gpa, &.{ work_dir, output_name });
    defer {
        std.Io.Dir.cwd().deleteFile(io, output_path) catch {};
        gpa.free(output_path);
    }
    const output_spec = try std.fmt.allocPrint(gpa, "{s}:{s}", .{ if (format == .png) "png" else "jpeg", output_path });
    defer gpa.free(output_spec);
    // Photon decodes one image. Match that behavior for animated GIF/WebP and
    // multi-page formats instead of letting ImageMagick emit numbered files.
    const input_spec = try std.fmt.allocPrint(gpa, "{s}[0]", .{input_path});
    defer gpa.free(input_spec);
    const resize_arg = try std.fmt.allocPrint(gpa, "{d}x{d}!", .{ dims.width, dims.height });
    defer gpa.free(resize_arg);
    const quality_arg = try std.fmt.allocPrint(gpa, "{d}", .{quality});
    defer gpa.free(quality_arg);
    const timeout_arg = try std.fmt.allocPrint(gpa, "{d}", .{@max(options.timeout_seconds, 1)});
    defer gpa.free(timeout_arg);
    const temp_define = try std.fmt.allocPrint(gpa, "registry:temporary-path={s}", .{work_dir});
    defer gpa.free(temp_define);

    const png_argv = [_][]const u8{
        converter,
        "-limit",
        "memory",
        "256MiB",
        "-limit",
        "map",
        "512MiB",
        "-limit",
        "disk",
        "1GiB",
        "-limit",
        "area",
        "400MP",
        "-limit",
        "time",
        timeout_arg,
        "-define",
        temp_define,
        input_spec,
        "-auto-orient",
        "-resize",
        resize_arg,
        "-strip",
        "-depth",
        "8",
        "-define",
        "png:compression-level=9",
        output_spec,
    };
    const jpeg_argv = [_][]const u8{
        converter,
        "-limit",
        "memory",
        "256MiB",
        "-limit",
        "map",
        "512MiB",
        "-limit",
        "disk",
        "1GiB",
        "-limit",
        "area",
        "400MP",
        "-limit",
        "time",
        timeout_arg,
        "-define",
        temp_define,
        input_spec,
        "-auto-orient",
        "-resize",
        resize_arg,
        "-strip",
        "-depth",
        "8",
        "-background",
        "white",
        "-alpha",
        "remove",
        "-alpha",
        "off",
        "-quality",
        quality_arg,
        output_spec,
    };
    const argv: []const []const u8 = if (format == .png) &png_argv else &jpeg_argv;
    const run = std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 * 1024),
        .stderr_limit = .limited(256 * 1024),
        .timeout = .{ .duration = .{ .raw = .fromSeconds(options.timeout_seconds), .clock = .real } },
    }) catch return null;
    defer gpa.free(run.stdout);
    defer gpa.free(run.stderr);
    const succeeded = switch (run.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!succeeded) return null;

    // A raw candidate cannot be larger than the base64 ceiling and still pass.
    const candidate = std.Io.Dir.cwd().readFileAlloc(io, output_path, gpa, .limited(options.max_base64_bytes)) catch return null;
    errdefer gpa.free(candidate);
    if (candidate.len == 0 or std.base64.standard.Encoder.calcSize(candidate.len) >= options.max_base64_bytes) {
        gpa.free(candidate);
        return null;
    }
    const sniff = image_magic.detectSupportedMime(candidate[0..@min(candidate.len, image_magic.sniff_bytes)]) orelse {
        gpa.free(candidate);
        return null;
    };
    const expected = if (format == .png) "image/png" else "image/jpeg";
    if (!std.mem.eql(u8, sniff, expected)) {
        gpa.free(candidate);
        return null;
    }
    return .{ .bytes = candidate, .mime_type = expected };
}

fn tempRoot(gpa: std.mem.Allocator, options: Options) ![]u8 {
    if (options.temp_dir) |value| return gpa.dupe(u8, value);
    if (options.environ) |env| {
        if (env.get("TMPDIR") orelse env.get("TEMP") orelse env.get("TMP")) |value| {
            if (value.len > 0) return gpa.dupe(u8, value);
        }
    }
    return gpa.dupe(u8, if (builtin.os.tag == .windows) "." else "/tmp");
}

fn resolveConverter(gpa: std.mem.Allocator, io: Io, options: Options) !?[]u8 {
    if (options.converter_path) |path| {
        if (path.len == 0 or std.ascii.eqlIgnoreCase(path, "none")) return null;
        return if (isRegularFile(io, path)) try gpa.dupe(u8, path) else null;
    }
    if (options.environ) |env| if (env.get("PI_IMAGE_CONVERTER")) |path| {
        if (path.len == 0 or std.ascii.eqlIgnoreCase(path, "none")) return null;
        return if (isRegularFile(io, path)) try gpa.dupe(u8, path) else null;
    };

    const names = if (builtin.os.tag == .windows)
        &[_][]const u8{"magick.exe"}
    else
        &[_][]const u8{ "magick", "convert" };
    if (options.environ) |env| if (env.get("PATH")) |path_value| {
        var dirs = std.mem.splitScalar(u8, path_value, if (builtin.os.tag == .windows) ';' else ':');
        while (dirs.next()) |dir| {
            for (names) |name| {
                const candidate = if (dir.len == 0) try gpa.dupe(u8, name) else try std.fs.path.join(gpa, &.{ dir, name });
                if (isRegularFile(io, candidate)) return candidate;
                gpa.free(candidate);
            }
        }
    };

    // Common self-contained ImageMagick location used by minimal Linux images.
    if (builtin.os.tag != .windows) {
        for (&[_][]const u8{ "/opt/imagemagick/bin/magick", "/usr/local/bin/magick", "/usr/bin/magick" }) |candidate| {
            if (isRegularFile(io, candidate)) return try gpa.dupe(u8, candidate);
        }
    }
    return null;
}

fn isRegularFile(io: Io, path: []const u8) bool {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return stat.kind == .file;
}

fn dimensionsFor(bytes: []const u8, mime: []const u8) ?Dimensions {
    if (std.mem.eql(u8, mime, "image/png")) return pngDimensions(bytes);
    if (std.mem.eql(u8, mime, "image/jpeg")) return jpegDimensions(bytes);
    if (std.mem.eql(u8, mime, "image/gif")) return gifDimensions(bytes);
    if (std.mem.eql(u8, mime, "image/webp")) return webpDimensions(bytes);
    if (std.mem.eql(u8, mime, "image/bmp")) return bmpDimensions(bytes);
    return null;
}

fn pngDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 24) return null;
    const width = readU32Be(bytes, 16);
    const height = readU32Be(bytes, 20);
    return validDimensions(width, height);
}

fn gifDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 10) return null;
    return validDimensions(readU16Le(bytes, 6), readU16Le(bytes, 8));
}

fn bmpDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 26) return null;
    const dib = readU32Le(bytes, 14);
    if (dib == 12) return validDimensions(readU16Le(bytes, 18), readU16Le(bytes, 20));
    if (dib < 40 or bytes.len < 26) return null;
    const width_signed: i32 = @bitCast(readU32Le(bytes, 18));
    const height_signed: i32 = @bitCast(readU32Le(bytes, 22));
    if (width_signed == 0 or height_signed == 0 or width_signed == std.math.minInt(i32) or height_signed == std.math.minInt(i32)) return null;
    const width: u32 = @intCast(if (width_signed < 0) -width_signed else width_signed);
    const height: u32 = @intCast(if (height_signed < 0) -height_signed else height_signed);
    return validDimensions(width, height);
}

fn jpegDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 4 or bytes[0] != 0xff or bytes[1] != 0xd8) return null;
    var offset: usize = 2;
    while (offset + 1 < bytes.len) {
        while (offset < bytes.len and bytes[offset] != 0xff) : (offset += 1) {}
        if (offset + 1 >= bytes.len) break;
        while (offset + 1 < bytes.len and bytes[offset + 1] == 0xff) : (offset += 1) {}
        if (offset + 1 >= bytes.len) break;
        const marker = bytes[offset + 1];
        offset += 2;
        if (marker == 0xd8 or marker == 0xd9 or marker == 0x01 or (marker >= 0xd0 and marker <= 0xd7)) continue;
        if (offset + 2 > bytes.len) return null;
        const segment_len = readU16Be(bytes, offset);
        if (segment_len < 2 or offset + segment_len > bytes.len) return null;
        if (isSofMarker(marker)) {
            if (segment_len < 7) return null;
            return validDimensions(readU16Be(bytes, offset + 5), readU16Be(bytes, offset + 3));
        }
        offset += segment_len;
    }
    return null;
}

fn isSofMarker(marker: u8) bool {
    return switch (marker) {
        0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf => true,
        else => false,
    };
}

fn webpDimensions(bytes: []const u8) ?Dimensions {
    if (bytes.len < 20 or !std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WEBP")) return null;
    var offset: usize = 12;
    while (offset + 8 <= bytes.len) {
        const size = readU32Le(bytes, offset + 4);
        const data_start = offset + 8;
        const data_end_u64 = @as(u64, data_start) + size;
        if (data_end_u64 > bytes.len) return null;
        const data_end: usize = @intCast(data_end_u64);
        if (std.mem.eql(u8, bytes[offset .. offset + 4], "VP8X") and data_end - data_start >= 10) {
            const width = 1 + readU24Le(bytes, data_start + 4);
            const height = 1 + readU24Le(bytes, data_start + 7);
            return validDimensions(width, height);
        }
        if (std.mem.eql(u8, bytes[offset .. offset + 4], "VP8L") and data_end - data_start >= 5 and bytes[data_start] == 0x2f) {
            const b1 = bytes[data_start + 1];
            const b2 = bytes[data_start + 2];
            const b3 = bytes[data_start + 3];
            const b4 = bytes[data_start + 4];
            const width: u32 = 1 + @as(u32, b1) + ((@as(u32, b2) & 0x3f) << 8);
            const height: u32 = 1 + (@as(u32, b2) >> 6) + (@as(u32, b3) << 2) + ((@as(u32, b4) & 0x0f) << 10);
            return validDimensions(width, height);
        }
        if (std.mem.eql(u8, bytes[offset .. offset + 4], "VP8 ") and data_end - data_start >= 10 and
            bytes[data_start + 3] == 0x9d and bytes[data_start + 4] == 0x01 and bytes[data_start + 5] == 0x2a)
        {
            const width = readU16Le(bytes, data_start + 6) & 0x3fff;
            const height = readU16Le(bytes, data_start + 8) & 0x3fff;
            return validDimensions(width, height);
        }
        offset = data_end + (size & 1);
    }
    return null;
}

fn validDimensions(width_any: anytype, height_any: anytype) ?Dimensions {
    const width: u32 = @intCast(width_any);
    const height: u32 = @intCast(height_any);
    if (width == 0 or height == 0) return null;
    return .{ .width = width, .height = height };
}

fn exifOrientation(bytes: []const u8, mime: []const u8) u8 {
    const tiff_offset = if (std.mem.eql(u8, mime, "image/jpeg")) findJpegTiffOffset(bytes) else findWebpTiffOffset(bytes);
    if (tiff_offset == null) return 1;
    return readOrientationFromTiff(bytes, tiff_offset.?);
}

fn findJpegTiffOffset(bytes: []const u8) ?usize {
    var offset: usize = 2;
    while (offset + 3 < bytes.len) {
        if (bytes[offset] != 0xff) return null;
        const marker = bytes[offset + 1];
        if (marker == 0xff) {
            offset += 1;
            continue;
        }
        const length = readU16Be(bytes, offset + 2);
        if (length < 2 or offset + 2 + length > bytes.len) return null;
        if (marker == 0xe1) {
            const segment_start = offset + 4;
            if (segment_start + 6 > bytes.len or !hasExifHeader(bytes, segment_start)) return null;
            return segment_start + 6;
        }
        offset += 2 + length;
    }
    return null;
}

fn findWebpTiffOffset(bytes: []const u8) ?usize {
    var offset: usize = 12;
    while (offset + 8 <= bytes.len) {
        const size = readU32Le(bytes, offset + 4);
        const data_start = offset + 8;
        const data_end_u64 = @as(u64, data_start) + size;
        if (data_end_u64 > bytes.len) return null;
        if (std.mem.eql(u8, bytes[offset .. offset + 4], "EXIF")) {
            if (size >= 6 and hasExifHeader(bytes, data_start)) return data_start + 6;
            return data_start;
        }
        offset = @intCast(data_end_u64 + (size & 1));
    }
    return null;
}

fn hasExifHeader(bytes: []const u8, offset: usize) bool {
    return offset + 6 <= bytes.len and std.mem.eql(u8, bytes[offset .. offset + 6], "Exif\x00\x00");
}

fn readOrientationFromTiff(bytes: []const u8, start: usize) u8 {
    if (start + 8 > bytes.len) return 1;
    const little = bytes[start] == 'I' and bytes[start + 1] == 'I';
    const big = bytes[start] == 'M' and bytes[start + 1] == 'M';
    if (!little and !big) return 1;
    const ifd_offset = readU32Endian(bytes, start + 4, little);
    const ifd_start_u64 = @as(u64, start) + ifd_offset;
    if (ifd_start_u64 + 2 > bytes.len) return 1;
    const ifd_start: usize = @intCast(ifd_start_u64);
    const count = readU16Endian(bytes, ifd_start, little);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        const pos_u64 = @as(u64, ifd_start) + 2 + @as(u64, index) * 12;
        if (pos_u64 + 12 > bytes.len) return 1;
        const pos: usize = @intCast(pos_u64);
        if (readU16Endian(bytes, pos, little) != 0x0112) continue;
        const value = readU16Endian(bytes, pos + 8, little);
        return if (value >= 1 and value <= 8) @intCast(value) else 1;
    }
    return 1;
}

fn readU16Endian(bytes: []const u8, offset: usize, little: bool) u16 {
    return if (little) readU16Le(bytes, offset) else readU16Be(bytes, offset);
}

fn readU32Endian(bytes: []const u8, offset: usize, little: bool) u32 {
    return if (little) readU32Le(bytes, offset) else readU32Be(bytes, offset);
}

fn readU16Le(bytes: []const u8, offset: usize) u16 {
    if (offset + 2 > bytes.len) return 0;
    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}
fn readU16Be(bytes: []const u8, offset: usize) u16 {
    if (offset + 2 > bytes.len) return 0;
    return (@as(u16, bytes[offset]) << 8) | @as(u16, bytes[offset + 1]);
}
fn readU24Le(bytes: []const u8, offset: usize) u32 {
    if (offset + 3 > bytes.len) return 0;
    return @as(u32, bytes[offset]) | (@as(u32, bytes[offset + 1]) << 8) | (@as(u32, bytes[offset + 2]) << 16);
}
fn readU32Le(bytes: []const u8, offset: usize) u32 {
    if (offset + 4 > bytes.len) return 0;
    return @as(u32, bytes[offset]) | (@as(u32, bytes[offset + 1]) << 8) | (@as(u32, bytes[offset + 2]) << 16) | (@as(u32, bytes[offset + 3]) << 24);
}
fn readU32Be(bytes: []const u8, offset: usize) u32 {
    if (offset + 4 > bytes.len) return 0;
    return (@as(u32, bytes[offset]) << 24) | (@as(u32, bytes[offset + 1]) << 16) | (@as(u32, bytes[offset + 2]) << 8) | @as(u32, bytes[offset + 3]);
}

// -------------------------------------------------------------------------
// Tests

fn tinyBmp() [58]u8 {
    var bmp = [_]u8{0} ** 58;
    bmp[0] = 'B';
    bmp[1] = 'M';
    bmp[2] = 58;
    bmp[10] = 54;
    bmp[14] = 40;
    bmp[18] = 1;
    bmp[22] = 1;
    bmp[26] = 1;
    bmp[28] = 24;
    bmp[34] = 4;
    bmp[56] = 0xff;
    return bmp;
}

test "image inspection reads PNG GIF BMP JPEG and WebP dimensions" {
    var png = [_]u8{0} ** 24;
    const signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
    @memcpy(png[0..8], &signature);
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    try std.testing.expectEqual(Dimensions{ .width = 2, .height = 3 }, inspect(&png).?.dimensions);

    var gif = [_]u8{0} ** 10;
    @memcpy(gif[0..6], "GIF89a");
    gif[6] = 4;
    gif[8] = 5;
    try std.testing.expectEqual(Dimensions{ .width = 4, .height = 5 }, inspect(&gif).?.dimensions);

    const bmp = tinyBmp();
    try std.testing.expectEqual(Dimensions{ .width = 1, .height = 1 }, inspect(&bmp).?.dimensions);

    const jpeg = [_]u8{ 0xff, 0xd8, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x07, 0x00, 0x09, 0x01, 0x01, 0x11, 0x00, 0xff, 0xd9 };
    try std.testing.expectEqual(Dimensions{ .width = 9, .height = 7 }, inspect(&jpeg).?.dimensions);

    var webp = [_]u8{0} ** 30;
    @memcpy(webp[0..4], "RIFF");
    @memcpy(webp[8..12], "WEBP");
    @memcpy(webp[12..16], "VP8X");
    webp[16] = 10;
    webp[24] = 10; // width = 11
    webp[27] = 12; // height = 13
    try std.testing.expectEqual(Dimensions{ .width = 11, .height = 13 }, inspect(&webp).?.dimensions);
}

test "JPEG EXIF orientation swaps display dimensions" {
    // APP1 Exif segment with little-endian TIFF orientation=6 followed by SOF0.
    const jpeg = [_]u8{
        0xff, 0xd8,
        0xff, 0xe1,
        0x00, 0x22,
        'E',  'x',
        'i',  'f',
        0,    0,
        'I',  'I',
        0x2a, 0,
        8,    0,
        0,    0,
        1,    0,
        0x12, 0x01,
        3,    0,
        1,    0,
        0,    0,
        6,    0,
        0,    0,
        0,    0,
        0,    0,
        0xff, 0xc0,
        0x00, 0x0b,
        0x08, 0x00,
        0x02, 0x00,
        0x03, 0x01,
        0x01, 0x11,
        0x00, 0xff,
        0xd9,
    };
    const value = inspect(&jpeg).?;
    try std.testing.expectEqual(@as(u8, 6), value.orientation);
    try std.testing.expectEqual(Dimensions{ .width = 3, .height = 2 }, value.dimensions);
    try std.testing.expectEqual(Dimensions{ .width = 2, .height = 3 }, value.orientedDimensions());
}

test "safe EXIF-oriented JPEG remains byte-for-byte like upstream" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const jpeg = [_]u8{
        0xff, 0xd8, 0xff, 0xe1, 0x00, 0x22,
        'E',  'x',  'i',  'f',  0,    0,
        'I',  'I',  0x2a, 0,    8,    0,
        0,    0,    1,    0,    0x12, 0x01,
        3,    0,    1,    0,    0,    0,
        6,    0,    0,    0,    0,    0,
        0,    0,    0xff, 0xc0, 0x00, 0x0b,
        0x08, 0x00, 0x02, 0x00, 0x03, 0x01,
        0x01, 0x11, 0x00, 0xff, 0xd9,
    };
    var result = (try processBytes(gpa, io, &jpeg, .{ .converter_path = "none" })).?;
    defer result.deinit(gpa);
    const expected = try image_magic.encodeBase64(gpa, &jpeg);
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, result.data_b64);
    try std.testing.expectEqual(@as(u32, 2), result.original_width);
    try std.testing.expectEqual(@as(u32, 3), result.original_height);
    try std.testing.expect(!result.was_resized);
    try std.testing.expect(!result.orientation_normalized);
}

test "safe supported image remains byte-for-byte when converter is disabled" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var png = [_]u8{0} ** 24;
    const signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
    @memcpy(png[0..8], &signature);
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    var result = (try processBytes(gpa, io, &png, .{ .converter_path = "none" })).?;
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("image/png", result.mime_type);
    const expected = try image_magic.encodeBase64(gpa, &png);
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, result.data_b64);
    try std.testing.expect(!result.was_resized);
}

test "BMP conversion requires a backend" {
    const bmp = tinyBmp();
    try std.testing.expect((try processBytes(std.testing.allocator, std.testing.io, &bmp, .{
        .auto_resize = false,
        .converter_path = "none",
    })) == null);
}

test "fitDimensions preserves aspect ratio" {
    try std.testing.expectEqual(Dimensions{ .width = 1000, .height = 2000 }, fitDimensions(.{ .width = 2400, .height = 4800 }, 2000, 2000));
    try std.testing.expectEqual(Dimensions{ .width = 2000, .height = 100 }, fitDimensions(.{ .width = 2400, .height = 120 }, 2000, 2000));
}
