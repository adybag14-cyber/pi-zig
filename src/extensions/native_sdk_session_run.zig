//! Original AgentSession._startRun ordering over live receiver dependencies.
//! This private body does not supply absent session methods or activate a class.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
const Stage = enum(c_int) { prepared, prompted, post, boundary, continued, finalized };

pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    const method = try engine.checked(c.JS_NewCFunction(engine.context, start, "_startRun", 2));
    defer engine.freeValue(method);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, method, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "_startRun", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn start(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, receiver: c.JSValue, trigger: c.JSValue, started: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, trigger, started) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, trigger: c.JSValue, started: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    try scope.put(owner, "enteredRunTry", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "started", started);
    try scope.set(receiver, "_isAgentRunActive", c.pi_js_bool(engine.context, 1));
    try scope.set(receiver, "_agentRunAbortRequested", c.pi_js_bool(engine.context, 0));
    const prepared = scope.invoke(receiver, "_prepareRun", &.{trigger}) catch |err| {
        const reason = flow.reason(engine, err);
        defer engine.freeValue(reason);
        return prepareFailed(engine, owner, reason);
    };
    try wait(engine, owner, prepared, .prepared);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try flow.wait(continuation, engine, owner, value, @intFromEnum(stage));
}
fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, magic: c_int) !void {
    advance(engine, owner, value, rejected, @enumFromInt(magic)) catch |err| {
        const entered = try sdk.get(engine, owner, "enteredRunTry");
        defer engine.freeValue(entered);
        if (c.JS_ToBool(engine.context, entered) == 1) {
            const reason = flow.reason(engine, err);
            defer engine.freeValue(reason);
            return finalize(engine, owner, reason, true);
        }
        return err;
    };
}
fn prepareFailed(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    try scope.set(receiver, "_isAgentRunActive", c.pi_js_bool(engine.context, 0));
    _ = try scope.invoke(receiver, "_flushPendingBashMessages", &.{});
    _ = try scope.invoke(receiver, "_flushPendingCustomMessages", &.{});
    _ = try scope.invoke(receiver, "_resolveIdleWaitIfIdle", &.{});
    try flow.settle(engine, owner, true, reason);
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    if (stage == .prepared and rejected) return prepareFailed(engine, owner, value);
    if (stage == .finalized) {
        if (rejected) return flow.settle(engine, owner, true, value);
        const failed = try sdk.get(engine, owner, "runFailed");
        defer engine.freeValue(failed);
        const reason = try sdk.get(engine, owner, "runReason");
        defer engine.freeValue(reason);
        return flow.settle(engine, owner, c.JS_ToBool(engine.context, failed) == 1, reason);
    }
    if (rejected) return finalize(engine, owner, value, true);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    switch (stage) {
        .prepared => {
            _ = try scope.invoke(receiver, "_flushPendingBashMessages", &.{});
            _ = try scope.invoke(receiver, "_flushPendingCustomMessages", &.{});
            const started = try scope.get(owner, "started");
            if (!temp.nullish(started)) _ = try scope.call(started, c.pi_js_undefined(), &.{});
            try scope.set(receiver, "_failedResponse", c.pi_js_undefined());
            _ = try scope.invoke(receiver, "_recordSelection", &.{});
            _ = try scope.invoke(try scope.get(receiver, "_pendingToolNames"), "clear", &.{});
            // Only the agent invocation and subsequent loop are inside Source's
            // second try/finally; failures in the prelude above do not enter it.
            try scope.put(owner, "enteredRunTry", c.pi_js_bool(engine.context, 1));
            const result = try scope.invoke(try scope.get(receiver, "agent"), "prompt", &.{value});
            try wait(engine, owner, result, .prompted);
        },
        .prompted, .continued => try loop(engine, owner),
        .post => {
            if (scope.truthy(value)) {
                if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) return finalize(engine, owner, c.pi_js_undefined(), false);
                return continueAgent(engine, owner);
            }
            if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) return finalize(engine, owner, c.pi_js_undefined(), false);
            const result = try scope.invoke(receiver, "_runBeforeSettleBoundary", &.{});
            try wait(engine, owner, result, .boundary);
        },
        .boundary => {
            if (!scope.truthy(value)) return finalize(engine, owner, c.pi_js_undefined(), false);
            if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) return finalize(engine, owner, c.pi_js_undefined(), false);
            try continueAgent(engine, owner);
        },
        .finalized => unreachable,
    }
}
fn loop(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) return finalize(engine, owner, c.pi_js_undefined(), false);
    const result = try scope.invoke(receiver, "_handlePostAgentRun", &.{});
    try wait(engine, owner, result, .post);
}
fn continueAgent(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.invoke(try scope.get(try scope.get(owner, "agent"), "agent"), "continue", &.{});
    try wait(engine, owner, result, .continued);
}
fn finalize(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue, failed: bool) !void {
    // Retire the try marker before invoking any cleanup getter or callback, so
    // an error in finally overrides the prior error without running finally twice.
    try sdk.put(engine, owner, "enteredRunTry", c.pi_js_bool(engine.context, 0));
    try sdk.put(engine, owner, "runFailed", c.pi_js_bool(engine.context, @intFromBool(failed)));
    try sdk.put(engine, owner, "runReason", c.JS_DupValue(engine.context, reason));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(receiver, "_agentRunAbortRequested"))) _ = try scope.invoke(receiver, "_finishCancelledRetry", &.{});
    try scope.set(receiver, "_failedResponse", c.pi_js_undefined());
    try scope.set(receiver, "_runSystemPromptOptions", c.pi_js_undefined());
    _ = try scope.invoke(receiver, "_flushPendingBashMessages", &.{});
    _ = try scope.invoke(receiver, "_flushPendingCustomMessages", &.{});
    const settled = try scope.invoke(receiver, "_emitAgentSettled", &.{});
    try wait(engine, owner, settled, .finalized);
}
