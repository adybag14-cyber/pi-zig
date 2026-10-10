//! Pi's concrete color API, implemented in Zig on the owning QuickJS VM.
const std = @import("std");
const engine_mod = @import("engine.zig");
pub const colors = @import("../tui/colors.zig");
const c = engine_mod.c;
const Method = enum(c_int) { indexedColor, rgbColor, oklchColor, okhslColor, parseColor, colorToRgb, colorToOklch, colorToOkhsl, colorToHex, mixColors, foregroundAnsi, backgroundAnsi, styleText, styleTextWithAnsi, oklabToOkhslLightness };

fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, flags) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
}
fn get(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
pub fn number(engine: *engine_mod.Engine, value: c.JSValue) !f64 {
    var result: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    return result;
}
pub fn throwError(engine: *engine_mod.Engine, message: []const u8) anyerror {
    const exception = engine.checked(c.JS_NewError(engine.context)) catch |err| return err;
    const text = engine.checked(c.JS_NewStringLen(engine.context, message.ptr, message.len)) catch |err| {
        engine.freeValue(exception);
        return err;
    };
    put(engine, exception, "message", text, c.JS_PROP_C_W_E) catch |err| {
        engine.freeValue(exception);
        return err;
    };
    _ = engine.checked(c.JS_Throw(engine.context, exception)) catch |err| return err;
    unreachable;
}
fn invalid(engine: *engine_mod.Engine, value: c.JSValue, prefix: []const u8) anyerror {
    const text = engine.toString(value) catch |err| return err;
    defer engine.gpa.free(text);
    const message = std.fmt.allocPrint(engine.gpa, "{s}{s}", .{ prefix, text }) catch |err| return err;
    defer engine.gpa.free(message);
    return throwError(engine, message);
}
fn finite(engine: *engine_mod.Engine, value: c.JSValue, name: []const u8) !f64 {
    const result = if (c.JS_IsNumber(value)) try number(engine, value) else std.math.nan(f64);
    if (!std.math.isFinite(result)) {
        const message = try std.fmt.allocPrint(engine.gpa, "{s} must be finite", .{name});
        defer engine.gpa.free(message);
        return throwError(engine, message);
    }
    return result;
}
fn bounded(engine: *engine_mod.Engine, value: c.JSValue, name: []const u8, maximum: f64) !f64 {
    const result = try finite(engine, value, name);
    if (result < 0 or result > maximum) {
        const prefix = try std.fmt.allocPrint(engine.gpa, "{s} must be between 0 and {d}: ", .{ name, maximum });
        defer engine.gpa.free(prefix);
        return invalid(engine, value, prefix);
    }
    return result;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn channels(engine: *engine_mod.Engine, object: c.JSValue, comptime names: anytype) ![names.len]f64 {
    var rooted: [names.len]c.JSValue = undefined;
    var count: usize = 0;
    defer for (rooted[0..count]) |value| engine.freeValue(value);
    inline for (names, 0..) |name, index| {
        rooted[index] = try get(engine, object, name);
        count += 1;
    }
    var result: [names.len]f64 = undefined;
    inline for (names, 0..) |_, index| result[index] = try number(engine, rooted[index]);
    return result;
}
pub fn read(engine: *engine_mod.Engine, value: c.JSValue) !?colors.Color {
    const kind = try get(engine, value, "kind");
    defer engine.freeValue(kind);
    if (!c.JS_IsString(kind)) return null;
    const name = try engine.toString(kind);
    defer engine.gpa.free(name);
    if (std.mem.eql(u8, name, "rgb")) {
        const fields = try channels(engine, value, .{ "r", "g", "b" });
        return .{ .rgb = .{ .r = fields[0], .g = fields[1], .b = fields[2] } };
    }
    if (std.mem.eql(u8, name, "oklch")) {
        const fields = try channels(engine, value, .{ "l", "c", "h" });
        return .{ .oklch = .{ .l = fields[0], .c = fields[1], .h = fields[2] } };
    }
    if (std.mem.eql(u8, name, "indexed")) {
        const fields = try channels(engine, value, .{"index"});
        // Constructor-created values always satisfy this; malformed structural
        // inputs must not reach a Zig float-to-integer trap.
        if (!std.math.isFinite(fields[0]) or fields[0] < 0 or fields[0] > 255 or fields[0] != @floor(fields[0])) return error.InvalidStructuralColor;
        return .{ .indexed = @intFromFloat(fields[0]) };
    }
    return null;
}
fn record(engine: *engine_mod.Engine, comptime names: anytype, values: [names.len]f64) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    inline for (names, 0..) |name, index| try put(engine, object, name, c.JS_NewFloat64(engine.context, values[index]), c.JS_PROP_C_W_E);
    return object;
}
pub fn create(engine: *engine_mod.Engine, value: colors.Color) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try put(engine, object, "kind", try engine.checked(c.JS_NewString(engine.context, @tagName(value))), c.JS_PROP_C_W_E);
    switch (value) {
        .indexed => |index| try put(engine, object, "index", c.JS_NewInt32(engine.context, index), c.JS_PROP_C_W_E),
        .rgb => |rgb| {
            try put(engine, object, "r", c.JS_NewFloat64(engine.context, rgb.r), c.JS_PROP_C_W_E);
            try put(engine, object, "g", c.JS_NewFloat64(engine.context, rgb.g), c.JS_PROP_C_W_E);
            try put(engine, object, "b", c.JS_NewFloat64(engine.context, rgb.b), c.JS_PROP_C_W_E);
        },
        .oklch => |lch| {
            try put(engine, object, "l", c.JS_NewFloat64(engine.context, lch.l), c.JS_PROP_C_W_E);
            try put(engine, object, "c", c.JS_NewFloat64(engine.context, lch.c), c.JS_PROP_C_W_E);
            try put(engine, object, "h", c.JS_NewFloat64(engine.context, lch.h), c.JS_PROP_C_W_E);
        },
    }
    try freeze(engine, object);
    return object;
}
pub fn freeze(engine: *engine_mod.Engine, object: c.JSValue) !void {
    // Use the intrinsic, rather than user-replaceable Object.freeze.
    var names: [*c]c.JSPropertyEnum = null;
    var length: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &length, object, c.JS_GPN_STRING_MASK) < 0) return error.OutOfMemory;
    defer c.JS_FreePropertyEnum(engine.context, names, length);
    for (names[0..length]) |property| {
        if (c.JS_DefineProperty(engine.context, object, property.atom, c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined(), c.JS_PROP_HAS_CONFIGURABLE | c.JS_PROP_HAS_WRITABLE) < 0) return error.JavaScriptException;
    }
    if (c.JS_PreventExtensions(engine.context, object) < 0) return error.JavaScriptException;
}
pub fn mode(engine: *engine_mod.Engine, value: c.JSValue) !colors.ColorMode {
    if (!c.JS_IsString(value)) return .@"256color";
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return if (std.mem.eql(u8, text, "truecolor")) .truecolor else .@"256color";
}
fn string(engine: *engine_mod.Engine, text: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn truth(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try get(engine, object, name);
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) != 0;
}
pub fn style(engine: *engine_mod.Engine, text: c.JSValue, foreground: c.JSValue, background: c.JSValue, options: c.JSValue) !c.JSValue {
    var prefix: std.ArrayList(u8) = .empty;
    defer prefix.deinit(engine.gpa);
    var suffix: std.ArrayList(u8) = .empty;
    defer suffix.deinit(engine.gpa);
    inline for (.{ .{ foreground, "\x1b[39m" }, .{ background, "\x1b[49m" } }) |item| {
        if (c.JS_ToBool(engine.context, item[0]) != 0) {
            const opening = try engine.toString(item[0]);
            defer engine.gpa.free(opening);
            try prefix.appendSlice(engine.gpa, opening);
            try suffix.insertSlice(engine.gpa, 0, item[1]);
        }
    }
    // Repeated reads and short-circuiting are observable for JS accessor options.
    if (try truth(engine, options, "bold")) try prefix.appendSlice(engine.gpa, "\x1b[1m");
    if (try truth(engine, options, "dim")) try prefix.appendSlice(engine.gpa, "\x1b[2m");
    if (try truth(engine, options, "bold") or try truth(engine, options, "dim")) try suffix.insertSlice(engine.gpa, 0, "\x1b[22m");
    inline for (.{ .{ "italic", "\x1b[3m", "\x1b[23m" }, .{ "underline", "\x1b[4m", "\x1b[24m" }, .{ "inverse", "\x1b[7m", "\x1b[27m" }, .{ "strikethrough", "\x1b[9m", "\x1b[29m" } }) |item| {
        if (try truth(engine, options, item[0])) {
            try prefix.appendSlice(engine.gpa, item[1]);
            try suffix.insertSlice(engine.gpa, 0, item[2]);
        }
    }
    const body = try engine.toString(text);
    defer engine.gpa.free(body);
    try prefix.appendSlice(engine.gpa, body);
    try prefix.appendSlice(engine.gpa, suffix.items);
    return string(engine, prefix.items);
}
pub fn ansiValue(engine: *engine_mod.Engine, value: c.JSValue, color_mode: colors.ColorMode, background: bool) !c.JSValue {
    const kind = try get(engine, value, "kind");
    defer engine.freeValue(kind);
    if (c.JS_IsString(kind)) {
        const name = try engine.toString(kind);
        defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "indexed")) {
            const index = try get(engine, value, "index");
            defer engine.freeValue(index);
            const index_text = try engine.toString(index);
            defer engine.gpa.free(index_text);
            const result = try std.fmt.allocPrint(engine.gpa, "\x1b[{d};5;{s}m", .{ @as(u8, if (background) 48 else 38), index_text });
            defer engine.gpa.free(result);
            return string(engine, result);
        }
    }
    const color = (try read(engine, value)) orelse return engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of undefined (reading 'r')"));
    if (color_mode == .truecolor) {
        const rgb = colors.colorToRgb(color);
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(engine.gpa);
        try text.appendSlice(engine.gpa, if (background) "\x1b[48;2;" else "\x1b[38;2;");
        for ([_]f64{ rgb.r, rgb.g, rgb.b }, 0..) |channel, index| {
            if (index != 0) try text.append(engine.gpa, ';');
            const rounded = c.JS_NewFloat64(engine.context, jsRound(channel));
            const numeric = try engine.toString(rounded);
            defer engine.gpa.free(numeric);
            try text.appendSlice(engine.gpa, numeric);
        }
        try text.append(engine.gpa, 'm');
        return string(engine, text.items);
    }
    const text = try colors.colorAnsi(engine.gpa, color, color_mode, background);
    defer engine.gpa.free(text);
    return string(engine, text);
}
fn jsRound(value: f64) f64 {
    if (!std.math.isFinite(value) or @abs(value) >= 4503599627370496) return value;
    const floor = @floor(value);
    const rounded = if (value - floor >= 0.5) floor + 1 else floor;
    return if (rounded == 0 and value < 0) -0.0 else rounded;
}
fn hexValue(engine: *engine_mod.Engine, rgb: colors.Rgb) !c.JSValue {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(engine.gpa);
    try result.append(engine.gpa, '#');
    for ([_]f64{ rgb.r, rgb.g, rgb.b }) |channel| {
        const value = c.JS_NewFloat64(engine.context, jsRound(channel));
        const method = try get(engine, value, "toString");
        defer engine.freeValue(method);
        var args = [_]c.JSValue{c.JS_NewInt32(engine.context, 16)};
        const radix = try engine.checked(c.JS_Call(engine.context, method, value, 1, &args));
        defer engine.freeValue(radix);
        const digits = try engine.toString(radix);
        defer engine.gpa.free(digits);
        if (digits.len < 2) try result.append(engine.gpa, '0');
        try result.appendSlice(engine.gpa, digits);
    }
    return string(engine, result.items);
}
fn constructorColor(engine: *engine_mod.Engine, method: Method, args: []const c.JSValue) !colors.Color {
    switch (method) {
        .indexedColor => {
            const index = if (c.JS_IsNumber(arg(args, 0))) try number(engine, arg(args, 0)) else std.math.nan(f64);
            return colors.indexedColor(index) catch return invalid(engine, arg(args, 0), "ANSI color index must be an integer from 0 to 255: ");
        },
        .rgbColor => return colors.rgbColor(try bounded(engine, arg(args, 0), "r", 255), try bounded(engine, arg(args, 1), "g", 255), try bounded(engine, arg(args, 2), "b", 255)),
        .okhslColor, .oklchColor => {
            const names = if (method == .okhslColor) [3][]const u8{ "h", "s", "l" } else [3][]const u8{ "l", "c", "h" };
            const first = try finite(engine, arg(args, 0), names[0]);
            const second = try finite(engine, arg(args, 1), names[1]);
            const third = try finite(engine, arg(args, 2), names[2]);
            if (method == .okhslColor) {
                _ = try bounded(engine, arg(args, 1), "s", 1);
                _ = try bounded(engine, arg(args, 2), "l", 1);
                return colors.okhslColor(first, second, third);
            }
            _ = try bounded(engine, arg(args, 0), "l", 1);
            if (second < 0) return invalid(engine, arg(args, 1), "c must not be negative: ");
            return colors.oklchColor(first, second, third);
        },
        else => unreachable,
    }
}
pub fn parse(engine: *engine_mod.Engine, value: c.JSValue) !colors.Color {
    if (c.JS_IsNumber(value)) return constructorColor(engine, .indexedColor, &.{value});
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    const parsed = colors.parseChannels(text) catch return invalid(engine, value, "Invalid color value: ");
    const method_kind: Method, const fields: [3]f64 = switch (parsed) {
        .rgb => |rgb| .{ .rgbColor, .{ rgb.r, rgb.g, rgb.b } },
        .okhsl => |hsl| .{ .okhslColor, .{ hsl.h, hsl.s, hsl.l } },
        .oklch => |lch| .{ .oklchColor, .{ lch.l, lch.c, lch.h } },
    };
    const values = [_]c.JSValue{ c.JS_NewFloat64(engine.context, fields[0]), c.JS_NewFloat64(engine.context, fields[1]), c.JS_NewFloat64(engine.context, fields[2]) };
    return constructorColor(engine, method_kind, &values);
}
fn operation(engine: *engine_mod.Engine, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .oklabToOkhslLightness => return c.JS_NewFloat64(engine.context, @import("../tui/oklab.zig").oklabToOkhslLightness(try number(engine, arg(args, 0)))),
        .indexedColor, .rgbColor, .oklchColor, .okhslColor => return create(engine, try constructorColor(engine, method, args)),
        .parseColor => return create(engine, try parse(engine, arg(args, 0))),
        .styleTextWithAnsi => return style(engine, arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3)),
        .styleText => {
            const options = arg(args, 1);
            const color_mode = try mode(engine, arg(args, 2));
            const fg = try get(engine, options, "fg");
            defer engine.freeValue(fg);
            const foreground = if (c.JS_ToBool(engine.context, fg) != 0) blk: {
                const again = try get(engine, options, "fg");
                defer engine.freeValue(again);
                break :blk try ansiValue(engine, again, color_mode, false);
            } else c.JS_DupValue(engine.context, fg);
            defer engine.freeValue(foreground);
            const bg = try get(engine, options, "bg");
            defer engine.freeValue(bg);
            const background = if (c.JS_ToBool(engine.context, bg) != 0) blk: {
                const again = try get(engine, options, "bg");
                defer engine.freeValue(again);
                break :blk try ansiValue(engine, again, color_mode, true);
            } else c.JS_DupValue(engine.context, bg);
            defer engine.freeValue(background);
            return style(engine, arg(args, 0), foreground, background, options);
        },
        .foregroundAnsi, .backgroundAnsi => return ansiValue(engine, arg(args, 0), try mode(engine, arg(args, 1)), method == .backgroundAnsi),
        .mixColors => {
            const amount = try bounded(engine, arg(args, 2), "amount", 1);
            var space: colors.MixSpace = .oklch;
            if (c.JS_IsString(arg(args, 3))) {
                const text = try engine.toString(arg(args, 3));
                defer engine.gpa.free(text);
                if (std.mem.eql(u8, text, "srgb")) space = .srgb;
            }
            const first = (try read(engine, arg(args, 0))) orelse return engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of undefined (reading 'r')"));
            const second = (try read(engine, arg(args, 1))) orelse return engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of undefined (reading 'r')"));
            const method_kind: Method, const fields: [3]f64 = if (space == .srgb) blk: {
                const a = colors.colorToRgb(first);
                const b = colors.colorToRgb(second);
                break :blk .{ .rgbColor, .{ a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount, a.b + (b.b - a.b) * amount } };
            } else blk: {
                const a = colors.colorToOklch(first);
                const b = colors.colorToOklch(second);
                const first_hue = if (a.c < 1e-7) b.h else a.h;
                const second_hue = if (b.c < 1e-7) first_hue else b.h;
                const delta = @rem(second_hue - first_hue + 540, 360) - 180;
                break :blk .{ .oklchColor, .{ a.l + (b.l - a.l) * amount, a.c + (b.c - a.c) * amount, first_hue + delta * amount } };
            };
            const values = [_]c.JSValue{ c.JS_NewFloat64(engine.context, fields[0]), c.JS_NewFloat64(engine.context, fields[1]), c.JS_NewFloat64(engine.context, fields[2]) };
            return create(engine, try constructorColor(engine, method_kind, &values));
        },
        else => {},
    }
    const color = (try read(engine, arg(args, 0))) orelse {
        if (method == .colorToRgb) return c.pi_js_undefined();
        return engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot read properties of undefined (reading 'r')"));
    };
    switch (method) {
        .colorToRgb => {
            const rgb = colors.colorToRgb(color);
            return record(engine, .{ "r", "g", "b" }, .{ rgb.r, rgb.g, rgb.b });
        },
        .colorToOklch => {
            const lch = colors.colorToOklch(color);
            return record(engine, .{ "l", "c", "h" }, .{ lch.l, lch.c, lch.h });
        },
        .colorToOkhsl => {
            const hsl = colors.colorToOkhsl(color);
            return record(engine, .{ "h", "s", "l" }, .{ hsl.h, hsl.s, hsl.l });
        },
        .colorToHex => {
            return hexValue(engine, colors.colorToRgb(color));
        },
        else => unreachable,
    }
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return operation(engine, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(context);
        return c.JS_ThrowTypeError(context, "Native color: %s", @as([*:0]const u8, @errorName(err)));
    };
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = if (field.value == @intFromEnum(Method.oklabToOkhslLightness)) 1 else 3;
        try put(engine, exports, name.ptr, try engine.checked(c.pi_js_function_magic(engine.context, call, name.ptr, length, @intCast(field.value))), c.JS_PROP_C_W_E);
    }
}
