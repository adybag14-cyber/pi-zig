//! Prepared canonical real-module controls. Bindings must come from actual
//! completed namespaces, not injected mock core/frontend/require callbacks.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const graph = @import("extensions/native_jiti_core_graph.zig");
const cells = graph.cells;
const functions = @import("extensions/native_node_module_callable.zig");
fn same(engine: *v.em.Engine, first: c.JSValue, second: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}
/// The newly built actual require captures exactly this graph's real frontend;
/// Core and Frontend import the SAME require. No public prelink reference exists.
pub fn verifyActualCanonicalCycle(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.createCanonical(engine, bindings); defer instance.deinit(engine);
    const exports = try cells.exports(engine, &instance);
    defer engine.freeValue(exports.create_jiti); defer engine.freeValue(exports.eval_module);
    const core = try cells.coreImports(engine, instance.owner);
    const frontend = try cells.frontendImports(engine, instance.owner);
    try same(engine, core.jiti_require, frontend.jiti_require);
    try same(engine, core.eval_module, exports.eval_module);
    try same(engine, frontend.eval_module_self, exports.eval_module);
    try same(engine, frontend.nested_create_jiti, exports.create_jiti);
    // This is the KNOWN declaration hard-wired by requiring.create, never a
    // guest-provided callable/opaque cast. Exact reviewed inputRoots layout.
    const captures = try functions.capturedRoots(engine, core.jiti_require);
    try std.testing.expectEqual(@as(usize, 17), captures.len);
    try same(engine, captures[13], exports.eval_module);
    try same(engine, captures[15], bindings.require.resolve_inputs.js_ext_re);
    try same(engine, captures[16], bindings.require.resolve_inputs.ts_ext_re);
    const name = try v.js.get(engine, core.jiti_require, "name"); defer engine.freeValue(name);
    const expected_name = try engine.checked(c.JS_NewString(engine.context, "jitiRequire")); defer engine.freeValue(expected_name);
    try same(engine, name, expected_name);
    const length = try v.js.get(engine, core.jiti_require, "length"); defer engine.freeValue(length);
    try same(engine, length, c.JS_NewInt32(engine.context, 3));
    try std.testing.expect(c.JS_IsConstructor(engine.context, core.jiti_require));
    try std.testing.expectError(error.JitiModuleCellsAlreadyLinked, cells.linkCanonical(engine, &instance, bindings));
    try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &instance));
}
pub fn verifyMissingDependencyNoCommit(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.declare(engine); defer instance.deinit(engine);
    const before = c.pi_js_native_memory_used(engine.native_memory_owner);
    var missing = bindings; missing.frontend.transform = c.pi_js_undefined();
    try std.testing.expectError(error.RequiredActualJitiFrontendImport, cells.linkCanonical(engine, &instance, missing));
    try std.testing.expectEqual(before, c.pi_js_native_memory_used(engine.native_memory_owner));
    try std.testing.expectError(error.JitiModuleCellsNotReady, cells.exports(engine, &instance));
    try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &instance));
    // Correct actual inputs can still link once after the rejected preflight.
    try cells.linkCanonical(engine, &instance, bindings);
    try cells.initialize(engine, &instance);
}
pub fn verifyMismatchedRealImportsNoCommit(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.declare(engine); defer instance.deinit(engine);
    var mismatched = bindings;
    // Deliberately wrong REAL imported function, not a replacement callback.
    mismatched.frontend.debug = bindings.core.is_dir;
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, mismatched.frontend.debug, bindings.core.debug));
    try std.testing.expectError(error.MismatchedActualJitiModuleImports, cells.linkCanonical(engine, &instance, mismatched));
    try std.testing.expectError(error.JitiModuleCellsNotReady, cells.exports(engine, &instance));
}
/// Exhaust the existing actual combined runtime/native ledger AFTER declaring
/// the two real bodies. The new require's aggregate native reservation must
/// fail before any guest callback. Release the owned test reservation, retry
/// actual linking, then initialize; no partial require can have been exported.
pub fn verifyBudgetDenialRollbackAndRetry(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    var instance = try graph.declare(engine); defer instance.deinit(engine);
    const before = c.pi_js_native_memory_used(engine.native_memory_owner);
    try std.testing.expect(before <= engine.options.memory_limit);
    const remaining = engine.options.memory_limit - before;
    try std.testing.expect(c.pi_js_native_memory_reserve(engine.native_memory_owner, remaining) != 0);
    {
        defer c.pi_js_native_memory_release(engine.native_memory_owner, remaining);
        try std.testing.expectError(error.OutOfMemory, cells.linkCanonical(engine, &instance, bindings));
        try std.testing.expectEqual(before + remaining, c.pi_js_native_memory_used(engine.native_memory_owner));
        try std.testing.expectError(error.JitiModuleCellsNotReady, cells.exports(engine, &instance));
        try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &instance));
    }
    try cells.linkCanonical(engine, &instance, bindings);
    try cells.initialize(engine, &instance);
    const exports = try cells.exports(engine, &instance);
    defer engine.freeValue(exports.create_jiti); defer engine.freeValue(exports.eval_module);
    try same(engine, (try cells.coreImports(engine, instance.owner)).jiti_require, (try cells.frontendImports(engine, instance.owner)).jiti_require);
}
/// Only the real core declaration remains as an external root across GC. Its
/// record -> require -> frontend cycle survives; dropping that final root must
/// release charged storage. The shared ledger ALSO counts VM/class-registry
/// allocations, so equality to a pre-construction baseline would be false.
/// This does not claim C class-registry/Graph2 reclamation or run guest code.
pub fn verifyActualCycleMarkingAndLedgerRelease(engine: *v.em.Engine, bindings: cells.CanonicalBindings) !void {
    c.JS_RunGC(engine.runtime);
    var instance = try graph.createCanonical(engine, bindings);
    var instance_live = true; defer if (instance_live) instance.deinit(engine);
    const exports = try cells.exports(engine, &instance);
    engine.freeValue(exports.eval_module);
    instance.deinit(engine); instance_live = false;
    var core_live = true; defer if (core_live) engine.freeValue(exports.create_jiti);
    c.JS_RunGC(engine.runtime);
    const captures = try functions.capturedRoots(engine, exports.create_jiti);
    try std.testing.expectEqual(@as(usize, 1), captures.len);
    const core = try cells.coreImports(engine, captures[0]);
    const frontend = try cells.frontendImports(engine, captures[0]);
    try same(engine, core.jiti_require, frontend.jiti_require);
    const require_captures = try functions.capturedRoots(engine, core.jiti_require);
    try same(engine, require_captures[13], core.eval_module);
    const held = c.pi_js_native_memory_used(engine.native_memory_owner);
    engine.freeValue(exports.create_jiti); core_live = false;
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(c.pi_js_native_memory_used(engine.native_memory_owner) < held);
}
