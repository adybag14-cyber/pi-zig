//! Pi 1.1.0 APC cursor markers. Resolution precedes SGR-aware composition.
const std = @import("std");
pub const cursor = "\x1b_pi:c\x07";
pub const fake_start = "\x1b_pi:fc\x07";
pub const fake_end = "\x1b_pi:/fc\x07";
pub fn appendFake(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    try out.appendSlice(gpa, fake_start);
    try out.appendSlice(gpa, text);
    try out.appendSlice(gpa, fake_end);
}
pub fn resolveAlloc(gpa: std.mem.Allocator, line: []const u8, hardware: bool) ![]u8 {
    if (std.mem.indexOf(u8, line, fake_start) == null) return gpa.dupe(u8, line);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const focused = if (hardware) std.mem.indexOf(u8, line, cursor ++ fake_start) else null;
    var drop_start: ?usize = null;
    var drop_end: ?usize = null;
    if (focused) |at| {
        drop_start = at + cursor.len;
        drop_end = std.mem.indexOfPos(u8, line, at + cursor.len + fake_start.len, fake_end);
    }
    var index: usize = 0;
    while (index < line.len) {
        if (drop_start != null and index == drop_start.?) {
            index += fake_start.len;
        } else if (drop_end != null and index == drop_end.?) {
            index += fake_end.len;
        } else if (std.mem.startsWith(u8, line[index..], fake_start)) {
            try out.appendSlice(gpa, "\x1b[7m");
            index += fake_start.len;
        } else if (std.mem.startsWith(u8, line[index..], fake_end)) {
            try out.appendSlice(gpa, "\x1b[27m");
            index += fake_end.len;
        } else {
            try out.append(gpa, line[index]);
            index += 1;
        }
    }
    return out.toOwnedSlice(gpa);
}
pub fn resolveLines(gpa: std.mem.Allocator, lines: [][]u8, hardware: bool) !void {
    for (lines) |*line| {
        const next = try resolveAlloc(gpa, line.*, hardware);
        gpa.free(line.*);
        line.* = next;
    }
}
test "actual Source1ced focused unfocused truncated nested multiline styled fake cursor markers resolve exactly" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/cursor-original-1ced.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const actual = try resolveAlloc(std.testing.allocator, item.object.get("line").?.string, item.object.get("hardware").?.bool);
        defer std.testing.allocator.free(actual);
        try std.testing.expectEqualStrings(item.object.get("expected").?.string, actual);
    }
    for (fixture.value.object.get("wrappers").?.array.items) |item| {
        var wrapped: std.ArrayList(u8) = .empty;
        defer wrapped.deinit(std.testing.allocator);
        try appendFake(std.testing.allocator, &wrapped, item.object.get("text").?.string);
        try std.testing.expectEqualStrings(item.object.get("expected").?.string, wrapped.items);
    }
}
