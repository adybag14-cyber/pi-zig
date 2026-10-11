//! Source API pending flag values commit into the actual loader runtime Map.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
pub fn runtime(engine: *em.Engine, token: c.JSValue) !c.JSValue {
    const scope = try sdk.get(engine, token, "_sdkResourceOwner");
    defer engine.freeValue(scope);
    return sdk.get(engine, scope, "_extensionRuntime");
}
pub fn get(engine: *em.Engine, token: c.JSValue, name: c.JSValue) !c.JSValue {
    const pending = try sdk.get(engine, token, "_sdkPendingFlagValues");
    defer engine.freeValue(pending);
    const present = try js.invoke(engine, pending, "has", &.{name});
    defer engine.freeValue(present);
    if (c.JS_ToBool(engine.context, present) == 1) return js.invoke(engine, pending, "get", &.{name});
    const current = try runtime(engine, token);
    defer engine.freeValue(current);
    const values = try sdk.get(engine, current, "flagValues");
    defer engine.freeValue(values);
    return js.invoke(engine, values, "get", &.{name});
}
fn typeName(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    return sdk.text(engine, if (c.JS_IsUndefined(value)) "undefined" else if (c.JS_IsBool(value)) "boolean" else if (c.JS_IsNumber(value)) "number" else if (c.JS_IsBigInt(value)) "bigint" else if (c.JS_IsString(value)) "string" else if (c.JS_IsSymbol(value)) "symbol" else if (c.JS_IsFunction(engine.context, value)) "function" else "object");
}
pub fn register(engine: *em.Engine, token: c.JSValue, row: c.JSValue, name: c.JSValue, options: c.JSValue, loading: bool) !c.JSValue {
    const first = try sdk.get(engine, options, "default");
    defer engine.freeValue(first);
    if (!c.JS_IsUndefined(first)) {
        const second = try sdk.get(engine, options, "default");
        defer engine.freeValue(second);
        const actual = try typeName(engine, second);
        defer engine.freeValue(actual);
        const expected = try sdk.get(engine, options, "type");
        defer engine.freeValue(expected);
        if (!c.JS_IsStrictEqual(engine.context, actual, expected)) {
            const prefix = try sdk.text(engine, "Invalid default for flag \"");
            defer engine.freeValue(prefix);
            const name_text = try engine.checked(c.JS_ToString(engine.context, name));
            defer engine.freeValue(name_text);
            const between = try sdk.text(engine, "\": expected ");
            defer engine.freeValue(between);
            const type_value = try sdk.get(engine, options, "type");
            defer engine.freeValue(type_value);
            const type_text = try engine.checked(c.JS_ToString(engine.context, type_value));
            defer engine.freeValue(type_text);
            const got = try sdk.text(engine, ", got ");
            defer engine.freeValue(got);
            const current = try sdk.get(engine, options, "default");
            defer engine.freeValue(current);
            const current_type = try typeName(engine, current);
            defer engine.freeValue(current_type);
            const message = try @import("native_select_list.zig").concat(engine, &.{ prefix, name_text, between, type_text, got, current_type });
            defer engine.freeValue(message);
            return engine.checked(c.JS_Throw(engine.context, try js.builtin(engine, "Error", &.{message})));
        }
    }
    const flags = try sdk.get(engine, row, "flags");
    defer engine.freeValue(flags);
    const setter = try sdk.get(engine, flags, "set");
    defer engine.freeValue(setter);
    const definition = try sdk.object(engine);
    defer engine.freeValue(definition);
    try sdk.put(engine, definition, "name", c.JS_DupValue(engine.context, name));
    try sdk.put(engine, definition, "extensionPath", try sdk.get(engine, row, "path"));
    try js.spreadInto(engine, definition, options);
    const stored = try js.call(engine, setter, flags, &.{ name, definition });
    engine.freeValue(stored);
    const default_value = try sdk.get(engine, options, "default");
    defer engine.freeValue(default_value);
    if (!c.JS_IsUndefined(default_value)) {
        const current = try runtime(engine, token);
        defer engine.freeValue(current);
        const values = try sdk.get(engine, current, "flagValues");
        defer engine.freeValue(values);
        const has = try js.invoke(engine, values, "has", &.{name});
        defer engine.freeValue(has);
        if (c.JS_ToBool(engine.context, has) != 1) {
            const target = if (loading) try sdk.get(engine, token, "_sdkPendingFlagValues") else c.JS_DupValue(engine.context, values);
            defer engine.freeValue(target);
            if (loading) {
                const pending_has = try js.invoke(engine, target, "has", &.{name});
                defer engine.freeValue(pending_has);
                if (c.JS_ToBool(engine.context, pending_has) == 1) return c.pi_js_undefined();
            }
            const set = try sdk.get(engine, target, "set");
            defer engine.freeValue(set);
            const value = try sdk.get(engine, options, "default");
            defer engine.freeValue(value);
            const changed = try js.call(engine, set, target, &.{ name, value });
            engine.freeValue(changed);
        }
    }
    return c.pi_js_undefined();
}
pub fn commit(engine: *em.Engine, token: c.JSValue) !void {
    const pending = try sdk.get(engine, token, "_sdkPendingFlagValues");
    defer engine.freeValue(pending);
    const current = try runtime(engine, token);
    defer engine.freeValue(current);
    const values = try sdk.get(engine, current, "flagValues");
    defer engine.freeValue(values);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    var iterator = try js.Iterator.init(engine, pending, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer engine.freeValue(pair[0]);
        defer engine.freeValue(pair[1]);
        const ignored = try js.invoke(engine, values, "set", &pair);
        engine.freeValue(ignored);
    }
    const cleared = try js.invoke(engine, pending, "clear", &.{});
    engine.freeValue(cleared);
}
