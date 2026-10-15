//! Source export-html/ansi-to-html.ts presentation over lossless JS strings.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const utf16 = @import("native_utf16.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const palette = [_][]const u8{
    "#000000", "#800000", "#008000", "#808000", "#000080", "#800080", "#008080", "#c0c0c0",
    "#808080", "#ff0000", "#00ff00", "#ffff00", "#0000ff", "#ff00ff", "#00ffff", "#ffffff",
};
const Style = struct {
    fg: ?[]u8 = null,
    bg: ?[]u8 = null,
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    fn deinit(self: *Style, gpa: std.mem.Allocator) void {
        if (self.fg) |value| gpa.free(value);
        if (self.bg) |value| gpa.free(value);
    }
    fn has(self: *const Style) bool {
        return self.fg != null or self.bg != null or self.bold or self.dim or self.italic or self.underline;
    }
    fn replace(self: *Style, gpa: std.mem.Allocator, background: bool, next: ?[]u8) void {
        const target = if (background) &self.bg else &self.fg;
        if (target.*) |value| gpa.free(value);
        target.* = next;
    }
};
fn append(gpa: std.mem.Allocator, output: *std.ArrayList(u16), text: []const u8) !void {
    const units = try std.unicode.wtf8ToWtf16LeAlloc(gpa, text);
    defer gpa.free(units);
    for (units) |unit| try output.append(gpa, std.mem.littleToNative(u16, unit));
}
fn escaped(gpa: std.mem.Allocator, output: *std.ArrayList(u16), units: []const u16) !void {
    for (units) |unit| switch (unit) {
        '&' => try append(gpa, output, "&amp;"),
        '<' => try append(gpa, output, "&lt;"),
        '>' => try append(gpa, output, "&gt;"),
        '"' => try append(gpa, output, "&quot;"),
        '\'' => try append(gpa, output, "&#039;"),
        else => try output.append(gpa, unit),
    };
}
fn decimal(engine: *em.Engine, value: f64) ![]u8 {
    return engine.toString(c.JS_NewFloat64(engine.context, value));
}
fn hex(engine: *em.Engine, value: f64) ![]u8 {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try scope.invoke(c.JS_NewFloat64(engine.context, value), "toString", &.{c.JS_NewInt32(engine.context, 16)});
    return engine.toString(try scope.invoke(text, "padStart", &.{ c.JS_NewInt32(engine.context, 2), try scope.text("0") }));
}
fn component(value: f64) f64 {
    return if (value == 0) 0 else 55 + value * 40;
}
fn color256(engine: *em.Engine, index: f64) ![]u8 {
    if (index < 16) return engine.gpa.dupe(u8, palette[@intFromFloat(index)]);
    if (index < 232) {
        const cube = index - 16;
        const r = try hex(engine, component(@floor(cube / 36)));
        defer engine.gpa.free(r);
        const g = try hex(engine, component(@floor(@mod(cube, 36) / 6)));
        defer engine.gpa.free(g);
        const b = try hex(engine, component(@mod(cube, 6)));
        defer engine.gpa.free(b);
        return std.fmt.allocPrint(engine.gpa, "#{s}{s}{s}", .{ r, g, b });
    }
    const gray = try hex(engine, 8 + (index - 232) * 10);
    defer engine.gpa.free(gray);
    return std.fmt.allocPrint(engine.gpa, "#{s}{s}{s}", .{ gray, gray, gray });
}
fn rgb(engine: *em.Engine, values: []const f64) ![]u8 {
    const r = try decimal(engine, values[0]);
    defer engine.gpa.free(r);
    const g = try decimal(engine, values[1]);
    defer engine.gpa.free(g);
    const b = try decimal(engine, values[2]);
    defer engine.gpa.free(b);
    return std.fmt.allocPrint(engine.gpa, "rgb({s},{s},{s})", .{ r, g, b });
}
fn apply(engine: *em.Engine, params: []const f64, style: *Style) !void {
    var index: usize = 0;
    while (index < params.len) : (index += 1) {
        const code = params[index];
        if (code == 0) {
            style.deinit(engine.gpa);
            style.* = .{};
        } else if (code == 1) {
            style.bold = true;
        } else if (code == 2) {
            style.dim = true;
        } else if (code == 3) {
            style.italic = true;
        } else if (code == 4) {
            style.underline = true;
        } else if (code == 22) {
            style.bold = false;
            style.dim = false;
        } else if (code == 23) {
            style.italic = false;
        } else if (code == 24) {
            style.underline = false;
        } else if (code >= 30 and code <= 37) {
            style.replace(engine.gpa, false, try engine.gpa.dupe(u8, palette[@intFromFloat(code - 30)]));
        } else if (code == 38 or code == 48) {
            if (params.len > index + 2 and params[index + 1] == 5) {
                style.replace(engine.gpa, code == 48, try color256(engine, params[index + 2]));
                index += 2;
            } else if (params.len > index + 4 and params[index + 1] == 2) {
                style.replace(engine.gpa, code == 48, try rgb(engine, params[index + 2 ..][0..3]));
                index += 4;
            }
        } else if (code == 39 or code == 49) {
            style.replace(engine.gpa, code == 49, null);
        } else if (code >= 40 and code <= 47) {
            style.replace(engine.gpa, true, try engine.gpa.dupe(u8, palette[@intFromFloat(code - 40)]));
        } else if (code >= 90 and code <= 97) {
            style.replace(engine.gpa, false, try engine.gpa.dupe(u8, palette[@intFromFloat(code - 90 + 8)]));
        } else if (code >= 100 and code <= 107) {
            style.replace(engine.gpa, true, try engine.gpa.dupe(u8, palette[@intFromFloat(code - 100 + 8)]));
        }
    }
}
fn css(engine: *em.Engine, style: *const Style, output: *std.ArrayList(u16)) !void {
    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(engine.gpa);
    const fg = if (style.fg) |value| try std.fmt.allocPrint(engine.gpa, "color:{s}", .{value}) else null;
    defer if (fg) |value| engine.gpa.free(value);
    const bg = if (style.bg) |value| try std.fmt.allocPrint(engine.gpa, "background-color:{s}", .{value}) else null;
    defer if (bg) |value| engine.gpa.free(value);
    if (fg) |value| try parts.append(engine.gpa, value);
    if (bg) |value| try parts.append(engine.gpa, value);
    if (style.bold) try parts.append(engine.gpa, "font-weight:bold");
    if (style.dim) try parts.append(engine.gpa, "opacity:0.6");
    if (style.italic) try parts.append(engine.gpa, "font-style:italic");
    if (style.underline) try parts.append(engine.gpa, "text-decoration:underline");
    for (parts.items, 0..) |part, index| {
        if (index != 0) try append(engine.gpa, output, ";");
        try append(engine.gpa, output, part);
    }
}
fn parameters(engine: *em.Engine, text: []const u16) ![]f64 {
    var result: std.ArrayList(f64) = .empty;
    errdefer result.deinit(engine.gpa);
    if (text.len == 0) {
        try result.append(engine.gpa, 0);
    } else {
        var start: usize = 0;
        for (0..text.len + 1) |index| if (index == text.len or text[index] == ';') {
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            const parsed = try scope.call(try scope.global("parseInt"), c.pi_js_undefined(), &.{ try scope.own(try utf16.string(engine, text[start..index])), c.JS_NewInt32(engine.context, 10) });
            var number: f64 = 0;
            if (scope.truthy(parsed) and c.JS_ToFloat64(engine.context, &number, parsed) < 0) return js.capture(engine);
            try result.append(engine.gpa, number);
            start = index + 1;
        };
    }
    return result.toOwnedSlice(engine.gpa);
}
pub fn ansiToHtml(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    const text = try utf16.unitsAlloc(engine, input);
    defer engine.gpa.free(text);
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(engine.gpa);
    var style: Style = .{};
    defer style.deinit(engine.gpa);
    var scan: usize = 0;
    var last: usize = 0;
    var in_span = false;
    while (scan + 2 < text.len) {
        if (text[scan] != 27 or text[scan + 1] != '[') {
            scan += 1;
            continue;
        }
        var end = scan + 2;
        while (end < text.len and ((text[end] >= '0' and text[end] <= '9') or text[end] == ';')) : (end += 1) {}
        if (end == text.len or text[end] != 'm') {
            scan += 1;
            continue;
        }
        try escaped(engine.gpa, &output, text[last..scan]);
        const params = try parameters(engine, text[scan + 2 .. end]);
        defer engine.gpa.free(params);
        if (in_span) {
            try append(engine.gpa, &output, "</span>");
            in_span = false;
        }
        try apply(engine, params, &style);
        if (style.has()) {
            try append(engine.gpa, &output, "<span style=\"");
            try css(engine, &style, &output);
            try append(engine.gpa, &output, "\">");
            in_span = true;
        }
        last = end + 1;
        scan = last;
    }
    try escaped(engine.gpa, &output, text[last..]);
    if (in_span) try append(engine.gpa, &output, "</span>");
    return utf16.string(engine, output.items);
}
fn line(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return lineValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn lineValue(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const body = try scope.own(try ansiToHtml(engine, value));
    return c.JS_DupValue(engine.context, try scope.concat(try scope.concat(try scope.text("<div class=\"ansi-line\">"), if (scope.truthy(body)) body else try scope.text("&nbsp;")), try scope.text("</div>")));
}
pub fn ansiLinesToHtml(engine: *em.Engine, lines: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, line, "", 1)));
    const converted = try scope.invoke(lines, "map", &.{callback});
    return js.invoke(engine, converted, "join", &.{try scope.text("")});
}
