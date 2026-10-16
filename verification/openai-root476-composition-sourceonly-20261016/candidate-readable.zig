//! Actual OpenAI6.40 ReadableStreamToAsyncIterable shim. The fallback's two
//! async methods own genuine AF Await boundaries; existing async iterables pass
//! through unchanged, preserving their live iterator protocol.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const af = @import("native_async_function.zig");
const body = @import("native_async_body.zig");
pub fn deferred(scope: *Scope, response: c.JSValue, controller: c.JSValue) anyerror!c.JSValue {
    const result = try scope.object();
    const Adapter = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            if (!row.truthy(try row.get(roots[0], "body"))) {
                _ = try row.invoke(roots[1], "abort", &.{});
                if (!c.JS_IsUndefined(try row.global("navigator")) and try v.eq(&row, try row.get(try row.global("navigator"), "product"), "ReactNative")) return v.errorText(&row, try row.text("The default react-native fetch implementation does not support streaming. Please use expo/fetch: https://docs.expo.dev/versions/latest/sdk/expo/#expofetch-api"));
                return v.errorText(&row, try row.text("Attempted to iterate over a response with no body"));
            }
            const iterable = try create(&row, try row.get(roots[0], "body"));
            const symbol = try row.own(try engine.checked(c.JS_GetAsyncIteratorSymbol(engine.context)));
            return c.JS_DupValue(engine.context, try row.call(try row.own(try v.js.getKey(engine, iterable, symbol)), iterable, &.{}));
        }
    };
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
    try v.js.setKey(scope.engine, result, symbol, try scope.own(try @import("native_node_function.zig").createMethod(scope.engine, "[Symbol.asyncIterator]", 0, Adapter.call, &.{ response, controller })));
    return result;
}
pub fn create(scope: *Scope, stream: c.JSValue) anyerror!c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
    if (scope.truthy(try scope.own(try v.js.getKey(scope.engine, stream, symbol)))) return stream;
    const reader = try scope.invoke(stream, "getReader", &.{});
    const result = try scope.object();
    try scope.put(result, "next", try scope.own(try af.createResumable(scope.engine, "next", 0, next, &.{reader})));
    try scope.put(result, "return", try scope.own(try af.createResumable(scope.engine, "return", 0, close, &.{reader})));
    const Self = struct {
        fn call(engine: *v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.JS_DupValue(engine.context, receiver);
        }
    };
    try v.js.setKey(scope.engine, result, symbol, try scope.own(try @import("native_node_function.zig").createMethod(scope.engine, "[Symbol.asyncIterator]", 0, Self.call, &.{})));
    return result;
}
fn next(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const reader = roots[0];
    if (completion == .start) {
        const generation = engine.native_allocation_generation;
        af.replaceState(engine, slot, try engine.checked(c.JS_NewBigUint64(engine.context, generation)));
        const pending = scope.invoke(reader, "read", &.{}) catch |err| {
            return readFailure(&scope, reader, err, generation);
        };
        return .{ .awaited = c.JS_DupValue(engine.context, pending) };
    }
    if (completion == .rejected) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, slot.*) < 0) return v.js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, generation);
        try releaseAfterFailure(&scope, reader);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    const generation = engine.native_allocation_generation;
    return fulfilledNext(&scope, reader, input) catch |err| {
        return readFailure(&scope, reader, err, generation);
    };
}
fn readFailure(scope: *Scope, reader: c.JSValue, err: anyerror, generation: u64) anyerror!af.Action {
    try escapeFatal(scope, err, generation);
    const failure = try body.failure(scope.engine, err);
    errdefer switch (failure) { inline else => |value| scope.engine.freeValue(value) };
    // Source catches read, the done getter and normal-path releaseLock.
    // Keep the original owned reason while catch cleanup may replace it.
    if (scope.engine.captured_exception) |captured| {
        scope.engine.captured_exception = null;
        scope.engine.freeValue(captured);
    }
    try releaseAfterFailure(scope, reader);
    return failure;
}
fn releaseAfterFailure(scope: *Scope, reader: c.JSValue) anyerror!void {
    const generation = scope.engine.native_allocation_generation;
    _ = scope.invoke(reader, "releaseLock", &.{}) catch |err| {
        try escapeFatal(scope, err, generation);
        return err;
    };
}
fn escapeFatal(scope: *Scope, err: anyerror, generation: u64) anyerror!void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (scope.engine.captured_exception) |reason| {
        try body.rethrowRecognizedAllocation(scope.engine, reason, generation);
        if (c.JS_IsUncatchableError(reason)) return err;
    };
}
fn fulfilledNext(scope: *Scope, reader: c.JSValue, input: c.JSValue) anyerror!af.Action {
    if (scope.truthy(try v.optional(scope, input, "done"))) _ = try scope.invoke(reader, "releaseLock", &.{});
    return .{ .returned = c.JS_DupValue(scope.engine.context, input) };
}
fn close(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const generation = engine.native_allocation_generation;
        af.replaceState(engine, slot, try engine.checked(c.JS_NewBigUint64(engine.context, generation)));
        const pending = scope.invoke(roots[0], "cancel", &.{}) catch |err| {
            try escapeFatal(&scope, err, generation);
            return err;
        };
        try releaseAfterFailure(&scope, roots[0]);
        return .{ .awaited = c.JS_DupValue(engine.context, pending) };
    }
    if (completion == .rejected) {
        var generation: u64 = 0;
        if (c.JS_ToBigUint64(engine.context, &generation, slot.*) < 0) return v.js.capture(engine);
        try body.rethrowRecognizedAllocation(engine, input, generation);
        return .{ .thrown = c.JS_DupValue(engine.context, input) };
    }
    const result = try scope.object();
    try scope.put(result, "done", c.JS_NewBool(engine.context, true));
    try scope.put(result, "value", c.pi_js_undefined());
    return .{ .returned = c.JS_DupValue(engine.context, result) };
}
