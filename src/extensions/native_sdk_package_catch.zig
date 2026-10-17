//! Package-leaf Source catch ownership only. This does not alter Engine or
//! shared async flow. A new throw during a catch may capture the same object;
//! therefore the old slot is transferred now, never cleared by identity later.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const body = @import("native_async_body.zig");

/// Await/.catch callback inputs are borrowed DATA, even when a private tag or
/// uncatchable bit was born while an unrelated operation was suspended. Only
/// actual current pending events may bypass the Source catch/retry/finally.
pub fn guard(engine: *v.em.Engine, _: c.JSValue, _: u64) !void {
    try engine.checkNativeEntry();
    try body.enterRejectedContinuation(engine);
}

/// BEFORE any native stage/property allocation, including fulfilled/start.
pub fn enter(engine: *v.em.Engine, completion: body.native.Completion) !void {
    try engine.checkNativeEntry();
    if (completion == .rejected) try body.enterRejectedContinuation(engine);
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
