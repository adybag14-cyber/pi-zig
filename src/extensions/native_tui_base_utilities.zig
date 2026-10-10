//! Internal Source string utilities needed by complete TuiBase method bodies.
//! Normalization decomposes AM before recognizing terminal escapes, losslessly.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const terminal = @import("../tui/utf16_terminal.zig");
const Method = enum(c_int) { normalizeTerminalOutput, parseOscColorResponse };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
    return c.JS_ThrowTypeError(engine.context, "Native TuiBase utility: %s", @as([*:0]const u8, @errorName(err)));
}
pub fn regexp(engine: *js.Engine, source: []const u8, flags: []const u8) !c.JSValue {
    const pattern = try v.text(engine, source);
    defer engine.freeValue(pattern);
    const options = try v.text(engine, flags);
    defer engine.freeValue(options);
    var args = [_]c.JSValue{ pattern, options };
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, args.len, &args));
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    return (switch (@as(Method, @enumFromInt(magic))) {
        .normalizeTerminalOutput => normalize(engine, value, data[0]),
        .parseOscColorResponse => parseOsc(engine, value, data[0]),
    }) catch |err| fail(engine, err);
}
fn replaceAm(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const thai = v.text(engine, "\u{0e33}") catch |err| return fail(engine, err);
    defer engine.freeValue(thai);
    return v.text(engine, if (argc > 0 and c.JS_IsStrictEqual(context, argv[0], thai)) "\u{0e4d}\u{0e32}" else "\u{0ecd}\u{0eb2}") catch |err| fail(engine, err);
}
fn normalize(engine: *js.Engine, value: c.JSValue, bindings: c.JSValue) !c.JSValue {
    var normalized = c.JS_DupValue(engine.context, value);
    defer engine.freeValue(normalized);
    const am_pattern = try js.get(engine, bindings, "amPattern");
    defer engine.freeValue(am_pattern);
    const contains_am = try js.invoke(engine, am_pattern, "test", &.{normalized});
    defer engine.freeValue(contains_am);
    if (v.truthy(engine, contains_am)) {
        const replace = try js.get(engine, normalized, "replace");
        defer engine.freeValue(replace);
        const global_pattern = try js.get(engine, bindings, "amGlobalPattern");
        defer engine.freeValue(global_pattern);
        const mapper = try engine.checked(c.JS_NewCFunction2(engine.context, replaceAm, "", 1, c.JS_CFUNC_generic, 0));
        defer engine.freeValue(mapper);
        const decomposed = try js.call(engine, replace, normalized, &.{ global_pattern, mapper });
        engine.freeValue(normalized);
        normalized = decomposed;
    }
    const tab = try v.text(engine, "\t");
    defer engine.freeValue(tab);
    const contains_tab = try js.invoke(engine, normalized, "includes", &.{tab});
    defer engine.freeValue(contains_tab);
    if (!v.truthy(engine, contains_tab)) return c.JS_DupValue(engine.context, normalized);
    const units = try utf16.unitsAlloc(engine, normalized);
    defer engine.gpa.free(units);
    var output: std.ArrayList(u16) = .empty;
    defer output.deinit(engine.gpa);
    var index: usize = 0;
    while (index < units.len) {
        const ansi = terminal.ansiLength(units, index);
        if (ansi > 0) {
            try output.appendSlice(engine.gpa, units[index..][0..ansi]);
            index += ansi;
            continue;
        }
        if (units[index] == '\t') try output.appendSlice(engine.gpa, &.{ ' ', ' ', ' ' }) else try output.append(engine.gpa, units[index]);
        index += 1;
    }
    return utf16.string(engine, output.items);
}
fn parseOsc(engine: *js.Engine, data: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const pattern = try js.get(engine, bindings, "oscColorPattern");
    defer engine.freeValue(pattern);
    const match = try js.invoke(engine, data, "match", &.{pattern});
    defer engine.freeValue(match);
    if (!v.truthy(engine, match)) return c.pi_js_undefined();
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
    defer engine.freeValue(first);
    const ten = try v.text(engine, "10");
    defer engine.freeValue(ten);
    const target = blk: {
        if (c.JS_IsStrictEqual(engine.context, first, ten)) break :blk try v.text(engine, "foreground");
        const current = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 1));
        defer engine.freeValue(current);
        const eleven = try v.text(engine, "11");
        defer engine.freeValue(eleven);
        if (c.JS_IsStrictEqual(engine.context, current, eleven)) break :blk try v.text(engine, "background");
        const number = try js.global(engine, "Number");
        defer engine.freeValue(number);
        const parse = try js.get(engine, number, "parseInt");
        defer engine.freeValue(parse);
        const digits = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 2));
        defer engine.freeValue(digits);
        break :blk try js.call(engine, parse, number, &.{ digits, c.JS_NewInt32(engine.context, 10) });
    };
    defer engine.freeValue(target);
    const result = try js.object(engine);
    errdefer engine.freeValue(result);
    try js.define(engine, result, "target", c.JS_DupValue(engine.context, target));
    const raw = try engine.checked(c.JS_GetPropertyUint32(engine.context, match, 3));
    defer engine.freeValue(raw);
    const trimmed = try js.invoke(engine, raw, "trim", &.{});
    defer engine.freeValue(trimmed);
    const text = try engine.toString(trimmed);
    defer engine.gpa.free(text);
    const wrapped = try std.fmt.allocPrint(engine.gpa, "\x1b]10;{s}\x07", .{text});
    defer engine.gpa.free(wrapped);
    const reply = @import("../tui/terminal_colors.zig").parseOsc(wrapped);
    const rgb = blk: {
        const color = if (reply) |value| value.rgb else null;
        if (color) |channels| {
            const object = try js.object(engine);
            errdefer engine.freeValue(object);
            try js.define(engine, object, "r", v.numeric(engine, channels.r));
            try js.define(engine, object, "g", v.numeric(engine, channels.g));
            try js.define(engine, object, "b", v.numeric(engine, channels.b));
            break :blk object;
        }
        break :blk c.pi_js_undefined();
    };
    try js.define(engine, result, "rgb", rgb);
    return result;
}
pub fn install(engine: *js.Engine, bindings: c.JSValue) !void {
    try js.define(engine, bindings, "amPattern", try regexp(engine, "[\u{0e33}\u{0eb3}]", ""));
    try js.define(engine, bindings, "amGlobalPattern", try regexp(engine, "[\u{0e33}\u{0eb3}]", "g"));
    try js.define(engine, bindings, "oscColorPattern", try regexp(engine, "^\x1b\\](?:(1[01])|4;(\\d{1,3}));([^\x07\x1b]*)(?:\x07|\x1b\\\\)$", "i"));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        var data = [_]c.JSValue{bindings};
        try js.define(engine, bindings, field.name, try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, 1, field.value, 1, &data)));
    }
}
