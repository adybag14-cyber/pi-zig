//! Actual pi-ai simple-options bodies with shared native module dependencies.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum { clampMaxTokensToContext, resolveSamplingParams, buildBaseOptions, clampReasoning, thinkingBudgetForLevel, clampThinkingBudgetToAnswerRoom, adjustMaxTokensForThinking };
pub fn create(engine: *em.Engine, clamp_thinking: c.JSValue, estimate_context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "clampThinking", clamp_thinking);
    try scope.put(owner, "estimateContext", estimate_context);
    const budgets = try scope.object();
    inline for (.{ .{ "minimal", 1024 }, .{ "low", 2048 }, .{ "medium", 8192 }, .{ "high", 16384 } }) |entry| try scope.put(budgets, entry[0], c.JS_NewInt32(engine.context, entry[1]));
    try scope.put(owner, "budgets", budgets);
    const exports = try scope.object();
    try scope.put(exports, "MIN_ANSWER_TOKENS", c.JS_NewInt32(engine.context, 1024));
    try scope.put(exports, "DEFAULT_THINKING_BUDGETS", budgets);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                return dispatch(host, roots[0], method, args);
            }
        };
        const length = switch (method) {
            .clampMaxTokensToContext, .resolveSamplingParams => 3,
            .buildBaseOptions, .adjustMaxTokensForThinking => 4,
            .clampReasoning => 1,
            else => 2,
        };
        try scope.put(exports, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, length, Adapter.call, &.{owner})));
    }
    return c.JS_DupValue(engine.context, exports);
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (args.len > i) args[i] else c.pi_js_undefined();
}
fn op(scope: *Scope, kind: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, kind, left, right));
}
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn nullish(value: c.JSValue, fallback: c.JSValue) c.JSValue {
    return if (temp.nullish(value)) fallback else value;
}
fn clampReason(scope: *Scope, effort: c.JSValue) !c.JSValue {
    return if (scope.equal(effort, try scope.text("xhigh")) or scope.equal(effort, try scope.text("max"))) scope.text("high") else effort;
}
fn budget(scope: *Scope, owner: c.JSValue, level: c.JSValue, custom: c.JSValue) !c.JSValue {
    const merged = try scope.own(try js.spread(scope.engine, try scope.get(owner, "budgets")));
    try js.spreadInto(scope.engine, merged, custom);
    return scope.own(try js.getKey(scope.engine, merged, try clampReason(scope, level)));
}
fn answerRoom(scope: *Scope, thinking: c.JSValue, ceiling: c.JSValue) !c.JSValue {
    const math = try scope.global("Math");
    const min = try scope.get(math, "min");
    const max_receiver = try scope.global("Math");
    const max = try scope.get(max_receiver, "max");
    const remaining = try scope.call(max, max_receiver, &.{ c.JS_NewInt32(scope.engine.context, 0), try op(scope, .subtract, ceiling, c.JS_NewInt32(scope.engine.context, 1024)) });
    return scope.call(min, math, &.{ thinking, remaining });
}
fn maxTokens(scope: *Scope, owner: c.JSValue, model: c.JSValue, context: c.JSValue, requested: c.JSValue) !c.JSValue {
    if (try arithmetic.compare(scope.engine, .less_equal, try scope.get(model, "contextWindow"), c.JS_NewInt32(scope.engine.context, 0))) return scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 1), requested });
    const window = try scope.get(model, "contextWindow");
    const estimate = try scope.call(try scope.get(owner, "estimateContext"), c.pi_js_undefined(), &.{context});
    const available = try op(scope, .subtract, try op(scope, .subtract, window, try scope.get(estimate, "tokens")), c.JS_NewInt32(scope.engine.context, 4096));
    const math = try scope.global("Math");
    const min = try scope.get(math, "min");
    const inner = try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 1), available });
    return scope.call(min, math, &.{ requested, inner });
}
fn sampling(scope: *Scope, owner: c.JSValue, model: c.JSValue, level: c.JSValue, requested: c.JSValue) !c.JSValue {
    const effective = try scope.call(try scope.get(owner, "clampThinking"), c.pi_js_undefined(), &.{ model, level });
    const map = try scope.get(model, "samplingParamsByThinkingLevel");
    const per_level = if (temp.nullish(map)) c.pi_js_undefined() else try scope.own(try js.getKey(scope.engine, map, effective));
    if (!scope.truthy(try scope.get(model, "samplingParams")) and !scope.truthy(per_level) and !scope.truthy(requested)) return c.pi_js_undefined();
    const merged = try scope.own(try js.spread(scope.engine, try scope.get(model, "samplingParams")));
    try js.spreadInto(scope.engine, merged, per_level);
    try js.spreadInto(scope.engine, merged, requested);
    return merged;
}
fn dispatch(engine: *em.Engine, owner: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = arg(args, 0);
    const second = arg(args, 1);
    const third = arg(args, 2);
    const fourth = arg(args, 3);
    const value = switch (method) {
        .clampReasoning => try clampReason(&scope, first),
        .thinkingBudgetForLevel => try budget(&scope, owner, first, second),
        .clampThinkingBudgetToAnswerRoom => try answerRoom(&scope, first, second),
        .clampMaxTokensToContext => try maxTokens(&scope, owner, first, second, third),
        .resolveSamplingParams => try sampling(&scope, owner, first, second, third),
        .adjustMaxTokensForThinking => blk: {
            var thinking = try budget(&scope, owner, third, fourth);
            const limit = if (c.JS_IsUndefined(first)) second else capped: {
                const math = try scope.global("Math");
                const min = try scope.get(math, "min");
                break :capped try scope.call(min, math, &.{ try op(&scope, .add, first, thinking), second });
            };
            if (try arithmetic.compare(engine, .less_equal, limit, thinking)) thinking = try answerRoom(&scope, thinking, limit);
            const result = try scope.object();
            try scope.put(result, "maxTokens", limit);
            try scope.put(result, "thinkingBudget", thinking);
            break :blk result;
        },
        .buildBaseOptions => blk: {
            const effective = try optional(&scope, third, "reasoning");
            const requested = try optional(&scope, third, "samplingParams");
            const params = try sampling(&scope, owner, first, nullish(effective, try scope.text("off")), requested);
            const result = try scope.object();
            try scope.put(result, "temperature", try optional(&scope, third, "temperature"));
            try scope.put(result, "samplingParams", params);
            const caller_limit = try optional(&scope, third, "maxTokens");
            const raw_limit = if (temp.nullish(caller_limit)) try scope.get(first, "maxTokens") else caller_limit;
            try scope.put(result, "maxTokens", try maxTokens(&scope, owner, first, second, raw_limit));
            inline for (.{ "signal", "telemetryContext" }) |name| try scope.put(result, name, try optional(&scope, third, name));
            try scope.put(result, "apiKey", if (scope.truthy(fourth)) fourth else try optional(&scope, third, "apiKey"));
            inline for (.{ "fetch", "transport", "cacheRetention", "sessionId", "headers", "onPayload", "onResponse", "onProviderStreamEvent", "timeoutMs", "websocketConnectTimeoutMs", "maxRetries", "maxRetryDelayMs", "metadata", "env" }) |name| try scope.put(result, name, try optional(&scope, third, name));
            break :blk result;
        },
    };
    return c.JS_DupValue(engine.context, value);
}
