//! Bounded text selection: a header, one line scan, and only the shown prefix.
const std = @import("std");
const types = @import("types.zig");
const filesystem = @import("filesystem.zig");
const decode = @import("decode.zig");
const line_scan = @import("line_scan.zig");
pub const max_bytes = 50 * 1024;
pub const max_lines = 2000;
pub const Selection = struct {
    head: []u8,
    scan: line_scan.LineScan,
    totalLines: u64,
    selectedLines: u64,
    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        gpa.free(self.head);
        self.* = undefined;
    }
};
fn propagate(comptime T: type, result: anytype) types.Result(T) {
    return .{ .failure = result.failure };
}
pub fn head(reader: *filesystem.BinaryReader, start: u64, end: u64, skip_bom: bool, context: types.Context) !types.Result([]u8) {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(reader.gpa);
    var decoder = decode.rangeDecoder();
    const sink: decode.Text = .{ .gpa = reader.gpa, .output = &text };
    var position = if (skip_bom and start == 0) @as(u64, 3) else start;
    var newlines: usize = 0;
    while (position < end) {
        const result = try reader.read(position, @min(64 * 1024, end - position), context);
        if (result == .failure) return propagate([]u8, result);
        const bytes = result.value;
        defer reader.gpa.free(bytes);
        if (bytes.len == 0) break;
        position += bytes.len;
        const before = text.items.len;
        try decoder.push(bytes, sink);
        newlines += std.mem.count(u8, text.items[before..], "\n");
        if (newlines >= max_lines or text.items.len > max_bytes + 1) return .{ .value = try text.toOwnedSlice(reader.gpa) };
    }
    try decoder.finish(sink);
    return .{ .value = try text.toOwnedSlice(reader.gpa) };
}
/// Metadata belongs to the same open file. Retry once if a writer changed it
/// during the scan/read, and never substitute a new file at its original path.
pub fn selection(reader: *filesystem.BinaryReader, options: line_scan.Options, context: types.Context) !types.Result(Selection) {
    for (0..2) |attempt| {
        const info_result = try reader.info(context);
        if (info_result == .failure) return propagate(Selection, info_result);
        var before = info_result.value;
        defer before.deinit(reader.gpa);
        const scanned = try reader.scanLines(options, context);
        if (scanned == .failure) return propagate(Selection, scanned);
        const scan = scanned.value;
        const header = try reader.read(0, 3, context);
        if (header == .failure) return propagate(Selection, header);
        defer reader.gpa.free(header.value);
        const decoded = try head(reader, scan.start, scan.end, decode.startsWithBom(header.value), context);
        if (decoded == .failure) return propagate(Selection, decoded);
        const text = decoded.value;
        var transferred = false;
        defer if (!transferred) reader.gpa.free(text);
        const after_result = try reader.info(context);
        if (after_result == .failure) return propagate(Selection, after_result);
        var after = after_result.value;
        defer after.deinit(reader.gpa);
        if (before.size != after.size or before.mtimeMs != after.mtimeMs) {
            if (attempt == 0) continue;
            return types.failure(Selection, reader.gpa, .invalid, reader.path, null, "File changed while it was read");
        }
        const total_lines = scan.newlines + 1;
        const end_line = @min(options.endLine orelse total_lines, total_lines);
        const selected_lines = if (options.startLine >= end_line) 0 else end_line - options.startLine;
        const terminated = scan.lastLineStart == scan.end and scan.lastLineStart > scan.start;
        transferred = true;
        return .{ .value = .{ .head = text, .scan = scan, .totalLines = total_lines, .selectedLines = if (scan.selectedBytes == 0) 0 else selected_lines - @as(u64, @intFromBool(terminated)) } };
    }
    unreachable;
}
fn characterEnd(text: []const u8, offset: usize) usize {
    var end = @min(offset, text.len);
    while (end > 0 and end < text.len and text[end] & 0xc0 == 0x80) : (end -= 1) {}
    return end;
}
/// Existing CLI text format, using scan totals rather than treating the prefix
/// as the whole file. Structured durable diagnostics can use Selection itself.
pub fn legacyText(gpa: std.mem.Allocator, selected: Selection) ![]u8 {
    if (selected.selectedLines <= max_lines and selected.scan.selectedBytes <= max_bytes) return gpa.dupe(u8, selected.head);
    const first_end = std.mem.indexOfScalar(u8, selected.head, '\n') orelse selected.head.len;
    if (first_end + @as(usize, @intFromBool(first_end < selected.head.len)) > max_bytes) {
        const end = characterEnd(selected.head, max_bytes);
        return std.fmt.allocPrint(gpa, "{s}\n... [truncated: first line exceeds byte limit]", .{selected.head[0..end]});
    }
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var from: usize = 0;
    var count: usize = 0;
    var truncated_by: []const u8 = "lines";
    while (from < selected.head.len) {
        const end = if (std.mem.indexOfScalarPos(u8, selected.head, from, '\n')) |index| index + 1 else selected.head.len;
        if (count >= max_lines) break;
        if (text.items.len + end - from > max_bytes) {
            truncated_by = "bytes";
            break;
        }
        try text.appendSlice(gpa, selected.head[from..end]);
        count += 1;
        from = end;
    }
    if (text.items.len == 0 or text.items[text.items.len - 1] != '\n') try text.append(gpa, '\n');
    const notice = try std.fmt.allocPrint(gpa, "... [truncated: showing {d}/{d} lines, limit {s}]\n", .{ count, selected.selectedLines, truncated_by });
    defer gpa.free(notice);
    try text.appendSlice(gpa, notice);
    return text.toOwnedSlice(gpa);
}

test "durable bounded read selects file lines beyond the old whole-file size limit with bounded memory" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(io, "large", .{});
    defer file.close(io);
    const size = 33 * 1024 * 1024;
    try file.setLength(io, size);
    try file.writePositionalAll(io, "\ntail😀", size - 9);
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(io, &path_buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    var opened = try fs.openBinaryReader("large", .{}, .{});
    if (opened == .failure) {
        defer opened.failure.deinit(gpa);
        return error.ReadFixtureOpenFailed;
    }
    var reader = opened.value;
    defer reader.deinit();
    var result = try selection(&reader, .{ .startLine = 1 }, .{});
    if (result == .failure) {
        defer result.failure.deinit(gpa);
        return error.ReadFixtureFailed;
    }
    var selected = result.value;
    defer selected.deinit(gpa);
    try std.testing.expectEqualStrings("tail😀", selected.head);
    try std.testing.expectEqual(@as(u64, 2), selected.totalLines);
    try std.testing.expectEqual(@as(u64, 1), selected.selectedLines);
    const text = try legacyText(gpa, selected);
    defer gpa.free(text);
    try std.testing.expectEqualStrings("tail😀", text);
}
