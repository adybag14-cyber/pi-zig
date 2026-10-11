//! Actual VM arithmetic for image strategies with observable option coercion.
const js = @import("native_js_values.zig");
const c = js.c;
pub const Operation = enum(c_int) { add, subtract, multiply, divide, less, less_equal, greater, greater_equal };
pub fn binary(engine: *js.Engine, operation: Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiBinaryOperator(engine.context, @intFromEnum(operation), left, right));
}
pub fn compare(engine: *js.Engine, operation: Operation, left: c.JSValue, right: c.JSValue) !bool {
    const value = try binary(engine, operation, left, right);
    defer engine.freeValue(value);
    const result = c.JS_ToBool(engine.context, value);
    if (result < 0) return js.capture(engine);
    return result != 0;
}
pub fn math(engine: *js.Engine, name: [*:0]const u8, input: c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    return js.invoke(engine, object, name, &.{input});
}
/// Preserve Source left-to-right multiplication/division and mutable Math.round.
pub fn scaleDimension(engine: *js.Engine, dimension: c.JSValue, limit: c.JSValue, divisor: c.JSValue) !c.JSValue {
    const product = try binary(engine, .multiply, dimension, limit);
    defer engine.freeValue(product);
    const quotient = try binary(engine, .divide, product, divisor);
    defer engine.freeValue(quotient);
    return math(engine, "round", quotient);
}
