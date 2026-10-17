//! Prepared whole-pipeline controls. Actual native loader/runtime/bus and an
//! actual imported physical guest factory are REQUIRED. No fake jiti, Module,
//! require, transactional API, event bus, registry or Promise is substituted.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub const Mode = enum { initializer, whole_loader };
pub const Subject = struct {
    loader: c.JSValue,
    factory: c.JSValue,
    paths: c.JSValue,
    cwd: c.JSValue,
    bus: c.JSValue,
    runtime: c.JSValue,
    /// Actual exported controller from the retained guest controller module;
    /// its gate/resolve/reject are created by REAL guest new Promise.
    controller: c.JSValue,
};
fn same(engine: *v.em.Engine, first: c.JSValue, second: c.JSValue) !void { try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second)); }
fn number(engine: *v.em.Engine, object: c.JSValue, key: [*:0]const u8, expected: i32) !void {
    const value = try v.js.get(engine, object, key); defer engine.freeValue(value);
    var integer: i32 = 0; if (c.JS_ToInt32(engine.context, &integer, value) < 0) return v.js.capture(engine);
    try std.testing.expectEqual(expected, integer);
}
fn begin(engine: *v.em.Engine, actual: Subject, mode: Mode) !c.JSValue {
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const gate = try v.js.get(engine, actual.controller, "gate"); defer engine.freeValue(gate);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, gate));
    const function = try v.js.get(engine, actual.loader, if (mode == .initializer) "loadExtensionFromFactory" else "loadExtensionsCached"); defer engine.freeValue(function);
    try std.testing.expect(c.JS_IsAsyncFunction(function));
    const outer = try v.js.call(engine, function, c.pi_js_undefined(), &.{ if (mode == .initializer) actual.factory else actual.paths, actual.cwd, actual.bus, actual.runtime });
    errdefer engine.freeValue(outer);
    c.JS_PromiseMarkAsHandled(engine.context, outer);
    // Finish genuine import/factory-start jobs while the actual guest gate is
    // pending. This also installs real RETURN-adoption continuations. The next
    // gate rejection job then reaches actual initializeExtension's native Await.
    _ = try engine.runReadyJobs(512);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try number(engine, actual.controller, "calls", 1);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    return outer;
}
fn rejectGate(engine: *v.em.Engine, actual: Subject, reason: c.JSValue) !void {
    const reject = try v.js.get(engine, actual.controller, "reject"); defer engine.freeValue(reject);
    const ignored = try v.js.call(engine, reject, c.pi_js_undefined(), &.{reason}); engine.freeValue(ignored);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
fn diagnostics(engine: *v.em.Engine, actual: Subject) !void { try number(engine, actual.controller, "diagnosticReads", 0); }
fn discarded(engine: *v.em.Engine, actual: Subject) !void {
    const event = try engine.checked(c.JS_NewString(engine.context, "actual-sdk-rejected-data")); defer engine.freeValue(event);
    const ignored = try v.js.invoke(engine, actual.bus, "emit", &.{ event, c.pi_js_undefined() }); engine.freeValue(ignored);
    try number(engine, actual.controller, "delivered", 0);
}
/// Run separately with an old actual native-tagged Error, unrelated later
/// generation, ordinary marked Error, and lookalike name/message. For a native
/// tag, create the reason BEFORE begin; no active VM event may remain.
pub fn verifyOldData(engine: *v.em.Engine, actual: Subject, old_reason: c.JSValue, mode: Mode) !void {
    c.JS_SetUncatchableError(engine.context, old_reason);
    const outer = try begin(engine, actual, mode); defer engine.freeValue(outer);
    try rejectGate(engine, actual, old_reason);
    _ = try engine.runReadyJobs(512);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsUncatchableError(old_reason));
    const result = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(result);
    if (mode == .initializer) {
        try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, outer));
        try same(engine, result, old_reason);
    } else {
        try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_FULFILLED), c.JS_PromiseState(engine.context, outer));
        const errors = try v.js.get(engine, result, "errors"); defer engine.freeValue(errors);
        try number(engine, errors, "length", 1);
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, errors, 0)); defer engine.freeValue(row);
        const message = try v.js.get(engine, row, "error"); defer engine.freeValue(message);
        const expected = try v.js.get(engine, actual.controller, "expectedError"); defer engine.freeValue(expected);
        try same(engine, message, expected);
    }
    try discarded(engine, actual);
    try diagnostics(engine, actual);
}
/// Retained guest controller installs a message getter that throws the SAME
/// reason stored in the prior diagnostic slot. It is an actual NEW capture,
/// not pointer inequality. Source formatter is outside its protected try.
pub fn verifySameObjectFormatterRethrow(engine: *v.em.Engine, actual: Subject, actual_reason: c.JSValue) !void {
    c.JS_ClearUncatchableError(engine.context, actual_reason);
    if (engine.captured_exception) |prior| engine.freeValue(prior);
    engine.captured_exception = c.JS_DupValue(engine.context, actual_reason);
    const outer = try begin(engine, actual, .whole_loader); defer engine.freeValue(outer);
    try rejectGate(engine, actual, actual_reason);
    _ = try engine.runReadyJobs(512);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, outer));
    const reason = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(reason);
    try same(engine, reason, actual_reason);
    try same(engine, engine.captured_exception orelse return error.MissingRestoredSdkLoaderDiagnostic, actual_reason);
    try number(engine, actual.controller, "messageReads", 1);
    try discarded(engine, actual);
    try diagnostics(engine, actual);
}
fn freshOOM(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory(); }
pub fn installFreshOOMProbe(engine: *v.em.Engine) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, freshOOM, "ActualSdkLoaderFreshOOM", 0)); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, "ActualSdkLoaderFreshOOM", c.JS_DupValue(engine.context, function));
}
fn fatalJob(engine: *v.em.Engine) !c.JSValue {
    var owner: ?*c.JSContext = null;
    try std.testing.expect(c.JS_ExecutePendingJob(engine.runtime, &owner) < 0);
    const context = owner orelse return error.MissingSdkLoaderFatalJobOwner;
    try std.testing.expect(c.JS_HasException(context));
    return c.JS_GetException(context);
}
/// Guest controller's real discard subscription wrapper calls the genuine
/// fault probe AFTER actual unsubscribe. Current private OOM must bypass
/// formatter/error aggregation and preserve the original allocation identity.
pub fn verifyFreshDiscardOOM(engine: *v.em.Engine, actual: Subject, ordinary_reason: c.JSValue) !void {
    const outer = try begin(engine, actual, .whole_loader); defer engine.freeValue(outer);
    const generation = engine.native_allocation_generation;
    try rejectGate(engine, actual, ordinary_reason);
    const fatal = try fatalJob(engine); defer engine.freeValue(fatal);
    try same(engine, fatal, engine.native_allocation_exception orelse return error.MissingActualSdkAllocation);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try std.testing.expect(c.JS_IsUncatchableError(fatal));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try diagnostics(engine, actual);
}
const Event = enum { pending_host, interrupt };
const Hook = struct { engine: *v.em.Engine, marker: c.JSValue, reason: c.JSValue, observed: c.JSValue, event: Event, fired: bool = false };
fn beforeJob(context: ?*c.JSContext, before: bool, marker: c.JSValue, raw: ?*anyopaque) callconv(.c) void {
    const ctx = context orelse return; const hook: *Hook = @ptrCast(@alignCast(raw.?));
    if (!before or hook.fired or !c.JS_IsStrictEqual(ctx, marker, hook.marker)) return;
    hook.fired = true;
    if (hook.event == .pending_host) {
        c.JS_SetUncatchableError(ctx, hook.reason); _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, hook.reason));
    } else {
        hook.engine.cancelled.store(true, .release);
        const source = "for (;;) {}";
        const result = c.JS_Eval(ctx, source, source.len, "actual-sdk-loader-deferred-interrupt.js", c.JS_EVAL_TYPE_GLOBAL);
        hook.engine.cancelled.store(false, .release); c.JS_FreeValue(ctx, result);
    }
    if (c.JS_HasException(ctx)) { const reason = c.JS_GetException(ctx); hook.observed = c.JS_DupValue(ctx, reason); _ = c.JS_Throw(ctx, reason); }
}
/// Exclusive fresh Engine only; installs no hook over an application owner's
/// hook. begin drains genuine factory/import work before the actual gate Await.
fn eventWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, event_reason: c.JSValue, event: Event) !void {
    const marker = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())); defer engine.freeValue(marker);
    c.JS_SetExecutionContext(engine.runtime, marker); defer c.JS_SetExecutionContext(engine.runtime, c.pi_js_undefined());
    const outer = try begin(engine, actual, .whole_loader); defer engine.freeValue(outer);
    c.JS_SetUncatchableError(engine.context, old_data); try rejectGate(engine, actual, old_data);
    var hook: Hook = .{ .engine = engine, .marker = marker, .reason = event_reason, .observed = c.pi_js_undefined(), .event = event };
    defer engine.freeValue(hook.observed);
    c.JS_SetExecutionContextHook(engine.runtime, beforeJob, &hook); defer c.JS_SetExecutionContextHook(engine.runtime, null, null);
    const generation = engine.native_allocation_generation;
    const fatal = try fatalJob(engine); defer engine.freeValue(fatal);
    try std.testing.expect(hook.fired); try same(engine, fatal, hook.observed);
    if (event == .pending_host) try same(engine, fatal, event_reason);
    try std.testing.expect(c.JS_IsUncatchableError(fatal));
    try std.testing.expect(c.JS_IsUncatchableError(old_data)); // No rejected-DATA clear before actual pending event.
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(fatal));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try diagnostics(engine, actual);
}
pub fn verifyPendingHostWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, actual_host_reason: c.JSValue) !void { try eventWins(engine, actual, old_data, actual_host_reason, .pending_host); }
pub fn verifyDeferredInterrupt(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue) !void { try eventWins(engine, actual, old_data, c.pi_js_undefined(), .interrupt); }
