//! VM-rooted context epochs with the original runner's immutable stale reason.
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub const default_message = "This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload(). For newSession, fork, and switchSession, move post-replacement work into withSession and use the ctx passed to withSession. For reload, do not use the old ctx after await ctx.reload().";
pub fn create(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
}
pub fn replace(engine: *engine_mod.Engine, current: *c.JSValue, reason: []const u8) !void {
    const fresh = try create(engine);
    errdefer engine.freeValue(fresh);
    const message = try engine.checked(c.JS_NewStringLen(engine.context, reason.ptr, reason.len));
    if (c.JS_DefinePropertyValueStr(engine.context, current.*, "message", message, 0) < 0) return error.JavaScriptException;
    engine.freeValue(current.*);
    current.* = fresh;
}
pub fn assertActive(engine: *engine_mod.Engine, lifetime: c.JSValue) !void {
    const message = try engine.checked(c.JS_GetPropertyStr(engine.context, lifetime, "message"));
    defer engine.freeValue(message);
    if (c.JS_IsUndefined(message) or c.JS_ToBool(engine.context, message) == 0) return;
    const exception = try engine.checked(c.JS_NewError(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, exception, "message", c.JS_DupValue(engine.context, message), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(exception);
        return error.JavaScriptException;
    }
    _ = try engine.checked(c.JS_Throw(engine.context, exception));
}
