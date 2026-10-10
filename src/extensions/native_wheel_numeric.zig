//! Numeric subtraction preserves native JavaScript Number/BigInt evaluation.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
fn primitive(engine: *js.Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(value)) return c.JS_DupValue(engine.context, value);
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
fn integer(engine: *js.Engine, value: c.JSValue) !std.math.big.int.Managed {
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    var result = try std.math.big.int.Managed.init(engine.gpa);
    errdefer result.deinit();
    try result.setString(10, text);
    return result;
}
pub fn subtract(engine: *js.Engine, left: c.JSValue, right: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const first = try primitive(engine, left, symbol);
    defer engine.freeValue(first);
    const first_number: f64 = if (c.JS_IsBigInt(first)) 0 else try v.number(engine, first);
    const second = try primitive(engine, right, symbol);
    defer engine.freeValue(second);
    const second_number: f64 = if (c.JS_IsBigInt(second)) 0 else try v.number(engine, second);
    if (!c.JS_IsBigInt(first) and !c.JS_IsBigInt(second)) return v.numeric(engine, first_number - second_number);
    if (!c.JS_IsBigInt(first) or !c.JS_IsBigInt(second)) return js.typeError(engine, "Cannot mix BigInt and other types, use explicit conversions");
    var a = try integer(engine, first);
    defer a.deinit();
    var b = try integer(engine, second);
    defer b.deinit();
    var difference = try std.math.big.int.Managed.init(engine.gpa);
    defer difference.deinit();
    try difference.sub(&a, &b);
    const text = try difference.toString(engine.gpa, 10, .lower);
    defer engine.gpa.free(text);
    const string = try v.text(engine, text);
    defer engine.freeValue(string);
    return js.call(engine, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{string});
}
pub fn compareScalar(engine: *js.Engine, value: c.JSValue, scalar: i32, inclusive: bool) !bool {
    if (!c.JS_IsBigInt(value)) {
        const number = try v.number(engine, value);
        return if (inclusive) number <= @as(f64, @floatFromInt(scalar)) else number < @as(f64, @floatFromInt(scalar));
    }
    var number = try integer(engine, value);
    defer number.deinit();
    const order = number.toConst().orderAgainstScalar(scalar);
    return order == .lt or (inclusive and order == .eq);
}
pub fn postIncrement(engine: *js.Engine, object: c.JSValue, field: [*:0]const u8, symbol: c.JSValue) !c.JSValue {
    const previous = try js.get(engine, object, field);
    defer engine.freeValue(previous);
    const original = try primitive(engine, previous, symbol);
    defer engine.freeValue(original);
    const old_numeric = if (c.JS_IsBigInt(original)) c.JS_DupValue(engine.context, original) else v.numeric(engine, try v.number(engine, original));
    errdefer engine.freeValue(old_numeric);
    const incremented = blk: {
        if (!c.JS_IsBigInt(old_numeric)) break :blk v.numeric(engine, try v.number(engine, old_numeric) + 1);
        var number = try integer(engine, old_numeric);
        defer number.deinit();
        try number.addScalar(&number, 1);
        const text = try number.toString(engine.gpa, 10, .lower);
        defer engine.gpa.free(text);
        const string = try v.text(engine, text);
        defer engine.freeValue(string);
        break :blk try js.call(engine, engine.intrinsic_bigint_constructor, c.pi_js_undefined(), &.{string});
    };
    try v.set(engine, object, field, incremented);
    return old_numeric;
}
