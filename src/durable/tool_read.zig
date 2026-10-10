//! Source-backed read selection, including JavaScript slice-number semantics.
const std = @import("std");
const types = @import("types.zig");
const values = @import("tool_types.zig");
const filesystem = @import("filesystem.zig");
const bounded = @import("read.zig");
const scan_module = @import("line_scan.zig");
const decode = @import("decode.zig");
const truncate = @import("truncate.zig");
pub const images = @import("image_processor.zig");
pub const Input = struct { path: []const u8, offset: ?f64 = null, limit: ?f64 = null };
pub const Options = struct {
    images: ?images.Processor = null,
    model: images.Model = .{},
    model_context: ?*anyopaque = null,
    resolve_model: ?*const fn (?*anyopaque, types.Context) anyerror!images.Model = null,
};
test {
    _ = @import("tool_read_images42a_test.zig");
}
fn integer(number: f64) f64 {
    return if (std.math.isNan(number)) 0 else @trunc(number);
}
fn safe(number: f64) bool {
    return std.math.isFinite(number) and number >= 0 and number <= scan_module.max_safe_integer and number == @trunc(number);
}
fn minimum(a: f64, b: f64) f64 {
    return if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(f64) else @min(a, b);
}
fn maximum(a: f64, b: f64) f64 {
    return if (std.math.isNan(a) or std.math.isNan(b)) std.math.nan(f64) else @max(a, b);
}
fn be(bytes: []const u8, at: usize) u32 {
    if (at + 4 > bytes.len) return 0;
    return std.mem.readInt(u32, bytes[at..][0..4], .big);
}
fn le(bytes: []const u8, at: usize) u32 {
    if (at + 4 > bytes.len) return 0;
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
fn starts(bytes: []const u8, at: usize, text: []const u8) bool {
    return at <= bytes.len and std.mem.startsWith(u8, bytes[at..], text);
}
fn bmp(bytes: []const u8) bool {
    if (bytes.len < 26) return false;
    const size = le(bytes, 2);
    const pixels = le(bytes, 10);
    const dib = le(bytes, 14);
    if ((size != 0 and size < 26) or @as(u64, pixels) < 14 + @as(u64, dib) or (size != 0 and pixels >= size)) return false;
    const at: usize = if (dib == 12) 22 else if (dib >= 40 and dib <= 124 and bytes.len >= 30) 26 else return false;
    const planes = std.mem.readInt(u16, bytes[at..][0..2], .little);
    const bits = std.mem.readInt(u16, bytes[at + 2 ..][0..2], .little);
    return planes == 1 and switch (bits) {
        1, 4, 8, 16, 24, 32 => true,
        else => false,
    };
}
fn image(reader: anytype, size: u64, context: types.Context) !types.Result(?[]const u8) {
    const result = try reader.read(0, 32, context);
    if (result == .failure) return .{ .failure = result.failure };
    const header = result.value;
    defer reader.gpa.free(header);
    if (starts(header, 0, "\xff\xd8\xff")) return .{ .value = if (header.len > 3 and header[3] == 0xf7) null else "image/jpeg" };
    if (starts(header, 0, "GIF87a") or starts(header, 0, "GIF89a")) return .{ .value = "image/gif" };
    if (starts(header, 0, "RIFF") and starts(header, 8, "WEBP")) return .{ .value = "image/webp" };
    if (starts(header, 0, "BM") and bmp(header)) return .{ .value = "image/bmp" };
    if (!starts(header, 0, "\x89PNG\r\n\x1a\n") or header.len < 16 or be(header, 8) != 13 or !starts(header, 12, "IHDR")) return .{ .value = null };
    var offset: u64 = 8;
    while (offset + 8 <= size) {
        const chunk = try reader.read(offset, 8, context);
        if (chunk == .failure) return .{ .failure = chunk.failure };
        defer reader.gpa.free(chunk.value);
        if (starts(chunk.value, 4, "acTL")) return .{ .value = null };
        if (starts(chunk.value, 4, "IDAT")) break;
        const next = offset + 12 + be(chunk.value, 0);
        if (next <= offset or next > size) break;
        offset = next;
    }
    return .{ .value = "image/png" };
}
fn imageError(gpa: std.mem.Allocator, message: []u8) !values.Result {
    var result: values.ToolResult = .{ .isError = true };
    errdefer result.deinit(gpa);
    try result.diagnostic(gpa, .err, "unsupported_image", message);
    return .{ .value = result };
}
fn imageNote(writer: *std.Io.Writer, comptime format: []const u8, args: anytype) !void {
    // This writer is allocation-backed; its only drain failure is OOM.
    writer.print(format, args) catch return error.OutOfMemory;
}
fn readImage(reader: anytype, info: types.FileInfo, input: Input, mime: []const u8, options: Options, context: types.Context) !values.Result {
    const gpa = reader.gpa;
    const model = if (options.resolve_model) |resolve| try resolve(options.model_context, context) else options.model;
    var prepared: images.Prepared = undefined;
    if (options.images) |processor| {
        const read_result = try reader.read(0, info.size, context);
        if (read_result == .failure) return values.fileFailure(gpa, read_result.failure);
        defer gpa.free(read_result.value);
        prepared = (try processor.prepare(processor.context, gpa, read_result.value, mime, model.limits)) orelse
            return imageError(gpa, try std.fmt.allocPrint(gpa, "{s} is an image ({s}) that cannot be prepared for the model", .{ input.path, mime }));
    } else {
        if (!images.inlineType(mime)) return imageError(gpa, try std.fmt.allocPrint(gpa, "{s} is an image ({s}) that needs converting, and no image processor is configured", .{ input.path, mime }));
        const base64_length = @ceil(@as(f64, @floatFromInt(info.size)) / 3) * 4;
        if (base64_length > model.limits.maxBytes) {
            const size = try truncate.formatSize(gpa, info.size);
            defer gpa.free(size);
            return imageError(gpa, try std.fmt.allocPrint(gpa, "{s} is an image ({s}) of {s}, too large to send, and no image processor is configured to shrink it", .{ input.path, mime, size }));
        }
        const read_result = try reader.read(0, info.size, context);
        if (read_result == .failure) return values.fileFailure(gpa, read_result.failure);
        defer gpa.free(read_result.value);
        const size = images.dimensions(read_result.value, mime) orelse return imageError(gpa, try std.fmt.allocPrint(gpa, "{s} is an image ({s}) whose size cannot be read", .{ input.path, mime }));
        if (size.width > model.limits.maxWidth or size.height > model.limits.maxHeight) return imageError(gpa, try std.fmt.allocPrint(gpa, "{s} is an image ({s}) of {d}x{d}, larger than {d}x{d}, and no image processor is configured to shrink it", .{ input.path, mime, size.width, size.height, model.limits.maxWidth, model.limits.maxHeight }));
        const encoder = std.base64.standard.Encoder;
        const encoded = try gpa.alloc(u8, encoder.calcSize(read_result.value.len));
        errdefer gpa.free(encoded);
        _ = encoder.encode(encoded, read_result.value);
        prepared = .{ .data = encoded, .mimeType = try gpa.dupe(u8, mime) };
    }
    var transferred = false;
    defer if (!transferred) prepared.deinit(gpa) else if (prepared.convertedFrom) |value| gpa.free(value);
    var result: values.ToolResult = .{};
    errdefer result.deinit(gpa);
    var message: std.Io.Writer.Allocating = .init(gpa);
    defer message.deinit();
    try imageNote(&message.writer, "Read image file [{s}].", .{prepared.mimeType});
    if (prepared.convertedFrom) |from| try imageNote(&message.writer, " Converted from {s} to {s}.", .{ from, prepared.mimeType });
    if (prepared.resized) |resize| try imageNote(&message.writer, " Resized from {d}x{d} to {d}x{d}. Multiply coordinates by {d:.2} to map them to the original.", .{ resize.from.width, resize.from.height, resize.to.width, resize.to.height, resize.from.width / resize.to.width });
    if (!model.vision) try imageNote(&message.writer, " The current model does not support images; it sees a placeholder instead.", .{});
    try result.diagnostic(gpa, .info, "image", try gpa.dupe(u8, message.written()));
    try result.images.append(gpa, .{ .data = prepared.data, .mimeType = prepared.mimeType });
    transferred = true;
    return .{ .value = result };
}
fn readOnce(reader: anytype, info: types.FileInfo, input: Input, options: Options, is_image: *bool, context: types.Context) !values.Result {
    const gpa = reader.gpa;
    const mime = try image(reader, info.size, context);
    if (mime == .failure) return values.fileFailure(gpa, mime.failure);
    is_image.* = mime.value != null;
    if (mime.value) |kind| return readImage(reader, info, input, kind, options, context);
    var result: values.ToolResult = .{};
    errdefer result.deinit(gpa);
    const offset = input.offset orelse 0;
    const start_line = if (offset == 0 or std.math.isNan(offset)) @as(f64, 0) else maximum(0, offset - 1);
    const display = start_line + 1;
    const slice_start = integer(start_line);
    const scan_start: u64 = if (safe(slice_start)) @intFromFloat(slice_start) else 0;
    const requested_end = if (input.limit) |limit| maximum(@as(f64, @floatFromInt(scan_start)) + 1, integer(start_line + limit)) else null;
    const scan_end: ?u64 = if (requested_end) |end| if (safe(end)) @intFromFloat(end) else null else null;
    const scanned = try reader.scanLines(.{ .startLine = scan_start, .endLine = scan_end }, context);
    if (scanned == .failure) return values.fileFailure(gpa, scanned.failure);
    var scan = scanned.value;
    const total = scan.newlines + 1;
    const total_float: f64 = @floatFromInt(total);
    if (start_line >= total_float) return .{ .failure = .{ .message = if (std.math.isInf(offset)) try std.fmt.allocPrint(gpa, "Offset Infinity is beyond end of file ({d} lines total)", .{total}) else try std.fmt.allocPrint(gpa, "Offset {d} is beyond end of file ({d} lines total)", .{ offset, total }) } };
    var limited: ?f64 = null;
    var selected_count: f64 = total_float - slice_start;
    if (input.limit) |limit| {
        const end_line = minimum(start_line + limit, total_float);
        limited = end_line - start_line;
        const relative_end = integer(end_line);
        const slice_end = if (relative_end < 0) maximum(total_float + relative_end, 0) else relative_end;
        selected_count = maximum(0, slice_end - slice_start);
        if (selected_count > 0 and relative_end < 0) {
            const rescanned = try reader.scanLines(.{ .startLine = scan_start, .endLine = @intFromFloat(slice_end) }, context);
            if (rescanned == .failure) return values.fileFailure(gpa, rescanned.failure);
            scan = rescanned.value;
        }
    }
    const empty = selected_count == 0;
    const terminated = !empty and scan.lastLineStart == scan.end and scan.lastLineStart > scan.start;
    const total_lines: u64 = if (empty or scan.selectedBytes == 0) 0 else @as(u64, @intFromFloat(selected_count)) - @as(u64, @intFromBool(terminated));
    const total_bytes = if (empty) 0 else scan.selectedBytes;
    const header = try reader.read(0, 3, context);
    if (header == .failure) return values.fileFailure(gpa, header.failure);
    defer gpa.free(header.value);
    const selected = if (empty) types.Result([]u8){ .value = try gpa.dupe(u8, "") } else try bounded.head(reader, scan.start, scan.end, decode.startsWithBom(header.value), context);
    if (selected == .failure) return values.fileFailure(gpa, selected.failure);
    const head = selected.value;
    defer gpa.free(head);
    const cut = truncate.headOf(head, total_lines, total_bytes);
    var details = cut.details;
    var text = cut.content;
    if (details.firstLineExceedsLimit) {
        const integral = start_line == integer(start_line);
        const line = if (integral) head[0..(std.mem.indexOfScalar(u8, head, '\n') orelse head.len)] else "";
        const end = truncate.characterEnd(line, truncate.max_bytes);
        text = line[0..end];
        const size = try truncate.formatSize(gpa, if (integral) scan.firstLineBytes else 0);
        defer gpa.free(size);
        const shown = try truncate.formatSize(gpa, end);
        defer gpa.free(shown);
        try result.diagnostic(gpa, .warn, "truncated", try std.fmt.allocPrint(gpa, "Line {d} is {s}, exceeds the 50.0KB limit; showing its first {s}. Use bash: sed -n '{d}p' {s} | tail -c +{d}", .{ display, size, shown, display, input.path, end + 1 }));
        details.outputBytes = end;
        details.outputLines = 1;
        result.details = .{ .truncation = details };
    } else if (details.truncated) {
        const end_display = display + @as(f64, @floatFromInt(details.outputLines)) - 1;
        try result.diagnostic(gpa, .info, "truncated", try std.fmt.allocPrint(gpa, "Showing lines {d}-{d} of {d}{s}. Use offset={d} to continue.", .{ display, end_display, total, if (details.truncatedBy == .lines) "" else " (50.0KB limit)", end_display + 1 }));
        result.details = .{ .truncation = details };
    } else if (limited) |count| {
        if (start_line + count < total_float) try result.diagnostic(gpa, .info, null, try std.fmt.allocPrint(gpa, "{d} more lines in file. Use offset={d} to continue.", .{ total_float - (start_line + count), start_line + count + 1 }));
    }
    if (text.len != 0) result.text = try gpa.dupe(u8, text);
    return .{ .value = result };
}
pub fn execute(env: anytype, input: Input, context: types.Context) !values.Result {
    return executeWithOptions(env, input, .{}, context);
}
pub fn executeWithOptions(env: anytype, input: Input, options: Options, context: types.Context) !values.Result {
    const gpa = env.fs.gpa;
    const resolved = try resolvePath(gpa, env, input.path, context);
    if (resolved == .failure) return values.fileFailure(gpa, resolved.failure);
    const path = resolved.value;
    defer gpa.free(path);
    const opened = try env.openBinaryReader(path, .{}, context);
    if (opened == .failure) return values.fileFailure(gpa, opened.failure);
    var reader = opened.value;
    defer reader.deinit();
    for (0..2) |attempt| {
        const before_result = try reader.info(context);
        if (before_result == .failure) return values.fileFailure(gpa, before_result.failure);
        var before = before_result.value;
        defer before.deinit(gpa);
        var is_image = false;
        var result = try readOnce(&reader, before, input, options, &is_image, context);
        var transferred = false;
        defer if (!transferred) result.deinit(gpa);
        const after_result = try reader.info(context);
        if (after_result == .failure) return values.fileFailure(gpa, after_result.failure);
        var after = after_result.value;
        defer after.deinit(gpa);
        const unchanged = after.size == before.size and after.mtimeMs == before.mtimeMs;
        if (!unchanged and (is_image or after.size <= before.size)) {
            if (attempt == 0) continue;
            return .{ .failure = .{ .message = try std.fmt.allocPrint(gpa, "{s} changed while it was read", .{input.path}) } };
        }
        transferred = true;
        return result;
    }
    unreachable;
}
pub fn resolvePath(gpa: std.mem.Allocator, env: anytype, path: []const u8, context: types.Context) !types.Result([]u8) {
    const text = @import("text.zig");
    const normalized = try text.toolPath(gpa, path);
    defer gpa.free(normalized);
    const resolved = try env.absolutePath(normalized, context);
    if (resolved == .failure) return resolved;
    const original = resolved.value;
    var transferred = false;
    defer if (!transferred) gpa.free(original);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const temporary = arena.allocator();
    const nfd = try text.normalize(temporary, original, .nfd);
    const candidates = [_][]const u8{ original, try text.screenshot(temporary, original), nfd, try text.curly(temporary, original), try text.curly(temporary, nfd) };
    for (candidates, 0..) |candidate, index| {
        var duplicate = false;
        for (candidates[0..index]) |earlier| if (std.mem.eql(u8, candidate, earlier)) {
            duplicate = true;
            break;
        };
        if (duplicate) continue;
        const exists = try env.exists(candidate, context);
        if (exists == .failure) return .{ .failure = exists.failure };
        if (exists.value) return .{ .value = try gpa.dupe(u8, candidate) };
    }
    transferred = true;
    return .{ .value = original };
}

test "durable b7df growing real file returns the scanned selection without a retry" {
    const gpa = std.testing.allocator;
    const original = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    try scratch.dir.writeFile(original, .{ .sub_path = "log", .data = "a\nb" });
    const writer = try scratch.dir.openFile(original, "log", .{ .mode = .read_write });
    defer writer.close(original);
    const Hook = struct {
        var io: std.Io = undefined;
        var writerFile: std.Io.File = undefined;
        var calls: usize = 0;
        var mutationError: ?anyerror = null;
        fn stat(context: ?*anyopaque, file: std.Io.File) std.Io.File.StatError!std.Io.File.Stat {
            calls += 1;
            // Regular-file validation consumes one stat; the next two are
            // readText's before/after metadata checks on every platform.
            if (calls == 3) writerFile.writePositionalAll(io, "\nadded", 3) catch |err| {
                mutationError = err;
            };
            return io.vtable.fileStat(context, file);
        }
    };
    Hook.io = original;
    Hook.writerFile = writer;
    Hook.calls = 0;
    Hook.mutationError = null;
    var vtable = original.vtable.*;
    vtable.fileStat = Hook.stat;
    var modified = original;
    modified.vtable = &vtable;
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(original, &buffer);
    var fs = try filesystem.FileSystem.init(gpa, modified, buffer[0..length], null);
    defer fs.deinit();
    const Env = struct {
        fs: filesystem.FileSystem,
        fn openBinaryReader(self: *@This(), path: []const u8, options: filesystem.OpenBinaryOptions, context: types.Context) !types.Result(filesystem.BinaryReader) {
            return self.fs.openBinaryReader(path, options, context);
        }
        fn absolutePath(self: *@This(), path: []const u8, context: types.Context) !types.Result([]u8) {
            return self.fs.absolutePath(path, context);
        }
        fn exists(self: *@This(), path: []const u8, context: types.Context) !types.Result(bool) {
            return self.fs.exists(path, context);
        }
    };
    var env: Env = .{ .fs = fs };
    var result = try execute(&env, .{ .path = "log" }, .{});
    defer result.deinit(gpa);
    try std.testing.expect(Hook.mutationError == null);
    try std.testing.expect(result == .value);
    var fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/growing_read_b7df.json"), .{});
    defer fixture.deinit();
    const expected = fixture.value.object.get("result").?.object.get("content").?.array.items[0].object.get("text").?.string;
    try std.testing.expectEqualStrings(expected, result.value.text.?);
    try std.testing.expectEqual(@as(usize, 3), Hook.calls);
    const contents = try scratch.dir.readFileAlloc(original, "log", gpa, .limited(100));
    defer gpa.free(contents);
    try std.testing.expectEqualStrings("a\nb\nadded", contents);
}
