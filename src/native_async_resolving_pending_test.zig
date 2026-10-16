//! Prepared negative controls for F06 native-body resolving sites. These are
//! desired terminal assertions, not executed observations or a parity claim.
const std = @import("std");
const em = @import("extensions/engine.zig");
const af = @import("extensions/native_async_function.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;
const Probe = struct {
    engine: *em.Engine,
    target: ?c.JSValue = null, // Borrowed from the test's owned outer Promise.
    armed: bool = true,
    hits: usize = 0,
};
fn injectFatal(context: ?*c.JSContext, promise: c.JSValue, hook_data: ?*anyopaque) void {
    const probe: *Probe = @ptrCast(@alignCast(hook_data.?));
    if (!probe.armed) return;
    if (probe.target) |target| if (!c.JS_IsStrictEqual(context, target, promise)) return;
    probe.armed = false;
    probe.hits += 1;
    _ = probe.engine.throwNativeOutOfMemory();
    c.JS_SetUncatchableError(context, probe.engine.native_allocation_exception.?);
}
fn resolvingHook(context: ?*c.JSContext, kind: c.JSPromiseHookType, promise: c.JSValue, _: c.JSValue, hook_data: ?*anyopaque) callconv(.c) void {
    if (kind == c.JS_PROMISE_HOOK_RESOLVE) injectFatal(context, promise, hook_data);
}
fn rejectingTracker(context: ?*c.JSContext, promise: c.JSValue, _: c.JSValue, handled: bool, hook_data: ?*anyopaque) callconv(.c) void {
    // Public Promise RESOLVE hooks deliberately exclude rejected promises.
    // Rejection uses the actual public host rejection tracker instead.
    if (!handled) injectFatal(context, promise, hook_data);
}
fn rawReturn(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_DupValue(engine.context, args[0]);
}
fn rawThrow(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, args[0])));
}
fn resumed(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    return switch (completion) {
        .start => .{ .awaited = c.JS_DupValue(engine.context, args[0]) },
        .fulfilled => if (c.JS_ToBool(engine.context, roots[0]) == 1)
            .{ .thrown = c.JS_DupValue(engine.context, args[1]) }
        else
            .{ .returned = c.JS_DupValue(engine.context, args[1]) },
        .rejected => .{ .thrown = c.JS_DupValue(engine.context, input) },
    };
}
fn checkReason(engine: *em.Engine, reason: c.JSValue, boundary: u64, probe: *const Probe) !void {
    try std.testing.expectEqual(@as(usize, 1), probe.hits);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))));
    try std.testing.expect(engine.nativeAllocationError(error.JavaScriptException, boundary) == error.OutOfMemory);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn startControl(reject: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const marker = if (reject) try scope.object() else c.JS_NewInt32(engine.context, 7);
    const function = try scope.own(try af.create(engine, "nativeResolvingProbe", 1, if (reject) rawThrow else rawReturn, &.{}));
    var probe: Probe = .{ .engine = engine };
    if (reject) c.JS_SetHostPromiseRejectionTracker(engine.runtime, rejectingTracker, &probe) else c.JS_SetPromiseHook(engine.runtime, resolvingHook, &probe);
    defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    defer c.JS_SetPromiseHook(engine.runtime, null, null);
    const boundary = engine.native_allocation_generation;
    var args = [_]c.JSValue{marker};
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
    defer engine.freeValue(result);
    // Capture/own the raw reason before assertions, including the current
    // negative outcome where a settled Promise escaped with a pending error.
    const reason = c.JS_GetException(engine.context);
    defer engine.freeValue(reason);
    try checkReason(engine, reason, boundary, &probe);
    try std.testing.expect(c.JS_IsException(result));
}
fn resumedControl(reject: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const marker = if (reject) try scope.object() else c.JS_NewInt32(engine.context, 7);
    const ready = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, false, c.pi_js_undefined())));
    const function = try scope.own(try af.createResumable(engine, "nativeResumedResolvingProbe", 2, resumed, &.{c.pi_js_bool(engine.context, @intFromBool(reject))}));
    var args = [_]c.JSValue{ ready, marker };
    const pending = c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args);
    defer engine.freeValue(pending);
    try std.testing.expect(!c.JS_IsException(pending));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    var probe: Probe = .{ .engine = engine, .target = pending };
    if (reject) c.JS_SetHostPromiseRejectionTracker(engine.runtime, rejectingTracker, &probe) else c.JS_SetPromiseHook(engine.runtime, resolvingHook, &probe);
    defer c.JS_SetHostPromiseRejectionTracker(engine.runtime, null, null);
    defer c.JS_SetPromiseHook(engine.runtime, null, null);
    const boundary = engine.native_allocation_generation;
    var job_context: ?*c.JSContext = null;
    const status = c.JS_ExecutePendingJob(engine.runtime, &job_context);
    const reason = c.JS_GetException(job_context orelse engine.context);
    defer engine.freeValue(reason);
    try checkReason(engine, reason, boundary, &probe);
    // F06 is expected to return +1 here despite the hook's pending fatal.
    // The required host delivery is -1, independent of the settled Promise.
    try std.testing.expect(status < 0);
}
test "native AF resolving pending START return hook must deliver exact fatal exception" {
    try startControl(false);
}
test "native AF resolving pending resumed return hook must fail the actual job" {
    try resumedControl(false);
}
test "native AF resolving pending START rejection tracker must deliver exact fatal exception" {
    try startControl(true);
}
test "native AF resolving pending resumed rejection tracker must fail the actual job" {
    try resumedControl(true);
}
