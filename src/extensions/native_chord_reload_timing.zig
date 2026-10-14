//! Actual Source retirement, activation deadline and gate drain timers.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    if (mode == 5) return c.pi_js_bool(engine.context, 0);
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, reject: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 3) {
        const error_value = try h.errorValue(&s, try s.get(work, "bindings"), "aborted", &.{ try s.get(work, "what"), try s.text(" within "), try s.get(work, "deadline"), try s.text(" ms") }, try r.reason(&s, "deadline"));
        return js.call(engine, try s.get(work, "reject"), c.pi_js_undefined(), &.{error_value});
    }
    if (mode == 4) return js.call(engine, try s.get(work, "resolve"), c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, 1)});
    if (mode == 5) return c.pi_js_bool(engine.context, 0);
    var timer_callback = resolve;
    {
        try h.field(&s, work, "resolve", resolve);
        try h.field(&s, work, "reject", reject);
        var data = [_]c.JSValue{work};
        timer_callback = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, if (mode == 1) 3 else 4, 1, &data)));
    }
    const timeout = try s.keep(try js.global(engine, "setTimeout"));
    try h.field(&s, work, "timer", try s.keep(try js.call(engine, timeout, c.pi_js_undefined(), &.{ timer_callback, try s.get(work, "deadline") })));
    return c.pi_js_undefined();
}
fn timer(s: *Scope, work: c.JSValue, mode: c_int) !c.JSValue {
    var data = [_]c.JSValue{work};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 2, mode, 1, &data)));
    return s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
}
fn finish(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")}));
    return if (rejected) h.throwValue(&s, value) else s.result(value);
}
pub fn deadline(s: *Scope, bindings: c.JSValue, reload: c.JSValue, pending: c.JSValue, what: c.JSValue) !c.JSValue {
    const work = try s.record();
    inline for (.{ "bindings", "reload", "what" }, .{ bindings, reload, what }) |name, value| try h.field(s, work, name, value);
    try h.field(s, work, "deadline", r.default(s, try s.get(try s.get(reload, "options"), "gateDeadline"), c.JS_NewInt32(s.engine.context, 5000)));
    const promises = try s.list();
    try js.push(s.engine, promises, pending);
    try js.push(s.engine, promises, try timer(s, work, 1));
    return h.wait(finish, s.engine, work, try r.promise(s, "race", promises), 1);
}
fn gateExecutor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return gateOne(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn gateOne(engine: *h.Engine, record: c.JSValue, resolve: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const grandfathered = try r.copySet(&s, try h.invoke(&s, try s.get(record, "leases"), "keys", &.{}));
    const gate = try s.record();
    try h.field(&s, gate, "grandfathered", grandfathered);
    try h.field(&s, gate, "queue", try s.list());
    try h.field(&s, gate, "drained", resolve);
    try r.put(&s, record, "gate", gate);
    _ = try h.invoke(&s, record, "stopTasks", &.{});
    if (try r.index(&s, grandfathered, "size") == 0) _ = try s.keep(try js.call(engine, resolve, c.pi_js_undefined(), &.{}));
    return c.pi_js_undefined();
}
pub fn drain(s: *Scope, reload: c.JSValue) !c.JSValue {
    const gated = try s.list();
    const candidates = try h.values(s, try s.get(reload, "candidates"));
    for (0..try h.length(s, candidates)) |index| {
        const candidate = try s.at(candidates, index);
        if (try h.length(s, try s.get(candidate, "reasons")) > 0 and try s.equal(try s.get(try s.get(candidate, "object"), "status"), "live")) try js.push(s.engine, gated, candidate);
    }
    try r.put(s, reload, "gated", gated);
    const promises = try s.list();
    for (0..try h.length(s, gated)) |index| {
        var data = [_]c.JSValue{try s.get(try s.at(gated, index), "object")};
        const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, gateExecutor, "", 1, 0, 1, &data)));
        try js.push(s.engine, promises, try s.keep(try js.builtin(s.engine, "Promise", &.{executor})));
    }
    const work = try s.record();
    try h.field(s, work, "reload", reload);
    try h.field(s, work, "deadline", r.default(s, try s.get(try s.get(reload, "options"), "gateDeadline"), c.JS_NewInt32(s.engine.context, 5000)));
    const done = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 5, 0, null)));
    const raced = try s.list();
    try js.push(s.engine, raced, try h.invoke(s, try r.promise(s, "all", promises), "then", &.{done}));
    try js.push(s.engine, raced, try timer(s, work, 2));
    return h.wait(finish, s.engine, work, try r.promise(s, "race", raced), 2);
}
