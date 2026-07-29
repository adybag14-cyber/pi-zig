//! Format tool calls and assistant messages for the terminal.
const std = @import("std");
const Io = std.Io;
const ansi = @import("ansi.zig");

/// When true, suppress terminal writes (used by unit tests to avoid pipe deadlock).
var silent: bool = false;

pub fn setSilent(v: bool) void {
    silent = v;
}

pub fn writeAll(io: Io, bytes: []const u8) !void {
    if (silent) return;
    // Prefer streaming stdout; fall back to debug print.
    Io.File.stdout().writeStreamingAll(io, bytes) catch {
        std.debug.print("{s}", .{bytes});
    };
}

pub fn printLine(io: Io, text: []const u8) !void {
    if (silent) return;
    try writeAll(io, text);
    try writeAll(io, "\n");
}

pub fn renderHeader(io: Io, version: []const u8, context_count: usize, skills_count: usize) !void {
    var buf: [512]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "{s}pi (pi-zig){s} coding agent {s}  context={d} skills={d}", .{
        ansi.bold,
        ansi.reset,
        version,
        context_count,
        skills_count,
    });
    try printLine(io, line);
}

pub fn renderToolCall(io: Io, name: []const u8, args: []const u8) !void {
    var tbuf: [128]u8 = undefined;
    const title = try ansi.toolTitle(name, &tbuf);
    try writeAll(io, title);
    try writeAll(io, " ");
    const preview = if (args.len > 120) args[0..120] else args;
    var mbuf: [160]u8 = undefined;
    const muted = try ansi.muted(preview, &mbuf);
    try printLine(io, muted);
}

pub fn renderToolResult(io: Io, name: []const u8, content: []const u8, is_error: bool) !void {
    _ = name;
    var buf: [96]u8 = undefined;
    if (is_error) {
        const s = try ansi.err("✗ tool error", &buf);
        try printLine(io, s);
    } else {
        const s = try ansi.success("✓ tool ok", &buf);
        try printLine(io, s);
    }
    const preview = if (content.len > 400) content[0..400] else content;
    try printLine(io, preview);
    if (content.len > 400) try printLine(io, "…");
}

pub fn renderAssistant(io: Io, text: []const u8) !void {
    if (text.len == 0) return;
    try printLine(io, text);
}

test "render helpers compile" {
    try std.testing.expect(ansi.bold.len > 0);
}
