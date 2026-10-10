//! Internal Source AltScreenFlashContainer. Timers and callbacks remain ordinary
//! VM values; lifecycle ownership is supplied by the genuine native timer host.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const Method = enum(c_int) { flash, dispose, invalidate, render };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native alternate-screen flash: %s", @as([*:0]const u8, @errorName(err)));
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "entries", try js.array(engine));
    try js.define(engine, object, "nextId", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, object, "requestRender", c.pi_js_undefined());
    try v.set(engine, object, "requestRender", c.JS_DupValue(engine.context, v.arg(args, 0)));
    return object;
}
fn findCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return find(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| fail(engine, err);
}
fn find(engine: *js.Engine, entry: c.JSValue, id: c.JSValue) !c.JSValue {
    const current = try js.get(engine, entry, "id");
    defer engine.freeValue(current);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, current, id)));
}
fn expireCall(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return expire(engine, data[0], data[1]) catch |err| fail(engine, err);
}
fn expire(engine: *js.Engine, object: c.JSValue, id: c.JSValue) !c.JSValue {
    const entries = try js.get(engine, object, "entries");
    defer engine.freeValue(entries);
    const function = try js.get(engine, entries, "findIndex");
    defer engine.freeValue(function);
    var data = [_]c.JSValue{id};
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, findCall, "", 1, 0, 1, &data));
    defer engine.freeValue(predicate);
    const index = try js.call(engine, function, entries, &.{predicate});
    defer engine.freeValue(index);
    if (c.JS_IsStrictEqual(engine.context, index, c.JS_NewInt32(engine.context, -1))) return c.pi_js_undefined();
    const current = try js.get(engine, object, "entries");
    defer engine.freeValue(current);
    try v.invokeVoid(engine, current, "splice", &.{ index, c.JS_NewInt32(engine.context, 1) });
    try v.invokeVoid(engine, object, "requestRender", &.{});
    return c.pi_js_undefined();
}
fn flash(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !void {
    const message = v.arg(args, 0);
    const duration = if (c.JS_IsUndefined(v.arg(args, 1))) c.JS_NewInt32(engine.context, 1000) else v.arg(args, 1);
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    const id = try @import("native_wheel_numeric.zig").postIncrement(engine, object, "nextId", symbol);
    defer engine.freeValue(id);
    const schedule = try js.global(engine, "setTimeout");
    defer engine.freeValue(schedule);
    var data = [_]c.JSValue{ object, id };
    const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, expireCall, "", 0, 0, 2, &data));
    defer engine.freeValue(callback);
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const delay = try js.invoke(engine, math, "max", &.{ c.JS_NewInt32(engine.context, 0), duration });
    defer engine.freeValue(delay);
    const timer = try js.call(engine, schedule, c.pi_js_undefined(), &.{ callback, delay });
    defer engine.freeValue(timer);
    try v.invokeVoid(engine, timer, "unref", &.{});
    const entries = try js.get(engine, object, "entries");
    defer engine.freeValue(entries);
    const push = try js.get(engine, entries, "push");
    defer engine.freeValue(push);
    const entry = try js.object(engine);
    defer engine.freeValue(entry);
    try js.define(engine, entry, "id", c.JS_DupValue(engine.context, id));
    try js.define(engine, entry, "message", c.JS_DupValue(engine.context, message));
    try js.define(engine, entry, "timer", c.JS_DupValue(engine.context, timer));
    const pushed = try js.call(engine, push, entries, &.{entry});
    engine.freeValue(pushed);
    try v.invokeVoid(engine, object, "requestRender", &.{});
}
fn dispose(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue) !void {
    const entries = try js.get(engine, object, "entries");
    defer engine.freeValue(entries);
    const symbol = try js.get(engine, bindings, "iteratorSymbol");
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, entries, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const cancel = try js.global(engine, "clearTimeout");
        defer engine.freeValue(cancel);
        const timer = try js.get(engine, entry, "timer");
        defer engine.freeValue(timer);
        const result = try js.call(engine, cancel, c.pi_js_undefined(), &.{timer});
        engine.freeValue(result);
    }
    const current = try js.get(engine, object, "entries");
    defer engine.freeValue(current);
    try v.set(engine, current, "length", c.JS_NewInt32(engine.context, 0));
}
fn renderCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return renderEntry(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0], data[1]) catch |err| fail(engine, err);
}
fn renderEntry(engine: *js.Engine, entry: c.JSValue, width: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const truncate = try js.get(engine, bindings, "truncateToWidth");
    defer engine.freeValue(truncate);
    const space = try v.text(engine, " ");
    defer engine.freeValue(space);
    const message = try js.get(engine, entry, "message");
    defer engine.freeValue(message);
    const padded = try v.concat(engine, &.{ space, message, space });
    defer engine.freeValue(padded);
    const empty = try v.text(engine, "");
    defer engine.freeValue(empty);
    const truncated = try js.call(engine, truncate, c.pi_js_undefined(), &.{ padded, width, empty });
    defer engine.freeValue(truncated);
    const begin = try v.text(engine, "\x1b[7m");
    defer engine.freeValue(begin);
    const end = try v.text(engine, "\x1b[27m");
    defer engine.freeValue(end);
    return v.concat(engine, &.{ begin, truncated, end });
}
fn invoke(engine: *js.Engine, object: c.JSValue, bindings: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .flash => try flash(engine, object, bindings, args),
        .dispose => try dispose(engine, object, bindings),
        .invalidate => {},
        .render => {
            const entries = try js.get(engine, object, "entries");
            defer engine.freeValue(entries);
            const map = try js.get(engine, entries, "map");
            defer engine.freeValue(map);
            var data = [_]c.JSValue{ v.arg(args, 0), bindings };
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, renderCall, "", 1, 0, 2, &data));
            defer engine.freeValue(callback);
            return js.call(engine, map, entries, &.{callback});
        },
    }
    return c.pi_js_undefined();
}
fn call(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, object, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
pub fn create(engine: *js.Engine, exports: c.JSValue) !c.JSValue {
    const bindings = try js.object(engine);
    defer engine.freeValue(bindings);
    try js.define(engine, bindings, "truncateToWidth", try js.get(engine, exports, "truncateToWidth"));
    const symbol = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol);
    inline for (.{ .{ "iteratorSymbol", "iterator" }, .{ "primitiveSymbol", "toPrimitive" } }) |names| try js.define(engine, bindings, names[0], try js.get(engine, symbol, names[1]));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    inline for (std.meta.fields(Method)) |field| {
        var data = [_]c.JSValue{bindings};
        const length: c_int = if (field.value == @intFromEnum(Method.flash) or field.value == @intFromEnum(Method.render)) 1 else 0;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, length, field.value, 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return @import("native_class.zig").constructor(engine, "AltScreenFlashContainer", 1, prototype, construct, &.{});
}
