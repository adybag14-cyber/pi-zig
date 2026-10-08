//! UTF16 layout helpers for Source Input. ANSI admission follows Source utils.
const std = @import("std");
const graphemes = @import("utf16_graphemes.zig");
const terminal = @import("terminal_text.zig");
pub fn ansiLength(text: []const u16, start: usize) usize {
    if (start + 1 >= text.len or text[start] != 0x1b) return 0;
    const kind = text[start + 1];
    if (kind == '[') {
        for (text[start + 2 ..], start + 2..) |unit, index| switch (unit) {
            'm', 'G', 'K', 'H', 'J' => return index + 1 - start,
            else => {},
        };
    } else if (kind == ']' or kind == '_') {
        for (text[start + 2 ..], start + 2..) |unit, index| {
            if (unit == 7) return index + 1 - start;
            if (unit == 0x1b and index + 1 < text.len and text[index + 1] == '\\') return index + 2 - start;
        }
    }
    return 0;
}
pub fn graphemeWidth(gpa: std.mem.Allocator, text: []const u16) !usize {
    _ = gpa;
    return @import("utf16_width.zig").width(text);
}
pub fn visibleWidth(gpa: std.mem.Allocator, text: []const u16) !usize {
    var clean: std.ArrayList(u16) = .empty;
    defer clean.deinit(gpa);
    var at: usize = 0;
    while (at < text.len) {
        const ansi = ansiLength(text, at);
        if (ansi != 0) {
            at += ansi;
            continue;
        }
        if (text[at] == '\t') try clean.appendSlice(gpa, &.{ ' ', ' ', ' ' }) else try clean.append(gpa, text[at]);
        at += 1;
    }
    var total: usize = 0;
    var iterator: graphemes.Iterator = .{ .text = clean.items };
    while (iterator.next()) |segment| total += try graphemeWidth(gpa, clean.items[segment.start..segment.end]);
    return total;
}
pub fn sliceAlloc(gpa: std.mem.Allocator, text: []const u16, start: usize, length: usize) ![]u16 {
    if (length == 0) return gpa.dupe(u16, &.{});
    const end_column = start + length;
    var result: std.ArrayList(u16) = .empty;
    errdefer result.deinit(gpa);
    var pending: std.ArrayList(u16) = .empty;
    defer pending.deinit(gpa);
    var column: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const ansi = ansiLength(text, at);
        if (ansi != 0) {
            if (column >= start and column < end_column) {
                try result.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try result.appendSlice(gpa, text[at..][0..ansi]);
            } else if (column < start) try pending.appendSlice(gpa, text[at..][0..ansi]);
            at += ansi;
            continue;
        }
        var text_end = at;
        while (text_end < text.len and ansiLength(text, text_end) == 0) : (text_end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = text[at..text_end] };
        while (iterator.next()) |segment| {
            const cluster = text[at + segment.start .. at + segment.end];
            const width = try graphemeWidth(gpa, cluster);
            if (column >= start and column < end_column and column + width <= end_column) {
                try result.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try result.appendSlice(gpa, cluster);
            }
            column += width;
            if (column >= end_column) break;
        }
        at = text_end;
        if (column >= end_column) break;
    }
    return result.toOwnedSlice(gpa);
}
fn hyperlinkClose(gpa: std.mem.Allocator, output: *std.ArrayList(u16)) !void {
    var active: ?[]const u16 = null;
    var at: usize = 0;
    const prefix = std.unicode.utf8ToUtf16LeStringLiteral("\x1b]8;");
    while (at < output.items.len) {
        const count = ansiLength(output.items, at);
        if (count == 0) {
            at += 1;
            continue;
        }
        const code = output.items[at..][0..count];
        if (std.mem.startsWith(u16, code, prefix)) {
            const terminator: usize = if (code[code.len - 1] == 7) 1 else 2;
            const body = code[prefix.len .. code.len - terminator];
            if (std.mem.indexOfScalar(u16, body, ';')) |separator| active = if (separator + 1 == body.len) null else code[code.len - terminator ..];
        }
        at += count;
    }
    if (active) |terminator| {
        // Copy the terminator before append can invalidate the output storage.
        const bel = terminator.len == 1;
        try output.appendSlice(gpa, std.unicode.utf8ToUtf16LeStringLiteral("\x1b]8;;"));
        try output.appendSlice(gpa, if (bel) &.{7} else &.{ 0x1b, '\\' });
    }
}
/// Source truncateToWidth(text, width, "") without padding.
pub fn truncateAlloc(gpa: std.mem.Allocator, text: []const u16, maximum: usize) ![]u16 {
    if (maximum == 0) return gpa.dupe(u16, &.{});
    var result: std.ArrayList(u16) = .empty;
    errdefer result.deinit(gpa);
    var pending: std.ArrayList(u16) = .empty;
    defer pending.deinit(gpa);
    var total: usize = 0;
    var kept: usize = 0;
    var contiguous = true;
    var at: usize = 0;
    while (at < text.len) {
        const ansi = ansiLength(text, at);
        if (ansi != 0) {
            try pending.appendSlice(gpa, text[at..][0..ansi]);
            at += ansi;
            continue;
        }
        var text_end = at;
        while (text_end < text.len and ansiLength(text, text_end) == 0) : (text_end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = text[at..text_end] };
        while (iterator.next()) |segment| {
            const cluster = text[at + segment.start .. at + segment.end];
            const width = try graphemeWidth(gpa, cluster);
            if (contiguous and kept + width <= maximum) {
                try result.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try result.appendSlice(gpa, cluster);
                kept += width;
            } else {
                contiguous = false;
                pending.clearRetainingCapacity();
            }
            total += width;
            if (total > maximum) {
                try hyperlinkClose(gpa, &result);
                try result.appendSlice(gpa, std.unicode.utf8ToUtf16LeStringLiteral("\x1b[0m"));
                return result.toOwnedSlice(gpa);
            }
        }
        at = text_end;
    }
    const original = try gpa.dupe(u16, text);
    result.deinit(gpa);
    return original;
}
