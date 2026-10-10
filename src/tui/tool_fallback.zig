//! Source generic tool header formatting over the actual owned argument JSON.
const std = @import("std");
const palette_mod = @import("theme_palette.zig");
pub fn textOutput(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    var index: usize = 0;
    while (index < raw.len) : (index += 1) {
        if (ansiEnd(raw, index)) |end| {
            index = end - 1;
            continue;
        }
        const byte = raw[index];
        if (byte <= 8 or byte == 11 or byte == 12 or (byte >= 14 and byte <= 31) or byte == '\r') continue;
        if (index + 2 < raw.len and byte == 0xef and raw[index + 1] == 0xbf and raw[index + 2] >= 0xb9 and raw[index + 2] <= 0xbb) {
            index += 2;
            continue;
        }
        try result.append(gpa, byte);
    }
    return result.toOwnedSlice(gpa);
}
fn finalByte(byte: u8) bool {
    return switch (byte) {
        '0'...'9', 'A'...'P', 'R'...'T', 'Z', 'c', 'f'...'n', 'q'...'u', 'y', '=', '>', '<', '~' => true,
        else => false,
    };
}
/// The exact Source stripAnsi OSC/CSI grammar, over UTF8 encoded C1 controls.
fn ansiEnd(raw: []const u8, start: usize) ?usize {
    const escaped = raw[start] == 0x1b;
    const c1 = start + 1 < raw.len and raw[start] == 0xc2 and raw[start + 1] == 0x9b;
    if (!escaped and !c1) return null;
    if (escaped and start + 1 < raw.len and raw[start + 1] == ']') {
        var position = start + 2;
        while (position < raw.len) : (position += 1) {
            if (raw[position] == 7) return position + 1;
            if (position + 1 < raw.len and ((raw[position] == 0x1b and raw[position + 1] == '\\') or (raw[position] == 0xc2 and raw[position + 1] == 0x9c))) return position + 2;
        }
    }
    var position = start + @as(usize, if (c1) 2 else 1);
    while (position < raw.len and std.mem.indexOfScalar(u8, "[]()#;?", raw[position]) != null) position += 1;
    var matched: ?usize = if (position < raw.len and finalByte(raw[position])) position + 1 else null;
    if (position == raw.len or !std.ascii.isDigit(raw[position])) return matched;
    var count: usize = 0;
    while (position < raw.len and count < 4 and std.ascii.isDigit(raw[position])) : (count += 1) {
        position += 1;
        if (position < raw.len and finalByte(raw[position])) matched = position + 1;
    }
    while (position < raw.len and (raw[position] == ';' or raw[position] == ':')) {
        position += 1;
        if (position < raw.len and finalByte(raw[position])) matched = position + 1;
        count = 0;
        while (position < raw.len and count < 4 and std.ascii.isDigit(raw[position])) : (count += 1) {
            position += 1;
            if (position < raw.len and finalByte(raw[position])) matched = position + 1;
        }
    }
    return matched;
}
fn styled(gpa: std.mem.Allocator, palette: ?*const palette_mod.Palette, token: []const u8, text: []const u8) ![]u8 {
    return if (palette) |value| value.style(token, text) else gpa.dupe(u8, text);
}
fn valueText(gpa: std.mem.Allocator, value: std.json.Value, expanded: bool) ![]u8 {
    if (expanded and value == .string) return gpa.dupe(u8, value.string);
    return std.json.Stringify.valueAlloc(gpa, value, .{ .whitespace = if (expanded) .indent_2 else .minified });
}
pub fn format(gpa: std.mem.Allocator, title: []const u8, args: std.json.Value, expanded: bool, palette: ?*const palette_mod.Palette) ![]u8 {
    const bold = try std.fmt.allocPrint(gpa, "\x1b[1m{s}\x1b[22m", .{title});
    defer gpa.free(bold);
    const header = try styled(gpa, palette, "toolTitle", bold);
    defer gpa.free(header);
    if (args == .null or (args == .object and args.object.count() == 0)) return gpa.dupe(u8, header);
    var entries: std.Io.Writer.Allocating = .init(gpa);
    defer entries.deinit();
    if (args == .object) {
        var iterator = args.object.iterator();
        var first = true;
        while (iterator.next()) |entry| {
            if (!first) try entries.writer.writeAll(if (expanded) "\n" else " ");
            first = false;
            try writeEntry(gpa, &entries.writer, entry.key_ptr.*, entry.value_ptr.*, expanded);
        }
    } else try writeEntry(gpa, &entries.writer, "args", args, expanded);
    const raw = entries.written();
    var end = raw.len;
    if (!expanded) {
        var points = (try std.unicode.Utf8View.init(raw)).iterator();
        var length: usize = 0;
        var preview_end: usize = 0;
        while (points.nextCodepoint()) |point| {
            length += if (point > 0xffff) @as(usize, 2) else 1;
            if (length <= 97) preview_end = points.i;
        }
        if (length > 100) end = preview_end;
    }
    const preview = if (end < raw.len) try std.fmt.allocPrint(gpa, "{s}...", .{raw[0..end]}) else try gpa.dupe(u8, raw);
    defer gpa.free(preview);
    const tail = try styled(gpa, palette, "muted", preview);
    defer gpa.free(tail);
    return std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ header, if (expanded) "\n" else " ", tail });
}
fn writeEntry(gpa: std.mem.Allocator, writer: *std.Io.Writer, key: []const u8, value: std.json.Value, expanded: bool) !void {
    const raw = try valueText(gpa, value, expanded);
    defer gpa.free(raw);
    if (expanded) try writer.print("  {s}: ", .{key}) else try writer.print("{s}=", .{key});
    for (raw) |byte| {
        if (expanded) switch (byte) {
            '\t' => try writer.writeAll("   "),
            '\r' => {},
            '\n' => try writer.writeAll("\n    "),
            else => try writer.writeByte(byte),
        } else try writer.writeByte(byte);
    }
}
