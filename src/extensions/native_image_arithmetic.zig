//! Actual VM arithmetic for image strategies with observable option coercion.
const js = @import("native_js_values.zig");
const c = js.c;
pub const Operation = enum(c_int) { add, subtract, multiply, divide, less, less_equal, greater, greater_equal, remainder };
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
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    const round = try js.get(engine, object, "round");
    defer engine.freeValue(round);
    const product = try binary(engine, .multiply, dimension, limit);
    defer engine.freeValue(product);
    const quotient = try binary(engine, .divide, product, divisor);
    defer engine.freeValue(quotient);
    return js.call(engine, round, object, &.{quotient});
}
fn scaleOption(engine: *js.Engine, dimension: c.JSValue, options: c.JSValue, name: [*:0]const u8, divisor: c.JSValue) !c.JSValue {
    const object = try js.global(engine, "Math");
    defer engine.freeValue(object);
    const round = try js.get(engine, object, "round");
    defer engine.freeValue(round);
    const limit = try js.get(engine, options, name);
    defer engine.freeValue(limit);
    const product = try binary(engine, .multiply, dimension, limit);
    defer engine.freeValue(product);
    const quotient = try binary(engine, .divide, product, divisor);
    defer engine.freeValue(quotient);
    return js.call(engine, round, object, &.{quotient});
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
        const height = try scaleOption(engine, result.height, options, "maxWidth", result.width);
        engine.freeValue(result.height);
        result.height = height;
        const assigned = try js.get(engine, options, "maxWidth");
        engine.freeValue(result.width);
        result.width = assigned;
    }
    const second_limit = try js.get(engine, options, "maxHeight");
    defer engine.freeValue(second_limit);
    if (try compare(engine, .greater, result.height, second_limit)) {
        const width = try scaleOption(engine, result.width, options, "maxHeight", result.height);
        engine.freeValue(result.width);
        result.width = width;
        const assigned = try js.get(engine, options, "maxHeight");
        engine.freeValue(result.height);
        result.height = assigned;
    }
    return result;
}
/// Source evaluates Array.from, Set and the quality getter in that order.
/// Actual guest constructors and methods retain SameValueZero and mutation.
pub fn qualitySteps(engine: *js.Engine, options: c.JSValue) !c.JSValue {
    const array_constructor = try js.global(engine, "Array");
    defer engine.freeValue(array_constructor);
    const from = try js.get(engine, array_constructor, "from");
    defer engine.freeValue(from);
    const set_constructor = try js.global(engine, "Set");
    defer engine.freeValue(set_constructor);
    const input = try js.array(engine);
    defer engine.freeValue(input);
    const quality = try js.get(engine, options, "jpegQuality");
    if (c.JS_SetPropertyUint32(engine.context, input, 0, quality) < 0) return js.capture(engine);
    inline for (.{ 85, 70, 55, 40 }, 1..) |value, index| {
        if (c.JS_SetPropertyUint32(engine.context, input, index, c.JS_NewInt32(engine.context, value)) < 0) return js.capture(engine);
    }
    var arguments = [_]c.JSValue{input};
    const set = try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, 1, &arguments));
    defer engine.freeValue(set);
    return js.call(engine, from, array_constructor, &.{set});
}
pub fn fitsEncodedSize(engine: *js.Engine, encoded_size: usize, options: c.JSValue) !bool {
    const size = c.JS_NewFloat64(engine.context, @floatFromInt(encoded_size));
    defer engine.freeValue(size);
    const limit = try js.get(engine, options, "maxBytes");
    defer engine.freeValue(limit);
    return compare(engine, .less, size, limit);
}
pub fn wasmDimension(engine: *js.Engine, dimension: c.JSValue) !u32 {
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, dimension) < 0) return js.capture(engine);
    return result;
}
pub fn nextDimension(engine: *js.Engine, dimension: c.JSValue) !c.JSValue {
    const one = c.JS_NewInt32(engine.context, 1);
    if (c.JS_IsStrictEqual(engine.context, dimension, one)) return one;
    const max_object = try js.global(engine, "Math");
    defer engine.freeValue(max_object);
    const max = try js.get(engine, max_object, "max");
    defer engine.freeValue(max);
    const floor_object = try js.global(engine, "Math");
    defer engine.freeValue(floor_object);
    const floor = try js.get(engine, floor_object, "floor");
    defer engine.freeValue(floor);
    const ratio = c.JS_NewFloat64(engine.context, 0.75);
    defer engine.freeValue(ratio);
    const product = try binary(engine, .multiply, dimension, ratio);
    defer engine.freeValue(product);
    const rounded = try js.call(engine, floor, floor_object, &.{product});
    defer engine.freeValue(rounded);
    return js.call(engine, max, max_object, &.{ one, rounded });
}
