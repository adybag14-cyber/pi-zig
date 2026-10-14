//! Original settlement notifications and sequential deferred-action ownership.
//! No missing session callback is replaced with a successful stub.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    const method = try engine.checked(c.JS_NewCFunction(engine.context, start, "_emitAgentSettled", 0));
    defer engine.freeValue(method);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, method, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "_emitAgentSettled", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn start(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, receiver) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, receiver: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner) catch |err| try failOperation(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const warmer = try scope.get(receiver, "_cacheWarmer");
    if (!temp.nullish(warmer)) _ = try scope.invoke(warmer, "onAgentSettled", &.{});
    try scope.set(receiver, "_isAgentRunActive", c.pi_js_bool(engine.context, 0));
    try scope.set(receiver, "_isEmittingAgentSettled", c.pi_js_bool(engine.context, 1));
    try scope.put(owner, "emittingTry", c.pi_js_bool(engine.context, 1));
    try scope.put(owner, "aborted", try scope.get(receiver, "_agentRunAbortRequested"));
    const runner = try scope.get(receiver, "_extensionRunner");
    const emit = try scope.get(runner, "emit");
    const event = try settledEvent(&scope, owner);
    const result = try scope.call(emit, runner, &.{event});
    try flow.wait(continuation, engine, owner, result, 0);
}
fn settledEvent(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("agent_settled"));
    try scope.put(event, "aborted", try scope.get(owner, "aborted"));
    return event;
}
fn continuation(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    advance(engine, owner, value, rejected, stage) catch |err| try failOperation(engine, owner, err);
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return rejectReason(engine, owner, value);
    if (stage != 0) return nextAction(engine, owner);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.get(owner, "agent");
    const emit = try scope.get(receiver, "_emit");
    _ = try scope.call(emit, receiver, &.{try settledEvent(&scope, owner)});
    try scope.put(owner, "emittingTry", c.pi_js_bool(engine.context, 0));
    try scope.set(receiver, "_isEmittingAgentSettled", c.pi_js_bool(engine.context, 0));
    const actions = try scope.invoke(try scope.get(receiver, "_deferredSettledActions"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
    if (!try scope.positive(try scope.get(actions, "length"))) {
        _ = try scope.invoke(receiver, "_resolveIdleWaitIfIdle", &.{});
        return flow.settle(engine, owner, false, c.pi_js_undefined());
    }
    try scope.put(owner, "actionsTry", c.pi_js_bool(engine.context, 1));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, actions, symbol);
    defer iterator.deinit();
    try scope.put(owner, "iterator", iterator.iterator);
    try scope.put(owner, "next", iterator.next_function);
    try nextAction(engine, owner);
}
fn restored(engine: *em.Engine, owner: c.JSValue) !js.Iterator {
    const iterator = try sdk.get(engine, owner, "iterator");
    errdefer engine.freeValue(iterator);
    const next = try sdk.get(engine, owner, "next");
    errdefer engine.freeValue(next);
    const closed = try sdk.get(engine, owner, "iteratorClosed");
    defer engine.freeValue(closed);
    return .{ .engine = engine, .iterator = iterator, .next_function = next, .closed = c.JS_ToBool(engine.context, closed) == 1 };
}
fn nextAction(engine: *em.Engine, owner: c.JSValue) !void {
    var iterator = try restored(engine, owner);
    defer iterator.deinit();
    const action = iterator.next() catch |err| {
        try sdk.put(engine, owner, "iteratorClosed", c.pi_js_bool(engine.context, 1));
        return err;
    };
    if (action) |callback| {
        defer engine.freeValue(callback);
        const result = try js.call(engine, callback, c.pi_js_undefined(), &.{});
        defer engine.freeValue(result);
        return flow.wait(continuation, engine, owner, result, 1);
    }
    try sdk.put(engine, owner, "actionsTry", c.pi_js_bool(engine.context, 0));
    const receiver = try sdk.get(engine, owner, "agent");
    defer engine.freeValue(receiver);
    const ignored = try js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{});
    engine.freeValue(ignored);
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
fn failOperation(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    try rejectReason(engine, owner, reason);
}
fn rejectReason(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    const receiver = try sdk.get(engine, owner, "agent");
    defer engine.freeValue(receiver);
    const emitting = try sdk.get(engine, owner, "emittingTry");
    defer engine.freeValue(emitting);
    if (c.JS_ToBool(engine.context, emitting) == 1) {
        try sdk.put(engine, owner, "emittingTry", c.pi_js_bool(engine.context, 0));
        if (c.JS_SetPropertyStr(engine.context, receiver, "_isEmittingAgentSettled", c.pi_js_bool(engine.context, 0)) < 0) return js.capture(engine);
    }
    const actions = try sdk.get(engine, owner, "actionsTry");
    defer engine.freeValue(actions);
    if (c.JS_ToBool(engine.context, actions) == 1) {
        try sdk.put(engine, owner, "actionsTry", c.pi_js_bool(engine.context, 0));
        const captured_iterator = try sdk.get(engine, owner, "iterator");
        defer engine.freeValue(captured_iterator);
        if (c.JS_IsObject(captured_iterator)) {
            var iterator = try restored(engine, owner);
            defer iterator.deinit();
            const previous = engine.captured_exception;
            engine.captured_exception = c.JS_DupValue(engine.context, reason);
            iterator.closePreserving();
            if (engine.captured_exception) |value| engine.freeValue(value);
            engine.captured_exception = previous;
        }
        const ignored = try js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{});
        engine.freeValue(ignored);
    }
    try flow.settle(engine, owner, true, reason);
}
