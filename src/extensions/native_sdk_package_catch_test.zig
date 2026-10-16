//! Prepared native ownership controls. Not run or build-registered in this
//! source-only checkpoint; these are invariants, not invented Source goldens.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const caught = @import("native_sdk_package_catch.zig");
const c = em.c;

fn same(engine: *em.Engine, first: c.JSValue, second: c.JSValue) !void {
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}
fn ordinary(engine: *em.Engine) !void {
    try std.testing.expectError(error.JavaScriptException, engine.eval(
        "throw {name:'OutOfMemory',message:'out of memory',ordinary:true}",
        "package-ordinary-lookalike.js", c.JS_EVAL_TYPE_GLOBAL));
}

test "package ignored catch releases captured strong root across actual GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    try std.testing.expectError(error.JavaScriptException, engine.eval(
        \\globalThis.finalizedPackageReasons=[];
        \\globalThis.packageReasonRegistry=new FinalizationRegistry(value=>finalizedPackageReasons.push(value));
        \\(()=>{const reason={ordinary:true};globalThis.packageReasonWeak=new WeakRef(reason);packageReasonRegistry.register(reason,'ordinary');throw reason})()
    , "package-captured-weak-prepare.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expect(engine.captured_exception != null);
    try caught.ignore(engine, error.JavaScriptException, engine.native_allocation_generation);
    try std.testing.expect(engine.captured_exception == null);
    c.JS_ClearKeptObjects(engine.runtime);
    c.JS_RunGC(engine.runtime);
    const verified = try engine.eval(
        \\if(packageReasonWeak.deref()!==undefined)throw Error('handled captured reason still strongly rooted');
        \\// Finalization callback scheduling is observational, not a timing promise.
        \\globalThis.packageReasonFinalizerObservation=finalizedPackageReasons.slice();
    , "package-captured-weak-released.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(verified);
}

test "package named catch owns old reason while same-object callback throw survives" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    try ordinary(engine);
    const original = (try caught.take(engine, error.JavaScriptException, engine.native_allocation_generation)) orelse return error.MissingOrdinaryReason;
    var original_owned = true;
    defer if (original_owned) engine.freeValue(original);
    try std.testing.expect(engine.captured_exception == null);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "packageSameReason", c.JS_DupValue(engine.context, original));
    const callback = try engine.eval("(()=>{throw packageSameReason})", "package-same-rethrow-callback.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(callback);
    try std.testing.expectError(error.JavaScriptException, js.call(engine, callback, c.pi_js_undefined(), &.{}));
    try same(engine, original, engine.captured_exception orelse return error.MissingNewCapture);
    // End only the old catch binding. No identity-based deferred slot clearing.
    engine.freeValue(original);
    original_owned = false;
    try std.testing.expect(engine.captured_exception != null);
    const retained = try js.global(engine, "packageSameReason");
    defer engine.freeValue(retained);
    try same(engine, retained, engine.captured_exception.?);
}

test "package catch preserves direct OOM unrelated slot and preexisting fatal identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    try ordinary(engine);
    const original = c.JS_DupValue(engine.context, engine.captured_exception.?);
    defer engine.freeValue(original);
    try std.testing.expect((try caught.take(engine, error.InvalidPackageProbe, engine.native_allocation_generation)) == null);
    try same(engine, original, engine.captured_exception.?);
    try std.testing.expectError(error.OutOfMemory, caught.take(engine, error.OutOfMemory, engine.native_allocation_generation));
    try same(engine, original, engine.captured_exception.?);
    c.JS_SetUncatchableError(engine.context, original);
    try std.testing.expectError(error.JavaScriptException, caught.take(engine, error.JavaScriptException, engine.native_allocation_generation));
    try same(engine, original, engine.captured_exception.?);
}

test "package catch preserves exact fresh private OOM but consumes stale private reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_exception_diagnostics_suppressed += 1;
    const before = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const fresh = c.JS_DupValue(engine.context, engine.captured_exception.?);
    defer engine.freeValue(fresh);
    try std.testing.expectError(error.JavaScriptException, caught.take(engine, error.JavaScriptException, before));
    try same(engine, fresh, engine.captured_exception.?);
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
    // A different private reason is born before this new catch boundary.
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const stale = c.JS_DupValue(engine.context, engine.captured_exception.?);
    defer engine.freeValue(stale);
    const owned = (try caught.take(engine, error.JavaScriptException, engine.native_allocation_generation)) orelse return error.MissingStaleReason;
    defer engine.freeValue(owned);
    try same(engine, stale, owned);
    try std.testing.expect(engine.captured_exception == null);
}
