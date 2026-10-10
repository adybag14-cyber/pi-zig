//! Source-compatible exact modifiers and plain/glob allowlists.
const std = @import("std");
/// AgentSession's default loadout; the registry additionally exposes grep/find/ls.
pub const default_tool_names = [_][]const u8{ "read", "bash", "edit", "write" };
pub fn isModifier(entry: []const u8) bool {
    return entry.len > 0 and (entry[0] == '+' or entry[0] == '-');
}
pub fn usesModifiers(entries: []const []const u8) bool {
    for (entries) |entry| if (isModifier(entry)) return true;
    return false;
}
pub fn listError(gpa: std.mem.Allocator, entries: []const []const u8) !?[]u8 {
    var modifiers: usize = 0;
    for (entries) |entry| if (isModifier(entry)) {
        modifiers += 1;
    };
    if (modifiers == 0) return null;
    if (modifiers != entries.len) return try gpa.dupe(u8, "tool names cannot be mixed with +name or -name entries");
    for (entries) |entry| if (std.mem.indexOfScalar(u8, entry, '*') != null) return try std.fmt.allocPrint(gpa, "+name and -name entries take exact tool names, not patterns: {s}", .{entry});
    return null;
}
/// Array storage is owned, names borrow caller strings; order and duplicates
/// in the base match JavaScript indexOf/splice semantics.
pub fn apply(gpa: std.mem.Allocator, base: []const []const u8, entries: []const []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(gpa);
    try names.appendSlice(gpa, base);
    for (entries) |entry| {
        if (!isModifier(entry)) continue;
        const name = entry[1..];
        var index: ?usize = null;
        for (names.items, 0..) |existing, i| if (std.mem.eql(u8, existing, name)) {
            index = i;
            break;
        };
        if (entry[0] == '+' and index == null and name.len > 0) try names.append(gpa, name) else if (entry[0] == '-' and index != null) _ = names.orderedRemove(index.?);
    }
    return names.toOwnedSlice(gpa);
}
pub fn enabled(base: bool, name: []const u8, entries: ?[]const []const u8) bool {
    var result = base;
    for (entries orelse &.{}) |entry| if (isModifier(entry) and std.mem.eql(u8, entry[1..], name)) {
        result = entry[0] == '+';
    };
    return result;
}

test "tool modifiers preserve source ordering exactness last-operation and failure ownership" {
    const gpa = std.testing.allocator;
    const values = try apply(gpa, &.{ "read", "write", "write" }, &.{ "-write", "+codemode", "+read", "-read", "+read", "+", "plain" });
    defer gpa.free(values);
    try std.testing.expectEqual(@as(usize, 3), values.len);
    for ([_][]const u8{ "write", "codemode", "read" }, values) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
    const mixed = (try listError(gpa, &.{ "+read", "write" })).?;
    defer gpa.free(mixed);
    try std.testing.expectEqualStrings("tool names cannot be mixed with +name or -name entries", mixed);
    const pattern = (try listError(gpa, &.{"+mcp__*"})).?;
    defer gpa.free(pattern);
    try std.testing.expectEqualStrings("+name and -name entries take exact tool names, not patterns: +mcp__*", pattern);
    try std.testing.expect((try listError(gpa, &.{ "read", "mcp__*" })) == null);
    try std.testing.expect(enabled(false, "read", &.{ "+read", "-read", "+read" }));
    const Sweep = struct {
        fn run(alloc: std.mem.Allocator) !void {
            const names = try apply(alloc, &.{ "read", "write" }, &.{ "+codemode", "-write" });
            defer alloc.free(names);
            const diagnostic = (try listError(alloc, &.{"+mcp__*"})).?;
            defer alloc.free(diagnostic);
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Sweep.run, .{});
}
