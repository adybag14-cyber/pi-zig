//! Actual consumer linger ownership of b45 shared remote bindings.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
fn close(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "close", &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn idle(s: *Scope, host: c.JSValue, bindings: c.JSValue, binding: c.JSValue) !void {
    const owned = (try h.actor(s, host, bindings, .HostImpl)).data;
    const types = try s.get(owned, "lingerTypes");
    const name = try s.get(try s.get(binding, "contract"), "name");
    const ms = if (c.JS_ToBool(s.engine.context, try s.builtin("Object", "hasOwn", &.{ types, name })) != 0) try s.key(types, name) else c.JS_NewInt32(s.engine.context, 0);
    const zero = c.JS_NewInt32(s.engine.context, 0);
    const nonpositive = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 5, ms, zero)));
    if (c.JS_ToBool(s.engine.context, nonpositive) != 0 or try h.flag(s, binding, "ended") or !try h.flag(s, binding, "applied") or c.JS_ToBool(s.engine.context, try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 5, try s.get(owned, "lingerCap"), zero)))) != 0) {
        _ = try h.invoke(s, binding, "close", &.{});
        return;
    }
    var captures = [_]c.JSValue{binding};
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, close, "", 0, 0, 1, &captures)));
    const timer = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "setTimeout")), c.pi_js_undefined(), &.{ callback, ms }));
    try h.field(s, binding, "lingerTimer", timer);
    const unref = try s.get(timer, "unref");
    if (!h.nullish(unref)) _ = try s.keep(try js.call(s.engine, unref, timer, &.{}));
    const lingering = try s.get(owned, "lingering");
    _ = try h.invoke(s, lingering, "set", &.{ try s.get(binding, "key"), binding });
    var iterator = try js.Iterator.init(s.engine, try h.invoke(s, lingering, "values", &.{}), try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |oldest| {
        defer s.engine.freeValue(oldest);
        const within = try s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 5, try s.get(lingering, "size"), try s.get(owned, "lingerCap"))));
        if (c.JS_ToBool(s.engine.context, within) != 0) {
            try iterator.close();
            break;
        }
        _ = try h.invoke(s, oldest, "close", &.{});
    }
}
pub fn forget(s: *Scope, host: c.JSValue, bindings: c.JSValue, binding: c.JSValue) !void {
    const owned = (try h.actor(s, host, bindings, .HostImpl)).data;
    const key = try s.get(binding, "key");
    inline for (.{ try s.get(host, "bindings"), try s.get(owned, "lingering") }) |map| {
        if (c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, map, "get", &.{key}), binding)) _ = try h.invoke(s, map, "delete", &.{key});
    }
}
