//! Exact8efd Harness host values: capture option properties once, resolve the
//! captured callable/plain value synchronously at each Source use.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
pub fn resolve(engine: *em.Engine, captured_input: c.JSValue) !c.JSValue {
    var pending_frame = @import("native_pending_owner.zig").Frame.init(engine);
    pending_frame.enter() catch |err| return pending_frame.finishValue(err);
    return pending_frame.finishValue(resolvePendingBody(engine, captured_input));
}
fn resolvePendingBody(engine: *em.Engine, captured_input: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (!c.JS_IsFunction(engine.context, captured_input)) return c.JS_DupValue(engine.context, captured_input);
    const generation = engine.native_allocation_generation;
    return engine.checked(c.JS_Call(engine.context, captured_input, c.pi_js_undefined(), 0, null)) catch |err| {
        try escapeFatal(engine, err, generation);
        return err;
    };
}
pub fn escapeFatal(engine: *em.Engine, err: anyerror, generation: u64) !void {
    _ = generation; // A guest-call span or diagnostic tag is not producer proof.
    return @import("native_pending_owner.zig").catchFailure(engine, err);
}
/// Actual native events retain their independent pending/invocation policy.
/// A captured diagnostic supplies only a new ordinary Source completion.
pub fn getterFailure(engine: *em.Engine, err: anyerror, generation: u64) c.JSValue {
    _ = generation;
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    const pending = engine.nativeCallbackResult(c.pi_js_undefined());
    if (c.JS_IsException(pending)) return pending;
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        return c.JS_PiThrowExceptionData(engine.context, reason);
    };
    return @import("native_durable.zig").reject(engine, err);
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
