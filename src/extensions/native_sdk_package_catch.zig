//! Package-leaf Source catch ownership only. This does not alter Engine or
//! shared async flow. A new throw during a catch may capture the same object;
//! therefore the old slot is transferred now, never cleared by identity later.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const body = @import("native_async_body.zig");

/// Borrowed rejection reasons have no captured slot ownership to consume.
pub fn guard(engine: *v.em.Engine, reason: c.JSValue, generation: u64) !void {
    if (c.JS_IsUncatchableError(reason)) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    try body.rethrowRecognizedAllocation(engine, reason, generation);
}

/// Returns the owned ordinary captured reason, if this is a JS exception.
/// Fatal errors retain their original Engine slot and exact reason. Non-JS
/// failures cannot consume an unrelated captured exception.
pub fn take(engine: *v.em.Engine, err: anyerror, generation: u64) !?c.JSValue {
    if (err == error.OutOfMemory) return err;
    if (err != error.JavaScriptException) return null;
    const reason = engine.captured_exception orelse return err;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}

/// Source catch {} has no lexical use for its captured ordinary reason.
pub fn ignore(engine: *v.em.Engine, err: anyerror, generation: u64) !void {
    if (try take(engine, err, generation)) |reason| engine.freeValue(reason);
}
