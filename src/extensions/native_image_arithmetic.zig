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
pub const Dimensions = struct {
    width: c.JSValue,
    height: c.JSValue,
    pub fn deinit(self: *Dimensions, engine: *js.Engine) void {
        engine.freeValue(self.width);
        engine.freeValue(self.height);
    }
};
/// Source keeps the option value itself after each limiting assignment. Do not
/// convert it to a float before subsequent comparison or WASM argument coercion.
pub fn initialDimensions(engine: *js.Engine, original_width: c.JSValue, original_height: c.JSValue, options: c.JSValue) !Dimensions {
    var result: Dimensions = .{ .width = c.JS_DupValue(engine.context, original_width), .height = c.JS_DupValue(engine.context, original_height) };
    errdefer result.deinit(engine);
    const first_limit = try js.get(engine, options, "maxWidth");
    defer engine.freeValue(first_limit);
    if (try compare(engine, .greater, result.width, first_limit)) {
        const used_limit = try js.get(engine, options, "maxWidth");
        defer engine.freeValue(used_limit);
        const height = try scaleDimension(engine, result.height, used_limit, result.width);
        engine.freeValue(result.height);
        result.height = height;
        const assigned = try js.get(engine, options, "maxWidth");
        engine.freeValue(result.width);
        result.width = assigned;
    }
    const second_limit = try js.get(engine, options, "maxHeight");
    defer engine.freeValue(second_limit);
    if (try compare(engine, .greater, result.height, second_limit)) {
        const used_limit = try js.get(engine, options, "maxHeight");
        defer engine.freeValue(used_limit);
        const width = try scaleDimension(engine, result.width, used_limit, result.height);
        engine.freeValue(result.width);
        result.width = width;
        const assigned = try js.get(engine, options, "maxHeight");
        engine.freeValue(result.height);
        result.height = assigned;
    }
    return result;
}
