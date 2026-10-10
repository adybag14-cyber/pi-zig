//! Small owner-VM helpers without dependencies on application SDK modules.
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
pub fn object(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
pub fn array(engine: *Engine) !c.JSValue {
    return engine.checked(c.JS_NewArray(engine.context));
}
pub fn get(engine: *Engine, value: c.JSValue, name: [:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, value, name));
}
pub fn put(engine: *Engine, target: c.JSValue, name: [:0]const u8, value: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, target, name, value) < 0) return error.JavaScriptException;
}
pub fn length(engine: *Engine, value: c.JSValue) !usize {
    const size = try get(engine, value, "length");
    defer engine.freeValue(size);
    var result: u32 = 0;
    if (c.JS_ToUint32(engine.context, &result, size) < 0) return error.JavaScriptException;
    return result;
}
pub fn invoke(engine: *Engine, receiver: c.JSValue, name: [:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
