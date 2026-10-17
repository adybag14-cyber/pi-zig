//! Actual processEvents reducer and synchronous for-of with awaited listeners.
const p = @import("native_agent_af_values.zig");
const em = @import("engine.zig");
const c = p.c;
const af = p.af;
const js = @import("native_js_values.zig");
pub fn create(engine: *em.Engine) !c.JSValue { return af.createResumable(engine, "processEvents", 1, invoke, &.{}); }
fn invoke(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) anyerror!af.Action {
    return run(engine, agent, args, state, completion, input) catch |err| p.failure(engine, err);
}
fn run(engine: *em.Engine, agent: c.JSValue, args: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    if (completion == .rejected) { try p.rejected(&s, state.*, input); return closeThrow(&s, state.*, input); }
    if (completion == .fulfilled) return next(&s, state.*);
    const owner = try p.init(&s, state);
    const event = if (args.len > 0) args[0] else c.pi_js_undefined();
    try s.put(owner, "event", event);
    try reduce(&s, agent, event);
    const active = try p.get(&s, agent, "activeRun");
    const signal = if (c.JS_IsNull(active) or c.JS_IsUndefined(active)) c.pi_js_undefined() else try p.get(&s, try p.get(&s, active, "abortController"), "signal");
    if (!s.truthy(signal)) _ = try p.raise(&s, "Agent listener invoked outside active run");
    try s.put(owner, "signal", signal);
    const listeners = try p.get(&s, agent, "listeners");
    const symbol = try s.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    const generation = engine.native_allocation_generation;
    const method = try s.own(try p.guard(engine, generation, js.getKey(engine, listeners, symbol)));
    const iterator = try p.call(&s, method, listeners, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(engine, "Iterator is not an object");
    try s.put(owner, "iterator", iterator);
    try s.put(owner, "next", try p.get(&s, iterator, "next"));
    try s.put(owner, "steps", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, 0))));
    return next(&s, owner);
}
fn next(s: *p.Scope, owner: c.JSValue) !af.Action {
    var steps: u64 = 0;
    if (c.JS_ToBigUint64(s.engine.context, &steps, try s.get(owner, "steps")) < 0) return js.capture(s.engine);
    steps +|= 1;
    if (s.engine.cancelled.load(.acquire) or (steps % 256 == 0 and blk: {
        s.engine.interrupts +|= 1;
        break :blk s.engine.interrupts > s.engine.options.interrupt_budget;
    })) { _ = try s.engine.checked(c.JS_ThrowInternalError(s.engine.context, "interrupted")); unreachable; }
    try s.put(owner, "steps", try s.own(try s.engine.checked(c.JS_NewBigUint64(s.engine.context, steps))));
    // Iterator step/result/done/value failures precede the Source loop body and
    // must not invoke return. The captured next method is never reread.
    const iterator = try s.get(owner, "iterator");
    const result = try p.call(s, try s.get(owner, "next"), iterator, &.{});
    if (!c.JS_IsObject(result)) return js.typeError(s.engine, "Iterator result is not an object");
    if (s.truthy(try p.get(s, result, "done"))) return .{ .returned = c.pi_js_undefined() };
    const listener = try p.get(s, result, "value");
    try s.put(owner, "listener", listener);
    return listen(s, owner, listener) catch |err| {
        const reason = try s.own(try p.caught(s.engine, err));
        return closeThrow(s, owner, reason);
    };
}
fn listen(s: *p.Scope, owner: c.JSValue, listener: c.JSValue) !af.Action { return p.wait(s, owner, listener, c.pi_js_undefined(), &.{ try s.get(owner, "event"), try s.get(owner, "signal") }, 0); }
fn closeThrow(s: *p.Scope, owner: c.JSValue, reason: c.JSValue) !af.Action {
    close(s, owner) catch |err| {
        // Sync IteratorClose preserves an ordinary original body throw over
        // ordinary return getter/call/type errors. Fresh trusted fatal escapes.
        const discarded = try p.caught(s.engine, err);
        s.engine.freeValue(discarded);
    };
    return .{ .thrown = c.JS_DupValue(s.engine.context, reason) };
}
fn close(s: *p.Scope, owner: c.JSValue) !void {
    const iterator = try s.get(owner, "iterator");
    const method = try p.get(s, iterator, "return");
    if (c.JS_IsNull(method) or c.JS_IsUndefined(method)) return;
    // This is synchronous for-of. Never Await a Promise returned by return().
    _ = try p.call(s, method, iterator, &.{});
}
fn reduce(s: *p.Scope, agent: c.JSValue, event: c.JSValue) !void {
    const kind = try p.get(s, event, "type");
    if (s.equal(kind, try s.text("message_start")) or s.equal(kind, try s.text("message_update"))) {
        try p.set(s, try p.get(s, agent, "_state"), "streamingMessage", try p.get(s, event, "message"));
    } else if (s.equal(kind, try s.text("message_end"))) {
        try p.set(s, try p.get(s, agent, "_state"), "streamingMessage", c.pi_js_undefined());
        const messages = try p.get(s, try p.get(s, agent, "_state"), "messages");
        const push = try p.get(s, messages, "push");
        _ = try p.call(s, push, messages, &.{try p.get(s, event, "message")});
    } else if (s.equal(kind, try s.text("tool_execution_start")) or s.equal(kind, try s.text("tool_execution_end"))) {
        const constructor = try p.global(s, "Set");
        const prior = try p.get(s, try p.get(s, agent, "_state"), "pendingToolCalls");
        const pending = try p.construct(s, constructor, &.{prior});
        const callback = try p.get(s, pending, if (s.equal(kind, try s.text("tool_execution_start"))) "add" else "delete");
        _ = try p.call(s, callback, pending, &.{try p.get(s, event, "toolCallId")});
        try p.set(s, try p.get(s, agent, "_state"), "pendingToolCalls", pending);
    } else if (s.equal(kind, try s.text("turn_end"))) {
        if (s.equal(try p.get(s, try p.get(s, event, "message"), "role"), try s.text("assistant")) and s.truthy(try p.get(s, try p.get(s, event, "message"), "errorMessage"))) try p.set(s, try p.get(s, agent, "_state"), "errorMessage", try p.get(s, try p.get(s, event, "message"), "errorMessage"));
    } else if (s.equal(kind, try s.text("agent_end"))) try p.set(s, try p.get(s, agent, "_state"), "streamingMessage", c.pi_js_undefined());
}
