//! Prepared, unrun controls requiring the genuine composed loader, actual
//! imported physical guest extension, transactional API/runtime and event bus.
//! No collaborator, registry, importer, Promise or completed graph is fabricated.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const historical = @import("native_sdk_loader_rejected_data_controls.zig");
pub const Subject = historical.Subject;
fn same(engine: *v.em.Engine, a: c.JSValue, b: c.JSValue) !void { try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b)); }
fn count(engine: *v.em.Engine, object: c.JSValue, key: [*:0]const u8, expected: i32) !void {
    const value = try v.js.get(engine, object, key); defer engine.freeValue(value);
    var actual: i32 = 0;
    if (c.JS_ToInt32(engine.context, &actual, value) < 0) return v.js.capture(engine);
    try std.testing.expectEqual(expected, actual);
}
fn begin(engine: *v.em.Engine, actual: Subject) !c.JSValue {
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const gate = try v.js.get(engine, actual.controller, "gate"); defer engine.freeValue(gate);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, gate));
    const method = try v.js.get(engine, actual.loader, "loadExtensionsCached"); defer engine.freeValue(method);
    try std.testing.expect(c.JS_IsAsyncFunction(method));
    const outer = try v.js.call(engine, method, c.pi_js_undefined(), &.{ actual.paths, actual.cwd, actual.bus, actual.runtime });
    errdefer engine.freeValue(outer);
    c.JS_PromiseMarkAsHandled(engine.context, outer);
    _ = try engine.runReadyJobs(512);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try count(engine, actual.controller, "calls", 1);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    return outer;
}
fn reject(engine: *v.em.Engine, actual: Subject, reason: c.JSValue) !void {
    const ignored = try v.js.invoke(engine, actual.controller, "reject", &.{reason}); engine.freeValue(ignored);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn observeMessage(engine: *v.em.Engine, actual: Subject, reason: c.JSValue) !c.JSValue {
    const message = try v.js.get(engine, reason, "message");
    errdefer engine.freeValue(message);
    const ignored = try v.js.invoke(engine, actual.controller, "observeMessage", &.{ reason, message }); engine.freeValue(ignored);
    return message;
}
fn expectFormatted(engine: *v.em.Engine, actual: Subject, outer: c.JSValue, message: c.JSValue, expected_reads: i32) !void {
    _ = try engine.runReadyJobs(512);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_FULFILLED), c.JS_PromiseState(engine.context, outer));
    const result = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(result);
    const errors = try v.js.get(engine, result, "errors"); defer engine.freeValue(errors);
    try count(engine, errors, "length", 1);
    const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, errors, 0)); defer engine.freeValue(row);
    const error_text = try v.js.get(engine, row, "error"); defer engine.freeValue(error_text);
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    try same(engine, error_text, try scope.concat(try scope.text("Failed to load extension: "), message));
    try count(engine, actual.controller, "messageReads", expected_reads);
    try count(engine, actual.controller, "diagnosticReads", 0);
    // Actual transactional discard must remove the real guest subscription.
    const event = try scope.text("actual-sdk-settled-completion");
    const ignored = try v.js.invoke(engine, actual.bus, "emit", &.{ event, c.pi_js_undefined() }); engine.freeValue(ignored);
    try count(engine, actual.controller, "delivered", 0);
}
pub fn verifyOrdinaryUserError(engine: *v.em.Engine, actual: Subject) !void {
    const reason = try v.js.get(engine, actual.controller, "reason"); defer engine.freeValue(reason);
    const message = try observeMessage(engine, actual, reason); defer engine.freeValue(message);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    const outer = try begin(engine, actual); defer engine.freeValue(outer);
    try reject(engine, actual, reason);
    try expectFormatted(engine, actual, outer, message, 1);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
}
/// The host catches an ACTUAL installed Engine interrupt, then supplies its
/// owned value as settled Promise DATA. No name/flag lookalike is constructed.
pub fn verifyCaughtInterruptData(engine: *v.em.Engine, actual: Subject) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    engine.cancelled.store(true, .release);
    const source = "for (;;) {}";
    const result = c.JS_Eval(engine.context, source, source.len, "actual-loader-caught-interrupt.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.cancelled.store(false, .release);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
    const message = try observeMessage(engine, actual, reason); defer engine.freeValue(message);
    const outer = try begin(engine, actual); defer engine.freeValue(outer);
    try reject(engine, actual, reason);
    try expectFormatted(engine, actual, outer, message, 1);
    try std.testing.expect(c.JS_IsUncatchableError(reason)); // DATA bit is untouched.
}
/// The tag is born AFTER the real loader START while its actual guest factory
/// is awaiting. It is still DATA, not a failed operation in resumed code.
pub fn verifyFreshPrivateTagDataDuringAwait(engine: *v.em.Engine, actual: Subject) !void {
    const outer = try begin(engine, actual); defer engine.freeValue(outer);
    try std.testing.expect(engine.native_fatal_invocation == null);
    const generation = engine.native_allocation_generation;
    _ = engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    const message = try observeMessage(engine, actual, reason); defer engine.freeValue(message);
    try reject(engine, actual, reason);
    try expectFormatted(engine, actual, outer, message, 1);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
}
/// Source catch's message getter throws the same ordinary object again; actual
/// IteratorClose observes get/call once and ordinary close failure is suppressed.
/// actual.paths must come from controller.makeClosingPaths(actual physical path).
pub fn verifySameReasonThroughIteratorClose(engine: *v.em.Engine, actual: Subject) !void {
    const reason = try v.js.get(engine, actual.controller, "reason"); defer engine.freeValue(reason);
    const ignored = try v.js.invoke(engine, actual.controller, "throwMessage", &.{reason}); engine.freeValue(ignored);
    const outer = try begin(engine, actual); defer engine.freeValue(outer);
    try reject(engine, actual, reason);
    _ = try engine.runReadyJobs(512);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, outer));
    const result = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(result);
    try same(engine, result, reason);
    try count(engine, actual.controller, "messageReads", 1);
    try count(engine, actual.controller, "closeGets", 1);
    try count(engine, actual.controller, "closeCalls", 1);
    try count(engine, actual.controller, "diagnosticReads", 0);
}
fn fatalProbe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemoryFatal();
}
fn nextFatal(engine: *v.em.Engine) !c.JSValue {
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        var owner: ?*c.JSContext = null;
        const result = c.JS_ExecutePendingJob(engine.runtime, &owner);
        if (result < 0) {
            const context = owner orelse return error.MissingActualLoaderFatalOwner;
            try std.testing.expect(c.JS_HasException(context));
            return c.JS_GetException(context);
        }
        if (result == 0) return error.ExpectedActualLoaderFatalCompletion;
    }
    return error.ActualLoaderFatalControlBound;
}
/// Fresh exclusive Engine/realm only. Fatal branch intentionally performs no
/// guest restoration. Prior diagnostic DATA cannot replace the current fatal.
pub fn verifyFatalFormatterCompletion(engine: *v.em.Engine, actual: Subject, prior_data: c.JSValue) !void {
    try std.testing.expect(engine.captured_exception == null);
    engine.captured_exception = c.JS_DupValue(engine.context, prior_data);
    try engine.bindFunction("ActualSdkSettledFatal", fatalProbe, 0);
    const ignored = try v.js.invoke(engine, actual.controller, "fatalMessage", &.{}); engine.freeValue(ignored);
    const reason = try v.js.get(engine, actual.controller, "reason"); defer engine.freeValue(reason);
    const outer = try begin(engine, actual); defer engine.freeValue(outer);
    const generation = engine.native_allocation_generation;
    const prior_bit = c.JS_IsUncatchableError(prior_data);
    try reject(engine, actual, reason);
    const fatal = try nextFatal(engine); defer engine.freeValue(fatal);
    try same(engine, fatal, engine.native_allocation_exception orelse return error.MissingActualLoaderNativeOOM);
    try same(engine, fatal, engine.captured_exception orelse return error.MissingActualLoaderFatalCapture);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(c.JS_IsUncatchableError(fatal));
    try std.testing.expectEqual(prior_bit, c.JS_IsUncatchableError(prior_data));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try count(engine, actual.controller, "messageReads", 1);
    try count(engine, actual.controller, "diagnosticReads", 0);
}
// Reuse only these still-valid actual-pending-event controls; the historical
// verifyOldData control asserting bit-clearing is deliberately not selected.
pub fn verifyActualPendingFatalWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, actual_reason: c.JSValue) !void { try historical.verifyPendingHostWins(engine, actual, old_data, actual_reason); }
pub fn verifyActualDeferredInterruptWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue) !void { try historical.verifyDeferredInterrupt(engine, actual, old_data); }
