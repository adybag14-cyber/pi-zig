//! Prepared UNRUN controls. Actual children/imports come from the real frontend
//! owner. No fake child, stream, event emitter, wait or completed graph is made.
const std = @import("std");
const x = @import("extensions/native_sdk_exec_values.zig");
const wait = @import("extensions/native_wait_for_child_process.zig");
const exec = @import("extensions/native_sdk_exec.zig");
const f = @import("extensions/native_node_function.zig");
const c = x.c;
pub fn verifyOrdinaryMetadata(engine: *x.em.Engine) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try wait.create(engine));
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    try std.testing.expect(c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(s.equal(try s.get(function, "name"), try s.text("waitForChildProcess")));
    try std.testing.expect(s.equal(try s.get(function, "length"), c.JS_NewInt32(engine.context, 1)));
}
/// Returns actual pending caller IO. Root must settle the real frontend and
/// prove native actors AND all real OS descendants absent before acceptance.
pub fn startActualCaller(engine: *x.em.Engine, actual_spawn: c.JSValue, real_subject: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try wait.create(engine));
    const namespace = try s.own(try exec.create(engine, .{ .spawn = actual_spawn, .wait_for_child_process = function }));
    const execute = try s.get(namespace, "execCommand");
    const caller = try s.own(try engine.eval(@embedFile("extensions/fixtures/sdk-live-child-waiter-caller.mjs"), "actual-live-waiter-caller.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(engine.context, try s.call(caller, c.pi_js_undefined(), &.{ function, actual_spawn, execute, real_subject }));
}
pub fn verifyAcceptedOriginalRows(engine: *x.em.Engine, actual_rows: c.JSValue, independently_accepted_original_rows: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    const actual = try s.call(stringify, json, &.{actual_rows}); const original = try s.call(stringify, json, &.{independently_accepted_original_rows});
    try std.testing.expect(s.equal(actual, original));
}
fn recordData(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_DefinePropertyValueStr(engine.context, roots[0], "caught", c.JS_DupValue(engine.context, x.arg(args, 0)), c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    return c.pi_js_undefined();
}
/// real_child is a genuine already-spawned live child from the actual backend.
/// This real user error event rejects the wait Promise with historical flagged
/// DATA, then crosses the real .then(undefined).catch handler path. The host
/// owner remains responsible for actual child shutdown/absence on EVERY exit.
pub fn verifyFlaggedDataThroughActualChild(engine: *x.em.Engine, real_child: c.JSValue) !void {
    try std.testing.expect(engine.native_fatal_invocation == null and !c.JS_HasException(engine.context));
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try wait.create(engine));
    const pending = try s.call(function, c.pi_js_undefined(), &.{real_child});
    const box = try s.object(); try s.put(box, "caught", c.pi_js_undefined());
    const handler = try s.own(try f.createArrow(engine, "", 1, recordData, &.{box}));
    const forwarded = try s.invoke(pending, "then", &.{c.pi_js_undefined()});
    const observed = try s.invoke(forwarded, "catch", &.{handler});
    c.JS_PromiseMarkAsHandled(engine.context, observed);
    _ = engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    _ = try s.invoke(real_child, "emit", &.{ try s.text("error"), reason });
    _ = try engine.runReadyJobs(256);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_FULFILLED), c.JS_PromiseState(engine.context, observed));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, try s.get(box, "caught"), reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason)); // DATA bit untouched.
}
fn actualFatal(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return engine.checked(engine.throwNativeOutOfMemoryFatal()); }
/// The actual child's stdout getter is the failed producer inside the live
/// Promise executor, not a stand-in child or fake deferred callback. Use a
/// fresh real owner/realm; teardown must retire its OS child without guest
/// restoration after fatal failure.
pub fn verifyFatalFromActualChildGetter(engine: *x.em.Engine, real_child: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const function = try s.own(try wait.create(engine));
    const getter = try s.own(try f.createMethod(engine, "get stdout", 0, actualFatal, &.{}));
    const atom = c.JS_NewAtom(engine.context, "stdout"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, real_child, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    var args = [_]c.JSValue{real_child};
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception orelse return error.ActualFatalIdentityLost));
}
