//! Source search tools have a byte window without a line limit.
const std = @import("std");
pub const max_bytes = 50 * 1024;
pub const max_lines = 9007199254740991;
pub const Result = struct {
    content: []const u8,
    truncated: bool,
    truncatedBy: ?[]const u8,
    totalLines: usize,
    totalBytes: usize,
    outputLines: usize,
    outputBytes: usize,
    lastLinePartial: bool = false,
    firstLineExceedsLimit: bool = false,
    maxLines: u64 = max_lines,
    maxBytes: u64 = max_bytes,
};
pub fn head(text: []const u8) Result {
    const lines = if (text.len == 0) 0 else std.mem.count(u8, text, "\n") + @as(usize, @intFromBool(!std.mem.endsWith(u8, text, "\n")));
    if (text.len <= max_bytes) return .{ .content = text, .truncated = false, .truncatedBy = null, .totalLines = lines, .totalBytes = text.len, .outputLines = lines, .outputBytes = text.len };
    const first_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    if (first_end > max_bytes) return .{ .content = "", .truncated = true, .truncatedBy = "bytes", .totalLines = lines, .totalBytes = text.len, .outputLines = 0, .outputBytes = 0, .firstLineExceedsLimit = true };
    var end: usize = 0;
    var output_lines: usize = 0;
    var cursor: usize = 0;
    while (cursor < text.len) {
        const next = std.mem.indexOfScalarPos(u8, text, cursor, '\n') orelse text.len;
        if (next > max_bytes) break;
        end = next;
        output_lines += 1;
        cursor = next + 1;
    }
    return .{ .content = text[0..end], .truncated = true, .truncatedBy = "bytes", .totalLines = lines, .totalBytes = text.len, .outputLines = output_lines, .outputBytes = end };
}
