//! Broken reparse leaves are present, not absent. Never follow unapproved links.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const cache = @import("cache.zig");
const junctions = @import("junctions.zig");
const Deadline = @import("deadline.zig").Deadline;
const Pin = struct { path: []const u8, status: []const u8 };
const Missing = struct { path: []const u8 };
const Audit = struct { pins: []Pin, mismatches: []Missing };
pub const State = enum { absent, present };
pub const Sink = struct {
    context: *anyopaque,
    write_fn: *const fn (*anyopaque, []const u8, []const u8, State) anyerror!void,
};

pub fn check(allocator: std.mem.Allocator, audit_path: []const u8, root: []const u8, plan: []const junctions.Plan,
    deadline: Deadline, sink: Sink) !void
{
    try junctions.validatePlan(plan, root);
    for (plan) |row| try junctions.check(allocator, row);
    const bytes = try files.readBounded(allocator, audit_path, 2 * 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(Audit, allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    var count: usize = 0;
    var present: usize = 0;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = seen.keyIterator();
        while (keys.next()) |key| allocator.free(key.*);
        seen.deinit(allocator);
    }
    for (parsed.value.pins) |pin| {
        if (!std.mem.eql(u8, pin.status, "platform_optional_absent")) continue;
        try one(allocator, root, plan, pin.path, deadline, sink, &seen, &count, &present);
    }
    for (parsed.value.mismatches) |missing| {
        try one(allocator, root, plan, missing.path, deadline, sink, &seen, &count, &present);
    }
    if (count != 84 or present != 0) return error.Original84AbsenceNegative;
}
fn one(allocator: std.mem.Allocator, root: []const u8, plan: []const junctions.Plan, relative_input: []const u8,
    deadline: Deadline, sink: Sink, seen: *std.StringHashMapUnmanaged(void), count: *usize, present: *usize) !void
{
    try deadline.normal();
    const relative = try cache.windowsRelative(allocator, relative_input);
    var transferred = false;
    errdefer if (!transferred) allocator.free(relative);
    const entry = try seen.getOrPut(allocator, relative);
    if (entry.found_existing) return error.DuplicateAbsencePath;
    transferred = true;
    const path = try files.join(allocator, root, relative);
    defer allocator.free(path);
    const resolved = try junctions.resolveCheckedPlan(allocator, plan, root, path);
    defer allocator.free(resolved);
    const state = try inspectPhysicalPath(allocator, resolved);
    count.* += 1;
    if (state == .present) present.* += 1;
    try sink.write_fn(sink.context, relative, resolved[root.len + 1..], state);
}

pub fn inspectPhysicalPath(allocator: std.mem.Allocator, path: []const u8) !State {
    try files.absolute(path);
    // Inspect each existing ancestor without traversing its reparse point. An
    // absent ancestor proves the leaf absent; AccessDenied/unknown is negative.
    var start: usize = 3;
    while (std.mem.indexOfScalarPos(u8, path, start, '\\')) |end| {
        const parent = try inspectLeaf(allocator, path[0..end], true);
        if (parent == .absent) return .absent;
        start = end + 1;
    }
    return inspectLeaf(allocator, path, false);
}
fn inspectLeaf(allocator: std.mem.Allocator, path: []const u8, parent: bool) !State {
    const utf8 = try std.fmt.allocPrint(allocator, "\\\\?\\{s}", .{path});
    defer allocator.free(utf8);
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(allocator, utf8);
    defer allocator.free(wide);
    const handle = w.CreateFileW(wide.ptr, 0, 1 | 2 | 4, null, w.open_existing,
        w.file_flag_open_reparse_point | w.file_flag_backup_semantics, null);
    if (handle == w.invalid) {
        const cause = w.GetLastError();
        if (cause == 2 or cause == 3) return .absent;
        return error.AbsenceUnverifiable;
    }
    defer _ = w.CloseHandle(handle);
    if (parent) {
        const tag = try files.requirePhysical(handle);
        if (tag.attributes & w.file_attribute_directory == 0) return error.AbsenceParentNotDirectory;
    }
    return .present;
}
