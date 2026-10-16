//! Package/Git-local borrowed data definition. Reused Scope.put delegates to
//! sdk.put, whose negative status does not capture the pending VM reason.
//! Capture at this actual boundary so later catches cannot inspect a stale
//! slot or lose the fresh reason. Engine/shared Scope/sdk remain unchanged.
const v = @import("native_ai_provider_values.zig");
pub fn put(engine: *v.em.Engine, object: v.c.JSValue, name: [*:0]const u8, value: v.c.JSValue) !void {
    if (v.c.JS_DefinePropertyValueStr(engine.context, object, name, v.c.JS_DupValue(engine.context, value), v.c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
}
