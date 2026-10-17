//! Original settlement notifications and sequential deferred-action ownership.
//! No missing session callback is replaced with a successful stub.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const async_body = @import("native_async_body.zig");
const native = async_body.native;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn install(engine: *em.Engine, exports: c.JSValue) !void {
    const method = try native.createResumable(engine, "_emitAgentSettled", 0, body, &.{});
    defer engine.freeValue(method);
    if (c.JS_DefinePropertyValueStr(engine.context, exports, "_emitAgentSettled", c.JS_DupValue(engine.context, method), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn body(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    const generation = engine.native_allocation_generation;
    return bodyWithSourceCatch(engine, receiver, state, completion, input) catch |err| {
        // This wrapper includes failures raised from the Source catch/finally
        // adaptation itself, not only failures from resumeBody.
        try trustedBoundary(engine, err, generation);
        return async_body.failureSince(engine, err, generation);
    };
}
fn bodyWithSourceCatch(engine: *em.Engine, receiver: c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    const generation = engine.native_allocation_generation;
    return resumeBody(engine, receiver, state, completion, input) catch |err| {
        if (err == error.OutOfMemory) {
            // Execute an entered Source finally without manufacturing a guest
            // reason or allowing a cleanup failure to consume the fatal OOM.
            if (!c.JS_IsUndefined(state.*)) unwindFinally(engine, state.*, null) catch {};
            return error.OutOfMemory;
        }
        if (err != error.JavaScriptException) return async_body.failureSince(engine, err, generation);
        if (engine.captured_exception) |reason| {
            const retained = c.JS_DupValue(engine.context, reason);
            defer engine.freeValue(retained);
            // Mark/rethrow a fresh tagged reason before host classification
            // could erase its identity. Keep that exact value across finally.
            trustedBoundary(engine, err, generation) catch |fatal| {
                if (fatal != error.JavaScriptException) return fatal;
                return fatalFinally(engine, state.*, retained);
            };
            // Historical private tags stay historical, but an already fatal
            // VM reason must not enter the ordinary Source failure path.
            if (c.JS_IsUncatchableError(retained)) return fatalFinally(engine, state.*, retained);
            if (c.JS_IsUndefined(state.*)) return .{ .thrown = c.JS_DupValue(engine.context, retained) };
            try rejectReason(engine, state.*, retained);
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            return async_body.action(&scope, state.*);
        }
        return error.ActualCapturedSettlementExceptionRequired;
    };
}
fn trustedBoundary(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try async_body.rethrowRecognizedAllocation(engine, reason, generation);
    };
}
fn throwFatal(engine: *em.Engine, reason: c.JSValue) !void {
    // Only the recognized fresh or preexisting-uncatchable path calls here.
    c.JS_SetUncatchableError(engine.context, reason);
    _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
    unreachable;
}
fn fatalFinally(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !native.Action {
    const retained = c.JS_DupValue(engine.context, reason);
    defer engine.freeValue(retained);
    if (!c.JS_IsUndefined(owner)) unwindFinally(engine, owner, retained) catch {};
    try throwFatal(engine, retained);
    unreachable;
}
fn resumeBody(engine: *em.Engine, receiver: c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const generation = engine.native_allocation_generation;
        const owner = try async_body.init(&scope, state);
        try scope.put(owner, "agent", receiver);
        try scope.put(owner, "nativeGeneration", try scope.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
        try initialize(engine, owner);
    } else {
        if (completion == .rejected) {
            try async_body.enterRejectedContinuation(engine);
        }
        try advance(engine, state.*, input, completion == .rejected, try async_body.stage(&scope, state.*));
    }
    return async_body.action(&scope, state.*);
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
    try async_body.wait(&scope, owner, result, 0);
}
fn settledEvent(scope: *Scope, owner: c.JSValue) !c.JSValue {
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("agent_settled"));
    try scope.put(event, "aborted", try scope.get(owner, "aborted"));
    return event;
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
        return async_body.resolve(&scope, owner, c.pi_js_undefined());
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
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        return async_body.wait(&scope, owner, result, 1);
    }
    try sdk.put(engine, owner, "actionsTry", c.pi_js_bool(engine.context, 0));
    const receiver = try sdk.get(engine, owner, "agent");
    defer engine.freeValue(receiver);
    const ignored = try js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{});
    engine.freeValue(ignored);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try async_body.resolve(&scope, owner, c.pi_js_undefined());
}
fn unwindFinally(engine: *em.Engine, owner: c.JSValue, reason: ?c.JSValue) !void {
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
            engine.captured_exception = if (reason) |value| c.JS_DupValue(engine.context, value) else null;
            var preserve_fatal_capture = false;
            defer {
                if (preserve_fatal_capture) {
                    // A newly fatal close reason owns the current capture.
                    // Release the saved primary capture instead of replacing it.
                    if (previous) |value| engine.freeValue(value);
                } else {
                    if (engine.captured_exception) |value| engine.freeValue(value);
                    engine.captured_exception = previous;
                }
            }
            const generation = engine.native_allocation_generation;
            iterator.close() catch |err| {
                trustedBoundary(engine, err, generation) catch |fatal| {
                    if (fatal == error.OutOfMemory) {
                        // The deferred-actions finally still attempts idle
                        // resolution; the original direct native union wins.
                        const ignored = js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{}) catch return error.OutOfMemory;
                        engine.freeValue(ignored);
                        return error.OutOfMemory;
                    }
                    if (fatal != error.JavaScriptException) return fatal;
                    preserve_fatal_capture = true;
                    return closeFatalAfterIdle(engine, receiver, engine.captured_exception orelse return error.ActualFatalCloseReasonRequired);
                };
                if (err != error.JavaScriptException) return err;
                if (engine.captured_exception) |failure| if (c.JS_IsUncatchableError(failure)) {
                    preserve_fatal_capture = true;
                    return closeFatalAfterIdle(engine, receiver, failure);
                };
            };
        }
        const ignored = try js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{});
        engine.freeValue(ignored);
    }
}
fn closeFatalAfterIdle(engine: *em.Engine, receiver: c.JSValue, reason: c.JSValue) !void {
    const retained = c.JS_DupValue(engine.context, reason);
    defer engine.freeValue(retained);
    if (js.invoke(engine, receiver, "_resolveIdleWaitIfIdle", &.{})) |ignored| {
        engine.freeValue(ignored);
    } else |_| {}
    try throwFatal(engine, retained);
}
fn rejectReason(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    try unwindFinally(engine, owner, reason);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try async_body.reject(&scope, owner, reason);
}
