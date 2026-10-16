//! Prepared controls over a factory namespace composed from actual inputs.
//! No fake Models/manager/loader/session constructor or registry is created.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
const names = [_][*:0]const u8{ "createAgentSession", "createAgentSessionServices", "createAgentSessionFromServices", "createAgentSessionRuntime" };
fn assertEmptyCapture(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (engine.captured_exception != null) return error.FactoryHandledReasonStillCaptured;
    return c.pi_js_undefined();
}
pub fn verifyBrandsAndEarlyRejections(engine: *em.Engine, actual_factory: c.JSValue) !void {
    for (names, [_]i32{ 0, 1, 1, 2 }, 0..) |name, length, index| {
        const function = try js.get(engine, actual_factory, name); defer engine.freeValue(function);
        try std.testing.expect(c.JS_IsAsyncFunction(function) != 0);
        try std.testing.expect(!c.JS_IsConstructor(engine.context, function));
        const actual_length = try js.get(engine, function, "length"); defer engine.freeValue(actual_length);
        var count: i32 = 0;
        if (c.JS_ToInt32(engine.context, &count, actual_length) < 0) return js.capture(engine);
        try std.testing.expectEqual(length, count);
        const arguments = [_]c.JSValue{ c.pi_js_undefined(), c.JS_NULL };
        const pending = try js.call(engine, function, c.pi_js_undefined(), if (index == 3) &arguments else &.{c.JS_NULL});
        defer engine.freeValue(pending);
        // An ordinary body getter error rejects its outer Promise. It does not
        // escape the call or leave the rejected reason in a host capture slot.
        try std.testing.expect(c.JS_PromiseState(engine.context, pending) >= 0);
        try std.testing.expect(engine.captured_exception == null);
        try std.testing.expectError(error.JavaScriptException, engine.awaitValue(pending));
        const owned = engine.captured_exception orelse return error.MissingExpectedBodyRejection;
        engine.captured_exception = null;
        defer engine.freeValue(owned);
        try std.testing.expect(c.JS_IsError(owned));
    }
}
pub fn verifyRawOptionsReason(engine: *em.Engine, actual_factory: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "ActualFactory", c.JS_DupValue(engine.context, actual_factory));
    const observed = try engine.evalModule(
        \\const reason={raw:true};let gets=0,escaped=false,pending;
        \\try{pending=ActualFactory.createAgentSessionFromServices(new Proxy({}, {get(){gets++;throw reason}}))}catch{escaped=true}
        \\let rejected;try{await pending}catch(error){rejected=error}
        \\if(escaped||gets!==1||rejected!==reason)throw Error('factory ordinary getter boundary/identity');
        \\export const passed=true;
    , "factory-from-services-raw-options.mjs");
    defer engine.freeValue(observed);
}
fn freshAllocation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    if (c.JS_DefinePropertyValueStr(engine.context, roots[0], "original", c.JS_DupValue(engine.context, reason), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
}
fn fatalCase(engine: *em.Engine, actual_factory: c.JSValue, actual_options: c.JSValue, actual_result: c.JSValue, source: []const u8, filename: [:0]const u8) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const record = try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)); defer engine.freeValue(record);
    const hook = try @import("extensions/native_node_function.zig").create(engine, "raiseFactoryNativeAllocation", 0, freshAllocation, &.{record}); defer engine.freeValue(hook);
    try js.define(engine, global, "ActualFactory", c.JS_DupValue(engine.context, actual_factory));
    try js.define(engine, global, "ActualRuntimeOptions", c.JS_DupValue(engine.context, actual_options));
    try js.define(engine, global, "ActualRuntimeResult", c.JS_DupValue(engine.context, actual_result));
    try js.define(engine, global, "raiseFactoryNativeAllocation", c.JS_DupValue(engine.context, hook));
    try js.define(engine, global, "factoryGuestCaught", c.pi_js_bool(engine.context, 0));
    try std.testing.expectError(error.JavaScriptException, engine.evalModule(source, filename));
    const original = try js.get(engine, record, "original"); defer engine.freeValue(original);
    const captured = engine.captured_exception orelse return error.MissingFactoryFatalReason;
    try std.testing.expect(c.pi_js_native_allocation_error_generation(original) != 0);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, captured));
    try std.testing.expect(c.JS_IsUncatchableError(captured));
    const caught = try js.global(engine, "factoryGuestCaught"); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_ToBool(engine.context, caught) == 0);
    c.JS_ClearUncatchableError(engine.context, captured);
    engine.captured_exception = null;
    engine.freeValue(captured);
}
/// actual_options has the real existing cwd/SessionManager required by the
/// Source assertion. actual_result contains a real session and real services.
/// The resumed case wraps that real result only to inject one native failure.
pub fn verifyWrappedNativeFailures(engine: *em.Engine, actual_factory: c.JSValue, actual_options: c.JSValue, actual_result: c.JSValue) !void {
    try fatalCase(engine, actual_factory, actual_options, actual_result,
        \\try{await ActualFactory.createAgentSessionFromServices({get services(){raiseFactoryNativeAllocation()}})}catch{factoryGuestCaught=true}
        \\throw Error('factory START native allocation became ordinary');
    , "factory-start-native-allocation.mjs");
    try fatalCase(engine, actual_factory, actual_options, actual_result,
        \\const result=new Proxy(ActualRuntimeResult,{get(target,key,receiver){if(key==='session')raiseFactoryNativeAllocation();return Reflect.get(target,key,receiver)}});
        \\try{await ActualFactory.createAgentSessionRuntime(()=>result,ActualRuntimeOptions)}catch{factoryGuestCaught=true}
        \\throw Error('factory resumed native allocation became ordinary');
    , "factory-resumed-native-allocation.mjs");
}
/// Observes the lifecycle result's live property read order and verifies the
/// exact real constructor identity; the controlled callback is a legal Source
/// user factory returning the supplied real session/services result.
pub fn verifyRuntimeOrdering(engine: *em.Engine, actual_factory: c.JSValue, actual_options: c.JSValue, actual_result: c.JSValue, actual_runtime_constructor: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "ActualFactory", c.JS_DupValue(engine.context, actual_factory));
    try js.define(engine, global, "ActualRuntimeOptions", c.JS_DupValue(engine.context, actual_options));
    try js.define(engine, global, "ActualRuntimeResult", c.JS_DupValue(engine.context, actual_result));
    try js.define(engine, global, "ActualRuntimeConstructor", c.JS_DupValue(engine.context, actual_runtime_constructor));
    const observed = try engine.evalModule(
        \\const trace=[];let entered=false;
        \\const source=new Proxy(ActualRuntimeResult,{get(target,key,receiver){trace.push(String(key));return Reflect.get(target,key,receiver)}});
        \\function create(options){if(options!==ActualRuntimeOptions)throw Error('runtime options identity');entered=true;return source}
        \\const pending=ActualFactory.createAgentSessionRuntime(create,ActualRuntimeOptions);
        \\if(!entered||trace.length!==1||trace[0]!=='then')throw Error('runtime callback/Await boundary');
        \\const result=await pending;
        \\if(!(result instanceof ActualRuntimeConstructor))throw Error('runtime constructor identity');
        \\if(trace.slice(0,5).join(',')!=='then,session,services,diagnostics,modelFallbackMessage')throw Error('runtime live result getter order: '+trace);
        \\export const passed=true;
    , "factory-runtime-order-and-identity.mjs");
    defer engine.freeValue(observed);
}

/// actual_services_options must contain a real ModelRuntime and real resource
/// options whose legitimate extension registers at least one provider. Only
/// that real runtime's user-overridable registration method is made to throw.
pub fn verifyServiceCatchOwnership(engine: *em.Engine, actual_factory: c.JSValue, actual_services_options: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const hook = try @import("extensions/native_node_function.zig").create(engine, "assertFactoryCaptureEmpty", 0, assertEmptyCapture, &.{}); defer engine.freeValue(hook);
    try js.define(engine, global, "ActualFactory", c.JS_DupValue(engine.context, actual_factory));
    try js.define(engine, global, "ActualServicesOptions", c.JS_DupValue(engine.context, actual_services_options));
    try js.define(engine, global, "assertFactoryCaptureEmpty", c.JS_DupValue(engine.context, hook));
    const observed = try engine.evalModule(
        \\const runtime=ActualServicesOptions.modelRuntime,original=runtime.registerProvider;
        \\const reason=new Error('owned');let handled=0;
        \\Object.defineProperty(reason,'message',{get(){assertFactoryCaptureEmpty();handled++;return 'owned'}});
        \\runtime.registerProvider=function(){throw reason};
        \\try{const result=await ActualFactory.createAgentSessionServices(ActualServicesOptions);if(handled===0||!result.diagnostics.some(row=>row.type==='error'&&row.message.endsWith('error: owned')))throw Error('real registration fixture/owned catch')}
        \\finally{runtime.registerProvider=original}
        \\export const passed=true;
    , "factory-real-services-catch-ownership.mjs");
    defer engine.freeValue(observed);
}
