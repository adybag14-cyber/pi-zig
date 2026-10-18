//! Prepared only: real child/transport bindings and owned command inputs are
//! supplied by the actual frontend owner. No process or wait graph is faked.
const std = @import("std");
const x = @import("extensions/native_sdk_exec_values.zig");
const subject = @import("extensions/native_sdk_exec.zig");
const fatal = @import("extensions/native_sdk_exec_fatal.zig");
const f = @import("extensions/native_node_function.zig");
const c = x.c;
pub const Inputs = subject.Inputs;
pub fn verifyActualAsyncMetadata(engine: *x.em.Engine, inputs: Inputs) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const namespace = try s.own(try subject.create(engine, inputs));
    const function = try s.get(namespace, "execCommand");
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(s.equal(try s.get(function, "length"), c.JS_NewInt32(engine.context, 4)));
    try std.testing.expect(s.equal(try s.get(function, "name"), try s.text("execCommand")));
}
/// Returns the actual pending observation Promise. Root's genuine owner must
/// pump/settle the real frontend and prove all descendants/leases retired.
/// real_subject={executable,child,cwd,missing}, all exact owned command paths.
pub fn startActualCaller(engine: *x.em.Engine, inputs: Inputs, real_subject: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const namespace = try s.own(try subject.create(engine, inputs));
    const function = try s.get(namespace, "execCommand");
    const caller = try s.own(try engine.eval(@embedFile("extensions/fixtures/sdk-exec-command-caller.mjs"), "actual-core-exec-caller.js", c.JS_EVAL_TYPE_GLOBAL));
    return c.JS_DupValue(engine.context, try s.call(caller, c.pi_js_undefined(), &.{ function, real_subject }));
}
pub fn verifyAcceptedOriginalRows(engine: *x.em.Engine, actual_rows: c.JSValue, independently_accepted_original_rows: c.JSValue) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const json = try s.global("JSON"); const stringify = try s.get(json, "stringify");
    const observed = try s.call(stringify, json, &.{actual_rows});
    const original = try s.call(stringify, json, &.{independently_accepted_original_rows});
    try std.testing.expect(s.equal(observed, original));
}
pub fn verifyActualPendingBeforeExecEntry(engine: *x.em.Engine, inputs: Inputs) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit();
    const namespace = try s.own(try subject.create(engine, inputs)); const function = try s.get(namespace, "execCommand");
    const reason = try s.object();
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const current = c.JS_GetException(engine.context); defer engine.freeValue(current);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, current));
}
fn actualExecutorFatal(engine: *x.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = engine.throwNativeOutOfMemoryFatal();
    fatal.record(roots[0], &invocation);
    return engine.checked(engine.leaveNativeInvocation(&invocation, result));
}
/// Exercises the actual holder with the genuine intrinsic Promise and a real
/// native allocation producer. This unit creates no child and substitutes no
/// child/wait implementation; the complete exec IO cases are separate above.
pub fn verifyActualExecutorFatalSurvivesPromiseConstruction(engine: *x.em.Engine) !void {
    var s: x.Scope = .{ .engine = engine }; defer s.deinit(); var o: x.Ops = .{ .s = &s };
    const holder = try fatal.create(&o); const constructor = try o.global("Promise");
    const executor = try o.own(try f.createArrow(engine, "", 1, actualExecutorFatal, &.{holder}));
    if (fatal.construct(&o, constructor, executor, holder)) |_| return error.ActualExecutorFatalWasSwallowed
    else |err| try std.testing.expect(err == error.JavaScriptException);
    const reason = engine.captured_exception orelse return error.MissingActualExecutorFatal;
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    // Fresh-realm teardown; no guest restoration after fatal failure.
}
