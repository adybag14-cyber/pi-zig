//! Ordered AsyncIterator records and awaited abrupt close for the pinned SDK
//! producer bodies. These helpers do not add suspension points of their own.
const v = @import("native_ai_provider_values.zig");
const gen = @import("native_async_generator.zig");
const flow = @import("native_agent_async.zig");
const Scope = v.Scope;
const c = v.c;
pub fn state(scope: *Scope) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, c.pi_js_null())));
}
pub fn begin(scope: *Scope, owner: c.JSValue, iterable: c.JSValue) !void {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetAsyncIteratorSymbol(scope.engine.context)));
    const method = try scope.own(try v.js.getKey(scope.engine, iterable, symbol));
    const iterator = try scope.call(method, iterable, &.{});
    if (!c.JS_IsObject(iterator)) return v.js.typeError(scope.engine, "Async iterator is not an object");
    try scope.put(owner, "iterator", iterator);
    // GetAsyncIterator retains nextMethod once, rather than looking it up per
    // advance. Caller accessors must not gain extra evaluations.
    try scope.put(owner, "nextMethod", try scope.get(iterator, "next"));
    try scope.put(owner, "iteratorEntered", c.pi_js_bool(scope.engine.context, 1));
}
pub fn next(scope: *Scope, owner: c.JSValue) !gen.Action {
    try scope.put(owner, "awaitingNext", c.pi_js_bool(scope.engine.context, 1));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, try scope.call(try scope.get(owner, "nextMethod"), try scope.get(owner, "iterator"), &.{})) };
}
pub fn validate(scope: *Scope, result: c.JSValue) !void {
    if (!c.JS_IsObject(result)) return v.js.typeError(scope.engine, "Iterator result is not an object");
}
fn original(scope: *Scope, owner: c.JSValue) !gen.Action {
    const thrown = scope.truthy(try scope.get(owner, "closeThrown"));
    const value = c.JS_DupValue(scope.engine.context, try scope.get(owner, "closeInput"));
    return if (thrown) .{ .thrown = value } else .{ .complete = value };
}
pub fn close(scope: *Scope, owner: c.JSValue, input: c.JSValue, thrown: bool) !gen.Action {
    try scope.put(owner, "closeInput", input);
    try scope.put(owner, "closeThrown", c.pi_js_bool(scope.engine.context, @intFromBool(thrown)));
    if (!scope.truthy(try scope.get(owner, "iteratorEntered"))) return original(scope, owner);
    const iterator = try scope.get(owner, "iterator");
    const method = try scope.get(iterator, "return");
    if (v.nullish(method)) return original(scope, owner);
    try scope.put(owner, "closing", c.pi_js_bool(scope.engine.context, 1));
    const pending = scope.call(method, iterator, &.{}) catch |err| {
        if (err != error.JavaScriptException or !thrown) return err;
        const ignored = flow.reason(scope.engine, err);
        scope.engine.freeValue(ignored);
        if (scope.engine.captured_exception) |captured| {
            scope.engine.captured_exception = null;
            scope.engine.freeValue(captured);
        }
        return original(scope, owner);
    };
    return .{ .awaited = c.JS_DupValue(scope.engine.context, pending) };
}
pub fn closed(scope: *Scope, owner: c.JSValue, completion: gen.Completion, input: c.JSValue) !?gen.Action {
    if (!scope.truthy(try scope.get(owner, "closing"))) return null;
    if (completion == .rejected and !scope.truthy(try scope.get(owner, "closeThrown"))) return .{ .thrown = c.JS_DupValue(scope.engine.context, input) };
    if (completion == .fulfilled and !c.JS_IsObject(input) and !scope.truthy(try scope.get(owner, "closeThrown"))) return v.js.typeError(scope.engine, "Async iterator return result is not an object");
    return try original(scope, owner);
}
