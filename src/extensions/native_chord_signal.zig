//! Source1692 linkedSignal: detach each source listener when the context closes or any source aborts.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn callback(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, captures[0], if (mode == 0) c.pi_js_undefined() else captures[1], mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, work: c.JSValue, source: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 2) return js.invoke(engine, work, "removeEventListener", &.{ try s.text("abort"), source });
    try release(&s, work);
    if (mode == 1) _ = try h.invoke(&s, try s.get(work, "controller"), "abort", &.{try s.get(source, "reason")});
    return c.pi_js_undefined();
}
fn release(s: *Scope, work: c.JSValue) !void {
    const removals = try h.invoke(s, try s.get(work, "detach"), "splice", &.{c.JS_NewInt32(s.engine.context, 0)});
    var iterator = try r.iterate(s, removals);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |remove| {
        defer s.engine.freeValue(remove);
        _ = try s.keep(try js.call(s.engine, remove, c.pi_js_undefined(), &.{}));
    }
}
pub fn linked(s: *Scope, sources: c.JSValue) !c.JSValue {
    const work = try s.record();
    const controller = try s.keep(try js.builtin(s.engine, "AbortController", &.{}));
    try h.field(s, work, "controller", controller);
    const detach = try s.list();
    try h.field(s, work, "detach", detach);
    var data = [_]c.JSValue{work};
    const stop = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "release", 0, 0, 1, &data)));
    var iterator = try r.iterate(s, sources);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |source| {
        defer s.engine.freeValue(source);
        if (try h.flag(s, source, "aborted")) {
            try release(s, work);
            _ = try h.invoke(s, controller, "abort", &.{try s.get(source, "reason")});
            // for-of break calls return on non-built-in caller iterators.
            try iterator.close();
            break;
        }
        var forward_data = [_]c.JSValue{ work, source };
        const forward = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "forward", 0, 1, 2, &forward_data)));
        const options = try s.record();
        try h.field(s, options, "once", c.pi_js_bool(s.engine.context, 1));
        _ = try h.invoke(s, source, "addEventListener", &.{ try s.text("abort"), forward, options });
        var remove_data = [_]c.JSValue{ source, forward };
        const remove = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 2, 2, &remove_data)));
        try js.push(s.engine, detach, remove);
    }
    const result = try s.record();
    try h.field(s, result, "signal", try s.get(controller, "signal"));
    try h.field(s, result, "release", stop);
    return result;
}
