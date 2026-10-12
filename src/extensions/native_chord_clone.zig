//! Actual TypeBox SystemClone traversal used by Chord Host admission.
const scoped = @import("native_chord_values.zig");
const Scope = scoped.Scope;
const js = scoped.js;
const c = js.c;
const Engine = js.Engine;

fn instance(s: *Scope, value: c.JSValue, name: [*:0]const u8) !bool {
    const constructor = try s.keep(try js.global(s.engine, name));
    const result = c.JS_IsInstanceOf(s.engine.context, value, constructor);
    if (result < 0) return js.capture(s.engine);
    return result != 0;
}
fn unsafeKey(s: *Scope, key: c.JSValue) !bool {
    return try s.equal(key, "__proto__") or try s.equal(key, "constructor") or try s.equal(key, "prototype");
}
fn size(s: *Scope, value: c.JSValue) !u32 {
    var result: u32 = undefined;
    if (c.JS_ToUint32(s.engine.context, &result, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return result;
}
fn arrayMap(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return clone(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn fromArray(s: *Scope, value: c.JSValue) !c.JSValue {
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, arrayMap, "", 1, 0, 0, null)));
    return js.invoke(s.engine, value, "map", &.{callback});
}
fn fromIterable(s: *Scope, value: c.JSValue, name: [*:0]const u8, method: [*:0]const u8) anyerror!c.JSValue {
    const constructor = try s.keep(try js.global(s.engine, name));
    // Source spread consumes the actual iterator before recursively cloning.
    const iterator = try s.keep(try js.invoke(s.engine, value, method, &.{}));
    const values = try s.keep(try @import("native_iterator_spread.zig").snapshot(s.engine, iterator));
    const copied = try s.keep(try clone(s.engine, values));
    var arguments = [_]c.JSValue{copied};
    return s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, 1, &arguments));
}
fn classInstance(s: *Scope, value: c.JSValue) !bool {
    const proto = try s.builtin("Object", "getPrototypeOf", &.{value});
    if (c.JS_IsNull(proto)) return false;
    // Preserve the three distinct Source constructor reads; a getter can vary.
    if (!c.JS_IsFunction(s.engine.context, try s.get(proto, "constructor"))) return false;
    const constructor = try s.get(proto, "constructor");
    const object = try s.keep(try js.global(s.engine, "Object"));
    if (c.JS_IsStrictEqual(s.engine.context, constructor, object)) return false;
    return !(try s.equal(try s.get(try s.get(proto, "constructor"), "name"), "Object"));
}
fn fromObject(s: *Scope, value: c.JSValue) anyerror!c.JSValue {
    if (try classInstance(s, value)) return s.result(value);
    const schema = try s.has(value, "~kind") or try s.has(value, "~unsafe");
    const result = try s.record();
    const names = try s.builtin("Object", "getOwnPropertyNames", &.{value});
    const count = try size(s, names);
    for (0..count) |index| {
        const key = try s.at(names, index);
        if (try unsafeKey(s, key)) continue;
        if (schema) {
            const descriptor = try s.builtin("Object", "getOwnPropertyDescriptor", &.{ value, key });
            const item = try s.keep(try clone(s.engine, try s.get(descriptor, "value")));
            try js.setKey(s.engine, descriptor, try s.text("value"), item);
            if (c.JS_IsStrictEqual(s.engine.context, try s.get(descriptor, "enumerable"), c.pi_js_bool(s.engine.context, 1))) {
                try js.setKey(s.engine, result, key, item);
            } else {
                _ = try s.builtin("Object", "defineProperty", &.{ result, key, descriptor });
            }
        } else {
            const item = try s.keep(try clone(s.engine, try s.key(value, key)));
            try js.setKey(s.engine, result, key, item);
        }
    }
    if (!schema) {
        const symbols = try s.builtin("Object", "getOwnPropertySymbols", &.{value});
        const symbol_count = try size(s, symbols);
        for (0..symbol_count) |index| {
            const key = try s.at(symbols, index);
            const item = try s.keep(try clone(s.engine, try s.key(value, key)));
            try js.setKey(s.engine, result, key, item);
        }
    }
    return s.result(result);
}
pub fn clone(engine: *Engine, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (c.JS_ToBool(engine.context, try s.builtin("ArrayBuffer", "isView", &.{value})) > 0) return js.invoke(engine, value, "slice", &.{});
    if (try instance(&s, value, "RegExp")) {
        const constructor = try s.keep(try js.global(engine, "RegExp"));
        const source = try s.get(value, "source");
        const flags = try s.get(value, "flags");
        return @import("native_schema_regexp.zig").construct(engine, constructor, source, flags);
    }
    if (try instance(&s, value, "Map")) return fromIterable(&s, value, "Map", "entries");
    if (try instance(&s, value, "Set")) return fromIterable(&s, value, "Set", "values");
    if (c.JS_ToBool(engine.context, try s.builtin("Array", "isArray", &.{value})) > 0) return fromArray(&s, value);
    if (c.JS_IsObject(value) and !c.JS_IsFunction(engine.context, value)) return fromObject(&s, value);
    return s.result(value);
}
fn invoke(engine: *Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return clone(engine, if (args.len > 0) args[0] else c.pi_js_undefined());
}
pub fn function(engine: *Engine) !c.JSValue {
    return @import("native_node_function.zig").create(engine, "Clone", 1, invoke, &.{});
}
