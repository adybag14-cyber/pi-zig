//! Source-backed read selection, including JavaScript slice-number semantics.
const std = @import("std");
const types = @import("types.zig");
const values = @import("tool_types.zig");
const filesystem = @import("filesystem.zig");
const bounded = @import("read.zig");
const scan_module = @import("line_scan.zig");
const decode = @import("decode.zig");
const truncate = @import("truncate.zig");
pub const Input = struct { path: []const u8, offset: ?f64 = null, limit: ?f64 = null };
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
fn image(reader: *filesystem.BinaryReader, size: u64, context: types.Context) !types.Result(?[]const u8) {
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
fn readOnce(reader: *filesystem.BinaryReader, info: types.FileInfo, input: Input, context: types.Context) !values.Result {
    const gpa = reader.gpa;
    const mime = try image(reader, info.size, context);
    if (mime == .failure) return values.fileFailure(gpa, mime.failure);
    var result: values.ToolResult = .{};
    errdefer result.deinit(gpa);
    if (mime.value) |kind| {
        result.isError = true;
        try result.diagnostic(gpa, .err, "unsupported_image", try std.fmt.allocPrint(gpa, "{s} is an image ({s}); reading images is not supported", .{ input.path, kind }));
        return .{ .value = result };
    }
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
        var result = try readOnce(&reader, before, input, context);
        var transferred = false;
        defer if (!transferred) result.deinit(gpa);
        const after_result = try reader.info(context);
        if (after_result == .failure) return values.fileFailure(gpa, after_result.failure);
        var after = after_result.value;
        defer after.deinit(gpa);
        if (before.size != after.size or before.mtimeMs != after.mtimeMs) {
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
