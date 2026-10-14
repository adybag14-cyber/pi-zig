//! Actual lazy retainedCodeVersions iteration, including a pending version only after current map exhaustion.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (mode == 2) return c.JS_DupValue(ctx, receiver);
    const engine = h.Engine.fromContext(ctx.?);
    return advance(engine, captures[0], mode == 1) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn result(s: *Scope, value: c.JSValue, done: bool) !c.JSValue {
    const item = try s.record();
    try h.field(s, item, "value", value);
    try h.field(s, item, "done", c.pi_js_bool(s.engine.context, @intFromBool(done)));
    return s.result(item);
}
fn advance(engine: *h.Engine, work: c.JSValue, closing: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (closing) try h.field(&s, work, "done", c.pi_js_bool(engine.context, 1));
    if (try h.flag(&s, work, "done")) return result(&s, c.pi_js_undefined(), true);
    const host = try s.get(work, "host");
    var iterator = try s.get(work, "iterator");
    if (c.JS_IsUndefined(iterator)) {
        iterator = try h.invoke(&s, try s.get(host, "codeVersions"), "entries", &.{});
        try h.field(&s, work, "iterator", iterator);
    }
    if (try r.next(&s, iterator)) |entry| return result(&s, try r.pair(&s, try s.at(entry, 0), try s.get(try s.at(entry, 1), "services")), false);
    try h.field(&s, work, "done", c.pi_js_bool(engine.context, 1));
    const pending = try s.get(host, "pending");
    if (!c.JS_IsUndefined(pending)) return result(&s, try r.pair(&s, try s.get(pending, "id"), try s.get(pending, "services")), false);
    return result(&s, c.pi_js_undefined(), true);
}
pub fn iterate(s: *Scope, host: c.JSValue) !c.JSValue {
    const work = try s.record();
    try h.field(s, work, "host", host);
    const iterator = try s.record();
    var captures = [_]c.JSValue{work};
    inline for (.{ "next", "return" }, 0..) |name, mode| try js.define(s.engine, iterator, name, try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, name, 0, @intCast(mode), 1, &captures)));
    const identity = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "[Symbol.iterator]", 0, 2, 0, null)));
    try js.setKey(s.engine, iterator, try h.iteratorSymbol(s), identity);
    return iterator;
}
