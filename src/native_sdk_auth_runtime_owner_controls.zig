//! Actual Auth-only frontend/runtime composition controls, SOURCE ONLY/unrun.
//! Each entry requires a fresh Engine and genuine canonical frontend Inputs.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const owner = @import("extensions/native_sdk_auth_runtime_owner.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const cleanup = @import("native_auth_resource_cleanup_controls.zig");
pub const Profile = enum { original_auth_observer, actual_memory_roundtrip, read_ordinary_cleanup, read_new_fatal_cleanup, read_rejected_diagnostic, sync_reload_raw_pending };

/// Runs actual owner construction, not a class/Completed/child-process fixture.
/// The actual frontend bridge/environment/providers must outlive this Engine.
pub fn verify(engine: *em.Engine, inputs: owner.Inputs, comptime profile: Profile) !c.JSValue {
    try engine.checkNativeEntry();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const value = verifyScoped(engine, inputs, profile) catch |err| {
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("extensions/native_sdk.zig").fail(engine, err)));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn verifyScoped(engine: *em.Engine, inputs: owner.Inputs, comptime profile: Profile) !c.JSValue {
    var actual = try owner.create(engine, inputs);
    var scope: Scope = .{ .engine = engine };
    // observe is an aggregate of separately guarded producers. A broad entry
    // generation would reclassify historical successful DATA as a later event.
    var selected = owned.Completion.initValue(engine, observe(&scope, &actual, profile));
    selected.releaseScope(&scope);
    actual.retireInto(&selected);
    return selected.finishValue();
}
fn observe(scope: *Scope, actual: *owner.Owner, comptime profile: Profile) !c.JSValue {
    const engine = scope.engine;
    const auth = try owned.ownRoot(scope, try actual.authStorage());
    switch (profile) {
        .read_ordinary_cleanup => try cleanup.verifyActualReadRetirement(engine, auth, false),
        .read_new_fatal_cleanup => try cleanup.verifyActualReadRetirement(engine, auth, true),
        .read_rejected_diagnostic => try cleanup.verifyActualReadCleanupDiagnostic(engine, auth),
        .sync_reload_raw_pending => try cleanup.verifyActualSyncReloadCaughtReason(engine, auth),
        .actual_memory_roundtrip => {
            const memory = try owned.ownRoot(scope, try actual.inMemory());
            const global = try owned.ownRoot(scope, try engine.checked(c.JS_GetGlobalObject(engine.context)));
            try scope.put(global, "__actualOwnedAuthMemory", memory);
            _ = try engine.checked(c.pi_js_undefined());
            return engine.evalModule(
                \\const store=__actualOwnedAuthMemory;
                \\await store.modify('actual-owner',()=>({type:'oauth',access:'owned-value'}));
                \\if((await store.read('actual-owner')).access!=='owned-value')throw Error('actual owned Auth read');
                \\const rows=await store.list();if(!rows.some(x=>x.providerId==='actual-owner'&&x.type==='oauth'))throw Error('actual owned Auth list');
                \\await store.delete('actual-owner');if(await store.read('actual-owner')!==undefined)throw Error('actual owned Auth delete');
                \\export const completed=true;
            , "actual-owned-auth-memory-roundtrip.mjs");
        },
        .original_auth_observer => {
            // This value module aliases only the genuine authenticated exports.
            try engine.registerValueModule("actual-owned-auth-runtime-controls", auth);
            const source = try std.mem.concat(engine.gpa, u8, &.{
                "import{AuthStorage}from'actual-owned-auth-runtime-controls';\n",
                @embedFile("extensions/fixtures/auth-storage-resource-genuine-af-observer.mjs"),
                "\nexport const observations=await observeAuthStorage(AuthStorage);\n",
            });
            defer engine.gpa.free(source);
            return engine.evalModule(source, "actual-owned-auth-original-observer.mjs");
        },
    }
    return c.pi_js_undefined();
}

const GetterProbe = struct {
    engine: *em.Engine,
    exports: c.JSValue,
    reason: c.JSValue,
    fatal: bool,
    calls: usize = 0,
    downstream: usize = 0,
};
fn freeProbe(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const p: *GetterProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, p.exports);
    c.JS_FreeValueRT(runtime, p.reason);
    p.engine.gpa.destroy(p);
}
fn markProbe(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const p: *GetterProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, p.exports, marker);
    c.JS_MarkValue(runtime, p.reason, marker);
}
fn pendingGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p: *GetterProbe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    p.calls += 1;
    if (p.fatal) {
        _ = p.engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(context);
        if (c.JS_IsUndefined(p.reason)) p.reason = c.JS_DupValue(context, reason);
        _ = c.JS_Throw(context, reason);
    } else _ = c.JS_Throw(context, c.JS_DupValue(context, p.reason));
    // A real raw C getter returns an owned successful value AND a pending
    // event. Caller must normalize that event before append/downstream work.
    return c.JS_DupValue(context, p.exports);
}
fn downstreamGetter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const p: *GetterProbe = @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
    p.downstream += 1;
    return c.JS_DupValue(context, p.exports);
}
/// New fresh-realm profiles build the REAL frontend/runtime owner. Mutating
/// its genuine two carrier properties is a boundary input, never a fabricated
/// Module/Completed/Auth namespace. No guest restoration after fatal; teardown
/// occurs through actual native completion retirement and Engine destruction.
pub fn verifyGetterBoundary(engine: *em.Engine, inputs: owner.Inputs, comptime fatal: bool) !void {
    var actual = try owner.create(engine, inputs);
    var scope: Scope = .{ .engine = engine };
    var selected = owned.Completion.initVoid(engine, getterBoundary(&scope, &actual, fatal));
    selected.releaseScope(&scope);
    actual.retireInto(&selected);
    return selected.finishVoid();
}
fn getterBoundary(scope: *Scope, actual: *owner.Owner, comptime fatal: bool) !void {
    const engine = scope.engine;
    const exports = try owned.ownRoot(scope, try actual.authStorage());
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Actual Auth owner pending getter probe", .finalizer = freeProbe, .gc_mark = markProbe };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const holder = try owned.ownRoot(scope, try engine.checked(c.JS_NewObjectClass(engine.context, class)));
    const reason = if (fatal) c.pi_js_undefined() else try engine.eval("globalThis.__actualOwnerCoercions=0;({toString(){globalThis.__actualOwnerCoercions++;return 'ordinary owner reason'}})", "auth-owner-ordinary-reason.js", c.JS_EVAL_TYPE_GLOBAL);
    const p = engine.gpa.create(GetterProbe) catch |err| {
        var failed = owned.Completion.initVoid(engine, err);
        failed.release(reason);
        try failed.finishVoid();
        unreachable;
    };
    p.* = .{ .engine = engine, .exports = c.JS_DupValue(engine.context, exports), .reason = reason, .fatal = fatal };
    _ = c.JS_SetOpaque(holder, p);
    var roots = [_]c.JSValue{holder};
    const getter = try owned.ownRoot(scope, try engine.checked(c.JS_NewCFunctionData2(engine.context, pendingGetter, "get actual pending Auth", 0, 0, roots.len, &roots)));
    const downstream = try owned.ownRoot(scope, try engine.checked(c.JS_NewCFunctionData2(engine.context, downstreamGetter, "get actual downstream exports", 0, 0, roots.len, &roots)));
    const runtime_name = c.JS_NewAtom(engine.context, "authStorage");
    if (runtime_name == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, runtime_name);
    if (c.JS_DefinePropertyGetSet(engine.context, actual.runtime_imports, runtime_name, c.JS_DupValue(engine.context, getter), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    _ = try engine.checked(c.pi_js_undefined());
    const registry = engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthModuleOwner;
    const name = c.JS_NewAtom(engine.context, "exports");
    if (name == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, name);
    if (c.JS_DefinePropertyGetSet(engine.context, registry, name, c.JS_DupValue(engine.context, downstream), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    _ = try engine.checked(c.pi_js_undefined());
    const before_generation = engine.native_allocation_generation;
    const suppression = engine.native_exception_diagnostics_suppressed;
    const invocation = engine.native_fatal_invocation;
    if (actual.authStorage()) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualOwnerGetterFailure;
    } else |err| if (err != error.JavaScriptException) return err;
    const caught = engine.captured_exception orelse return error.MissingActualOwnerGetterFailure;
    if (!c.JS_IsStrictEqual(engine.context, caught, p.reason) or p.calls != 1 or p.downstream != 0) return error.ActualOwnerPendingIdentityOrOrder;
    if (c.JS_IsUncatchableError(caught) != fatal) return error.ActualOwnerPendingFatalStatus;
    if (fatal and engine.native_allocation_generation -% before_generation == 0) return error.RequiredNewActualOwnerFatalProducer;
    if (!fatal) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const count = c.JS_GetPropertyStr(engine.context, global, "__actualOwnerCoercions");
        defer engine.freeValue(count);
        if (!c.JS_IsStrictEqual(engine.context, count, c.JS_NewInt32(engine.context, 0))) return error.ActualOwnerDiagnosticCoercion;
    }
    if (engine.native_exception_diagnostics_suppressed != suppression or engine.native_fatal_invocation != invocation) return error.ActualOwnerPendingUnbalanced;
}
