//! Local jiti native-loop policy. Mirrors linked JS_ThrowInterrupted's actual
//! new Error marking; never classifies a guest value by its name/message.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub fn check(engine: *v.em.Engine, steps: usize) !void {
    if (!engine.cancelled.load(.acquire) and !(steps % 256 == 0 and blk: {
        engine.interrupts +|= 1;
        break :blk engine.interrupts > engine.options.interrupt_budget;
    })) return;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    _ = c.JS_ThrowInternalError(engine.context, "interrupted");
    const reason = c.JS_GetException(engine.context);
    c.JS_SetUncatchableError(engine.context, reason);
    _ = try engine.checked(c.JS_Throw(engine.context, reason));
    unreachable;
}
/// Array-literal spread advances the real iterator, with the same normal
/// next/done/value behavior as js.Iterator.next. Only the local policy changes.
/// Abrupt IteratorStep does not gain an invented IteratorClose/return call.
pub fn next(iterator: *v.js.Iterator) !?c.JSValue {
    iterator.native_steps +|= 1;
    try check(iterator.engine, iterator.native_steps);
    errdefer iterator.closed = true;
    const step = try v.js.call(iterator.engine, iterator.next_function, iterator.iterator, &.{});
    defer iterator.engine.freeValue(step);
    if (!c.JS_IsObject(step)) return v.js.typeError(iterator.engine, "Iterator result is not an object");
    const done = try v.js.get(iterator.engine, step, "done");
    defer iterator.engine.freeValue(done);
    if (c.JS_ToBool(iterator.engine.context, done) != 0) { iterator.closed = true; return null; }
    return try v.js.get(iterator.engine, step, "value");
}
