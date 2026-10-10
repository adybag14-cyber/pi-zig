//! Internal native Source wheel-gesture accelerator for alternate-screen input.
//! Ordinary JS state and dynamic Source Math/Number/process lookups are retained.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const v = @import("native_select_list.zig");
const arithmetic = @import("native_tui_value_arithmetic.zig");
const numeric = @import("native_wheel_numeric.zig");
const Method = enum(c_int) { setLines, next, reset };
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native wheel scroll: %s", @as([*:0]const u8, @errorName(err)));
}
fn globalCall(engine: *js.Engine, object_name: [*:0]const u8, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const object = try js.global(engine, object_name);
    defer engine.freeValue(object);
    return js.invoke(engine, object, method, args);
}
fn negativeInfinity(engine: *js.Engine) !c.JSValue {
    const number = try js.global(engine, "Number");
    defer engine.freeValue(number);
    return js.get(engine, number, "NEGATIVE_INFINITY");
}
fn terminalAccelerates(engine: *js.Engine) !bool {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    const environment = try js.get(engine, process, "env");
    defer engine.freeValue(environment);
    const platform = try js.get(engine, process, "platform");
    defer engine.freeValue(platform);
    const darwin = try v.text(engine, "darwin");
    defer engine.freeValue(darwin);
    if (!c.JS_IsStrictEqual(engine.context, platform, darwin)) return false;
    inline for (.{ "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY" }) |name| {
        const value = try js.get(engine, environment, name);
        defer engine.freeValue(value);
        if (!c.JS_IsUndefined(value)) return false;
    }
    return true;
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const object = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(object);
    try js.define(engine, object, "lines", c.pi_js_undefined());
    try js.define(engine, object, "accelerate", c.pi_js_undefined());
    try js.define(engine, object, "lastTime", try negativeInfinity(engine));
    try js.define(engine, object, "lastDirection", c.JS_NewInt32(engine.context, 0));
    try js.define(engine, object, "averageGap", c.pi_js_undefined());
    try js.define(engine, object, "carry", c.JS_NewInt32(engine.context, 0));
    const lines = v.arg(args, 0);
    const accelerate = v.arg(args, 1);
    // Source base-class field initialization precedes default parameter getters;
    // both default arguments are then evaluated before constructor assignments.
    const actual_lines = if (c.JS_IsUndefined(lines)) try v.text(engine, "auto") else c.JS_DupValue(engine.context, lines);
    defer engine.freeValue(actual_lines);
    const actual_accelerate = if (c.JS_IsUndefined(accelerate)) c.pi_js_bool(engine.context, @intFromBool(!try terminalAccelerates(engine))) else c.JS_DupValue(engine.context, accelerate);
    defer engine.freeValue(actual_accelerate);
    try v.set(engine, object, "lines", c.JS_DupValue(engine.context, actual_lines));
    try v.set(engine, object, "accelerate", c.JS_DupValue(engine.context, actual_accelerate));
    return object;
}
fn invoke(engine: *js.Engine, object: c.JSValue, symbol: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .setLines => {
            try v.set(engine, object, "lines", c.JS_DupValue(engine.context, v.arg(args, 0)));
            const reset = try js.invoke(engine, object, "reset", &.{});
            engine.freeValue(reset);
        },
        .reset => {
            try v.set(engine, object, "lastTime", try negativeInfinity(engine));
            try v.set(engine, object, "lastDirection", c.JS_NewInt32(engine.context, 0));
            try v.set(engine, object, "averageGap", c.pi_js_undefined());
            try v.set(engine, object, "carry", c.JS_NewInt32(engine.context, 0));
        },
        .next => return next(engine, object, symbol, args),
    }
    return c.pi_js_undefined();
}
fn next(engine: *js.Engine, object: c.JSValue, symbol: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const auto = try v.text(engine, "auto");
    defer engine.freeValue(auto);
    const lines = try js.get(engine, object, "lines");
    defer engine.freeValue(lines);
    if (!c.JS_IsStrictEqual(engine.context, lines, auto)) {
        const number = try js.global(engine, "Number");
        defer engine.freeValue(number);
        const finite = try js.get(engine, number, "isFinite");
        defer engine.freeValue(finite);
        const field = try js.get(engine, object, "lines");
        defer engine.freeValue(field);
        const checked = try js.call(engine, finite, number, &.{field});
        defer engine.freeValue(checked);
        if (!v.truthy(engine, checked)) return c.JS_NewInt32(engine.context, 1);
        const math = try js.global(engine, "Math");
        defer engine.freeValue(math);
        const maximum = try js.get(engine, math, "max");
        defer engine.freeValue(maximum);
        const floor_math = try js.global(engine, "Math");
        defer engine.freeValue(floor_math);
        const floor = try js.get(engine, floor_math, "floor");
        defer engine.freeValue(floor);
        const current = try js.get(engine, object, "lines");
        defer engine.freeValue(current);
        const whole = try js.call(engine, floor, floor_math, &.{current});
        defer engine.freeValue(whole);
        return js.call(engine, maximum, math, &.{ c.JS_NewInt32(engine.context, 1), whole });
    }
    const accelerate = try js.get(engine, object, "accelerate");
    defer engine.freeValue(accelerate);
    if (!v.truthy(engine, accelerate)) return c.JS_NewInt32(engine.context, 1);
    const direction = v.arg(args, 0);
    const now = v.arg(args, 1);
    const previous_time = try js.get(engine, object, "lastTime");
    defer engine.freeValue(previous_time);
    const gap = try numeric.subtract(engine, now, previous_time, symbol);
    defer engine.freeValue(gap);
    const previous_direction = try js.get(engine, object, "lastDirection");
    defer engine.freeValue(previous_direction);
    const same_gesture = c.JS_IsStrictEqual(engine.context, direction, previous_direction) and try numeric.compareScalar(engine, gap, 200, true);
    try v.set(engine, object, "lastTime", c.JS_DupValue(engine.context, now));
    try v.set(engine, object, "lastDirection", c.JS_DupValue(engine.context, direction));
    if (!same_gesture) {
        try v.set(engine, object, "averageGap", c.pi_js_undefined());
        try v.set(engine, object, "carry", c.JS_NewInt32(engine.context, 0));
        return c.JS_NewInt32(engine.context, 1);
    }
    if (try numeric.compareScalar(engine, gap, 5, false)) return c.JS_NewInt32(engine.context, 1);
    const average = try js.get(engine, object, "averageGap");
    defer engine.freeValue(average);
    const new_average = blk: {
        if (c.JS_IsUndefined(average)) break :blk c.JS_DupValue(engine.context, gap);
        const current = try js.get(engine, object, "averageGap");
        defer engine.freeValue(current);
        const sum = try arithmetic.add(engine, current, gap, symbol);
        defer engine.freeValue(sum);
        break :blk v.numeric(engine, try v.number(engine, sum) / 2);
    };
    try v.set(engine, object, "averageGap", new_average);
    const minimum_math = try js.global(engine, "Math");
    defer engine.freeValue(minimum_math);
    const minimum = try js.get(engine, minimum_math, "min");
    defer engine.freeValue(minimum);
    const maximum_math = try js.global(engine, "Math");
    defer engine.freeValue(maximum_math);
    const maximum = try js.get(engine, maximum_math, "max");
    defer engine.freeValue(maximum);
    const current_average = try js.get(engine, object, "averageGap");
    defer engine.freeValue(current_average);
    const speed = try js.call(engine, maximum, maximum_math, &.{ c.JS_NewInt32(engine.context, 1), v.numeric(engine, 100 / try v.number(engine, current_average)) });
    defer engine.freeValue(speed);
    const clamped = try js.call(engine, minimum, minimum_math, &.{ c.JS_NewInt32(engine.context, 6), speed });
    defer engine.freeValue(clamped);
    const carry = try js.get(engine, object, "carry");
    defer engine.freeValue(carry);
    const count = try arithmetic.add(engine, clamped, carry, symbol);
    defer engine.freeValue(count);
    const whole = try globalCall(engine, "Math", "floor", &.{count});
    errdefer engine.freeValue(whole);
    try v.set(engine, object, "carry", v.numeric(engine, try v.number(engine, count) - try v.number(engine, whole)));
    return whole;
}
fn call(context: ?*c.JSContext, object: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return invoke(engine, object, data[0], @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| fail(engine, err);
}
pub fn create(engine: *js.Engine) !c.JSValue {
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const symbols = try js.global(engine, "Symbol");
    defer engine.freeValue(symbols);
    const symbol = try js.get(engine, symbols, "toPrimitive");
    defer engine.freeValue(symbol);
    inline for (std.meta.fields(Method)) |field| {
        var data = [_]c.JSValue{symbol};
        const length: c_int = if (field.value == @intFromEnum(Method.setLines)) 1 else if (field.value == @intFromEnum(Method.next)) 2 else 0;
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, field.name, length, field.value, 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return @import("native_class.zig").constructor(engine, "WheelScrollAccelerator", 0, prototype, construct, &.{});
}
