//! Source ICU dictionary-cache refinement: only engine-internal breaks subdivide
//! the original rule span, retaining mixed-script prefixes/suffixes and word tag.
const std = @import("std");
const words = @import("utf16_words.zig");
const graphemes = @import("utf16_graphemes.zig");
const cjk = @import("word_cjk.zig");
const sea = @import("word_sea.zig");
const Language = union(enum) { cjk, korean, sea: sea.Language, unhandled };
fn dictionaryCharacter(cp: u21) bool {
    const flags = words.traits(cp);
    const script = flags & 15;
    return flags & 16 != 0 or script == 1 or script == 2 or words.wordProperty(cp) == .Katakana or (cp >= 0xac00 and cp <= 0xd7a3);
}
fn languageFor(cp: u21) Language {
    if (cjk.handles(cp)) return .cjk;
    if (cp >= 0xac00 and cp <= 0xd7a3) return .korean;
    const script = words.traits(cp) & 15;
    if (script >= 5 and script <= 8) {
        const language: sea.Language = @enumFromInt(script);
        if (sea.handles(language, cp)) return .{ .sea = language };
    }
    return .unhandled;
}
fn handles(language: Language, cp: u21) bool {
    return switch (language) {
        .cjk => cjk.handles(cp),
        .korean => cp >= 0xac00 and cp <= 0xd7a3,
        .sea => |value| sea.handles(value, cp),
        .unhandled => false,
    };
}
pub fn refineAlloc(gpa: std.mem.Allocator, text: []const u16, rules: []const words.Segment) ![]words.Segment {
    var result: std.ArrayList(words.Segment) = .empty;
    errdefer result.deinit(gpa);
    for (rules) |rule| {
        if (!rule.dictionary) {
            try result.append(gpa, rule);
            continue;
        }
        var boundaries: std.ArrayList(usize) = .empty;
        defer boundaries.deinit(gpa);
        var at = rule.start;
        while (at < rule.end) {
            const cp = graphemes.scalar(text, at);
            if (!dictionaryCharacter(cp.value)) {
                at = cp.end;
                continue;
            }
            const language = languageFor(cp.value);
            if (language == .unhandled) {
                at = cp.end;
                continue;
            }
            const start = at;
            while (at < rule.end and handles(language, graphemes.scalar(text, at).value)) at = graphemes.scalar(text, at).end;
            const found = switch (language) {
                .cjk => try cjk.breaksAlloc(gpa, text, start, at),
                // The pinned CJ dictionary contains no Hangul entries, and ICU
                // does not add unknown-character fallback edges for syllables.
                .korean => try gpa.dupe(usize, &.{}),
                .sea => |value| try sea.breaksAlloc(gpa, text, start, at, value),
                .unhandled => unreachable,
            };
            defer gpa.free(found);
            for (found) |boundary| if (boundary > rule.start and boundary < rule.end and (boundaries.items.len == 0 or boundary > boundaries.items[boundaries.items.len - 1])) try boundaries.append(gpa, boundary);
        }
        var start = rule.start;
        for (boundaries.items) |boundary| {
            try result.append(gpa, .{ .start = start, .end = boundary, .word = rule.word });
            start = boundary;
        }
        try result.append(gpa, .{ .start = start, .end = rule.end, .word = rule.word });
    }
    return result.toOwnedSlice(gpa);
}
