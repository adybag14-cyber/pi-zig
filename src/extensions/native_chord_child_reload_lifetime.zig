//! Actual Source ChildReloads cancellation and parent-loss lifetime, independent of prepare implementation.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, finish: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return completed(engine, captures[0], finish != 0, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn completed(engine: *h.Engine, host: c.JSValue, finish: bool, error_value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (finish) {
        try endReload(&s, host);
    } else _ = try h.invoke(&s, host, "report", &.{error_value});
    return c.pi_js_undefined();
}
pub fn endReload(s: *Scope, host: c.JSValue) !void {
    try js.setKey(s.engine, host, try s.text("reloading"), c.pi_js_bool(s.engine.context, 0));
    _ = try h.invoke(s, host, "maybeRetire", &.{});
}
pub fn cancel(s: *Scope, host: c.JSValue, data: c.JSValue, operation: c.JSValue) !void {
    try js.setKey(s.engine, operation, try s.text("cancelled"), c.pi_js_bool(s.engine.context, 1));
    const prepared = try s.equal(try s.get(operation, "state"), "prepared");
    if (prepared) try h.field(s, data, "childOperation", c.pi_js_undefined());
    const reload = try s.get(operation, "reload");
    if (h.nullish(reload)) return;
    const rolling_back = try h.invoke(s, reload, "rollback", &.{});
    var captures = [_]c.JSValue{host};
    const rejected = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, 0, 1, &captures)));
    const reported = try h.invoke(s, rolling_back, "catch", &.{rejected});
    if (prepared) {
        const finished = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 1, 1, &captures)));
        _ = try h.invoke(s, reported, "finally", &.{finished});
    }
}
pub fn parentLost(s: *Scope, _: c.JSValue, host: c.JSValue, data: c.JSValue) anyerror!void {
    const operation = try s.get(data, "childOperation");
    if (!c.JS_IsUndefined(operation)) try cancel(s, host, data, operation);
}
