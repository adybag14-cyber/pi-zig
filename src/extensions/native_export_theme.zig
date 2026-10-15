//! Source HTML-export theme selection, concrete CSS colors and explicit JSON export colors.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const theme = @import("native_theme.zig");
const color = @import("native_color.zig");
const c = em.c;
fn effective(scope: *Scope, name: c.JSValue) !c.JSValue {
    if (!@import("native_sdk_prompt_scope.zig").nullish(name)) return name;
    const current = try scope.get(try scope.own(try theme.moduleState(scope.engine)), "currentThemeName");
    return if (@import("native_sdk_prompt_scope.zig").nullish(current)) scope.text("system") else current;
}
pub fn resolved(engine: *em.Engine, name: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const instance = try scope.own(try theme.loadByValue(engine, try effective(&scope, name), null));
    const colors = try scope.get(instance, "colors");
    const result = try scope.object();
    var names: [*c]c.JSPropertyEnum = null;
    var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, colors, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    for (names[0..count]) |entry| {
        const value = try scope.own(try engine.checked(c.JS_GetProperty(engine.context, colors, entry.atom)));
        const concrete = (try color.read(engine, value)) orelse return error.RequiredConcreteThemeColor;
        const hex = try color.colors.colorToHex(engine.gpa, concrete);
        defer engine.gpa.free(hex);
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, c.JS_DupValue(engine.context, try scope.text(hex)), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    }
    return c.JS_DupValue(engine.context, result);
}
fn loadJson(scope: *Scope, name: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const raw_name = try engine.toString(name);
    defer engine.gpa.free(raw_name);
    var raw: []u8 = undefined;
    if (std.mem.eql(u8, raw_name, "dark") or std.mem.eql(u8, raw_name, "light")) {
        if (engine.native_io != null) {
            const sources = try scope.own(try @import("native_theme_assets.zig").builtinSources(engine));
            raw = try engine.toString(try scope.own(try js.getKey(engine, sources, name)));
        } else raw = try engine.gpa.dupe(u8, if (std.mem.eql(u8, raw_name, "dark")) @embedFile("../themes/fixtures/dark-original-6fb.json") else @embedFile("../themes/fixtures/light-original-6fb.json"));
    } else {
        const registry = try scope.get(try scope.own(try theme.moduleState(engine)), "registeredThemes");
        const registered = try scope.invoke(registry, "get", &.{name});
        const source_path = if (scope.truthy(registered)) try scope.get(registered, "sourcePath") else c.pi_js_undefined();
        const path = if (scope.truthy(source_path)) try engine.toString(source_path) else blk: {
            if (scope.truthy(registered)) return error.RegisteredThemeWithoutSourcePath;
            const directory = try @import("native_theme_watch.zig").directory(engine);
            defer engine.gpa.free(directory);
            const filename = try std.fmt.allocPrint(engine.gpa, "{s}.json", .{raw_name});
            defer engine.gpa.free(filename);
            break :blk try @import("node_path.zig").join(engine.gpa, &.{ directory, filename }, if (builtin.os.tag == .windows) .win32 else .posix);
        };
        defer engine.gpa.free(path);
        raw = try std.Io.Dir.cwd().readFileAlloc(engine.native_io orelse return error.NativeIoUnavailable, path, engine.gpa, .limited(4 * 1024 * 1024));
    }
    defer engine.gpa.free(raw);
    // Use the actual Theme parser/validator before inspecting the original JSON.
    const validated = try scope.own(try theme.fromJson(engine, raw, null, null));
    _ = validated;
    const input = if (std.mem.startsWith(u8, raw, "\xef\xbb\xbf")) raw[3..] else raw;
    const terminated = try engine.gpa.dupeZ(u8, input);
    defer engine.gpa.free(terminated);
    return scope.own(try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, terminated.len, "export-theme.json")));
}
fn resolve(scope: *Scope, value: c.JSValue, vars: c.JSValue, visited: *std.StringHashMapUnmanaged(void)) anyerror!c.JSValue {
    if (c.JS_IsNumber(value)) return value;
    const text = try scope.engine.toString(value);
    defer scope.engine.gpa.free(text);
    if (text.len == 0 or text[0] == '#' or (text.len >= 6 and (std.ascii.eqlIgnoreCase(text[0..6], "oklch(") or std.ascii.eqlIgnoreCase(text[0..6], "okhsl(")))) return value;
    if (visited.contains(text)) return error.CircularExportColorVariable;
    if (visited.count() >= 4096) return error.ThemeVariableLimit;
    const key = try scope.text(text);
    if (!try js.hasKey(scope.engine, vars, key)) return error.ExportColorVariableNotFound;
    const copied = try scope.engine.gpa.dupe(u8, text);
    errdefer scope.engine.gpa.free(copied);
    try visited.put(scope.engine.gpa, copied, {});
    return resolve(scope, try scope.own(try js.getKey(scope.engine, vars, key)), vars, visited);
}
fn explicitValue(scope: *Scope, value: c.JSValue, vars: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value)) return value;
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = visited.keyIterator();
        while (keys.next()) |key| scope.engine.gpa.free(key.*);
        visited.deinit(scope.engine.gpa);
    }
    const found = try resolve(scope, value, vars, &visited);
    const concrete = if (c.JS_IsNumber(found)) try color.colors.indexedColor(try color.number(scope.engine, found)) else blk: {
        const text = try scope.engine.toString(found);
        defer scope.engine.gpa.free(text);
        if (text.len == 0) return c.pi_js_undefined();
        if (text.len < 6 or !std.ascii.eqlIgnoreCase(text[0..6], "okhsl(")) return found;
        break :blk try color.colors.parseColor(text);
    };
    const hex = try color.colors.colorToHex(scope.engine.gpa, concrete);
    defer scope.engine.gpa.free(hex);
    return scope.text(hex);
}
fn explicitImpl(engine: *em.Engine, name: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const selected = try effective(&scope, name);
    if (scope.equal(selected, try scope.text("system"))) return js.object(engine);
    const document = try loadJson(&scope, selected);
    const section = try scope.get(document, "export");
    if (!scope.truthy(section)) return js.object(engine);
    const variables = try scope.get(document, "vars");
    const vars = if (@import("native_sdk_prompt_scope.zig").nullish(variables)) try scope.object() else variables;
    const result = try scope.object();
    inline for (.{ "pageBg", "cardBg", "infoBg" }) |key| try scope.put(result, key, try explicitValue(&scope, try scope.get(section, key), vars));
    return c.JS_DupValue(engine.context, result);
}
pub fn explicit(engine: *em.Engine, name: c.JSValue) !c.JSValue {
    return explicitImpl(engine, name) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = null;
        return js.object(engine);
    };
}
fn parseRgb(text: []const u8) ?[3]f64 {
    if (text.len == 7 and text[0] == '#') {
        var rgb: [3]f64 = undefined;
        for (&rgb, 0..) |*channel, i| channel.* = @floatFromInt(std.fmt.parseInt(u8, text[1 + i * 2 .. 3 + i * 2], 16) catch return null);
        return rgb;
    }
    if (!std.mem.startsWith(u8, text, "rgb")) return null;
    var at: usize = 3;
    while (at < text.len and std.ascii.isWhitespace(text[at])) at += 1;
    if (at == text.len or text[at] != '(') return null;
    at += 1;
    var rgb: [3]f64 = undefined;
    for (&rgb, 0..) |*channel, i| {
        while (at < text.len and std.ascii.isWhitespace(text[at])) at += 1;
        const begin = at;
        while (at < text.len and std.ascii.isDigit(text[at])) at += 1;
        if (begin == at) return null;
        channel.* = std.fmt.parseFloat(f64, text[begin..at]) catch return null;
        while (at < text.len and std.ascii.isWhitespace(text[at])) at += 1;
        if (at == text.len or text[at] != (if (i < 2) @as(u8, ',') else ')')) return null;
        at += 1;
    }
    return if (at == text.len) rgb else null;
}
fn rgbValue(scope: *Scope, rgb: [3]f64) !c.JSValue {
    const text = try std.fmt.allocPrint(scope.engine.gpa, "rgb({d}, {d}, {d})", .{ rgb[0], rgb[1], rgb[2] });
    defer scope.engine.gpa.free(text);
    return scope.text(text);
}
pub fn derived(engine: *em.Engine, base: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const raw = try engine.toString(base);
    defer engine.gpa.free(raw);
    const result = try scope.object();
    const rgb = parseRgb(raw) orelse {
        inline for (.{ "pageBg", "cardBg", "infoBg" }, .{ "rgb(24, 24, 30)", "rgb(30, 30, 36)", "rgb(60, 55, 40)" }) |key, value| try scope.put(result, key, try scope.text(value));
        return c.JS_DupValue(engine.context, result);
    };
    var linear: [3]f64 = undefined;
    for (&linear, rgb) |*out, channel| {
        const s = channel / 255;
        out.* = if (s <= 0.03928) s / 12.92 else std.math.pow(f64, (s + 0.055) / 1.055, 2.4);
    }
    const light = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2] > 0.5;
    var page: [3]f64 = undefined;
    var card: [3]f64 = undefined;
    for (rgb, &page, &card) |channel, *p, *card_channel| {
        p.* = @min(255, @max(0, @floor(channel * (if (light) @as(f64, 0.96) else 0.7) + 0.5)));
        card_channel.* = @min(255, @max(0, @floor(channel * 0.85 + 0.5)));
    }
    try scope.put(result, "pageBg", try rgbValue(&scope, page));
    try scope.put(result, "cardBg", if (light) base else try rgbValue(&scope, card));
    try scope.put(result, "infoBg", try rgbValue(&scope, if (light) .{ @min(255, rgb[0] + 10), @min(255, rgb[1] + 5), @max(0, rgb[2] - 20) } else .{ @min(255, rgb[0] + 20), @min(255, rgb[1] + 15), rgb[2] }));
    return c.JS_DupValue(engine.context, result);
}
