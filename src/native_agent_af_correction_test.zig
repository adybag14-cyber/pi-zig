//! Prepared actual-VM controls for the two reviewed Agent AF fatal boundaries.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const functions = @import("extensions/native_node_function.zig");
const c = em.c;
var marked: bool = false;
var observed: ?c.JSValue = null; // Borrowed identity; Engine owns captured reason.
fn executorFault(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (marked) {
        const err = p.callbackFailure(engine, error.OutOfMemory);
        observed = engine.captured_exception;
        return err;
    }
    _ = engine.checked(engine.throwNativeOutOfMemory()) catch |err| { observed = engine.captured_exception; return err; };
    unreachable;
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
test "native Agent AF correction actual Promise executor marked fault escapes exact reason and wrap" {
    for (.{ @as(u64, 0), std.math.maxInt(u64) }) |generation| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: p.Scope = .{ .engine = engine }; defer s.deinit();
        engine.native_allocation_generation = generation; marked = true; observed = null;
        const executor = try s.own(try functions.createArrow(engine, "", 1, executorFault, &.{}));
        const constructor = try p.global(&s, "Promise");
        try std.testing.expectError(error.JavaScriptException, p.construct(&s, constructor, &.{executor}));
        const actual = engine.captured_exception orelse return error.MissingActualExecutorFault;
        try std.testing.expect(observed != null and c.JS_IsStrictEqual(engine.context, actual, observed.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
    }
}
test "native Agent AF correction successful constructor ignores catchable fresh historical and lookalike data" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    marked = false; observed = null;
    const executor = try s.own(try functions.createArrow(engine, "", 1, executorFault, &.{}));
    const constructor = try p.global(&s, "Promise");
    _ = try p.construct(&s, constructor, &.{executor});
    const fresh = engine.captured_exception orelse return error.MissingCatchableExecutorFault;
    try std.testing.expect(observed != null and c.JS_IsStrictEqual(engine.context, fresh, observed.?));
    try std.testing.expect(!c.JS_IsUncatchableError(fresh) and c.pi_js_native_allocation_error_generation(fresh) != 0);
    const good = try s.own(try functions.createArrow(engine, "", 1, noop, &.{}));
    c.JS_SetUncatchableError(engine.context, fresh); // Historical data; no pending event.
    _ = try p.construct(&s, constructor, &.{good});
    const lookalike = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, lookalike);
    try std.testing.expect(c.JS_IsUncatchableError(lookalike));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(lookalike) == 0);
    if (engine.captured_exception) |old| engine.freeValue(old);
    engine.captured_exception = c.JS_DupValue(engine.context, lookalike);
    _ = try p.construct(&s, constructor, &.{good});
    try std.testing.expect(c.pi_js_native_allocation_error_generation(lookalike) == 0);
}
fn cancelNow(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    em.Engine.fromContext(context.?).cancelled.store(true, .release);
    return c.pi_js_undefined();
}
test "native Agent AF correction event iterator cancellation remains host fatal before next call" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/abort_signal.zig").install(engine);
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "markIteratorCanceled", try s.own(try engine.checked(c.JS_NewCFunction(engine.context, cancelNow, "markIteratorCanceled", 0))));
    const receiver = try s.own(try engine.eval("({_state:{},activeRun:{abortController:new AbortController()},listeners:{[Symbol.iterator](){return{get next(){markIteratorCanceled();return function(){throw Error('unexpected step')}}}}}})", "actual-event-interrupt-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    const event = try s.object(); try s.put(event, "type", try s.text("owned"));
    const function = try s.own(try @import("extensions/native_agent_events_async.zig").create(engine));
    var args = [_]c.JSValue{event};
    const result = c.JS_Call(engine.context, function, receiver, args.len, &args);
    engine.cancelled.store(false, .release);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result) and c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception orelse return error.MissingActualInterruptReason));
}
