//! One actual Chord FIFO publication queue shared by every Host in the module.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn initialize(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.record();
    try h.field(&s, state, "queue", try s.list());
    try h.field(&s, state, "held", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, state, "draining", c.pi_js_bool(engine.context, 0));
    try h.field(&s, bindings, "publication", state);
}
fn count(s: *Scope, state: c.JSValue) !i32 {
    var result: i32 = undefined;
    if (c.JS_ToInt32(s.engine.context, &result, try s.get(state, "held")) < 0) return js.capture(s.engine);
    return result;
}
fn setDraining(engine: *h.Engine, state: c.JSValue, value: bool) !void {
    if (c.JS_SetPropertyStr(engine.context, state, "draining", c.pi_js_bool(engine.context, @intFromBool(value))) < 0) return js.capture(engine);
}
pub fn drain(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.get(bindings, "publication");
    if (try h.flag(&s, state, "draining") or try count(&s, state) > 0) return;
    try setDraining(engine, state, true);
    defer setDraining(engine, state, false) catch {};
    const queue = try s.get(state, "queue");
    while (true) {
        const task = try h.invoke(&s, queue, "shift", &.{});
        if (c.JS_IsUndefined(task)) return;
        _ = try s.keep(try js.call(engine, task, c.pi_js_undefined(), &.{}));
    }
}
pub fn enqueue(engine: *h.Engine, bindings: c.JSValue, task: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.get(bindings, "publication");
    _ = try h.invoke(&s, try s.get(state, "queue"), "push", &.{task});
    try drain(engine, bindings);
}
pub fn hold(engine: *h.Engine, bindings: c.JSValue, function: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.get(bindings, "publication");
    const before = try count(&s, state);
    try h.field(&s, state, "held", c.JS_NewInt32(engine.context, before + 1));
    const returned = js.call(engine, function, c.pi_js_undefined(), &.{}) catch |err| {
        try h.field(&s, state, "held", c.JS_NewInt32(engine.context, (try count(&s, state)) - 1));
        try drain(engine, bindings);
        return err;
    };
    const result = try s.keep(returned);
    try h.field(&s, state, "held", c.JS_NewInt32(engine.context, (try count(&s, state)) - 1));
    try drain(engine, bindings);
    return s.result(result);
}
