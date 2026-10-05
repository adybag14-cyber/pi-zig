//! Whole-line head truncation, given a bounded decoded prefix and exact totals.
const std = @import("std");
pub const max_lines = 2000;
pub const max_bytes = 50 * 1024;
pub const By = enum { lines, bytes };
pub const Details = struct {
    truncated: bool = false,
    truncatedBy: ?By = null,
    totalLines: u64,
    totalBytes: u64,
    outputLines: u64,
    outputBytes: u64,
    lastLinePartial: bool = false,
    firstLineExceedsLimit: bool = false,
    maxLines: u64 = max_lines,
    maxBytes: u64 = max_bytes,
};
pub const Result = struct { content: []const u8, details: Details };
pub fn headOf(prefix: []const u8, lines: u64, bytes: u64) Result {
    var details: Details = .{ .totalLines = lines, .totalBytes = bytes, .outputLines = lines, .outputBytes = bytes };
    if (lines <= max_lines and bytes <= max_bytes) return .{ .content = prefix, .details = details };
    details.truncated = true;
    details.outputLines = 0;
    details.outputBytes = 0;
    details.truncatedBy = .bytes;
    const first_end = std.mem.indexOfScalar(u8, prefix, '\n') orelse prefix.len;
    if (first_end > max_bytes) {
        details.firstLineExceedsLimit = true;
        return .{ .content = "", .details = details };
    }
    var start: usize = 0;
    var end: usize = 0;
    var byte_break = false;
    while (start < prefix.len and details.outputLines < max_lines) {
        const next = std.mem.indexOfScalarPos(u8, prefix, start, '\n') orelse prefix.len;
        if (next > max_bytes) {
            byte_break = true;
            break;
        }
        end = next;
        details.outputLines += 1;
        start = next + 1;
    }
    details.outputBytes = end;
    details.truncatedBy = if (byte_break or details.outputLines >= lines) .bytes else .lines;
    return .{ .content = prefix[0..end], .details = details };
}
pub fn characterEnd(text: []const u8, offset: usize) usize {
    var end = @min(offset, text.len);
    while (end > 0 and end < text.len and text[end] & 0xc0 == 0x80) : (end -= 1) {}
    return end;
}
pub fn formatSize(gpa: std.mem.Allocator, bytes: u64) ![]u8 {
    if (bytes < 1024) return std.fmt.allocPrint(gpa, "{d}B", .{bytes});
    const divisor: f64 = if (bytes < 1024 * 1024) 1024 else 1024 * 1024;
    return std.fmt.allocPrint(gpa, "{d:.1}{s}", .{ @as(f64, @floatFromInt(bytes)) / divisor, if (divisor == 1024) "KB" else "MB" });
}
