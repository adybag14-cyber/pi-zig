//! Prepared source-only native Await queued-callback/GC control.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
const Probe = struct {
    engine: *em.Engine,
    target: c.JSValue, // Borrowed from the test's owned settled input Promise.
    armed: bool = true,
    hits: usize = 0,
};
fn handledTracker(context: ?*c.JSContext, promise: c.JSValue, _: c.JSValue, handled: bool, hook_data: ?*anyopaque) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(hook_data.?));
    if (!handled or !probe.armed or !c.JS_IsStrictEqual(context, promise, probe.target)) return;
    probe.armed = false;
    probe.hits += 1;
    _ = probe.engine.throwNativeOutOfMemory();
    c.JS_SetUncatchableError(context, probe.engine.native_allocation_exception.?);
}
fn awaited(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.JS_DupValue(engine.context, args[0]) };
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var count: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &count, try scope.get(roots[0], "resumes")) < 0) return error.JavaScriptException;
    try scope.set(roots[0], "resumes", c.JS_NewInt32(engine.context, count + 1));
    return if (completion == .rejected) .{ .thrown = c.JS_DupValue(engine.context, input) } else .{ .returned = c.JS_DupValue(engine.context, input) };
}
test "native AF Await inactive queued tracker callback survives GC and never resumes retired roots" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const counter = try scope.object();
    try scope.put(counter, "resumes", c.JS_NewInt32(engine.context, 0));
    const original_rejection = try scope.object();
    const rejected = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, true, original_rejection)));
    const function = try scope.own(try af.createResumable(engine, "nativeAwaitInactiveProbe", 1, awaited, &.{counter}));
    var probe: Probe = .{ .engine = engine, .target = rejected };
    c.JS_SetHostPromiseRejectionTracker(engine.runtime, handledTracker, &probe);
    defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    const boundary = engine.native_allocation_generation;
    var args = [_]c.JSValue{rejected};
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
    defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(usize, 1), probe.hits);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    const after_delivery = engine.native_allocation_generation;
    c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    // The queued resolver owns the inactive async state and its native_ctx.
    // GC must not revive the cleared native_function/state/argv roots.
    c.JS_RunGC(engine.runtime);
    var jobs: usize = 0;
    while (c.JS_IsJobPending(engine.runtime)) {
        if (jobs == 8) return error.NativeAwaitInactiveJobBudget;
        var job_context: ?*c.JSContext = null;
        const status = c.JS_ExecutePendingJob(engine.runtime, &job_context);
        if (status < 0) {
            const unexpected = c.JS_GetException(job_context orelse engine.context);
            _ = try engine.checked(c.JS_Throw(engine.context, unexpected));
        }
        try std.testing.expect(status > 0);
        jobs += 1;
    }
    try std.testing.expect(jobs > 0);
    var count: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &count, try scope.get(counter, "resumes")) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 0), count);
    try std.testing.expectEqual(after_delivery, engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(engine.context));
    c.JS_RunGC(engine.runtime);
    // The same real native function must still resume an active invocation.
    const fulfilled = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())));
    args[0] = fulfilled;
    const healthy = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
    defer engine.freeValue(healthy);
    try std.testing.expect(!c.JS_IsException(healthy));
    const settled = try engine.awaitValue(healthy);
    engine.freeValue(settled);
    if (c.JS_ToInt32(engine.context, &count, try scope.get(counter, "resumes")) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 1), count);
    try std.testing.expectEqual(after_delivery, engine.native_allocation_generation);
}
