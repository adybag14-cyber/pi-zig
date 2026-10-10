//! Source provider retry patterns run in the captured C VM RegExp intrinsic.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
fn matches(engine: *Engine, text: c.JSValue, pattern: []const u8) !bool {
    const source = try engine.checked(c.JS_NewStringLen(engine.context, pattern.ptr, pattern.len));
    defer engine.freeValue(source);
    const flags = try engine.checked(c.JS_NewString(engine.context, "i"));
    defer engine.freeValue(flags);
    var args = [_]c.JSValue{ source, flags };
    const regexp = try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, &args));
    defer engine.freeValue(regexp);
    const result = try vm.invoke(engine, regexp, "test", &.{text});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
pub fn retryable(engine: *Engine, message: c.JSValue) !bool {
    const reason = try vm.get(engine, message, "stopReason");
    defer engine.freeValue(reason);
    const error_reason = try engine.checked(c.JS_NewString(engine.context, "error"));
    defer engine.freeValue(error_reason);
    if (!c.JS_IsStrictEqual(engine.context, reason, error_reason)) return false;
    const text = try vm.get(engine, message, "errorMessage");
    defer engine.freeValue(text);
    if (c.JS_ToBool(engine.context, text) == 0) return false;
    if (try matches(engine, text, @embedFile("nonretryable-provider-pattern.txt"))) return false;
    return matches(engine, text, @embedFile("retryable-provider-pattern.txt"));
}
pub fn delay(engine: *Engine, policy: c.JSValue, attempt: c.JSValue) !c.JSValue {
    const math = try js.global(engine, "Math");
    defer engine.freeValue(math);
    const number = try js.global(engine, "Number");
    defer engine.freeValue(number);
    const base = try vm.get(engine, policy, "baseDelayMs");
    defer engine.freeValue(base);
    var base_number: f64 = 0;
    var attempt_number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &base_number, base) < 0 or c.JS_ToFloat64(engine.context, &attempt_number, attempt) < 0) return js.capture(engine);
    const exponent = try vm.invoke(engine, math, "max", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, attempt_number - 1) });
    defer engine.freeValue(exponent);
    const power = try vm.invoke(engine, math, "pow", &.{ c.JS_NewInt32(engine.context, 2), exponent });
    defer engine.freeValue(power);
    var power_number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &power_number, power) < 0) return js.capture(engine);
    const raw = c.JS_NewFloat64(engine.context, base_number * power_number);
    const safe = try vm.invoke(engine, number, "isSafeInteger", &.{raw});
    defer engine.freeValue(safe);
    const value = if (c.JS_ToBool(engine.context, safe) != 0) raw else c.JS_NewFloat64(engine.context, 9007199254740991);
    const cap = try vm.get(engine, policy, "maxAgentDelayMs");
    defer engine.freeValue(cap);
    return vm.invoke(engine, math, "min", &.{ value, if (c.JS_IsUndefined(cap) or c.JS_IsNull(cap)) c.JS_NewInt32(engine.context, 60000) else cap });
}
