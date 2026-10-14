//! Source provider retry patterns run in the captured C VM RegExp intrinsic.
const engine_mod = @import("engine.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub fn retryable(engine: *Engine, message: c.JSValue) !bool {
    return @import("native_ai_error_classification.zig").retryable(engine, message);
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
