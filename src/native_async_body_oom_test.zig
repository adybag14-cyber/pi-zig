//! Regression gates for the shared recorder's wrapped START/resume failure path.
//! These require the reviewed real native AsyncFunction primitive; no source or
//! Promise/branding substitute participates. Prepared, not executed by this lane.
const std = @import("std");
const em = @import("extensions/engine.zig");
const body = @import("extensions/native_async_body.zig");
const af = body.native;
const c = em.c;
fn wrappedStart(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, _: af.Completion, _: c.JSValue) !af.Action {
    return body.failure(engine, error.OutOfMemory);
}
fn wrappedResume(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, completion: af.Completion, _: c.JSValue) !af.Action {
    if (completion == .start) return .{ .awaited = c.pi_js_undefined() };
    return body.failure(engine, error.OutOfMemory);
}
test "shared recorder wrapped START host OOM remains uncatchable, not rejected Promise" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try af.createResumable(engine, "wrappedStartOOM", 0, wrappedStart, &.{});
    defer engine.freeValue(function);
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const failure = c.JS_GetException(engine.context);
    defer engine.freeValue(failure);
    try std.testing.expect(c.JS_IsUncatchableError(failure));
}
test "shared recorder wrapped resumed host OOM escapes actual Await job" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const function = try af.createResumable(engine, "wrappedResumeOOM", 0, wrappedResume, &.{});
    defer engine.freeValue(function);
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null));
    defer engine.freeValue(pending);
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
    var context: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &context) < 0);
    const failure = c.JS_GetException(context orelse engine.context);
    defer engine.freeValue(failure);
    try std.testing.expect(c.JS_IsUncatchableError(failure));
    try std.testing.expectEqual(c.JS_PROMISE_PENDING, c.JS_PromiseState(engine.context, pending));
}
fn guestLookalike(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue, _: *c.JSValue, _: af.Completion, _: c.JSValue) !af.Action {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, args[0]))) catch |err| return body.failure(engine, err);
    unreachable;
}
test "shared recorder guest OOM lookalike preserves raw catchable rejection identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const marker = try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(marker);
    const name = try engine.checked(c.JS_NewString(engine.context, "OutOfMemory"));
    if (c.JS_DefinePropertyValueStr(engine.context, marker, "name", name, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const function = try af.createResumable(engine, "guestLookalike", 1, guestLookalike, &.{});
    defer engine.freeValue(function);
    var args = [_]c.JSValue{marker};
    const pending = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args));
    defer engine.freeValue(pending);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const reason = c.JS_PromiseResult(engine.context, pending);
    defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
}
