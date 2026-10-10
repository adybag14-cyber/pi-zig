//! Private Source UTF16 ANSI, grapheme-cell, OSC8 and background operations.
const std = @import("std");
const a = @import("native_tui_alt_frame.zig");
const Frame = a.Frame;
const c = a.c;
const js = a.js;
const v = a.v;
const utf = @import("native_utf16.zig");
const term = @import("../tui/utf16_terminal.zig");
const graphemes = @import("../tui/utf16_graphemes.zig");
const Method = enum(c_int) { extractAnsiCode, getGraphemeCellRange, getOsc8LinkAtColumn, getActiveBackgroundAnsi };
fn string(f: *Frame, units: []const u16) !c.JSValue {
    return f.own(try utf.string(f.engine, units));
}
pub fn ansi(f: *Frame, text: c.JSValue, index: f64) !c.JSValue {
    const units = try utf.unitsAlloc(f.engine, text);
    defer f.engine.gpa.free(units);
    if (!std.math.isFinite(index) or index < 0 or index >= @as(f64, @floatFromInt(units.len))) return c.pi_js_null();
    const start: usize = @intFromFloat(index);
    const count = term.ansiLength(units, start);
    if (count == 0) return c.pi_js_null();
    const output = try f.record();
    try f.define(output, "code", try f.method(text, "substring", &.{ f.num(index), f.num(index + @as(f64, @floatFromInt(count))) }));
    try f.define(output, "length", f.num(@floatFromInt(count)));
    return output;
}
fn cellOrLink(f: *Frame, line: c.JSValue, column: f64, link: bool) !c.JSValue {
    const units = try utf.unitsAlloc(f.engine, line);
    defer f.engine.gpa.free(units);
    var index: usize = 0;
    var current: f64 = 0;
    var url: c.JSValue = c.pi_js_undefined();
    while (index < units.len) {
        const length = term.ansiLength(units, index);
        if (length > 0) {
            if (link) {
                const code = try string(f, units[index..][0..length]);
                const regex = try f.get(f.bindings, "osc8Pattern");
                const match = try f.method(regex, "exec", &.{code});
                if (f.truth(match)) {
                    const candidate = try f.at(match, 1);
                    url = if (f.truth(candidate)) candidate else c.pi_js_undefined();
                }
            }
            index += length;
            continue;
        }
        var end = index;
        while (end < units.len and term.ansiLength(units, end) == 0) : (end += 1) {}
        var iterator: graphemes.Iterator = .{ .text = units[index..end] };
        while (iterator.next()) |piece| {
            const value = units[index + piece.start .. index + piece.end];
            const width: f64 = if (link and value.len == 1 and value[0] == '\t') 3 else @floatFromInt(try term.graphemeWidth(f.engine.gpa, value));
            if ((link or width > 0) and column >= current and column < current + width) {
                if (link) return url;
                const result = try f.record();
                try f.define(result, "start", f.num(current));
                try f.define(result, "end", f.num(current + width));
                return result;
            }
            current += width;
        }
        index = end;
    }
    return c.pi_js_undefined();
}
fn background(f: *Frame, text: c.JSValue) !c.JSValue {
    var color: c.JSValue = c.pi_js_undefined();
    var index: f64 = 0;
    while (index < try f.n(text, "length")) {
        const escape = try ansi(f, text, index);
        if (!f.truth(escape)) {
            index += 1;
            continue;
        }
        const code = try f.get(escape, "code");
        index += try f.n(escape, "length");
        if (!f.truth(try f.method(code, "endsWith", &.{try f.text("m")}))) continue;
        const match = try f.method(code, "match", &.{try f.get(f.bindings, "sgrPattern")});
        if (!f.truth(match)) continue;
        const parameters = try f.at(match, 1);
        if (try f.is(parameters, "") or try f.is(parameters, "0")) {
            color = c.pi_js_undefined();
            continue;
        }
        const parts = try f.method(parameters, "split", &.{try f.text(";")});
        var part: f64 = 0;
        while (part < try f.n(parts, "length")) {
            const number = try f.number(try f.method(try f.global("Number"), "parseInt", &.{ try f.at(parts, part), f.num(10) }));
            if (number == 38 or number == 48) {
                var count: f64 = 0;
                if (try f.is(try f.at(parts, part + 1), "5") and !c.JS_IsUndefined(try f.at(parts, part + 2))) count = 3 else if (try f.is(try f.at(parts, part + 1), "2") and !c.JS_IsUndefined(try f.at(parts, part + 4))) count = 5;
                if (count > 0) {
                    if (number == 48) color = try f.method(try f.method(parts, "slice", &.{ f.num(part), f.num(part + count) }), "join", &.{try f.text(";")});
                    part += count;
                    continue;
                }
            }
            if (number == 0 or number == 49) color = c.pi_js_undefined() else if ((number >= 40 and number <= 47) or (number >= 100 and number <= 107)) color = try f.call(try f.global("String"), c.pi_js_undefined(), &.{f.num(number)});
            part += 1;
        }
    }
    return if (f.truth(color)) f.concat(&.{ try f.text("\x1b["), color, try f.text("m") }) else f.text("");
}
fn call(ctx: ?*c.JSContext, this: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(ctx.?);
    var f: Frame = .{ .engine = engine, .object = this, .bindings = data[0] };
    defer f.deinit();
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    const output = (switch (@as(Method, @enumFromInt(magic))) {
        .extractAnsiCode => ansi(&f, v.arg(args, 0), f.number(v.arg(args, 1)) catch |err| return a.fail(engine, err)),
        .getGraphemeCellRange => cellOrLink(&f, v.arg(args, 0), f.number(v.arg(args, 1)) catch |err| return a.fail(engine, err), false),
        .getOsc8LinkAtColumn => cellOrLink(&f, v.arg(args, 0), f.number(v.arg(args, 1)) catch |err| return a.fail(engine, err), true),
        .getActiveBackgroundAnsi => background(&f, v.arg(args, 0)),
    }) catch |err| return a.fail(engine, err);
    return f.result(output);
}
pub fn install(engine: *js.Engine, bindings: c.JSValue) !void {
    try js.define(engine, bindings, "osc8Pattern", try @import("native_tui_base_utilities.zig").regexp(engine, "^\x1b\\]8;[^;]*;([^\\x07\\x1b]*)(?:\\x07|\\x1b\\\\)$", ""));
    try js.define(engine, bindings, "sgrPattern", try @import("native_tui_base_utilities.zig").regexp(engine, "\x1b\\[([\\d;]*)m", ""));
    var data = [_]c.JSValue{bindings};
    inline for (std.meta.fields(Method)) |field| try js.define(engine, bindings, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, if (@as(Method, @enumFromInt(field.value)) == .getActiveBackgroundAnsi) 1 else 2, field.value, 1, &data)));
}
