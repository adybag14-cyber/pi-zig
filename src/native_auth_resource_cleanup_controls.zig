//! Prospective integration controls for the actual Auth read continuation.
//! Requires the genuine SDK-owned namespace and the separately composed C DATA
//! producer semantics. No bootstrap, class or transport substitute is created.
//! SOURCE ONLY: unregistered, uncompiled and unrun.
const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const c = em.c;
const Cleanup = enum { ordinary, fatal, rejected_data_diagnostic, raw_pending };
const Route = enum { read, reload, sync_reload };
const Probe = struct {
    engine: *em.Engine,
    class: c.JSClassID = 0,
    ordinary_cleanup: c.JSValue,
    actual_fatal: c.JSValue = c.pi_js_undefined(),
    cleanup: Cleanup,
    caught_data: bool = false,
    data_generation: u64 = 0,
    initially_marked: bool = false,
    references: usize = 1,
    getters: usize = 0,
    finalized: usize = 0,
};
// A failed control may leave a VM-owned carrier. Its counted heap probe stays
// alive until that carrier actually retires; no finalizer borrows a stack frame.
threadlocal var active: ?*Probe = null;
fn release(p: *Probe) void {
    p.references -= 1;
    if (p.references != 0) return;
    p.engine.freeValue(p.ordinary_cleanup);
    p.engine.freeValue(p.actual_fatal);
    p.engine.gpa.destroy(p);
}
fn retireCarrier(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    defer release(p);
    p.finalized += 1;
    if (p.cleanup == .fatal or p.cleanup == .raw_pending) {
        if (p.cleanup == .fatal) _ = p.engine.throwNativeOutOfMemoryFatal() else _ = p.engine.throwNativeOutOfMemory();
        // Record identity without consuming the actual pending event. This is
        // an actual newly published native fatal, not marked rejected DATA.
        const reason = c.JS_GetException(p.engine.context);
        p.initially_marked = c.JS_IsUncatchableError(reason);
        if (c.JS_IsUndefined(p.actual_fatal)) p.actual_fatal = c.JS_DupValue(p.engine.context, reason);
        _ = c.JS_Throw(p.engine.context, reason);
    } else if (p.cleanup == .rejected_data_diagnostic) {
        // A genuine caught Await rejection leaves a diagnostic, not a pending
        // throw. Its new private tag and historical bit must not promote A.
        _ = p.engine.throwNativeOutOfMemory();
        const data = c.JS_GetException(p.engine.context);
        defer p.engine.freeValue(data);
        c.JS_SetUncatchableError(p.engine.context, data);
        p.data_generation = c.pi_js_native_allocation_error_generation(data);
        var resolving: [2]c.JSValue = undefined;
        const promise = c.JS_NewPromiseCapability(p.engine.context, &resolving);
        if (c.JS_IsException(promise)) return;
        defer p.engine.freeValue(promise);
        var arguments = [_]c.JSValue{data};
        const rejected = c.JS_Call(p.engine.context, resolving[1], c.pi_js_undefined(), arguments.len, &arguments);
        p.engine.freeValue(rejected);
        p.engine.freeValue(resolving[0]);
        p.engine.freeValue(resolving[1]);
        const attempted = p.engine.awaitValueOnly(promise);
        if (attempted) |value| p.engine.freeValue(value) else |err| p.caught_data = err == error.JavaScriptException;
    } else {
        _ = c.JS_Throw(p.engine.context, c.JS_DupValue(p.engine.context, p.ordinary_cleanup));
    }
}
fn credential(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p = active orelse return c.JS_ThrowInternalError(context, "No active Auth cleanup control");
    p.getters += 1;
    const value = c.JS_NewObjectClass(context, p.class);
    if (c.JS_IsException(value)) return value;
    p.references += 1;
    _ = c.JS_SetOpaque(value, p);
    // No native or guest reference is retained here. Auth's continuation
    // becomes its sole holder before options.signal.throwIfAborted throws A.
    return value;
}
fn throwCredential(context: ?*c.JSContext, self: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = credential(context, self, argc, args);
    if (c.JS_IsException(value)) return value;
    return c.JS_Throw(context, value);
}
fn expose(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
/// Invoke once per fresh genuine SDK realm. false asserts ordinary A survives
/// ordinary native cleanup B; true asserts newly emitted native fatal C wins A.
/// These are native temporary-retirement controls, not Source guest finally.
pub fn verifyActualReadRetirement(engine: *em.Engine, auth_exports: c.JSValue, fatal_cleanup: bool) !void {
    return verifyActualRetirement(engine, auth_exports, c.pi_js_undefined(), if (fatal_cleanup) .fatal else .ordinary, .read);
}
pub fn verifyActualReadCleanupDiagnostic(engine: *em.Engine, auth_exports: c.JSValue) !void {
    return verifyActualRetirement(engine, auth_exports, c.pi_js_undefined(), .rejected_data_diagnostic, .read);
}
pub fn verifyActualSyncReloadCaughtReason(engine: *em.Engine, auth_exports: c.JSValue) !void {
    return verifyActualRetirement(engine, auth_exports, c.pi_js_undefined(), .raw_pending, .sync_reload);
}
/// Caller supplies the exact ResourceLoader constructor from the genuine SDK
/// resource assembly. A borrowed receiver is an explicit method caller input;
/// it does not stand in for an assembled loader or its real module dependencies.
pub fn verifyActualReloadRetirement(engine: *em.Engine, resource_constructor: c.JSValue, fatal_cleanup: bool) !void {
    return verifyActualRetirement(engine, c.pi_js_undefined(), resource_constructor, if (fatal_cleanup) .fatal else .ordinary, .reload);
}
pub fn verifyActualReloadCleanupDiagnostic(engine: *em.Engine, resource_constructor: c.JSValue) !void {
    return verifyActualRetirement(engine, c.pi_js_undefined(), resource_constructor, .rejected_data_diagnostic, .reload);
}
fn verifyActualRetirement(engine: *em.Engine, auth_exports: c.JSValue, resource_constructor: c.JSValue, cleanup: Cleanup, route: Route) !void {
    if (active != null) return error.AuthCleanupControlAlreadyActive;
    var s: v.Scope = .{ .engine = engine };
    defer s.deinit();
    if (route != .reload) {
        const owner = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthModuleOwner;
        if (!c.JS_IsStrictEqual(engine.context, try s.get(owner, "exports"), auth_exports)) return error.RequiredGenuineSdkAuthNamespace;
        const auth = try s.get(auth_exports, "AuthStorage");
        const read = try s.get(try s.get(auth, "prototype"), "read");
        if (!c.JS_IsAsyncFunction(read)) return error.RequiredGenuineAuthAsyncRead;
        try expose(engine, "__actualAuthStorage", auth);
    } else {
        if (!c.JS_IsConstructor(engine.context, resource_constructor)) return error.RequiredGenuineResourceLoaderConstructor;
        const reload = try s.get(try s.get(resource_constructor, "prototype"), "reload");
        if (!c.JS_IsAsyncFunction(reload)) return error.RequiredGenuineResourceAsyncReload;
        try expose(engine, "__actualResourceReload", reload);
    }
    const ordinary = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    const p = try engine.gpa.create(Probe);
    p.* = .{ .engine = engine, .ordinary_cleanup = c.JS_DupValue(engine.context, ordinary), .cleanup = cleanup };
    defer release(p);
    _ = c.JS_NewClassID(engine.runtime, &p.class);
    const definition: c.JSClassDef = .{ .class_name = "Actual Auth sole credential retirement", .finalizer = retireCarrier };
    if (c.JS_NewClass(engine.runtime, p.class, &definition) < 0) return error.OutOfMemory;
    const getter = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, if (route == .sync_reload) throwCredential else credential, "actual carrier control", 0)));
    try expose(engine, "__credentialRetirementGetter", getter);
    active = p;
    defer active = null;
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const generation = engine.native_allocation_generation;
    const source: []const u8 = if (route == .sync_reload)
        \\const store=__actualAuthStorage.inMemory();
        \\globalThis.__authCleanupCoercions=0;
        \\store.parseStorageData=__credentialRetirementGetter;
        \\store.reload();
        \\export const unexpectedCompletion=true;
    else if (route == .read)
        \\const store=__actualAuthStorage.inMemory();
        \\const ordinary={toString(){globalThis.__authCleanupCoercions++;return 'ordinary A'}};
        \\globalThis.__authCleanupCoercions=0;
        \\const data={};
        \\Object.defineProperty(data,'fixture',{get:__credentialRetirementGetter});
        \\store.readLatestData=async function(){return data};
        \\const signal={throwIfAborted(){throw ordinary}};
        \\export let caughtOriginal=false;
        \\try{await store.read('fixture',{signal})}catch(reason){caughtOriginal=reason===ordinary}
        \\export const coercions=globalThis.__authCleanupCoercions;
    else
        \\const ordinary={toString(){globalThis.__authCleanupCoercions++;return 'ordinary A'}};
        \\globalThis.__authCleanupCoercions=0;
        \\const loader={};
        \\Object.defineProperty(loader,'loaded',{get:__credentialRetirementGetter});
        \\const options={get resolveProjectTrust(){throw ordinary}};
        \\export let caughtOriginal=false;
        \\try{await __actualResourceReload.call(loader,options)}catch(reason){caughtOriginal=reason===ordinary}
        \\export const coercions=globalThis.__authCleanupCoercions;
    ;
    const evaluated = engine.evalModule(source, "actual-auth-read-native-retirement-control.mjs");
    try std.testing.expect(engine.native_fatal_invocation == invocation);
    if (cleanup == .fatal or cleanup == .raw_pending) {
        if (evaluated) |unexpected| {
            engine.freeValue(unexpected);
            return error.ExpectedActualAuthRetirementFatal;
        } else |err| if (err != error.JavaScriptException) return err;
        const actual = c.JS_DupValue(engine.context, engine.captured_exception orelse return error.MissingActualAuthRetirementFatal);
        defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsObject(p.actual_fatal));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, p.actual_fatal));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        if (cleanup == .raw_pending) try std.testing.expect(!p.initially_marked);
        const tagged = c.pi_js_native_allocation_error_generation(actual);
        try std.testing.expect(tagged != 0 and tagged -% generation != 0 and tagged -% generation <= engine.native_allocation_generation -% generation);
        // Own the terminal fatal separately before reading the fixture's own
        // numeric data property. No getter/reporter or guest code is executed.
        try std.testing.expect(!c.JS_HasException(engine.context));
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const count = c.JS_GetPropertyStr(engine.context, global, "__authCleanupCoercions");
        defer engine.freeValue(count);
        try std.testing.expect(!c.JS_IsException(count) and c.JS_IsNumber(count));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0)));
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception orelse return error.LostActualAuthRetirementFatal, actual));
    } else {
        const namespace = try evaluated;
        defer engine.freeValue(namespace);
        try std.testing.expect(s.truthy(try s.get(namespace, "caughtOriginal")));
        try std.testing.expect(s.equal(try s.get(namespace, "coercions"), c.JS_NewInt32(engine.context, 0)));
        try std.testing.expect(engine.captured_exception == null);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
    if (cleanup == .rejected_data_diagnostic) {
        try std.testing.expect(p.caught_data);
        try std.testing.expect(p.data_generation != 0 and p.data_generation -% generation != 0 and p.data_generation -% generation <= engine.native_allocation_generation -% generation);
        try std.testing.expect(c.JS_IsUndefined(p.actual_fatal));
    }
    try std.testing.expectEqual(@as(usize, 1), p.getters);
    try std.testing.expectEqual(@as(usize, 1), p.finalized);
    try std.testing.expectEqual(suppression, engine.native_exception_diagnostics_suppressed);
}
