//! Actual Agent.processEvents state reduction followed by live iterator awaits.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;

pub fn process(engine: *em.Engine, agent: c.JSValue, event: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, agent);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, event) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}

fn begin(engine: *em.Engine, owner: c.JSValue, event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const agent = try scope.get(owner, "agent");
    try scope.put(owner, "event", event);
    try reduce(&scope, agent, event);
    const active = try scope.get(agent, "activeRun");
    const signal = if (temp.nullish(active)) c.pi_js_undefined() else try scope.get(try scope.get(active, "abortController"), "signal");
    if (!scope.truthy(signal)) _ = try @import("native_agent_methods.zig").raise(&scope, "Agent listener invoked outside active run");
    try scope.put(owner, "signal", signal);
    const listeners = try scope.get(agent, "listeners");
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, listeners, symbol);
    defer iterator.deinit();
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try scope.put(owner, "steps", c.JS_NewInt32(engine.context, 0));
    try advance(engine, owner);
}

fn reduce(scope: *Scope, agent: c.JSValue, event: c.JSValue) !void {
    const kind = try scope.get(event, "type");
    if (scope.equal(kind, try scope.text("message_start")) or scope.equal(kind, try scope.text("message_update"))) {
        const state = try scope.get(agent, "_state");
        try scope.set(state, "streamingMessage", try scope.get(event, "message"));
    } else if (scope.equal(kind, try scope.text("message_end"))) {
        try scope.set(try scope.get(agent, "_state"), "streamingMessage", c.pi_js_undefined());
        const messages = try scope.get(try scope.get(agent, "_state"), "messages");
        const push = try scope.get(messages, "push");
        _ = try scope.call(push, messages, &.{try scope.get(event, "message")});
    } else if (scope.equal(kind, try scope.text("tool_execution_start")) or scope.equal(kind, try scope.text("tool_execution_end"))) {
        // Source evaluates the global Set constructor before the initial
        // pending-call argument and reads event.toolCallId after add/delete.
        const constructor = try scope.global("Set");
        const prior = try scope.get(try scope.get(agent, "_state"), "pendingToolCalls");
        var args = [_]c.JSValue{prior};
        const pending = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
        const callback = try scope.get(pending, if (scope.equal(kind, try scope.text("tool_execution_start"))) "add" else "delete");
        _ = try scope.call(callback, pending, &.{try scope.get(event, "toolCallId")});
        try scope.set(try scope.get(agent, "_state"), "pendingToolCalls", pending);
    } else if (scope.equal(kind, try scope.text("turn_end"))) {
        if (scope.equal(try scope.get(try scope.get(event, "message"), "role"), try scope.text("assistant")) and scope.truthy(try scope.get(try scope.get(event, "message"), "errorMessage"))) {
            const state = try scope.get(agent, "_state");
            try scope.set(state, "errorMessage", try scope.get(try scope.get(event, "message"), "errorMessage"));
        }
    } else if (scope.equal(kind, try scope.text("agent_end"))) {
        try scope.set(try scope.get(agent, "_state"), "streamingMessage", c.pi_js_undefined());
    }
}

fn restore(engine: *em.Engine, owner: c.JSValue) !js.Iterator {
    const iterator = try sdk.get(engine, owner, "iterator");
    errdefer engine.freeValue(iterator);
    const next = try sdk.get(engine, owner, "next");
    errdefer engine.freeValue(next);
    const steps_value = try sdk.get(engine, owner, "steps");
    defer engine.freeValue(steps_value);
    var steps: i64 = 0;
    if (c.JS_ToInt64(engine.context, &steps, steps_value) < 0) return js.capture(engine);
    return .{ .engine = engine, .iterator = iterator, .next_function = next, .native_steps = @intCast(steps) };
}

fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    var iterator = try restore(engine, owner);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const listener = (try iterator.next()) orelse return flow.settle(engine, owner, false, c.pi_js_undefined());
    defer engine.freeValue(listener);
    try sdk.put(engine, owner, "steps", c.JS_NewFloat64(engine.context, @floatFromInt(@min(iterator.native_steps, std.math.maxInt(i64)))));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const event = try scope.get(owner, "event");
    const signal = try scope.get(owner, "signal");
    const value = try scope.call(listener, c.pi_js_undefined(), &.{ event, signal });
    try flow.wait(continuation, engine, owner, value, 0);
}

fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) {
        // Abrupt completion in the loop body closes the retained iterator;
        // Source preserves the original listener rejection over close errors.
        var iterator = try restore(engine, owner);
        defer iterator.deinit();
        const previous = engine.captured_exception;
        engine.captured_exception = c.JS_DupValue(engine.context, value);
        iterator.closePreserving();
        if (engine.captured_exception) |captured| engine.freeValue(captured);
        engine.captured_exception = previous;
        return flow.settle(engine, owner, true, value);
    }
    try advance(engine, owner);
}
