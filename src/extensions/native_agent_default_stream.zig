//! Original pi-agent-core module-local fallback stream binding.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const c = em.c;
pub fn set(engine: *em.Engine, value: c.JSValue) void {
    if (engine.native_agent_default_stream) |previous| engine.freeValue(previous);
    engine.native_agent_default_stream = c.JS_DupValue(engine.context, value);
}
pub fn get(engine: *em.Engine) !c.JSValue {
    const stream = engine.native_agent_default_stream orelse c.pi_js_undefined();
    if (c.JS_ToBool(engine.context, stream) == 0) {
        var scope: temp.Scope = .{ .engine = engine };
        defer scope.deinit();
        return @import("native_agent_methods.zig").raise(&scope, "No default stream function configured. Pass streamFn explicitly or call setDefaultStreamFn().");
    }
    return c.JS_DupValue(engine.context, stream);
}
pub fn setter(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    set(em.Engine.fromContext(context.?), if (argc > 0) argv[0] else c.pi_js_undefined());
    return c.pi_js_undefined();
}
pub fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return get(engine) catch |err| sdk.fail(engine, err);
}
