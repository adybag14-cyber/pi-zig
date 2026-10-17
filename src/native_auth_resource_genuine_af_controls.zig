//! Actual-module integration controls, SOURCE ONLY/unrun. The embedding SDK
//! owner supplies its genuine Auth namespace and DefaultResourceLoader class.
//! This creates no Completed record, dependency stub, transport, or proxy.
const std = @import("std");
const em = @import("extensions/engine.zig");
const v = @import("extensions/native_ai_provider_values.zig");
const c = em.c;
const Scope = v.Scope;
fn publish(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    try @import("extensions/native_js_values.zig").define(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn actualSubject(engine: *em.Engine, auth_exports: c.JSValue, resource_constructor: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthModuleOwner;
    if (!c.JS_IsStrictEqual(engine.context, try s.get(owner, "exports"), auth_exports)) return error.RequiredGenuineSdkAuthNamespace;
    const auth = try s.get(auth_exports, "AuthStorage");
    if (!c.JS_IsConstructor(engine.context, auth) or !c.JS_IsConstructor(engine.context, resource_constructor)) return error.RequiredActualBootstrapClasses;
    const prototype = try s.get(auth, "prototype");
    inline for (.{ "reloadFromStorageAsync", "readLatestData", "read", "modify", "delete", "list" }) |name| {
        const method = try s.get(prototype, name);
        if (!c.JS_IsAsyncFunction(method) or c.JS_IsConstructor(engine.context, method)) return error.RequiredGenuineAuthAsyncFunction;
    }
    const reload = try s.get(try s.get(resource_constructor, "prototype"), "reload");
    if (!c.JS_IsAsyncFunction(reload) or c.JS_IsConstructor(engine.context, reload)) return error.RequiredGenuineResourceReloadAsyncFunction;
    const subject = try s.object();
    try s.put(subject, "AuthStorage", auth);
    try s.put(subject, "DefaultResourceLoader", resource_constructor);
    try engine.registerValueModule("actual-auth-reload-control-subject", subject);
}
/// Caller must provide the exact ResourceLoader constructor returned by the
/// genuine SDK resource assembly. The Auth namespace is additionally checked
/// against its private installed module owner. Each entry uses a fresh realm.
pub fn observeActualBootstrapBindings(engine: *em.Engine, auth_exports: c.JSValue, resource_constructor: c.JSValue) !c.JSValue {
    try actualSubject(engine, auth_exports, resource_constructor);
    const source = try std.mem.concat(engine.gpa, u8, &.{
        "import{AuthStorage,DefaultResourceLoader}from'actual-auth-reload-control-subject';\n",
        @embedFile("extensions/fixtures/auth-storage-resource-genuine-af-observer.mjs"),
        "\nexport const observations={auth:await observeAuthStorage(AuthStorage),reload:await observeResourceReload(DefaultResourceLoader)};\n",
    });
    defer engine.gpa.free(source);
    const namespace = try engine.evalModule(source, "actual-auth-reload-genuine-af-controls.mjs");
    errdefer engine.freeValue(namespace);
    // Actual retained callbacks must have the VM async bit, independently of
    // Source-visible prototype/tag checks in the common original observer.
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const callbacks = try s.get(try s.global("globalThis"), "__observedAuthAsyncCallbacks");
    var count: u32 = 0;
    if (c.JS_ToUint32(engine.context, &count, try s.get(callbacks, "length")) < 0) return v.js.capture(engine);
    if (count != 3) return error.ActualStorageCallbackControlCount;
    for (0..count) |index| {
        const callback = try v.at(&s, callbacks, @intCast(index));
        if (!c.JS_IsAsyncFunction(callback) or c.JS_IsConstructor(engine.context, callback)) return error.RequiredActualAsyncStorageCallback;
    }
    return namespace;
}
fn markedRejectionData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    // Deliberate test DATA producer: clear the actual pending event, then
    // return its owned real private-tagged Error as a successful value. This
    // is not an actual new throw; Promise.reject receives it as borrowed DATA.
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    return reason;
}
pub fn verifyActualRejectedData(engine: *em.Engine, auth_exports: c.JSValue, resource_constructor: c.JSValue) !c.JSValue {
    try actualSubject(engine, auth_exports, resource_constructor);
    const make = try engine.checked(c.JS_NewCFunction(engine.context, markedRejectionData, "makeMarkedRejectionData", 0));
    defer engine.freeValue(make);
    try publish(engine, "makeMarkedRejectionData", make);
    const source = try std.mem.concat(engine.gpa, u8, &.{
        "import{AuthStorage,DefaultResourceLoader}from'actual-auth-reload-control-subject';\n",
        @embedFile("extensions/fixtures/auth-storage-resource-genuine-af-observer.mjs"),
        "\nexport const proof=await verifyNativeRejectedData(AuthStorage,DefaultResourceLoader,makeMarkedRejectionData);\n",
    });
    defer engine.gpa.free(source);
    return engine.evalModule(source, "actual-auth-reload-rejected-data-controls.mjs");
}
fn throwSameMarked(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Throw(context, c.JS_DupValue(context, roots[0]));
}
/// The same marked object is DATA in verifyActualRejectedData, but an actual
/// new pending throw here. This guards against a blanket flag-clearing repair.
pub fn verifyActualCurrentEvent(engine: *em.Engine, auth_exports: c.JSValue, resource_constructor: c.JSValue) !void {
    try actualSubject(engine, auth_exports, resource_constructor);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const auth = try s.get(auth_exports, "AuthStorage");
    const store = try s.invoke(auth, "inMemory", &.{});
    const reason = try s.own(markedRejectionData(engine.context, c.pi_js_undefined(), 0, null));
    if (!c.JS_IsObject(reason) or !c.JS_IsUncatchableError(reason)) return error.RequiredActualMarkedReasonFixture;
    var captures = [_]c.JSValue{reason};
    const throwing = try s.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, throwSameMarked, "throwSameMarked", 0, 0, captures.len, &captures)));
    try s.set(store, "readLatestData", throwing);
    const read = try s.get(try s.get(auth, "prototype"), "read");
    const provider = try s.text("fixture");
    var arguments = [_]c.JSValue{provider};
    const attempted = engine.checked(c.JS_Call(engine.context, read, store, arguments.len, &arguments));
    if (attempted) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualCurrentFatalEvent;
    } else |err| if (err != error.JavaScriptException) return err;
    const actual = engine.captured_exception orelse return error.MissingActualCurrentReason;
    if (!c.JS_IsStrictEqual(engine.context, actual, reason) or !c.JS_IsUncatchableError(actual)) return error.ActualCurrentReasonWasReplaced;
}
