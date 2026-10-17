//! Prepared controls require a real Module8a and actual nested jiti/context.
//! No fabricated factory, empty registry, or surrogate cache can supply Subject.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const evaluation = @import("extensions/native_jiti_eval_module.zig");
pub const Subject = struct { inputs: evaluation.Inputs, request: evaluation.TransformedRequest };
fn install(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try v.js.define(engine, global, name, c.JS_DupValue(engine.context, value));
}
/// Real fixture exports its own moduleRecord, and real context has moduleCache
/// enabled. Source frontend/resolver/nested factory must already be complete.
pub fn verifyRealModuleAndCaches(engine: *v.em.Engine, actual: Subject) !void {
    const result = try evaluation.evaluateTransformed(engine, actual.inputs, actual.request); defer engine.freeValue(result);
    const module = try v.js.get(engine, result, "moduleRecord"); defer engine.freeValue(module);
    const constructor = try v.js.get(engine, module, "constructor"); defer engine.freeValue(constructor);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, constructor, actual.inputs.module_constructor));
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, module)); defer engine.freeValue(prototype);
    const expected_prototype = try v.js.get(engine, actual.inputs.module_constructor, "prototype"); defer engine.freeValue(expected_prototype);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, prototype, expected_prototype));
    const parent_entry = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(parent_entry);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, module, parent_entry));
    const require = try v.js.get(engine, actual.request.context, "nativeRequire"); defer engine.freeValue(require);
    const cache = try v.js.get(engine, require, "cache"); defer engine.freeValue(cache);
    const native_entry = try v.js.getKey(engine, cache, actual.request.filename); defer engine.freeValue(native_entry);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, module, native_entry));
    const loaded = try v.js.get(engine, module, "loaded"); defer engine.freeValue(loaded);
    try std.testing.expect(c.JS_ToBool(engine.context, loaded) == 1);
    const exported = try v.js.get(engine, module, "exports"); defer engine.freeValue(exported);
    // This actual profile uses interopDefault=false, preserving exact exports.
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, exported));
}
/// Actual async fixture suspends with a user-controlled Promise. The real
/// native slot supplies its release function; this control does not replace
/// nested jiti/import/require with a fake callable or manual thenable runner.
pub fn verifyAsyncPublicationAndFinish(engine: *v.em.Engine, actual: Subject, actual_release: c.JSValue) !void {
    const pending = try evaluation.evaluateTransformed(engine, actual.inputs, actual.request); defer engine.freeValue(pending);
    const partial = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(partial);
    const before = try v.js.get(engine, partial, "loaded"); defer engine.freeValue(before);
    try std.testing.expect(c.JS_ToBool(engine.context, before) == 0);
    const released = try v.js.call(engine, actual_release, c.pi_js_undefined(), &.{}); defer engine.freeValue(released);
    const result = try engine.awaitValue(pending); defer engine.freeValue(result);
    const after = try v.js.get(engine, partial, "loaded"); defer engine.freeValue(after);
    try std.testing.expect(c.JS_ToBool(engine.context, after) == 1);
    const module = try v.js.get(engine, result, "moduleRecord"); defer engine.freeValue(module);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, module, partial));
}
/// Actual profile uses a source-bound custom onError that returns, plus an
/// actual throwing fixture. Source observation must be accepted independently;
/// none of its expected reason/message/trace bytes are created by this helper.
pub fn verifyAcceptedReturningOnError(engine: *v.em.Engine, actual: Subject, actual_trace: c.JSValue, accepted_source_trace: c.JSValue) !void {
    const result = try evaluation.evaluateTransformed(engine, actual.inputs, actual.request); defer engine.freeValue(result);
    try install(engine, "ActualJitiEvalTrace", actual_trace);
    try install(engine, "AcceptedJitiEvalTrace", accepted_source_trace);
    const checked = try engine.evalModule(
        \\if(JSON.stringify(ActualJitiEvalTrace)!==JSON.stringify(AcceptedJitiEvalTrace))throw Error('actual returning onError Source trace');export const passed=true;
    , "jiti-eval-returning-onerror-accepted-reference.mjs");
    defer engine.freeValue(checked);
    const record = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(record);
    const loaded = try v.js.get(engine, record, "loaded"); defer engine.freeValue(loaded);
    try std.testing.expect(c.JS_ToBool(engine.context, loaded) == 1);
    const exports = try v.js.get(engine, record, "exports"); defer engine.freeValue(exports);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, exports));
}
/// Negative binding control begins with the real subject, removes one required
/// callable, and verifies preflight failure leaves its actual cache unchanged.
pub fn verifyMissingBindingBeforePublication(engine: *v.em.Engine, actual: Subject) !void {
    const before = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(before);
    var inputs = actual.inputs; inputs.nested_create_jiti = c.pi_js_undefined();
    try std.testing.expectError(error.RequiredActualJitiEvaluationBinding, evaluation.evaluateTransformed(engine, inputs, actual.request));
    const after = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before, after));
}
/// Real original-source TypeScript unsupported by API12a rejects before any
/// Module/cache publication. Positive supported construction is not inferred.
pub fn verifyUnsupportedBeforePublication(engine: *v.em.Engine, actual: Subject) !void {
    const before = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(before);
    var request = actual.request; request.source = "import value from './child.ts'; export const answer=value;";
    try std.testing.expectError(error.UnsupportedModuleImport, evaluation.evaluateTransformed(engine, actual.inputs, request));
    const after = try v.js.getKey(engine, actual.request.parent_cache, actual.request.filename); defer engine.freeValue(after);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before, after));
}
