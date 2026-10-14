//! Source1692 task restart serialization and stop-generation fencing.
const r = @import("native_chord_reload_values.zig");
const object_api = @import("native_chord_object.zig");
const runtime = @import("native_chord_object_runtime.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    if (mode == 2) return c.pi_js_bool(engine.context, 0);
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 0) {
        try h.field(&s, work, "resolve", resolve);
        var captures = [_]c.JSValue{work};
        const fire = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, 1, 1, &captures)));
        try h.field(&s, work, "timer", try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ fire, try s.get(work, "deadline") })));
        return c.pi_js_undefined();
    }
    if (mode == 1) return js.call(engine, try s.get(work, "resolve"), c.pi_js_undefined(), &.{c.pi_js_bool(engine.context, 1)});
    return js.invoke(engine, try s.get(work, "stopped"), "delete", &.{try s.get(work, "done")});
}
fn bump(s: *Scope, data: c.JSValue) !c.JSValue {
    const next = try s.keep(try s.engine.checked(c.JS_PiIncrement(s.engine.context, try s.get(data, "taskRuns"))));
    try h.field(s, data, "taskRuns", next);
    return next;
}
fn startNow(s: *Scope, bindings: c.JSValue, object: c.JSValue) !void {
    var keys = try r.mapIterator(s, try s.get(try s.get(object, "decls"), "tasks"), "keys");
    defer keys.deinit();
    errdefer keys.closePreserving();
    while (try keys.next()) |key| {
        defer s.engine.freeValue(key);
        try runtime.startTask(s, object, bindings, key, try h.invoke(s, try s.get(object, "host"), "currentCodeVersion", &.{}));
    }
}
pub fn start(s: *Scope, bindings: c.JSValue, object: c.JSValue) anyerror!void {
    const data = try object_api.state(s, object, bindings);
    const generation = try bump(s, data);
    const stopped = try s.get(data, "stopped");
    if (try r.index(s, stopped, "size") == 0) return startNow(s, bindings, object);
    const work = try s.record();
    inline for (.{ "bindings", "object", "data", "generation" }, .{ bindings, object, data, generation }) |name, value| try h.field(s, work, name, value);
    try h.field(s, work, "deadline", try s.get(try s.get(object, "host"), "taskStopDeadline"));
    var captures = [_]c.JSValue{work};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, 0, 1, &captures)));
    const late = try s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
    const settled = try r.promise(s, "allSettled", try h.snapshot(s, stopped));
    const early = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 2, 0, null)));
    const pending = try s.list();
    try js.push(s.engine, pending, try h.invoke(s, settled, "then", &.{early}));
    try js.push(s.engine, pending, late);
    _ = try s.keep(try h.wait(finished, s.engine, work, try r.promise(s, "race", pending), 0));
}
fn finished(engine: *h.Engine, work: c.JSValue, missed: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, missed);
    _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")}));
    const object = try s.get(work, "object");
    if (!c.JS_IsStrictEqual(engine.context, try s.get(work, "generation"), try s.get(try s.get(work, "data"), "taskRuns")) or !try s.equal(try s.get(object, "status"), "live")) return c.pi_js_undefined();
    const bindings = try s.get(work, "bindings");
    if (c.JS_ToBool(engine.context, missed) != 0) _ = try h.invoke(&s, try s.get(object, "host"), "report", &.{try h.errorValue(&s, bindings, "aborted", &.{ try s.get(object, "address"), try s.text(": aborted tasks still running after "), try s.get(work, "deadline"), try s.text(" ms; starting their replacements anyway") }, c.pi_js_undefined())});
    try startNow(&s, bindings, object);
    return c.pi_js_undefined();
}
pub fn stop(s: *Scope, bindings: c.JSValue, object: c.JSValue) anyerror!void {
    const data = try object_api.state(s, object, bindings);
    _ = try bump(s, data);
    const tasks = try s.get(data, "tasks");
    var iterator = try r.mapIterator(s, tasks, "values");
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |task| {
        defer s.engine.freeValue(task);
        _ = try h.invoke(s, try s.get(task, "controller"), "abort", &.{try h.errorValue(s, bindings, "aborted", &.{try s.text("task stopped")}, c.pi_js_undefined())});
        const done = try s.get(task, "done");
        const stopped = try s.get(data, "stopped");
        _ = try h.invoke(s, stopped, "add", &.{done});
        const work = try s.record();
        try h.field(s, work, "stopped", stopped);
        try h.field(s, work, "done", done);
        var captures = [_]c.JSValue{work};
        const remove = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 3, 1, &captures)));
        _ = try h.invoke(s, done, "finally", &.{remove});
    }
    _ = try h.invoke(s, tasks, "clear", &.{});
}
