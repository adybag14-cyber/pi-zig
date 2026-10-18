//! Genuine Pi1.3 Agent.prompt/continue bodies. Each selected Source Await is
//! passed directly to the native AF primitive; no flow-owned Promise is made.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const body = @import("native_async_body.zig");
const af = body.native;
const functions = @import("native_node_function.zig");
const p = @import("native_agent_af_values.zig");
pub const Kind = enum { prompt, continue_run };

pub fn create(engine: *v.em.Engine, comptime kind: Kind) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
            return invoke(host, kind, receiver, args, state, completion, input) catch |err| p.failure(host, err);
        }
    };
    return af.createResumable(engine, if (kind == .prompt) "prompt" else "continue", if (kind == .prompt) 2 else 0, Adapter.call, &.{});
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (args.len > index) args[index] else c.pi_js_undefined(); }
fn invoke(engine: *v.em.Engine, comptime kind: Kind, receiver: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .fulfilled) return .{ .returned = c.pi_js_undefined() };
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) {
        try body.enterRejectedContinuation(engine);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    af.replaceState(engine, state, c.JS_DupValue(engine.context, owner));
    if (kind == .prompt) {
        if (s.truthy(try p.get(&s, receiver, "activeRun"))) _ = try @import("native_agent_methods.zig").raise(&s, "Agent is already processing a prompt. Use steer() or followUp() to queue messages, or wait for completion.");
        const messages = try p.invoke(&s, receiver, "normalizePromptInput", &.{arg(args, 0), arg(args, 1)});
        try s.put(owner, "messages", messages);
        const handler = try p.get(&s, receiver, "runPromptMessages");
        return awaitCall(&s, owner, handler, receiver, &.{messages});
    }
    if (s.truthy(try p.get(&s, receiver, "activeRun"))) _ = try @import("native_agent_methods.zig").raise(&s, "Agent is already processing. Wait for completion before continuing.");
    const messages = try p.get(&s, try p.get(&s, receiver, "_state"), "messages");
    const length = try p.get(&s, try p.get(&s, try p.get(&s, receiver, "_state"), "messages"), "length");
    const index = try p.binary(&s, 1, length, c.JS_NewInt32(engine.context, 1));
    const last = try p.getKey(&s, messages, index);
    try s.put(owner, "lastMessage", last);
    if (!s.truthy(last)) _ = try @import("native_agent_methods.zig").raise(&s, "No messages to continue from");
    const current = try p.get(&s, try p.get(&s, receiver, "_state"), "messages");
    const every = try p.get(&s, current, "every");
    const predicate = try s.own(try functions.createArrow(engine, "", 1, systemOnly, &.{}));
    if (s.truthy(try p.call(&s, every, current, &.{predicate}))) _ = try @import("native_agent_methods.zig").raise(&s, "No messages to continue from");
    if (s.equal(try p.get(&s, last, "role"), try s.text("assistant"))) {
        const steering = try p.invoke(&s, try p.get(&s, receiver, "steeringQueue"), "drain", &.{});
        try s.put(owner, "queuedSteering", steering);
        if (try p.positive(&s, try p.get(&s, steering, "length"))) {
            const handler = try p.get(&s, receiver, "runPromptMessages");
            const options = try s.object();
            try s.put(options, "skipInitialSteeringPoll", c.pi_js_bool(engine.context, 1));
            return awaitCall(&s, owner, handler, receiver, &.{steering, options});
        }
        const follow_up = try p.invoke(&s, try p.get(&s, receiver, "followUpQueue"), "drain", &.{});
        try s.put(owner, "queuedFollowUps", follow_up);
        if (try p.positive(&s, try p.get(&s, follow_up, "length"))) {
            const handler = try p.get(&s, receiver, "runPromptMessages");
            return awaitCall(&s, owner, handler, receiver, &.{follow_up});
        }
        _ = try @import("native_agent_methods.zig").raise(&s, "Cannot continue from message role: assistant");
    }
    const handler = try p.get(&s, receiver, "runContinuation");
    return awaitCall(&s, owner, handler, receiver, &.{});
}
fn awaitCall(s: *Scope, _: c.JSValue, handler: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !af.Action {
    const value = try p.call(s, handler, receiver, args);
    return .{ .awaited = c.JS_DupValue(s.engine.context, value) };
}
fn systemOnly(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return c.JS_NewBool(engine.context, s.equal(try p.get(&s, arg(args, 0), "role"), try s.text("system")));
}
