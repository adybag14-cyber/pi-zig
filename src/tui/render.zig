//! Format tool calls and assistant messages for the terminal.
const std = @import("std");
const Io = std.Io;
const ansi = @import("ansi.zig");
const markdown = @import("markdown.zig");
const terminal_image = @import("terminal_image.zig");
const Theme = @import("../themes/theme.zig").Theme;

/// When true, suppress terminal writes (used by unit tests to avoid pipe deadlock).
var silent: bool = false;

pub const Palette = struct {
    accent_sgr: []const u8 = "36",
    error_sgr: []const u8 = "31",
    success_sgr: []const u8 = "32",
    muted_sgr: []const u8 = "90",
};

/// Set once during startup. The referenced theme must outlive terminal rendering.
var palette: Palette = .{};

pub fn setSilent(v: bool) void {
    silent = v;
}

pub fn setTheme(theme: *const Theme) void {
    palette = .{
        .accent_sgr = theme.accent_sgr,
        .error_sgr = theme.error_sgr,
        .success_sgr = theme.success_sgr,
        .muted_sgr = theme.muted_sgr,
    };
}

pub fn resetTheme() void {
    palette = .{};
}

pub fn activePalette() Palette {
    return palette;
}

pub fn style(buf: []u8, sgr: []const u8, text: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "\x1b[{s}m{s}{s}", .{ sgr, text, ansi.reset });
}

fn boldStyle(buf: []u8, sgr: []const u8, text: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}\x1b[{s}m{s}{s}", .{ ansi.bold, sgr, text, ansi.reset });
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
    var title_buf: [128]u8 = undefined;
    const title = try boldStyle(&title_buf, palette.accent_sgr, "pi (pi-zig)");
    var buf: [512]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "{s} coding agent {s}  context={d} skills={d}", .{
        title,
        version,
        context_count,
        skills_count,
    });
    try printLine(io, line);
}

pub fn renderToolCall(io: Io, name: []const u8, args: []const u8) !void {
    var title_buf: [256]u8 = undefined;
    const title = try boldStyle(&title_buf, palette.accent_sgr, name);
    try writeAll(io, title);
    try writeAll(io, " ");
    const preview = if (args.len > 120) args[0..120] else args;
    var muted_buf: [256]u8 = undefined;
    const muted = try style(&muted_buf, palette.muted_sgr, preview);
    try printLine(io, muted);
}

pub fn renderToolResult(io: Io, name: []const u8, content: []const u8, is_error: bool) !void {
    _ = name;
    var buf: [128]u8 = undefined;
    const status = if (is_error)
        try style(&buf, palette.error_sgr, "✗ tool error")
    else
        try style(&buf, palette.success_sgr, "✓ tool ok");
    try printLine(io, status);
    const preview = if (content.len > 400) content[0..400] else content;
    try printLine(io, preview);
    if (content.len > 400) try printLine(io, "…");
}

pub fn renderAssistant(io: Io, text: []const u8) !void {
    if (text.len == 0) return;
    try printLine(io, text);
}

fn activeMarkdownTheme() markdown.Theme {
    return .{
        .heading_sgr = palette.accent_sgr,
        .link_sgr = palette.accent_sgr,
        .list_bullet_sgr = palette.accent_sgr,
        .code_border_sgr = palette.muted_sgr,
        .quote_border_sgr = palette.muted_sgr,
        .hr_sgr = palette.muted_sgr,
    };
}

/// Render a completed assistant response using the native width-aware Markdown
/// pipeline. Print/JSON modes intentionally remain byte-oriented; this function
/// is for the interactive terminal where ANSI styling and OSC hyperlinks belong.
pub fn renderAssistantMarkdown(
    gpa: std.mem.Allocator,
    io: Io,
    text: []const u8,
    width: usize,
    capabilities: terminal_image.TerminalCapabilities,
) !void {
    return renderAssistantMarkdownPadded(gpa, io, text, width, capabilities, 0);
}

/// Render completed assistant Markdown with the original configurable output
/// padding. Width is reduced before wrapping so indentation never pushes a line
/// beyond the terminal's visible cell budget.
pub fn renderAssistantMarkdownPadded(
    gpa: std.mem.Allocator,
    io: Io,
    text: []const u8,
    width: usize,
    capabilities: terminal_image.TerminalCapabilities,
    padding: u8,
) !void {
    if (text.len == 0) return;
    const left: usize = @min(@as(usize, padding), @as(usize, 8));
    const content_width = @max(@as(usize, 1), width -| left);
    var rendered = try markdown.render(gpa, text, content_width, activeMarkdownTheme(), .{}, capabilities);
    defer rendered.deinit(gpa);
    if (left == 0) {
        for (rendered.lines) |line| try printLine(io, line);
        return;
    }
    var prefix_buffer: [8]u8 = @splat(' ');
    const prefix = prefix_buffer[0..left];
    for (rendered.lines) |line| {
        try writeAll(io, prefix);
        try printLine(io, line);
    }
}

test "renderer accepts active custom theme palette" {
    const custom = Theme{
        .accent_sgr = "38;2;1;2;3",
        .error_sgr = "38;5;196",
        .success_sgr = "38;5;46",
        .muted_sgr = "38;5;244",
    };
    setTheme(&custom);
    defer resetTheme();
    const active = activePalette();
    try std.testing.expectEqualStrings("38;2;1;2;3", active.accent_sgr);
    var buf: [64]u8 = undefined;
    const rendered = try style(&buf, active.accent_sgr, "pi");
    try std.testing.expect(std.mem.startsWith(u8, rendered, "\x1b[38;2;1;2;3m"));
    try std.testing.expect(std.mem.endsWith(u8, rendered, ansi.reset));
}

test "assistant Markdown renderer accepts terminal capabilities and active palette" {
    const custom = Theme{
        .accent_sgr = "38;2;1;2;3",
        .error_sgr = "31",
        .success_sgr = "32",
        .muted_sgr = "38;5;244",
    };
    setTheme(&custom);
    defer resetTheme();
    setSilent(true);
    defer setSilent(false);
    try renderAssistantMarkdown(std.testing.allocator, std.testing.io, "## Result\n- [x] complete", 24, .{ .hyperlinks = true });
}
