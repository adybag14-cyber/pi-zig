//! Genuine application-owned Auth namespace is mandatory. No resolver/FS/module
//! substitute is manufactured; the actual current SDK owner supplies bindings.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const owned = @import("extensions/native_sdk_owned_completion.zig");
fn publish(engine: *v.em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    try @import("extensions/native_sdk.zig").put(engine, global, name, c.JS_DupValue(engine.context, value));
}
fn actual(engine: *v.em.Engine, exports: c.JSValue, root: c.JSValue) !void {
    var scope: v.Scope = .{ .engine = engine }; defer scope.deinit();
    const owner = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthOwner;
    if (!scope.equal(try scope.get(owner, "exports"), exports)) return error.RequiredActualAuthNamespaceIdentity;
    const constructor = try scope.get(exports, "ReadOnlyAuthStorage");
    if (!c.JS_IsConstructor(engine.context, constructor)) return error.RequiredActualReadonlyConstructor;
    const prototype = try scope.get(constructor, "prototype");
    inline for (.{ "read", "list", "modify", "delete" }) |name| {
        const method = try scope.get(prototype, name);
        if (!c.JS_IsAsyncFunction(method) or c.JS_IsConstructor(engine.context, method)) return error.RequiredGenuineReadonlyAsyncMethod;
    }
    if (c.JS_IsAsyncFunction(try scope.get(prototype, "load"))) return error.RequiredOrdinaryReadonlyLoad;
    const read_stored = try scope.get(exports, "readStoredCredential");
    if (!c.JS_IsFunction(engine.context, read_stored) or c.JS_IsAsyncFunction(read_stored) or !c.JS_IsConstructor(engine.context, read_stored)) return error.RequiredOrdinaryReadStoredCredential;
    try publish(engine, "ActualReadonlyAuthStorage", constructor);
    try publish(engine, "actualReadStoredCredential", read_stored);
    try publish(engine, "actualReadonlyRoot", root);
}
fn run(engine: *v.em.Engine, tail: []const u8) !c.JSValue {
    const source = try std.mem.concat(engine.gpa, u8, &.{ @embedFile("extensions/fixtures/auth-readonly-genuine-af-observer.mjs"), "\n", tail });
    defer engine.gpa.free(source);
    return engine.evalModule(source, "actual-readonly-genuine-af-observer.mjs");
}
pub fn observeActual(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !c.JSValue {
    try actual(engine, auth_exports, root);
    return run(engine, "export const observations=await observeReadonly(ActualReadonlyAuthStorage,actualReadStoredCredential,actualReadonlyRoot);");
}
fn data(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    _ = v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
    const value = c.JS_GetException(context);c.JS_SetUncatchableError(context, value);return value;
}
pub fn verifyData(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !c.JSValue {
    try actual(engine, auth_exports, root);
    const make = try engine.checked(c.JS_NewCFunction(engine.context, data, "actualReadonlyData", 0));defer engine.freeValue(make);
    try publish(engine, "actualReadonlyData", make);
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const result = try run(engine, "export const observations=await verifyReadonlyData(ActualReadonlyAuthStorage,actualReadonlyRoot,actualReadonlyData);");
    errdefer engine.freeValue(result);
    if (engine.captured_exception != null or c.JS_HasException(engine.context)) return error.HandledReadonlyDataRetainedAsDiagnostic;
    if (engine.native_exception_diagnostics_suppressed != suppression or engine.native_fatal_invocation != invocation) return error.ReadonlyDataUnbalancedBoundary;
    return result;
}
const CurrentProbe = struct { engine: *v.em.Engine, reason: c.JSValue = c.pi_js_undefined(), calls: usize = 0 };
fn freeCurrent(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *CurrentProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, p.reason);p.engine.gpa.destroy(p);
}
fn markCurrent(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const p: *CurrentProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, p.reason, marker);
}
fn current(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p: *CurrentProbe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    p.calls += 1;
    _ = p.engine.throwNativeOutOfMemoryFatal(); // Actual fresh native producer.
    const reason = c.JS_GetException(context);
    if (c.JS_IsUndefined(p.reason)) p.reason = c.JS_DupValue(context, reason);
    return c.JS_Throw(context, reason);
}
pub fn verifyCurrent(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !void {
    try actual(engine, auth_exports, root);
    var scope: v.Scope = .{ .engine = engine };defer scope.deinit();
    var class: c.JSClassID = 0;_ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Readonly actual current OOM probe", .finalizer = freeCurrent, .gc_mark = markCurrent };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const holder = try owned.ownRoot(&scope, try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    const p = try engine.gpa.create(CurrentProbe);p.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(holder, p);
    var roots = [_]c.JSValue{holder};
    const throwing = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, current, "actualReadonlyCurrent", 0, 0, roots.len, &roots)));
    try publish(engine, "actualReadonlyCurrent", throwing);
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const generation = engine.native_allocation_generation;
    const evaluated = run(engine,
        \\globalThis.actualReadonlyAfterFatal=0;
        \\const store=new ActualReadonlyAuthStorage(path.join(actualReadonlyRoot,'current.json'));
        \\await store.list({signal:{throwIfAborted:actualReadonlyCurrent}});
        \\actualReadonlyAfterFatal++;export const unexpected=true;
    );
    if (evaluated) |value| {engine.freeValue(value);return error.ExpectedActualReadonlyFatal;}else |err|if(err!=error.JavaScriptException)return err;
    const caught = engine.captured_exception orelse return error.MissingActualReadonlyFatal;
    if (!c.JS_IsStrictEqual(engine.context, caught, p.reason) or !c.JS_IsUncatchableError(caught) or p.calls != 1) return error.ActualReadonlyFatalIdentity;
    const tagged = c.pi_js_native_allocation_error_generation(caught);
    if (tagged == 0 or tagged -% generation == 0 or tagged -% generation > engine.native_allocation_generation -% generation) return error.RequiredNewReadonlyFatalProducer;
    const global = c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const count = c.JS_GetPropertyStr(engine.context, global, "actualReadonlyAfterFatal");defer engine.freeValue(count);
    if (!c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0))) return error.ActualReadonlyFatalContinued;
    if (engine.native_exception_diagnostics_suppressed != suppression or engine.native_fatal_invocation != invocation) return error.ReadonlyCurrentUnbalancedBoundary;
}
fn actualGc(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    c.JS_RunGC(v.em.Engine.fromContext(context.?).runtime);
    return c.pi_js_undefined();
}
pub fn verifySignalRetirement(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !c.JSValue {
    try actual(engine, auth_exports, root);
    const gc = try engine.checked(c.JS_NewCFunction(engine.context, actualGc, "actualReadonlyGc", 0));defer engine.freeValue(gc);
    try publish(engine, "actualReadonlyGc", gc);
    const prior = try engine.eval(
        \\(()=>{let target={retirement:'prior signal job'};globalThis.weakReadonlyCheck=new WeakRef(target);
        \\globalThis.takeReadonlyCheck=()=>{const result=target;target=undefined;return result}})();
    , "readonly-check-prior-job", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(prior);
    c.JS_ClearKeptObjects(engine.runtime);
    return run(engine,
        \\const store=new ActualReadonlyAuthStorage(path.join(actualReadonlyRoot,'signal-retirement.json'));
        \\let inspected=false;
        \\store.load=function(){actualReadonlyGc();assert(weakReadonlyCheck.deref()===undefined,'completed signal check retains ignored return');inspected=true;return {}};
        \\await store.read('absent',{signal:{throwIfAborted(){return takeReadonlyCheck()}}});
        \\assert(inspected,'actual later load must run');export const proof=true;
    );
}
pub fn verifyReadonlyFactoryPending(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !void { return pendingFactory(engine, auth_exports, root, false); }
pub fn verifyAuthCarrierPending(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue) !void { return pendingFactory(engine, auth_exports, root, true); }
fn pendingFactory(engine: *v.em.Engine, auth_exports: c.JSValue, root: c.JSValue, comptime carrier: bool) !void {
    try actual(engine, auth_exports, root);
    var scope: v.Scope = .{ .engine = engine };defer scope.deinit();
    const owner = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner").?;
    const get_agent_dir = try scope.get(owner, "getAgentDir");
    const resolver = try scope.get(owner, "resolveConfigValue");
    const command = try scope.get(owner, "isCommandConfigValue");
    const imports = try scope.object();
    if (carrier) {
        const platform = engine.native_module_values.get("pi-native:actual-sdk-filesystem-platform") orelse return error.RequiredActualSdkPlatform;
        try scope.put(imports, "FileAuthStorageBackend", try scope.get(auth_exports, "FileAuthStorageBackend"));
        try scope.put(imports, "getFileRevision", try scope.get(try scope.get(platform, "pathUtilities"), "getFileRevision"));
        try scope.put(imports, "getAgentDir", get_agent_dir);
        try scope.put(imports, "resolveConfigValue", resolver);
        try scope.put(imports, "isCommandConfigValue", command);
    }
    const prepared = try engine.eval(
        \\globalThis.directReadonlyFactoryCoercions=0;
        \\globalThis.directReadonlyFactoryReason={toString(){directReadonlyFactoryCoercions++;return 'ordinary factory A'}};
    , "actual-readonly-factory-reason", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(prepared);
    const reason = try scope.get(try scope.global("globalThis"), "directReadonlyFactoryReason");
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const modules = engine.native_module_values.count();
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    c.JS_SetMemoryLimit(engine.runtime, 1);
    const attempted = if (carrier)
        @import("extensions/native_auth_storage_production.zig").create(engine, imports)
    else
        @import("extensions/native_auth_readonly_production.zig").create(engine, .{ .get_agent_dir = get_agent_dir, .resolve_config_value = resolver, .is_command_config_value = command });
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    if (attempted) |value| {engine.freeValue(value);return error.ExpectedActualFactoryPendingFirst;}else |err|if(err!=error.JavaScriptException)return err;
    if (!c.JS_IsStrictEqual(engine.context, engine.captured_exception orelse return error.MissingActualFactoryPendingReason, reason)) return error.ActualFactoryPendingIdentity;
    if (engine.native_module_values.count() != modules) return error.ActualFactoryEnteredChildInstall;
    if (engine.native_exception_diagnostics_suppressed != suppression or engine.native_fatal_invocation != invocation) return error.ActualFactoryUnbalancedBoundary;
    const global = c.JS_GetGlobalObject(engine.context);defer engine.freeValue(global);
    const count = c.JS_GetPropertyStr(engine.context, global, "directReadonlyFactoryCoercions");defer engine.freeValue(count);
    if (!c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0))) return error.ActualFactoryDiagnosedCaughtReason;
}
