//! Exact schema Number/BigInt comparisons without narrowing arbitrary integers.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Big = std.math.big.int.Managed;
fn number(engine: *Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return error.JavaScriptException;
    return result;
}
fn integer(engine: *Engine, value: c.JSValue) !Big {
    var result = try Big.init(engine.gpa);
    errdefer result.deinit();
    if (c.JS_IsBigInt(value)) {
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        try result.setString(10, text);
    } else {
        const scalar = try number(engine, value);
        const bits: u64 = @bitCast(scalar);
        const exponent: i32 = @as(i32, @intCast((bits >> 52) & 0x7ff)) - 1023;
        const mantissa = (bits & 0x000fffffffffffff) | (if (exponent == -1023) @as(u64, 0) else @as(u64, 1) << 52);
        if (exponent < 0) try result.set(0) else if (exponent < 52) {
            try result.set(mantissa >> @as(u6, @intCast(52 - exponent)));
        } else {
            try result.set(mantissa);
            try result.shiftLeft(&result, @intCast(exponent - 52));
        }
        result.setSign(scalar >= 0 or scalar == 0);
    }
    return result;
}
pub fn compare(engine: *Engine, left: c.JSValue, right: c.JSValue) !std.math.Order {
    if (!c.JS_IsBigInt(left) and !c.JS_IsBigInt(right)) return std.math.order(try number(engine, left), try number(engine, right));
    var lhs = try integer(engine, left);
    defer lhs.deinit();
    var rhs = try integer(engine, right);
    defer rhs.deinit();
    const order = Big.order(lhs, rhs);
    if (order != .eq) return order;
    if (!c.JS_IsBigInt(left)) {
        const scalar = try number(engine, left);
        if (scalar != @trunc(scalar)) return if (scalar > 0) .gt else .lt;
    }
    if (!c.JS_IsBigInt(right)) {
        const scalar = try number(engine, right);
        if (scalar != @trunc(scalar)) return if (scalar > 0) .lt else .gt;
    }
    return .eq;
}
fn toBigInt(engine: *Engine, constructor: c.JSValue, value: c.JSValue) !c.JSValue {
    if (c.JS_IsStrictEqual(engine.context, constructor, engine.intrinsic_bigint_constructor) and c.JS_IsNumber(value)) {
        const scalar = try number(engine, value);
        if (!std.math.isFinite(scalar) or scalar != @trunc(scalar)) {
            const text = try engine.toString(value);
            defer engine.gpa.free(text);
            const message = try std.fmt.allocPrintSentinel(engine.gpa, "The number {s} cannot be converted to a BigInt because it is not an integer", .{text}, 0);
            defer engine.gpa.free(message);
            return engine.checked(c.JS_ThrowRangeError(engine.context, "%s", message.ptr));
        }
    }
    var args = [_]c.JSValue{value};
    return engine.checked(c.JS_Call(engine.context, constructor, c.pi_js_undefined(), 1, &args));
}
pub fn multiple(engine: *Engine, dividend: c.JSValue, divisor: c.JSValue) !bool {
    if (c.JS_IsBigInt(dividend) or c.JS_IsBigInt(divisor)) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try vm.get(engine, global, "BigInt");
        defer engine.freeValue(constructor);
        const lhs = try toBigInt(engine, constructor, dividend);
        defer engine.freeValue(lhs);
        const rhs = try toBigInt(engine, constructor, divisor);
        defer engine.freeValue(rhs);
        if (c.JS_IsBigInt(lhs) != c.JS_IsBigInt(rhs)) {
            _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Cannot mix BigInt and other types, use explicit conversions"));
            unreachable;
        }
        if (!c.JS_IsBigInt(lhs)) {
            _ = try number(engine, lhs);
            _ = try number(engine, rhs);
            return false;
        }
        var left = try integer(engine, lhs);
        defer left.deinit();
        var right = try integer(engine, rhs);
        defer right.deinit();
        if (right.toConst().eqlZero()) {
            _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Division by zero"));
            unreachable;
        }
        var quotient = try Big.init(engine.gpa);
        defer quotient.deinit();
        var remainder = try Big.init(engine.gpa);
        defer remainder.deinit();
        try Big.divTrunc(&quotient, &remainder, &left, &right);
        return remainder.toConst().eqlZero();
    }
    const value = try number(engine, dividend);
    const limit = try number(engine, divisor);
    if (!std.math.isFinite(value)) return true;
    const reciprocal = 1 / limit;
    if (value == @trunc(value) and std.math.isFinite(reciprocal) and @rem(reciprocal, 1) == 0) return true;
    if (limit == 0) return false;
    const remainder = @rem(value, limit);
    return @min(@abs(remainder), @min(@abs(remainder - limit), @abs(remainder + limit))) < 1e-10;
}
