//! Exact Windows argv/environment construction, with no inherited environment.
const std = @import("std");
const w = @import("win32.zig");
pub const max_command_units = 32766;

pub fn serialize(allocator: std.mem.Allocator, argv: []const []const u8) ![:0]u16 {
    if (argv.len == 0) return error.EmptyCommand;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    for (argv, 0..) |arg, index| {
        if (std.mem.indexOfScalar(u8, arg, 0) != null) return error.CommandContainsNul;
        if (index != 0) try text.append(allocator, ' ');
        try text.append(allocator, '"');
        var slashes: usize = 0;
        for (arg) |byte| {
            if (byte == '\\') {
                slashes += 1;
                continue;
            }
            try text.appendNTimes(allocator, '\\', if (byte == '"') slashes * 2 + 1 else slashes);
            slashes = 0;
            try text.append(allocator, byte);
        }
        try text.appendNTimes(allocator, '\\', slashes * 2);
        try text.append(allocator, '"');
        // Bound before UTF-16 conversion too; valid UTF-8 consumes no fewer
        // bytes than its UTF-16 units. Avoid accepting unbounded input first.
        if (text.items.len > max_command_units * 3) return error.CommandTooLong;
    }
    const result = try std.unicode.utf8ToUtf16LeAllocZ(allocator, text.items);
    errdefer allocator.free(result);
    if (result.len > max_command_units) return error.CommandTooLong;
    return result;
}

pub fn requireRoundTrip(allocator: std.mem.Allocator, command: [:0]const u16, argv: []const []const u8) !void {
    var count: i32 = 0;
    const actual = w.CommandLineToArgvW(command.ptr, &count) orelse return error.CommandParseFailed;
    defer _ = w.LocalFree(@ptrCast(actual));
    if (count < 0 or @as(usize, @intCast(count)) != argv.len) return error.CommandRoundTripMismatch;
    for (argv, 0..) |arg, index| {
        const expected = try std.unicode.utf8ToUtf16LeAlloc(allocator, arg);
        defer allocator.free(expected);
        if (!std.mem.eql(u16, std.mem.span(actual[index]), expected)) return error.CommandRoundTripMismatch;
    }
}

pub const Pair = struct { key: []const u8, value: []const u8 };

pub fn environment(allocator: std.mem.Allocator, pairs: []const Pair) ![]u16 {
    if (pairs.len == 0 or pairs.len > 64) return error.EnvironmentEntryLimit;
    const sorted = try allocator.dupe(Pair, pairs);
    defer allocator.free(sorted);
    for (sorted) |pair| {
        if (pair.key.len == 0 or std.mem.indexOfAny(u8, pair.key, "=\x00") != null or
            std.mem.indexOfScalar(u8, pair.value, 0) != null) return error.InvalidEnvironmentEntry;
        // The approved allowlist keys are ASCII, so ASCII case folding is
        // exact for this environment; callers cannot inject arbitrary keys.
        for (pair.key) |byte| if (byte >= 0x80) return error.NonAsciiEnvironmentKey;
    }
    std.mem.sort(Pair, sorted, {}, struct {
        fn less(_: void, a: Pair, b: Pair) bool {
            return std.ascii.lessThanIgnoreCase(a.key, b.key);
        }
    }.less);
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    for (sorted, 0..) |pair, index| {
        if (index > 0 and std.ascii.eqlIgnoreCase(sorted[index - 1].key, pair.key))
            return error.DuplicateEnvironmentKey;
        const entry = try std.fmt.allocPrint(allocator, "{s}={s}", .{ pair.key, pair.value });
        defer allocator.free(entry);
        const wide = try std.unicode.utf8ToUtf16LeAlloc(allocator, entry);
        defer allocator.free(wide);
        if (wide.len > 32766 or out.items.len + wide.len + 2 > 65536) return error.EnvironmentBlockTooLarge;
        try out.appendSlice(allocator, wide);
        try out.append(allocator, 0);
    }
    try out.append(allocator, 0);
    return out.toOwnedSlice(allocator);
}
