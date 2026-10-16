//! Unrun observation-only negative. This is not an executable gate or a claim
//! that arbitrary VM values can carry the pinned C Error-only fatal marker.
const em = @import("../../src/extensions/engine.zig");
const host = @import("../../src/extensions/native_durable_host_inputs.zig");
const c = em.c;
pub const Observation = struct { same_identity: bool, error_class: bool, uncatchable: bool, private_tag: u64 };
pub fn observe(engine: *em.Engine, supplied_pending: c.JSValue) !Observation {
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, supplied_pending));
    const result = host.getterFailure(engine, error.OutOfMemory, engine.native_allocation_generation);
    if (!c.JS_IsException(result)) return error.MixedHostControlDidNotThrow;
    const actual = c.JS_GetException(engine.context);
    defer engine.freeValue(actual);
    return .{ .same_identity = c.JS_IsStrictEqual(engine.context, supplied_pending, actual),
        .error_class = c.JS_IsError(actual), .uncatchable = c.JS_IsUncatchableError(actual),
        .private_tag = c.pi_js_native_allocation_error_generation(actual) };
}
