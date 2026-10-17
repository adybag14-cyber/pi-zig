//! Thin owned-return access to the VM's genuine async-iterator acquisition.
//! No AsyncFromSync adapter or Promise implementation is built in Zig/guest JS.
const em = @import("engine.zig");
pub fn acquire(engine: *em.Engine, borrowed: em.c.JSValue) !em.c.JSValue {
    return engine.checked(em.c.JS_PiGetAsyncIterator(engine.context, borrowed));
}
