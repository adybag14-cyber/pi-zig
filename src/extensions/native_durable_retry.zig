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
    const Scope = @import("native_sdk_prompt_scope.zig").Scope;
    const arithmetic = @import("native_image_arithmetic.zig");
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const base = try scope.get(policy, "baseDelayMs");
    const math_max = try scope.global("Math");
    const max = try scope.get(math_max, "max");
    const position = try scope.own(try arithmetic.binary(engine, .subtract, attempt, c.JS_NewInt32(engine.context, 1)));
    const exponent = try scope.call(max, math_max, &.{ c.JS_NewInt32(engine.context, 0), position });
    const power = try scope.own(try arithmetic.binary(engine, .power, c.JS_NewInt32(engine.context, 2), exponent));
    const raw = try scope.own(try arithmetic.binary(engine, .multiply, base, power));
    const number = try scope.global("Number");
    const safe = try scope.invoke(number, "isSafeInteger", &.{raw});
    const value = if (scope.truthy(safe)) raw else try scope.get(try scope.global("Number"), "MAX_SAFE_INTEGER");
    const math_min = try scope.global("Math");
    const min = try scope.get(math_min, "min");
    const cap = try scope.get(policy, "maxAgentDelayMs");
    return js.call(engine, min, math_min, &.{ value, if (c.JS_IsUndefined(cap) or c.JS_IsNull(cap)) c.JS_NewInt32(engine.context, 60000) else cap });
}
