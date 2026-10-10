//! JavaScript prefix increment for the screen's public mutable focus counter.
//! Uses Number hint and arbitrary precision BigInt, without guest global calls.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn primitive(engine: *js.Engine, value: c.JSValue, bindings: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
    const symbol = try js.get(engine, bindings, "primitiveSymbol");
    defer engine.freeValue(symbol);
    const exotic = try js.getKey(engine, value, symbol);
    defer engine.freeValue(exotic);
    if (!c.JS_IsNull(exotic) and !c.JS_IsUndefined(exotic)) {
        const hint = try v.text(engine, "number");
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
pub fn increment(engine: *js.Engine, screen: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const previous = try js.get(engine, screen, "focusOrderCounter");
    defer engine.freeValue(previous);
    const numeric = try primitive(engine, previous, bindings);
    defer engine.freeValue(numeric);
    const next = blk: {
        if (!c.JS_IsBigInt(numeric)) break :blk v.numeric(engine, try v.number(engine, numeric) + 1);
        const text = try engine.toString(numeric);
        defer engine.gpa.free(text);
        var integer = try std.math.big.int.Managed.init(engine.gpa);
        defer integer.deinit();
        try integer.setString(10, text);
        try integer.addScalar(&integer, 1);
        const incremented = try integer.toString(engine.gpa, 10, .lower);
        defer engine.gpa.free(incremented);
        const string = try v.text(engine, incremented);
        defer engine.freeValue(string);
        break :blk try js.call(engine, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{string});
    };
    errdefer engine.freeValue(next);
    try v.set(engine, screen, "focusOrderCounter", c.JS_DupValue(engine.context, next));
    return next;
}
