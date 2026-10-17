//! Prepared actual-provider controls. Never supplies a fake TTY/crypto/FS/path,
//! parser/checker/registry or jiti factory to make bootstrap appear complete.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const shared = @import("extensions/native_jiti_shared_dependencies.zig");
fn same(engine: *v.em.Engine, first: c.JSValue, second: c.JSValue) !void { try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second)); }
fn expectCreateError(engine: *v.em.Engine, actual: shared.Inputs, expected: anyerror) !void {
    if (shared.create(engine, actual)) |unexpected| {
        unexpected.deinit(engine);
        return error.UnexpectedSharedDependencySuccess;
    } else |err| try std.testing.expect(err == expected);
}
pub fn verifyCanonicalRepeatedGraph(engine: *v.em.Engine, actual: shared.Inputs) !void {
    const first = try shared.create(engine, actual); defer first.deinit(engine);
    const second = try shared.create(engine, actual); defer second.deinit(engine);
    inline for (std.meta.fields(shared.Exports)) |field| try same(engine, @field(first, field.name), @field(second, field.name));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, first.pathe, first.pathe_utils));
    inline for (.{ first.pathe, first.pathe_utils, first.mlly, first.utilities }) |namespace| {
        const prototype = try engine.checked(c.JS_GetPrototype(engine.context, namespace)); defer engine.freeValue(prototype);
        try std.testing.expect(c.JS_IsNull(prototype));
    }
    const first_syntax = try v.js.get(engine, first.mlly, "hasESMSyntax"); defer engine.freeValue(first_syntax);
    const second_syntax = try v.js.get(engine, second.mlly, "hasESMSyntax"); defer engine.freeValue(second_syntax);
    try same(engine, first_syntax, second_syntax);
    const first_resolver = try v.js.get(engine, first.mlly, "resolvePathSync"); defer engine.freeValue(first_resolver);
    const second_resolver = try v.js.get(engine, second.mlly, "resolvePathSync"); defer engine.freeValue(second_resolver);
    try same(engine, first_resolver, second_resolver);
    try std.testing.expect(!c.JS_IsAsyncFunction(first.dynamic_import));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, first.dynamic_import));
    const length = try v.js.get(engine, first.dynamic_import, "length"); defer engine.freeValue(length);
    try same(engine, length, c.JS_NewInt32(engine.context, 2));
}
/// actual_alias_namespace is the real installed fs/other spelling's export
/// record, not an invented namespace. The canonical import identity is fixed.
pub fn verifyChangedCanonicalInputRejected(engine: *v.em.Engine, actual: shared.Inputs, actual_alias_namespace: c.JSValue) !void {
    const first = try shared.create(engine, actual); defer first.deinit(engine);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual.filesystem, actual_alias_namespace));
    var changed = actual; changed.filesystem = actual_alias_namespace;
    try expectCreateError(engine, changed, error.JitiSharedDependenciesImportsChanged);
    const again = try shared.create(engine, actual); defer again.deinit(engine);
    try same(engine, first.utilities, again.utilities);
}
pub fn verifyPendingBeforeInitialization(engine: *v.em.Engine, actual: shared.Inputs, actual_reason: c.JSValue) !void {
    try std.testing.expect(engine.captured_exception == null);
    const modules = engine.native_module_values.count();
    const namespace_counter = engine.native_namespace_counter;
    const diagnostics = engine.native_exception_diagnostics_suppressed;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, actual_reason));
    try expectCreateError(engine, actual, error.JavaScriptException);
    const reason = engine.captured_exception orelse return error.MissingSharedDependencyPendingReason;
    defer { engine.captured_exception = null; engine.freeValue(reason); }
    try same(engine, reason, actual_reason);
    try std.testing.expectEqual(modules, engine.native_module_values.count());
    try std.testing.expectEqual(namespace_counter, engine.native_namespace_counter);
    try std.testing.expectEqual(diagnostics, engine.native_exception_diagnostics_suppressed);
}
fn observedColorFailure(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    // The REAL Source hasColors runs first with the actual prototype receiver,
    // real env and real OS policy. Only an explicit test fault is added.
    const result = c.JS_Call(context, roots[0], receiver, argc, argv);
    if (c.JS_IsException(result) or c.JS_HasException(context)) return result;
    c.JS_FreeValue(context, result);
    return c.JS_Throw(context, c.JS_DupValue(context, roots[1]));
}
fn observedColorReentry(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = c.JS_Call(context, roots[0], receiver, argc, argv);
    if (c.JS_IsException(result) or c.JS_HasException(context)) return result;
    const entered = c.JS_GetPropertyStr(context, roots[7], "entered"); defer c.JS_FreeValue(context, entered);
    if (c.JS_IsException(entered)) { const pending = c.JS_GetException(context); c.JS_FreeValue(context, result); return c.JS_Throw(context, pending); }
    if (c.JS_ToBool(context, entered) != 0) return result; // Bound even a missing-reservation regression.
    if (c.JS_SetPropertyStr(context, roots[7], "entered", c.pi_js_bool(context, 1)) < 0) { const pending = c.JS_GetException(context); c.JS_FreeValue(context, result); return c.JS_Throw(context, pending); }
    const engine = v.em.Engine.fromContext(context.?);
    const actual: shared.Inputs = .{ .filesystem = roots[1], .node_path = roots[2], .node_url = roots[3], .tty = roots[4], .process = roots[5], .builtin_modules = roots[6] };
    if (shared.create(engine, actual)) |unexpected| {
        unexpected.deinit(engine); c.JS_FreeValue(context, result);
        return c.JS_ThrowTypeError(context, "Partial shared dependency graph escaped during actual hasColors");
    } else |err| {
        if (err != error.JitiSharedDependenciesInitializing) { c.JS_FreeValue(context, result); return c.JS_ThrowTypeError(context, "Unexpected shared dependency reentry error: %s", @as([*:0]const u8, @errorName(err))); }
    }
    return result;
}
/// Real constructor/prototype/method delegate, no color-capability substitute.
/// No partially initialized namespace may escape when actual hasColors reenters.
pub fn verifyRealColorReentry(engine: *v.em.Engine, actual: shared.Inputs) !void {
    try std.testing.expect(!engine.native_module_values.contains("#pi-native:jiti2.7-shared-dependencies"));
    const tty = try v.js.get(engine, actual.tty, "default"); defer engine.freeValue(tty);
    const constructor = try v.js.get(engine, tty, "WriteStream"); defer engine.freeValue(constructor);
    const prototype = try v.js.get(engine, constructor, "prototype"); defer engine.freeValue(prototype);
    const atom = c.JS_NewAtom(engine.context, "hasColors"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    if (c.JS_GetOwnProperty(engine.context, &descriptor, prototype, atom) != 1) return error.RequiredActualTtyHasColorsDescriptor;
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    if (!c.JS_IsFunction(engine.context, descriptor.value) or !c.JS_IsUndefined(descriptor.getter) or !c.JS_IsUndefined(descriptor.setter)) return error.RequiredActualTtyHasColorsDataMethod;
    const control = try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())); defer engine.freeValue(control);
    if (c.JS_DefinePropertyValueStr(engine.context, control, "entered", c.pi_js_bool(engine.context, 0), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    var roots = [_]c.JSValue{ descriptor.value, actual.filesystem, actual.node_path, actual.node_url, actual.tty, actual.process, actual.builtin_modules, control };
    const observer = try engine.checked(c.JS_NewCFunctionData2(engine.context, observedColorReentry, "observedActualHasColorsReentry", 0, 0, roots.len, &roots)); defer engine.freeValue(observer);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, observer), descriptor.flags & c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    defer { _ = c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags & c.JS_PROP_C_W_E); }
    const graph = try shared.create(engine, actual); defer graph.deinit(engine);
    const again = try shared.create(engine, actual); defer again.deinit(engine);
    try same(engine, graph.utilities, again.utilities);
    const entered = try v.js.get(engine, control, "entered"); defer engine.freeValue(entered);
    try std.testing.expect(c.JS_ToBool(engine.context, entered) != 0);
}
/// Fresh exclusive Engine/actual dependencies. A real hasColors failure must
/// roll back the private reservation BEFORE any public namespace is created;
/// restoring the real method then permits one genuine initialization/reuse.
pub fn verifyRealColorInitializationRollback(engine: *v.em.Engine, actual: shared.Inputs, actual_reason: c.JSValue) !void {
    try std.testing.expect(!engine.native_module_values.contains("#pi-native:jiti2.7-shared-dependencies"));
    const tty = try v.js.get(engine, actual.tty, "default"); defer engine.freeValue(tty);
    const constructor = try v.js.get(engine, tty, "WriteStream"); defer engine.freeValue(constructor);
    const prototype = try v.js.get(engine, constructor, "prototype"); defer engine.freeValue(prototype);
    const atom = c.JS_NewAtom(engine.context, "hasColors"); if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    var descriptor: c.JSPropertyDescriptor = undefined;
    if (c.JS_GetOwnProperty(engine.context, &descriptor, prototype, atom) != 1) return error.RequiredActualTtyHasColorsDescriptor;
    defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
    if (!c.JS_IsFunction(engine.context, descriptor.value) or !c.JS_IsUndefined(descriptor.getter) or !c.JS_IsUndefined(descriptor.setter)) return error.RequiredActualTtyHasColorsDataMethod;
    var roots = [_]c.JSValue{ descriptor.value, actual_reason };
    const observer = try engine.checked(c.JS_NewCFunctionData2(engine.context, observedColorFailure, "observedActualHasColors", 0, 0, roots.len, &roots)); defer engine.freeValue(observer);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, observer), descriptor.flags & c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    var restored = false;
    defer { if (!restored) { _ = c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags & c.JS_PROP_C_W_E); } }
    const modules = engine.native_module_values.count();
    const namespaces = engine.native_namespace_counter;
    try expectCreateError(engine, actual, error.JavaScriptException);
    const reason = engine.captured_exception orelse return error.MissingActualSharedColorFailure;
    try same(engine, reason, actual_reason);
    try std.testing.expectEqual(modules, engine.native_module_values.count());
    try std.testing.expectEqual(namespaces, engine.native_namespace_counter);
    engine.captured_exception = null; engine.freeValue(reason);
    if (c.JS_DefinePropertyValue(engine.context, prototype, atom, c.JS_DupValue(engine.context, descriptor.value), descriptor.flags & c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
    restored = true;
    const first = try shared.create(engine, actual); defer first.deinit(engine);
    const again = try shared.create(engine, actual); defer again.deinit(engine);
    try same(engine, first.utilities, again.utilities);
}
