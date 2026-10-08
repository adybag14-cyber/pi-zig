//! Pure Zig NFKC and original UTF16 index mapping for ICU CJK word refinement.
const std = @import("std");
const data = @import("icu78/generated_normalization.zig");
const graphemes = @import("utf16_graphemes.zig");
pub fn combining(cp: u21) u8 {
    var low: usize = 0;
    var high = data.combining.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const value = data.combining[mid];
        if (cp < value.cp) high = mid else if (cp > value.cp) low = mid + 1 else return value.value;
    }
    return 0;
}
fn decomposition(cp: u21) ?[]const u21 {
    var low: usize = 0;
    var high = data.mappings.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const value = data.mappings[mid];
        if (cp < value.cp) high = mid else if (cp > value.cp) low = mid + 1 else return value.text;
    }
    return null;
}
fn composed(first: u21, second: u21) ?u21 {
    if (first >= 0x1100 and first < 0x1113 and second >= 0x1161 and second < 0x1176) return 0xac00 + (first - 0x1100) * 588 + (second - 0x1161) * 28;
    if (first >= 0xac00 and first < 0xd7a4 and (first - 0xac00) % 28 == 0 and second > 0x11a7 and second < 0x11c3) return first + (second - 0x11a7);
    var low: usize = 0;
    var high = data.compositions.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        const value = data.compositions[mid];
        if (first < value.first or (first == value.first and second < value.second)) high = mid else if (first > value.first or (first == value.first and second > value.second)) low = mid + 1 else return value.value;
    }
    return null;
}
fn appendOrdered(gpa: std.mem.Allocator, list: *std.ArrayList(u21), cp: u21) !void {
    const cc = combining(cp);
    var at = list.items.len;
    if (cc != 0) while (at > 0 and combining(list.items[at - 1]) > cc) : (at -= 1) {};
    try list.insert(gpa, at, cp);
}
pub fn normalizeAlloc(gpa: std.mem.Allocator, text: []const u16) ![]u16 {
    var ordered: std.ArrayList(u21) = .empty;
    defer ordered.deinit(gpa);
    var at: usize = 0;
    while (at < text.len) {
        const cp = graphemes.scalar(text, at);
        if (cp.value >= 0xac00 and cp.value < 0xd7a4) {
            const index = cp.value - 0xac00;
            try appendOrdered(gpa, &ordered, 0x1100 + index / 588);
            try appendOrdered(gpa, &ordered, 0x1161 + (index % 588) / 28);
            if (index % 28 != 0) try appendOrdered(gpa, &ordered, 0x11a7 + index % 28);
        } else if (decomposition(cp.value)) |values| {
            for (values) |value| try appendOrdered(gpa, &ordered, value);
        } else try appendOrdered(gpa, &ordered, cp.value);
        at = cp.end;
    }
    var written: usize = 0;
    var starter: ?usize = null;
    var last_cc: u8 = 0;
    for (ordered.items) |cp| {
        const cc = combining(cp);
        if (starter) |position| if (last_cc == 0 or last_cc < cc) {
            if (composed(ordered.items[position], cp)) |value| {
                ordered.items[position] = value;
                continue;
            }
        };
        if (cc == 0) starter = written;
        ordered.items[written] = cp;
        written += 1;
        last_cc = cc;
    }
    ordered.items.len = written;
    var result: std.ArrayList(u16) = .empty;
    errdefer result.deinit(gpa);
    for (ordered.items) |cp| {
        if (cp <= 0xffff) try result.append(gpa, @intCast(cp)) else try result.appendSlice(gpa, &.{ @as(u16, @intCast(0xd800 + ((cp - 0x10000) >> 10))), @as(u16, @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff))) });
    }
    return result.toOwnedSlice(gpa);
}
fn hasBoundaryBefore(cp: u21) bool {
    const first = if (decomposition(cp)) |values| values[0] else cp;
    if (combining(first) != 0 or (first >= 0x1161 and first < 0x1176) or (first > 0x11a7 and first < 0x11c3)) return false;
    return std.sort.binarySearch(u21, &data.backwards, first, struct {
        fn compare(key: u21, item: u21) std.math.Order {
            return std.math.order(key, item);
        }
    }.compare) == null;
}
pub const Mapped = struct {
    gpa: std.mem.Allocator,
    text: []u16,
    original: []usize,
    pub fn deinit(self: *Mapped) void {
        self.gpa.free(self.text);
        self.gpa.free(self.original);
    }
};
pub fn normalizeMappedAlloc(gpa: std.mem.Allocator, text: []const u16) !Mapped {
    const complete = try normalizeAlloc(gpa, text);
    defer gpa.free(complete);
    if (std.mem.eql(u16, complete, text)) {
        const owned = try gpa.dupe(u16, text);
        errdefer gpa.free(owned);
        const map = try gpa.alloc(usize, text.len + 1);
        for (map, 0..) |*value, index| value.* = index;
        return .{ .gpa = gpa, .text = owned, .original = map };
    }
    var output: std.ArrayList(u16) = .empty;
    errdefer output.deinit(gpa);
    var map: std.ArrayList(usize) = .empty;
    errdefer map.deinit(gpa);
    var start: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const cp = graphemes.scalar(text, at);
        if (at > start and hasBoundaryBefore(cp.value)) {
            const normalized = try normalizeAlloc(gpa, text[start..at]);
            defer gpa.free(normalized);
            try output.appendSlice(gpa, normalized);
            try map.appendNTimes(gpa, start, normalized.len);
            start = at;
        }
        at = cp.end;
    }
    const last = try normalizeAlloc(gpa, text[start..]);
    defer gpa.free(last);
    try output.appendSlice(gpa, last);
    try map.appendNTimes(gpa, start, last.len);
    try map.append(gpa, text.len);
    if (!std.mem.eql(u16, complete, output.items)) return error.InvalidNormalizationBoundary;
    const owned = try output.toOwnedSlice(gpa);
    errdefer gpa.free(owned);
    return .{ .gpa = gpa, .text = owned, .original = try map.toOwnedSlice(gpa) };
}
fn unitsAlloc(gpa: std.mem.Allocator, values: []const std.json.Value, codepoints: bool) ![]u16 {
    var result: std.ArrayList(u16) = .empty;
    errdefer result.deinit(gpa);
    for (values) |value| {
        const cp: u21 = @intCast(value.integer);
        if (!codepoints or cp <= 0xffff) try result.append(gpa, @intCast(cp)) else try result.appendSlice(gpa, &.{ @as(u16, @intCast(0xd800 + ((cp - 0x10000) >> 10))), @as(u16, @intCast(0xdc00 + ((cp - 0x10000) & 0x3ff))) });
    }
    return result.toOwnedSlice(gpa);
}
test "Source ICU78 Unicode17 NFKC mappings compositions and original sequence corpus" {
    const gpa = std.testing.allocator;
    const fixture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/word-normalization-original-6fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("mappings").?.array.items) |entry| {
        const cp = [_]std.json.Value{entry.object.get("codepoint").?};
        const text = try unitsAlloc(gpa, &cp, true);
        defer gpa.free(text);
        const wanted = try unitsAlloc(gpa, entry.object.get("nfkc").?.array.items, true);
        defer gpa.free(wanted);
        const actual = try normalizeAlloc(gpa, text);
        defer gpa.free(actual);
        try std.testing.expectEqualSlices(u16, wanted, actual);
    }
    for (fixture.value.object.get("cases").?.array.items) |entry| {
        const text = try unitsAlloc(gpa, entry.object.get("units").?.array.items, false);
        defer gpa.free(text);
        const wanted = try unitsAlloc(gpa, entry.object.get("nfkc").?.array.items, false);
        defer gpa.free(wanted);
        var actual = try normalizeMappedAlloc(gpa, text);
        defer actual.deinit();
        try std.testing.expectEqualSlices(u16, wanted, actual.text);
    }
}
fn allocationCase(gpa: std.mem.Allocator) !void {
    const text = try std.unicode.utf8ToUtf16LeAlloc(gpa, "ｶﾞｯﾂﾎﾟｰｽﾞあゟい");
    defer gpa.free(text);
    var result = try normalizeMappedAlloc(gpa, text);
    defer result.deinit();
}
test "native word normalization failure paths free ordered units maps and chunks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
