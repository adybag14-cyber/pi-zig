//! Prepared genuine-declaration contrasts, UNRUN. All Subjects use the actual
//! canonical wrapper and real native require/import capabilities. User probes
//! delegate those real capabilities; no stub namespace/result/importer/require.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const graph = @import("extensions/native_jiti_core_graph.zig");
const cells = graph.cells;
const functions = @import("extensions/native_node_module_callable.zig");
pub const Subject = struct { declaration: c.JSValue, context: c.JSValue, id: c.JSValue, asynchronous: c.JSValue, counters: c.JSValue };
fn same(engine: *v.em.Engine, a: c.JSValue, b: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b));
}
fn rawCall(engine: *v.em.Engine, actual: Subject) c.JSValue {
    var args = [_]c.JSValue{actual.context, actual.id, actual.asynchronous};
    return c.JS_Call(engine.context, actual.declaration, c.pi_js_undefined(), args.len, &args);
}
fn takeActualException(engine: *v.em.Engine, result: c.JSValue) !c.JSValue {
    if (!c.JS_IsException(result)) {engine.freeValue(result);return error.ExpectedActualNativeImportException;}
    try std.testing.expect(c.JS_HasException(engine.context));
    return c.JS_GetException(engine.context);
}
fn count(engine: *v.em.Engine, counters: c.JSValue, name: [*:0]const u8, expected: i32) !void {
    const value = try v.js.get(engine, counters, name); defer engine.freeValue(value);
    try same(engine, value, c.JS_NewInt32(engine.context, expected));
}
pub fn verifyCanonicalTwoRealDeclarations(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.createCanonical(engine, bindings); defer instance.deinit(engine);
    const exports = try cells.exports(engine, &instance); defer engine.freeValue(exports.create_jiti); defer engine.freeValue(exports.eval_module);
    const core = try cells.coreImports(engine, instance.owner);
    const frontend = try cells.frontendImports(engine, instance.owner);
    try same(engine, core.jiti_require, frontend.jiti_require);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, core.jiti_require, frontend.native_import_or_require));
    // Both are known constructors hard-wired by canonical assembly, not
    // arbitrary guest-function casts. Actual reviewed inputRoots layout.
    const require_roots = try functions.capturedRoots(engine, core.jiti_require);
    const native_roots = try functions.capturedRoots(engine, frontend.native_import_or_require);
    try std.testing.expectEqual(@as(usize, 17), require_roots.len);
    try std.testing.expectEqual(require_roots.len, native_roots.len);
    for (require_roots, native_roots) |first, second| try same(engine, first, second);
    try same(engine, native_roots[13], exports.eval_module);
    const name = try v.js.get(engine, frontend.native_import_or_require, "name"); defer engine.freeValue(name);
    const expected_name = try engine.checked(c.JS_NewString(engine.context, "nativeImportOrRequire")); defer engine.freeValue(expected_name);
    try same(engine, name, expected_name);
    const length = try v.js.get(engine, frontend.native_import_or_require, "length"); defer engine.freeValue(length);
    try same(engine, length, c.JS_NewInt32(engine.context, 3));
    try std.testing.expect(c.JS_IsConstructor(engine.context, frontend.native_import_or_require));
}
/// Actual genuine import Promise.then is observed/delegated by the original
/// user input, which can return a marker. Wrapper must return it EXACTLY.
pub fn verifyRealRawThenReturn(engine: *v.em.Engine, actual: Subject, observed_raw_result: c.JSValue) !void {
    const result = rawCall(engine, actual); defer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try same(engine, result, observed_raw_result);
    try count(engine, actual.counters, "importReads", 2);
    try count(engine, actual.counters, "requireReads", 0);
    try count(engine, actual.counters, "diagnosticReads", 0);
}
pub fn verifySyncUsesRealRequireWithoutImportRead(engine: *v.em.Engine, actual: Subject, actual_required_export: c.JSValue) !void {
    const result = rawCall(engine, actual); defer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try same(engine, result, actual_required_export);
    try count(engine, actual.counters, "importReads", 0);
    try count(engine, actual.counters, "requireReads", 1);
}
/// A Source condition/callee/normalize/then getter or actual invocation throw
/// is synchronous in this ordinary declaration, not a rejected wrapper Promise.
pub fn verifyActualSynchronousThrow(engine: *v.em.Engine, actual: Subject, original_reason: c.JSValue) !void {
    const reason = try takeActualException(engine, rawCall(engine, actual)); defer engine.freeValue(reason);
    try same(engine, reason, original_reason);
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.captured_exception == null);
    try count(engine, actual.counters, "diagnosticReads", 0);
}
pub fn verifyActualPendingEventBeforeGetters(engine: *v.em.Engine, actual: Subject, pending_reason: c.JSValue) !void {
    try std.testing.expect(!c.JS_HasException(engine.context));
    c.JS_SetUncatchableError(engine.context, pending_reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, pending_reason));
    const reason = try takeActualException(engine, rawCall(engine, actual)); defer engine.freeValue(reason);
    try same(engine, reason, pending_reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try count(engine, actual.counters, "importReads", 0);
    try count(engine, actual.counters, "requireReads", 0);
    try count(engine, actual.counters, "diagnosticReads", 0);
}
fn pendingSuccess(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context orelse return c.pi_js_undefined();
    const reason = if (argc > 0) argv[0] else c.pi_js_undefined();
    c.JS_SetUncatchableError(ctx, reason);
    _ = c.JS_Throw(ctx, c.JS_DupValue(ctx, reason));
    return c.pi_js_undefined();
}
fn freshAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}
/// Explicit native-only event probes, never production context capabilities.
pub fn installNativeEventProbes(engine: *v.em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const pending = try engine.checked(c.JS_NewCFunction(engine.context, pendingSuccess, "ActualNativeImportPendingEvent", 1)); defer engine.freeValue(pending);
    const allocation = try engine.checked(c.JS_NewCFunction(engine.context, freshAllocation, "ActualNativeImportFreshOOM", 0)); defer engine.freeValue(allocation);
    try v.js.define(engine, global, "ActualNativeImportPendingEvent", c.JS_DupValue(engine.context, pending));
    try v.js.define(engine, global, "ActualNativeImportFreshOOM", c.JS_DupValue(engine.context, allocation));
}
/// A real delegated capability/then can leave a pending actual host event
/// despite a success return. Preserve that reason over success-value cleanup.
pub fn verifyPendingEventOverSuccessValue(engine: *v.em.Engine, actual: Subject, actual_pending_reason: c.JSValue) !void {
    const reason = try takeActualException(engine, rawCall(engine, actual)); defer engine.freeValue(reason);
    try same(engine, reason, actual_pending_reason);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try count(engine, actual.counters, "diagnosticReads", 0);
}
pub fn verifyFreshCurrentNativeOOM(engine: *v.em.Engine, actual: Subject) !void {
    const generation = engine.native_allocation_generation;
    const reason = try takeActualException(engine, rawCall(engine, actual)); defer engine.freeValue(reason);
    try std.testing.expect(engine.native_allocation_generation != generation);
    try same(engine, reason, engine.native_allocation_exception orelse return error.MissingFreshNativeImportAllocation);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try count(engine, actual.counters, "diagnosticReads", 0);
}
/// Only for an exclusive test Engine with no concurrent tasks/jobs. Source
/// namespace inputs are already complete. The actual ordinary callable uses
/// two GPA allocations (state,17roots). Fail the THIRD allocation, so genuine
/// require was staged and new nativeImport declaration construction fails.
pub fn verifySecondDeclarationRollbackAndRetry(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.declare(engine); defer instance.deinit(engine);
    const backing = engine.gpa;
    var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = 2 });
    {
        engine.gpa = failing.allocator(); defer engine.gpa = backing;
        try std.testing.expectError(error.OutOfMemory, cells.linkCanonical(engine, &instance, bindings));
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(@as(usize, 2), failing.allocations);
    }
    // The decorator forwarded all storage to the same backing allocator;
    // restoring it before later finalization does not retire borrowed state.
    c.JS_RunGC(engine.runtime);
    try std.testing.expectError(error.JitiModuleCellsNotReady, cells.exports(engine, &instance));
    try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &instance));
    try cells.linkCanonical(engine, &instance, bindings);
    try cells.initialize(engine, &instance);
    const frontend = try cells.frontendImports(engine, instance.owner);
    try std.testing.expect(c.JS_IsFunction(engine.context, frontend.native_import_or_require));
}
