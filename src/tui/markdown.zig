//! Width-aware terminal Markdown renderer.
//!
//! This is a native, dependency-free renderer for the Markdown constructs Pi
//! emits most often. It deliberately keeps parsing and terminal layout together:
//! inline ANSI/OSC sequences have zero visible width, image protocol lines are
//! never split, fenced blocks remain stable while streaming, and tables fall back
//! gracefully when the viewport cannot fit their borders.
const std = @import("std");
const terminal_image = @import("terminal_image.zig");
const latex = @import("latex.zig");
const terminal_text = @import("terminal_text.zig");

const reset = "\x1b[0m";

pub const Theme = struct {
    heading_sgr: []const u8 = "1;36",
    link_sgr: []const u8 = "4;36",
    link_url_sgr: []const u8 = "90",
    code_sgr: []const u8 = "33",
    code_block_sgr: []const u8 = "38;5;252",
    code_border_sgr: []const u8 = "90",
    quote_sgr: []const u8 = "3;90",
    quote_border_sgr: []const u8 = "90",
    hr_sgr: []const u8 = "90",
    list_bullet_sgr: []const u8 = "36",
    bold_sgr: []const u8 = "1",
    italic_sgr: []const u8 = "3",
    strikethrough_sgr: []const u8 = "9",
    underline_sgr: []const u8 = "4",
    code_block_indent: []const u8 = "  ",
};

pub const Options = struct {
    padding_x: usize = 0,
    padding_y: usize = 0,
    preserve_ordered_list_markers: bool = false,
    preserve_backslash_escapes: bool = false,
    render_latex_delimiters: bool = true,
    pad_to_width: bool = false,
};

pub const Rendered = struct {
    lines: [][]u8,

    pub fn deinit(self: *Rendered, gpa: std.mem.Allocator) void {
        for (self.lines) |line| gpa.free(line);
        gpa.free(self.lines);
        self.* = undefined;
    }
};

fn appendStyled(writer: *std.Io.Writer, sgr: []const u8, text: []const u8) !void {
    if (sgr.len == 0) return writer.writeAll(text);
    try writer.writeAll("\x1b[");
    try writer.writeAll(sgr);
    try writer.writeAll("m");
    try writer.writeAll(text);
    try writer.writeAll(reset);
}

fn styledAlloc(gpa: std.mem.Allocator, sgr: []const u8, text: []const u8) anyerror![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try appendStyled(&out.writer, sgr, text);
    return out.toOwnedSlice();
}

fn replaceTabs(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (input) |byte| {
        if (byte == '\t') try out.appendSlice(gpa, "   ") else try out.append(gpa, byte);
    }
    return out.toOwnedSlice(gpa);
}

fn escapeEnd(bytes: []const u8, start: usize) ?usize {
    const sequence = terminal_text.extractSequence(bytes, start) orelse return null;
    return sequence.end;
}

pub fn visibleWidth(bytes: []const u8) usize {
    return terminal_text.visibleWidth(bytes);
}

fn trimTrailingSpaces(bytes: []const u8) []const u8 {
    var end = bytes.len;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t' or bytes[end - 1] == '\r')) : (end -= 1) {}
    return bytes[0..end];
}

fn recomputeLastSpace(bytes: []const u8) ?usize {
    var last: ?usize = null;
    var index: usize = 0;
    while (index < bytes.len) {
        if (bytes[index] == 0x1b) {
            if (escapeEnd(bytes, index)) |end| {
                index = end;
                continue;
            }
        }
        if (bytes[index] == ' ' or bytes[index] == '\t') last = index;
        const sequence_length = std.unicode.utf8ByteSequenceLength(bytes[index]) catch 1;
        index += @min(sequence_length, bytes.len - index);
    }
    return last;
}

fn pushCurrentLine(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), current: *std.ArrayList(u8)) !void {
    const trimmed = trimTrailingSpaces(current.items);
    try lines.append(gpa, try gpa.dupe(u8, trimmed));
    current.clearRetainingCapacity();
}

/// Wrap visible terminal cells while retaining CSI, OSC 8, and graphics control
/// sequences byte-for-byte. Long unbroken tokens are split at UTF-8 boundaries.
pub fn wrapAnsi(gpa: std.mem.Allocator, text: []const u8, width_raw: usize) ![][]u8 {
    const width = @max(@as(usize, 1), width_raw);
    var lines: std.ArrayList([]u8) = .empty;
    errdefer {
        for (lines.items) |line| gpa.free(line);
        lines.deinit(gpa);
    }
    if (terminal_image.isImageLine(text)) {
        try lines.append(gpa, try gpa.dupe(u8, text));
        return lines.toOwnedSlice(gpa);
    }

    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(gpa);
    var current_width: usize = 0;
    var last_space: ?usize = null;
    var index: usize = 0;
    while (index < text.len) {
        if (text[index] == 0x1b) {
            if (escapeEnd(text, index)) |end| {
                try current.appendSlice(gpa, text[index..end]);
                index = end;
                continue;
            }
        }
        if (text[index] == '\n') {
            try pushCurrentLine(gpa, &lines, &current);
            current_width = 0;
            last_space = null;
            index += 1;
            continue;
        }
        if (text[index] == '\r') {
            index += 1;
            continue;
        }
        const cluster = terminal_text.nextCluster(text, index) orelse break;
        const is_space = cluster.bytes.len == 1 and (cluster.bytes[0] == ' ' or cluster.bytes[0] == '\t');

        if (!is_space and current_width + cluster.width > width and current.items.len > 0) {
            if (last_space) |space_index| {
                const prefix = trimTrailingSpaces(current.items[0..space_index]);
                try lines.append(gpa, try gpa.dupe(u8, prefix));
                const remainder_start = space_index + 1;
                const remainder = try gpa.dupe(u8, current.items[remainder_start..]);
                current.clearRetainingCapacity();
                defer gpa.free(remainder);
                try current.appendSlice(gpa, remainder);
                current_width = visibleWidth(current.items);
                last_space = recomputeLastSpace(current.items);
            } else {
                try pushCurrentLine(gpa, &lines, &current);
                current_width = 0;
                last_space = null;
            }
        }
        if (is_space and current.items.len == 0) {
            index = cluster.end;
            continue;
        }
        if (is_space) last_space = current.items.len;
        try current.appendSlice(gpa, cluster.bytes);
        current_width += cluster.width;
        index = cluster.end;
    }
    if (current.items.len > 0 or lines.items.len == 0) try pushCurrentLine(gpa, &lines, &current);
    return lines.toOwnedSlice(gpa);
}

fn findUnescaped(haystack: []const u8, needle: []const u8, start: usize) ?usize {
    if (needle.len == 0 or start > haystack.len) return null;
    var cursor = start;
    while (cursor <= haystack.len) {
        const relative = std.mem.indexOf(u8, haystack[cursor..], needle) orelse return null;
        const found = cursor + relative;
        var backslashes: usize = 0;
        var probe = found;
        while (probe > 0 and haystack[probe - 1] == '\\') {
            backslashes += 1;
            probe -= 1;
        }
        if (backslashes % 2 == 0) return found;
        cursor = found + needle.len;
    }
    return null;
}

fn appendLink(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    label_raw: []const u8,
    href: []const u8,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) anyerror!void {
    const label = try renderInline(gpa, label_raw, theme, options, capabilities);
    defer gpa.free(label);
    const styled_label = try styledAlloc(gpa, theme.link_sgr, label);
    defer gpa.free(styled_label);
    if (capabilities.hyperlinks) {
        const linked = try terminal_image.hyperlink(gpa, styled_label, href);
        defer gpa.free(linked);
        try writer.writeAll(linked);
        return;
    }
    try writer.writeAll(styled_label);
    const comparison = if (std.mem.startsWith(u8, href, "mailto:")) href[7..] else href;
    if (!std.mem.eql(u8, label_raw, href) and !std.mem.eql(u8, label_raw, comparison)) {
        const suffix = try std.fmt.allocPrint(gpa, " ({s})", .{href});
        defer gpa.free(suffix);
        try appendStyled(writer, theme.link_url_sgr, suffix);
    }
}

fn appendInlineStyled(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    inner_raw: []const u8,
    sgr: []const u8,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) anyerror!void {
    const inner = try renderInline(gpa, inner_raw, theme, options, capabilities);
    defer gpa.free(inner);
    try appendStyled(writer, sgr, inner);
}

fn looksLikeInlineLatex(text: []const u8) bool {
    return std.mem.indexOfScalar(u8, text, '\\') != null or
        std.mem.indexOfAny(u8, text, "_^=+*/<>[]|") != null;
}

fn startsIdentifier(value: []const u8) bool {
    return value.len > 0 and (std.ascii.isAlphabetic(value[0]) or value[0] == '_');
}

fn looksLikeEnvironmentVariable(value: []const u8) bool {
    if (value.len == 0 or (!std.ascii.isUpper(value[0]) and value[0] != '_')) return false;
    for (value) |byte| {
        if (!std.ascii.isUpper(byte) and !std.ascii.isDigit(byte) and byte != '_') return false;
    }
    return true;
}

fn looksLikeShellVariablePrefix(value: []const u8) bool {
    if (value.len == 0 or (!std.ascii.isUpper(value[0]) and value[0] != '_')) return false;
    var end: usize = 1;
    while (end < value.len and (std.ascii.isUpper(value[end]) or std.ascii.isDigit(value[end]) or value[end] == '_')) end += 1;
    return end == value.len or (end < value.len and (value[end] == '/' or value[end] == ':' or value[end] == '.'));
}

fn appendLatexOrRaw(
    gpa: std.mem.Allocator,
    writer: *std.Io.Writer,
    source: []const u8,
    inner: []const u8,
    display: bool,
) anyerror!void {
    if (try latex.renderLatex(gpa, inner, .{ .display = display })) |rendered| {
        defer gpa.free(rendered);
        try writer.writeAll(rendered);
    } else {
        try writer.writeAll(source);
    }
}

const InlineLatex = struct {
    raw_end: usize,
    inner: []const u8,
    pending: bool,
};

fn parseInlineLatex(source: []const u8, index: usize) ?InlineLatex {
    var opening: []const u8 = "";
    var closing: []const u8 = "";
    if (std.mem.startsWith(u8, source[index..], "$$")) {
        opening = "$$";
        closing = "$$";
    } else if (std.mem.startsWith(u8, source[index..], "\\(")) {
        opening = "\\(";
        closing = "\\)";
    } else if (std.mem.startsWith(u8, source[index..], "\\[")) {
        opening = "\\[";
        closing = "\\]";
    } else if (source[index] == '$' and (index + 1 >= source.len or !std.ascii.isWhitespace(source[index + 1]))) {
        opening = "$";
        closing = "$";
    } else return null;

    const content_start = index + opening.len;
    const close = findUnescaped(source, closing, content_start) orelse {
        const pending_source = source[content_start..];
        if (opening[0] == '\\' or looksLikeInlineLatex(pending_source)) return .{
            .raw_end = source.len,
            .inner = pending_source,
            .pending = true,
        };
        return null;
    };
    const inner = source[content_start..close];
    if (inner.len == 0 or std.mem.indexOfScalar(u8, inner, '\n') != null) return null;
    if (std.mem.eql(u8, opening, "$")) {
        if (std.ascii.isWhitespace(inner[inner.len - 1])) return null;
        const after = source[close + closing.len ..];
        if (after.len > 0 and std.ascii.isDigit(after[0])) return null;
        if (std.mem.indexOfScalar(u8, inner, '`') != null) return null;
        if ((looksLikeEnvironmentVariable(inner) and startsIdentifier(after)) or looksLikeShellVariablePrefix(inner)) return null;
    }
    return .{ .raw_end = close + closing.len, .inner = inner, .pending = false };
}

/// Render CommonMark-style inline constructs without requiring a dynamic parser.
pub fn renderInline(
    gpa: std.mem.Allocator,
    source: []const u8,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var index: usize = 0;
    while (index < source.len) {
        if (options.render_latex_delimiters) {
            if (parseInlineLatex(source, index)) |math| {
                if (math.pending) {
                    try out.writer.writeAll(source[index..math.raw_end]);
                    break;
                }
                try appendLatexOrRaw(gpa, &out.writer, source[index..math.raw_end], math.inner, false);
                index = math.raw_end;
                continue;
            }
        }

        // Backslash escapes.
        if (source[index] == '\\' and index + 1 < source.len) {
            const escaped = source[index + 1];
            if (std.mem.indexOfScalar(u8, "\\`*{}[]()#+-.!_>~|$", escaped) != null) {
                if (options.preserve_backslash_escapes) try out.writer.writeByte('\\');
                try out.writer.writeByte(escaped);
                index += 2;
                continue;
            }
        }

        // Images become explicit text fallbacks at the inline layer.
        if (std.mem.startsWith(u8, source[index..], "![")) {
            if (std.mem.indexOf(u8, source[index + 2 ..], "](")) |middle_rel| {
                const middle = index + 2 + middle_rel;
                if (findUnescaped(source, ")", middle + 2)) |close| {
                    try out.writer.writeAll("[Image: ");
                    try out.writer.writeAll(source[index + 2 .. middle]);
                    if (close > middle + 2) {
                        try out.writer.writeAll(" (");
                        try out.writer.writeAll(source[middle + 2 .. close]);
                        try out.writer.writeByte(')');
                    }
                    try out.writer.writeByte(']');
                    index = close + 1;
                    continue;
                }
            }
        }

        // Links.
        if (source[index] == '[') {
            if (std.mem.indexOf(u8, source[index + 1 ..], "](")) |middle_rel| {
                const middle = index + 1 + middle_rel;
                if (findUnescaped(source, ")", middle + 2)) |close| {
                    try appendLink(gpa, &out.writer, source[index + 1 .. middle], source[middle + 2 .. close], theme, options, capabilities);
                    index = close + 1;
                    continue;
                }
            }
        }

        // Autolinks and inline HTML. URLs/emails are linked; other tags stay text.
        if (source[index] == '<') {
            if (findUnescaped(source, ">", index + 1)) |close| {
                const body = source[index + 1 .. close];
                if (std.mem.startsWith(u8, body, "http://") or std.mem.startsWith(u8, body, "https://")) {
                    try appendLink(gpa, &out.writer, body, body, theme, options, capabilities);
                } else if (std.mem.indexOfScalar(u8, body, '@') != null and std.mem.indexOfScalar(u8, body, ' ') == null) {
                    const href = try std.fmt.allocPrint(gpa, "mailto:{s}", .{body});
                    defer gpa.free(href);
                    try appendLink(gpa, &out.writer, body, href, theme, options, capabilities);
                } else {
                    try out.writer.writeAll(source[index .. close + 1]);
                }
                index = close + 1;
                continue;
            }
        }

        // Code spans support arbitrary backtick runs.
        if (source[index] == '`') {
            var run_end = index;
            while (run_end < source.len and source[run_end] == '`') : (run_end += 1) {}
            const delimiter = source[index..run_end];
            if (findUnescaped(source, delimiter, run_end)) |close| {
                var code = source[run_end..close];
                if (code.len >= 2 and code[0] == ' ' and code[code.len - 1] == ' ' and std.mem.indexOfNone(u8, code, " ") != null) code = code[1 .. code.len - 1];
                try appendStyled(&out.writer, theme.code_sgr, code);
                index = close + delimiter.len;
                continue;
            }
        }

        // Strong emphasis.
        if (std.mem.startsWith(u8, source[index..], "**") or std.mem.startsWith(u8, source[index..], "__")) {
            const delimiter = source[index .. index + 2];
            if (findUnescaped(source, delimiter, index + 2)) |close| {
                if (close > index + 2) {
                    try appendInlineStyled(gpa, &out.writer, source[index + 2 .. close], theme.bold_sgr, theme, options, capabilities);
                    index = close + 2;
                    continue;
                }
            }
        }

        // Strict strikethrough requires non-space boundaries.
        if (std.mem.startsWith(u8, source[index..], "~~")) {
            if (findUnescaped(source, "~~", index + 2)) |close| {
                const inner = source[index + 2 .. close];
                if (inner.len > 0 and !std.ascii.isWhitespace(inner[0]) and !std.ascii.isWhitespace(inner[inner.len - 1])) {
                    try appendInlineStyled(gpa, &out.writer, inner, theme.strikethrough_sgr, theme, options, capabilities);
                    index = close + 2;
                    continue;
                }
            }
        }

        // Emphasis, avoiding intraword underscores.
        if (source[index] == '*' or source[index] == '_') {
            const delimiter = source[index];
            const intraword_underscore = delimiter == '_' and index > 0 and index + 1 < source.len and
                std.ascii.isAlphanumeric(source[index - 1]) and std.ascii.isAlphanumeric(source[index + 1]);
            if (!intraword_underscore) {
                const needle = source[index .. index + 1];
                if (findUnescaped(source, needle, index + 1)) |close| {
                    if (close > index + 1) {
                        try appendInlineStyled(gpa, &out.writer, source[index + 1 .. close], theme.italic_sgr, theme, options, capabilities);
                        index = close + 1;
                        continue;
                    }
                }
            }
        }

        const sequence_length = std.unicode.utf8ByteSequenceLength(source[index]) catch 1;
        const end = @min(source.len, index + sequence_length);
        try out.writer.writeAll(source[index..end]);
        index = end;
    }
    return out.toOwnedSlice();
}

const Fence = struct {
    marker: u8,
    count: usize,
    language: []const u8,
};

fn leadingSpaces(line: []const u8) usize {
    var count: usize = 0;
    while (count < line.len and count < 4 and line[count] == ' ') : (count += 1) {}
    return count;
}

fn parseFence(line: []const u8) ?Fence {
    const spaces = leadingSpaces(line);
    if (spaces > 3 or spaces >= line.len) return null;
    const marker = line[spaces];
    if (marker != '`' and marker != '~') return null;
    var end = spaces;
    while (end < line.len and line[end] == marker) : (end += 1) {}
    if (end - spaces < 3) return null;
    return .{
        .marker = marker,
        .count = end - spaces,
        .language = std.mem.trim(u8, line[end..], " \t\r"),
    };
}

fn isClosingFence(line: []const u8, fence: Fence) bool {
    const spaces = leadingSpaces(line);
    if (spaces > 3 or spaces >= line.len or line[spaces] != fence.marker) return false;
    var end = spaces;
    while (end < line.len and line[end] == fence.marker) : (end += 1) {}
    return end - spaces >= fence.count and std.mem.trim(u8, line[end..], " \t\r").len == 0;
}

const Heading = struct { depth: usize, text: []const u8 };

fn parseHeading(line: []const u8) ?Heading {
    const spaces = leadingSpaces(line);
    if (spaces > 3) return null;
    var end = spaces;
    while (end < line.len and end - spaces < 6 and line[end] == '#') : (end += 1) {}
    const depth = end - spaces;
    if (depth == 0 or (end < line.len and line[end] != ' ' and line[end] != '\t')) return null;
    var text = std.mem.trim(u8, line[end..], " \t\r");
    while (text.len > 0 and text[text.len - 1] == '#') text = std.mem.trimEnd(u8, text[0 .. text.len - 1], " \t");
    return .{ .depth = depth, .text = text };
}

fn isHorizontalRule(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len < 3) return false;
    const marker = trimmed[0];
    if (marker != '-' and marker != '*' and marker != '_') return false;
    var count: usize = 0;
    for (trimmed) |byte| {
        if (byte == marker) count += 1 else if (byte != ' ' and byte != '\t') return false;
    }
    return count >= 3;
}

fn quoteContent(line: []const u8) ?[]const u8 {
    const spaces = leadingSpaces(line);
    if (spaces > 3 or spaces >= line.len or line[spaces] != '>') return null;
    var start = spaces + 1;
    if (start < line.len and line[start] == ' ') start += 1;
    return line[start..];
}

const ListMarker = struct {
    leading: usize,
    ordered: bool,
    source_marker: []const u8,
    number: usize,
    body_start: usize,
};

fn parseListMarker(line: []const u8) ?ListMarker {
    var cursor: usize = 0;
    while (cursor < line.len and line[cursor] == ' ') : (cursor += 1) {}
    if (cursor >= line.len) return null;
    const marker_start = cursor;
    if (line[cursor] == '-' or line[cursor] == '+' or line[cursor] == '*') {
        cursor += 1;
        if (cursor >= line.len or (line[cursor] != ' ' and line[cursor] != '\t')) return null;
        while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) : (cursor += 1) {}
        return .{ .leading = marker_start, .ordered = false, .source_marker = line[marker_start .. marker_start + 1], .number = 0, .body_start = cursor };
    }
    if (!std.ascii.isDigit(line[cursor])) return null;
    var digits: usize = 0;
    var number: usize = 0;
    while (cursor < line.len and std.ascii.isDigit(line[cursor]) and digits < 9) : ({
        cursor += 1;
        digits += 1;
    }) {
        number = number * 10 + (line[cursor] - '0');
    }
    if (digits == 0 or cursor >= line.len or (line[cursor] != '.' and line[cursor] != ')')) return null;
    cursor += 1;
    if (cursor >= line.len or (line[cursor] != ' ' and line[cursor] != '\t')) return null;
    const marker_end = cursor;
    while (cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) : (cursor += 1) {}
    return .{ .leading = marker_start, .ordered = true, .source_marker = line[marker_start..marker_end], .number = number, .body_start = cursor };
}

fn isTableSeparator(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r|");
    if (trimmed.len == 0) return false;
    var cells = std.mem.splitScalar(u8, trimmed, '|');
    var count: usize = 0;
    while (cells.next()) |raw| {
        var cell = std.mem.trim(u8, raw, " \t");
        if (cell.len > 0 and cell[0] == ':') cell = cell[1..];
        if (cell.len > 0 and cell[cell.len - 1] == ':') cell = cell[0 .. cell.len - 1];
        cell = std.mem.trim(u8, cell, " \t");
        if (cell.len < 3) return false;
        for (cell) |byte| if (byte != '-') return false;
        count += 1;
    }
    return count > 0;
}

fn splitTableCells(gpa: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var trimmed = std.mem.trim(u8, line, " \t\r");
    if (trimmed.len > 0 and trimmed[0] == '|') trimmed = trimmed[1..];
    if (trimmed.len > 0 and trimmed[trimmed.len - 1] == '|') trimmed = trimmed[0 .. trimmed.len - 1];
    var cells: std.ArrayList([]const u8) = .empty;
    errdefer cells.deinit(gpa);
    var iterator = std.mem.splitScalar(u8, trimmed, '|');
    while (iterator.next()) |cell| try cells.append(gpa, std.mem.trim(u8, cell, " \t"));
    return cells.toOwnedSlice(gpa);
}

fn isBlockStart(lines: []const []const u8, index: usize) bool {
    if (index >= lines.len) return false;
    const line = lines[index];
    if (std.mem.trim(u8, line, " \t\r").len == 0) return true;
    if (parseFence(line) != null or parseHeading(line) != null or isHorizontalRule(line) or quoteContent(line) != null or parseListMarker(line) != null) return true;
    return index + 1 < lines.len and std.mem.indexOfScalar(u8, line, '|') != null and isTableSeparator(lines[index + 1]);
}

fn appendOwned(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), line: []u8) !void {
    errdefer gpa.free(line);
    try lines.append(gpa, line);
}

fn appendDuped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), line: []const u8) !void {
    return appendOwned(gpa, lines, try gpa.dupe(u8, line));
}

fn appendBlank(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8)) !void {
    if (lines.items.len > 0 and lines.items[lines.items.len - 1].len == 0) return;
    try appendDuped(gpa, lines, "");
}

fn appendWrapped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), text: []const u8, width: usize) !void {
    const wrapped = try wrapAnsi(gpa, text, width);
    defer gpa.free(wrapped);
    for (wrapped) |line| try lines.append(gpa, line);
}

fn repeatUtf8(gpa: std.mem.Allocator, glyph: []const u8, count: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, glyph.len * count);
    var index: usize = 0;
    while (index < count) : (index += 1) try out.appendSlice(gpa, glyph);
    return out.toOwnedSlice(gpa);
}

fn makeBorder(gpa: std.mem.Allocator, left: []const u8, joiner: []const u8, right: []const u8, widths: []const usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(left);
    for (widths, 0..) |width, index| {
        if (index > 0) try out.writer.writeAll(joiner);
        const rule = try repeatUtf8(gpa, "─", width + 2);
        defer gpa.free(rule);
        try out.writer.writeAll(rule);
    }
    try out.writer.writeAll(right);
    return out.toOwnedSlice();
}

fn renderTableRow(
    gpa: std.mem.Allocator,
    output: *std.ArrayList([]u8),
    cells: []const []const u8,
    widths: []const usize,
    header: bool,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) !void {
    const count = widths.len;
    const wrapped_cells = try gpa.alloc([][]u8, count);
    defer gpa.free(wrapped_cells);
    var initialized: usize = 0;
    defer {
        for (wrapped_cells[0..initialized]) |wrapped| {
            for (wrapped) |line| gpa.free(line);
            gpa.free(wrapped);
        }
    }
    var max_lines: usize = 1;
    for (0..count) |column| {
        const raw = if (column < cells.len) cells[column] else "";
        const rendered_inline = try renderInline(gpa, raw, theme, options, capabilities);
        defer gpa.free(rendered_inline);
        const displayed = if (header) try styledAlloc(gpa, theme.bold_sgr, rendered_inline) else try gpa.dupe(u8, rendered_inline);
        defer gpa.free(displayed);
        wrapped_cells[column] = try wrapAnsi(gpa, displayed, widths[column]);
        initialized += 1;
        max_lines = @max(max_lines, wrapped_cells[column].len);
    }

    for (0..max_lines) |line_index| {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try out.writer.writeAll("│ ");
        for (0..count) |column| {
            if (column > 0) try out.writer.writeAll(" │ ");
            const cell_line = if (line_index < wrapped_cells[column].len) wrapped_cells[column][line_index] else "";
            try out.writer.writeAll(cell_line);
            const missing = widths[column] -| visibleWidth(cell_line);
            try out.writer.splatByteAll(' ', missing);
        }
        try out.writer.writeAll(" │");
        try appendOwned(gpa, output, try out.toOwnedSlice());
    }
}

fn renderTable(
    gpa: std.mem.Allocator,
    output: *std.ArrayList([]u8),
    source_lines: []const []const u8,
    start: usize,
    width: usize,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) !usize {
    const header = try splitTableCells(gpa, source_lines[start]);
    defer gpa.free(header);
    const column_count = header.len;
    if (column_count == 0) return start + 1;

    var end = start + 2;
    while (end < source_lines.len) : (end += 1) {
        const trimmed = std.mem.trim(u8, source_lines[end], " \t\r");
        if (trimmed.len == 0 or std.mem.indexOfScalar(u8, trimmed, '|') == null) break;
    }

    const border_overhead = 3 * column_count + 1;
    if (width <= border_overhead or width - border_overhead < column_count) {
        for (source_lines[start..end]) |line| try appendWrapped(gpa, output, line, width);
        return end;
    }

    const widths = try gpa.alloc(usize, column_count);
    defer gpa.free(widths);
    @memset(widths, 1);
    for (header, 0..) |cell, column| {
        const rendered_inline = try renderInline(gpa, cell, theme, options, capabilities);
        defer gpa.free(rendered_inline);
        widths[column] = @max(@as(usize, 1), visibleWidth(rendered_inline));
    }
    var row_index = start + 2;
    while (row_index < end) : (row_index += 1) {
        const row = try splitTableCells(gpa, source_lines[row_index]);
        defer gpa.free(row);
        for (row, 0..) |cell, column| {
            if (column >= column_count) break;
            const rendered_inline = try renderInline(gpa, cell, theme, options, capabilities);
            defer gpa.free(rendered_inline);
            widths[column] = @max(widths[column], @min(@as(usize, 40), visibleWidth(rendered_inline)));
        }
    }
    const available_cells = width - border_overhead;
    var total: usize = 0;
    for (widths) |column_width| total += column_width;
    while (total > available_cells) {
        var widest_index: ?usize = null;
        var widest: usize = 1;
        for (widths, 0..) |column_width, column| {
            if (column_width > widest) {
                widest = column_width;
                widest_index = column;
            }
        }
        const column = widest_index orelse break;
        widths[column] -= 1;
        total -= 1;
    }
    while (total < available_cells) {
        var grew = false;
        for (widths) |*column_width| {
            if (total >= available_cells) break;
            column_width.* += 1;
            total += 1;
            grew = true;
        }
        if (!grew) break;
    }

    const top = try makeBorder(gpa, "┌", "┬", "┐", widths);
    try appendOwned(gpa, output, top);
    try renderTableRow(gpa, output, header, widths, true, theme, options, capabilities);
    const separator = try makeBorder(gpa, "├", "┼", "┤", widths);
    try appendOwned(gpa, output, separator);
    row_index = start + 2;
    while (row_index < end) : (row_index += 1) {
        const row = try splitTableCells(gpa, source_lines[row_index]);
        defer gpa.free(row);
        try renderTableRow(gpa, output, row, widths, false, theme, options, capabilities);
        if (row_index + 1 < end) {
            const divider = try makeBorder(gpa, "├", "┼", "┤", widths);
            try appendOwned(gpa, output, divider);
        }
    }
    const bottom = try makeBorder(gpa, "└", "┴", "┘", widths);
    try appendOwned(gpa, output, bottom);
    return end;
}

fn renderLatexBlock(
    gpa: std.mem.Allocator,
    output: *std.ArrayList([]u8),
    source_lines: []const []const u8,
    start: usize,
    options: Options,
) anyerror!?usize {
    if (!options.render_latex_delimiters or start >= source_lines.len) return null;
    const line = source_lines[start];
    const leading = leadingSpaces(line);
    if (leading > 3) return null;
    const candidate = line[leading..];
    var opening: []const u8 = "";
    var closing: []const u8 = "";
    if (std.mem.startsWith(u8, candidate, "$$")) {
        opening = "$$";
        closing = "$$";
    } else if (std.mem.startsWith(u8, candidate, "\\[")) {
        opening = "\\[";
        closing = "\\]";
    } else return null;

    var content: std.Io.Writer.Allocating = .init(gpa);
    defer content.deinit();
    var raw: std.ArrayList([]const u8) = .empty;
    defer raw.deinit(gpa);
    try raw.append(gpa, line);

    const first_content = candidate[opening.len..];
    if (findUnescaped(first_content, closing, 0)) |close| {
        if (std.mem.trim(u8, first_content[close + closing.len ..], " \t\r").len != 0) return null;
        try content.writer.writeAll(first_content[0..close]);
        const math = std.mem.trim(u8, content.written(), " \t\r\n");
        if (math.len == 0) return null;
        if (try latex.renderLatex(gpa, math, .{ .display = true })) |rendered| {
            defer gpa.free(rendered);
            var iterator = std.mem.splitScalar(u8, rendered, '\n');
            while (iterator.next()) |rendered_line| try appendDuped(gpa, output, rendered_line);
        } else {
            for (raw.items) |raw_line| try appendDuped(gpa, output, raw_line);
        }
        return start + 1;
    }

    if (first_content.len > 0) try content.writer.writeAll(first_content);
    var index = start + 1;
    while (index < source_lines.len) : (index += 1) {
        const current = source_lines[index];
        try raw.append(gpa, current);
        if (findUnescaped(current, closing, 0)) |close| {
            if (std.mem.trim(u8, current[close + closing.len ..], " \t\r").len != 0) return null;
            if (content.written().len > 0) try content.writer.writeByte('\n');
            try content.writer.writeAll(current[0..close]);
            const math = std.mem.trim(u8, content.written(), " \t\r\n");
            if (math.len == 0) return null;
            if (try latex.renderLatex(gpa, math, .{ .display = true })) |rendered| {
                defer gpa.free(rendered);
                var iterator = std.mem.splitScalar(u8, rendered, '\n');
                while (iterator.next()) |rendered_line| try appendDuped(gpa, output, rendered_line);
            } else {
                for (raw.items) |raw_line| try appendDuped(gpa, output, raw_line);
            }
            return index + 1;
        }
        if (content.written().len > 0) try content.writer.writeByte('\n');
        try content.writer.writeAll(current);
    }
    for (raw.items) |raw_line| try appendDuped(gpa, output, raw_line);
    return source_lines.len;
}

fn renderBlocks(
    gpa: std.mem.Allocator,
    output: *std.ArrayList([]u8),
    source_lines: []const []const u8,
    width: usize,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) anyerror!void {
    var index: usize = 0;
    while (index < source_lines.len) {
        const line = source_lines[index];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) {
            try appendBlank(gpa, output);
            index += 1;
            continue;
        }

        if (try renderLatexBlock(gpa, output, source_lines, index, options)) |next_index| {
            index = next_index;
            continue;
        }

        if (parseFence(line)) |fence| {
            var label_writer: std.Io.Writer.Allocating = .init(gpa);
            defer label_writer.deinit();
            try label_writer.writer.writeByte(fence.marker);
            try label_writer.writer.splatByteAll(fence.marker, fence.count - 1);
            if (fence.language.len > 0) {
                try label_writer.writer.writeByte(' ');
                try label_writer.writer.writeAll(fence.language);
            }
            const label = try styledAlloc(gpa, theme.code_border_sgr, label_writer.written());
            try appendOwned(gpa, output, label);
            index += 1;
            var content_end = index;
            while (content_end < source_lines.len and !isClosingFence(source_lines[content_end], fence)) : (content_end += 1) {}
            var effective_end = content_end;
            if (content_end == source_lines.len and effective_end > index) {
                const last = std.mem.trim(u8, source_lines[effective_end - 1], " \t\r");
                var partial = last.len > 0 and last.len < fence.count;
                for (last) |byte| {
                    if (byte != fence.marker) partial = false;
                }
                if (partial) effective_end -= 1;
            }
            for (source_lines[index..effective_end]) |code_line| {
                const styled = try styledAlloc(gpa, theme.code_block_sgr, code_line);
                defer gpa.free(styled);
                const indented = try std.fmt.allocPrint(gpa, "{s}{s}", .{ theme.code_block_indent, styled });
                try appendOwned(gpa, output, indented);
            }
            var closing_writer: std.Io.Writer.Allocating = .init(gpa);
            defer closing_writer.deinit();
            try closing_writer.writer.splatByteAll(fence.marker, fence.count);
            try appendOwned(gpa, output, try styledAlloc(gpa, theme.code_border_sgr, closing_writer.written()));
            index = if (content_end < source_lines.len) content_end + 1 else content_end;
            continue;
        }

        if (parseHeading(line)) |heading| {
            const rendered_inline = try renderInline(gpa, heading.text, theme, options, capabilities);
            defer gpa.free(rendered_inline);
            var heading_writer: std.Io.Writer.Allocating = .init(gpa);
            defer heading_writer.deinit();
            if (heading.depth >= 3) {
                try heading_writer.writer.splatByteAll('#', heading.depth);
                try heading_writer.writer.writeByte(' ');
            }
            try heading_writer.writer.writeAll(rendered_inline);
            const sgr = if (heading.depth == 1) "1;4;36" else theme.heading_sgr;
            try appendOwned(gpa, output, try styledAlloc(gpa, sgr, heading_writer.written()));
            index += 1;
            continue;
        }

        if (isHorizontalRule(line)) {
            const count = @min(width, @as(usize, 80));
            const rule = try repeatUtf8(gpa, "─", count);
            defer gpa.free(rule);
            try appendOwned(gpa, output, try styledAlloc(gpa, theme.hr_sgr, rule));
            index += 1;
            continue;
        }

        if (quoteContent(line) != null) {
            var quote_source: std.Io.Writer.Allocating = .init(gpa);
            defer quote_source.deinit();
            var end = index;
            while (end < source_lines.len) : (end += 1) {
                const content = quoteContent(source_lines[end]) orelse break;
                if (end > index) try quote_source.writer.writeByte('\n');
                try quote_source.writer.writeAll(content);
            }
            var nested = try render(gpa, quote_source.written(), @max(@as(usize, 1), width -| 2), theme, .{
                .preserve_ordered_list_markers = options.preserve_ordered_list_markers,
                .preserve_backslash_escapes = options.preserve_backslash_escapes,
                .render_latex_delimiters = options.render_latex_delimiters,
            }, capabilities);
            defer nested.deinit(gpa);
            const border = try styledAlloc(gpa, theme.quote_border_sgr, "│ ");
            defer gpa.free(border);
            for (nested.lines) |nested_line| {
                const quoted = try styledAlloc(gpa, theme.quote_sgr, nested_line);
                defer gpa.free(quoted);
                try appendOwned(gpa, output, try std.fmt.allocPrint(gpa, "{s}{s}", .{ border, quoted }));
            }
            index = end;
            continue;
        }

        if (parseListMarker(line)) |marker| {
            var body = line[marker.body_start..];
            var task_prefix: []const u8 = "";
            if (body.len >= 3 and body[0] == '[' and body[2] == ']' and (body[1] == ' ' or body[1] == 'x' or body[1] == 'X')) {
                task_prefix = if (body[1] == ' ') "[ ] " else "[x] ";
                body = std.mem.trimStart(u8, body[3..], " \t");
            }
            const depth = marker.leading / 2;
            const indent_count = depth * 4;
            const bullet = if (marker.ordered)
                if (options.preserve_ordered_list_markers)
                    try std.fmt.allocPrint(gpa, "{s} ", .{marker.source_marker})
                else
                    try std.fmt.allocPrint(gpa, "{d}. ", .{marker.number})
            else if (options.preserve_ordered_list_markers)
                try std.fmt.allocPrint(gpa, "{s} ", .{marker.source_marker})
            else
                try gpa.dupe(u8, "- ");
            defer gpa.free(bullet);
            const styled_bullet = try styledAlloc(gpa, theme.list_bullet_sgr, bullet);
            defer gpa.free(styled_bullet);
            const body_inline = try renderInline(gpa, body, theme, options, capabilities);
            defer gpa.free(body_inline);
            const marker_width = visibleWidth(bullet) + visibleWidth(task_prefix);
            const content_width = @max(@as(usize, 1), width -| indent_count -| marker_width);
            const wrapped = try wrapAnsi(gpa, body_inline, content_width);
            defer {
                for (wrapped) |wrapped_line| gpa.free(wrapped_line);
                gpa.free(wrapped);
            }
            for (wrapped, 0..) |wrapped_line, line_index| {
                var item_writer: std.Io.Writer.Allocating = .init(gpa);
                errdefer item_writer.deinit();
                try item_writer.writer.splatByteAll(' ', indent_count);
                if (line_index == 0) {
                    try item_writer.writer.writeAll(styled_bullet);
                    try item_writer.writer.writeAll(task_prefix);
                } else {
                    try item_writer.writer.splatByteAll(' ', marker_width);
                }
                try item_writer.writer.writeAll(wrapped_line);
                try appendOwned(gpa, output, try item_writer.toOwnedSlice());
            }
            index += 1;
            continue;
        }

        if (index + 1 < source_lines.len and std.mem.indexOfScalar(u8, line, '|') != null and isTableSeparator(source_lines[index + 1])) {
            index = try renderTable(gpa, output, source_lines, index, width, theme, options, capabilities);
            continue;
        }

        // Paragraph: soft line breaks become spaces; two trailing spaces remain
        // hard line breaks. Stop before the next block construct.
        var paragraph: std.Io.Writer.Allocating = .init(gpa);
        defer paragraph.deinit();
        var end = index;
        while (end < source_lines.len) : (end += 1) {
            if (end > index and isBlockStart(source_lines, end)) break;
            const paragraph_line = source_lines[end];
            if (std.mem.trim(u8, paragraph_line, " \t\r").len == 0) break;
            if (end > index) {
                const previous = source_lines[end - 1];
                if (previous.len >= 2 and std.mem.endsWith(u8, previous, "  ")) try paragraph.writer.writeByte('\n') else try paragraph.writer.writeByte(' ');
            }
            const content = if (paragraph_line.len >= 2 and std.mem.endsWith(u8, paragraph_line, "  ")) paragraph_line[0 .. paragraph_line.len - 2] else paragraph_line;
            try paragraph.writer.writeAll(content);
        }
        const rendered_inline = try renderInline(gpa, paragraph.written(), theme, options, capabilities);
        defer gpa.free(rendered_inline);
        try appendWrapped(gpa, output, rendered_inline, width);
        index = end;
    }
}

fn applyPadding(
    gpa: std.mem.Allocator,
    raw_lines: *std.ArrayList([]u8),
    total_width: usize,
    options: Options,
) !Rendered {
    var output: std.ArrayList([]u8) = .empty;
    errdefer {
        for (output.items) |line| gpa.free(line);
        output.deinit(gpa);
    }
    const empty = try gpa.alloc(u8, if (options.pad_to_width) total_width else 0);
    defer gpa.free(empty);
    @memset(empty, ' ');
    for (0..options.padding_y) |_| try appendDuped(gpa, &output, empty);
    for (raw_lines.items) |line| {
        if (terminal_image.isImageLine(line)) {
            try appendDuped(gpa, &output, line);
            continue;
        }
        var writer: std.Io.Writer.Allocating = .init(gpa);
        errdefer writer.deinit();
        try writer.writer.splatByteAll(' ', options.padding_x);
        try writer.writer.writeAll(line);
        try writer.writer.splatByteAll(' ', options.padding_x);
        if (options.pad_to_width) {
            const missing = total_width -| visibleWidth(writer.written());
            try writer.writer.splatByteAll(' ', missing);
        }
        try appendOwned(gpa, &output, try writer.toOwnedSlice());
    }
    for (0..options.padding_y) |_| try appendDuped(gpa, &output, empty);
    while (output.items.len > 0 and output.items[output.items.len - 1].len == 0 and options.padding_y == 0) {
        const removed = output.pop().?;
        gpa.free(removed);
    }
    return .{ .lines = try output.toOwnedSlice(gpa) };
}

pub fn render(
    gpa: std.mem.Allocator,
    markdown: []const u8,
    total_width_raw: usize,
    theme: Theme,
    options: Options,
    capabilities: terminal_image.TerminalCapabilities,
) anyerror!Rendered {
    const total_width = @max(@as(usize, 1), total_width_raw);
    const content_width = @max(@as(usize, 1), total_width -| (options.padding_x * 2));
    const normalized = try replaceTabs(gpa, markdown);
    defer gpa.free(normalized);
    if (std.mem.trim(u8, normalized, " \t\r\n").len == 0) return .{ .lines = try gpa.alloc([]u8, 0) };

    var source_lines_list: std.ArrayList([]const u8) = .empty;
    defer source_lines_list.deinit(gpa);
    var iterator = std.mem.splitScalar(u8, normalized, '\n');
    while (iterator.next()) |line| try source_lines_list.append(gpa, line);

    var raw_lines: std.ArrayList([]u8) = .empty;
    defer {
        for (raw_lines.items) |line| gpa.free(line);
        raw_lines.deinit(gpa);
    }
    try renderBlocks(gpa, &raw_lines, source_lines_list.items, content_width, theme, options, capabilities);
    return applyPadding(gpa, &raw_lines, total_width, options);
}

// -----------------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------------

fn joinedLines(gpa: std.mem.Allocator, rendered: Rendered) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    for (rendered.lines, 0..) |line, index| {
        if (index > 0) try out.writer.writeByte('\n');
        try out.writer.writeAll(line);
    }
    return out.toOwnedSlice();
}

test "Markdown headings and inline styles render ANSI" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "# Title\n\nThis is **bold**, *italic*, ~~gone~~ and `code`.", 80, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\x1b[1;4;36mTitle") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\x1b[1mbold") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\x1b[3mitalic") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\x1b[9mgone") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\x1b[33mcode") != null);
}

test "Markdown links use OSC 8 or visible URL fallback" {
    const gpa = std.testing.allocator;
    var linked = try render(gpa, "See [Pi](https://example.test/pi).", 80, .{}, .{}, .{ .hyperlinks = true });
    defer linked.deinit(gpa);
    const linked_text = try joinedLines(gpa, linked);
    defer gpa.free(linked_text);
    try std.testing.expect(std.mem.indexOf(u8, linked_text, "\x1b]8;;https://example.test/pi") != null);

    var fallback = try render(gpa, "See [Pi](https://example.test/pi).", 80, .{}, .{}, .{});
    defer fallback.deinit(gpa);
    const fallback_text = try joinedLines(gpa, fallback);
    defer gpa.free(fallback_text);
    try std.testing.expect(std.mem.indexOf(u8, fallback_text, "(https://example.test/pi)") != null);
}

test "Markdown fenced code blocks trim streamed partial closing fence" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "```zig\nconst x = 1;\n``", 80, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expect(std.mem.indexOf(u8, joined, "const x = 1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "\n  \x1b[38;5;252m``") == null);
    try std.testing.expect(std.mem.endsWith(u8, joined, "```\x1b[0m"));
}

test "Markdown task ordered and nested list markers render" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "- [x] done\n3) third\n  * nested", 80, .{}, .{ .preserve_ordered_list_markers = true }, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expect(std.mem.indexOf(u8, joined, "[x] done") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "3) ") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "    \x1b[36m* ") != null);
}

test "Markdown blockquotes recursively render blocks" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "> ## Quote\n> - item\n> continued", 50, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    try std.testing.expect(rendered.lines.len >= 3);
    for (rendered.lines) |line| try std.testing.expect(std.mem.indexOf(u8, line, "│ ") != null);
}

test "Markdown tables fit viewport and wrap cells" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "| Name | Description |\n| --- | --- |\n| Pi | Native terminal coding agent |", 32, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expect(std.mem.indexOf(u8, joined, "┌") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "┼") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "Native") != null);
    for (rendered.lines) |line| try std.testing.expect(visibleWidth(line) <= 32);
}

test "Markdown narrow tables fall back to source" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |", 8, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expect(std.mem.indexOf(u8, joined, "| A |") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "┌") == null);
}

test "ANSI wrapping ignores styles and OSC hyperlinks" {
    const gpa = std.testing.allocator;
    const linked = try terminal_image.hyperlink(gpa, "abcdefgh", "https://example.test");
    defer gpa.free(linked);
    const styled = try styledAlloc(gpa, "1", linked);
    defer gpa.free(styled);
    const lines = try wrapAnsi(gpa, styled, 4);
    defer {
        for (lines) |line| gpa.free(line);
        gpa.free(lines);
    }
    try std.testing.expectEqual(@as(usize, 2), lines.len);
    try std.testing.expectEqual(@as(usize, 4), visibleWidth(lines[0]));
    try std.testing.expectEqual(@as(usize, 4), visibleWidth(lines[1]));
}

test "Markdown preserves escaped punctuation only when requested" {
    const gpa = std.testing.allocator;
    var normalized = try render(gpa, "\\*literal\\*", 40, .{}, .{}, .{});
    defer normalized.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, normalized.lines[0], "\\*") == null);
    var preserved = try render(gpa, "\\*literal\\*", 40, .{}, .{ .preserve_backslash_escapes = true }, .{});
    defer preserved.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, preserved.lines[0], "\\*literal\\*") != null);
}

test "Markdown horizontal rules and hard line breaks render" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "above  \nbelow\n\n---", 12, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    try std.testing.expect(rendered.lines.len >= 3);
    try std.testing.expect(std.mem.indexOf(u8, rendered.lines[0], "above") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.lines[1], "below") != null);
    try std.testing.expect(visibleWidth(rendered.lines[rendered.lines.len - 1]) == 12);
}

test "Markdown padding and width constraints apply after wrapping" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "one two three four", 12, .{}, .{ .padding_x = 1, .padding_y = 1, .pad_to_width = true }, .{});
    defer rendered.deinit(gpa);
    try std.testing.expect(rendered.lines.len >= 4);
    for (rendered.lines) |line| try std.testing.expectEqual(@as(usize, 12), visibleWidth(line));
}

test "Markdown inline image syntax has explicit fallback" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "Look ![diagram](file:///tmp/a.png)", 80, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, rendered.lines[0], "[Image: diagram (file:///tmp/a.png)]") != null);
}

test "Markdown renders inline LaTeX and preserves currency shell and unsupported input" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "A map $\\mathbb{C}^3 \\to \\mathbb{C}^3$, $xy$, and \\(s \\to \\infty\\).", 120, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expectEqualStrings("A map ℂ³ → ℂ³, xy, and s → ∞.", joined);

    const literal = "Costs $5 and $10; use `$x$`, $HOME/$USER, and ${PATH}.";
    var preserved = try render(gpa, literal, 120, .{}, .{}, .{});
    defer preserved.deinit(gpa);
    const preserved_joined = try joinedLines(gpa, preserved);
    defer gpa.free(preserved_joined);
    try std.testing.expectEqualStrings("Costs $5 and $10; use \x1b[33m$x$\x1b[0m, $HOME/$USER, and ${PATH}.", preserved_joined);

    const unsupported = "Unknown $x + \\unknown{y}$ after";
    var raw = try render(gpa, unsupported, 120, .{}, .{}, .{});
    defer raw.deinit(gpa);
    const raw_joined = try joinedLines(gpa, raw);
    defer gpa.free(raw_joined);
    try std.testing.expectEqualStrings(unsupported, raw_joined);
}

test "Markdown display LaTeX renders blocks and preserves pending streams" {
    const gpa = std.testing.allocator;
    var rendered = try render(gpa, "Before\n\n\\[\nE \\approx \\frac{0.1\\ \\text{lux}}{100\\ \\text{lm/W}}\n\\]\n\nafter", 100, .{}, .{}, .{});
    defer rendered.deinit(gpa);
    const joined = try joinedLines(gpa, rendered);
    defer gpa.free(joined);
    try std.testing.expectEqualStrings("Before\n\n    0.1 lux\nE ≈ ────────\n    100 lm/W\n\nafter", joined);

    var pending = try render(gpa, "\\[\nx^2", 80, .{}, .{}, .{});
    defer pending.deinit(gpa);
    const pending_joined = try joinedLines(gpa, pending);
    defer gpa.free(pending_joined);
    try std.testing.expectEqualStrings("\\[\nx^2", pending_joined);
}

test "Markdown can disable LaTeX rendering and excludes fenced code" {
    const gpa = std.testing.allocator;
    const source = "Map $\\mathbb{C}^3 \\to \\mathbb{C}^3$";
    var disabled = try render(gpa, source, 100, .{}, .{ .render_latex_delimiters = false }, .{});
    defer disabled.deinit(gpa);
    const disabled_joined = try joinedLines(gpa, disabled);
    defer gpa.free(disabled_joined);
    try std.testing.expectEqualStrings(source, disabled_joined);

    var fenced = try render(gpa, "```text\n$\\mathbb{C}^3$\n```", 100, .{}, .{}, .{});
    defer fenced.deinit(gpa);
    const fenced_joined = try joinedLines(gpa, fenced);
    defer gpa.free(fenced_joined);
    try std.testing.expect(std.mem.indexOf(u8, fenced_joined, "$\\mathbb{C}^3$") != null);
    try std.testing.expect(std.mem.indexOf(u8, fenced_joined, "ℂ³") == null);
}
