//! Models chat/deferred services: native async auth setup and event forwarding.
//! The public stream is returned synchronously and owns GC-visible continuations.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const models = @import("native_models.zig");
const c = em.c;
const Action = enum(c_int) { stream, complete, streamSimple, completeSimple, streamDeferred, fetchDeferred, cancelDeferred };
const Stage = enum(c_int) { prepared, source, next, sync_value, result, cancelled };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn intrinsic(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    const cache = try scope.get(try scope.get(state, "store"), "cache");
    return .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
}
fn wait(scope: *Scope, state: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsic(scope, state);
    return scope.own(try awaiting.continueWith(advance, scope.engine, &captured, state, value, @intFromEnum(stage)));
}
pub fn install(engine: *em.Engine, instance: c.JSValue, store: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var data = [_]c.JSValue{store};
    inline for (std.meta.fields(Action)) |field| try scope.put(instance, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, 3, field.value, data.len, &data))));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const action: Action = @enumFromInt(raw);
    return invoke(engine, data[0], action, args[0..@intCast(argc)]) catch |err| switch (action) {
        .stream, .streamSimple, .streamDeferred => @import("native_durable.zig").reject(engine, err),
        else => @import("native_durable.zig").rejectedPromise(engine, err),
    };
}
fn normalize(scope: *Scope, context: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_ai_transcript_context.zig").normalize(scope.engine, context));
}
fn invoke(engine: *em.Engine, store: c.JSValue, action: Action, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = if (args.len > 0) args[0] else c.pi_js_undefined();
    const input = if (args.len > 1) args[1] else c.pi_js_undefined();
    const options = if (args.len > 2) args[2] else c.pi_js_undefined();
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "model", model);
    try scope.put(state, "options", options);
    const deferred = action == .streamDeferred or action == .fetchDeferred or action == .cancelDeferred;
    try scope.put(state, "input", if (deferred) input else try normalize(&scope, input));
    try scope.put(state, "method", try scope.text(switch (action) {
        .stream, .complete => "stream",
        .streamSimple, .completeSimple => "streamSimple",
        .streamDeferred, .fetchDeferred => "fetchDeferred",
        .cancelDeferred => "cancelDeferred",
    }));
    try scope.put(state, "cancel", c.pi_js_bool(engine.context, @intFromBool(action == .cancelDeferred)));
    if (action != .cancelDeferred) {
        const exports = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeModelsStreamUnavailable;
        const constructor = try scope.get(exports, "AssistantMessageEventStream");
        try scope.put(state, "startedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
        const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
        try scope.put(state, "outer", outer);
    }
    const pending = setup(&scope, state) catch |err| {
        if (err != error.JavaScriptException or engine.captured_exception == null) return err;
        // An async setup failure is observed after the synchronous stream return.
        const reason = engine.captured_exception.?;
        const rejected_setup = try scope.own(try rejection(engine, reason));
        _ = try wait(&scope, state, rejected_setup, .prepared);
        if (action == .cancelDeferred) return c.JS_DupValue(engine.context, rejected_setup);
        const outer = try scope.get(state, "outer");
        return if (action == .complete or action == .completeSimple or action == .fetchDeferred) c.JS_DupValue(engine.context, try scope.invoke(outer, "result", &.{})) else c.JS_DupValue(engine.context, outer);
    };
    const observed = try wait(&scope, state, pending, .prepared);
    if (action == .cancelDeferred) return c.JS_DupValue(engine.context, observed);
    const outer = try scope.get(state, "outer");
    return if (action == .complete or action == .completeSimple or action == .fetchDeferred) c.JS_DupValue(engine.context, try scope.invoke(outer, "result", &.{})) else c.JS_DupValue(engine.context, outer);
}
fn rejection(engine: *em.Engine, reason: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer for (functions) |value| engine.freeValue(value);
    var args = [_]c.JSValue{reason};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[1], c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return promise;
}
fn raise(scope: *Scope, state: c.JSValue, code: []const u8, message: c.JSValue) anyerror {
    const text = scope.engine.toString(message) catch |err| return err;
    defer scope.engine.gpa.free(text);
    const reason = scope.own(models.fromCause(scope.engine, scope.get(state, "store") catch |err| return err, code, text, c.pi_js_undefined()) catch |err| return err) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason))) catch |err| return err;
    unreachable;
}
fn setup(scope: *Scope, state: c.JSValue) !c.JSValue {
    const model = try scope.get(state, "model");
    var kind = try scope.get(model, "type");
    if (nullish(kind)) kind = try scope.text("chat");
    if (!scope.equal(kind, try scope.text("chat"))) return raise(scope, state, "provider", try scope.concat(try scope.concat(try scope.concat(try scope.text("Model "), try scope.get(model, "provider")), try scope.text("/")), try scope.concat(try scope.get(model, "id"), try scope.text(" is not a chat model"))));
    const provider = try scope.own(try models.query(scope.engine, try scope.get(state, "store"), .getProvider, &.{try scope.get(model, "provider")}));
    if (c.JS_IsUndefined(provider)) return raise(scope, state, "provider", try scope.concat(try scope.text("Unknown provider: "), try scope.get(model, "provider")));
    try scope.put(state, "provider", provider);
    const method = try scope.get(state, "method");
    if (scope.equal(method, try scope.text("fetchDeferred")) and !scope.truthy(try scope.get(provider, "fetchDeferred"))) return raise(scope, state, "provider", try scope.concat(try scope.concat(try scope.text("Provider "), try scope.get(model, "provider")), try scope.text(" does not support deferred responses")));
    if (scope.equal(method, try scope.text("cancelDeferred")) and !scope.truthy(try scope.get(provider, "cancelDeferred"))) return raise(scope, state, "provider", try scope.concat(try scope.concat(try scope.text("Provider "), try scope.get(model, "provider")), try scope.text(" does not support deferred responses")));
    return scope.own(try @import("native_models_typed.zig").applyAuth(scope.engine, try scope.get(state, "store"), model, try scope.get(state, "options")));
}
fn failed(scope: *Scope, state: c.JSValue, reason: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(state, "cancel"))) return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason)));
    const model = try scope.get(state, "model");
    const message = try scope.object();
    try scope.put(message, "role", try scope.text("assistant"));
    try scope.put(message, "content", try scope.array());
    inline for (.{ "api", "provider" }) |key| try scope.put(message, key, try scope.get(model, key));
    try scope.put(message, "model", try scope.get(model, "id"));
    const usage = try scope.object();
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |key| try scope.put(usage, key, c.JS_NewInt32(scope.engine.context, 0));
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |key| try scope.put(cost, key, c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(usage, "cost", cost);
    try scope.put(message, "usage", usage);
    try scope.put(message, "stopReason", try scope.text("error"));
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return js.capture(scope.engine);
    try scope.put(message, "errorMessage", if (instance == 1) try scope.get(reason, "message") else try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{reason}));
    try scope.put(message, "timestamp", try scope.get(state, "startedAt"));
    const event = try scope.object();
    try scope.put(event, "type", try scope.text("error"));
    try scope.put(event, "reason", try scope.text("error"));
    try scope.put(event, "error", message);
    const outer = try scope.get(state, "outer");
    _ = try scope.invoke(outer, "push", &.{event});
    _ = try scope.invoke(outer, "end", &.{message});
    return c.pi_js_undefined();
}
fn next(scope: *Scope, state: c.JSValue) !c.JSValue {
    const iterator = try scope.get(state, "iterator");
    return c.JS_DupValue(scope.engine.context, try wait(scope, state, try scope.invoke(iterator, "next", &.{}), .next));
}
fn advance(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    return advanceInner(engine, state, value, rejected, @enumFromInt(raw)) catch |err| {
        if (err != error.JavaScriptException or engine.captured_exception == null) {
            retireHostFailure(engine, state, err);
            return err;
        }
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        return failed(&scope, state, engine.captured_exception.?) catch |terminal_error| {
            retireHostFailure(engine, state, terminal_error);
            return terminal_error;
        };
    };
}
fn advanceInner(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (rejected) return failed(&scope, state, value);
    switch (stage) {
        .prepared => {
            const provider = try scope.get(state, "provider");
            const method = try scope.own(try js.getKey(engine, provider, try scope.get(state, "method")));
            const source = try scope.call(method, provider, &.{ try scope.get(value, "requestModel"), try scope.get(state, "input"), try scope.get(value, "requestOptions") });
            if (scope.truthy(try scope.get(state, "cancel"))) return c.JS_DupValue(engine.context, try wait(&scope, state, source, .cancelled));
            return c.JS_DupValue(engine.context, try wait(&scope, state, source, .source));
        },
        .source => {
            const source = value;
            try scope.put(state, "source", source);
            const symbol = try scope.global("Symbol");
            const async_method = try scope.own(try js.getKey(engine, source, try scope.get(symbol, "asyncIterator")));
            const sync = nullish(async_method);
            const method_iterator = if (sync) try scope.own(try js.getKey(engine, source, try scope.get(symbol, "iterator"))) else async_method;
            try scope.put(state, "sync", c.pi_js_bool(engine.context, @intFromBool(sync)));
            try scope.put(state, "iterator", try scope.call(method_iterator, source, &.{}));
            return next(&scope, state);
        },
        .next => {
            if (scope.truthy(try scope.get(value, "done"))) {
                const source = try scope.get(state, "source");
                const result = try scope.get(source, "result");
                if (c.JS_IsFunction(engine.context, result)) return c.JS_DupValue(engine.context, try wait(&scope, state, try scope.call(result, source, &.{}), .result));
                _ = try scope.invoke(try scope.get(state, "outer"), "end", &.{c.pi_js_undefined()});
                return c.pi_js_undefined();
            }
            const event = try scope.get(value, "value");
            if (scope.truthy(try scope.get(state, "sync"))) return c.JS_DupValue(engine.context, try wait(&scope, state, event, .sync_value));
            _ = try scope.invoke(try scope.get(state, "outer"), "push", &.{event});
            return next(&scope, state);
        },
        .sync_value => {
            _ = try scope.invoke(try scope.get(state, "outer"), "push", &.{value});
            return next(&scope, state);
        },
        .result => {
            _ = try scope.invoke(try scope.get(state, "outer"), "end", &.{value});
            return c.pi_js_undefined();
        },
        .cancelled => return c.pi_js_undefined(),
    }
}

// Retire a public stream even when a failed host allocation prevents building
// the normal setup-error DTO. Native EventStream rejection needs no host roots.
fn retireHostFailure(engine: *em.Engine, state: c.JSValue, err: anyerror) void {
    const outer = c.JS_GetPropertyStr(engine.context, state, "outer");
    defer engine.freeValue(outer);
    if (!c.JS_IsObject(outer) or c.JS_IsException(outer)) return;
    const reason = if (err == error.JavaScriptException and engine.captured_exception != null)
        c.JS_DupValue(engine.context, engine.captured_exception.?)
    else allocation: {
        _ = engine.throwNativeOutOfMemory();
        break :allocation c.JS_GetException(engine.context);
    };
    defer engine.freeValue(reason);
    @import("native_stream.zig").reject(engine, outer, reason) catch {};
}

/// Source lazyStream used by native Provider factory deferred dispatch. Setup
/// executes now; its promise/exception is forwarded behind a synchronous stream.
pub fn fromSetup(engine: *em.Engine, store: c.JSValue, model: c.JSValue, setup_function: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    try scope.put(state, "store", store);
    try scope.put(state, "model", model);
    try scope.put(state, "startedAt", try scope.invoke(try scope.global("Date"), "now", &.{}));
    const exports = engine.native_module_values.get("@earendil-works/pi-ai") orelse return error.NativeModelsStreamUnavailable;
    const outer = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.get(exports, "AssistantMessageEventStream"), 0, null)));
    try scope.put(state, "outer", outer);
    const pending = scope.call(setup_function, c.pi_js_undefined(), &.{}) catch |err| pending: {
        if (err != error.JavaScriptException or engine.captured_exception == null) return err;
        break :pending try scope.own(try rejection(engine, engine.captured_exception.?));
    };
    _ = try wait(&scope, state, pending, .source);
    return c.JS_DupValue(engine.context, outer);
}
