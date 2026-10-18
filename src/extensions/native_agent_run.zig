//! Actual Agent prompt/continue routing and lifecycle-owned loop executors.
//! Loop callables are the installer's captured native module imports; there is
//! no fallback implementation and this module installs no public facade.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn prompt(engine: *em.Engine, agent: c.JSValue, input: c.JSValue, images: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startPrompt(engine, pending.owner, input, images) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn startPrompt(engine: *em.Engine, owner: c.JSValue, input: c.JSValue, images: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(agent, "activeRun"))) _ = try @import("native_agent_methods.zig").raise(&scope, "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.");
    const messages = try scope.invoke(agent, "normalizePromptInput", &.{ input, images });
    const result = try scope.invoke(agent, "runPromptMessages", &.{messages});
    try flow.wait(finishVoid, engine, owner, result, 0);
}

pub fn continueRun(engine: *em.Engine, agent: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startContinuation(engine, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn startContinuation(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(agent, "activeRun"))) _ = try @import("native_agent_methods.zig").raise(&scope, "Agent is already processing. Wait for completion before continuing.");
    const messages = try scope.get(try scope.get(agent, "_state"), "messages");
    const length = try scope.get(try scope.get(try scope.get(agent, "_state"), "messages"), "length");
    const index = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, length, c.JS_NewInt32(engine.context, 1))));
    const last = try scope.own(try @import("native_sdk_models.zig").property(engine, messages, index));
    if (!scope.truthy(last)) _ = try @import("native_agent_methods.zig").raise(&scope, "No messages to continue from");
    const current_messages = try scope.get(try scope.get(agent, "_state"), "messages");
    const every = try scope.get(current_messages, "every");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, systemOnly, "", 1)));
    if (scope.truthy(try scope.call(every, current_messages, &.{predicate}))) _ = try @import("native_agent_methods.zig").raise(&scope, "No messages to continue from");
    if (scope.equal(try scope.get(last, "role"), try scope.text("assistant"))) {
        const steering = try scope.invoke(try scope.get(agent, "steeringQueue"), "drain", &.{});
        if (try scope.positive(try scope.get(steering, "length"))) {
            const handler = try scope.get(agent, "runPromptMessages");
            const options = try scope.object();
            try scope.put(options, "skipInitialSteeringPoll", c.pi_js_bool(engine.context, 1));
            const result = try scope.call(handler, agent, &.{ steering, options });
            return flow.wait(finishVoid, engine, owner, result, 0);
        }
        const follow_up = try scope.invoke(try scope.get(agent, "followUpQueue"), "drain", &.{});
        if (try scope.positive(try scope.get(follow_up, "length"))) return flow.wait(finishVoid, engine, owner, try scope.invoke(agent, "runPromptMessages", &.{follow_up}), 0);
        _ = try @import("native_agent_methods.zig").raise(&scope, "Cannot continue from message role: assistant");
    }
    try flow.wait(finishVoid, engine, owner, try scope.invoke(agent, "runContinuation", &.{}), 0);
}

fn systemOnly(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return isSystem(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}

fn isSystem(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(message, "role"), try scope.text("system"))));
}

pub fn runMessages(engine: *em.Engine, agent: c.JSValue, messages: c.JSValue, options: c.JSValue, actual_loop: c.JSValue, continuing: bool) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startRun(engine, pending.owner, messages, options, actual_loop, continuing) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn startRun(engine: *em.Engine, owner: c.JSValue, messages: c.JSValue, options: c.JSValue, actual_loop: c.JSValue, continuing: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const input = if (c.JS_IsUndefined(options)) try scope.object() else options;
    const agent = try scope.get(owner, "agent");
    const lifecycle = try scope.get(agent, "runWithLifecycle");
    const executor = try scope.own(if (continuing)
        try @import("native_agent_execution_async.zig").createExecutor(engine, true, agent, messages, input, actual_loop)
    else
        try @import("native_agent_execution_async.zig").createExecutor(engine, false, agent, messages, input, actual_loop));
    const result = try scope.call(lifecycle, agent, &.{executor});
    try flow.wait(finishVoid, engine, owner, result, 0);
}

fn finishVoid(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
