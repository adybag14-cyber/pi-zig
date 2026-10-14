//! Actual b45 async Host.get, distinct from the immediate Host.hold view.
const h = @import("native_chord_host_values.zig");
const c = h.c;
const js = h.js;
const aw = @import("native_chord_async_work.zig");
fn ready(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    try aw.complete(&s, work, if (rejected) value else try s.get(try s.get(work, "ref"), "proxy"), rejected);
}
pub fn get(engine: *h.Engine, host: c.JSValue, bindings: c.JSValue, type_value: c.JSValue, input: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try aw.create(&s);
    const ref = try h.invoke(&s, host, "acquire", &.{ type_value, input, options, try s.text("external") });
    try h.field(&s, work, "ref", ref);
    const signals = try s.list();
    const signal = if (h.nullish(options)) c.pi_js_undefined() else try s.get(options, "signal");
    if (!c.JS_IsUndefined(signal)) try js.push(engine, signals, try s.get(options, "signal"));
    const pending = try s.keep(try @import("native_chord_ready_v4.zig").awaitReady(engine, bindings, ref, signals, try s.get(host, "readyTimeout")));
    try aw.wait(ready, &s, work, pending, 0);
    return aw.result(&s, work);
}
