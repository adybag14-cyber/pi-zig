//! Checked JSON shape and values used by executable behavior fixtures.
const std = @import("std");
pub fn field(value: std.json.Value, name: []const u8) !std.json.Value {
    if (value != .object) return error.CompactionExpectedObject;
    return value.object.get(name) orelse error.CompactionFieldMissing;
}
pub fn text(value: std.json.Value, wanted: []const u8) !void {
    try std.testing.expect(value == .string);
    try std.testing.expectEqualStrings(wanted, value.string);
}
pub fn kind(value: std.json.Value, name: []const u8) bool {
    const v = if (value == .object) value.object.get("type") orelse return false else return false;
    return v == .string and std.mem.eql(u8, v.string, name);
}
