//! Genuine AsyncFunction adapter for a synchronous native `return expression`
//! body. The VM creates the outer Promise and adopts the owned return value.
//! This adapter adds no Await, Promise.resolve, then lookup, or prototype edit.
//! Callbacks return one owned value; arguments/receiver/captures are borrowed.
//! A failed native operation propagates its error through the primitive's
//! current-invocation transport. A returned rejected Promise remains DATA;
//! neither this adapter nor the callback entry classifies its rejection reason.
//! Bodies with Source Await must use createResumable instead.
const em = @import("engine.zig");
const af = @import("native_async_function.zig");
const c = em.c;
pub const Callback = af.Callback;

pub fn create(engine: *em.Engine, name: [*:0]const u8, length: c_int, callback: Callback, captures: []const c.JSValue) !c.JSValue {
    return af.create(engine, name, length, callback, captures);
}

pub fn createArrow(engine: *em.Engine, name: [*:0]const u8, length: c_int, callback: Callback, captures: []const c.JSValue, lexical_this: c.JSValue) !c.JSValue {
    return af.createArrow(engine, name, length, callback, captures, lexical_this);
}
