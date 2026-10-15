//! Original AuthStorage.inMemory and its serialized in-memory backend.
//! The AuthStorage orchestration remains the shared actual native binding.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const temp = @import("native_sdk_prompt_scope.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn install(engine: *em.Engine, auth_storage: c.JSValue) !void {
    var roots = [_]c.JSValue{auth_storage};
    try js.define(engine, auth_storage, "inMemory", try engine.checked(c.JS_NewCFunctionData2(engine.context, inMemory, "inMemory", 0, 0, roots.len, &roots)));
}
fn inMemory(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return memoryValue(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn memoryValue(engine: *em.Engine, auth_storage: c.JSValue, data: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const backend = try scope.own(try createBackend(engine));
    const state = try scope.get(backend, "nativeMemoryState");
    const json = try scope.invoke(try scope.global("JSON"), "stringify", &.{ if (c.JS_IsUndefined(data)) try scope.object() else data, c.pi_js_null(), c.JS_NewInt32(engine.context, 2) });
    try scope.put(state, "value", json);
    return js.invoke(engine, auth_storage, "fromStorage", &.{backend});
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
pub fn createBackend(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    const promise = try scope.own(try engine.checked(c.JS_PiPromiseResolve(engine.context, c.pi_js_undefined())));
    try scope.put(state, "asyncChain", promise);
    try scope.put(state, "noop", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, noop, "", 0))));
    const result = try scope.object();
    // The private state is non-enumerable, solely to initialize the real
    // backend for the convenience wrapper; it is never a public storage API.
    if (c.JS_DefinePropertyValueStr(engine.context, result, "nativeMemoryState", c.JS_DupValue(engine.context, state), 0) < 0) return js.capture(engine);
    inline for (.{ "withLock", "withLockAsync" }, 0..) |name, i| {
        var roots = [_]c.JSValue{state};
        try scope.put(result, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, lock, name, 1, @intCast(i), roots.len, &roots))));
    }
    return c.JS_DupValue(engine.context, result);
}
fn lock(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return (if (magic == 0) sync(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) else asyncLock(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined())) catch |err| sdk.fail(engine, err);
}
fn update(scope: *Scope, state: c.JSValue, response: c.JSValue) !c.JSValue {
    const result = try scope.get(response, "result");
    const next = try scope.get(response, "next");
    if (!c.JS_IsUndefined(next)) try scope.put(state, "value", next);
    return result;
}
fn sync(engine: *em.Engine, state: c.JSValue, callback: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const response = try scope.call(callback, c.pi_js_undefined(), &.{try scope.get(state, "value")});
    return c.JS_DupValue(engine.context, try update(&scope, state, response));
}
fn check(scope: *Scope, owner: c.JSValue) !void {
    const options = try scope.get(owner, "options");
    const signal = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "signal");
    if (!temp.nullish(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
fn asyncLock(engine: *em.Engine, state: c.JSValue, callback: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const previous = try scope.get(state, "asyncChain");
    const pending = try flow.create(engine, state);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    try scope.put(pending.owner, "callback", callback);
    try scope.put(pending.owner, "options", options);
    const observed = try scope.invoke(previous, "catch", &.{try scope.get(state, "noop")});
    try flow.wait(advance, engine, pending.owner, observed, 0);
    try scope.put(state, "asyncChain", try scope.invoke(pending.promise, "catch", &.{try scope.get(state, "noop")}));
    const returned = try race(engine, pending.promise, if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "signal"));
    engine.freeValue(pending.promise);
    return returned;
}
fn advance(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.get(owner, "agent");
    if (stage == 0) {
        try check(&scope, owner);
        const response = try scope.call(try scope.get(owner, "callback"), c.pi_js_undefined(), &.{try scope.get(state, "value")});
        return flow.wait(advance, engine, owner, response, 1);
    }
    // Destructuring precedes the second signal check in Source.
    const result = try scope.get(value, "result");
    const next = try scope.get(value, "next");
    try check(&scope, owner);
    if (!c.JS_IsUndefined(next)) try scope.put(state, "value", next);
    try flow.settle(engine, owner, false, result);
}
fn abortReason(scope: *Scope, signal: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(try scope.get(signal, "reason"))) return scope.get(signal, "reason");
    const reason = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text("The operation was aborted")}));
    try scope.set(reason, "name", try scope.text("AbortError"));
    return reason;
}
fn race(engine: *em.Engine, operation: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.truthy(signal)) return c.JS_DupValue(engine.context, operation);
    const noop_value = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, noop, "", 0)));
    if (scope.truthy(try scope.get(signal, "aborted"))) {
        _ = try scope.invoke(operation, "catch", &.{noop_value});
        return js.invoke(engine, try scope.global("Promise"), "reject", &.{try abortReason(&scope, signal)});
    }
    const pending = try flow.create(engine, signal);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    var roots = [_]c.JSValue{pending.owner};
    const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, onAbort, "onAbort", 0, 0, roots.len, &roots)));
    try scope.put(pending.owner, "listener", listener);
    const options = try scope.object();
    try scope.put(options, "once", c.pi_js_bool(engine.context, 1));
    _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, options });
    try flow.wait(raceDone, engine, pending.owner, operation, 0);
    if (scope.truthy(try scope.get(signal, "aborted"))) try raceDone(engine, pending.owner, try abortReason(&scope, signal), true, 0);
    return pending.promise;
}
fn onAbort(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const reason = abortReason(&scope, scope.get(roots[0], "agent") catch |err| return sdk.fail(engine, err)) catch |err| return sdk.fail(engine, err);
    raceDone(engine, roots[0], reason, true, 0) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn raceDone(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner, "settled"))) return;
    try scope.put(owner, "settled", c.pi_js_bool(engine.context, 1));
    _ = try scope.invoke(try scope.get(owner, "agent"), "removeEventListener", &.{ try scope.text("abort"), try scope.get(owner, "listener") });
    try flow.settle(engine, owner, rejected, value);
}
