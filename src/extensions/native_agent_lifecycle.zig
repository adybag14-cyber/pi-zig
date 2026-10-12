//! Original Agent.runWithLifecycle try/catch/finally and idle ownership.
//! Executor and failure-handler awaits use realm intrinsics. The idle promise
//! still uses the ordinary global Promise constructor, as the Source does.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;

pub fn run(engine: *em.Engine, agent: c.JSValue, executor: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, executor) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn begin(engine: *em.Engine, owner: c.JSValue, executor: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(agent, "activeRun"))) {
        _ = try @import("native_agent_methods.zig").raise(&scope, "Agent is already processing.");
    }
    const controller = try scope.own(try js.builtin(engine, "AbortController", &.{}));
    try scope.put(owner, "controller", controller);
    const captured = try scope.object();
    // This is the Source's actual initial () => {} value, overwritten by the
    // ordinary Promise executor in normal construction; it is not an Agent
    // method or a substitute for any missing runtime operation.
    try scope.put(captured, "resolve", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, initialResolve, "resolvePromise", 0))));
    var roots = [_]c.JSValue{captured};
    const capture = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, captureResolve, "", 1, 0, roots.len, &roots)));
    const idle = try scope.own(try js.builtin(engine, "Promise", &.{capture}));
    const active = try scope.object();
    try scope.put(active, "promise", idle);
    try scope.put(active, "resolve", try scope.get(captured, "resolve"));
    try scope.put(active, "abortController", controller);
    try scope.set(agent, "activeRun", active);
    try scope.set(try scope.get(agent, "_state"), "isStreaming", c.pi_js_bool(engine.context, 1));
    try scope.set(try scope.get(agent, "_state"), "streamingMessage", c.pi_js_undefined());
    try scope.set(try scope.get(agent, "_state"), "errorMessage", c.pi_js_undefined());
    execute(engine, owner, executor) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        try failure(engine, owner, raw);
    };
}

fn execute(engine: *em.Engine, owner: c.JSValue, executor: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const controller = try scope.get(owner, "controller");
    const value = try scope.call(executor, c.pi_js_undefined(), &.{try scope.get(controller, "signal")});
    try flow.wait(continuation, engine, owner, value, 0);
}

fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (stage == 0 and rejected) return failure(engine, owner, value);
    try finish(engine, owner, stage == 1 and rejected, value);
}

fn failure(engine: *em.Engine, owner: c.JSValue, raw: c.JSValue) !void {
    awaitFailure(engine, owner, raw) catch |err| {
        const replacement = flow.reason(engine, err);
        defer engine.freeValue(replacement);
        try finish(engine, owner, true, replacement);
    };
}

fn awaitFailure(engine: *em.Engine, owner: c.JSValue, raw: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    const handler = try scope.get(agent, "handleRunFailure");
    const aborted = try scope.get(try scope.get(try scope.get(owner, "controller"), "signal"), "aborted");
    const value = try scope.call(handler, agent, &.{ raw, aborted });
    try flow.wait(continuation, engine, owner, value, 1);
}

fn finish(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = scope.invoke(try scope.get(owner, "agent"), "finishRun", &.{}) catch |err| {
        try flow.rejectError(engine, owner, err);
        return;
    };
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}

fn initialResolve(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}

fn captureResolve(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    sdk.put(engine, roots[0], "resolve", if (argc > 0) c.JS_DupValue(engine.context, argv[0]) else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
