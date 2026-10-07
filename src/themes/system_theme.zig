//! Source Pi 7fb59f9 system-theme classifier and palette generation.
const std = @import("std");
const colors = @import("../tui/colors.zig");
const oklab = @import("../tui/oklab.zig");
pub const recipe = @import("system_theme_recipe.zig");
pub const Appearance = enum { dark, light };
extern "c" fn pow(f64, f64) f64;
extern "c" fn exp(f64) f64;
pub fn relativeLuminance(rgb: colors.Rgb) f64 {
    var linear: [3]f64 = undefined;
    for ([_]f64{ rgb.r, rgb.g, rgb.b }, 0..) |channel, index| {
        const value = channel / 255;
        linear[index] = if (value <= 0.04045) value / 12.92 else pow((value + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2];
}
pub fn wcagContrast(first: colors.Rgb, second: colors.Rgb) f64 {
    const a = relativeLuminance(first);
    const b = relativeLuminance(second);
    return (@max(a, b) + 0.05) / (@min(a, b) + 0.05);
}
pub fn terminalAppearance(background: colors.Rgb, foreground: ?colors.Rgb) Appearance {
    const white = colors.Rgb{ .r = 255, .g = 255, .b = 255 };
    const black = colors.Rgb{ .r = 0, .g = 0, .b = 0 };
    const white_contrast = wcagContrast(white, background);
    const black_contrast = wcagContrast(black, background);
    if (foreground) |fg| {
        const fg_lightness = colors.colorToOklch(.{ .rgb = fg }).l;
        const bg_lightness = colors.colorToOklch(.{ .rgb = background }).l;
        if (@abs(fg_lightness - bg_lightness) > 0.05) {
            const appearance: Appearance = if (fg_lightness > bg_lightness) .dark else .light;
            if ((if (appearance == .dark) white_contrast else black_contrast) >= 4.5) return appearance;
        }
    }
    return if (white_contrast >= black_contrast) .dark else .light;
}
pub const Input = struct {
    foreground: ?colors.Rgb = null,
    background: ?colors.Rgb = null,
    palette: []const colors.Rgb = &.{},
    saturation: f64 = 1,
    appearance_hint: ?Appearance = null,
};
pub const Value = union(enum) { default, indexed: u8, rgb: colors.Rgb };
pub const Result = struct { values: [recipe.tokens.len]Value, dim: [recipe.tokens.len]bool, appearance: ?Appearance };
const SourceColor = struct { hsl: colors.Okhsl, chroma: f64 };
fn sourceOf(rgb: colors.Rgb) SourceColor {
    return .{ .hsl = colors.colorToOkhsl(.{ .rgb = rgb }), .chroma = colors.colorToOklch(.{ .rgb = rgb }).c };
}
fn lightness(rgb: colors.Rgb) f64 {
    return colors.colorToOklch(.{ .rgb = rgb }).l;
}
fn bellWeight(value: f64) f64 {
    const delta = value - 0.5;
    const gaussian = exp(-(delta * delta) / (2 * 0.25 * 0.25));
    const at_zero = exp(-0.25 / (2 * 0.25 * 0.25));
    return (gaussian - at_zero) / (1 - at_zero);
}
fn saturationCurve(family: recipe.Family, value: f64) f64 {
    const floor = if (family.max > 0) family.min / family.max else 1;
    return floor + (1 - floor) * bellWeight(value);
}
fn anchored(source: SourceColor, family: recipe.Family, value: f64, saturation: f64) colors.Rgb {
    const anchor = saturationCurve(family, source.hsl.l);
    const falloff = if (anchor > 0) @min(1, saturationCurve(family, value) / anchor) else 1;
    const color = colors.okhslColor(source.hsl.h, source.hsl.s * falloff * saturation, value) catch unreachable;
    const cap = source.chroma * falloff * saturation;
    const lch = colors.colorToOklch(color);
    return if (lch.c <= cap) colors.colorToRgb(color) else colors.colorToRgb(colors.oklchColor(lch.l, cap, source.hsl.h) catch unreachable);
}
fn levelTarget(level: u8, appearance: Appearance, surface: f64) ?f64 {
    const curve = if (appearance == .dark) recipe.levels[level].dark else recipe.levels[level].light;
    if (surface < curve.reachable[0] or surface > curve.reachable[1]) return null;
    var sum: f64 = 0;
    for (curve.coefficients, 0..) |coefficient, power| sum += coefficient * pow(surface, @floatFromInt(power));
    return sum;
}
const Canvas = [recipe.tokens.len + 1]?colors.Rgb;
const Solver = struct {
    background: colors.Rgb,
    foreground: ?colors.Rgb,
    background_l: f64,
    saturation: f64,
    appearance: Appearance,
    palette: ?[16]SourceColor,
    fn paint(self: Solver, token: usize, value: f64) colors.Rgb {
        const target_lightness = oklab.oklabToOkhslLightness(value);
        const info = recipe.tokens[token];
        const family = recipe.families[info.family];
        if (self.palette) |palette| return anchored(palette[info.slot], family, target_lightness, self.saturation);
        return (colors.okhslColor(family.hue, (family.min + (family.max - family.min) * bellWeight(target_lightness)) * self.saturation, target_lightness) catch unreachable).rgb;
    }
    fn target(self: Solver, level: u8, surface: f64, relaxation: f64) ?f64 {
        const reached = levelTarget(level, self.appearance, surface);
        if (reached == null and relaxation == 0) return null;
        const extreme: f64 = if (self.appearance == .dark) 1 else 0;
        const distance = (reached orelse extreme) - surface;
        const floor = (levelTarget(recipe.readable_floor[if (self.appearance == .dark) 0 else 1], self.appearance, surface) orelse extreme) - surface;
        const compressed = if (@abs(distance) > @abs(floor)) distance - (distance - floor) * @min(relaxation, 1) else distance;
        return surface + compressed * (1 - @max(0, relaxation - 1));
    }
    fn readable(self: Solver, rgb: colors.Rgb) bool {
        const channel: f64 = if (self.appearance == .dark) 255 else 0;
        return wcagContrast(.{ .r = channel, .g = channel, .b = channel }, rgb) >= 4.5;
    }
    fn limitPanel(self: Solver, token: usize, value: f64) colors.Rgb {
        const rgb = self.paint(token, value);
        if (self.readable(rgb)) return rgb;
        var low = self.background_l;
        var high = value;
        for (0..20) |_| {
            const middle = (low + high) / 2;
            if (self.readable(self.paint(token, middle))) low = middle else high = middle;
        }
        return self.paint(token, low);
    }
    fn solve(self: Solver, relaxation: f64) ?Canvas {
        var canvas: Canvas = @splat(null);
        canvas[recipe.tokens.len] = self.background;
        for (recipe.solve_order) |token| {
            var needed: f64 = if (self.appearance == .dark) -std.math.inf(f64) else std.math.inf(f64);
            for (recipe.rules) |rule| {
                if (rule.token != token) continue;
                for (rule.on) |surface| {
                    const value = self.target(rule.level, lightness(canvas[surface] orelse self.background), relaxation) orelse return null;
                    if (value < 0 or value > 1) return null;
                    needed = if (self.appearance == .dark) @max(needed, value) else @min(needed, value);
                }
            }
            canvas[token] = if (recipe.tokens[token].panel) self.limitPanel(token, needed) else self.paint(token, needed);
        }
        return canvas;
    }
};
fn meetsContrast(rgb: colors.Rgb, surfaces: []const colors.Rgb) bool {
    for (surfaces) |surface| if (wcagContrast(rgb, surface) < 4.5) return false;
    return true;
}
fn withTextContrast(rgb: colors.Rgb, surfaces: []const colors.Rgb, lighter: bool) colors.Rgb {
    if (meetsContrast(rgb, surfaces)) return rgb;
    const hsl = colors.colorToOkhsl(.{ .rgb = rgb });
    const extreme: f64 = if (lighter) 1 else 0;
    const limit = (colors.okhslColor(hsl.h, hsl.s, extreme) catch unreachable).rgb;
    if (!meetsContrast(limit, surfaces)) return limit;
    var low = hsl.l;
    var high = extreme;
    for (0..20) |_| {
        const middle = (low + high) / 2;
        if (meetsContrast((colors.okhslColor(hsl.h, hsl.s, middle) catch unreachable).rgb, surfaces)) high = middle else low = middle;
    }
    return (colors.okhslColor(hsl.h, hsl.s, high) catch unreachable).rgb;
}
pub fn generate(input: Input) Result {
    const saturation = @min(1, @max(0, input.saturation));
    var result: Result = .{ .values = @splat(.default), .dim = @splat(false), .appearance = input.appearance_hint };
    const background = input.background orelse {
        for (recipe.tokens, 0..) |token, index| {
            if (token.panel) continue;
            const neutral = token.family == 0;
            if (!neutral and saturation > 0) result.values[index] = .{ .indexed = token.slot };
            if (neutral and !token.foreground) result.dim[index] = true;
        }
        return result;
    };
    result.appearance = terminalAppearance(background, input.foreground);
    var solver: Solver = .{ .background = background, .foreground = input.foreground, .background_l = lightness(background), .saturation = saturation, .appearance = result.appearance.?, .palette = null };
    if (input.palette.len == 16) {
        var palette: [16]SourceColor = undefined;
        for (input.palette, 0..) |rgb, index| palette[index] = sourceOf(rgb);
        solver.palette = palette;
    }
    var relaxation: f64 = 0;
    var canvas = solver.solve(0);
    if (canvas == null) {
        var low: f64 = 0;
        var high: f64 = 2;
        canvas = solver.solve(high);
        for (0..20) |_| {
            const middle = (low + high) / 2;
            if (solver.solve(middle)) |attempt| {
                high = middle;
                canvas = attempt;
            } else low = middle;
        }
        relaxation = high;
    }
    const solved = canvas orelse @as(Canvas, @splat(null));
    for (solved[0..recipe.tokens.len], 0..) |rgb, index| if (rgb) |value| {
        result.values[index] = .{ .rgb = value };
    };
    for (recipe.tokens, 0..) |token, index| {
        if (!token.foreground) continue;
        var surfaces: [64]colors.Rgb = undefined;
        var count: usize = 0;
        for (recipe.rules) |rule| if (rule.token == index) {
            for (rule.on) |surface| {
                surfaces[count] = solved[surface] orelse background;
                count += 1;
            }
        };
        var text = solved[index];
        if (input.foreground) |foreground| {
            var targets_valid = true;
            var needed: f64 = if (solver.appearance == .dark) -std.math.inf(f64) else std.math.inf(f64);
            for (surfaces[0..count]) |surface| {
                const value = solver.target(recipe.foreground_level, lightness(surface), relaxation) orelse {
                    targets_valid = false;
                    break;
                };
                if (value < 0 or value > 1) {
                    targets_valid = false;
                    break;
                }
                needed = if (solver.appearance == .dark) @max(needed, value) else @min(needed, value);
            }
            if (targets_valid) {
                const foreground_l = lightness(foreground);
                if (if (solver.appearance == .dark) foreground_l >= needed else foreground_l <= needed) {
                    result.values[index] = .default;
                    continue;
                }
                text = anchored(sourceOf(foreground), recipe.families[0], oklab.oklabToOkhslLightness(needed), saturation);
            }
        }
        if (text) |value| result.values[index] = .{ .rgb = withTextContrast(value, surfaces[0..count], solver.appearance == .dark) };
    }
    return result;
}
fn jsonNumber(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => unreachable,
    };
}
fn jsonRgb(value: std.json.Value) colors.Rgb {
    return .{ .r = jsonNumber(value.object.get("r").?), .g = jsonNumber(value.object.get("g").?), .b = jsonNumber(value.object.get("b").?) };
}
test "actual source system themes reproduce 163 no-report background palette grayscale and contrast relaxation cases" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/system-theme-original-7fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("cases").?.array.items, 0..) |case, case_index| {
        const source = case.object.get("input").?.object;
        var palette: [16]colors.Rgb = undefined;
        var input: Input = .{};
        if (source.get("background")) |value| input.background = jsonRgb(value);
        if (source.get("foreground")) |value| input.foreground = jsonRgb(value);
        if (source.get("palette")) |value| {
            for (value.array.items, 0..) |rgb, index| palette[index] = jsonRgb(rgb);
            input.palette = &palette;
        }
        if (source.get("saturation")) |value| input.saturation = jsonNumber(value);
        if (source.get("appearanceHint")) |value| input.appearance_hint = std.meta.stringToEnum(Appearance, value.string).?;
        const expected = case.object.get("result").?.object;
        const actual = generate(input);
        if (expected.get("appearance")) |value| try std.testing.expectEqualStrings(value.string, @tagName(actual.appearance.?)) else try std.testing.expect(actual.appearance == null);
        for (recipe.tokens, 0..) |token, index| {
            const value = expected.get("colors").?.object.get(token.name).?;
            switch (actual.values[index]) {
                .default => try std.testing.expectEqualStrings("", value.string),
                .indexed => |slot| try std.testing.expectEqual(jsonNumber(value), @as(f64, @floatFromInt(slot))),
                .rgb => |rgb| {
                    const hex = try colors.colorToHex(std.testing.allocator, .{ .rgb = rgb });
                    defer std.testing.allocator.free(hex);
                    std.testing.expectEqualStrings(value.string, hex) catch |err| {
                        std.debug.print("System source case {d} token {s}\n", .{ case_index, token.name });
                        return err;
                    };
                },
            }
            var dim = false;
            for (expected.get("dim").?.array.items) |name| if (std.mem.eql(u8, name.string, token.name)) {
                dim = true;
            };
            try std.testing.expectEqual(dim, actual.dim[index]);
        }
    }
}
