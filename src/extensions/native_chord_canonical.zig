//! Actual Chord canonical JSON and UTF-16 two-lane FNV contract fingerprints.
const std = @import("std");
const js = @import("native_js_values.zig");
const strings = @import("native_utf16.zig");
const c = js.c;
const Engine = js.Engine;
fn builtin(engine: *Engine, owner: [*:0]const u8, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, owner);
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, args);
}
fn text(engine: *Engine, value: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_NewString(engine.context, value));
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return map(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), mode, data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn map(engine: *Engine, key: c.JSValue, mode: c_int, object: c.JSValue) anyerror!c.JSValue {
    if (mode == 0) return canonicalJson(engine, key);
    if (mode == 1) {
        const value = try js.getKey(engine, object, key);
        defer engine.freeValue(value);
        return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(value)));
    }
    const encoded_key = try builtin(engine, "JSON", "stringify", &.{key});
    defer engine.freeValue(encoded_key);
    const value = try js.getKey(engine, object, key);
    defer engine.freeValue(value);
    const encoded_value = try canonicalJson(engine, value);
    defer engine.freeValue(encoded_value);
    const colon = try text(engine, ":");
    defer engine.freeValue(colon);
    return strings.concat(engine, &.{ encoded_key, colon, encoded_value });
}
fn mapper(engine: *Engine, mode: c_int, object: c.JSValue) !c.JSValue {
    var data = [_]c.JSValue{object};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 1, mode, 1, &data));
}
pub fn canonicalJson(engine: *Engine, value: c.JSValue) anyerror!c.JSValue {
    if (c.JS_IsNull(value) or !c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) {
        const encoded = try builtin(engine, "JSON", "stringify", &.{value});
        if (!c.JS_IsUndefined(encoded)) return encoded;
        return text(engine, "null");
    }
    const array = try builtin(engine, "Array", "isArray", &.{value});
    defer engine.freeValue(array);
    const is_array = c.JS_ToBool(engine.context, array) > 0;
    const items = if (is_array) c.JS_DupValue(engine.context, value) else blk: {
        const keys = try builtin(engine, "Object", "keys", &.{value});
        defer engine.freeValue(keys);
        const filter = try mapper(engine, 1, value);
        defer engine.freeValue(filter);
        const filtered = try js.invoke(engine, keys, "filter", &.{filter});
        defer engine.freeValue(filtered);
        break :blk try js.invoke(engine, filtered, "sort", &.{});
    };
    defer engine.freeValue(items);
    const transform = try mapper(engine, if (is_array) 0 else 2, value);
    defer engine.freeValue(transform);
    const mapped = try js.invoke(engine, items, "map", &.{transform});
    defer engine.freeValue(mapped);
    const comma = try text(engine, ",");
    defer engine.freeValue(comma);
    const joined = try js.invoke(engine, mapped, "join", &.{comma});
    defer engine.freeValue(joined);
    const before = try text(engine, if (is_array) "[" else "{");
    defer engine.freeValue(before);
    const after = try text(engine, if (is_array) "]" else "}");
    defer engine.freeValue(after);
    return strings.concat(engine, &.{ before, joined, after });
}
pub fn hash64(engine: *Engine, input: c.JSValue) !c.JSValue {
    const units = try strings.unitsAlloc(engine, input);
    defer engine.gpa.free(units);
    var first: u32 = 0x811c9dc5;
    var second: u32 = 0x01000193 ^ 0x5bd1e995;
    for (units) |unit| {
        first = (first ^ @as(u32, unit)) *% 0x01000193;
        second = (second ^ @as(u32, unit)) *% 0x5bd1e995 ^ (second >> 13);
    }
    const encoded = try std.fmt.allocPrint(engine.gpa, "{x:0>8}{x:0>8}", .{ first, second });
    defer engine.gpa.free(encoded);
    return engine.checked(c.JS_NewStringLen(engine.context, encoded.ptr, encoded.len));
}
pub fn deepEqual(engine: *Engine, first: c.JSValue, second: c.JSValue) !bool {
    if (c.JS_IsStrictEqual(engine.context, first, second)) return true;
    const a = try canonicalJson(engine, first);
    defer engine.freeValue(a);
    const b = try canonicalJson(engine, second);
    defer engine.freeValue(b);
    return c.JS_IsStrictEqual(engine.context, a, b);
}
