//! Actual native module dependencies retained by OpenAI factory continuations.
const v = @import("native_ai_provider_values.zig");
pub fn create(engine: *v.em.Engine) !v.c.JSValue {
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const thinking = try scope.own(try @import("native_ai_thinking.zig").create(engine));
    const estimate = try scope.own(try @import("native_ai_estimate.zig").create(engine));
    const simple = try scope.own(try @import("native_ai_simple_options.zig").create(engine, try scope.get(thinking, "clampThinkingLevel"), try scope.get(estimate, "estimateContextTokens")));
    const result = try scope.object();
    try scope.put(result, "thinking", thinking);
    try scope.put(result, "simple", simple);
    try scope.put(result, "json", try scope.own(try @import("native_ai_json_parse.zig").create(engine)));
    try scope.put(result, "env", try scope.own(try @import("native_ai_env_keys.zig").create(engine, .{})));
    return v.c.JS_DupValue(engine.context, result);
}
pub fn options(scope: *v.Scope, dependencies: v.c.JSValue, model: v.c.JSValue, context: v.c.JSValue, input: v.c.JSValue) !v.c.JSValue {
    const base = try scope.invoke(try scope.get(dependencies, "simple"), "buildBaseOptions", &.{ model, context, input, try v.optional(scope, input, "apiKey") });
    const copied = try v.spread(scope, base);
    try scope.put(copied, "toolChoice", try v.optional(scope, input, "toolChoice"));
    const reasoning = try v.optional(scope, input, "reasoning");
    const clamped = if (scope.truthy(reasoning)) try scope.invoke(try scope.get(dependencies, "thinking"), "clampThinkingLevel", &.{ model, try scope.get(input, "reasoning") }) else v.c.pi_js_undefined();
    const result = try v.spread(scope, copied);
    try scope.put(result, "reasoningEffort", if (try v.eq(scope, clamped, "off")) v.c.pi_js_undefined() else clamped);
    try scope.put(result, "thinkingBudgets", try v.optional(scope, input, "thinkingBudgets"));
    return result;
}
