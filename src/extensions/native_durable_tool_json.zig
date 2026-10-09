//! Structural argument comparison for replay and nested-call identity.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn equal(engine: *Engine, left: c.JSValue, right: c.JSValue) !bool {
    if (c.JS_IsStrictEqual(engine.context, left, right)) return true;
    if (!c.JS_IsObject(left) or !c.JS_IsObject(right) or c.JS_IsFunction(engine.context, left) or c.JS_IsFunction(engine.context, right)) return false;
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const left_array = try vm.invoke(engine, array, "isArray", &.{left});
    defer engine.freeValue(left_array);
    const lhs_is_array = c.JS_ToBool(engine.context, left_array) != 0;
    const right_array = if (lhs_is_array) c.pi_js_bool(engine.context, 0) else try vm.invoke(engine, array, "isArray", &.{right});
    defer engine.freeValue(right_array);
    if (lhs_is_array or c.JS_ToBool(engine.context, right_array) != 0) {
        const checked_left = try vm.invoke(engine, array, "isArray", &.{left});
        defer engine.freeValue(checked_left);
        if (c.JS_ToBool(engine.context, checked_left) == 0) return false;
        const checked_right = try vm.invoke(engine, array, "isArray", &.{right});
        defer engine.freeValue(checked_right);
        if (c.JS_ToBool(engine.context, checked_right) == 0) return false;
        const left_length = try vm.get(engine, left, "length");
        defer engine.freeValue(left_length);
        const right_length = try vm.get(engine, right, "length");
        defer engine.freeValue(right_length);
        if (!c.JS_IsStrictEqual(engine.context, left_length, right_length)) return false;
        var captures = [_]c.JSValue{right};
        const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, arrayItem, "", 2, 0, captures.len, &captures));
        defer engine.freeValue(predicate);
        const matched = try vm.invoke(engine, left, "every", &.{predicate});
        defer engine.freeValue(matched);
        return c.JS_ToBool(engine.context, matched) != 0;
    }
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const keys = try vm.invoke(engine, object, "keys", &.{left});
    defer engine.freeValue(keys);
    const key_count = try vm.get(engine, keys, "length");
    defer engine.freeValue(key_count);
    const other_keys = try vm.invoke(engine, object, "keys", &.{right});
    defer engine.freeValue(other_keys);
    const other_count = try vm.get(engine, other_keys, "length");
    defer engine.freeValue(other_count);
    if (!c.JS_IsStrictEqual(engine.context, key_count, other_count)) return false;
    var captures = [_]c.JSValue{ left, right };
    const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, objectItem, "", 1, 0, captures.len, &captures));
    defer engine.freeValue(predicate);
    const matched = try vm.invoke(engine, keys, "every", &.{predicate});
    defer engine.freeValue(matched);
    return c.JS_ToBool(engine.context, matched) != 0;
}
fn arrayItem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const value = if (argc > 0) argv[0] else c.pi_js_undefined();
    const index = if (argc > 1) argv[1] else c.pi_js_undefined();
    const other = js.getKey(engine, data[0], index) catch |err| return @import("native_durable.zig").reject(engine, err);
    defer engine.freeValue(other);
    const result = equal(engine, value, other) catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(result));
}
fn objectItem(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return objectEqual(engine, data[0], data[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn objectEqual(engine: *Engine, left: c.JSValue, right: c.JSValue, key: c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Object");
    defer engine.freeValue(object);
    const own = try vm.invoke(engine, object, "hasOwn", &.{ right, key });
    defer engine.freeValue(own);
    if (c.JS_ToBool(engine.context, own) == 0) return c.pi_js_bool(engine.context, 0);
    const a = try js.getKey(engine, left, key);
    defer engine.freeValue(a);
    const b = try js.getKey(engine, right, key);
    defer engine.freeValue(b);
    return c.pi_js_bool(engine.context, @intFromBool(try equal(engine, a, b)));
}
