//! Exact8efd Harness host values: capture option properties once, resolve the
//! captured callable/plain value synchronously at each Source use.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
pub fn resolve(engine: *em.Engine, captured: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, captured)) return c.JS_DupValue(engine.context, captured);
    const generation = engine.native_allocation_generation;
    return engine.checked(c.JS_Call(engine.context, captured, c.pi_js_undefined(), 0, null)) catch |err| {
        try escapeFatal(engine, err, generation);
        return err;
    };
}
pub fn escapeFatal(engine: *em.Engine, err: anyerror, generation: u64) !void {
    if (err == error.OutOfMemory) return err;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
        if (c.JS_IsUncatchableError(reason)) return err;
    };
}
/// Leaf-only getter exit. A newer pending VM reason wins. Ordinary captured
/// ownership transfers before guest code can catch; no deferred identity cleanup.
pub fn getterFailure(engine: *em.Engine, err: anyerror, generation: u64) c.JSValue {
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        // A trusted OOM cannot downgrade an existing Error to an ordinary throw.
        // Preserve its exact identity rather than allocate a replacement. The
        // pinned C API only marks Error-class values; arbitrary pending values
        // combined with direct OOM remain an unsupported mixed host contract.
        if (err == error.OutOfMemory and c.JS_IsError(reason)) c.JS_SetUncatchableError(engine.context, reason);
        return throwOwned(engine, reason, generation);
    }
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        return throwOwned(engine, reason, generation);
    };
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        return throwOwned(engine, reason, generation);
    }
    return @import("native_durable.zig").reject(engine, err);
}
fn throwOwned(engine: *em.Engine, reason: c.JSValue, generation: u64) c.JSValue {
    defer engine.freeValue(reason);
    @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch return engine.throwCaptured();
    if (c.JS_IsUncatchableError(reason)) {
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch return engine.throwCaptured();
        unreachable;
    }
    if (engine.captured_exception) |previous| {
        engine.captured_exception = null;
        engine.freeValue(previous);
    }
    return c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
}
pub fn captured(engine: *em.Engine, session: c.JSValue, options: c.JSValue, comptime name: [:0]const u8) !c.JSValue {
    const owner = try @import("native_durable.zig").state(engine, session);
    if (owner.creation_owner) |harness| {
        const host = try @import("native_durable_harness.zig").state(engine, harness);
        const value = if (comptime @import("std").mem.eql(u8, name, "models")) host.host_models else host.host_settings;
        if (value) |input| return c.JS_DupValue(engine.context, input);
    }
    // Direct internal scheduler/Session controls predate Harness construction.
    return sdk.get(engine, options, name);
}
