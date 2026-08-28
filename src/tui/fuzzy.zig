//! Deterministic ASCII fuzzy scoring shared by selectors and completion.
//! Higher scores are better; null means the query is not a subsequence.
const std = @import("std");

fn isBoundary(text: []const u8, index: usize) bool {
    if (index == 0) return true;
    const prev = text[index - 1];
    const current = text[index];
    if (prev == '/' or prev == '-' or prev == '_' or prev == '.' or prev == ' ' or prev == '\t') return true;
    return std.ascii.isLower(prev) and std.ascii.isUpper(current);
}

pub fn score(text: []const u8, query_raw: []const u8) ?i32 {
    const query = std.mem.trim(u8, query_raw, " \t\r\n");
    if (query.len == 0) return 0;
    if (text.len == 0 or query.len > text.len) return null;

    if (std.ascii.eqlIgnoreCase(text, query)) {
        const exact_case_bonus: i32 = if (std.mem.eql(u8, text, query)) 200 else 0;
        return 20_000 + exact_case_bonus;
    }
    if (text.len >= query.len and std.ascii.eqlIgnoreCase(text[0..query.len], query)) {
        var case_bonus: i32 = 0;
        for (query, 0..) |byte, index| if (text[index] == byte) {
            case_bonus += 4;
        };
        return 12_000 + case_bonus - @as(i32, @intCast(text.len - query.len));
    }

    var total: i32 = 0;
    var text_index: usize = 0;
    var previous_match: ?usize = null;
    var first_match: ?usize = null;

    for (query) |needle_raw| {
        const needle = std.ascii.toLower(needle_raw);
        var found: ?usize = null;
        while (text_index < text.len) : (text_index += 1) {
            if (std.ascii.toLower(text[text_index]) == needle) {
                found = text_index;
                break;
            }
        }
        const index = found orelse return null;
        if (first_match == null) first_match = index;

        total += 100;
        if (isBoundary(text, index)) total += 90;
        if (text[index] == needle_raw) total += 8;
        if (previous_match) |previous| {
            const gap = index - previous - 1;
            if (gap == 0) {
                total += 65;
            } else {
                total -= @as(i32, @intCast(@min(gap, 24))) * 6;
            }
        }
        previous_match = index;
        text_index = index + 1;
    }

    // Prefer matches beginning early and compact candidates when all else ties.
    total -= @as(i32, @intCast(@min(first_match.?, 80))) * 4;
    total -= @as(i32, @intCast(@min(text.len - query.len, 80)));
    return total;
}

pub fn bestScore(fields: []const []const u8, query: []const u8) ?i32 {
    var best: ?i32 = null;
    for (fields) |field| {
        if (score(field, query)) |candidate| {
            if (best == null or candidate > best.?) best = candidate;
        }
    }
    return best;
}

test "fuzzy score ranks exact prefix boundary and subsequence" {
    const exact = score("claude-sonnet", "claude-sonnet").?;
    const prefix = score("claude-sonnet-4", "claude").?;
    const boundary = score("anthropic/claude-sonnet", "cs").?;
    const loose = score("miscatalogsample", "cs").?;
    try std.testing.expect(exact > prefix);
    try std.testing.expect(prefix > boundary);
    try std.testing.expect(boundary > loose);
    try std.testing.expect(score("gpt-4o", "zz") == null);
}

test "fuzzy scoring is case insensitive but rewards exact case" {
    try std.testing.expect(score("GPT-4o", "GPT").? > score("gpt-4o", "GPT").?);
    try std.testing.expect(score("Claude Sonnet", "clsn") != null);
}

test "bestScore searches provider model and display fields" {
    const fields = [_][]const u8{ "anthropic", "claude-sonnet-4", "Claude Sonnet 4" };
    try std.testing.expect(bestScore(&fields, "ant") != null);
    try std.testing.expect(bestScore(&fields, "cs4") != null);
    try std.testing.expect(bestScore(&fields, "gemini") == null);
}
