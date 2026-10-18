//! Private canonical manager imports captured at the real SDK install boundary.
//! Never recover constructors from mutable prototype.constructor properties.
const em = @import("engine.zig");
const c = em.c;
const js = @import("native_js_values.zig");
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const key = "\x00sdk-actual-manager-imports";

/// Called only by native_sdk's actual original installer, with its actual
/// constructor export record. No arbitrary Completed/import capability exists.
pub fn captureInstalled(engine: *em.Engine, exports: c.JSValue) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    captureOwned(engine, exports) catch |err| {
        _ = try engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
        unreachable;
    };
    engine.freeValue(try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())));
}
fn captureOwned(engine: *em.Engine, exports: c.JSValue) !void {
    if (engine.native_module_values.contains(key)) return error.ActualSdkManagersAlreadyCaptured;
    var scope: Scope = .{ .engine = engine };
    const projection = try owned.finishValue(&scope, project(&scope, exports));
    engine.freeValue(try publish(engine, projection));
}

/// The genuine fresh private-manager route invokes the SAME original SDK body,
/// then retires its temporary full record before publishing the projection.
/// Normal worker TUI/editor installation captures before this method is called.
pub fn acquire(engine: *em.Engine, comptime install_body: anytype) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |cached| return c.JS_DupValue(engine.context, cached);
    // A failed old install is not a completed manager authority. In particular,
    // do not rebuild a constructor from the public mutable prototype field.
    if (engine.native_sdk_class != 0) return error.RequiredOriginalSdkManagerModuleOwner;
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const value = acquireOwned(engine, install_body) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn acquireOwned(engine: *em.Engine, comptime install_body: anytype) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const projection = try owned.finishValue(&scope, fresh(&scope, install_body));
    return publish(engine, projection);
}
fn fresh(scope: *Scope, comptime install_body: anytype) !c.JSValue {
    const exports = try owned.ownRoot(scope, try js.object(scope.engine));
    try install_body(scope.engine, exports);
    return project(scope, exports);
}
fn project(scope: *Scope, exports: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const projection = try owned.ownRoot(scope, try js.object(engine));
    inline for (.{ "SessionManager", "SettingsManager" }) |name| {
        const generation = engine.native_allocation_generation;
        const constructor = try owned.ownRoot(scope, try guards.guard(engine, generation, js.get(engine, exports, name)));
        if (!c.JS_IsConstructor(engine.context, constructor)) return error.RequiredActualSdkManagerConstructor;
        const define_generation = engine.native_allocation_generation;
        const status = c.JS_DefinePropertyValueStr(engine.context, projection, name, c.JS_DupValue(engine.context, constructor), c.JS_PROP_C_W_E);
        const result: anyerror!c.JSValue = if (status < 0) js.capture(engine) else engine.checked(c.pi_js_undefined());
        _ = try guards.guard(engine, define_generation, result);
    }
    return c.JS_DupValue(engine.context, projection);
}
fn publish(engine: *em.Engine, projection: c.JSValue) !c.JSValue {
    engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var failed = owned.Completion.initValue(engine, err);
        failed.release(projection);
        return failed.finishValue();
    };
    // No guest call/native root retirement lies between reserve and commit.
    engine.native_module_values.putAssumeCapacity(key, c.JS_DupValue(engine.context, projection));
    return projection;
}
