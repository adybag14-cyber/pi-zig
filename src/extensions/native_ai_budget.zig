//! Keep the owner VM's cancellation/compute budget effective in native loops.
const em = @import("engine.zig");
pub fn step(engine: *em.Engine, count: *usize) !void {
    count.* +|= 1;
    if (engine.cancelled.load(.acquire) or (count.* % 256 == 0 and blocked: {
        engine.interrupts +|= 1;
        break :blocked engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(em.c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
