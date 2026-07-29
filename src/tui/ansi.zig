//! ANSI color helpers for terminal output.
const std = @import("std");

pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";
pub const red = "\x1b[31m";
pub const green = "\x1b[32m";
pub const yellow = "\x1b[33m";
pub const blue = "\x1b[34m";
pub const magenta = "\x1b[35m";
pub const cyan = "\x1b[36m";
pub const white = "\x1b[37m";

pub fn paint(comptime color: []const u8, text: []const u8, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}{s}{s}", .{ color, text, reset });
}

pub fn toolTitle(name: []const u8, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}{s}{s}{s}", .{ bold, cyan, name, reset });
}

pub fn success(text: []const u8, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}{s}{s}", .{ green, text, reset });
}

pub fn err(text: []const u8, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}{s}{s}", .{ red, text, reset });
}

pub fn muted(text: []const u8, buf: []u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "{s}{s}{s}", .{ dim, text, reset });
}

test "ansi paint wraps codes" {
    var buf: [64]u8 = undefined;
    const s = try paint(green, "ok", &buf);
    try std.testing.expect(std.mem.indexOf(u8, s, "ok") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, reset) != null);
}
