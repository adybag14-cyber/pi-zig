//! Pure UTF-8-safe word navigation used by the native editor.
const std = @import("std");

const Class = enum { whitespace, word, punctuation };

fn prevScalarStart(text: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var i = pos - 1;
    while (i > 0 and (text[i] & 0xC0) == 0x80) : (i -= 1) {}
    return i;
}

fn nextScalarEnd(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return text.len;
    const n = std.unicode.utf8ByteSequenceLength(text[pos]) catch 1;
    return @min(text.len, pos + @as(usize, n));
}

fn scalarClass(bytes: []const u8) Class {
    if (bytes.len == 0) return .whitespace;
    if (bytes.len == 1) {
        const c = bytes[0];
        if (std.ascii.isWhitespace(c)) return .whitespace;
        if (std.ascii.isAlphanumeric(c) or c == '_') return .word;
        return .punctuation;
    }
    // Intl.Segmenter treats most letters/scripts as word-like. Until the Zig
    // stdlib exposes UAX #29 segmentation, non-ASCII scalars are conservatively
    // treated as word-like rather than split byte-by-byte.
    return .word;
}

pub fn findWordBackward(text: []const u8, cursor: usize) usize {
    var pos = @min(cursor, text.len);
    while (pos > 0) {
        const start = prevScalarStart(text, pos);
        if (scalarClass(text[start..pos]) != .whitespace) break;
        pos = start;
    }
    if (pos == 0) return 0;
    var start = prevScalarStart(text, pos);
    const target = scalarClass(text[start..pos]);
    pos = start;
    while (pos > 0) {
        start = prevScalarStart(text, pos);
        if (scalarClass(text[start..pos]) != target) break;
        pos = start;
    }
    return pos;
}

pub fn findWordForward(text: []const u8, cursor: usize) usize {
    var pos = @min(cursor, text.len);
    while (pos < text.len) {
        const end = nextScalarEnd(text, pos);
        if (scalarClass(text[pos..end]) != .whitespace) break;
        pos = end;
    }
    if (pos >= text.len) return text.len;
    var end = nextScalarEnd(text, pos);
    const target = scalarClass(text[pos..end]);
    pos = end;
    while (pos < text.len) {
        end = nextScalarEnd(text, pos);
        if (scalarClass(text[pos..end]) != target) break;
        pos = end;
    }
    return pos;
}

pub fn previousScalar(text: []const u8, cursor: usize) usize {
    return prevScalarStart(text, @min(cursor, text.len));
}

pub fn nextScalar(text: []const u8, cursor: usize) usize {
    return nextScalarEnd(text, @min(cursor, text.len));
}

test "word navigation separates words punctuation and whitespace" {
    const text = "alpha...  beta";
    try std.testing.expectEqual(@as(usize, 10), findWordBackward(text, text.len));
    try std.testing.expectEqual(@as(usize, 5), findWordBackward(text, 10));
    try std.testing.expectEqual(@as(usize, 8), findWordForward(text, 5));
    try std.testing.expectEqual(@as(usize, 14), findWordForward(text, 8));
}

test "word navigation is UTF-8 scalar safe" {
    const text = "你好 world";
    const after_first = nextScalar(text, 0);
    try std.testing.expectEqual(@as(usize, 3), after_first);
    try std.testing.expectEqual(@as(usize, 0), findWordBackward(text, 6));
    try std.testing.expectEqual(@as(usize, 6), findWordForward(text, 0));
}
