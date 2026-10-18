//! c268154c utils/sleep.ts: the actual ordinary, live-Promise producer.
//! Its timer closures retain only their Source lexical bindings.
const x = @import("native_ai_auth_helper_values.zig");
const c = x.c;
const functions = @import("native_node_function.zig");
fn expression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, @call(.auto, body, .{&o} ++ args));
}
fn statement(engine: *x.em.Engine, comptime body: anytype, args: anytype) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, @call(.auto, body, .{&o} ++ args));
}
fn invocation(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    try engine.checkNativeEntry();
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    return x.finishInvocation(engine, &frame, expression(engine, body, args));
}
pub fn create(engine: *x.em.Engine) !c.JSValue { return invocation(engine, createBody, .{}); }
fn createBody(o: *x.Ops) !c.JSValue {
    return functions.create(o.s.engine, "sleep", 2, sleepCall, &.{});
}
fn sleepCall(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return expression(engine, sleepExpression, .{x.arg(args, 0), x.arg(args, 1)});
}
pub fn sleep(engine: *x.em.Engine, ms: c.JSValue, signal: c.JSValue) !c.JSValue {
    return invocation(engine, sleepExpression, .{ms, signal});
}
fn sleepExpression(o: *x.Ops, ms: c.JSValue, signal: c.JSValue) !c.JSValue {
    const promise = try o.global("Promise");
    const executor = try o.own(try functions.createArrow(o.s.engine, "", 2, execute, &.{ms, signal}));
    return c.JS_DupValue(o.s.engine.context, try x.guest.construct(o.s, promise, &.{executor}));
}
fn execute(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, executorBody, .{roots[0], roots[1], x.arg(args, 0), x.arg(args, 1)});
    return c.pi_js_undefined();
}
fn executorBody(o: *x.Ops, ms: c.JSValue, signal: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    // This is inside the actual Promise executor, so ordinary throws become
    // its rejection; the producer never substitutes an intrinsic capability.
    try statement(o.s.engine, throwIfAborted, .{signal});
    const timeout = try o.cell();
    try o.put(timeout, "initialized", c.pi_js_bool(o.s.engine.context, 0));
    const on_abort = try o.own(try functions.createArrow(o.s.engine, "onAbort", 0, abortCall, &.{timeout, reject, signal}));
    const handle = try o.own(try expression(o.s.engine, startTimer, .{ms, signal, on_abort, resolve}));
    try o.put(timeout, "value", handle);
    try o.put(timeout, "initialized", c.pi_js_bool(o.s.engine.context, 1));
    try statement(o.s.engine, addListener, .{signal, on_abort});
}
fn throwIfAborted(o: *x.Ops, signal: c.JSValue) !void { _ = try o.invoke(signal, "throwIfAborted", &.{}); }
fn startTimer(o: *x.Ops, ms: c.JSValue, signal: c.JSValue, on_abort: c.JSValue, resolve: c.JSValue) !c.JSValue {
    const timer = try o.global("setTimeout");
    const elapsed = try o.own(try functions.createArrow(o.s.engine, "", 0, elapsedCall, &.{signal, on_abort, resolve}));
    return c.JS_DupValue(o.s.engine.context, try o.call(timer, c.pi_js_undefined(), &.{elapsed, ms}));
}
fn abortCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, clearTimer, .{roots[0]});
    try statement(engine, rejectReason, .{roots[1], roots[2]});
    return c.pi_js_undefined();
}
fn elapsedCall(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try statement(engine, removeListener, .{roots[0], roots[1]});
    try statement(engine, resolveEmpty, .{roots[2]});
    return c.pi_js_undefined();
}
fn clearTimer(o: *x.Ops, timeout: c.JSValue) !void {
    const clear = try o.global("clearTimeout");
    if (!o.truthy(try o.get(timeout, "initialized"))) {
        const generation = try o.beforeAllocation();
        _ = try o.allocation(c.JS_ThrowReferenceError(o.s.engine.context, "timeout is not initialized"), generation);
        unreachable;
    }
    _ = try o.call(clear, c.pi_js_undefined(), &.{try o.get(timeout, "value")});
}
fn rejectReason(o: *x.Ops, reject: c.JSValue, signal: c.JSValue) !void {
    _ = try o.call(reject, c.pi_js_undefined(), &.{try o.get(signal, "reason")});
}
fn resolveEmpty(o: *x.Ops, resolve: c.JSValue) !void { _ = try o.call(resolve, c.pi_js_undefined(), &.{}); }
fn addListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    const add = try o.get(signal, "addEventListener");
    const name = try o.text("abort");
    const options = try o.object();
    try o.put(options, "once", c.pi_js_bool(o.s.engine.context, 1));
    _ = try o.call(add, signal, &.{name, on_abort, options});
}
fn removeListener(o: *x.Ops, signal: c.JSValue, on_abort: c.JSValue) !void {
    const remove = try o.get(signal, "removeEventListener");
    _ = try o.call(remove, signal, &.{try o.text("abort"), on_abort});
}
