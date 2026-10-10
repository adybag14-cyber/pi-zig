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
    return truncateOptionsAlloc(gpa, text, @floatFromInt(maximum), &.{}, false);
}
const Fragment = struct { text: []u16, width: usize };
fn fragmentAlloc(gpa: std.mem.Allocator, text: []const u16, maximum: f64) !Fragment {
    var output: std.ArrayList(u16) = .empty;
    errdefer output.deinit(gpa);
    var pending: std.ArrayList(u16) = .empty;
    defer pending.deinit(gpa);
    var total: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const ansi = ansiLength(text, at);
        if (ansi != 0) {
            try pending.appendSlice(gpa, text[at..][0..ansi]);
            at += ansi;
            continue;
        }
        var end = at;
        while (end < text.len and ansiLength(text, end) == 0) : (end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = text[at..end] };
        while (iterator.next()) |part| {
            const cluster = text[at + part.start .. at + part.end];
            const width = try graphemeWidth(gpa, cluster);
            if (@as(f64, @floatFromInt(total + width)) > maximum) return .{ .text = try output.toOwnedSlice(gpa), .width = total };
            try output.appendSlice(gpa, pending.items);
            pending.clearRetainingCapacity();
            try output.appendSlice(gpa, cluster);
            total += width;
        }
        at = end;
    }
    return .{ .text = try output.toOwnedSlice(gpa), .width = total };
}
fn padding(gpa: std.mem.Allocator, output: *std.ArrayList(u16), maximum: f64, visible: usize) !void {
    const needed = @max(0, maximum - @as(f64, @floatFromInt(visible)));
    try output.appendNTimes(gpa, ' ', @intFromFloat(needed));
}
fn finalize(gpa: std.mem.Allocator, output: *std.ArrayList(u16), prefix_width: usize, ellipsis: []const u16, ellipsis_width: usize, maximum: f64, pad: bool) ![]u16 {
    try hyperlinkClose(gpa, output);
    try output.appendSlice(gpa, std.unicode.utf8ToUtf16LeStringLiteral("\x1b[0m"));
    if (ellipsis.len != 0) {
        try output.appendSlice(gpa, ellipsis);
        try output.appendSlice(gpa, std.unicode.utf8ToUtf16LeStringLiteral("\x1b[0m"));
    }
    if (pad) try padding(gpa, output, maximum, prefix_width + ellipsis_width);
    return output.toOwnedSlice(gpa);
}
pub fn truncateOptionsAlloc(gpa: std.mem.Allocator, text: []const u16, maximum: f64, ellipsis: []const u16, pad: bool) ![]u16 {
    if (maximum <= 0) return gpa.dupe(u16, &.{});
    if (!std.math.isFinite(maximum) or maximum > 1_000_000) return error.InvalidTerminalLayoutWidth;
    var result: std.ArrayList(u16) = .empty;
    errdefer result.deinit(gpa);
    if (text.len == 0) {
        if (pad) try padding(gpa, &result, maximum, 0);
        return result.toOwnedSlice(gpa);
    }
    const ellipsis_width = try visibleWidth(gpa, ellipsis);
    if (@as(f64, @floatFromInt(ellipsis_width)) >= maximum) {
        const text_width = try visibleWidth(gpa, text);
        if (@as(f64, @floatFromInt(text_width)) <= maximum) {
            try result.appendSlice(gpa, text);
            if (pad) try padding(gpa, &result, maximum, text_width);
            return result.toOwnedSlice(gpa);
        }
        const clipped = try fragmentAlloc(gpa, ellipsis, maximum);
        defer gpa.free(clipped.text);
        if (clipped.width == 0) {
            if (pad) try padding(gpa, &result, maximum, 0);
            return result.toOwnedSlice(gpa);
        }
        return finalize(gpa, &result, 0, clipped.text, clipped.width, maximum, pad);
    }
    const target = maximum - @as(f64, @floatFromInt(ellipsis_width));
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
            if (contiguous and @as(f64, @floatFromInt(kept + width)) <= target) {
                try result.appendSlice(gpa, pending.items);
                pending.clearRetainingCapacity();
                try result.appendSlice(gpa, cluster);
                kept += width;
            } else {
                contiguous = false;
                pending.clearRetainingCapacity();
            }
            total += width;
            if (@as(f64, @floatFromInt(total)) > maximum) {
                return finalize(gpa, &result, kept, ellipsis, ellipsis_width, maximum, pad);
            }
        }
        at = text_end;
    }
    result.clearRetainingCapacity();
    try result.appendSlice(gpa, text);
    if (pad) try padding(gpa, &result, maximum, total);
    return result.toOwnedSlice(gpa);
}
fn fixtureUnits(gpa: std.mem.Allocator, value: std.json.Value) ![]u16 {
    const units = try gpa.alloc(u16, value.array.items.len);
    for (units, value.array.items) |*unit, item| unit.* = @intCast(item.integer);
    return units;
}
test "Source6fb public SelectList shared truncation preserves original Unicode ANSI ellipses fractions and padding" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/terminal-layout-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("truncation").?.array.items, 0..) |entry, index| {
        const text = try fixtureUnits(gpa, entry.object.get("text").?);
        defer gpa.free(text);
        const ellipsis = try fixtureUnits(gpa, entry.object.get("ellipsis").?);
        defer gpa.free(ellipsis);
        const maximum = entry.object.get("width").?;
        const width: f64 = if (maximum == .integer) @floatFromInt(maximum.integer) else maximum.float;
        const actual = try truncateOptionsAlloc(gpa, text, width, ellipsis, entry.object.get("pad").?.bool);
        defer gpa.free(actual);
        const expected = try fixtureUnits(gpa, entry.object.get("result").?);
        defer gpa.free(expected);
        std.testing.expectEqualSlices(u16, expected, actual) catch |err| {
            std.debug.print("Source truncation case {d}, width {d}\n", .{ index, width });
            return err;
        };
    }
}
