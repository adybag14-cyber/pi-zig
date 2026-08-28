//! Unicode- and terminal-control-aware text measurement and slicing.
//!
//! Terminal cells are not UTF-8 bytes or Unicode scalar counts. This module
//! centralizes the width rules used by layout, Markdown, LaTeX and hit testing:
//! ANSI/OSC/DCS/APC controls are zero-width; tabs use Pi's fixed three-cell
//! policy; CJK and emoji occupy two cells; combining/default-ignorable scalars
//! occupy no cells; terminal-spacing marks retain their cells; and common emoji,
//! flag, keycap, ZWJ and Indic conjunct clusters stay atomic while slicing.
const std = @import("std");
const tables = @import("unicode_tables.zig");

pub const tab_width: usize = 3;

pub const SequenceKind = enum {
    csi,
    osc,
    dcs,
    apc,
    pm,
    sos,
    escape,
};

pub const Sequence = struct {
    bytes: []const u8,
    end: usize,
    kind: SequenceKind,
};

pub const Cluster = struct {
    bytes: []const u8,
    start: usize,
    end: usize,
    width: usize,
};

pub const CellRange = struct {
    start: usize,
    end: usize,
};

pub const TruncateOptions = struct {
    ellipsis: []const u8 = "…",
    pad: bool = false,
    reset_style: bool = true,
};

fn inRanges(codepoint: u21, ranges: []const tables.Range) bool {
    var low: usize = 0;
    var high: usize = ranges.len;
    while (low < high) {
        const middle = low + (high - low) / 2;
        const range = ranges[middle];
        if (codepoint < range.first) {
            high = middle;
        } else if (codepoint > range.last) {
            low = middle + 1;
        } else {
            return true;
        }
    }
    return false;
}

pub fn isWide(codepoint: u21) bool {
    return inRanges(codepoint, &tables.wide_ranges);
}

pub fn isZeroWidth(codepoint: u21) bool {
    return inRanges(codepoint, &tables.zero_width_ranges);
}

pub fn isSpacingMark(codepoint: u21) bool {
    return inRanges(codepoint, &tables.spacing_mark_ranges);
}

pub fn isEmojiPresentation(codepoint: u21) bool {
    return inRanges(codepoint, &tables.emoji_presentation_ranges);
}

pub fn isEmojiModifier(codepoint: u21) bool {
    return inRanges(codepoint, &tables.emoji_modifier_ranges);
}

pub fn isRegionalIndicator(codepoint: u21) bool {
    return inRanges(codepoint, &tables.regional_indicator_ranges);
}

pub fn isExtendedPictographic(codepoint: u21) bool {
    return inRanges(codepoint, &tables.extended_pictographic_ranges);
}

pub fn isVirama(codepoint: u21) bool {
    return inRanges(codepoint, &tables.virama_ranges);
}

fn decodeAt(bytes: []const u8, index: usize) struct { cp: u21, len: usize, valid: bool } {
    if (index >= bytes.len) return .{ .cp = 0, .len = 0, .valid = false };
    const raw_len = std.unicode.utf8ByteSequenceLength(bytes[index]) catch
        return .{ .cp = bytes[index], .len = 1, .valid = false };
    const len = @min(raw_len, bytes.len - index);
    if (len != raw_len) return .{ .cp = bytes[index], .len = 1, .valid = false };
    const cp = std.unicode.utf8Decode(bytes[index .. index + len]) catch
        return .{ .cp = bytes[index], .len = 1, .valid = false };
    return .{ .cp = cp, .len = len, .valid = true };
}

fn isC0OrDelete(codepoint: u21) bool {
    return codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f);
}

pub fn codepointWidth(codepoint: u21) usize {
    if (codepoint == '\t') return tab_width;
    if (isSpacingMark(codepoint)) return 1;
    if (isC0OrDelete(codepoint) or isZeroWidth(codepoint) or isEmojiModifier(codepoint)) return 0;
    if (isRegionalIndicator(codepoint) or isEmojiPresentation(codepoint) or isWide(codepoint)) return 2;
    return 1;
}

fn stringSequenceEnd(bytes: []const u8, start: usize, allow_bel: bool) ?usize {
    var index = start + 2;
    while (index < bytes.len) : (index += 1) {
        if (allow_bel and bytes[index] == 0x07) return index + 1;
        if (bytes[index] == 0x1b and index + 1 < bytes.len and bytes[index + 1] == '\\') return index + 2;
        if (bytes[index] == 0x9c) return index + 1;
    }
    return null;
}

/// Extract a complete ECMA-48 terminal sequence beginning at `start`.
/// Incomplete string/control sequences return null so streaming callers can
/// retain them until the next chunk.
pub fn extractSequence(bytes: []const u8, start: usize) ?Sequence {
    if (start >= bytes.len) return null;
    if (bytes[start] == 0x9b) {
        var index = start + 1;
        while (index < bytes.len) : (index += 1) {
            if (bytes[index] >= 0x40 and bytes[index] <= 0x7e) {
                return .{ .bytes = bytes[start .. index + 1], .end = index + 1, .kind = .csi };
            }
        }
        return null;
    }
    if (bytes[start] != 0x1b or start + 1 >= bytes.len) return null;
    const introducer = bytes[start + 1];
    if (introducer == '[') {
        var index = start + 2;
        while (index < bytes.len) : (index += 1) {
            if (bytes[index] >= 0x40 and bytes[index] <= 0x7e) {
                return .{ .bytes = bytes[start .. index + 1], .end = index + 1, .kind = .csi };
            }
        }
        return null;
    }
    const kind: SequenceKind = switch (introducer) {
        ']' => .osc,
        'P' => .dcs,
        '_' => .apc,
        '^' => .pm,
        'X' => .sos,
        else => return .{ .bytes = bytes[start .. start + 2], .end = start + 2, .kind = .escape },
    };
    const end = stringSequenceEnd(bytes, start, kind == .osc or kind == .apc) orelse return null;
    return .{ .bytes = bytes[start..end], .end = end, .kind = kind };
}

fn trailingClusterScalar(codepoint: u21) bool {
    return ((!isC0OrDelete(codepoint) and codepoint != 0x200d) and isZeroWidth(codepoint)) or
        isSpacingMark(codepoint) or isEmojiModifier(codepoint) or
        codepoint == 0xfe0e or codepoint == 0xfe0f or codepoint == 0x20e3;
}

/// Return one terminal grapheme-like cluster. The implementation follows the
/// terminal width behavior Pi relies on rather than attempting to expose a full
/// Unicode text-boundary API.
pub fn nextCluster(bytes: []const u8, start: usize) ?Cluster {
    if (start >= bytes.len) return null;
    const first = decodeAt(bytes, start);
    if (first.len == 0) return null;
    if (!first.valid) return .{ .bytes = bytes[start .. start + first.len], .start = start, .end = start + first.len, .width = 1 };

    if (first.cp == '\t') return .{ .bytes = bytes[start .. start + first.len], .start = start, .end = start + first.len, .width = tab_width };

    var end = start + first.len;
    var width = codepointWidth(first.cp);
    var has_emoji = isEmojiPresentation(first.cp);
    var has_extended_pictographic = isExtendedPictographic(first.cp);
    var saw_vs16 = false;
    var saw_keycap = false;
    var regional_count: usize = if (isRegionalIndicator(first.cp)) 1 else 0;
    var previous = first.cp;

    // Regional-indicator flags are a two-scalar, two-cell cluster.
    if (regional_count == 1 and end < bytes.len) {
        const second = decodeAt(bytes, end);
        if (second.valid and isRegionalIndicator(second.cp)) {
            end += second.len;
            regional_count = 2;
            width = 2;
            previous = second.cp;
        }
    }

    while (end < bytes.len) {
        const decoded = decodeAt(bytes, end);
        if (!decoded.valid) break;
        const cp = decoded.cp;
        if (trailingClusterScalar(cp)) {
            if (isSpacingMark(cp)) width += 1;
            if (cp == 0xfe0f) saw_vs16 = true;
            if (cp == 0x20e3) saw_keycap = true;
            if (isEmojiModifier(cp)) has_emoji = true;
            end += decoded.len;
            previous = cp;
            continue;
        }
        if (cp == 0x200d) {
            const joiner_end = end + decoded.len;
            if (joiner_end >= bytes.len) {
                end = joiner_end;
                previous = cp;
                break;
            }
            const joined = decodeAt(bytes, joiner_end);
            if (!joined.valid) break;
            end = joiner_end + joined.len;
            has_emoji = has_emoji or has_extended_pictographic or isExtendedPictographic(joined.cp) or isEmojiPresentation(joined.cp);
            has_extended_pictographic = has_extended_pictographic or isExtendedPictographic(joined.cp);
            previous = joined.cp;
            while (end < bytes.len) {
                const tail = decodeAt(bytes, end);
                if (!tail.valid or !trailingClusterScalar(tail.cp)) break;
                if (isSpacingMark(tail.cp)) width += 1;
                if (tail.cp == 0xfe0f) saw_vs16 = true;
                if (tail.cp == 0x20e3) saw_keycap = true;
                end += tail.len;
                previous = tail.cp;
            }
            continue;
        }
        // Indic grapheme clusters can join a following consonant after a virama.
        if (isVirama(previous)) {
            width += codepointWidth(cp);
            end += decoded.len;
            previous = cp;
            continue;
        }
        break;
    }

    if (regional_count > 0) width = 2;
    if (has_emoji or saw_vs16 or saw_keycap) width = @max(width, 2);
    return .{ .bytes = bytes[start..end], .start = start, .end = end, .width = width };
}

pub fn visibleWidth(bytes: []const u8) usize {
    var width: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            index = sequence.end;
            continue;
        }
        const cluster = nextCluster(bytes, index) orelse break;
        width += cluster.width;
        index = cluster.end;
    }
    return width;
}

pub fn stripAlloc(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, bytes, 0x1b) == null and std.mem.indexOfScalar(u8, bytes, 0x9b) == null) {
        return gpa.dupe(u8, bytes);
    }
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            index = sequence.end;
            continue;
        }
        try out.append(gpa, bytes[index]);
        index += 1;
    }
    return out.toOwnedSlice(gpa);
}

/// Expand visible tabs and use decomposed Thai/Lao AM forms while preserving
/// tabs and bytes inside terminal string/control sequences.
pub fn normalizeTerminalOutputAlloc(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            try out.appendSlice(gpa, sequence.bytes);
            index = sequence.end;
            continue;
        }
        const decoded = decodeAt(bytes, index);
        if (decoded.valid and decoded.cp == 0x0e33) {
            try out.appendSlice(gpa, "\u{0e4d}\u{0e32}");
        } else if (decoded.valid and decoded.cp == 0x0eb3) {
            try out.appendSlice(gpa, "\u{0ecd}\u{0eb2}");
        } else if (bytes[index] == '\t') {
            try out.appendNTimes(gpa, ' ', tab_width);
        } else {
            try out.appendSlice(gpa, bytes[index .. index + decoded.len]);
        }
        index += decoded.len;
    }
    return out.toOwnedSlice(gpa);
}

pub fn graphemeCellRange(bytes: []const u8, column: usize) ?CellRange {
    var current: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            index = sequence.end;
            continue;
        }
        const cluster = nextCluster(bytes, index) orelse break;
        if (cluster.width > 0 and column >= current and column < current + cluster.width) {
            return .{ .start = current, .end = current + cluster.width };
        }
        current += cluster.width;
        index = cluster.end;
    }
    return null;
}

fn osc8Url(sequence: []const u8) ??[]const u8 {
    if (!std.mem.startsWith(u8, sequence, "\x1b]8;")) return null;
    var body = sequence[4..];
    if (std.mem.endsWith(u8, body, "\x1b\\")) body = body[0 .. body.len - 2] else if (body.len > 0 and body[body.len - 1] == 0x07) body = body[0 .. body.len - 1] else return null;
    const separator = std.mem.indexOfScalar(u8, body, ';') orelse return null;
    const url = body[separator + 1 ..];
    if (url.len == 0) return @as(?[]const u8, null);
    return url;
}

/// Return the URL of the OSC 8 hyperlink covering a visible terminal column.
pub fn osc8LinkAtColumn(bytes: []const u8, column: usize) ?[]const u8 {
    var active: ?[]const u8 = null;
    var current: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            if (sequence.kind == .osc) {
                if (osc8Url(sequence.bytes)) |parsed| active = parsed;
            }
            index = sequence.end;
            continue;
        }
        const cluster = nextCluster(bytes, index) orelse break;
        if (cluster.width > 0 and column >= current and column < current + cluster.width) return active;
        current += cluster.width;
        index = cluster.end;
    }
    return null;
}

fn activeOsc8Close(bytes: []const u8) []const u8 {
    var active = false;
    var use_bel = false;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            if (sequence.kind == .osc) {
                if (osc8Url(sequence.bytes)) |parsed| {
                    active = parsed != null;
                    use_bel = sequence.bytes.len > 0 and sequence.bytes[sequence.bytes.len - 1] == 0x07;
                }
            }
            index = sequence.end;
        } else index += 1;
    }
    if (!active) return "";
    return if (use_bel) "\x1b]8;;\x07" else "\x1b]8;;\x1b\\";
}

/// Keep whole terminal clusters up to a visible width. ANSI controls before
/// retained text are preserved; active hyperlinks and SGR state are safely
/// terminated when truncation occurs.
pub fn truncateAlloc(gpa: std.mem.Allocator, bytes: []const u8, max_width: usize, options: TruncateOptions) ![]u8 {
    const full_width = visibleWidth(bytes);
    if (full_width <= max_width) {
        var exact = try gpa.dupe(u8, bytes);
        if (options.pad and full_width < max_width) {
            exact = try gpa.realloc(exact, exact.len + max_width - full_width);
            @memset(exact[bytes.len..], ' ');
        }
        return exact;
    }
    const ellipsis_width = @min(visibleWidth(options.ellipsis), max_width);
    const content_limit = max_width - ellipsis_width;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var width: usize = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            try out.appendSlice(gpa, sequence.bytes);
            index = sequence.end;
            continue;
        }
        const cluster = nextCluster(bytes, index) orelse break;
        if (width + cluster.width > content_limit) break;
        try out.appendSlice(gpa, cluster.bytes);
        width += cluster.width;
        index = cluster.end;
    }
    const close = activeOsc8Close(out.items);
    if (close.len > 0) try out.appendSlice(gpa, close);
    if (options.reset_style) try out.appendSlice(gpa, "\x1b[0m");
    if (ellipsis_width > 0) try out.appendSlice(gpa, options.ellipsis);
    if (options.reset_style and ellipsis_width > 0) try out.appendSlice(gpa, "\x1b[0m");
    const final_width = width + ellipsis_width;
    if (options.pad and final_width < max_width) try out.appendNTimes(gpa, ' ', max_width - final_width);
    return out.toOwnedSlice(gpa);
}

/// Slice by terminal columns without splitting a wide or joined cluster. ANSI
/// controls preceding the first selected cluster are retained so style/link
/// state remains reproducible in the returned fragment.
pub fn sliceByColumnsAlloc(gpa: std.mem.Allocator, bytes: []const u8, start_column: usize, max_width: usize) ![]u8 {
    var prefix_controls: std.ArrayList(u8) = .empty;
    defer prefix_controls.deinit(gpa);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var current: usize = 0;
    var selected: usize = 0;
    var started = false;
    var index: usize = 0;
    while (index < bytes.len) {
        if (extractSequence(bytes, index)) |sequence| {
            if (started) try out.appendSlice(gpa, sequence.bytes) else try prefix_controls.appendSlice(gpa, sequence.bytes);
            index = sequence.end;
            continue;
        }
        const cluster = nextCluster(bytes, index) orelse break;
        const cluster_end = current + cluster.width;
        if (!started and cluster_end > start_column) {
            started = true;
            try out.appendSlice(gpa, prefix_controls.items);
        }
        if (started) {
            if (selected + cluster.width > max_width) break;
            try out.appendSlice(gpa, cluster.bytes);
            selected += cluster.width;
        }
        current = cluster_end;
        index = cluster.end;
    }
    if (started) {
        const close = activeOsc8Close(out.items);
        if (close.len > 0) try out.appendSlice(gpa, close);
        try out.appendSlice(gpa, "\x1b[0m");
    }
    return out.toOwnedSlice(gpa);
}

test "Unicode terminal widths cover controls CJK emoji and marks" {
    try std.testing.expectEqual(@as(usize, 3), visibleWidth("abc"));
    try std.testing.expectEqual(@as(usize, 5), visibleWidth("a\tb"));
    try std.testing.expectEqual(@as(usize, 4), visibleWidth("a界b"));
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("😀"));
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("👨‍👩‍👧‍👦"));
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("🇬🇧"));
    try std.testing.expectEqual(@as(usize, 2), visibleWidth("1️⃣"));
    try std.testing.expectEqual(@as(usize, 1), visibleWidth("e\u{301}"));
    try std.testing.expectEqual(@as(usize, 3), visibleWidth("\x1b[31mabc\x1b[0m"));
}

test "sequence extraction strips CSI OSC DCS and APC" {
    const gpa = std.testing.allocator;
    const value = "a\x1b[38;2;1;2;3mb\x1b]8;;https://x\x07c\x1b]8;;\x07\x1bPpayload\x1b\\\x1b_mark\x1b\\d";
    const stripped = try stripAlloc(gpa, value);
    defer gpa.free(stripped);
    try std.testing.expectEqualStrings("abcd", stripped);
    try std.testing.expectEqual(@as(usize, 4), visibleWidth(value));
}

test "grapheme cell hit testing keeps wide clusters atomic" {
    try std.testing.expectEqual(CellRange{ .start = 1, .end = 3 }, graphemeCellRange("a界b", 1).?);
    try std.testing.expectEqual(CellRange{ .start = 1, .end = 3 }, graphemeCellRange("a界b", 2).?);
    try std.testing.expectEqual(CellRange{ .start = 3, .end = 4 }, graphemeCellRange("a界b", 3).?);
}

test "OSC 8 links are found by visible column" {
    const value = "x\x1b]8;id=1;https://example.test\x07界y\x1b]8;;\x07z";
    try std.testing.expectEqualStrings("https://example.test", osc8LinkAtColumn(value, 1).?);
    try std.testing.expectEqualStrings("https://example.test", osc8LinkAtColumn(value, 3).?);
    try std.testing.expect(osc8LinkAtColumn(value, 4) == null);
}

test "normalization expands visible tabs and decomposes Thai Lao AM" {
    const gpa = std.testing.allocator;
    const normalized = try normalizeTerminalOutputAlloc(gpa, "a\tb กำ ກຳ \x1b]8;;x\turl\x07z");
    defer gpa.free(normalized);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "a   b") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "\u{0e4d}\u{0e32}") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "\u{0ecd}\u{0eb2}") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "x\turl") != null);
}

test "truncate and slice never divide wide or styled clusters" {
    const gpa = std.testing.allocator;
    const truncated = try truncateAlloc(gpa, "\x1b[31mab界cd", 5, .{});
    defer gpa.free(truncated);
    try std.testing.expectEqual(@as(usize, 5), visibleWidth(truncated));
    try std.testing.expect(std.mem.indexOf(u8, truncated, "界") != null);

    const sliced = try sliceByColumnsAlloc(gpa, "\x1b[31ma界bc", 1, 3);
    defer gpa.free(sliced);
    try std.testing.expectEqual(@as(usize, 3), visibleWidth(sliced));
    try std.testing.expect(std.mem.indexOf(u8, sliced, "界b") != null);
}
