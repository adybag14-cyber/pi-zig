//! Original cache-warming status and usage formatters, including live methods.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const values = @import("native_cache_warming_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn concatenate(scope: *Scope, lhs: c.JSValue, rhs: c.JSValue) !c.JSValue {
    return scope.concat(lhs, try scope.stringify(rhs));
}
fn dollars(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (try values.compare(scope, .less, value, c.JS_NewInt32(scope.engine.context, 0))) {
        const absolute = try scope.invoke(try scope.global("Math"), "abs", &.{value});
        return concatenate(scope, try scope.text("-$"), try scope.invoke(absolute, "toFixed", &.{c.JS_NewInt32(scope.engine.context, 3)}));
    }
    return concatenate(scope, try scope.text("$"), try scope.invoke(value, "toFixed", &.{c.JS_NewInt32(scope.engine.context, 3)}));
}
fn economics(scope: *Scope, decision: c.JSValue) !c.JSValue {
    if (!scope.truthy(try scope.get(decision, "economicsAvailable"))) return scope.text("cache economics unavailable");
    const math = try scope.global("Math");
    const round = try scope.get(math, "round");
    const probability = try scope.call(round, math, &.{try values.binary(scope, .multiply, try scope.get(decision, "continuationProbability"), c.JS_NewInt32(scope.engine.context, 100))});
    var text = try concatenate(scope, try scope.text(""), probability);
    text = try scope.concat(text, try scope.text(if (try values.is(scope, try scope.get(decision, "phase"), "streaming")) "% continuation probability while agent is running" else "% continuation probability"));
    const comparison = if (try values.is(scope, try scope.get(decision, "action"), "warm")) ">=" else "<";
    text = try scope.concat(text, try scope.text(", expected savings "));
    text = try scope.concat(text, try dollars(scope, try scope.get(decision, "expectedSavings")));
    text = try scope.concat(text, try scope.text(" "));
    text = try scope.concat(text, try scope.text(comparison));
    return scope.concat(text, try scope.text(" $0.050"));
}
fn remainder(scope: *Scope, value: c.JSValue, divisor: f64) !c.JSValue {
    var number: f64 = 0;
    if (c.JS_ToFloat64(scope.engine.context, &number, value) < 0) return js.capture(scope.engine);
    return c.JS_NewFloat64(scope.engine.context, @rem(number, divisor));
}
fn mathRatio(scope: *Scope, method: [*:0]const u8, numerator: c.JSValue, denominator: i32) !c.JSValue {
    const math = try scope.global("Math");
    const function = try scope.get(math, method);
    return scope.call(function, math, &.{try values.binary(scope, .divide, numerator, c.JS_NewInt32(scope.engine.context, denominator))});
}
fn decisionTime(scope: *Scope, next: c.JSValue, now: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(next) or try values.compare(scope, .less_equal, next, now)) return scope.text("Decision now");
    const math = try scope.global("Math");
    const ceil = try scope.get(math, "ceil");
    const difference = try values.binary(scope, .subtract, next, now);
    const remaining = try scope.call(ceil, math, &.{try values.binary(scope, .divide, difference, c.JS_NewInt32(scope.engine.context, 1000))});
    const hours = try mathRatio(scope, "floor", remaining, 3600);
    const remainder_seconds = try remainder(scope, remaining, 3600);
    const minutes = try mathRatio(scope, "floor", remainder_seconds, 60);
    const seconds = try remainder(scope, remainder_seconds, 60);
    const parts = try scope.array();
    if (try values.compare(scope, .greater, hours, c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(parts, "push", &.{try scope.concat(try scope.stringify(hours), try scope.text("h"))});
    if (try values.compare(scope, .greater, minutes, c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(parts, "push", &.{try scope.concat(try scope.stringify(minutes), try scope.text("m"))});
    if (try values.compare(scope, .greater, seconds, c.JS_NewInt32(scope.engine.context, 0)) or scope.equal(try scope.get(parts, "length"), c.JS_NewInt32(scope.engine.context, 0))) _ = try scope.invoke(parts, "push", &.{try scope.concat(try scope.stringify(seconds), try scope.text("s"))});
    return concatenate(scope, try scope.text("Decision in "), try scope.invoke(parts, "join", &.{try scope.text(" ")}));
}
pub fn status(scope: *Scope, value: c.JSValue, now: c.JSValue) !c.JSValue {
    const decision = try scope.get(value, "decision");
    if (!scope.truthy(decision) or (try values.is(scope, try scope.get(value, "state"), "inactive") and !scope.truthy(try scope.get(decision, "economicsAvailable")) and !scope.truthy(try scope.get(value, "extensionOverride")))) {
        const reason = try scope.get(value, "reason");
        return scope.concat(try concatenate(scope, try scope.text("Inactive ("), if (c.JS_IsNull(reason) or c.JS_IsUndefined(reason)) try scope.text("unknown reason") else reason), try scope.text(")"));
    }
    const details = if (scope.truthy(try scope.get(value, "extensionOverride")))
        try scope.concat(try scope.text("extension override, "), try economics(scope, decision))
    else
        try concatenate(scope, try scope.concat(try economics(scope, decision), try scope.text(" -> ")), try scope.get(decision, "action"));
    if (try values.is(scope, try scope.get(value, "state"), "inactive")) return scope.concat(try scope.concat(try scope.text("Stopped ("), details), try scope.text(")"));
    if (try values.is(scope, try scope.get(value, "state"), "refreshing")) return scope.concat(try scope.concat(try scope.text("Warming cache ("), details), try scope.text(")"));
    const time = try decisionTime(scope, try scope.get(value, "nextWarmAt"), now);
    return scope.concat(try scope.concat(try scope.concat(time, try scope.text(" (")), details), try scope.text(")"));
}
pub fn usage(scope: *Scope, entry: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const note = if (scope.truthy(try scope.get(entry, "note")))
        try scope.concat(try concatenate(scope, try scope.text(" ("), try scope.get(entry, "note")), try scope.text(")"))
    else
        try scope.text("");
    const number = try scope.get(try scope.get(try scope.get(entry, "usage"), "cost"), "total");
    const fixed = try scope.invoke(number, "toFixed", &.{c.JS_NewInt32(engine.context, 6)});
    const replace = try scope.get(fixed, "replace");
    var arguments = [_]c.JSValue{ try scope.text("(\\.\\d{3}\\d*?)0+$"), try scope.text("") };
    const pattern = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, arguments.len, &arguments)));
    const cost = try scope.call(replace, fixed, &.{ pattern, try scope.text("$1") });
    return concatenate(scope, try scope.concat(try scope.concat(try scope.text("Cache warmed"), note), try scope.text(": $")), cost);
}
