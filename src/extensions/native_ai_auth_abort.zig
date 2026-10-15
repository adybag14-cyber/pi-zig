//! Actual utils/abort.ts public helpers. Source Promise methods and signal
//! getters stay live, including abandoned-operation rejection observation.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const exports = try s.object();
    try s.put(exports, "operationSignal", try s.own(try functions.create(engine, "operationSignal", 1, operationSignal, &.{})));
    try s.put(exports, "raceWithAbortSignal", try s.own(try functions.create(engine, "raceWithAbortSignal", 2, raceWithAbortSignal, &.{})));
    return c.JS_DupValue(engine.context, exports);
}
fn noop(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
fn operationSignal(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const signal = arg(args, 0);
    if (!v.nullish(signal)) return c.JS_DupValue(engine.context, signal);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try s.get(try s.own(try v.js.builtin(engine, "AbortController", &.{})), "signal"));
}
fn abortReason(s: *Scope, signal: c.JSValue) !c.JSValue {
    if (!c.JS_IsUndefined(try s.get(signal, "reason"))) return s.get(signal, "reason");
    const reason = try s.own(try v.js.builtin(s.engine, "Error", &.{try s.text("The operation was aborted")}));
    try s.set(reason, "name", try s.text("AbortError"));
    return reason;
}
fn raceWithAbortSignal(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const operation = arg(args, 0);
    const signal = arg(args, 1);
    if (s.truthy(try s.get(signal, "aborted"))) {
        _ = try s.invoke(operation, "catch", &.{try s.own(try functions.createArrow(engine, "", 0, noop, &.{}))});
        const promise = try s.global("Promise");
        const reject = try s.get(promise, "reject");
        return c.JS_DupValue(engine.context, try s.call(reject, promise, &.{try abortReason(&s, signal)}));
    }
    const promise = try s.global("Promise");
    const executor = try s.own(try functions.createArrow(engine, "", 2, execute, &.{ operation, signal }));
    return engine.checked(c.JS_CallConstructor(engine.context, promise, 1, @constCast(&[_]c.JSValue{executor})));
}
fn execute(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    try s.put(state, "settled", c.JS_NewBool(engine.context, false));
    try s.put(state, "signal", roots[1]);
    try s.put(state, "resolve", arg(args, 0));
    try s.put(state, "reject", arg(args, 1));
    const on_abort = try s.own(try functions.createArrow(engine, "onAbort", 0, aborted, &.{state}));
    try s.put(state, "onAbort", on_abort);
    const options = try s.object();
    try s.put(options, "once", c.JS_NewBool(engine.context, true));
    _ = try s.invoke(roots[1], "addEventListener", &.{ try s.text("abort"), on_abort, options });
    const then = try s.get(roots[0], "then");
    const fulfilled = try s.own(try functions.createArrow(engine, "", 1, complete, &.{ state, c.JS_NewBool(engine.context, false) }));
    const rejected = try s.own(try functions.createArrow(engine, "", 1, complete, &.{ state, c.JS_NewBool(engine.context, true) }));
    _ = try s.call(then, roots[0], &.{ fulfilled, rejected });
    if (s.truthy(try s.get(roots[1], "aborted"))) _ = try s.call(on_abort, c.pi_js_undefined(), &.{});
    return c.pi_js_undefined();
}
fn cleanup(s: *Scope, state: c.JSValue) !void {
    const signal = try s.get(state, "signal");
    _ = try s.invoke(signal, "removeEventListener", &.{ try s.text("abort"), try s.get(state, "onAbort") });
}
fn aborted(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    if (s.truthy(try s.get(state, "settled"))) return c.pi_js_undefined();
    try s.put(state, "settled", c.JS_NewBool(engine.context, true));
    try cleanup(&s, state);
    const reject = try s.get(state, "reject");
    _ = try s.call(reject, c.pi_js_undefined(), &.{try abortReason(&s, try s.get(state, "signal"))});
    return c.pi_js_undefined();
}
fn complete(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    if (s.truthy(try s.get(state, "settled"))) return c.pi_js_undefined();
    try s.put(state, "settled", c.JS_NewBool(engine.context, true));
    try cleanup(&s, state);
    _ = try s.call(try s.get(state, if (s.truthy(roots[1])) "reject" else "resolve"), c.pi_js_undefined(), &.{arg(args, 0)});
    return c.pi_js_undefined();
}
