//! Prepared actual-VM controls for the two reviewed Agent AF fatal boundaries.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const functions = @import("extensions/native_node_function.zig");
const c = em.c;
const executor_fatal = @import("extensions/native_agent_executor_fatal.zig");
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
    for ([_]u64{ 0, std.math.maxInt(u64) }) |generation| {
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
var first_observed: ?c.JSValue = null; // Borrowed; the private holder retains it.
var fault_count: usize = 0;
fn retainedExecutorFault(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const generation = engine.native_allocation_generation;
    const err = executor_fatal.callbackFailure(engine, roots[0], error.OutOfMemory, generation);
    fault_count += 1;
    if (first_observed == null) first_observed = engine.captured_exception;
    return err;
}
fn overwriteDiagnostic(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // A native operation catches its own ordinary error and returns normally.
    // There is no pending event, but the Engine diagnostic slot has changed.
    const reason = try engine.checked(c.JS_NewError(engine.context));
    _ = engine.checked(c.JS_Throw(engine.context, reason)) catch return c.pi_js_undefined();
    unreachable;
}
test "native Agent AF correction retained first executor fatal wins later constructor completions" {
    const bodies = [_][]const u8{
        "super(executor); throw globalThis.ordinaryMarker;",
        "super(executor); overwriteDiagnostic();",
        "super(executor); overwriteDiagnostic(); throw globalThis.ordinaryMarker;",
        "super(executor); executor(()=>{});",
    };
    for (bodies, 0..) |constructor_body, index| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: p.Scope = .{ .engine = engine }; defer s.deinit();
        const holder = try s.own(try executor_fatal.create(engine));
        first_observed = null; fault_count = 0;
        const executor = try s.own(try functions.createArrow(engine, "", 1, retainedExecutorFault, &.{holder}));
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "ordinaryMarker", try s.object());
        try s.put(global, "overwriteDiagnostic", try s.own(try functions.createArrow(engine, "overwriteDiagnostic", 0, overwriteDiagnostic, &.{})));
        const source = try std.fmt.allocPrint(std.testing.allocator, "(class extends Promise {{constructor(executor){{{s}}}}})", .{constructor_body});
        defer std.testing.allocator.free(source);
        const constructor = try s.own(try engine.eval(source, "actual-promise-subclass-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
        try std.testing.expectError(error.JavaScriptException, executor_fatal.construct(&s, constructor, &.{executor}, holder));
        const actual = engine.captured_exception orelse return error.MissingRetainedExecutorFatal;
        try std.testing.expect(first_observed != null and c.JS_IsStrictEqual(engine.context, actual, first_observed.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
        try std.testing.expectEqual(@as(usize, if (index == 3) 2 else 1), fault_count);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
