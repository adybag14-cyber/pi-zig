//! Unicode17/Source ICU78.2 word segmentation in original UTF16 offsets.
//! The selected runtime profile uses pinned dictionary refinements. Unhandled
//! scripts preserve ICU rule spans rather than inventing scalar word runs.
const std = @import("std");
const data = @import("icu78/generated_words.zig");
const grapheme_data = @import("unicode17/generated_graphemes.zig");
const graphemes = @import("utf16_graphemes.zig");
const input = @import("utf16_input.zig");
pub const Mode = enum { unicode, icu };
pub const Segment = struct { start: usize, end: usize, word: bool, dictionary: bool = false };
const Node = struct { cp: u21, start: usize, end: usize, raw: data.Word, word: data.Word, flags: u8, cjk: bool, hangul: bool, pictographic: bool };
pub fn wordProperty(cp: u21) data.Word {
    var low: usize = 0;
    var high = data.words.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = data.words[mid];
        if (cp < range.first) high = mid else if (cp > range.last) low = mid + 1 else return range.property;
    }
    return .Other;
}
pub fn traits(cp: u21) u8 {
    var low: usize = 0;
    var high = data.traits.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = data.traits[mid];
        if (cp < range.first) high = mid else if (cp > range.last) low = mid + 1 else return range.flags;
    }
    return 0;
}
fn graphemeProperty(cp: u21) grapheme_data.Grapheme {
    var low: usize = 0;
    var high = grapheme_data.grapheme.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = grapheme_data.grapheme[mid];
        if (cp < range.first) high = mid else if (cp > range.last) low = mid + 1 else return range.property;
    }
    return .Other;
}
fn pictographic(cp: u21) bool {
    var low: usize = 0;
    var high = grapheme_data.pictographic.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = grapheme_data.pictographic[mid];
        if (cp < range.first) high = mid else if (cp > range.last) low = mid + 1 else return true;
    }
    return false;
}
fn node(cp: graphemes.Scalar, start: usize, mode: Mode) Node {
    const raw = wordProperty(cp.value);
    const flags = traits(cp.value);
    const script: data.Script = @enumFromInt(flags & 15);
    const cjk = script == .han or script == .hiragana or raw == .Katakana;
    const hangul = cp.value >= 0xac00 and cp.value <= 0xd7a3;
    var effective = raw;
    if (mode == .icu) {
        if ((raw == .ALetter and (cjk or hangul)) or (raw == .Extend and script == .han)) effective = .Other;
        if (flags & 16 != 0 and effective != .Extend and graphemeProperty(cp.value) != .Control) effective = .ALetter;
    }
    return .{ .cp = cp.value, .start = start, .end = cp.end, .raw = raw, .word = effective, .flags = flags, .cjk = mode == .icu and cjk, .hangul = mode == .icu and hangul, .pictographic = pictographic(cp.value) };
}
fn ignored(value: data.Word) bool {
    return value == .Extend or value == .Format or value == .ZWJ;
}
fn newline(value: data.Word) bool {
    return value == .CR or value == .LF or value == .Newline;
}
fn ah(value: data.Word) bool {
    return value == .ALetter or value == .Hebrew_Letter;
}
fn midLetter(value: data.Word) bool {
    return value == .MidLetter or value == .MidNumLet or value == .Single_Quote;
}
fn midNumeric(value: data.Word) bool {
    return value == .MidNum or value == .MidNumLet or value == .Single_Quote;
}
fn previousSignificant(nodes: []const Node, before: usize) ?usize {
    var index = before;
    while (index > 0) {
        index -= 1;
        if (!ignored(nodes[index].word)) return index;
    }
    return null;
}
fn nextSignificant(nodes: []const Node, from: usize) ?usize {
    var index = from;
    while (index < nodes.len) : (index += 1) if (!ignored(nodes[index].word)) return index;
    return null;
}
fn joins(nodes: []const Node, at: usize, mode: Mode) bool {
    const raw_left = nodes[at - 1];
    const right = nodes[at];
    if (raw_left.word == .CR and right.word == .LF) return true; // WB3
    if (newline(raw_left.word) or newline(right.word)) return false; // WB3a/b
    if (raw_left.word == .ZWJ and right.pictographic) return true; // WB3c
    if (raw_left.word == .WSegSpace and right.word == .WSegSpace) return true; // WB3d
    if (ignored(right.word)) return true; // WB4
    const left_index = previousSignificant(nodes, at) orelse return false;
    const left = nodes[left_index];
    if (newline(left.word)) return false;
    if (mode == .icu and left_index + 1 == at and ((left.cjk and right.cjk) or (left.hangul and right.hangul))) return true;
    if (ah(left.word) and ah(right.word)) return true; // WB5
    if (ah(left.word) and midLetter(right.word)) if (nextSignificant(nodes, at + 1)) |after| {
        if (ah(nodes[after].word)) return true;
    }; // WB6
    if (midLetter(left.word) and ah(right.word)) if (previousSignificant(nodes, left_index)) |before| {
        if (ah(nodes[before].word)) return true;
    }; // WB7
    if (left.word == .Hebrew_Letter and right.word == .Single_Quote) return true; // WB7a
    if (left.word == .Hebrew_Letter and right.word == .Double_Quote) if (nextSignificant(nodes, at + 1)) |after| {
        if (nodes[after].word == .Hebrew_Letter) return true;
    }; // WB7b
    if (left.word == .Double_Quote and right.word == .Hebrew_Letter) if (previousSignificant(nodes, left_index)) |before| {
        if (nodes[before].word == .Hebrew_Letter) return true;
    }; // WB7c
    if (left.word == .Numeric and right.word == .Numeric) return true; // WB8
    if ((ah(left.word) and right.word == .Numeric) or (left.word == .Numeric and ah(right.word))) return true; // WB9/10
    if (left.word == .Numeric and midNumeric(right.word)) if (nextSignificant(nodes, at + 1)) |after| {
        if (nodes[after].word == .Numeric) return true;
    }; // WB11
    if (midNumeric(left.word) and right.word == .Numeric) if (previousSignificant(nodes, left_index)) |before| {
        if (nodes[before].word == .Numeric) return true;
    }; // WB12
    if (left.word == .Katakana and right.word == .Katakana) return true; // WB13
    if ((ah(left.word) or left.word == .Numeric or left.word == .Katakana or left.word == .ExtendNumLet) and right.word == .ExtendNumLet) return true; // WB13a
    if (left.word == .ExtendNumLet and (ah(right.word) or right.word == .Numeric or right.word == .Katakana)) return true; // WB13b
    if (left.word == .Regional_Indicator and right.word == .Regional_Indicator) {
        var regional: usize = 0;
        var before: ?usize = left_index;
        while (before) |index| {
            if (nodes[index].word != .Regional_Indicator) break;
            regional += 1;
            before = previousSignificant(nodes, index);
        }
        return regional % 2 == 1; // WB15/16
    }
    return false; // WB999
}
fn segment(nodes: []const Node) Segment {
    var word = false;
    var dictionary = false;
    var extend_num: usize = 0;
    for (nodes, 0..) |item, index| {
        word = word or item.flags & 64 != 0;
        dictionary = dictionary or item.cjk or item.hangul or item.flags & 16 != 0;
        if (item.word == .ExtendNumLet) extend_num += 1;
        if (index > 0 and item.cjk and nodes[index - 1].cjk) word = true;
    }
    return .{ .start = nodes[0].start, .end = nodes[nodes.len - 1].end, .word = word or extend_num >= 2, .dictionary = dictionary };
}
pub fn ruleSegmentsAlloc(gpa: std.mem.Allocator, text: []const u16, mode: Mode) ![]Segment {
    var nodes: std.ArrayList(Node) = .empty;
    defer nodes.deinit(gpa);
    var at: usize = 0;
    while (at < text.len) {
        const cp = graphemes.scalar(text, at);
        try nodes.append(gpa, node(cp, at, mode));
        at = cp.end;
    }
    var result: std.ArrayList(Segment) = .empty;
    errdefer result.deinit(gpa);
    if (nodes.items.len != 0) {
        var first: usize = 0;
        for (1..nodes.items.len) |index| if (!joins(nodes.items, index, mode)) {
            try result.append(gpa, segment(nodes.items[first..index]));
            first = index;
        };
        try result.append(gpa, segment(nodes.items[first..]));
    }
    return result.toOwnedSlice(gpa);
}
pub fn segmentsAlloc(gpa: std.mem.Allocator, text: []const u16) ![]Segment {
    const rules = try ruleSegmentsAlloc(gpa, text, .icu);
    defer gpa.free(rules);
    return @import("word_languages.zig").refineAlloc(gpa, text, rules);
}
fn sliceIndex(length: usize, value: i64) usize {
    const count: i64 = @intCast(length);
    return @intCast(if (value < 0) @max(0, count + value) else @min(count, value));
}
fn whitespace(text: []const u16) bool {
    for (text) |unit| if (input.State.whitespace(unit)) return true;
    return false;
}
fn punctuation(unit: u16) bool {
    return unit < 0x80 and std.mem.indexOfScalar(u8, "(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`", @intCast(unit)) != null;
}
pub fn findBackwardAlloc(gpa: std.mem.Allocator, text: []const u16, cursor: i64) !i64 {
    if (cursor <= 0) return 0;
    const prefix = text[0..sliceIndex(text.len, cursor)];
    const segments = try segmentsAlloc(gpa, prefix);
    defer gpa.free(segments);
    var count = segments.len;
    var result = cursor;
    while (count > 0 and whitespace(prefix[segments[count - 1].start..segments[count - 1].end])) {
        count -= 1;
        result -= @intCast(segments[count].end - segments[count].start);
    }
    if (count == 0) return result;
    const last = segments[count - 1];
    if (last.word) {
        const part = prefix[last.start..last.end];
        var boundary: usize = 0;
        for (part, 0..) |unit, index| if (punctuation(unit)) {
            boundary = index + 1;
        };
        result -= @intCast(part.len - boundary);
    } else {
        while (count > 0 and !segments[count - 1].word and !whitespace(prefix[segments[count - 1].start..segments[count - 1].end])) {
            count -= 1;
            result -= @intCast(segments[count].end - segments[count].start);
        }
    }
    return result;
}
pub fn findForwardAlloc(gpa: std.mem.Allocator, text: []const u16, cursor: i64) !i64 {
    if (cursor >= text.len) return @intCast(text.len);
    const suffix = text[sliceIndex(text.len, cursor)..];
    const segments = try segmentsAlloc(gpa, suffix);
    defer gpa.free(segments);
    var index: usize = 0;
    var result = cursor;
    while (index < segments.len and whitespace(suffix[segments[index].start..segments[index].end])) : (index += 1) result += @intCast(segments[index].end - segments[index].start);
    if (index == segments.len) return result;
    const first = segments[index];
    if (first.word) {
        const part = suffix[first.start..first.end];
        var boundary = part.len;
        for (part, 0..) |unit, offset| if (punctuation(unit)) {
            boundary = offset;
            break;
        };
        result += @intCast(boundary);
    } else {
        while (index < segments.len and !segments[index].word and !whitespace(suffix[segments[index].start..segments[index].end])) : (index += 1) result += @intCast(segments[index].end - segments[index].start);
    }
    return result;
}
test "Unicode17 default word-boundary conformance preserves UTF16 positions" {
    const gpa = std.testing.allocator;
    var lines = std.mem.splitScalar(u8, @embedFile("unicode17/WordBreakTest.txt"), '\n');
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
            if (std.mem.eql(u8, token, "÷")) try wanted.append(gpa, text.items.len) else if (!std.mem.eql(u8, token, "×")) {
                const cp = try std.fmt.parseInt(u21, token, 16);
                if (cp <= 0xffff) try text.append(gpa, @intCast(cp)) else try text.appendSlice(gpa, &.{ @as(u16, @intCast(0xd800 + ((cp - 0x10000) >> 10))), @as(u16, @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff))) });
            }
        }
        const actual = try ruleSegmentsAlloc(gpa, text.items, .unicode);
        defer gpa.free(actual);
        var boundaries: std.ArrayList(usize) = .empty;
        defer boundaries.deinit(gpa);
        try boundaries.append(gpa, 0);
        for (actual) |item| try boundaries.append(gpa, item.end);
        std.testing.expectEqualSlices(usize, wanted.items, boundaries.items) catch |err| {
            std.debug.print("Word conformance mismatch {s}\n", .{line});
            return err;
        };
        cases += 1;
    }
    try std.testing.expect(cases > 1900);
}
test "actual Source6fb non-dictionary word rules tags and signed navigation positions" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-navigation-original-6fb.json"), .{});
    defer fixture.deinit();
    var tested: usize = 0;
    var language_cases: usize = 0;
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const raw = item.object.get("units").?.array.items;
        const text = try gpa.alloc(u16, raw.len);
        defer gpa.free(text);
        for (text, raw) |*unit, value| unit.* = @intCast(value.integer);
        const rules = try ruleSegmentsAlloc(gpa, text, .icu);
        defer gpa.free(rules);
        var needs_language = false;
        for (rules) |part| needs_language = needs_language or part.dictionary;
        if (needs_language) {
            language_cases += 1;
            continue;
        }
        errdefer std.debug.print("Source non-dictionary mismatch {any}\n", .{text});
        const wanted = item.object.get("segments").?.array.items;
        try std.testing.expectEqual(wanted.len, rules.len);
        for (wanted, rules) |expected, actual| {
            try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("start").?.integer)), actual.start);
            try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("end").?.integer)), actual.end);
            try std.testing.expectEqual(expected.object.get("word").?.bool, actual.word);
        }
        for (item.object.get("navigation").?.array.items) |position| {
            const cursor = position.object.get("cursor").?.integer;
            try std.testing.expectEqual(position.object.get("backward").?.integer, try findBackwardAlloc(gpa, text, cursor));
            try std.testing.expectEqual(position.object.get("forward").?.integer, try findForwardAlloc(gpa, text, cursor));
        }
        tested += 1;
    }
    try std.testing.expect(tested > 50 and language_cases > 50);
}
test "actual Source6fb complete default word corpus scripts tags and every signed cursor position" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-navigation-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items, 0..) |item, case_index| {
        const raw = item.object.get("units").?.array.items;
        const text = try gpa.alloc(u16, raw.len);
        defer gpa.free(text);
        for (text, raw) |*unit, value| unit.* = @intCast(value.integer);
        const actual = try segmentsAlloc(gpa, text);
        defer gpa.free(actual);
        const wanted = item.object.get("segments").?.array.items;
        errdefer std.debug.print("Source full word mismatch case {d}: {any}; actual {any}\n", .{ case_index, text, actual });
        try std.testing.expectEqual(wanted.len, actual.len);
        for (wanted, actual) |expected, part| {
            try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("start").?.integer)), part.start);
            try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("end").?.integer)), part.end);
            try std.testing.expectEqual(expected.object.get("word").?.bool, part.word);
        }
        for (item.object.get("navigation").?.array.items) |position| {
            const cursor = position.object.get("cursor").?.integer;
            errdefer std.debug.print("Navigation cursor {d}\n", .{cursor});
            try std.testing.expectEqual(position.object.get("backward").?.integer, try findBackwardAlloc(gpa, text, cursor));
            try std.testing.expectEqual(position.object.get("forward").?.integer, try findForwardAlloc(gpa, text, cursor));
        }
    }
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const text = try std.unicode.utf8ToUtf16LeAlloc(gpa, "中文测试 ภาษาไทยภาษาอังกฤษ ພາສາລາວ ភាសាខ្មែរ မြန်မာဘာသာ");
    defer gpa.free(text);
    const segments = try segmentsAlloc(gpa, text);
    defer gpa.free(segments);
    _ = try findBackwardAlloc(gpa, text, @as(i64, @intCast(text.len)));
    _ = try findForwardAlloc(gpa, text, -2);
}
test "native complete word segmentation navigation and all language failure paths release every allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
