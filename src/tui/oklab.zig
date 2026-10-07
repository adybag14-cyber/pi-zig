//! Oklab/OKHSL conversion, ported from Pi 7fb59f9 packages/tui/src/oklab.ts.
//! Original reference implementation Copyright (c) 2021 Björn Ottosson.
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to
//! deal in the Software without restriction, including without limitation the
//! rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//! sell copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions: The above copyright
//! notice and this permission notice shall be included in all copies or
//! substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
//! WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
const std = @import("std");
// Use the directly linked C runtime power function, matching the guest VM's
// numeric backend. std.math.pow uses a different algorithm whose last-bit
// gamma rounding changes the source's observable near-neutral hue.
extern "c" fn pow(f64, f64) f64;
pub const Vector = [3]f64;
const Matrix = [3]Vector;
pub const Rgb = struct { r: f64, g: f64, b: f64 };
pub const Okhsl = struct { h: f64, s: f64, l: f64 };
const linear_srgb_to_lms: Matrix = .{
    .{ 0.4122214694707629, 0.5363325372617349, 0.0514459932675022 },
    .{ 0.2119034958178251, 0.6806995506452344, 0.1073969535369405 },
    .{ 0.0883024591900564, 0.2817188391361215, 0.6299787016738222 },
};
const lms_to_lab: Matrix = .{
    .{ 0.210454268309314, 0.793617774702305, -0.0040720430116193 },
    .{ 1.9779985324311684, -2.42859224204858, 0.450593709617411 },
    .{ 0.0259040424655478, 0.7827717124575296, -0.8086757549230774 },
};
const lab_to_lms: Matrix = .{
    .{ 1, 0.3963377773761749, 0.2158037573099136 },
    .{ 1, -0.1055613458156586, -0.0638541728258133 },
    .{ 1, -0.0894841775298119, -1.2914855480194092 },
};
const lms_to_linear_srgb: Matrix = .{
    .{ 4.0767416360759583, -3.3077115392580629, 0.2309699031821043 },
    .{ -1.2684379732850315, 2.6097573492876882, -0.341319376002657 },
    .{ -0.0041960761386756, -0.7034186179359362, 1.7076146940746117 },
};
const saturation_fit = [_]struct { plane: [2]f64, polynomial: [5]f64 }{
    .{ .plane = .{ -1.8817031, -0.80936501 }, .polynomial = .{ 1.19086277, 1.76576728, 0.59662641, 0.75515197, 0.56771245 } },
    .{ .plane = .{ 1.8144408, -1.19445267 }, .polynomial = .{ 0.73956515, -0.45954404, 0.08285427, 0.12541073, -0.14503204 } },
    .{ .plane = .{ 0.13110758, 1.81333971 }, .polynomial = .{ 1.35733652, -0.00915799, -1.1513021, -0.50559606, 0.00692167 } },
};
const k1 = 0.206;
const k2 = 0.03;
const k3 = (1 + k1) / (1 + k2);
fn dot(a: Vector, b: Vector) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn multiply(matrix: Matrix, vector: Vector) Vector {
    return .{ dot(matrix[0], vector), dot(matrix[1], vector), dot(matrix[2], vector) };
}
fn cube(value: f64) f64 {
    return value * value * value;
}
fn square(value: f64) f64 {
    return value * value;
}
// Node 24's V8 fdlibm cube-root rounding is observable in neutral-color hue.
// Adapted from deps/v8/src/base/ieee754.cc in Node v24.14.0:
// Copyright (C) 1993 Sun Microsystems, Inc.; Copyright 2016 V8 authors.
// Permission to use, copy, modify, and distribute this software is freely
// granted, provided that this notice is preserved.
fn sourceCbrt(x: f64) f64 {
    const bits: u64 = @bitCast(x);
    const high: u32 = @truncate(bits >> 32);
    const sign = high & 0x80000000;
    const magnitude = high ^ sign;
    if (magnitude >= 0x7ff00000) return x + x;
    var estimate: f64 = 0;
    if (magnitude < 0x00100000) {
        if (bits & 0x7fffffffffffffff == 0) return x;
        estimate = @as(f64, @bitCast(@as(u64, 0x43500000) << 32)) * x;
        const scaled: u64 = @bitCast(estimate);
        estimate = @bitCast(@as(u64, sign | ((@as(u32, @truncate(scaled >> 32)) & 0x7fffffff) / 3 + 696219795)) << 32);
    } else estimate = @bitCast(@as(u64, sign | (magnitude / 3 + 715094163)) << 32);
    const ratio = (estimate * estimate) * (estimate / x);
    estimate *= (1.87595182427177009643 + ratio * (-1.88497979543377169875 + ratio * 1.621429720105354466140)) + ((ratio * ratio) * ratio) * (-0.758397934778766047437 + ratio * 0.145996192886612446982);
    estimate = @bitCast((@as(u64, @bitCast(estimate)) + 0x80000000) & 0xffffffffc0000000);
    const quotient = x / (estimate * estimate);
    return estimate + estimate * ((quotient - estimate) / (estimate + estimate + quotient));
}
pub fn oklabToOkhslLightness(value: f64) f64 {
    return 0.5 * (k3 * value - k1 + @sqrt(square(k3 * value - k1) + 4 * k2 * k3 * value));
}
fn okhslToOklabLightness(value: f64) f64 {
    return (value * value + k1 * value) / (k3 * (value + k2));
}
fn linearToSrgb(value: f64) f64 {
    return if (value > 0.0031308) 1.055 * pow(value, 1.0 / 2.4) - 0.055 else 12.92 * value;
}
fn srgbToLinear(value: f64) f64 {
    return if (value <= 0.04045) value / 12.92 else pow((value + 0.055) / 1.055, 2.4);
}
pub fn oklabToLinearSrgb(lab: Vector) Vector {
    var lms = multiply(lab_to_lms, lab);
    for (&lms) |*value| value.* = cube(value.*);
    return multiply(lms_to_linear_srgb, lms);
}
pub fn rgbToOklab(rgb: Rgb) Vector {
    var lms = multiply(linear_srgb_to_lms, .{ srgbToLinear(rgb.r / 255), srgbToLinear(rgb.g / 255), srgbToLinear(rgb.b / 255) });
    for (&lms) |*value| value.* = sourceCbrt(value.*);
    return multiply(lms_to_lab, lms);
}
pub fn linearSrgbToRgb(linear: Vector) Rgb {
    var values: Vector = undefined;
    for (linear, &values) |value, *output| output.* = @round(@min(1, @max(0, linearToSrgb(value))) * 255);
    return .{ .r = values[0], .g = values[1], .b = values[2] };
}
fn lmsSlopes(a: f64, b: f64) Vector {
    return .{ lab_to_lms[0][1] * a + lab_to_lms[0][2] * b, lab_to_lms[1][1] * a + lab_to_lms[1][2] * b, lab_to_lms[2][1] * a + lab_to_lms[2][2] * b };
}
fn maxSaturation(a: f64, b: f64) f64 {
    const channel = for (saturation_fit, 0..) |fit, index| {
        if (index == 2 or fit.plane[0] * a + fit.plane[1] * b > 1) break index;
    } else unreachable;
    const polynomial = saturation_fit[channel].polynomial;
    const weights = lms_to_linear_srgb[channel];
    const saturation = polynomial[0] + polynomial[1] * a + polynomial[2] * b + polynomial[3] * a * a + polynomial[4] * a * b;
    const slopes = lmsSlopes(a, b);
    var base: Vector = undefined;
    var values: Vector = undefined;
    var first: Vector = undefined;
    var second: Vector = undefined;
    for (slopes, 0..) |slope, index| {
        base[index] = 1 + saturation * slope;
        values[index] = cube(base[index]);
        first[index] = 3 * slope * square(base[index]);
        second[index] = 6 * square(slope) * base[index];
    }
    // Source Array.reduce starts at zero; retain its addition order.
    const f = (0 + weights[0] * values[0]) + weights[1] * values[1] + weights[2] * values[2];
    const f1 = (0 + weights[0] * first[0]) + weights[1] * first[1] + weights[2] * first[2];
    const f2 = (0 + weights[0] * second[0]) + weights[1] * second[1] + weights[2] * second[2];
    return saturation - (f * f1) / (f1 * f1 - 0.5 * f * f2);
}
fn cusp(a: f64, b: f64) [2]f64 {
    const saturation = maxSaturation(a, b);
    const linear = oklabToLinearSrgb(.{ 1, saturation * a, saturation * b });
    const lightness = sourceCbrt(1 / @max(linear[0], @max(linear[1], linear[2])));
    return .{ lightness, lightness * saturation };
}
fn maxChroma(a: f64, b: f64, lightness: f64, peak: [2]f64) f64 {
    if (lightness <= peak[0]) return (peak[1] * lightness) / peak[0];
    const t = (peak[1] * (lightness - 1)) / (peak[0] - 1);
    const slopes = lmsSlopes(a, b);
    var cubes: Vector = undefined;
    var first: Vector = undefined;
    var second: Vector = undefined;
    for (slopes, 0..) |slope, index| {
        const lms = lightness + t * slope;
        cubes[index] = cube(lms);
        first[index] = 3 * slope * square(lms);
        second[index] = 6 * square(slope) * lms;
    }
    var minimum = std.math.floatMax(f64);
    for (lms_to_linear_srgb) |row| {
        const f = dot(row, cubes) - 1;
        const f1 = dot(row, first);
        const f2 = dot(row, second);
        const u = f1 / (f1 * f1 - 0.5 * f * f2);
        const step = if (u >= 0) -f * u else std.math.floatMax(f64);
        minimum = @min(minimum, step);
    }
    return t + minimum;
}
fn chromaStops(lightness: f64, a: f64, b: f64) Vector {
    const peak = cusp(a, b);
    const maximum = maxChroma(a, b, lightness, peak);
    const k = maximum / @min(lightness * (peak[1] / peak[0]), (1 - lightness) * (peak[1] / (1 - peak[0])));
    const mid_s = 0.11516993 + 1 / (7.4477897 + 4.1590124 * b + a * (-2.19557347 + 1.75198401 * b + a * (-2.13704948 - 10.02301043 * b + a * (-4.24894561 + 5.38770819 * b + 4.69891013 * a))));
    const mid_t = 0.11239642 + 1 / (1.6132032 - 0.68124379 * b + a * (0.40370612 + 0.90148123 * b + a * (-0.27087943 + 0.6122399 * b + a * (0.00299215 - 0.45399568 * b - 0.14661872 * a))));
    const s = square(square(lightness * mid_s));
    const t = square(square((1 - lightness) * mid_t));
    const middle = 0.9 * k * @sqrt(@sqrt(1 / (1 / s + 1 / t)));
    const initial = @sqrt(1 / (1 / square(lightness * 0.4) + 1 / square((1 - lightness) * 0.8)));
    return .{ initial, middle, maximum };
}
pub fn okhslToRgb(hue: f64, saturation: f64, lightness: f64) Rgb {
    const lab_lightness = okhslToOklabLightness(lightness);
    var lab: Vector = .{ lab_lightness, 0, 0 };
    if (lab_lightness > 0 and lab_lightness < 1 and saturation > 0) {
        const angle = (2 * std.math.pi * @mod(@mod(hue, 360) + 360, 360)) / 360;
        const a = @cos(angle);
        const b = @sin(angle);
        const stops = chromaStops(lab_lightness, a, b);
        const chroma = if (saturation < 0.8) blk: {
            const t = 1.25 * saturation;
            const slope = 0.8 * stops[0];
            break :blk (t * slope) / (1 - (1 - slope / stops[1]) * t);
        } else blk: {
            const t = 5 * (saturation - 0.8);
            const slope = (0.2 * square(stops[1]) * square(1.25)) / stops[0];
            break :blk stops[1] + (t * slope) / (1 - (1 - slope / (stops[2] - stops[1])) * t);
        };
        lab = .{ lab_lightness, chroma * a, chroma * b };
    }
    return linearSrgbToRgb(oklabToLinearSrgb(lab));
}
pub fn rgbToOkhsl(rgb: Rgb) Okhsl {
    const lab = rgbToOklab(rgb);
    const chroma = @sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    const lightness = oklabToOkhslLightness(lab[0]);
    if (chroma < 1e-9 or lightness <= 0 or lightness >= 1) return .{ .h = 0, .s = 0, .l = lightness };
    const hue = @mod((std.math.atan2(lab[2], lab[1]) * 180) / std.math.pi + 360, 360);
    const stops = chromaStops(lab[0], lab[1] / chroma, lab[2] / chroma);
    const saturation = if (chroma < stops[1]) blk: {
        const slope = 0.8 * stops[0];
        break :blk 0.8 * (chroma / (slope + (1 - slope / stops[1]) * chroma));
    } else blk: {
        const slope = (0.2 * square(stops[1]) * square(1.25)) / stops[0];
        const offset = chroma - stops[1];
        break :blk 0.8 + 0.2 * (offset / (slope + (1 - slope / (stops[2] - stops[1])) * offset));
    };
    return .{ .h = hue, .s = @min(1, @max(0, saturation)), .l = lightness };
}
fn jsonNumber(value: std.json.Value) f64 {
    return switch (value) {
        .integer => @floatFromInt(value.integer),
        .float => value.float,
        else => unreachable,
    };
}
test "native Oklab and OKHSL reproduce 1039 actual original conversions gamut endpoints and fractional RGB" {
    var capture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/oklab-original-7fb.json"), .{});
    defer capture.deinit();
    for (capture.value.object.get("cases").?.array.items, 0..) |case, index| {
        if (std.mem.eql(u8, case.object.get("kind").?.string, "okhsl")) {
            const input = case.object.get("input").?.array.items;
            const actual = okhslToRgb(jsonNumber(input[0]), jsonNumber(input[1]), jsonNumber(input[2]));
            const expected = case.object.get("rgb").?.object;
            if (actual.r != jsonNumber(expected.get("r").?) or actual.g != jsonNumber(expected.get("g").?) or actual.b != jsonNumber(expected.get("b").?)) std.debug.print("OKHSL original case {d}: actual {any}, expected {any}\n", .{ index, actual, expected });
            try std.testing.expectEqual(jsonNumber(expected.get("r").?), actual.r);
            try std.testing.expectEqual(jsonNumber(expected.get("g").?), actual.g);
            try std.testing.expectEqual(jsonNumber(expected.get("b").?), actual.b);
        } else {
            const input = case.object.get("input").?.object;
            const rgb: Rgb = .{ .r = jsonNumber(input.get("r").?), .g = jsonNumber(input.get("g").?), .b = jsonNumber(input.get("b").?) };
            const lab = rgbToOklab(rgb);
            for (lab, case.object.get("lab").?.array.items) |actual, expected| try std.testing.expectApproxEqAbs(jsonNumber(expected), actual, 1e-10);
            const okhsl = rgbToOkhsl(rgb);
            const expected = case.object.get("okhsl").?.object;
            try std.testing.expectApproxEqAbs(jsonNumber(expected.get("h").?), okhsl.h, 1e-10);
            try std.testing.expectApproxEqAbs(jsonNumber(expected.get("s").?), okhsl.s, 1e-10);
            try std.testing.expectApproxEqAbs(jsonNumber(expected.get("l").?), okhsl.l, 1e-10);
        }
    }
}
