//! Process CLI `@file` arguments into prompt text and durable image attachments.
//!
//! Unlike the old checkpoint path, this module never interpolates arbitrary
//! binary bytes into a UTF-8 prompt. Supported images are identified from magic
//! bytes and base64 encoded; text must be valid UTF-8 and NUL-free; other binary
//! inputs become an explicit omission marker.
const std = @import("std");
const Io = std.Io;
const images = @import("../ai/images.zig");
const image_process = @import("../ai/image_process.zig");
const path_utils = @import("path_utils.zig");

pub const Options = struct {
    max_file_bytes: usize = 32 * 1024 * 1024,
    max_total_bytes: usize = 64 * 1024 * 1024,
    /// Original `images.autoResize` behavior. Safe provider-native images are
    /// retained byte-for-byte; oversized/rotated/unsupported images are
    /// normalized before becoming durable attachments.
    auto_resize_images: bool = true,
    /// Deterministic override used by tests and private/self-contained installs.
    image_converter_path: ?[]const u8 = null,
};

pub const ImageAttachment = struct {
    path: []u8,
    mime_type: []u8,
    data_b64: []u8,

    pub fn deinit(self: *ImageAttachment, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.mime_type);
        gpa.free(self.data_b64);
        self.* = undefined;
    }
};

pub const ProcessedFiles = struct {
    text: []u8,
    images: []ImageAttachment,

    pub fn deinit(self: *ProcessedFiles, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        for (self.images) |*image| image.deinit(gpa);
        gpa.free(self.images);
        self.* = undefined;
    }
};

/// Public file-magic MIME detector matching the current coding-agent export.
/// The returned MIME slice is static; null means the file is not one of the
/// supported inline image formats.
pub fn detectSupportedImageMimeTypeFromFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !?[]const u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024)) catch |err| switch (err) {
        error.StreamTooLong => return error.FileTooLarge,
        else => return err,
    };
    defer gpa.free(data);
    const inspection = image_process.inspect(data) orelse return null;
    return inspection.mime_type;
}

pub fn processFileArguments(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    cwd: []const u8,
    file_args: []const []const u8,
    options: Options,
) !ProcessedFiles {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(gpa);
    var attachments: std.ArrayList(ImageAttachment) = .empty;
    errdefer {
        for (attachments.items) |*item| item.deinit(gpa);
        attachments.deinit(gpa);
    }

    var total_bytes: usize = 0;
    for (file_args) |file_arg| {
        const absolute_path = try path_utils.resolveReadPath(gpa, io, environ, file_arg, cwd);
        defer gpa.free(absolute_path);
        if (!path_utils.pathExists(io, absolute_path)) return error.FileNotFound;

        const data = std.Io.Dir.cwd().readFileAlloc(io, absolute_path, gpa, .limited(options.max_file_bytes)) catch |err| switch (err) {
            error.StreamTooLong => return error.FileTooLarge,
            else => return err,
        };
        defer gpa.free(data);
        if (data.len == 0) continue;
        total_bytes = std.math.add(usize, total_bytes, data.len) catch return error.TotalInputTooLarge;
        if (total_bytes > options.max_total_bytes) return error.TotalInputTooLarge;

        if (image_process.inspect(data)) |inspection| {
            try appendFileOpen(&text, gpa, absolute_path);
            var processed = try image_process.processBytes(gpa, io, data, .{
                .auto_resize = options.auto_resize_images,
                .converter_path = options.image_converter_path,
                .environ = environ,
            });
            if (processed) |*normalized| {
                defer normalized.deinit(gpa);
                const hints = try normalized.formatHints(gpa);
                defer gpa.free(hints);
                try attachments.append(gpa, .{
                    .path = try gpa.dupe(u8, absolute_path),
                    .mime_type = try gpa.dupe(u8, normalized.mime_type),
                    .data_b64 = try gpa.dupe(u8, normalized.data_b64),
                });
                if (hints.len > 0) {
                    try text.append(gpa, '>');
                    try text.appendSlice(gpa, hints);
                    try text.appendSlice(gpa, "</file>\n");
                } else {
                    try text.appendSlice(gpa, "></file>\n");
                }
            } else {
                if (std.mem.eql(u8, inspection.mime_type, "image/bmp")) {
                    try text.appendSlice(gpa, ">[Image omitted: could not be converted to a supported inline image format.]</file>\n");
                } else {
                    try text.appendSlice(gpa, ">[Image omitted: could not be resized below the inline image size limit.]</file>\n");
                }
            }
            continue;
        }

        try appendFileOpen(&text, gpa, absolute_path);
        if (std.unicode.utf8ValidateSlice(data) and std.mem.indexOfScalar(u8, data, 0) == null) {
            try text.appendSlice(gpa, ">\n");
            try text.appendSlice(gpa, data);
            try text.appendSlice(gpa, "\n</file>\n");
        } else {
            try text.appendSlice(gpa, ">[File omitted: binary data is not a supported inline image.]</file>\n");
        }
    }

    return .{
        .text = try text.toOwnedSlice(gpa),
        .images = try attachments.toOwnedSlice(gpa),
    };
}

fn appendFileOpen(out: *std.ArrayList(u8), gpa: std.mem.Allocator, path: []const u8) !void {
    try out.appendSlice(gpa, "<file name=\"");
    for (path) |c| switch (c) {
        '&' => try out.appendSlice(gpa, "&amp;"),
        '"' => try out.appendSlice(gpa, "&quot;"),
        '<' => try out.appendSlice(gpa, "&lt;"),
        '>' => try out.appendSlice(gpa, "&gt;"),
        else => try out.append(gpa, c),
    };
    try out.append(gpa, '"');
}

test "process file arguments separates text, images, and unsupported binary" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "notes with space.txt", .data = "hello π" });
    var png = [_]u8{0} ** 24;
    @memcpy(png[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a });
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    try tmp.dir.writeFile(io, .{ .sub_path = "renamed.bin", .data = &png });
    try tmp.dir.writeFile(io, .{ .sub_path = "blob.bin", .data = &.{ 0xff, 0x00, 0xfe } });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const renamed_path = try std.fs.path.join(gpa, &.{ root, "renamed.bin" });
    defer gpa.free(renamed_path);
    try std.testing.expectEqualStrings("image/png", (try detectSupportedImageMimeTypeFromFile(gpa, io, renamed_path)).?);

    const args = [_][]const u8{ "notes with space.txt", "renamed.bin", "blob.bin" };
    var result = try processFileArguments(gpa, io, &env, root, &args, .{});
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), result.images.len);
    try std.testing.expectEqualStrings("image/png", result.images[0].mime_type);
    const expected = try images.encodeBase64(gpa, &png);
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, result.images[0].data_b64);
    try std.testing.expect(std.mem.indexOf(u8, result.text, "hello π") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.text, "renamed.bin\"></file>") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.text, "binary data is not a supported inline image") != null);
}

test "process file arguments omits BMP when conversion is unavailable" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
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
    try tmp.dir.writeFile(io, .{ .sub_path = "photo.bmp", .data = &bmp });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    var result = try processFileArguments(gpa, io, &env, root, &.{"photo.bmp"}, .{
        .image_converter_path = "none",
    });
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), result.images.len);
    try std.testing.expect(std.mem.indexOf(u8, result.text, "could not be converted") != null);
}

test "process file arguments rejects missing files and skips empty files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "empty.txt", .data = "" });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    var empty = try processFileArguments(gpa, io, &env, root, &.{"empty.txt"}, .{});
    defer empty.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), empty.text.len);
    try std.testing.expectEqual(@as(usize, 0), empty.images.len);
    try std.testing.expectError(error.FileNotFound, processFileArguments(gpa, io, &env, root, &.{"missing.txt"}, .{}));
}
