//! Prepared genuine-subject controls. No jobs have run. No fake createRequire,
//! Module, transform, importer or namespace is installed to make them positive.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const importer = @import("extensions/native_jiti_native_import.zig");
const profile = @import("extensions/native_jiti_profile.zig");
const public_factory = @import("extensions/native_jiti_public_factory.zig");
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
    defer { engine.captured_exception = null; engine.freeValue(captured); }
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, captured, actual_pending_reason));
    try std.testing.expectEqual(baseline, engine.native_exception_diagnostics_suppressed);
}
fn count(context: ?*c.JSContext, owner: c.JSValue) i32 {
    const value = c.JS_GetPropertyStr(context, owner, "calls"); defer c.JS_FreeValue(context, value);
    var result: i32 = 0; _ = c.JS_ToInt32(context, &result, value); return result;
}
fn actualCreateRequire(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const actual = c.JS_Call(context, roots[0], c.pi_js_undefined(), argc, argv);
    if (c.JS_IsException(actual) or c.JS_HasException(context)) return actual;
    if (argc == 0 or !c.JS_IsStrictEqual(context, argv[0], roots[1])) return actual;
    // Delegates to the REAL supplied loader. This is instrumentation around
    // actual createRequire/Module/cache, not a successful fake dependency.
    defer c.JS_FreeValue(context, actual);
    var retained = [_]c.JSValue{ actual, roots[2], roots[3] };
    return c.JS_NewCFunctionData2(context, actualBabelRequire, "observedActualBabelRequire", 1, 0, retained.len, &retained);
}
fn actualBabelRequire(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = c.JS_Call(context, roots[0], c.pi_js_undefined(), argc, argv);
    if (c.JS_IsException(result) or c.JS_HasException(context)) return result;
    const previous = count(context, roots[1]);
    if (c.JS_SetPropertyStr(context, roots[1], "calls", c.JS_NewInt32(context, previous + 1)) < 0) { const pending = c.JS_GetException(context); c.JS_FreeValue(context, result); return c.JS_Throw(context, pending); }
    if (previous == 0) {
        c.JS_SetUncatchableError(context, roots[2]);
        _ = c.JS_Throw(context, c.JS_DupValue(context, roots[2]));
    }
    return result;
}
/// Real loader succeeds with its actual backend export, THEN a current host
/// event is left pending. It must win before lazy lexical-cache assignment.
/// A second real call retries loading; a third hits the successfully set cell.
pub fn verifyPendingLazyLoadAndRetry(engine: *em.Engine, actual_inputs: public_factory.Inputs, actual_transform_options: c.JSValue, actual_pending_reason: c.JSValue) !void {
    try std.testing.expect(engine.captured_exception == null);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    const observer = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())); defer engine.freeValue(observer);
    if (c.JS_DefinePropertyValueStr(engine.context, observer, "calls", c.JS_NewInt32(engine.context, 0), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return js.capture(engine);
    var roots = [_]c.JSValue{ actual_inputs.create_require, actual_inputs.module_url, observer, actual_pending_reason };
    const delegated = try engine.checked(c.JS_NewCFunctionData2(engine.context, actualCreateRequire, "observedActualCreateRequire", 1, 0, roots.len, &roots)); defer engine.freeValue(delegated);
    var inputs = actual_inputs; inputs.create_require = delegated;
    const actual_public = try public_factory.create(engine, inputs); defer actual_public.deinit(engine);
    const options = try js.object(engine); defer engine.freeValue(options);
    if (c.JS_DefinePropertyValueStr(engine.context, options, "fsCache", c.pi_js_bool(engine.context, 0), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return js.capture(engine);
    const jiti = try js.call(engine, actual_public.create_jiti, c.pi_js_undefined(), &.{ inputs.physical_filename, options }); defer engine.freeValue(jiti);
    const resolved_options = try js.get(engine, jiti, "options"); defer engine.freeValue(resolved_options);
    const lazy = try js.get(engine, resolved_options, "transform"); defer engine.freeValue(lazy);
    var args = [_]c.JSValue{actual_transform_options};
    const failed = c.JS_Call(engine.context, lazy, c.pi_js_undefined(), args.len, &args);
    try std.testing.expect(c.JS_IsException(failed));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual_pending_reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(engine.last_error == null);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    try std.testing.expectEqual(@as(i32, 1), count(engine.context, observer));
    const retry = try js.call(engine, lazy, c.pi_js_undefined(), &.{actual_transform_options}); defer engine.freeValue(retry);
    try std.testing.expect(c.JS_IsObject(retry));
    try std.testing.expectEqual(@as(i32, 2), count(engine.context, observer));
    const cached = try js.call(engine, lazy, c.pi_js_undefined(), &.{actual_transform_options}); defer engine.freeValue(cached);
    try std.testing.expect(c.JS_IsObject(cached));
    try std.testing.expectEqual(@as(i32, 2), count(engine.context, observer));
}
fn pendingExports(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_SetUncatchableError(context, roots[1]);
    _ = c.JS_Throw(context, c.JS_DupValue(context, roots[1]));
    return c.JS_DupValue(context, roots[0]);
}
/// Instrument the REAL published Module's real exports field, returning its
/// SAME backend while leaving an actual current VM event. No namespace may
/// be installed and the existing CJS Module/cache identity must stay intact.
pub fn verifyPendingModuleGetterBeforeNamespace(engine: *em.Engine, staged: *profile.Prepared, actual_module: c.JSValue, actual_pending_reason: c.JSValue) !void {
    try std.testing.expect(engine.captured_exception == null);
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    const actual_exports = try js.get(engine, actual_module, "exports"); defer engine.freeValue(actual_exports);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual_exports, staged.native_babel_exports));
    const atom = c.JS_NewAtom(engine.context, "exports"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    if (c.JS_GetOwnProperty(engine.context, &descriptor, actual_module, atom) != 1) return error.RequiredActualBabelOwnExports;
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    if (!c.JS_IsUndefined(descriptor.getter) or !c.JS_IsUndefined(descriptor.setter)) return error.RequiredActualBabelDataExports;
    var roots = [_]c.JSValue{ actual_exports, actual_pending_reason };
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, pendingExports, "get exports", 0, 0, roots.len, &roots)); defer engine.freeValue(getter);
    if (c.JS_DefinePropertyGetSet(engine.context, actual_module, atom, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), descriptor.flags & (c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE)) < 0) return js.capture(engine);
    defer { _ = c.JS_DefinePropertyValue(engine.context, actual_module, atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags & c.JS_PROP_C_W_E); }
    try std.testing.expectError(error.JavaScriptException, profile.complete(engine, staged, actual_module));
    const reason = engine.captured_exception orelse return error.MissingActualModuleGetterEvent;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual_pending_reason));
    try std.testing.expect(c.JS_IsUndefined(staged.namespace));
    const cache = try js.get(engine, staged.module_constructor, "_cache"); defer engine.freeValue(cache);
    const current = try js.getKey(engine, cache, staged.babel_filename); defer engine.freeValue(current);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, current, actual_module));
    try std.testing.expect(engine.last_error == null);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
    engine.captured_exception = null; engine.freeValue(reason);
}
pub fn verifyPendingBeforeComplete(engine: *em.Engine, staged: *profile.Prepared, actual_module: c.JSValue, actual_pending_reason: c.JSValue) !void {
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual_pending_reason));
    try std.testing.expectError(error.JavaScriptException, profile.complete(engine, staged, actual_module));
    try std.testing.expect(staged.phase == .prepared);
    try std.testing.expect(c.JS_IsUndefined(staged.namespace));
    const reason = engine.captured_exception orelse return error.MissingActualCompleteEntryEvent;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, actual_pending_reason));
    engine.captured_exception = null; engine.freeValue(reason);
}
