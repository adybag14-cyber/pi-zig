//! Actual Agent.createLoopConfig fields and closure-owned queue callbacks.
const em = @import("engine.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const Kind = enum(c_int) { prepare, steering, follow_up };

pub fn create(engine: *em.Engine, agent: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (c.JS_IsUndefined(options)) try scope.object() else options;
    const skip = scope.equal(try scope.get(input, "skipInitialSteeringPoll"), c.pi_js_bool(engine.context, 1));
    const captured = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(captured, "skip", c.pi_js_bool(engine.context, @intFromBool(skip)));
    const result = try scope.object();
    try scope.put(result, "model", try scope.get(try scope.get(agent, "_state"), "model"));
    const reasoning = if (scope.equal(try scope.get(try scope.get(agent, "_state"), "thinkingLevel"), try scope.text("off"))) c.pi_js_undefined() else try scope.get(try scope.get(agent, "_state"), "thinkingLevel");
    try scope.put(result, "reasoning", reasoning);
    inline for (.{ "sessionId", "onPayload", "onResponse", "onProviderStreamEvent", "transport", "thinkingBudgets", "maxRetryDelayMs", "toolExecution", "beforeToolCall", "afterToolCall", "finishTurn", "prepareRequest" }) |name| try scope.put(result, name, try scope.get(agent, name));
    const with_context = try scope.get(agent, "prepareNextTurnWithContext");
    const has_prepare = scope.truthy(with_context) or scope.truthy(try scope.get(agent, "prepareNextTurn"));
    try scope.put(result, "prepareNextTurn", if (has_prepare) try scope.own(try callback(engine, agent, captured, .prepare, "", 1)) else c.pi_js_undefined());
    inline for (.{ "convertToLlm", "transformContext", "getApiKey" }) |name| try scope.put(result, name, try scope.get(agent, name));
    try scope.put(result, "getSteeringMessages", try scope.own(try callback(engine, agent, captured, .steering, "getSteeringMessages", 0)));
    try scope.put(result, "getFollowUpMessages", try scope.own(try callback(engine, agent, captured, .follow_up, "getFollowUpMessages", 0)));
    return c.JS_DupValue(engine.context, result);
}

fn callback(engine: *em.Engine, agent: c.JSValue, captured: c.JSValue, kind: Kind, name: [:0]const u8, length: c_int) !c.JSValue {
    return @import("native_agent_config_async.zig").create(engine, agent, captured, @enumFromInt(@intFromEnum(kind)), name, length);
}
