//! Schema-default elision for actual Chord record addresses.
const scoped = @import("native_chord_values.zig");
const Scope = scoped.Scope;
const js = scoped.js;
const c = js.c;
const Engine = js.Engine;
const schema = @import("native_chord_fits.zig");
const canonical = @import("native_chord_canonical.zig");
fn arrayMap(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, tuple: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return arrayItem(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), tuple != 0, data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn arrayItem(engine: *Engine, value: c.JSValue, index: c.JSValue, tuple: bool, items: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const item_schema = try schema.asSchema(&s, if (tuple) try s.key(items, index) else items);
    return stripDefaults(engine, item_schema, value);
}
pub fn stripDefaults(engine: *Engine, input: c.JSValue, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const is_array = try s.builtin("Array", "isArray", &.{value});
    if (c.JS_ToBool(engine.context, is_array) > 0) {
        const items = try s.get(input, "items");
        const tuple = c.JS_ToBool(engine.context, try s.builtin("Array", "isArray", &.{items})) > 0;
        var captures = [_]c.JSValue{items};
        const transform = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, arrayMap, "", if (tuple) 2 else 1, @intFromBool(tuple), 1, &captures)));
        return js.invoke(engine, value, "map", &.{transform});
    }
    if (c.JS_IsNull(value) or !c.JS_IsObject(value) or c.JS_IsFunction(engine.context, value)) return c.JS_DupValue(engine.context, value);
    const properties = try schema.asSchema(&s, try s.get(input, "properties"));
    const result = try s.record();
    const entries = try s.entries(value);
    const size = try s.get(entries, "length");
    var count: u32 = undefined;
    if (c.JS_ToUint32(engine.context, &count, size) < 0) return js.capture(engine);
    for (0..count) |index| {
        const entry = try s.at(entries, index);
        const key = try s.at(entry, 0);
        const item = try s.at(entry, 1);
        const property = try schema.asSchema(&s, try s.key(properties, key));
        if (try s.has(property, "default") and try canonical.deepEqual(engine, try s.get(property, "default"), item)) continue;
        const stripped = try s.keep(try stripDefaults(engine, property, item));
        // Source assigns to an ordinary result object; do not replace this with
        // a descriptor write that changes __proto__ assignment semantics.
        try js.setKey(engine, result, key, stripped);
    }
    return s.result(result);
}
pub fn canonicalIdentity(engine: *Engine, input: c.JSValue, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const root = try schema.asSchema(&s, input);
    const stripped = try s.keep(try stripDefaults(engine, root, value));
    return canonical.canonicalJson(engine, stripped);
}
