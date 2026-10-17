//! Source runWithLifecycle: actual idle Promise, direct AF catch/finally.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const functions = @import("native_node_function.zig");
const executor_fatal = @import("native_agent_executor_fatal.zig");
pub fn create(engine: *em.Engine) !c.JSValue { return af.createResumable(engine, "runWithLifecycle", 1, invoke, &.{}); }
fn invoke(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, agent, args, state, completion, input) catch |err| p.failure(engine, err);
}
fn run(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion != .start) {
        const stage = try p.stage(&s, state.*);
        if (completion == .rejected) {
            try p.rejected(&s, state.*, input);
            if (stage == 0) return caught(&s, agent, state.*, input);
            return finish(&s, agent, true, input);
        }
        return finish(&s, agent, false, c.pi_js_undefined());
    }
    const owner = try p.init(&s, state);
    if (s.truthy(try p.get(&s, agent, "activeRun"))) _ = try p.raise(&s, "Agent is already processing.");
    const controller = try p.construct(&s, try p.global(&s, "AbortController"), &.{});
    try s.put(owner, "controller", controller);
    const cell = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(cell, "resolve", try s.own(try functions.createArrow(engine, "resolvePromise", 0, noop, &.{})));
    try s.put(owner, "resolveCell", cell);
    const promise_constructor = try p.global(&s, "Promise");
    const fatal = try s.own(try executor_fatal.create(engine));
    const capture = try s.own(try functions.createArrow(engine, "", 1, captureResolve, &.{ cell, fatal }));
    const idle = try executor_fatal.construct(&s, promise_constructor, &.{capture}, fatal);
    try s.put(owner, "promise", idle);
    const active = try s.object();
    try s.put(active, "promise", idle);
    try s.put(active, "resolve", try s.get(cell, "resolve"));
    try s.put(active, "abortController", controller);
    try p.set(&s, agent, "activeRun", active);
    try p.set(&s, try p.get(&s, agent, "_state"), "isStreaming", c.pi_js_bool(engine.context, 1));
    try p.set(&s, try p.get(&s, agent, "_state"), "streamingMessage", c.pi_js_undefined());
    try p.set(&s, try p.get(&s, agent, "_state"), "errorMessage", c.pi_js_undefined());
    // The Source try starts after all setup and state assignments.
    return execute(&s, owner, if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| {
        const reason = try s.own(try p.caught(engine, err));
        return caught(&s, agent, owner, reason);
    };
}
fn execute(s: *p.Scope, owner: c.JSValue, executor: c.JSValue) !af.Action {
    const signal = try p.get(s, try s.get(owner, "controller"), "signal");
    return p.wait(s, owner, executor, c.pi_js_undefined(), &.{signal}, 0);
}
fn caught(s: *p.Scope, agent: c.JSValue, owner: c.JSValue, reason: c.JSValue) !af.Action {
    try s.put(owner, "caughtReason", reason);
    return handle(s, agent, owner, reason) catch |err| {
        const replacement = try s.own(try p.caught(s.engine, err));
        return finish(s, agent, true, replacement);
    };
}
fn handle(s: *p.Scope, agent: c.JSValue, owner: c.JSValue, reason: c.JSValue) !af.Action {
    const handler = try p.get(s, agent, "handleRunFailure");
    const aborted = try p.get(s, try p.get(s, try s.get(owner, "controller"), "signal"), "aborted");
    return p.wait(s, owner, handler, agent, &.{ reason, aborted }, 1);
}
fn finish(s: *p.Scope, agent: c.JSValue, rejected: bool, reason: c.JSValue) !af.Action {
    _ = try p.invoke(s, agent, "finishRun", &.{});
    return if (rejected) .{ .thrown = c.JS_DupValue(s.engine.context, reason) } else .{ .returned = c.pi_js_undefined() };
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
fn captureResolve(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const generation = engine.native_allocation_generation;
    s.put(roots[0], "resolve", if (args.len > 0) args[0] else c.pi_js_undefined()) catch |err| {
        return executor_fatal.callbackFailure(engine, roots[1], err, generation);
    };
    return c.pi_js_undefined();
}
