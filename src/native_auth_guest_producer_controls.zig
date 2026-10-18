//! Genuine Auth/Resource methods with independently supplied real SDK owners.
//! Source-only causal profiles; no fake Completed/backend/module is built.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
pub const Route = enum { auth_getter, auth_call, readonly_getter, reload_getter, retained_callback };
pub const Inputs = struct {
    auth_exports: c.JSValue,
    /// Exact constructor from the real ResourceLoader assembly. Used only by
    /// reload_getter, where a borrowed method receiver is the actual input.
    resource_constructor: c.JSValue = c.pi_js_undefined(),
    /// Exact enabled-resource callback retained by a delegating live Array
    /// method during genuine ResourceLoader.reload. The real owner must run
    /// that capture; no substitute callback may be supplied for these profiles.
    retained_resource_callback: c.JSValue = c.pi_js_undefined(),
    /// Real owned physical path required by the genuine readonly constructor.
    auth_path: c.JSValue,
};
const Probe = struct {
    engine: *em.Engine,
    reason: c.JSValue = c.pi_js_undefined(),
    fatal: bool,
    calls: usize = 0,
};
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, p.reason);
    p.engine.gpa.destroy(p);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, p.reason, marker);
}
fn make(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    p.calls += 1;
    if (p.fatal) _ = p.engine.throwNativeOutOfMemoryFatal()
    else _ = p.engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    if (c.JS_IsUndefined(p.reason)) p.reason = c.JS_DupValue(context, reason);
    // The ordinary profile is an ACTUAL successful DATA producer: the private
    // Error is returned unmarked, no pending event and no B1 fatal publication.
    // The guest then throws A inside the very same outer get/call operation.
    return if (p.fatal) c.JS_Throw(context, reason) else reason;
}
fn expose(scope: *Scope, global: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try scope.put(global, name, value);
    _ = try scope.engine.checked(c.pi_js_undefined());
}
/// All ten route/fatal combinations require an actual assembled Auth graph.
/// Each runs in a fresh realm; no guest restoration after a native fatal.
pub fn verify(engine: *em.Engine, inputs: Inputs, comptime route: Route, comptime fatal: bool) !void {
    var scope: Scope = .{ .engine = engine };
    var selected = owned.Completion.initVoid(engine, run(&scope, inputs, route, fatal));
    selected.releaseScope(&scope);
    return selected.finishVoid();
}
fn run(scope: *Scope, inputs: Inputs, comptime route: Route, comptime fatal: bool) !void {
    const engine = scope.engine;
    try engine.checkNativeEntry();
    const actual_owner = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthOwner;
    const actual_exports = try owned.ownRoot(scope, try @import("extensions/native_sdk.zig").get(engine, actual_owner, "exports"));
    if (!c.JS_IsStrictEqual(engine.context, actual_exports, inputs.auth_exports)) return error.RequiredActualAuthNamespace;
    const global = try owned.ownRoot(scope, try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try expose(scope, global, "__actualGuestAuth", inputs.auth_exports);
    try expose(scope, global, "__actualGuestAuthPath", inputs.auth_path);
    if (route == .reload_getter) {
        if (!c.JS_IsConstructor(engine.context, inputs.resource_constructor)) return error.RequiredActualResourceConstructor;
        const prototype = try owned.ownRoot(scope, try @import("extensions/native_sdk.zig").get(engine, inputs.resource_constructor, "prototype"));
        const reload = try owned.ownRoot(scope, try @import("extensions/native_sdk.zig").get(engine, prototype, "reload"));
        if (!c.JS_IsAsyncFunction(reload)) return error.RequiredActualResourceReloadAF;
        try expose(scope, global, "__actualGuestReload", reload);
    }
    if (route == .retained_callback) {
        if (!c.JS_IsFunction(engine.context, inputs.retained_resource_callback)) return error.RequiredActuallyRetainedResourceCallback;
        try expose(scope, global, "__actualRetainedResourceCallback", inputs.retained_resource_callback);
    }
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Actual guest DATA versus native producer", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const holder = try owned.ownRoot(scope, try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    const p = try engine.gpa.create(Probe);
    p.* = .{ .engine = engine, .fatal = fatal };
    _ = c.JS_SetOpaque(holder, p);
    var roots = [_]c.JSValue{holder};
    const maker = try owned.ownRoot(scope, try engine.checked(c.JS_NewCFunctionData2(engine.context, make, "actualPrivateDataOrFatal", 0, 0, roots.len, &roots)));
    try expose(scope, global, "__actualGuestMaker", maker);
    const prelude =
        \\let actualThrown;globalThis.__actualGuestAfter=0;globalThis.__actualGuestCoercions=0;
        \\function throwActual(){actualThrown=__actualGuestMaker();actualThrown.toString=function(){__actualGuestCoercions++;return 'ordinary private DATA'};throw actualThrown}
        \\export let caught=false;
    ;
    const subject: []const u8 = switch (route) {
        .auth_getter =>
            \\const store=__actualGuestAuth.AuthStorage.inMemory();
            \\const options={get signal(){return throwActual()}};
            \\try{await store.read('fixture',options)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        ,
        .auth_call =>
            \\const store=__actualGuestAuth.AuthStorage.inMemory();
            \\const options={signal:{throwIfAborted:throwActual}};
            \\try{await store.read('fixture',options)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        ,
        .readonly_getter =>
            \\const store=new __actualGuestAuth.ReadOnlyAuthStorage(__actualGuestAuthPath);
            \\const options={get signal(){return throwActual()}};
            \\try{await store.read('fixture',options)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        ,
        .reload_getter =>
            \\const receiver={loaded:false};
            \\const options={get resolveProjectTrust(){return throwActual()}};
            \\try{await __actualGuestReload.call(receiver,options)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        ,
        .retained_callback => if (fatal)
            \\const input={get enabled(){const promise=new Promise(()=>{__actualGuestMaker()});promise.catch(()=>{});return promise}};
            \\try{__actualRetainedResourceCallback(input)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        else
            \\const input={get enabled(){return throwActual()}};
            \\try{__actualRetainedResourceCallback(input)}catch(reason){caught=reason===actualThrown;__actualGuestAfter++}
        ,
    };
    const source = try std.mem.concat(engine.gpa, u8, &.{ prelude, "\n", subject, "\nexport const completed=true;" });
    defer engine.gpa.free(source);
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    const generation = engine.native_allocation_generation;
    const evaluated = engine.evalModule(source, "actual-auth-guest-producer-contrast.mjs");
    if (fatal) {
        if (evaluated) |unexpected| { engine.freeValue(unexpected); return error.ExpectedActualNativeFatal; }
        else |err| if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return error.MissingActualNativeFatal;
        if (!c.JS_IsStrictEqual(engine.context, reason, p.reason) or !c.JS_IsUncatchableError(reason)) return error.ActualNativeFatalIdentity;
    } else {
        const namespace = try evaluated;
        defer engine.freeValue(namespace);
        const caught = c.JS_GetPropertyStr(engine.context, namespace, "caught");
        defer engine.freeValue(caught);
        if (!c.JS_IsStrictEqual(engine.context, caught, c.pi_js_bool(engine.context, 1))) return error.SuccessfulPrivateDataBecameFatal;
        if (c.JS_IsUncatchableError(p.reason) or engine.captured_exception != null or c.JS_HasException(engine.context)) return error.OrdinaryPrivateDataNotHandled;
    }
    const after = c.JS_GetPropertyStr(engine.context, global, "__actualGuestAfter");
    defer engine.freeValue(after);
    if (!c.JS_IsStrictEqual(engine.context, after, c.JS_NewInt32(engine.context, if (fatal) 0 else 1))) return error.ActualGuestContinuationMismatch;
    const coercions = c.JS_GetPropertyStr(engine.context, global, "__actualGuestCoercions");
    defer engine.freeValue(coercions);
    if (!c.JS_IsStrictEqual(engine.context, coercions, c.JS_NewInt32(engine.context, 0))) return error.ActualGuestDiagnosticCoercion;
    const tagged = c.pi_js_native_allocation_error_generation(p.reason);
    if (p.calls != 1 or tagged == 0 or tagged -% generation == 0 or tagged -% generation > engine.native_allocation_generation -% generation) return error.RequiredActuallyNewNativeDataProducer;
    if (engine.native_exception_diagnostics_suppressed != suppression or engine.native_fatal_invocation != invocation) return error.ActualGuestBoundaryUnbalanced;
}
