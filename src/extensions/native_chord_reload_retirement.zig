//! Source1692 retirement: parent permission, forced root abort and bounded grace before resource retirement.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn gone(s: *Scope, work: c.JSValue) !bool {
    return !c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(work, "host"), "previous"), try s.get(work, "previous"));
}
fn ready(s: *Scope, work: c.JSValue) !bool {
    if (try gone(s, work)) return true;
    if (try h.flag(s, work, "grace")) return try r.index(s, try s.get(try s.get(work, "previous"), "roots"), "size") == 0;
    return c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(work, "host"), "retirable", &.{})) != 0;
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode != 0) {
        if (mode == 2 and !try ready(&s, work)) return c.pi_js_undefined();
        if (mode == 2) _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")}));
        _ = try s.keep(try js.call(engine, try s.get(work, "stop"), c.pi_js_undefined(), &.{}));
        return js.call(engine, try s.get(work, "resolve"), c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, @intFromBool(mode == 2))});
    }
    try h.field(&s, work, "resolve", resolve);
    var data = [_]c.JSValue{work};
    const timeout = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, 1, 1, &data)));
    try h.field(&s, work, "timer", try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ timeout, try s.get(work, "ms") })));
    const watcher = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, 2, 1, &data)));
    try h.field(&s, work, "stop", try h.invoke(&s, try s.get(work, "host"), "watchRetirement", &.{watcher}));
    return c.pi_js_undefined();
}
fn until(s: *Scope, work: c.JSValue, ms: c.JSValue, grace: bool) !c.JSValue {
    try h.field(s, work, "grace", c.pi_js_bool(s.engine.context, @intFromBool(grace)));
    if (try ready(s, work)) return s.keep(try h.resolved(s.engine, c.pi_js_bool(s.engine.context, 1)));
    try h.field(s, work, "ms", ms);
    var data = [_]c.JSValue{work};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, 0, 1, &data)));
    return s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
}
pub fn wait(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!c.JSValue {
    const host = try s.get(reload, "host");
    const previous = try s.get(host, "previous");
    if (c.JS_IsUndefined(previous)) return c.pi_js_undefined();
    const work = try s.record();
    inline for (.{ "bindings", "host", "previous" }, .{ bindings, host, previous }) |name, value| try h.field(s, work, name, value);
    const deadline = r.default(s, try s.get(try s.get(reload, "options"), "retireDeadline"), c.JS_NewInt32(s.engine.context, 5000));
    try h.field(s, work, "deadline", deadline);
    return s.keep(try h.wait(step, s.engine, work, try until(s, work, deadline, false), 0));
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    if (phase == 0 and c.JS_ToBool(engine.context, value) == 0 and !try gone(&s, work)) {
        const previous = try s.get(work, "previous");
        _ = try h.invoke(&s, try s.get(previous, "abort"), "abort", &.{try h.errorValue(&s, try s.get(work, "bindings"), "superseded", &.{ try s.text("code version "), try s.get(previous, "id"), try s.text(" was retired") }, c.pi_js_undefined())});
        const grace = try s.builtin("Math", "min", &.{ try s.get(work, "deadline"), c.JS_NewInt32(engine.context, 1000) });
        return h.wait(step, engine, work, try until(&s, work, grace, true), 1);
    }
    if (!try gone(&s, work)) _ = try h.invoke(&s, try s.get(work, "host"), "retire", &.{});
    return c.pi_js_undefined();
}
