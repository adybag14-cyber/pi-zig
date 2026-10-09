//! JavaScript numeric output limits, including fractional and non-finite values.
//! The integer-only native output API remains independent of this VM boundary.
const std = @import("std");
pub const Retention = enum { head, tail, other };
pub const Limits = struct { maxBytes: f64 = 50 * 1024, maxLines: f64 = 2000, retain: Retention = .tail };
pub const Slice = struct { text: []u8, bytes: usize, droppedBytes: usize, droppedLines: u64 };
fn number(value: usize) f64 {
    return @floatFromInt(value);
}
fn integer(value: f64) f64 {
    return if (std.math.isNan(value)) 0 else @trunc(value);
}
fn relative(value: f64, length: usize) usize {
    const index = integer(value);
    if (index < 0) return @intFromFloat(@max(number(length) + index, 0));
    return @intFromFloat(@min(index, number(length)));
}
fn property(bytes: []const u8, index: f64) u8 {
    if (!std.math.isFinite(index) or index < 0 or index >= number(bytes.len) or @trunc(index) != index) return 0;
    return bytes[@intFromFloat(index)];
}
fn characterEnd(bytes: []const u8, index: f64) f64 {
    var end = index;
    while (end > 0 and property(bytes, end) & 0xc0 == 0x80) end -= 1;
    return end;
}
fn characterStart(bytes: []const u8, index: f64) f64 {
    var start = index;
    while (start < number(bytes.len) and property(bytes, start) & 0xc0 == 0x80) start += 1;
    return start;
}
fn lastNewline(bytes: []const u8, from: f64) ?usize {
    if (bytes.len == 0) return null;
    const index = integer(from);
    if (index < -number(bytes.len)) return null;
    var cursor: usize = if (index < 0) @intFromFloat(number(bytes.len) + index) else @intFromFloat(@min(index, number(bytes.len - 1)));
    while (true) {
        if (bytes[cursor] == '\n') return cursor;
        if (cursor == 0) return null;
        cursor -= 1;
    }
}
fn nextNewline(bytes: []const u8, from: f64) ?usize {
    const start = relative(from, bytes.len);
    return std.mem.indexOfScalarPos(u8, bytes, start, '\n');
}
fn lines(bytes: []const u8) u64 {
    return std.mem.count(u8, bytes, "\n") + @as(u64, @intFromBool(bytes.len != 0 and bytes[bytes.len - 1] != '\n'));
}
pub fn boundOutput(gpa: std.mem.Allocator, bytes: []const u8, limits: Limits) !Slice {
    var from: f64 = 0;
    var to: f64 = number(bytes.len);
    if (limits.maxBytes == 0 or limits.maxLines == 0) {
        if (limits.retain == .head) to = 0 else from = to;
    } else if (limits.retain == .head) {
        var count: f64 = 0;
        for (bytes, 0..) |byte, index| if (byte == '\n') {
            count += 1;
            if (count == limits.maxLines) {
                to = number(index + 1);
                break;
            }
        };
        if (to > limits.maxBytes) to = if (lastNewline(bytes, limits.maxBytes - 1)) |index| number(index + 1) else characterEnd(bytes, limits.maxBytes);
    } else {
        var count: f64 = 1;
        var cursor = if (bytes.len != 0 and bytes[bytes.len - 1] == '\n') bytes.len - 1 else bytes.len;
        while (cursor > 0) {
            cursor -= 1;
            if (bytes[cursor] != '\n') continue;
            if (count == limits.maxLines) {
                from = number(cursor + 1);
                break;
            }
            count += 1;
        }
        if (number(bytes.len) - from > limits.maxBytes) {
            const start = number(bytes.len) - limits.maxBytes;
            const newline = nextNewline(bytes, start - 1);
            from = if (newline != null and newline.? + 1 < bytes.len) number(newline.? + 1) else characterStart(bytes, start);
        }
    }
    const first = relative(from, bytes.len);
    const last = @max(first, relative(to, bytes.len));
    const kept = bytes[first..last];
    // Source's TextDecoder replaces byte fragments caused by fractional indices.
    var decoded: std.ArrayList(u8) = .empty;
    defer decoded.deinit(gpa);
    var decoder = @import("../durable/decode.zig").rangeDecoder();
    try decoder.push(kept, @import("../durable/decode.zig").Text{ .gpa = gpa, .output = &decoded });
    try decoder.finish(@import("../durable/decode.zig").Text{ .gpa = gpa, .output = &decoded });
    return .{ .text = try decoded.toOwnedSlice(gpa), .bytes = kept.len, .droppedBytes = bytes.len - kept.len, .droppedLines = lines(bytes) - lines(kept) };
}
pub fn tailMargin(bytes: []const u8, limits: Limits) usize {
    const byte_start = if (number(bytes.len) > limits.maxBytes) characterEnd(bytes, number(bytes.len) - limits.maxBytes - 1) else 0;
    var line_start: f64 = 0;
    var count: f64 = 0;
    var cursor = bytes.len;
    while (cursor > 0) {
        cursor -= 1;
        if (bytes[cursor] != '\n') continue;
        count += 1;
        if (count > limits.maxLines) {
            line_start = number(cursor);
            break;
        }
    }
    return relative(@max(byte_start, line_start), bytes.len);
}
