//! Private CommonJS native-loop interruption, matching linked QuickJS's actual
//! JS_ThrowInterrupted. No C/Engine ABI or generic helper policy is changed.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub fn step(engine: *v.em.Engine, steps: *usize) !void {
    // A real pending completion precedes this host checkpoint. Preserve it;
    // an old engine.captured_exception is not evidence of a current throw.
    if (c.JS_HasException(engine.context)) return capturePending(engine);
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and budget: {
        engine.interrupts +|= 1;
        break :budget engine.interrupts > engine.options.interrupt_budget;
    })) return raiseFresh(engine);
}
fn raiseFresh(engine: *v.em.Engine) anyerror {
    if (c.JS_HasException(engine.context)) return capturePending(engine);
    // Same operation and same actually created reason as JS_ThrowInterrupted.
    // If error creation itself runs out of memory, retain that actual reason.
    _ = c.JS_ThrowInternalError(engine.context, "interrupted");
    if (!c.JS_HasException(engine.context)) return error.MissingCommonJSInterruptionReason;
    const owned = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, owned);
    _ = c.JS_Throw(engine.context, owned); // Transfers this one owned reference.
    return capturePending(engine);
}
fn capturePending(engine: *v.em.Engine) anyerror {
    if (!c.JS_HasException(engine.context)) return error.MissingCommonJSPendingReason;
    // Capture must not stringify an existing reason or read guest diagnostics.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context))) catch |err| return err;
    unreachable;
}
