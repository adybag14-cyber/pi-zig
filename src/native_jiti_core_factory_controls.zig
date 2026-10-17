//! Prepared actual-subject controls. No fake core/frontend/importer callback
//! can satisfy Bindings; complete genuine dependencies are still prerequisites.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const graph = @import("extensions/native_jiti_core_graph.zig");
const cells = graph.cells;
const evaluation = @import("extensions/native_jiti_eval_module.zig");
fn same(engine: *v.em.Engine, a: c.JSValue, b: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b));
}
/// Does not link dummy imports or expose a prelinked declaration. Both actual
/// canonical bodies exist, while namespace publication remains disallowed.
pub fn verifyUnlinkedNotExposed(engine: *v.em.Engine) !void {
    var actual = try graph.declare(engine); defer actual.deinit(engine);
    try std.testing.expectError(error.JitiModuleCellsNotReady, cells.exports(engine, &actual));
    try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &actual));
}
pub fn verifyForeignEngineRejected(engine: *v.em.Engine, foreign: *v.em.Engine) !void {
    try std.testing.expect(engine != foreign);
    var actual = try graph.declare(engine); defer actual.deinit(engine);
    try std.testing.expectError(error.ForeignJitiModuleCells, cells.exports(foreign, &actual));
}
/// Uses actual completed dependencies. No generic Bodies injection. All reads
/// inspect the retained real canonical import cells, not a mock Source facade.
pub fn verifyCanonicalCycleAndOnce(engine: *v.em.Engine, bindings: cells.Bindings) !void {
    var actual = try graph.create(engine, bindings); defer actual.deinit(engine);
    const first = try cells.exports(engine, &actual);
    defer engine.freeValue(first.create_jiti); defer engine.freeValue(first.eval_module);
    const second = try cells.exports(engine, &actual);
    defer engine.freeValue(second.create_jiti); defer engine.freeValue(second.eval_module);
    try same(engine, first.create_jiti, second.create_jiti);
    try same(engine, first.eval_module, second.eval_module);
    try same(engine, (try cells.coreImports(engine, actual.owner)).eval_module, first.eval_module);
    const frontend = try cells.frontendImports(engine, actual.owner);
    try same(engine, frontend.nested_create_jiti, first.create_jiti);
    try same(engine, frontend.eval_module_self, first.eval_module);
    try std.testing.expectError(error.JitiModuleCellsAlreadyLinked, cells.link(engine, &actual, bindings));
    try std.testing.expectError(error.JitiModuleCellsNotLinkedOrAlreadyInitialized, cells.initialize(engine, &actual));
    inline for (.{first.create_jiti, first.eval_module}, .{"createJiti", "evalModule"}, .{1, 2}) |function, name, length| {
        try std.testing.expect(c.JS_IsFunction(engine.context, function));
        try std.testing.expect(c.JS_IsConstructor(engine.context, function));
        const actual_name = try v.js.get(engine, function, "name"); defer engine.freeValue(actual_name);
        const expected_name = try engine.checked(c.JS_NewString(engine.context, name)); defer engine.freeValue(expected_name);
        try same(engine, actual_name, expected_name);
        const actual_length = try v.js.get(engine, function, "length"); defer engine.freeValue(actual_length);
        try same(engine, actual_length, c.JS_NewInt32(engine.context, length));
    }
}
pub const LoweredSubject = struct { inputs: evaluation.Inputs, request: evaluation.LoweredRequest };
/// Actual source value has a user toString that throws the supplied identity.
/// The real Module/cache and actual nested factory are mandatory. onError is
/// the Source parent's callback and must remain uncalled in accepted trace.
pub fn verifyWrapFailureAfterPublication(engine: *v.em.Engine, actual: LoweredSubject, original_reason: c.JSValue) !void {
    try std.testing.expectError(error.JavaScriptException, evaluation.evaluateLowered(engine, actual.inputs, actual.request));
    const reason = engine.captured_exception orelse return error.MissingControlReason;
    engine.captured_exception = null; defer engine.freeValue(reason);
    try same(engine, reason, original_reason);
    const module = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(module);
    try std.testing.expect(c.JS_IsObject(module));
    const native_require = try v.js.get(engine, actual.request.context, "nativeRequire"); defer engine.freeValue(native_require);
    const native_cache = try v.js.get(engine, native_require, "cache"); defer engine.freeValue(native_cache);
    const native_entry = try v.js.getKey(engine, native_cache, actual.request.filename); defer engine.freeValue(native_entry);
    try same(engine, module, native_entry);
}
/// Original invalid JS returned by the actual transform/cache, sync mode and a
/// real returning onError. Source performs compile catch, native-only cleanup,
/// then undefined-call catch, then loaded tail. Accepted Source trace required.
pub fn verifyCompileFailureReturnsThroughRealTail(engine: *v.em.Engine, actual: LoweredSubject) !void {
    const result = try evaluation.evaluateLowered(engine, actual.inputs, actual.request); defer engine.freeValue(result);
    const module = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(module);
    const loaded = try v.js.get(engine, module, "loaded"); defer engine.freeValue(loaded);
    try std.testing.expect(c.JS_ToBool(engine.context, loaded) == 1);
    const exported = try v.js.get(engine, module, "exports"); defer engine.freeValue(exported);
    try same(engine, result, exported);
    const native_require = try v.js.get(engine, actual.request.context, "nativeRequire"); defer engine.freeValue(native_require);
    const native_cache = try v.js.get(engine, native_require, "cache"); defer engine.freeValue(native_cache);
    try std.testing.expect(!try v.js.hasKey(engine, native_cache, actual.request.filename));
}
/// Compares only independently accepted observations from genuine original
/// Source controls. This helper neither manufactures nor writes expected data.
pub fn verifyAcceptedTrace(engine: *v.em.Engine, actual_trace: c.JSValue, accepted_trace: c.JSValue) !void {
    const json = try v.js.global(engine, "JSON"); defer engine.freeValue(json);
    const stringify = try v.js.get(engine, json, "stringify"); defer engine.freeValue(stringify);
    const actual = try v.js.call(engine, stringify, json, &.{actual_trace}); defer engine.freeValue(actual);
    const accepted = try v.js.call(engine, stringify, json, &.{accepted_trace}); defer engine.freeValue(accepted);
    try same(engine, actual, accepted);
}
