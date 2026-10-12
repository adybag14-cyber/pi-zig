//! Actual AgentLoop assistant-response pipeline, using intrinsic async awaits.
//! Caller stream functions feed original event/result semantics; this does not
//! supply a provider or a substitute default stream function.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
extern "c" fn JS_GetAsyncIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const Stage = enum(c_int) { transformed, converted, api_key, response, next, sync_value, started, updated, assigned, result, final_started, final_ended, close, close_sync_value };

pub fn run(engine: *em.Engine, context: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue, stream_function: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    begin(engine, pending.owner, context, config, signal, emit, stream_function) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn begin(engine: *em.Engine, owner: c.JSValue, context: c.JSValue, config: c.JSValue, signal: c.JSValue, emit: c.JSValue, stream: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "context", context }, .{ "config", config }, .{ "signal", signal }, .{ "emit", emit }, .{ "stream", stream } }) |field| try scope.put(owner, field[0], field[1]);
    try scope.put(owner, "partial", c.pi_js_null());
    try scope.put(owner, "added", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "steps", c.JS_NewInt32(engine.context, 0));
    const messages = try scope.get(context, "messages");
    if (scope.truthy(try scope.get(config, "transformContext"))) {
        const transformed = try scope.invoke(config, "transformContext", &.{ messages, signal });
        return wait(engine, owner, transformed, .transformed);
    }
    try convert(engine, owner, messages);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    return flow.wait(continueAwait, engine, owner, value, @intFromEnum(stage));
}
fn convert(engine: *em.Engine, owner: c.JSValue, messages: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending_conversion = try scope.invoke(try scope.get(owner, "config"), "convertToLlm", &.{messages});
    try wait(engine, owner, pending_conversion, .converted);
}
fn converted(engine: *em.Engine, owner: c.JSValue, messages: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // normalizeContext({messages}) creates only this wrapper and preserves the
    // actual converted array identity; no systemPrompt/tools were supplied.
    const normalized = try scope.object();
    try scope.put(normalized, "messages", messages);
    try scope.put(owner, "llmContext", normalized);
    const config = try scope.get(owner, "config");
    if (scope.truthy(try scope.get(config, "getApiKey"))) {
        const get_key = try scope.get(config, "getApiKey");
        const provider = try scope.get(try scope.get(config, "model"), "provider");
        return wait(engine, owner, try scope.call(get_key, config, &.{provider}), .api_key);
    }
    try callStream(engine, owner, c.pi_js_undefined());
}
fn callStream(engine: *em.Engine, owner: c.JSValue, api_key: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const config = try scope.get(owner, "config");
    const key = if (scope.truthy(api_key)) api_key else try scope.get(config, "apiKey");
    const function = try scope.get(owner, "stream");
    const model = try scope.get(config, "model");
    const context = try scope.get(owner, "llmContext");
    const options = try scope.own(try js.spread(engine, config));
    try scope.put(options, "apiKey", key);
    try scope.put(options, "signal", try scope.get(owner, "signal"));
    try wait(engine, owner, try scope.call(function, c.pi_js_undefined(), &.{ model, context, options }), .response);
}
fn response(engine: *em.Engine, owner: c.JSValue, stream: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "response", stream);
    const async_symbol = try scope.own(try engine.checked(JS_GetAsyncIteratorSymbol(engine.context)));
    var method = try scope.own(try js.getKey(engine, stream, async_symbol));
    const synchronous = temp.nullish(method);
    if (synchronous) {
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        method = try scope.own(try js.getKey(engine, stream, symbol));
    }
    const iterator = try scope.call(method, stream, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(engine, "Iterator is not an object");
    try scope.put(owner, "iterator", iterator);
    try scope.put(owner, "next", try scope.get(iterator, "next"));
    try scope.put(owner, "sync", c.pi_js_bool(engine.context, @intFromBool(synchronous)));
    try next(engine, owner);
}
fn next(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
    var steps: i64 = 0;
    if (c.JS_ToInt64(engine.context, &steps, try scope.get(owner, "steps")) < 0) return js.capture(engine);
    steps +|= 1;
    if (engine.cancelled.load(.acquire) or (@mod(steps, 256) == 0 and interrupted: {
        engine.interrupts +|= 1;
        break :interrupted engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
    try scope.put(owner, "steps", c.JS_NewFloat64(engine.context, @floatFromInt(steps)));
    const pending = try scope.call(try scope.get(owner, "next"), try scope.get(owner, "iterator"), &.{});
    if (scope.truthy(try scope.get(owner, "sync"))) return iteration(engine, owner, pending);
    try wait(engine, owner, pending, .next);
}
fn iteration(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsObject(value)) return js.typeError(engine, "Iterator result is not an object");
    const done = try scope.get(value, "done");
    if (scope.truthy(try scope.get(owner, "sync"))) {
        const item = try scope.get(value, "value");
        try scope.put(owner, "iterationDone", done);
        return wait(engine, owner, item, .sync_value);
    }
    if (scope.truthy(done)) return requestResult(engine, owner, false);
    try eventBody(engine, owner, try scope.get(value, "value"));
}
fn eventBody(engine: *em.Engine, owner: c.JSValue, event: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 1));
    const type_value = try scope.get(event, "type");
    if (scope.equal(type_value, try scope.text("start"))) {
        const partial = try scope.get(event, "partial");
        try scope.put(owner, "partial", partial);
        _ = try scope.invoke(try scope.get(try scope.get(owner, "context"), "messages"), "push", &.{partial});
        try scope.put(owner, "added", c.pi_js_bool(engine.context, 1));
        const outgoing = try scope.object();
        try scope.put(outgoing, "type", try scope.text("message_start"));
        try scope.put(outgoing, "message", try scope.own(try js.spread(engine, partial)));
        return emitSink(engine, owner, outgoing, .started);
    }
    inline for (.{ "text_start", "text_delta", "text_end", "thinking_start", "thinking_delta", "thinking_end", "toolcall_start", "toolcall_delta", "toolcall_end" }) |name| {
        if (scope.equal(type_value, try scope.text(name))) {
            if (scope.truthy(try scope.get(owner, "partial"))) {
                const partial = try scope.get(event, "partial");
                try scope.put(owner, "partial", partial);
                try replaceLast(&scope, owner, partial);
                const outgoing = try scope.object();
                try scope.put(outgoing, "type", try scope.text("message_update"));
                try scope.put(outgoing, "assistantMessageEvent", event);
                try scope.put(outgoing, "message", try scope.own(try js.spread(engine, partial)));
                return emitSink(engine, owner, outgoing, .updated);
            }
            return next(engine, owner);
        }
    }
    if (scope.equal(type_value, try scope.text("done")) or scope.equal(type_value, try scope.text("error"))) return requestResult(engine, owner, true);
    try next(engine, owner);
}
fn replaceLast(scope: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    const messages = try scope.get(try scope.get(owner, "context"), "messages");
    const current = try scope.get(try scope.get(owner, "context"), "messages");
    const index = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, try scope.get(current, "length"), c.JS_NewInt32(scope.engine.context, 1))));
    try js.setKey(scope.engine, messages, index, value);
}
fn emitSink(engine: *em.Engine, owner: c.JSValue, event: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const returned = try scope.call(try scope.get(owner, "emit"), c.pi_js_undefined(), &.{event});
    try wait(engine, owner, returned, stage);
}
fn requestResult(engine: *em.Engine, owner: c.JSValue, closing: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "closingResult", c.pi_js_bool(engine.context, @intFromBool(closing)));
    const pending = try resultPromise(engine, owner);
    defer engine.freeValue(pending);
    try wait(engine, owner, pending, .result);
}
fn resultPromise(engine: *em.Engine, outer: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, outer);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    beginResult(engine, pending.owner, outer) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn beginResult(engine: *em.Engine, owner: c.JSValue, outer: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    // The actual async result closure has its own intrinsic Promise and await.
    // Object.assign is captured before response.result() is invoked.
    const object = try scope.global("Object");
    try scope.put(owner, "assignReceiver", object);
    try scope.put(owner, "assign", try scope.get(object, "assign"));
    const pending = try scope.invoke(try scope.get(outer, "response"), "result", &.{});
    try wait(engine, owner, pending, .assigned);
}
fn assigned(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const patch = try scope.object();
    const outer = try scope.get(owner, "agent");
    const reasoning = try scope.get(try scope.get(outer, "config"), "reasoning");
    try scope.put(patch, "thinkingLevel", if (temp.nullish(reasoning)) try scope.text("off") else reasoning);
    const message = try scope.call(try scope.get(owner, "assign"), try scope.get(owner, "assignReceiver"), &.{ value, patch });
    try flow.settle(engine, owner, false, message);
}
fn result(engine: *em.Engine, owner: c.JSValue, message: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "final", message);
    if (scope.truthy(try scope.get(owner, "added"))) {
        try replaceLast(&scope, owner, message);
    } else {
        _ = try scope.invoke(try scope.get(try scope.get(owner, "context"), "messages"), "push", &.{message});
        const outgoing = try scope.object();
        try scope.put(outgoing, "type", try scope.text("message_start"));
        try scope.put(outgoing, "message", try scope.own(try js.spread(engine, message)));
        return emitSink(engine, owner, outgoing, .final_started);
    }
    try emitFinal(engine, owner);
}
fn emitFinal(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const outgoing = try scope.object();
    try scope.put(outgoing, "type", try scope.text("message_end"));
    try scope.put(outgoing, "message", try scope.get(owner, "final"));
    try emitSink(engine, owner, outgoing, .final_ended);
}
fn continueAwait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage_int: c_int) !void {
    const stage: Stage = @enumFromInt(stage_int);
    resumeCore(engine, owner, value, rejected, stage) catch |err| {
        const raw = flow.reason(engine, err);
        defer engine.freeValue(raw);
        try fail(engine, owner, raw);
    };
}
fn resumeCore(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == .close or stage == .close_sync_value) {
        if (scope.truthy(try scope.get(owner, "closeRejected"))) return flow.settle(engine, owner, true, try scope.get(owner, "closeValue"));
        if (rejected) return flow.settle(engine, owner, true, value);
        if (stage == .close and !c.JS_IsObject(value)) return js.typeError(engine, "Iterator return result is not an object");
        return flow.settle(engine, owner, false, try scope.get(owner, "closeValue"));
    }
    if (rejected and stage == .sync_value and !scope.truthy(try scope.get(owner, "iterationDone"))) return closeRejectedSyncValue(engine, owner, value);
    if (rejected) return fail(engine, owner, value);
    switch (stage) {
        .transformed => try convert(engine, owner, value),
        .converted => try converted(engine, owner, value),
        .api_key => try callStream(engine, owner, value),
        .response => try response(engine, owner, value),
        .next => try iteration(engine, owner, value),
        .sync_value => if (scope.truthy(try scope.get(owner, "iterationDone"))) try requestResult(engine, owner, false) else try eventBody(engine, owner, value),
        .started, .updated => try next(engine, owner),
        .assigned => try assigned(engine, owner, value),
        .result => try result(engine, owner, value),
        .final_started => try emitFinal(engine, owner),
        .final_ended => if (scope.truthy(try scope.get(owner, "closingResult"))) try close(engine, owner, try scope.get(owner, "final"), false) else try flow.settle(engine, owner, false, try scope.get(owner, "final")),
        .close, .close_sync_value => unreachable,
    }
}
fn closeRejectedSyncValue(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    // AsyncFromSyncIteratorContinuation closes the underlying synchronous
    // iterator when a nonterminal yielded value rejects. This is a synchronous
    // IteratorClose: do not await or unwrap the return result's value.
    const iterator_value = try sdk.get(engine, owner, "iterator");
    const next_function = sdk.get(engine, owner, "next") catch |err| {
        engine.freeValue(iterator_value);
        return err;
    };
    var iterator: js.Iterator = .{ .engine = engine, .iterator = iterator_value, .next_function = next_function };
    defer iterator.deinit();
    const previous = engine.captured_exception;
    engine.captured_exception = c.JS_DupValue(engine.context, value);
    iterator.closePreserving();
    if (engine.captured_exception) |captured| engine.freeValue(captured);
    engine.captured_exception = previous;
    try flow.settle(engine, owner, true, value);
}
fn fail(engine: *em.Engine, owner: c.JSValue, value: c.JSValue) !void {
    const body = try sdk.get(engine, owner, "body");
    defer engine.freeValue(body);
    if (c.JS_ToBool(engine.context, body) != 0) return close(engine, owner, value, true);
    try flow.settle(engine, owner, true, value);
}
fn close(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    closeCore(engine, owner, value, rejected) catch |err| {
        if (rejected) return flow.settle(engine, owner, true, value);
        return flow.rejectError(engine, owner, err);
    };
}
fn closeCore(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "body", c.pi_js_bool(engine.context, 0));
    try scope.put(owner, "closeValue", value);
    try scope.put(owner, "closeRejected", c.pi_js_bool(engine.context, @intFromBool(rejected)));
    const iterator = try scope.get(owner, "iterator");
    const method = try scope.get(iterator, "return");
    if (temp.nullish(method)) return flow.settle(engine, owner, rejected, value);
    const returned = try scope.call(method, iterator, &.{});
    if (scope.truthy(try scope.get(owner, "sync"))) {
        if (!c.JS_IsObject(returned)) return js.typeError(engine, "Iterator return result is not an object");
        _ = try scope.get(returned, "done");
        return wait(engine, owner, try scope.get(returned, "value"), .close_sync_value);
    }
    try wait(engine, owner, returned, .close);
}
