//! Prepared original-subject regression controls, UNRUN. Subject MUST be the
//! real cached Module/Promise created by the actual complete factory, actual
//! jitiRequire/context/resolution, interopDefault=false and tryNative=false.
//! No replacement require/importer/Module/cache can provide this subject.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const importing = @import("extensions/native_jiti_import.zig");
pub const Subject = struct {
    context: c.JSValue,
    jiti_require: c.JSValue,
    id: c.JSValue,
    module: c.JSValue,
    resolve: c.JSValue,
    reject: c.JSValue,
    diagnostic_counter: c.JSValue,
};
fn same(engine: *v.em.Engine, first: c.JSValue, second: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}
fn begin(engine: *v.em.Engine, actual: Subject, options: c.JSValue) !c.JSValue {
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const exports = try v.js.get(engine, actual.module, "exports"); defer engine.freeValue(exports);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, exports));
    const method = try importing.create(engine, actual.context, actual.jiti_require); defer engine.freeValue(method);
    const outer = try v.js.call(engine, method, c.pi_js_undefined(), &.{actual.id, options});
    errdefer engine.freeValue(outer);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, outer, exports));
    // Avoid test-host rejection tracking; no guest .then/extra Promise is added.
    c.JS_PromiseMarkAsHandled(engine.context, outer);
    return outer;
}
fn settle(engine: *v.em.Engine, actual_function: c.JSValue, value: c.JSValue) !void {
    const ignored = try v.js.call(engine, actual_function, c.pi_js_undefined(), &.{value}); engine.freeValue(ignored);
}
fn noDiagnostics(engine: *v.em.Engine, actual: Subject) !void {
    const count = try v.js.get(engine, actual.diagnostic_counter, "reads"); defer engine.freeValue(count);
    try same(engine, count, c.JS_NewInt32(engine.context, 0));
}
/// Old native Error/tag/flag exists BEFORE START. Current C2 Await must reject
/// with this same DATA identity; no owner/job fatal and no diagnostic coercion.
pub fn verifyOldFlaggedData(engine: *v.em.Engine, actual: Subject, old_reason: c.JSValue) !void {
    c.JS_SetUncatchableError(engine.context, old_reason);
    const outer = try begin(engine, actual, c.pi_js_undefined()); defer engine.freeValue(outer);
    try settle(engine, actual.reject, old_reason);
    _ = try engine.runReadyJobs(128);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, outer));
    const reason = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(reason);
    try same(engine, reason, old_reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try noDiagnostics(engine, actual);
}
/// User's non-enumerable options.default getter throws the SAME ordinary old
/// Error as the preexisting diagnostic slot. A fresh capture, not pointer
/// inequality, proves this invocation's actual event. No prelink dummy subject.
pub fn verifySameObjectOrdinaryRethrow(engine: *v.em.Engine, actual: Subject, old_reason: c.JSValue, actual_options: c.JSValue) !void {
    c.JS_ClearUncatchableError(engine.context, old_reason);
    if (engine.captured_exception) |prior| engine.freeValue(prior);
    engine.captured_exception = c.JS_DupValue(engine.context, old_reason);
    const outer = try begin(engine, actual, actual_options); defer engine.freeValue(outer);
    try settle(engine, actual.resolve, c.pi_js_undefined());
    _ = try engine.runReadyJobs(128);
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_REJECTED), c.JS_PromiseState(engine.context, outer));
    const reason = c.JS_PromiseResult(engine.context, outer); defer engine.freeValue(reason);
    try same(engine, reason, old_reason);
    try same(engine, engine.captured_exception orelse return error.MissingRestoredPriorDiagnostic, old_reason);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try noDiagnostics(engine, actual);
}
fn freshFailure(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}
/// Installs ONLY an explicit test fault probe. The Source options.default
/// getter calls it after real Await fulfillment. It is never a require facade.
pub fn installFreshFaultProbe(engine: *v.em.Engine) !void {
    const probe = try engine.checked(c.JS_NewCFunction(engine.context, freshFailure, "ActualJitiImportFreshOOM", 0)); defer engine.freeValue(probe);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, "ActualJitiImportFreshOOM", c.JS_DupValue(engine.context, probe));
}
fn fatalJob(engine: *v.em.Engine) !c.JSValue {
    var context: ?*c.JSContext = null;
    const result = c.JS_ExecutePendingJob(engine.runtime, &context);
    try std.testing.expect(result < 0);
    const owner = context orelse return error.MissingFatalJobContext;
    try std.testing.expect(c.JS_HasException(owner));
    // Inspect actual terminal event without outer diagnostic formatting. The
    // leaf itself still runs through the production AF suppression boundary.
    return c.JS_GetException(owner);
}
pub fn verifyFreshResumedOOM(engine: *v.em.Engine, actual: Subject, actual_options: c.JSValue) !void {
    const boundary = engine.native_allocation_generation;
    const outer = try begin(engine, actual, actual_options); defer engine.freeValue(outer);
    try settle(engine, actual.resolve, c.pi_js_undefined());
    const fatal = try fatalJob(engine); defer engine.freeValue(fatal);
    try std.testing.expect(engine.native_allocation_generation != boundary);
    try same(engine, fatal, engine.native_allocation_exception orelse return error.MissingFreshNativeAllocation);
    try std.testing.expect(c.JS_IsUncatchableError(fatal));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try noDiagnostics(engine, actual);
}
const Event = enum { pending_host_fatal, actual_interrupt };
const Hook = struct { engine: *v.em.Engine, kind: Event, marker: c.JSValue, reason: c.JSValue, observed: c.JSValue, fired: bool = false };
fn beforeJob(context: ?*c.JSContext, before: bool, marker: c.JSValue, raw: ?*anyopaque) callconv(.c) void {
    const ctx = context orelse return;
    const state: *Hook = @ptrCast(@alignCast(raw.?));
    if (!before or state.fired or !c.JS_IsStrictEqual(ctx, marker, state.marker)) return;
    state.fired = true;
    if (state.kind == .pending_host_fatal) {
        // Trusted raw host event in the actual pending VM slot, not DATA.
        c.JS_SetUncatchableError(ctx, state.reason);
        _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, state.reason));
    } else {
        // Genuine installed Engine interrupt handler creates the non-OOM
        // fatal. Reset cancellation only after that VM event exists, preventing
        // a second poll from replacing the first before the leaf checks it.
        state.engine.cancelled.store(true, .release);
        const source = "for (;;) {}";
        const result = c.JS_Eval(ctx, source, source.len, "actual-deferred-native-interrupt.js", c.JS_EVAL_TYPE_GLOBAL);
        state.engine.cancelled.store(false, .release);
        c.JS_FreeValue(ctx, result);
    }
    if (c.JS_HasException(ctx)) {
        const reason = c.JS_GetException(ctx);
        state.observed = c.JS_DupValue(ctx, reason);
        _ = c.JS_Throw(ctx, reason);
    }
}
/// This raw hook control requires its OWN fresh, exclusive Engine.init realm
/// before any application execution-context hook is installed. It never
/// replaces or tears down another owner's hook. Actual subject remains real.
fn eventWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, event_reason: c.JSValue, kind: Event) !void {
    const marker = try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)); defer engine.freeValue(marker);
    var hook: Hook = .{ .engine = engine, .kind = kind, .marker = marker, .reason = event_reason, .observed = c.pi_js_undefined() };
    defer engine.freeValue(hook.observed);
    c.JS_SetUncatchableError(engine.context, old_data);
    c.JS_SetExecutionContext(engine.runtime, marker);
    defer c.JS_SetExecutionContext(engine.runtime, c.pi_js_undefined());
    const outer = try begin(engine, actual, c.pi_js_undefined()); defer engine.freeValue(outer);
    try settle(engine, actual.reject, old_data);
    c.JS_SetExecutionContextHook(engine.runtime, beforeJob, &hook);
    defer c.JS_SetExecutionContextHook(engine.runtime, null, null);
    const generation = engine.native_allocation_generation;
    const fatal = try fatalJob(engine); defer engine.freeValue(fatal);
    try std.testing.expect(hook.fired);
    try same(engine, fatal, hook.observed);
    if (kind == .pending_host_fatal) try same(engine, fatal, event_reason);
    try std.testing.expect(c.JS_IsUncatchableError(fatal));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(fatal));
    // Entry pending event must win BEFORE the data's historical flag is cleared.
    try std.testing.expect(c.JS_IsUncatchableError(old_data));
    try std.testing.expectEqual(@as(c_int, c.JS_PROMISE_PENDING), c.JS_PromiseState(engine.context, outer));
    try noDiagnostics(engine, actual);
}
pub fn verifyPendingHookFatalWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, actual_host_event: c.JSValue) !void {
    try eventWins(engine, actual, old_data, actual_host_event, .pending_host_fatal);
}
pub fn verifyDeferredBudgetInterrupt(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue) !void {
    try eventWins(engine, actual, old_data, c.pi_js_undefined(), .actual_interrupt);
}
