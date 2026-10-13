//! Original cache-warming lifetimes and economics over live guest values.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
pub const Scope = temp.Scope;
pub const c = em.c;
const arithmetic = @import("native_image_arithmetic.zig");
pub fn binary(scope: *Scope, op: arithmetic.Operation, lhs: c.JSValue, rhs: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, op, lhs, rhs));
}
pub fn compare(scope: *Scope, op: arithmetic.Operation, lhs: c.JSValue, rhs: c.JSValue) !bool {
    return arithmetic.compare(scope.engine, op, lhs, rhs);
}
pub fn is(scope: *Scope, value: c.JSValue, expected: []const u8) !bool {
    return scope.equal(value, try scope.text(expected));
}
pub fn now(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Date"), "now", &.{});
}
pub fn delay(scope: *Scope, lifetime: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (try compare(scope, .less_equal, lifetime, c.JS_NewInt32(engine.context, 10000))) return c.pi_js_undefined();
    // Preserve callee resolution before argument coercion, including mutable Math.
    const max_math = try scope.global("Math");
    const max = try scope.get(max_math, "max");
    const floor_math = try scope.global("Math");
    const floor = try scope.get(floor_math, "floor");
    const min_math = try scope.global("Math");
    const min = try scope.get(min_math, "min");
    const margin = try binary(scope, .multiply, lifetime, c.JS_NewFloat64(engine.context, 0.9));
    const minimum = try scope.call(min, min_math, &.{ margin, try binary(scope, .subtract, lifetime, c.JS_NewInt32(engine.context, 10000)) });
    return scope.call(max, max_math, &.{ c.JS_NewInt32(engine.context, 1), try scope.call(floor, floor_math, &.{minimum}) });
}
pub fn ttl(scope: *Scope, model: c.JSValue, options: c.JSValue, env_lookup: c.JSValue) !c.JSValue {
    var retention = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "cacheRetention");
    if (temp.nullish(retention)) {
        const env = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "env");
        const value = try scope.call(env_lookup, c.pi_js_undefined(), &.{ try scope.text("PI_CACHE_RETENTION"), env });
        retention = try scope.text(if (try is(scope, value, "long")) "long" else "short");
    }
    if (try is(scope, retention, "none")) return c.pi_js_undefined();
    const cache = try scope.get(model, "promptCache");
    const seconds = if (temp.nullish(cache)) c.pi_js_undefined() else try scope.own(try js.getKey(scope.engine, cache, retention));
    return if (c.JS_IsUndefined(seconds)) c.pi_js_undefined() else binary(scope, .multiply, seconds, c.JS_NewInt32(scope.engine.context, 1000));
}
pub fn replayable(scope: *Scope, model: c.JSValue, options: c.JSValue) !bool {
    const reasoning = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "reasoning");
    if (!scope.truthy(reasoning) or !try is(scope, try scope.get(model, "api"), "anthropic-messages")) return true;
    const compat = try scope.get(model, "compat");
    const adaptive = if (temp.nullish(compat)) c.pi_js_undefined() else try scope.get(compat, "forceAdaptiveThinking");
    return scope.equal(adaptive, c.pi_js_bool(scope.engine.context, 1));
}
fn promptTokens(scope: *Scope, entries: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var index = try binary(scope, .subtract, try scope.get(entries, "length"), c.JS_NewInt32(engine.context, 1));
    while (try compare(scope, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) : (index = try binary(scope, .subtract, index, c.JS_NewInt32(engine.context, 1))) {
        const entry = try scope.own(try js.getKey(engine, entries, index));
        if (try is(scope, try scope.get(entry, "type"), "message") and try is(scope, try scope.get(try scope.get(entry, "message"), "role"), "assistant")) {
            const usage = try scope.get(try scope.get(entry, "message"), "usage");
            return binary(scope, .add, try binary(scope, .add, try scope.get(usage, "input"), try scope.get(usage, "cacheRead")), try scope.get(usage, "cacheWrite"));
        }
    }
    return c.JS_NewInt32(engine.context, 0);
}
fn price(scope: *Scope, model: c.JSValue, field: [:0]const u8, tokens: c.JSValue, output: bool) !c.JSValue {
    const usage = try scope.own(try @import("native_sdk.zig").jsonObject(scope.engine, "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}}"));
    try scope.set(usage, field, tokens);
    if (output) try scope.set(usage, "output", c.JS_NewInt32(scope.engine.context, 1));
    return scope.get(try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, model, usage)), "total");
}
pub fn evaluate(scope: *Scope, receiver: c.JSValue, run: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const model = try scope.get(run, "model");
    const tokens = try promptTokens(scope, try scope.invoke(try scope.get(receiver, "sessionManager"), "getBranch", &.{}));
    const hit = try price(scope, model, "cacheRead", tokens, false);
    const write_cost = try scope.get(try scope.get(model, "cost"), "cacheWrite");
    const miss = try price(scope, model, if (try compare(scope, .greater, write_cost, c.JS_NewInt32(engine.context, 0))) "cacheWrite" else "input", tokens, false);
    const warm = try price(scope, model, "cacheRead", tokens, true);
    const math = try scope.global("Math");
    const max = try scope.get(math, "max");
    const extra = try scope.call(max, math, &.{ c.JS_NewInt32(engine.context, 0), try binary(scope, .subtract, miss, hit) });
    const probability = c.JS_NewFloat64(engine.context, if (try is(scope, try scope.get(run, "phase"), "idle")) 0.15 else 1);
    const available = try compare(scope, .greater, tokens, c.JS_NewInt32(engine.context, 0)) and
        (try compare(scope, .greater, hit, c.JS_NewInt32(engine.context, 0)) or try compare(scope, .greater, miss, c.JS_NewInt32(engine.context, 0)));
    const savings = try binary(scope, .subtract, try binary(scope, .multiply, probability, extra), warm);
    const result = try scope.object();
    try scope.put(result, "phase", try scope.get(run, "phase"));
    try scope.put(result, "warmCost", warm);
    try scope.put(result, "missCost", extra);
    try scope.put(result, "continuationProbability", probability);
    try scope.put(result, "expectedSavings", savings);
    try scope.put(result, "economicsAvailable", c.pi_js_bool(engine.context, @intFromBool(available)));
    try scope.put(result, "action", try scope.text(if (try compare(scope, .greater_equal, savings, c.JS_NewFloat64(engine.context, 0.05))) "warm" else "stop"));
    return result;
}
