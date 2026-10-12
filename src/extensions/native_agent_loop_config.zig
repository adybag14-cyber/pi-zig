//! Actual Agent.createLoopConfig fields and closure-owned queue callbacks.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Kind = enum(c_int) { prepare, steering, follow_up };

pub fn create(engine: *em.Engine, agent: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (c.JS_IsUndefined(options)) try scope.object() else options;
    const skip = scope.equal(try scope.get(input, "skipInitialSteeringPoll"), c.pi_js_bool(engine.context, 1));
    const captured = try scope.object();
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
    var roots = [_]c.JSValue{ agent, captured };
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, name, length, @intFromEnum(kind), roots.len, &roots));
    errdefer engine.freeValue(function);
    const prototype = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, function, prototype) < 0) return js.capture(engine);
    return function;
}

fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return run(engine, roots[0], roots[1], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn run(engine: *em.Engine, agent: c.JSValue, captured: c.JSValue, kind: Kind, context: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, captured, kind, context) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn begin(engine: *em.Engine, owner: c.JSValue, captured: c.JSValue, kind: Kind, context: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    if (kind == .steering and scope.truthy(try scope.get(captured, "skip"))) {
        try scope.set(captured, "skip", c.pi_js_bool(engine.context, 0));
        return flow.settle(engine, owner, false, try scope.array());
    }
    if (kind != .prepare) {
        const queue = try scope.get(agent, if (kind == .steering) "steeringQueue" else "followUpQueue");
        return flow.settle(engine, owner, false, try scope.invoke(queue, "drain", &.{}));
    }
    const with_context = try scope.get(agent, "prepareNextTurnWithContext");
    const value = if (scope.truthy(with_context)) with: {
        const handler = try scope.get(agent, "prepareNextTurnWithContext");
        const signal = try scope.get(agent, "signal");
        break :with try scope.call(handler, agent, &.{ context, signal });
    } else without: {
        const handler = try scope.get(agent, "prepareNextTurn");
        if (temp.nullish(handler)) break :without c.pi_js_undefined();
        break :without try scope.call(handler, agent, &.{try scope.get(agent, "signal")});
    };
    try flow.wait(continuation, engine, owner, value, 0);
}

fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, value);
}
