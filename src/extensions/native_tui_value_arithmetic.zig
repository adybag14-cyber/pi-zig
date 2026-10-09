//! Ordinary JavaScript addition for the public layout algorithms' mutable fields.
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
pub fn primitive(engine: *js.Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const exotic = try js.getKey(engine, value, symbol);
    defer engine.freeValue(exotic);
    if (!c.JS_IsNull(exotic) and !c.JS_IsUndefined(exotic)) {
        const hint = try v.text(engine, "default");
        defer engine.freeValue(hint);
        const result = try js.call(engine, exotic, value, &.{hint});
        if (!c.JS_IsObject(result)) return result;
        engine.freeValue(result);
        return js.typeError(engine, "Cannot convert object to primitive value");
    }
    inline for (.{ "valueOf", "toString" }) |name| {
        const function = try js.get(engine, value, name);
        defer engine.freeValue(function);
        if (c.JS_IsFunction(engine.context, function)) {
            const result = try js.call(engine, function, value, &.{});
            if (!c.JS_IsObject(result)) return result;
            engine.freeValue(result);
        }
    }
    return js.typeError(engine, "Cannot convert object to primitive value");
}
pub fn add(engine: *js.Engine, left: c.JSValue, right: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const a = try primitive(engine, left, symbol);
    defer engine.freeValue(a);
    const b = try primitive(engine, right, symbol);
    defer engine.freeValue(b);
    if (c.JS_IsString(a) or c.JS_IsString(b)) return v.concat(engine, &.{ a, b });
    return v.numeric(engine, try v.number(engine, a) + try v.number(engine, b));
}
