//! Terminal report parsing and retained presentation data. Snapshot reads do
//! not perform terminal I/O; the input owner supplies complete report packets.
const std = @import("std");
pub const Rgb = @import("colors.zig").Rgb;
pub const Scheme = enum { dark, light };
pub const Target = union(enum) { foreground, background, palette: u16 };
pub const Reply = struct { target: Target, rgb: ?Rgb };
pub const Cache = struct {
    revision: u64 = 0,
    foreground: ?Rgb = null,
    background: ?Rgb = null,
    palette: [16]Rgb = undefined,
    has_palette: bool = false,
    scheme: ?Scheme = null,
    pending: bool = false,
    query_palette: [16]?Rgb = @splat(null),
    seen_palette: [1000]bool = @splat(false),
    seen_foreground: bool = false,
    seen_background: bool = false,
    replies: u16 = 0,
    fn bump(self: *Cache) !void {
        if (self.revision == std.math.maxInt(u64)) return error.TerminalColorRevisionOverflow;
        self.revision += 1;
    }
    pub fn begin(self: *Cache) !void {
        self.query_palette = @splat(null);
        self.seen_palette = @splat(false);
        self.seen_foreground = false;
        self.seen_background = false;
        self.replies = 0;
        if (!self.pending) {
            try self.bump();
            self.pending = true;
        }
    }
    pub fn finish(self: *Cache) !bool {
        if (!self.pending) return false;
        try self.bump();
        self.pending = false;
        return true;
    }
    pub fn report(self: *Cache, reply: Reply) !bool {
        var next = self.*;
        if (reply.rgb) |rgb| for ([_]f64{ rgb.r, rgb.g, rgb.b }) |value| if (!std.math.isFinite(value) or value < 0 or value > 255) return error.InvalidTerminalColorReport;
        var changed = false;
        switch (reply.target) {
            .foreground => {
                if (!next.seen_foreground) {
                    next.seen_foreground = true;
                    next.replies += 1;
                }
                if (reply.rgb) |rgb| if (next.foreground == null or !std.meta.eql(next.foreground.?, rgb)) {
                    next.foreground = rgb;
                    changed = true;
                };
            },
            .background => {
                if (!next.seen_background) {
                    next.seen_background = true;
                    next.replies += 1;
                }
                if (reply.rgb) |rgb| if (next.background == null or !std.meta.eql(next.background.?, rgb)) {
                    next.background = rgb;
                    changed = true;
                };
            },
            .palette => |index| {
                if (index >= next.seen_palette.len) return error.InvalidTerminalPaletteIndex;
                if (!next.seen_palette[index]) {
                    next.seen_palette[index] = true;
                    next.replies += 1;
                }
                if (index < 16) next.query_palette[index] = reply.rgb;
                var complete = true;
                for (next.query_palette) |item| if (item == null) {
                    complete = false;
                    break;
                };
                if (complete) {
                    var updated: [16]Rgb = undefined;
                    for (&updated, next.query_palette) |*item, rgb| item.* = rgb.?;
                    if (!next.has_palette or !std.meta.eql(next.palette, updated)) {
                        next.palette = updated;
                        next.has_palette = true;
                        changed = true;
                    }
                }
            },
        }
        if (next.pending and next.replies >= 18) {
            next.pending = false;
            changed = true;
        }
        if (changed) try next.bump();
        self.* = next;
        return changed;
    }
    pub fn setScheme(self: *Cache, scheme: Scheme) !bool {
        if (self.scheme == scheme) return false;
        try self.bump();
        self.scheme = scheme;
        return true;
    }
};
fn channel(text: []const u8) ?f64 {
    if (text.len == 0) return null;
    var value: f64 = 0;
    for (text) |byte| {
        const digit = std.fmt.charToDigit(byte, 16) catch return null;
        value = value * 16 + @as(f64, @floatFromInt(digit));
    }
    const maximum = std.math.pow(f64, 16, @floatFromInt(text.len)) - 1;
    if (maximum <= 0) return null;
    return @floor(value / maximum * 255 + 0.5);
}
fn color(raw: []const u8) ?Rgb {
    const value = trimEcma(raw);
    if (std.mem.startsWith(u8, value, "#")) {
        const hex = value[1..];
        const width: usize = if (hex.len == 6) 2 else if (hex.len == 12) 4 else return null;
        return .{ .r = channel(hex[0..width]) orelse return null, .g = channel(hex[width .. width * 2]) orelse return null, .b = channel(hex[width * 2 ..]) orelse return null };
    }
    var text = value;
    if (text.len >= 5 and std.ascii.eqlIgnoreCase(text[0..5], "rgba:")) text = text[5..] else if (text.len >= 4 and std.ascii.eqlIgnoreCase(text[0..4], "rgb:")) text = text[4..];
    var pieces = std.mem.splitScalar(u8, text, '/');
    const red = pieces.next() orelse return null;
    const green = pieces.next() orelse return null;
    const blue = pieces.next() orelse return null;
    // Source destructures three channels and ignores any following components.
    return .{ .r = channel(red) orelse return null, .g = channel(green) orelse return null, .b = channel(blue) orelse return null };
}
fn white(point: u21) bool {
    return switch (point) {
        9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trimEcma(text: []const u8) []const u8 {
    var begin: usize = 0;
    while (begin < text.len) {
        const length = std.unicode.utf8ByteSequenceLength(text[begin]) catch break;
        if (length > text.len - begin) break;
        const point = std.unicode.utf8Decode(text[begin..][0..length]) catch break;
        if (!white(point)) break;
        begin += length;
    }
    var end = text.len;
    while (end > begin) {
        var previous = end - 1;
        while (previous > begin and text[previous] & 0xc0 == 0x80) previous -= 1;
        const point = std.unicode.utf8Decode(text[previous..end]) catch break;
        if (!white(point)) break;
        end = previous;
    }
    return text[begin..end];
}
pub fn parseOsc(data: []const u8) ?Reply {
    if (!std.mem.startsWith(u8, data, "\x1b]")) return null;
    const end = if (std.mem.endsWith(u8, data, "\x07")) data.len - 1 else if (std.mem.endsWith(u8, data, "\x1b\\")) data.len - 2 else return null;
    if (end < 2) return null;
    const payload = data[2..end];
    var target: Target = undefined;
    var raw: []const u8 = undefined;
    if (std.mem.startsWith(u8, payload, "10;")) {
        target = .foreground;
        raw = payload[3..];
    } else if (std.mem.startsWith(u8, payload, "11;")) {
        target = .background;
        raw = payload[3..];
    } else if (std.mem.startsWith(u8, payload, "4;")) {
        const separator = std.mem.indexOfScalarPos(u8, payload, 2, ';') orelse return null;
        const digits = payload[2..separator];
        if (digits.len < 1 or digits.len > 3) return null;
        for (digits) |byte| if (!std.ascii.isDigit(byte)) return null;
        target = .{ .palette = std.fmt.parseInt(u16, digits, 10) catch return null };
        raw = payload[separator + 1 ..];
    } else return null;
    for (raw) |byte| if (byte == 7 or byte == 27) return null;
    return .{ .target = target, .rgb = color(raw) };
}
pub fn parseScheme(data: []const u8) ?Scheme {
    if (data.len == 0) return null;
    var remaining = data;
    var result: ?Scheme = null;
    while (remaining.len != 0) {
        if (!std.mem.startsWith(u8, remaining, "\x1b[?997;") or remaining.len < 9 or remaining[8] != 'n') return null;
        result = switch (remaining[7]) {
            '1' => .dark,
            '2' => .light,
            else => return null,
        };
        remaining = remaining[9..];
    }
    return result;
}
test "terminal color reports retain channel precision invalid color target and final scheme" {
    const reply = parseOsc("\x1b]10;rgb:ffff/8080/0000\x1b\\").?;
    try std.testing.expectEqual(@as(f64, 255), reply.rgb.?.r);
    try std.testing.expectEqual(@as(f64, 128), reply.rgb.?.g);
    try std.testing.expectEqual(@as(f64, 0), reply.rgb.?.b);
    try std.testing.expect(parseOsc("\x1b]4;999;not-a-color\x07").?.rgb == null);
    try std.testing.expect(parseOsc("\x1b]4;1234;#aabbcc\x07") == null);
    try std.testing.expectEqual(Scheme.light, parseScheme("\x1b[?997;1n\x1b[?997;2n").?);
    try std.testing.expect(parseScheme("\x1b[?997;3n") == null);
}
test "terminal color cache publishes only complete palettes suppresses unchanged reports and retains late replies" {
    var cache: Cache = .{};
    try cache.begin();
    const rgb: Rgb = .{ .r = 1, .g = 2, .b = 3 };
    try std.testing.expect(try cache.report(.{ .target = .foreground, .rgb = rgb }));
    const revision = cache.revision;
    try std.testing.expect(!try cache.report(.{ .target = .foreground, .rgb = rgb }));
    try std.testing.expectEqual(revision, cache.revision);
    for (0..15) |index| _ = try cache.report(.{ .target = .{ .palette = @intCast(index) }, .rgb = rgb });
    try std.testing.expect(!cache.has_palette);
    _ = try cache.report(.{ .target = .{ .palette = 15 }, .rgb = rgb });
    try std.testing.expect(cache.has_palette and cache.pending);
    _ = try cache.finish();
    try std.testing.expect(!cache.pending);
    try std.testing.expect(try cache.report(.{ .target = .background, .rgb = rgb }));
    try cache.begin();
    _ = try cache.report(.{ .target = .{ .palette = 0 }, .rgb = null });
    try std.testing.expect(cache.has_palette);
    try std.testing.expectError(error.InvalidTerminalColorReport, cache.report(.{ .target = .foreground, .rgb = .{ .r = std.math.nan(f64), .g = 0, .b = 0 } }));
    try std.testing.expectEqual(rgb, cache.foreground.?);
}
test "terminal color reports replay authentic original parser OSC targets colors and scheme repetitions" {
    const original = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/terminal-colors-original-7fb.json"), .{});
    defer original.deinit();
    for (original.value.object.get("osc").?.array.items) |row| {
        const expected = row.object.get("result").?;
        const actual = parseOsc(row.object.get("input").?.string);
        if (expected == .null) {
            try std.testing.expect(actual == null);
            continue;
        }
        try std.testing.expect(actual != null);
        const target = expected.object.get("target").?;
        switch (actual.?.target) {
            .foreground => try std.testing.expectEqualStrings("foreground", target.string),
            .background => try std.testing.expectEqualStrings("background", target.string),
            .palette => |index| try std.testing.expectEqual(@as(i64, index), target.integer),
        }
        if (expected.object.get("rgb")) |rgb| {
            try std.testing.expect(actual.?.rgb != null);
            for ([_]struct { name: []const u8, value: f64 }{ .{ .name = "r", .value = actual.?.rgb.?.r }, .{ .name = "g", .value = actual.?.rgb.?.g }, .{ .name = "b", .value = actual.?.rgb.?.b } }) |entry| {
                const number = rgb.object.get(entry.name).?;
                const wanted: f64 = switch (number) {
                    .integer => @floatFromInt(number.integer),
                    .float => number.float,
                    else => return error.InvalidOriginalCapture,
                };
                try std.testing.expectEqual(wanted, entry.value);
            }
        } else try std.testing.expect(actual.?.rgb == null);
    }
    for (original.value.object.get("schemes").?.array.items) |row| {
        const expected = row.object.get("result").?;
        const actual = parseScheme(row.object.get("input").?.string);
        if (expected == .null) try std.testing.expect(actual == null) else try std.testing.expectEqualStrings(expected.string, @tagName(actual.?));
    }
}
