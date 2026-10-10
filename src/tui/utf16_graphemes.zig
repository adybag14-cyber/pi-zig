//! Unicode 17 extended grapheme boundaries in JavaScript UTF16 code units.
//! UAX #29 revision 47, GB1..GB999. Isolated surrogates remain single units.
//! No terminal escape handling: segmentation sees the original string.
const std = @import("std");
const data = @import("unicode17/generated_graphemes.zig");
pub const Segment = struct { start: usize, end: usize };
pub const Scalar = struct { value: u21, end: usize };
pub fn scalar(text: []const u16, start: usize) Scalar {
    const first = text[start];
    if (std.unicode.utf16IsHighSurrogate(first) and start + 1 < text.len and std.unicode.utf16IsLowSurrogate(text[start + 1])) {
        return .{ .value = std.unicode.utf16DecodeSurrogatePair(text[start..][0..2]) catch unreachable, .end = start + 2 };
    }
    return .{ .value = first, .end = start + 1 };
}
fn property(comptime T: type, ranges: []const data.Range(T), cp: u21, default: T) T {
    var low: usize = 0;
    var high = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        if (cp < ranges[middle].first) high = middle else if (cp > ranges[middle].last) low = middle + 1 else return ranges[middle].property;
    }
    return default;
}
fn control(value: data.Grapheme) bool {
    return value == .Control or value == .CR or value == .LF;
}
pub const Iterator = struct {
    text: []const u16,
    offset: usize = 0,
    pub fn next(self: *Iterator) ?Segment {
        if (self.offset >= self.text.len) return null;
        const start = self.offset;
        const first = scalar(self.text, start);
        var prior = property(data.Grapheme, &data.grapheme, first.value, .Other);
        var regional: usize = if (prior == .Regional_Indicator) 1 else 0;
        var pictographic_chain = property(bool, &data.pictographic, first.value, false);
        var zwj_after_pictographic = false;
        const IndicState = enum { none, consonant, linked };
        var indic: IndicState = if (property(data.Indic, &data.indic, first.value, .None) == .Consonant) .consonant else .none;
        var end = first.end;
        while (end < self.text.len) {
            const current = scalar(self.text, end);
            const gcb = property(data.Grapheme, &data.grapheme, current.value, .Other);
            const incb = property(data.Indic, &data.indic, current.value, .None);
            const ep = property(bool, &data.pictographic, current.value, false);
            const join = if (prior == .CR and gcb == .LF) true // GB3
                else if (control(prior) or control(gcb)) false // GB4/GB5
                else if (prior == .L and (gcb == .L or gcb == .V or gcb == .LV or gcb == .LVT)) true // GB6
                else if ((prior == .LV or prior == .V) and (gcb == .V or gcb == .T)) true // GB7
                else if ((prior == .LVT or prior == .T) and gcb == .T) true // GB8
                else if (gcb == .Extend or gcb == .ZWJ or gcb == .SpacingMark or prior == .Prepend) true // GB9/9a/9b
                else if (incb == .Consonant and indic == .linked) true // GB9c
                else if (prior == .ZWJ and zwj_after_pictographic and ep) true // GB11
                else if (prior == .Regional_Indicator and gcb == .Regional_Indicator and regional % 2 == 1) true // GB12/13
                else false; // GB999
            if (!join) break;
            regional = if (gcb == .Regional_Indicator) regional + 1 else 0;
            zwj_after_pictographic = gcb == .ZWJ and pictographic_chain;
            pictographic_chain = ep or (gcb == .Extend and pictographic_chain);
            indic = switch (incb) {
                .Consonant => .consonant,
                .Extend => indic,
                .Linker => if (indic == .none) .none else .linked,
                .None => .none,
            };
            prior = gcb;
            end = current.end;
        }
        self.offset = end;
        return .{ .start = start, .end = end };
    }
};
/// Source Input segments the prefix independently, including a split surrogate.
pub fn previous(text: []const u16, cursor: usize) usize {
    var iterator: Iterator = .{ .text = text[0..@min(cursor, text.len)] };
    var result: usize = 0;
    while (iterator.next()) |segment| result = segment.start;
    return result;
}
/// Source Input segments the suffix independently, including a split surrogate.
pub fn next(text: []const u16, cursor: usize) usize {
    const start = @min(cursor, text.len);
    var iterator: Iterator = .{ .text = text[start..] };
    return start + if (iterator.next()) |segment| segment.end else 0;
}
fn appendScalar(list: *std.ArrayList(u16), gpa: std.mem.Allocator, cp: u21) !void {
    if (cp <= 0xffff) try list.append(gpa, @intCast(cp)) else {
        const value = cp - 0x10000;
        try list.appendSlice(gpa, &.{ @as(u16, @intCast(0xd800 + (value >> 10))), @as(u16, @intCast(0xdc00 + (value & 0x3ff))) });
    }
}
test "Unicode17 extended grapheme conformance uses exact UTF16 boundaries" {
    const gpa = std.testing.allocator;
    var lines = std.mem.splitScalar(u8, @embedFile("unicode17/GraphemeBreakTest.txt"), '\n');
    var cases: usize = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw[0 .. std.mem.indexOfScalar(u8, raw, '#') orelse raw.len], " \t\r");
        if (line.len == 0) continue;
        var text: std.ArrayList(u16) = .empty;
        defer text.deinit(gpa);
        var wanted: std.ArrayList(usize) = .empty;
        defer wanted.deinit(gpa);
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |token| {
            if (std.mem.eql(u8, token, "÷")) try wanted.append(gpa, text.items.len) else if (!std.mem.eql(u8, token, "×")) try appendScalar(&text, gpa, try std.fmt.parseInt(u21, token, 16));
        }
        var actual: std.ArrayList(usize) = .empty;
        defer actual.deinit(gpa);
        try actual.append(gpa, 0);
        var iterator: Iterator = .{ .text = text.items };
        while (iterator.next()) |segment| try actual.append(gpa, segment.end);
        std.testing.expectEqualSlices(usize, wanted.items, actual.items) catch |err| {
            std.debug.print("Grapheme conformance failed: {s}\n", .{line});
            return err;
        };
        cases += 1;
    }
    try std.testing.expect(cases > 700);
}
test "Source UTF16 cursor prefix suffix and isolated surrogate boundaries" {
    const text = [_]u16{ 'a', 0xd83d, 0xde00, 0x0301, 'z' };
    try std.testing.expectEqual(@as(usize, 1), previous(&text, 4));
    try std.testing.expectEqual(@as(usize, 1), previous(&text, 2));
    try std.testing.expectEqual(@as(usize, 4), next(&text, 2));
    try std.testing.expectEqual(@as(usize, 4), next(&text, 1));
}
