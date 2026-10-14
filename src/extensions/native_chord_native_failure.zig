//! Escape only a genuine fresh native allocator failure from private Chord continuations.
//! Ordinary guest errors and earlier native errors retain their Source catch/rejection behavior.
const em = @import("engine.zig");
const c = em.c;
pub fn escape(engine: *em.Engine, err: anyerror, generation: u64) ?c.JSValue {
    if (err == error.OutOfMemory) {
        const thrown = engine.throwNativeOutOfMemory();
        if (engine.native_allocation_exception) |value| c.JS_SetUncatchableError(engine.context, value);
        return thrown;
    }
    if (engine.nativeAllocationError(err, generation) == error.OutOfMemory) {
        if (engine.captured_exception) |value| c.JS_SetUncatchableError(engine.context, value);
        return engine.throwCaptured();
    }
    return null;
}
