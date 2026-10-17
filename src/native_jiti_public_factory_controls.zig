//! Prepared genuine-subject controls. No jobs have run. No fake createRequire,
//! Module, transform, importer or namespace is installed to make them positive.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const importer = @import("extensions/native_jiti_native_import.zig");
const profile = @import("extensions/native_jiti_profile.zig");
const c = em.c;
fn length(engine: *em.Engine, function: c.JSValue, expected: i32) !void {
    const value = try js.get(engine, function, "length"); defer engine.freeValue(value);
    var count: i32 = 0;
    if (c.JS_ToInt32(engine.context, &count, value) < 0) return js.capture(engine);
    try std.testing.expectEqual(expected, count);
}
/// Caller supplies genuine registered/owned module inputs at the physical
/// relative path. Engine registration/real module evaluation is the subject.
pub fn verifyCapturedQueue(engine: *em.Engine, physical_base: c.JSValue, relative_specifier: c.JSValue) !void {
    const function = try importer.create(engine, physical_base); defer engine.freeValue(function);
    try length(engine, function, 1);
    try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    const name = try js.get(engine, function, "name"); defer engine.freeValue(name);
    const text = try engine.toString(name); defer engine.gpa.free(text);
    try std.testing.expectEqualStrings("nativeImport", text);
    const receiver = try js.object(engine); defer engine.freeValue(receiver);
    const first = try js.call(engine, function, receiver, &.{relative_specifier}); defer engine.freeValue(first);
    try std.testing.expect(c.JS_PromiseState(engine.context, first) == c.JS_PROMISE_PENDING);
    try std.testing.expect(engine.captured_exception == null);
    // Raw capability has not adopted/awaited it in its ordinary callback.
    const namespace = try engine.awaitValue(first); defer engine.freeValue(namespace);
    const second = try js.call(engine, function, c.pi_js_undefined(), &.{relative_specifier}); defer engine.freeValue(second);
    const again = try engine.awaitValue(second); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, namespace, again));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first, second));
}
/// This receives a completed REAL profile namespace and original Source user
/// options. The owner must supply the actual external dependency graph first.
pub fn verifyActualNamespaceAndConstruction(engine: *em.Engine, actual_namespace: c.JSValue, actual_filename: c.JSValue, source_options: c.JSValue) !void {
    const factory = try js.get(engine, actual_namespace, "createJiti"); defer engine.freeValue(factory);
    const default = try js.get(engine, actual_namespace, "default"); defer engine.freeValue(default);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, factory, default));
    try std.testing.expect(c.JS_IsConstructor(engine.context, factory));
    try std.testing.expect(!c.JS_IsAsyncFunction(factory));
    try length(engine, factory, 1);
    const first = try js.call(engine, factory, c.pi_js_undefined(), &.{ actual_filename, source_options }); defer engine.freeValue(first);
    try std.testing.expect(c.JS_IsFunction(engine.context, first));
    const options = try js.get(engine, first, "options"); defer engine.freeValue(options);
    const transform = try js.get(engine, options, "transform"); defer engine.freeValue(transform);
    try std.testing.expect(c.JS_IsConstructor(engine.context, transform));
    try length(engine, transform, 0); // actual module-scoped lazyTransform
    var args = [_]c.JSValue{ actual_filename, source_options };
    const constructed = try engine.checked(c.JS_CallConstructor(engine.context, factory, args.len, &args)); defer engine.freeValue(constructed);
    try std.testing.expect(c.JS_IsFunction(engine.context, constructed));
    const constructed_options = try js.get(engine, constructed, "options"); defer engine.freeValue(constructed_options);
    const same_lazy = try js.get(engine, constructed_options, "transform"); defer engine.freeValue(same_lazy);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, transform, same_lazy));
}
/// No fake cache object is used: construct a real Module with the actual
/// constructor, then deliberately do NOT publish it. A namespace cannot leak.
pub fn verifyUnpublishedModuleRejected(engine: *em.Engine, actual_inputs: profile.Inputs) !void {
    var staged = try profile.prepare(engine, actual_inputs); defer staged.deinit();
    var args = [_]c.JSValue{actual_inputs.babel_filename};
    const actual_module = try engine.checked(c.JS_CallConstructor(engine.context, staged.module_constructor, args.len, &args)); defer engine.freeValue(actual_module);
    try std.testing.expect(c.JS_IsUndefined(staged.namespace));
    try std.testing.expectError(error.RequiredActualPublishedNativeBabelModule, profile.complete(engine, &staged, actual_module));
    try std.testing.expect(c.JS_IsUndefined(staged.namespace));
}
/// Entry event must win without consulting any namespace getter/allocating
/// declarations. This is the actual pending slot, not a flagged rejected datum.
pub fn verifyPendingBeforeProfile(engine: *em.Engine, actual_inputs: profile.Inputs, actual_pending_reason: c.JSValue) !void {
    const baseline = engine.native_exception_diagnostics_suppressed;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual_pending_reason));
    try std.testing.expectError(error.JavaScriptException, profile.prepare(engine, actual_inputs));
    const captured = engine.captured_exception orelse return error.MissingActualProfilePendingCapture;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, actual_pending_reason));
    try std.testing.expectEqual(baseline, engine.native_exception_diagnostics_suppressed);
}
