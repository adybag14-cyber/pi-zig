//! Source6fb grapheme cell widths using pinned ICU78.2 / Unicode17 data.
const std = @import("std");
const data = @import("unicode17/generated_width.zig");
const graphemes = @import("utf16_graphemes.zig");
fn flags(cp: u21) u8 {
    var low: usize = 0;
    var high = data.properties.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const entry = data.properties[mid];
        if (cp < entry.first) high = mid else if (cp > entry.last) low = mid + 1 else return entry.flags;
    }
    return 0;
}
fn isEmoji(text: []const u16) bool {
    var low: usize = 0;
    var high = data.emoji.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        switch (std.mem.order(u16, text, data.emoji[mid])) {
            .lt => high = mid,
            .gt => low = mid + 1,
            .eq => return true,
        }
    }
    return false;
}
pub fn width(text: []const u16) usize {
    if (text.len == 0) return 0;
    if (text.len == 1) {
        if (text[0] >= 0x20 and text[0] <= 0x7e) return 1;
        if (text[0] == 9) return 3;
    }
    var at: usize = 0;
    var count: usize = 0;
    var all_spacing = true;
    var all_zero = true;
    var base: ?graphemes.Scalar = null;
    while (at < text.len) {
        const cp = graphemes.scalar(text, at);
        const bits = flags(cp.value);
        all_spacing = all_spacing and bits & 8 != 0;
        all_zero = all_zero and bits & 4 != 0;
        if (base == null and bits & 2 == 0) base = cp;
        count += 1;
        at = cp.end;
    }
    if (all_spacing) return count;
    if (all_zero) return 0;
    if (isEmoji(text)) return 2;
    const first = base orelse return 0;
    if (first.value >= 0x1f1e6 and first.value <= 0x1f1ff) return 2;
    var total: usize = if (flags(first.value) & 16 != 0) 2 else 1;
    var follows_mark = false;
    at = first.end;
    while (at < text.len) {
        const cp = graphemes.scalar(text, at);
        const bits = flags(cp.value);
        if (bits & 8 != 0) {
            total += 1;
            follows_mark = false;
        } else if (bits & 1 != 0) follows_mark = true else if (bits & 2 == 0) {
            if (follows_mark or (cp.value >= 0xff00 and cp.value <= 0xffef)) total += if (bits & 16 != 0) @as(usize, 2) else 1 else if (cp.value == 0xe33 or cp.value == 0xeb3) total += 1;
            follows_mark = false;
        }
        at = cp.end;
    }
    return total;
}
fn scalarUnits(cp: u21, storage: *[2]u16) []const u16 {
    if (cp <= 0xffff) {
        storage[0] = @intCast(cp);
        return storage[0..1];
    }
    storage[0] = @intCast(0xd800 + ((cp - 0x10000) >> 10));
    storage[1] = @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff));
    return storage;
}
test "Source6fb public Input width matches every Unicode scalar and 9104 original grapheme cases" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/input-width-original-6fb.json"), .{});
    defer fixture.deinit();
    const expected = fixture.value.object.get("scalarWidths").?.array.items;
    var range: usize = 0;
    for (0..0x110000) |value| {
        while (range < expected.len and expected[range].object.get("last").?.integer < value) range += 1;
        const wanted: usize = if (range < expected.len and expected[range].object.get("first").?.integer <= value) @intCast(expected[range].object.get("value").?.integer) else 1;
        var storage: [2]u16 = undefined;
        std.testing.expectEqual(wanted, width(scalarUnits(@intCast(value), &storage))) catch |err| {
            std.debug.print("Scalar width mismatch U+{X}\n", .{value});
            return err;
        };
    }
    for (fixture.value.object.get("cases").?.array.items) |entry| {
        const text = try std.testing.allocator.alloc(u16, entry.object.get("units").?.array.items.len);
        defer std.testing.allocator.free(text);
        for (text, entry.object.get("units").?.array.items) |*unit, item| unit.* = @intCast(item.integer);
        std.testing.expectEqual(@as(usize, @intCast(entry.object.get("width").?.integer)), width(text)) catch |err| {
            std.debug.print("Cluster width mismatch {any}\n", .{text});
            return err;
        };
    }
}
