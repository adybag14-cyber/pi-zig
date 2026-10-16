//! Prepared, unrun exact native-reason/entered-finally controls for this leaf.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const c = em.c;

// This owned test injector uses the real Engine native allocation tag. It
// retains the exact reason before throwing/returning it; no guest name check.
fn nativeReason(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context);
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "ownedFatalReason", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(reason);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    return reason;
}
fn throwReason(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const reason = nativeReason(context, receiver, argc, args);
    return if (c.JS_IsException(reason)) reason else c.JS_Throw(context, reason);
}
fn markFatal(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc > 0) c.JS_SetUncatchableError(context, args[0]);
    return c.pi_js_undefined();
}
fn armActionFailure(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const failing: *std.testing.FailingAllocator = @ptrCast(@alignCast(engine.gpa.ptr));
    // The Source idle finally has finished its guest work. The next host
    // allocation is the fresh Scope used by the Source-catch action reader.
    failing.fail_index = failing.alloc_index;
    return c.pi_js_undefined();
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const prototype = try sdk.object(engine);
    defer engine.freeValue(prototype);
    try @import("extensions/native_sdk_session_control.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_settled.zig").install(engine, prototype);
    try sdk.put(engine, global, "ownedIdleMethods", c.JS_DupValue(engine.context, prototype));
    inline for (.{ .{ "ownedMakeNativeReason", nativeReason }, .{ "ownedThrowNativeReason", throwReason }, .{ "ownedMarkAlreadyFatal", markFatal } }) |entry| {
        try sdk.put(engine, global, entry[0], try engine.checked(c.JS_NewCFunction(engine.context, entry[1], entry[0], 1)));
    }
}
fn fatalCase(program: []const u8, expected_cleanup: i32) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const result = engine.evalModule(program, "owned-idle-settlement-fatal-identity.mjs");
    if (result) |value| {
        engine.freeValue(value);
        return error.RequiredFatalNativeReason;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const retained = try sdk.get(engine, global, "ownedFatalReason");
    defer engine.freeValue(retained);
    try std.testing.expect(engine.captured_exception != null);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, retained, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(retained));
    const cleanup = try sdk.get(engine, global, "ownedCleanupCalls");
    defer engine.freeValue(cleanup);
    var calls: i32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &calls, cleanup));
    try std.testing.expectEqual(expected_cleanup, calls);
}

test "native idle settlement preserves fresh synchronous and resumed control fatal identity" {
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={abortRetry:ownedThrowNativeReason};await ownedIdleMethods.abort.call(receiver);
    , 0);
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={isIdle:false,_getIdleWaitPromise(){return Promise.reject(ownedMakeNativeReason())}};await ownedIdleMethods.waitForIdle.call(receiver);
    , 0);
}

test "native idle settlement preserves fatal identity across entered emission finally failure" {
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const cleanup={ordinary:true},receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{emit:ownedThrowNativeReason}};
        \\Object.defineProperty(receiver,'_isEmittingAgentSettled',{set(value){if(!value){ownedCleanupCalls++;throw cleanup}}});await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 1);
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{emit(){return Promise.reject(ownedMakeNativeReason())}}};
        \\Object.defineProperty(receiver,'_isEmittingAgentSettled',{set(value){if(!value){ownedCleanupCalls++;throw {cleanup:true}}}});await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 1);
}

test "native idle settlement preserves deferred fatal reason across iterator and idle cleanup failures" {
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{async emit(){}},_emit(){},_resolveIdleWaitIfIdle(){ownedCleanupCalls++;throw {idle:true}},_deferredSettledActions:{splice(){return{length:1,[Symbol.iterator](){return{next(){return{done:false,value(){return Promise.reject(ownedMakeNativeReason())}}},return(){ownedCleanupCalls++;throw {iterator:true}}}}}}}};await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 2);
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{async emit(){}},_emit(){},_resolveIdleWaitIfIdle(){ownedCleanupCalls++;throw {idle:true}},_deferredSettledActions:{splice(){return{length:1,[Symbol.iterator](){return{next(){return{done:false,value(){throw {primary:true}}}},return(){ownedCleanupCalls++;return ownedThrowNativeReason()}}}}}}};await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 2);
}

test "native idle settlement retains historical uncatchable identity while guest lookalikes remain ordinary" {
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const historical=ownedMakeNativeReason();ownedMarkAlreadyFatal(historical);const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{emit(){throw historical}}};Object.defineProperty(receiver,'_isEmittingAgentSettled',{set(value){if(!value){ownedCleanupCalls++;throw {cleanup:true}}}});await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 1);
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    try install(engine);
    const module = try engine.evalModule(
        \\for(const primary of[new Error('out of memory'),ownedMakeNativeReason()]){primary.name='InternalError';const cleanup={cleanup:true};const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{emit(){throw primary}}};Object.defineProperty(receiver,'_isEmittingAgentSettled',{set(value){if(!value)throw cleanup}});let caught;try{await ownedIdleMethods._emitAgentSettled.call(receiver)}catch(error){caught=error}if(caught!==cleanup)throw Error('ordinary/historical guest finalizer override lost')}
    , "owned-idle-settlement-ordinary-controls.mjs");
    engine.freeValue(module);
}

test "native idle settlement trusts a fresh idle-finalizer failure after an ordinary primary rejection" {
    try fatalCase(
        \\globalThis.ownedCleanupCalls=0;const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{async emit(){}},_emit(){},_deferredSettledActions:[()=>{throw {ordinaryPrimary:true}}],_resolveIdleWaitIfIdle(){ownedCleanupCalls++;return ownedThrowNativeReason()}};await ownedIdleMethods._emitAgentSettled.call(receiver);
    , 1);
}

test "native idle settlement propagates Source catch action allocation failure through the outer boundary" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        const engine = try em.Engine.init(failing.allocator(), .{ .host_await_timeout_ms = 10000 });
        defer engine.deinit();
        try install(engine);
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try sdk.put(engine, global, "ownedArmActionFailure", try engine.checked(c.JS_NewCFunction(engine.context, armActionFailure, "ownedArmActionFailure", 0)));
        const generation = engine.native_allocation_generation;
        const evaluated = engine.evalModule(
            \\const receiver={_cacheWarmer:null,_agentRunAbortRequested:false,_extensionRunner:{async emit(){}},_emit(){},_deferredSettledActions:[()=>{throw {ordinaryPrimary:true}}],_resolveIdleWaitIfIdle:ownedArmActionFailure};await ownedIdleMethods._emitAgentSettled.call(receiver);
        , "owned-settlement-source-catch-action-allocation.mjs");
        const injected_index = failing.fail_index;
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(injected_index, failing.alloc_index);
        if (evaluated) |value| {
            engine.freeValue(value);
            return error.RequiredSourceCatchActionAllocationFailure;
        } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
        const reason = engine.captured_exception orelse return error.RequiredCapturedActionAllocationFailure;
        const marked = engine.native_allocation_exception orelse return error.RequiredMarkedActionAllocationFailure;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, marked));
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        const tagged = c.pi_js_native_allocation_error_generation(reason);
        try std.testing.expect(tagged != 0 and tagged -% generation != 0 and tagged -% generation <= engine.native_allocation_generation -% generation);
    }
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
