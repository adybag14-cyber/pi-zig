//! Actual classifier shared value checks, usage and one-shot result shapes.
const v = @import("native_ai_provider_values.zig");
pub const Scope = v.Scope;
pub const c = v.c;
pub fn generation(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "allocationGeneration", try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, scope.engine.native_allocation_generation))));
}
pub fn ownedAllocation(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !bool {
    const tag = c.pi_js_native_allocation_error_generation(reason);
    if (tag == 0) return false;
    var initial: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &initial, try scope.get(owner, "allocationGeneration")) < 0) return v.js.capture(scope.engine);
    const distance = tag -% initial;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% initial;
}
pub fn record(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try v.array(scope, value);
}
pub fn required(scope: *Scope, label: c.JSValue, value: c.JSValue, field: c.JSValue) !c.JSValue {
    if (!c.JS_IsNumber(value) or !scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value}))) return v.errorText(scope, try scope.concat(try scope.concat(try scope.stringify(label), try scope.text(" returned an invalid ")), try scope.stringify(field)));
    return value;
}
pub fn define(scope: *Scope, object: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const atom = c.JS_ValueToAtom(scope.engine.context, key);
    if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DefinePropertyValue(scope.engine.context, object, atom, c.JS_DupValue(scope.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
}
pub fn binary(scope: *Scope, operation: @import("native_image_arithmetic.zig").Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, operation, left, right));
}
fn tokenCount(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (c.JS_IsNumber(value) and scope.truthy(try scope.invoke(try scope.global("Number"), "isFinite", &.{value})) and try @import("native_image_arithmetic.zig").compare(scope.engine, .greater, value, c.JS_NewInt32(scope.engine.context, 0))) value else c.JS_NewInt32(scope.engine.context, 0);
}
pub fn usage(scope: *Scope, value: c.JSValue, model: c.JSValue) !c.JSValue {
    if (!try record(scope, value)) return c.pi_js_undefined();
    if (c.JS_IsUndefined(try scope.get(value, "input_tokens")) and c.JS_IsUndefined(try scope.get(value, "output_tokens"))) return c.pi_js_undefined();
    const input = try tokenCount(scope, try scope.get(value, "input_tokens"));
    const output = try tokenCount(scope, try scope.get(value, "output_tokens"));
    const token_usage = try scope.object();
    try scope.put(token_usage, "input", input);
    try scope.put(token_usage, "output", output);
    try scope.put(token_usage, "cacheRead", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(token_usage, "cacheWrite", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(token_usage, "totalTokens", try binary(scope, .add, input, output));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(token_usage, "cost", cost);
    const priced = try @import("native_ai_cost.zig").calculate(scope.engine, model, token_usage);
    scope.engine.freeValue(priced);
    return token_usage;
}
pub fn result(scope: *Scope, model: c.JSValue, images: bool) !c.JSValue {
    const output = try scope.object();
    inline for (.{ "api", "provider" }) |key| try scope.put(output, key, try scope.get(model, key));
    try scope.put(output, "model", try scope.get(model, "id"));
    try scope.put(output, if (images) "output" else "answers", if (images) try scope.array() else try scope.object());
    try scope.put(output, "stopReason", try scope.text("stop"));
    try scope.put(output, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    return output;
}
pub fn failure(scope: *Scope, output: c.JSValue, options: c.JSValue, reason: c.JSValue, prefix: c.JSValue, clear_answers: bool) !void {
    if (clear_answers) try scope.set(output, "answers", try scope.object());
    const signal = try v.optional(scope, options, "signal");
    try scope.set(output, "stopReason", try scope.text(if (scope.truthy(try v.optional(scope, signal, "aborted"))) "aborted" else "error"));
    const normalized = try @import("native_ai_provider_error.zig").normalize(scope, reason);
    try scope.set(output, "errorMessage", try @import("native_ai_provider_error.zig").format(scope, normalized, prefix));
}
