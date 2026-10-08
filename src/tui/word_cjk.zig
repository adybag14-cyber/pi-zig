//! ICU78 CJK dictionary-cost segmentation and NFKC offset restoration in Zig.
//! © 2016 and later Unicode, Inc.; Copyright (C) 2006-2016 IBM and others.
//! License and original dictionary notices are retained in icu78/LICENSE.txt.
const std = @import("std");
const dictionaries = @import("word_dictionary.zig");
const normalization = @import("word_normalization.zig");
const graphemes = @import("utf16_graphemes.zig");
const properties = @import("utf16_words.zig");
const Point = struct { value: u21, offset: usize };
pub fn handles(cp: u21) bool {
    const script = properties.traits(cp) & 15;
    return script == 1 or script == 2 or script == 3 or cp == 0x30fc or cp == 0xff70 or cp == 0xff9e or cp == 0xff9f;
}
fn katakana(cp: u21) bool {
    return (cp >= 0x30a1 and cp <= 0x30fe and cp != 0x30fb) or (cp >= 0xff66 and cp <= 0xff9f);
}
fn katakanaCost(length: usize) u32 {
    const values = [_]u32{ 8192, 984, 408, 240, 204, 252, 300, 372, 480 };
    return if (length < values.len) values[length] else 8192;
}
pub fn breaksAlloc(gpa: std.mem.Allocator, text: []const u16, start: usize, end: usize) ![]usize {
    var normalized = try normalization.normalizeMappedAlloc(gpa, text[start..end]);
    defer normalized.deinit();
    var points: std.ArrayList(Point) = .empty;
    defer points.deinit(gpa);
    var at: usize = 0;
    while (at < normalized.text.len) {
        const cp = graphemes.scalar(normalized.text, at);
        try points.append(gpa, .{ .value = cp.value, .offset = at });
        at = cp.end;
    }
    const count = points.items.len;
    if (count == 0) return gpa.dupe(usize, &.{});
    const best = try gpa.alloc(u32, count + 1);
    defer gpa.free(best);
    @memset(best, std.math.maxInt(u32));
    best[0] = 0;
    const previous = try gpa.alloc(usize, count + 1);
    defer gpa.free(previous);
    @memset(previous, std.math.maxInt(usize));
    var previous_katakana = false;
    const dict = dictionaries.cjk();
    for (points.items, 0..) |cp, index| {
        if (best[index] == std.math.maxInt(u32)) continue;
        var matches: [21]dictionaries.Match = undefined;
        var found = dict.matches(normalized.text[cp.offset..], 20, matches[0..20]).count;
        if ((found == 0 or matches[0].codepoints != 1) and !(cp.value >= 0xac00 and cp.value <= 0xd7a3)) {
            matches[found] = .{ .units = graphemes.scalar(normalized.text, cp.offset).end - cp.offset, .codepoints = 1, .value = 255 };
            found += 1;
        }
        for (matches[0..found]) |candidate| {
            const limit = index + candidate.codepoints;
            const cost = best[index] +% candidate.value;
            if (cost < best[limit]) {
                best[limit] = cost;
                previous[limit] = index;
            }
        }
        const is_katakana = katakana(cp.value);
        if (!previous_katakana and is_katakana) {
            var length: usize = 1;
            while (index + length < count and length < 20 and katakana(points.items[index + length].value)) : (length += 1) {}
            if (length < 20) {
                const cost = best[index] +% katakanaCost(length);
                if (cost < best[index + length]) {
                    best[index + length] = cost;
                    previous[index + length] = index;
                }
            }
        }
        previous_katakana = is_katakana;
    }
    if (best[count] == std.math.maxInt(u32)) return gpa.dupe(usize, &.{});
    var reverse: std.ArrayList(usize) = .empty;
    defer reverse.deinit(gpa);
    var index = count;
    while (index > 0) {
        if (index != count) try reverse.append(gpa, start + normalized.original[points.items[index].offset]);
        index = previous[index];
        if (index == std.math.maxInt(usize)) return error.InvalidCjkPath;
    }
    var result: std.ArrayList(usize) = .empty;
    errdefer result.deinit(gpa);
    for (0..reverse.items.len) |offset| {
        const value = reverse.items[reverse.items.len - offset - 1];
        if (value > start and value < end and (result.items.len == 0 or value > result.items[result.items.len - 1])) try result.append(gpa, value);
    }
    return result.toOwnedSlice(gpa);
}
test "actual Source ICU78 CJK dictionary costs and normalization offsets match full-script corpus" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-navigation-original-6fb.json"), .{});
    defer fixture.deinit();
    var tested: usize = 0;
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const raw = item.object.get("units").?.array.items;
        if (raw.len == 0) continue;
        const text = try gpa.alloc(u16, raw.len);
        defer gpa.free(text);
        for (text, raw) |*unit, value| unit.* = @intCast(value.integer);
        var valid = true;
        var at: usize = 0;
        while (at < text.len) {
            const cp = graphemes.scalar(text, at);
            if (!handles(cp.value)) {
                valid = false;
                break;
            }
            at = cp.end;
        }
        if (!valid) continue;
        const actual = try breaksAlloc(gpa, text, 0, text.len);
        defer gpa.free(actual);
        const wanted = item.object.get("segments").?.array.items;
        errdefer std.debug.print("CJK Source mismatch {any}; actual {any}\n", .{ text, actual });
        try std.testing.expectEqual(wanted.len - 1, actual.len);
        for (wanted[1..], actual) |expected, boundary| try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("start").?.integer)), boundary);
        tested += 1;
    }
    try std.testing.expect(tested > 15);
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const text = try std.unicode.utf8ToUtf16LeAlloc(gpa, "ｶﾞｯﾂﾎﾟｰｽﾞ東京都中文测试");
    defer gpa.free(text);
    const result = try breaksAlloc(gpa, text, 0, text.len);
    defer gpa.free(result);
}
test "native CJK refinement failure paths free normalization costs paths and boundaries" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
