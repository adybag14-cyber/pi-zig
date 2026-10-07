//! Source-compatible concrete colors and ANSI styling from Pi 7fb59f9.
const std = @import("std");
const oklab = @import("oklab.zig");
pub const Rgb = oklab.Rgb;
pub const Okhsl = oklab.Okhsl;
pub const Oklch = struct { l: f64, c: f64, h: f64 };
pub const Color = union(enum) { indexed: u8, rgb: Rgb, oklch: Oklch };
pub const ColorMode = enum { @"256color", truecolor };
pub const MixSpace = enum { oklch, srgb };
pub const Attributes = struct { bold: bool = false, dim: bool = false, italic: bool = false, underline: bool = false, inverse: bool = false, strikethrough: bool = false };
pub fn indexedColor(index: f64) !Color {
    if (!std.math.isFinite(index) or index != @floor(index) or index < 0 or index > 255) return error.InvalidColorIndex;
    return .{ .indexed = @intFromFloat(index) };
}
pub fn rgbColor(r: f64, g: f64, b: f64) !Color {
    for ([_]f64{ r, g, b }) |channel| {
        if (!std.math.isFinite(channel)) return error.NonFiniteColorChannel;
        if (channel < 0 or channel > 255) return error.ColorChannelOutOfRange;
    }
    return .{ .rgb = .{ .r = r, .g = g, .b = b } };
}
pub fn oklchColor(l: f64, c: f64, h: f64) !Color {
    if (!std.math.isFinite(l) or !std.math.isFinite(c) or !std.math.isFinite(h)) return error.NonFiniteColorChannel;
    if (l < 0 or l > 1 or c < 0) return error.ColorChannelOutOfRange;
    return .{ .oklch = .{ .l = l, .c = c, .h = @mod(@mod(h, 360) + 360, 360) } };
}
pub fn okhslColor(h: f64, s: f64, l: f64) !Color {
    if (!std.math.isFinite(h) or !std.math.isFinite(s) or !std.math.isFinite(l)) return error.NonFiniteColorChannel;
    if (s < 0 or s > 1 or l < 0 or l > 1) return error.ColorChannelOutOfRange;
    return .{ .rgb = oklab.okhslToRgb(h, s, l) };
}
fn whitespace(source: []const u8, position: *usize) void {
    while (position.* < source.len) {
        const length = std.unicode.utf8ByteSequenceLength(source[position.*]) catch return;
        if (length > source.len - position.*) return;
        const point = std.unicode.utf8Decode(source[position.*..][0..length]) catch return;
        switch (point) {
            0x9...0xd, 0x20, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => position.* += length,
            else => return,
        }
    }
}
fn number(source: []const u8, position: *usize) !f64 {
    const begin = position.*;
    if (position.* < source.len and (source[position.*] == '+' or source[position.*] == '-')) position.* += 1;
    const whole = position.*;
    while (position.* < source.len and std.ascii.isDigit(source[position.*])) position.* += 1;
    var digits = position.* > whole;
    if (position.* < source.len and source[position.*] == '.') {
        position.* += 1;
        const fraction = position.*;
        while (position.* < source.len and std.ascii.isDigit(source[position.*])) position.* += 1;
        digits = digits or position.* > fraction;
    }
    if (!digits) return error.InvalidColorValue;
    if (position.* < source.len and std.ascii.toLower(source[position.*]) == 'e') {
        position.* += 1;
        if (position.* < source.len and (source[position.*] == '+' or source[position.*] == '-')) position.* += 1;
        const exponent = position.*;
        while (position.* < source.len and std.ascii.isDigit(source[position.*])) position.* += 1;
        if (position.* == exponent) return error.InvalidColorValue;
    }
    return std.fmt.parseFloat(f64, source[begin..position.*]) catch error.InvalidColorValue;
}
fn suffix(source: []const u8, position: *usize, value: []const u8) bool {
    if (source.len - position.* < value.len or !std.ascii.eqlIgnoreCase(source[position.*..][0..value.len], value)) return false;
    position.* += value.len;
    return true;
}
fn separator(source: []const u8, position: *usize) !void {
    const begin = position.*;
    whitespace(source, position);
    if (begin == position.*) return error.InvalidColorValue;
}
pub const Parsed = union(enum) { rgb: Rgb, okhsl: Okhsl, oklch: Oklch };
pub fn parseChannels(source: []const u8) !Parsed {
    if ((source.len == 4 or source.len == 7) and source[0] == '#') {
        var channels: [3]f64 = undefined;
        for (&channels, 0..) |*channel, index| {
            const digits = if (source.len == 7) source[1 + index * 2 .. 3 + index * 2] else source[1 + index .. 2 + index];
            const value = std.fmt.parseInt(u8, digits, 16) catch return error.InvalidColorValue;
            channel.* = @floatFromInt(if (source.len == 7) @as(u16, value) else @as(u16, value) * 17);
        }
        return .{ .rgb = .{ .r = channels[0], .g = channels[1], .b = channels[2] } };
    }
    if (source.len < 8) return error.InvalidColorValue;
    const hsl = std.ascii.eqlIgnoreCase(source[0..6], "okhsl(");
    if (!hsl and !std.ascii.eqlIgnoreCase(source[0..6], "oklch(")) return error.InvalidColorValue;
    var position: usize = 6;
    whitespace(source, &position);
    var first = try number(source, &position);
    if (hsl) {
        _ = suffix(source, &position, "deg");
    } else if (suffix(source, &position, "%")) first /= 100;
    try separator(source, &position);
    var second = try number(source, &position);
    if (hsl and suffix(source, &position, "%")) second /= 100;
    try separator(source, &position);
    var third = try number(source, &position);
    if (hsl) {
        if (suffix(source, &position, "%")) third /= 100;
    } else _ = suffix(source, &position, "deg");
    whitespace(source, &position);
    if (!suffix(source, &position, ")") or position != source.len) return error.InvalidColorValue;
    return if (hsl) .{ .okhsl = .{ .h = first, .s = second, .l = third } } else .{ .oklch = .{ .l = first, .c = second, .h = third } };
}
pub fn parseColor(source: []const u8) !Color {
    return switch (try parseChannels(source)) {
        .rgb => |value| try rgbColor(value.r, value.g, value.b),
        .okhsl => |value| try okhslColor(value.h, value.s, value.l),
        .oklch => |value| try oklchColor(value.l, value.c, value.h),
    };
}
const basic = [_]Rgb{
    .{ .r = 0, .g = 0, .b = 0 },       .{ .r = 128, .g = 0, .b = 0 },   .{ .r = 0, .g = 128, .b = 0 },   .{ .r = 128, .g = 128, .b = 0 },
    .{ .r = 0, .g = 0, .b = 128 },     .{ .r = 128, .g = 0, .b = 128 }, .{ .r = 0, .g = 128, .b = 128 }, .{ .r = 192, .g = 192, .b = 192 },
    .{ .r = 128, .g = 128, .b = 128 }, .{ .r = 255, .g = 0, .b = 0 },   .{ .r = 0, .g = 255, .b = 0 },   .{ .r = 255, .g = 255, .b = 0 },
    .{ .r = 0, .g = 0, .b = 255 },     .{ .r = 255, .g = 0, .b = 255 }, .{ .r = 0, .g = 255, .b = 255 }, .{ .r = 255, .g = 255, .b = 255 },
};
const cube = [_]f64{ 0, 95, 135, 175, 215, 255 };
fn indexedToRgb(index: u8) Rgb {
    if (index < 16) return basic[index];
    if (index < 232) {
        const value: usize = index - 16;
        return .{ .r = cube[value / 36], .g = cube[(value % 36) / 6], .b = cube[value % 6] };
    }
    const gray: f64 = @floatFromInt(8 + @as(u16, index - 232) * 10);
    return .{ .r = gray, .g = gray, .b = gray };
}
fn inGamut(linear: oklab.Vector) bool {
    for (linear) |channel| if (channel < -1e-7 or channel > 1 + 1e-7) return false;
    return true;
}
fn oklchToRgb(value: Oklch) Rgb {
    const angle = (value.h * std.math.pi) / 180;
    const cos = @cos(angle);
    const sin = @sin(angle);
    const direct = oklab.oklabToLinearSrgb(.{ value.l, value.c * cos, value.c * sin });
    if (inGamut(direct)) return oklab.linearSrgbToRgb(direct);
    var linear = oklab.oklabToLinearSrgb(.{ value.l, 0, 0 });
    var low: f64 = 0;
    var high = value.c;
    for (0..20) |_| {
        const chroma = (low + high) / 2;
        const candidate = oklab.oklabToLinearSrgb(.{ value.l, chroma * cos, chroma * sin });
        if (inGamut(candidate)) {
            low = chroma;
            linear = candidate;
        } else high = chroma;
    }
    return oklab.linearSrgbToRgb(linear);
}
pub fn colorToRgb(color: Color) Rgb {
    return switch (color) {
        .indexed => |index| indexedToRgb(index),
        .rgb => |rgb| rgb,
        .oklch => |value| oklchToRgb(value),
    };
}
pub fn colorToOklch(color: Color) Oklch {
    if (color == .oklch) return color.oklch;
    const lab = oklab.rgbToOklab(colorToRgb(color));
    return .{ .l = lab[0], .c = @sqrt(lab[1] * lab[1] + lab[2] * lab[2]), .h = @mod((std.math.atan2(lab[2], lab[1]) * 180) / std.math.pi + 360, 360) };
}
pub fn colorToOkhsl(color: Color) Okhsl {
    return oklab.rgbToOkhsl(colorToRgb(color));
}
pub fn colorToHex(gpa: std.mem.Allocator, color: Color) ![]u8 {
    const rgb = colorToRgb(color);
    return std.fmt.allocPrint(gpa, "#{x:0>2}{x:0>2}{x:0>2}", .{ @as(u8, @intFromFloat(@round(rgb.r))), @as(u8, @intFromFloat(@round(rgb.g))), @as(u8, @intFromFloat(@round(rgb.b))) });
}
pub fn mixColors(first: Color, second: Color, amount: f64, space: MixSpace) !Color {
    if (!std.math.isFinite(amount)) return error.NonFiniteColorChannel;
    if (amount < 0 or amount > 1) return error.ColorChannelOutOfRange;
    if (space == .srgb) {
        const a = colorToRgb(first);
        const b = colorToRgb(second);
        return rgbColor(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount, a.b + (b.b - a.b) * amount);
    }
    const a = colorToOklch(first);
    const b = colorToOklch(second);
    const first_hue = if (a.c < 1e-7) b.h else a.h;
    const second_hue = if (b.c < 1e-7) first_hue else b.h;
    const delta = @mod(second_hue - first_hue + 540, 360) - 180;
    return oklchColor(a.l + (b.l - a.l) * amount, a.c + (b.c - a.c) * amount, first_hue + delta * amount);
}
fn closest(values: []const f64, target: f64) usize {
    var index: usize = 0;
    for (values, 0..) |value, candidate| if (@abs(target - value) < @abs(target - values[index])) {
        index = candidate;
    };
    return index;
}
fn distance(first: Rgb, second: Rgb) f64 {
    const r = first.r - second.r;
    const g = first.g - second.g;
    const b = first.b - second.b;
    return r * r * 0.299 + g * g * 0.587 + b * b * 0.114;
}
fn rgbToAnsi256(rgb: Rgb) usize {
    const r = closest(&cube, rgb.r);
    const g = closest(&cube, rgb.g);
    const b = closest(&cube, rgb.b);
    const cube_color: Rgb = .{ .r = cube[r], .g = cube[g], .b = cube[b] };
    var grays: [24]f64 = undefined;
    for (&grays, 0..) |*gray, index| gray.* = @floatFromInt(8 + index * 10);
    const offset = closest(&grays, @round(0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b));
    const gray = grays[offset];
    const spread = @max(rgb.r, @max(rgb.g, rgb.b)) - @min(rgb.r, @min(rgb.g, rgb.b));
    return if (spread < 10 and distance(rgb, .{ .r = gray, .g = gray, .b = gray }) < distance(rgb, cube_color)) 232 + offset else 16 + 36 * r + 6 * g + b;
}
pub fn colorAnsi(gpa: std.mem.Allocator, color: Color, mode: ColorMode, background: bool) ![]u8 {
    const kind: u8 = if (background) 48 else 38;
    if (color == .indexed) return std.fmt.allocPrint(gpa, "\x1b[{d};5;{d}m", .{ kind, color.indexed });
    const rgb = colorToRgb(color);
    if (mode == .truecolor) return std.fmt.allocPrint(gpa, "\x1b[{d};2;{d};{d};{d}m", .{ kind, @as(u16, @intFromFloat(@round(rgb.r))), @as(u16, @intFromFloat(@round(rgb.g))), @as(u16, @intFromFloat(@round(rgb.b))) });
    return std.fmt.allocPrint(gpa, "\x1b[{d};5;{d}m", .{ kind, rgbToAnsi256(rgb) });
}
pub fn styleTextWithAnsi(gpa: std.mem.Allocator, text: []const u8, foreground: ?[]const u8, background: ?[]const u8, attrs: Attributes) ![]u8 {
    var prefix: std.Io.Writer.Allocating = .init(gpa);
    defer prefix.deinit();
    var endings: [8][]const u8 = undefined;
    var size: usize = 0;
    if (foreground) |value| if (value.len > 0) {
        try prefix.writer.writeAll(value);
        endings[size] = "\x1b[39m";
        size += 1;
    };
    if (background) |value| if (value.len > 0) {
        try prefix.writer.writeAll(value);
        endings[size] = "\x1b[49m";
        size += 1;
    };
    if (attrs.bold) try prefix.writer.writeAll("\x1b[1m");
    if (attrs.dim) try prefix.writer.writeAll("\x1b[2m");
    if (attrs.bold or attrs.dim) {
        endings[size] = "\x1b[22m";
        size += 1;
    }
    inline for (.{ .{ "italic", "\x1b[3m", "\x1b[23m" }, .{ "underline", "\x1b[4m", "\x1b[24m" }, .{ "inverse", "\x1b[7m", "\x1b[27m" }, .{ "strikethrough", "\x1b[9m", "\x1b[29m" } }) |field| if (@field(attrs, field[0])) {
        try prefix.writer.writeAll(field[1]);
        endings[size] = field[2];
        size += 1;
    };
    try prefix.writer.writeAll(text);
    while (size > 0) {
        size -= 1;
        try prefix.writer.writeAll(endings[size]);
    }
    return prefix.toOwnedSlice();
}
fn jsonNumber(value: std.json.Value) f64 {
    return switch (value) {
        .integer => @floatFromInt(value.integer),
        .float => value.float,
        else => unreachable,
    };
}
fn expectRgb(expected: std.json.ObjectMap, rgb: Rgb) !void {
    try std.testing.expectEqual(jsonNumber(expected.get("r").?), rgb.r);
    try std.testing.expectEqual(jsonNumber(expected.get("g").?), rgb.g);
    try std.testing.expectEqual(jsonNumber(expected.get("b").?), rgb.b);
}
fn expectColor(expected: std.json.Value, actual: Color) !void {
    const kind = expected.object.get("kind").?.string;
    try std.testing.expectEqualStrings(kind, @tagName(actual));
    switch (actual) {
        .indexed => |index| try std.testing.expectEqual(jsonNumber(expected.object.get("index").?), @as(f64, @floatFromInt(index))),
        .rgb => |rgb| try expectRgb(expected.object, rgb),
        .oklch => |value| {
            try std.testing.expectApproxEqAbs(jsonNumber(expected.object.get("l").?), value.l, 1e-10);
            try std.testing.expectApproxEqAbs(jsonNumber(expected.object.get("c").?), value.c, 1e-10);
            try std.testing.expectApproxEqAbs(jsonNumber(expected.object.get("h").?), value.h, 1e-10);
        },
    }
}
fn parseJsonColor(value: std.json.Value) !Color {
    return if (value == .string) parseColor(value.string) else indexedColor(jsonNumber(value));
}
test "native color parser gamut ANSI all palette slots and styled combinations replay actual source" {
    const gpa = std.testing.allocator;
    var capture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/colors-original-7fb.json"), .{});
    defer capture.deinit();
    for (capture.value.object.get("cases").?.array.items, 0..) |case, index| {
        const color = try parseJsonColor(case.object.get("input").?);
        expectColor(case.object.get("color").?, color) catch |err| {
            std.debug.print("Color original case {d}\n", .{index});
            return err;
        };
        try expectRgb(case.object.get("rgb").?.object, colorToRgb(color));
        const hex = try colorToHex(gpa, color);
        defer gpa.free(hex);
        try std.testing.expectEqualStrings(case.object.get("hex").?.string, hex);
        const lch = colorToOklch(color);
        const lch_expected = case.object.get("oklch").?.object;
        try std.testing.expectApproxEqAbs(jsonNumber(lch_expected.get("l").?), lch.l, 1e-10);
        try std.testing.expectApproxEqAbs(jsonNumber(lch_expected.get("c").?), lch.c, 1e-10);
        if (@abs(jsonNumber(lch_expected.get("h").?) - lch.h) > 1e-10) std.debug.print("Oklch case {d} input {any} nativeRGB {any} nativeLab {any} expected {any}\n", .{ index, case.object.get("input").?, colorToRgb(color), oklab.rgbToOklab(colorToRgb(color)), lch_expected });
        try std.testing.expectApproxEqAbs(jsonNumber(lch_expected.get("h").?), lch.h, 1e-10);
        const hsl = colorToOkhsl(color);
        const hsl_expected = case.object.get("okhsl").?.object;
        try std.testing.expectApproxEqAbs(jsonNumber(hsl_expected.get("h").?), hsl.h, 1e-10);
        try std.testing.expectApproxEqAbs(jsonNumber(hsl_expected.get("s").?), hsl.s, 1e-10);
        try std.testing.expectApproxEqAbs(jsonNumber(hsl_expected.get("l").?), hsl.l, 1e-10);
        inline for (.{ .{ "fgTrue", ColorMode.truecolor, false }, .{ "fg256", ColorMode.@"256color", false }, .{ "bgTrue", ColorMode.truecolor, true }, .{ "bg256", ColorMode.@"256color", true } }) |field| {
            const ansi = try colorAnsi(gpa, color, field[1], field[2]);
            defer gpa.free(ansi);
            try std.testing.expectEqualStrings(case.object.get(field[0]).?.string, ansi);
        }
    }
    for (capture.value.object.get("invalid").?.array.items) |case| {
        const value = case.object.get("input").?;
        if (value == .null) continue; // JS coercion belongs to the native binding.
        if (parseJsonColor(value)) |_| return error.ExpectedOriginalInvalidColor else |_| {}
    }
    for (capture.value.object.get("mix").?.array.items) |case| {
        const first = try parseColor(case.object.get("first").?.string);
        const second = try parseColor(case.object.get("second").?.string);
        const mixed = try mixColors(first, second, jsonNumber(case.object.get("amount").?), if (std.mem.eql(u8, case.object.get("space").?.string, "srgb")) .srgb else .oklch);
        try expectColor(case.object.get("color").?, mixed);
        try expectRgb(case.object.get("rgb").?.object, colorToRgb(mixed));
        const hex = try colorToHex(gpa, mixed);
        defer gpa.free(hex);
        try std.testing.expectEqualStrings(case.object.get("hex").?.string, hex);
    }
    for (capture.value.object.get("styles").?.array.items) |case| {
        const flags: u6 = @intCast(case.object.get("flags").?.integer);
        const styled = try styleTextWithAnsi(gpa, "first\nsecond", "\x1b[38;2;18;171;205m", "\x1b[48;5;244m", .{ .bold = flags & 1 != 0, .dim = flags & 2 != 0, .italic = flags & 4 != 0, .underline = flags & 8 != 0, .inverse = flags & 16 != 0, .strikethrough = flags & 32 != 0 });
        defer gpa.free(styled);
        try std.testing.expectEqualStrings(case.object.get("value").?.string, styled);
    }
}
