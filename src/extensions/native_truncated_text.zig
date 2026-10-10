//! Source TruncatedText ordinary fields, first-line clipping and fresh render arrays.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const utf16 = @import("native_utf16.zig");
const Method = enum(c_int) { invalidate, render };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native TruncatedText: %s", @as([*:0]const u8, @errorName(err)));
}
fn spaces(engine: *js.Engine, count: c.JSValue) !c.JSValue {
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    return js.invoke(engine, space, "repeat", &.{count});
}
fn pushVerticalPadding(engine: *js.Engine, object: c.JSValue, result: c.JSValue, empty: c.JSValue) !void {
    var index: f64 = 0;
    while (index < try v.numberField(engine, object, "paddingY")) : (index += 1) {
        if (index >= 4096) {
            _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Maximum component frame size exceeded"));
            unreachable;
        }
        try js.push(engine, result, empty);
    }
}
fn render(engine: *js.Engine, object: c.JSValue, width: c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const empty = try spaces(engine, width);
    defer engine.freeValue(empty);
    try pushVerticalPadding(engine, object, result, empty);
    const terminal_width = try v.number(engine, width);
    const available = v.maximum(1, terminal_width - try v.numberField(engine, object, "paddingX") * 2);
    var single_line = try js.get(engine, object, "text");
    defer engine.freeValue(single_line);
    const source = try js.get(engine, object, "text");
    defer engine.freeValue(source);
    const newline = try v.text(engine, "\n");
    defer engine.freeValue(newline);
    const index = try js.invoke(engine, source, "indexOf", &.{newline});
    defer engine.freeValue(index);
    if (!c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) {
        const current = try js.get(engine, object, "text");
        defer engine.freeValue(current);
        const first = try js.invoke(engine, current, "substring", &.{ c.JS_NewInt32(engine.context, 0), index });
        engine.freeValue(single_line);
        single_line = first;
    }
    const units = try utf16.unitsAlloc(engine, single_line);
    defer engine.gpa.free(units);
    const clipped = if (std.math.isNan(available)) blk: {
        if (units.len == 0) break :blk try engine.gpa.dupe(u16, &.{});
        const ascii = for (units) |unit| {
            if (unit < 0x20 or unit > 0x7e) break false;
        } else true;
        break :blk try engine.gpa.dupe(u16, if (ascii) std.unicode.utf8ToUtf16LeStringLiteral("\x1b[0m...\x1b[0m") else units);
    } else if (std.math.isPositiveInf(available)) try engine.gpa.dupe(u16, units) else try @import("../tui/utf16_terminal.zig").truncateOptionsAlloc(engine.gpa, units, available, &.{ '.', '.', '.' }, false);
    defer engine.gpa.free(clipped);
    const display = try utf16.string(engine, clipped);
    defer engine.freeValue(display);
    const left_count = try js.get(engine, object, "paddingX");
    defer engine.freeValue(left_count);
    const left = try spaces(engine, left_count);
    defer engine.freeValue(left);
    const right_count = try js.get(engine, object, "paddingX");
    defer engine.freeValue(right_count);
    const right = try spaces(engine, right_count);
    defer engine.freeValue(right);
    const line = try v.concat(engine, &.{ left, display, right });
    defer engine.freeValue(line);
    const visible = try v.width(engine, line);
    const padding = try spaces(engine, v.numeric(engine, v.maximum(0, try v.number(engine, width) - visible)));
    defer engine.freeValue(padding);
    const final = try v.concat(engine, &.{ line, padding });
    defer engine.freeValue(final);
    try js.push(engine, result, final);
    try pushVerticalPadding(engine, object, result, empty);
    return result;
}
fn methodCall(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    if (@as(Method, @enumFromInt(magic)) == .invalidate) return c.pi_js_undefined();
    return render(engine, object, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| fail(engine, err);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "text", c.JS_DupValue(engine.context, v.arg(args, 0)));
    inline for (.{ .{ "paddingX", 1 }, .{ "paddingY", 2 } }) |field| {
        const value = v.arg(args, field[1]);
        try js.define(engine, object, field[0], if (c.JS_IsUndefined(value)) c.JS_NewInt32(engine.context, 0) else c.JS_DupValue(engine.context, value));
    }
    return object;
}
pub fn install(engine: *js.Engine, exports: c.JSValue) !void {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const function = try engine.checked(c.pi_js_function_magic(engine.context, methodCall, name.ptr, if (field.value == @intFromEnum(Method.render)) 1 else 0, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    try js.define(engine, exports, "TruncatedText", try @import("native_class.zig").constructor(engine, "TruncatedText", 1, prototype, construct, &.{}));
}
