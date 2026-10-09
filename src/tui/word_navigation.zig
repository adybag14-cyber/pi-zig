//! Source Unicode17/ICU78 word navigation for the core editor's UTF8 byte cursor.
//! Public JS Input uses UTF16 directly; this adapter preserves existing byte
//! storage while sharing the same language engine and allocation failures.
const std = @import("std");
const words = @import("utf16_words.zig");
fn prevScalarStart(text: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var at = pos - 1;
    while (at > 0 and (text[at] & 0xc0) == 0x80) : (at -= 1) {}
    return at;
}
fn nextScalarEnd(text: []const u8, pos: usize) usize {
    if (pos >= text.len) return text.len;
    return @min(text.len, pos + @as(usize, std.unicode.utf8ByteSequenceLength(text[pos]) catch 1));
}
fn unitsBefore(text: []const u8, cursor: usize) !usize {
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var count: usize = 0;
    while (iterator.nextCodepoint()) |cp| {
        if (iterator.i > cursor) return error.InvalidWordCursorBoundary;
        count += if (cp > 0xffff) @as(usize, 2) else 1;
        if (iterator.i == cursor) return count;
    }
    return count;
}
fn bytesBefore(text: []const u8, target: usize) !usize {
    if (target == 0) return 0;
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var count: usize = 0;
    while (iterator.nextCodepoint()) |cp| {
        count += if (cp > 0xffff) @as(usize, 2) else 1;
        if (count > target) return error.InvalidWordCursorBoundary;
        if (count == target) return iterator.i;
    }
    return text.len;
}
fn navigate(gpa: std.mem.Allocator, text: []const u8, cursor: usize, backwards: bool) !usize {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, text);
    defer gpa.free(units);
    const at = @min(cursor, text.len);
    const position = if (at == 0) 0 else try unitsBefore(text, at);
    const target = if (backwards) try words.findBackwardAlloc(gpa, units, @intCast(position)) else try words.findForwardAlloc(gpa, units, @intCast(position));
    return bytesBefore(text, @intCast(target));
}
pub fn findWordBackward(gpa: std.mem.Allocator, text: []const u8, cursor: usize) !usize {
    return navigate(gpa, text, cursor, true);
}
pub fn findWordForward(gpa: std.mem.Allocator, text: []const u8, cursor: usize) !usize {
    return navigate(gpa, text, cursor, false);
}
pub fn previousScalar(text: []const u8, cursor: usize) usize {
    return prevScalarStart(text, @min(cursor, text.len));
}
pub fn nextScalar(text: []const u8, cursor: usize) usize {
    return nextScalarEnd(text, @min(cursor, text.len));
}
test "core editor Source word navigation separates words punctuation and whitespace" {
    const gpa = std.testing.allocator;
    const text = "alpha...  beta";
    try std.testing.expectEqual(@as(usize, 10), try findWordBackward(gpa, text, text.len));
    try std.testing.expectEqual(@as(usize, 5), try findWordBackward(gpa, text, 10));
    try std.testing.expectEqual(@as(usize, 8), try findWordForward(gpa, text, 5));
    try std.testing.expectEqual(@as(usize, 14), try findWordForward(gpa, text, 8));
}
test "core editor Source byte cursor shares dictionary boundaries and preserves scalar helpers" {
    const gpa = std.testing.allocator;
    const text = "中文测试语言";
    try std.testing.expectEqual(@as(usize, 3), nextScalar(text, 0));
    try std.testing.expectEqual(@as(usize, 6), try findWordForward(gpa, text, 0));
    try std.testing.expectEqual(@as(usize, 12), try findWordBackward(gpa, text, text.len));
    try std.testing.expectError(error.InvalidWordCursorBoundary, findWordForward(gpa, "😀x", 1));
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const text = "中文测试 ภาษาไทยภาษาอังกฤษ";
    _ = try findWordBackward(gpa, text, text.len);
    _ = try findWordForward(gpa, text, 0);
}
test "core word byte adapter releases conversion and language allocations on every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
test "core editor byte cursor adapter replays every representable original Source word position" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-navigation-original-6fb.json"), .{});
    defer fixture.deinit();
    var tested: usize = 0;
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const raw = item.object.get("units").?.array.items;
        const units = try gpa.alloc(u16, raw.len);
        defer gpa.free(units);
        for (units, raw) |*unit, value| unit.* = @intCast(value.integer);
        const text = try std.unicode.wtf16LeToWtf8Alloc(gpa, units);
        defer gpa.free(text);
        for (item.object.get("navigation").?.array.items) |position| {
            const cursor = position.object.get("cursor").?.integer;
            if (cursor < 0 or cursor > units.len) continue;
            // A byte-backed editor has no position inside a four-byte scalar;
            // the direct UTF16 and JS Input corpora cover those splits.
            const bytes = bytesBefore(text, @intCast(cursor)) catch |err| switch (err) {
                error.InvalidWordCursorBoundary => continue,
                else => return err,
            };
            const backwards = try bytesBefore(text, @intCast(position.object.get("backward").?.integer));
            const forwards = try bytesBefore(text, @intCast(position.object.get("forward").?.integer));
            try std.testing.expectEqual(backwards, try findWordBackward(gpa, text, bytes));
            try std.testing.expectEqual(forwards, try findWordForward(gpa, text, bytes));
            tested += 1;
        }
    }
    try std.testing.expect(tested > 4000);
}
