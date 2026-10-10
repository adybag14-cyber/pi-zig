//! Owned JSONL decoding and durable action inspection for executable fixtures.
const std = @import("std");
const json = @import("json_fixture.zig");
pub fn load(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !std.json.Parsed(std.json.Value) {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(8 * 1024 * 1024));
    defer gpa.free(bytes);
    var encoded: std.Io.Writer.Allocating = .init(gpa);
    defer encoded.deinit();
    try encoded.writer.writeByte('[');
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (count > 0) try encoded.writer.writeByte(',');
        try encoded.writer.writeAll(trimmed);
        count += 1;
    }
    try encoded.writer.writeByte(']');
    return std.json.parseFromSlice(std.json.Value, gpa, encoded.written(), .{ .allocate = .alloc_always });
}
pub fn countCustom(items: []const std.json.Value, name: []const u8) usize {
    var count: usize = 0;
    for (items) |item| {
        if (!json.kind(item, "custom")) continue;
        const value = item.object.get("customType") orelse continue;
        if (value == .string and std.mem.eql(u8, value.string, name)) count += 1;
    }
    return count;
}
pub fn lastName(items: []const std.json.Value) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (items) |item| {
        if (!json.kind(item, "session_info")) continue;
        const name = item.object.get("name") orelse continue;
        if (name == .string) found = name.string;
    }
    if (found != null) return found;
    if (items.len > 0 and items[0] == .object) {
        if (items[0].object.get("name")) |name| if (name == .string) return name.string;
    }
    return null;
}
