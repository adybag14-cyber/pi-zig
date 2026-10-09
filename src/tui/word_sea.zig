//! Zig port of ICU78.2 Southeast Asian dictionary lookahead and resynchronization.
//! © 2016 and later Unicode, Inc.; Copyright (C) 2006-2016 IBM and others.
//! License and original dictionary notices are retained in icu78/LICENSE.txt.
const std = @import("std");
const dictionaries = @import("word_dictionary.zig");
const properties = @import("utf16_words.zig");
const width_data = @import("unicode17/generated_width.zig");
const graphemes = @import("utf16_graphemes.zig");
pub const Language = enum(u4) { thai = 5, myanmar = 6, lao = 7, khmer = 8 };
pub fn handles(language: Language, cp: u21) bool {
    const flags = properties.traits(cp);
    return flags & 15 == @intFromEnum(language) and flags & 16 != 0;
}
fn beginWord(language: Language, cp: u21) bool {
    return switch (language) {
        .thai => (cp >= 0xe01 and cp <= 0xe2e) or (cp >= 0xe40 and cp <= 0xe44),
        .myanmar => cp >= 0x1000 and cp <= 0x102a,
        .lao => (cp >= 0xe81 and cp <= 0xeae) or (cp >= 0xedc and cp <= 0xedd) or (cp >= 0xec0 and cp <= 0xec4),
        .khmer => cp >= 0x1780 and cp <= 0x17b3,
    };
}
fn endWord(language: Language, cp: u21) bool {
    if (!handles(language, cp)) return false;
    return switch (language) {
        .thai => cp != 0xe31 and !(cp >= 0xe40 and cp <= 0xe44),
        .lao => !(cp >= 0xec0 and cp <= 0xec4),
        .khmer => cp != 0x17d2,
        .myanmar => true,
    };
}
fn mark(language: Language, cp: u21) bool {
    if (cp == 0x20) return true;
    if (!handles(language, cp)) return false;
    var low: usize = 0;
    var high = width_data.properties.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const range = width_data.properties[mid];
        if (cp < range.first) high = mid else if (cp > range.last) low = mid + 1 else return range.flags & 1 != 0;
    }
    return false;
}
fn suffix(cp: u21) bool {
    return cp == 0xe2f or cp == 0xe46;
}
fn previousScalar(text: []const u16, at: usize) usize {
    if (at == 0) return 0;
    if (at >= 2 and std.unicode.utf16IsLowSurrogate(text[at - 1]) and std.unicode.utf16IsHighSurrogate(text[at - 2])) return at - 2;
    return at - 1;
}
const Possible = struct {
    values: [20]dictionaries.Match = undefined,
    offset: ?usize = null,
    count: usize = 0,
    prefix: usize = 0,
    current: usize = 0,
    marked: usize = 0,
    fn candidates(self: *Possible, text: []const u16, position: *usize, end: usize, dict: dictionaries.Dictionary) usize {
        const start = position.*;
        if (self.offset == null or self.offset.? != start) {
            self.offset = start;
            const found = dict.matches(text[start..end], end - start, &self.values);
            self.count = found.count;
            self.prefix = found.prefix;
        }
        if (self.count != 0) position.* = start + self.values[self.count - 1].units;
        self.current = self.count -| 1;
        self.marked = self.current;
        return self.count;
    }
    fn accept(self: *Possible, position: *usize) dictionaries.Match {
        const value = self.values[self.marked];
        position.* = self.offset.? + value.units;
        return value;
    }
    fn backup(self: *Possible, position: *usize) bool {
        if (self.current == 0) return false;
        self.current -= 1;
        position.* = self.offset.? + self.values[self.current].units;
        return true;
    }
};
pub fn breaksAlloc(gpa: std.mem.Allocator, text: []const u16, start: usize, end: usize, language: Language) ![]usize {
    if ((language == .thai and end - start <= 4) or (language != .thai and end - start < 4)) return gpa.dupe(usize, &.{});
    const dict = switch (language) {
        .thai => dictionaries.thai(),
        .myanmar => dictionaries.myanmar(),
        .lao => dictionaries.lao(),
        .khmer => dictionaries.khmer(),
    };
    var possible = [_]Possible{ .{}, .{}, .{} };
    var words_found: usize = 0;
    var position = start;
    var result: std.ArrayList(usize) = .empty;
    errdefer result.deinit(gpa);
    while (position < end) {
        const current = position;
        var length: usize = 0;
        var cp_length: usize = 0;
        const first = words_found % 3;
        const second = (words_found + 1) % 3;
        const third = (words_found + 2) % 3;
        const candidates = possible[first].candidates(text, &position, end, dict);
        if (candidates == 1) {
            const accepted = possible[first].accept(&position);
            length = accepted.units;
            cp_length = accepted.codepoints;
            words_found += 1;
        } else if (candidates > 1) {
            best: {
                if (position >= end) break :best;
                while (true) {
                    if (possible[second].candidates(text, &position, end, dict) > 0) {
                        possible[first].marked = possible[first].current;
                        if (position >= end) break :best;
                        while (true) {
                            if (possible[third].candidates(text, &position, end, dict) > 0) {
                                possible[first].marked = possible[first].current;
                                break :best;
                            }
                            if (!possible[second].backup(&position)) break;
                        }
                    }
                    if (!possible[first].backup(&position)) break;
                }
            }
            const accepted = possible[first].accept(&position);
            length = accepted.units;
            cp_length = accepted.codepoints;
            words_found += 1;
        }
        if (position < end and cp_length < 3) {
            const next = words_found % 3;
            if (possible[next].candidates(text, &position, end, dict) == 0 and (length == 0 or possible[next].prefix < 3)) {
                var remaining = end - (current + length);
                var consumed: usize = 0;
                while (true) {
                    const prior = position;
                    const cp = graphemes.scalar(text, position);
                    position = cp.end;
                    consumed += position - prior;
                    remaining -= position - prior;
                    if (remaining == 0) break;
                    const next_cp = graphemes.scalar(text, position).value;
                    if (endWord(language, cp.value) and beginWord(language, next_cp)) {
                        const found = possible[(words_found + 1) % 3].candidates(text, &position, end, dict);
                        position = current + length + consumed;
                        if (found > 0) break;
                    }
                }
                if (length == 0) words_found += 1;
                length += consumed;
            } else position = current + length;
        }
        while (position < end and mark(language, graphemes.scalar(text, position).value)) {
            const prior = position;
            position = graphemes.scalar(text, position).end;
            length += position - prior;
        }
        if (language == .thai and position < end and length > 0) {
            if (possible[words_found % 3].candidates(text, &position, end, dict) == 0 and suffix(graphemes.scalar(text, position).value)) {
                var cp = graphemes.scalar(text, position).value;
                if (cp == 0xe2f) {
                    const prior = previousScalar(text, position);
                    if (!suffix(graphemes.scalar(text, prior).value)) {
                        const end_suffix = graphemes.scalar(text, position).end;
                        length += end_suffix - position;
                        position = end_suffix;
                        cp = if (position < end) graphemes.scalar(text, position).value else 0;
                    }
                }
                if (cp == 0xe46) {
                    const prior = previousScalar(text, position);
                    if (graphemes.scalar(text, prior).value != 0xe46) {
                        const end_suffix = graphemes.scalar(text, position).end;
                        length += end_suffix - position;
                        position = end_suffix;
                    }
                }
            } else position = current + length;
        }
        if (length != 0) try result.append(gpa, current + length);
        if (position <= current) return error.WordDictionaryDidNotAdvance;
    }
    if (result.items.len != 0 and result.items[result.items.len - 1] >= end) _ = result.pop();
    return result.toOwnedSlice(gpa);
}
test "actual Source ICU78 Thai Lao Khmer and Burmese dictionary corpus matches full-script words" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-navigation-original-6fb.json"), .{});
    defer fixture.deinit();
    var counts = [_]usize{ 0, 0, 0, 0 };
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const raw = item.object.get("units").?.array.items;
        if (raw.len == 0) continue;
        const text = try gpa.alloc(u16, raw.len);
        defer gpa.free(text);
        for (text, raw) |*unit, value| unit.* = @intCast(value.integer);
        const script = properties.traits(text[0]) & 15;
        if (script < 5 or script > 8) continue;
        const language: Language = @enumFromInt(script);
        var valid = true;
        for (text) |unit| if (!handles(language, unit)) {
            valid = false;
            break;
        };
        if (!valid) continue;
        const wanted = item.object.get("segments").?.array.items;
        // Source's leading Extend rule forms a separate non-word span. The
        // engine-only test must not bypass that RBBI boundary; the complete
        // pipeline corpus above tests all such leading-mark cases unchanged.
        if (wanted.len != 0 and !wanted[0].object.get("word").?.bool) continue;
        const actual = try breaksAlloc(gpa, text, 0, text.len, language);
        defer gpa.free(actual);
        errdefer std.debug.print("SEA Source mismatch {any}; actual {any}\n", .{ text, actual });
        try std.testing.expectEqual(wanted.len - 1, actual.len);
        for (wanted[1..], actual) |expected, boundary| try std.testing.expectEqual(@as(usize, @intCast(expected.object.get("start").?.integer)), boundary);
        counts[script - 5] += 1;
    }
    for (counts) |count| try std.testing.expect(count >= 5);
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const text = try std.unicode.utf8ToUtf16LeAlloc(gpa, "การทดสอบการแบ่งคำภาษาไทย");
    defer gpa.free(text);
    const result = try breaksAlloc(gpa, text, 0, text.len, .thai);
    defer gpa.free(result);
}
test "native SEA dictionary failure paths release all boundary allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
