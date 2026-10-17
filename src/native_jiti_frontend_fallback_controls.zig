//! Prepared finite ordinary-fallback controls, UNRUN. The callback is captured
//! from the ACTUAL completed frontend's real Promise.catch registration using
//! original-input.mjs. Never create a fake frontend/require/importer/self.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
pub const Subject = struct {
    actual_callback: c.JSValue,
    original_options: c.JSValue,
    counters: c.JSValue,
};
fn same(engine: *v.em.Engine, first: c.JSValue, second: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}
fn rawCall(engine: *v.em.Engine, actual: Subject, data: c.JSValue) c.JSValue {
    var args = [_]c.JSValue{data};
    return c.JS_Call(engine.context, actual.actual_callback, c.pi_js_undefined(), 1, &args);
}
fn actualException(engine: *v.em.Engine, result: c.JSValue) !c.JSValue {
    if (!c.JS_IsException(result)) { engine.freeValue(result); return error.ExpectedActualFrontendException; }
    try std.testing.expect(c.JS_HasException(engine.context));
    // Raw terminal inspection avoids outer Engine.checked diagnostic coercion;
    // the production ModuleCallable boundary itself must still suppress it.
    return c.JS_GetException(engine.context);
}
fn noDiagnostics(engine: *v.em.Engine, actual: Subject) !void {
    const reads = try v.js.get(engine, actual.counters, "diagnosticReads"); defer engine.freeValue(reads);
    try same(engine, reads, c.JS_NewInt32(engine.context, 0));
}
/// Old tagged/flagged rejected data follows actual debug/spread/self fallback,
/// preserving the Source tail's exact observed raw result, not another Promise.
pub fn verifyHistoricalDataRawFallback(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, observed_source_raw_return: c.JSValue) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(old_data) != 0);
    c.JS_SetUncatchableError(engine.context, old_data);
    const result = rawCall(engine, actual, old_data); defer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try same(engine, result, observed_source_raw_return);
    try std.testing.expect(!c.JS_IsUncatchableError(old_data));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try noDiagnostics(engine, actual);
}
/// The original nonempty options object gets an enumerable USER getter only
/// after callback capture. It throws the SAME old ordinary diagnostic object
/// during the real Source spread; new capture ownership cannot use inequality.
pub fn verifySameObjectOrdinarySpreadRethrow(engine: *v.em.Engine, actual: Subject, same_reason: c.JSValue) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    c.JS_ClearUncatchableError(engine.context, same_reason);
    if (engine.captured_exception) |prior| engine.freeValue(prior);
    engine.captured_exception = c.JS_DupValue(engine.context, same_reason);
    const reason = try actualException(engine, rawCall(engine, actual, same_reason)); defer engine.freeValue(reason);
    try same(engine, reason, same_reason);
    // The actual ordinary trampoline consumes the new captured root into
    // JS_Throw before rawCall returns. actualException now owns that reason.
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try noDiagnostics(engine, actual);
}
fn freshFailure(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}
fn cancelBudget(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    v.em.Engine.fromContext(context.?).cancelled.store(true, .release);
    return c.pi_js_undefined();
}
/// Explicit native-only fault probes used by ORIGINAL user option getters;
/// no production binding/helper/require/core implementation is replaced.
pub fn installNativeFaultProbes(engine: *v.em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const allocation = try engine.checked(c.JS_NewCFunction(engine.context, freshFailure, "ActualJitiFallbackFreshOOM", 0)); defer engine.freeValue(allocation);
    const cancellation = try engine.checked(c.JS_NewCFunction(engine.context, cancelBudget, "ActualJitiFallbackCancelBudget", 0)); defer engine.freeValue(cancellation);
    try v.js.define(engine, global, "ActualJitiFallbackFreshOOM", c.JS_DupValue(engine.context, allocation));
    try v.js.define(engine, global, "ActualJitiFallbackCancelBudget", c.JS_DupValue(engine.context, cancellation));
}
pub fn verifyFreshSpreadOOM(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue) !void {
    const before = engine.native_allocation_generation;
    c.JS_SetUncatchableError(engine.context, old_data);
    const reason = try actualException(engine, rawCall(engine, actual, old_data)); defer engine.freeValue(reason);
    try std.testing.expect(engine.native_allocation_generation != before);
    try same(engine, reason, engine.native_allocation_exception orelse return error.MissingFreshFrontendAllocation);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try noDiagnostics(engine, actual);
}
pub fn verifyActualPendingEventWins(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue, current_event: c.JSValue) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(current_event));
    const generation = engine.native_allocation_generation;
    c.JS_SetUncatchableError(engine.context, old_data);
    c.JS_SetUncatchableError(engine.context, current_event);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, current_event));
    const reason = try actualException(engine, rawCall(engine, actual, old_data)); defer engine.freeValue(reason);
    try same(engine, reason, current_event);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    // Before data flag/private generation/debug/options work, the actual VM
    // event must win; the historical data flag remains untouched.
    try std.testing.expect(c.JS_IsUncatchableError(old_data));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    const extras = try v.js.get(engine, actual.counters, "extraReads"); defer engine.freeValue(extras);
    try same(engine, extras, c.JS_NewInt32(engine.context, 0));
    try noDiagnostics(engine, actual);
}
/// Source getter calls the real native cancellation probe and runs its actual
/// user loop, causing the installed Engine interrupt handler to throw. This
/// is a current non-OOM event, never inferred from rejected data or error name.
pub fn verifyRealSpreadInterrupt(engine: *v.em.Engine, actual: Subject, old_data: c.JSValue) !void {
    const generation = engine.native_allocation_generation;
    c.JS_SetUncatchableError(engine.context, old_data);
    defer engine.cancelled.store(false, .release);
    const result = rawCall(engine, actual, old_data);
    engine.cancelled.store(false, .release);
    const reason = try actualException(engine, result); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expectEqual(@as(u64, 0), c.pi_js_native_allocation_error_generation(reason));
    try noDiagnostics(engine, actual);
}
