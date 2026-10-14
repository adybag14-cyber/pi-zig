//! Source1692 cluster module-prefix selection, shared reload IDs and timed votes.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn modulesFor(s: *Scope, remote: c.JSValue, name: c.JSValue) !c.JSValue {
    const entries = try s.entries(if (h.nullish(remote)) try s.record() else remote);
    var best: ?c.JSValue = null;
    for (0..try h.length(s, entries)) |index| {
        const entry = try s.at(entries, index);
        const prefix = try s.at(entry, 0);
        if (h.nullish(name) or c.JS_ToBool(s.engine.context, try h.invoke(s, name, "startsWith", &.{prefix})) == 0) continue;
        if (best == null or try r.greater(s, try s.get(prefix, "length"), try s.get(try s.at(best.?, 0), "length"))) best = entry;
    }
    const selected = if (best) |entry| try s.at(entry, 1) else c.pi_js_undefined();
    return h.snapshot(s, if (h.nullish(selected)) try s.list() else selected);
}
pub fn nextId(s: *Scope, bindings: c.JSValue) !c.JSValue {
    const next = try s.keep(try s.engine.checked(c.JS_PiIncrement(s.engine.context, try s.get(bindings, "reloadSeq"))));
    try h.field(s, bindings, "reloadSeq", next);
    return next;
}
pub fn frame(s: *Scope, kind: []const u8, id: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "t", try s.text(kind));
    try h.field(s, result, "reload", id);
    return result;
}
pub fn send(s: *Scope, connection: c.JSValue, message: c.JSValue) !void {
    _ = try h.invoke(s, connection, "send", &.{message});
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), mode) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, reject: c.JSValue, mode: c_int) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (mode == 2) return js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")});
    const connection = try s.get(work, "connection");
    if (mode == 1) {
        _ = try h.invoke(&s, try s.get(connection, "votes"), "delete", &.{try s.get(work, "id")});
        return js.call(engine, try s.get(work, "reject"), c.pi_js_undefined(), &.{try h.errorValue(&s, try s.get(work, "bindings"), "aborted", &.{ try s.text("votes missing after "), try s.get(work, "deadline"), try s.text(" ms") }, try r.reason(&s, "vote_deadline"))});
    }
    const pending = try s.record();
    try h.field(&s, pending, "resolve", resolve);
    try h.field(&s, pending, "reject", reject);
    _ = try h.invoke(&s, try s.get(connection, "votes"), "set", &.{ try s.get(work, "id"), pending });
    try h.field(&s, work, "reject", reject);
    var data = [_]c.JSValue{work};
    const timeout = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, 1, 1, &data)));
    try h.field(&s, work, "timer", try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ timeout, try s.get(work, "deadline") })));
    return c.pi_js_undefined();
}
pub fn awaitVote(s: *Scope, bindings: c.JSValue, connection: c.JSValue, id: c.JSValue, deadline: c.JSValue) !c.JSValue {
    const work = try s.record();
    inline for (.{ "bindings", "connection", "id", "deadline" }, .{ bindings, connection, id, deadline }) |name, value| try h.field(s, work, name, value);
    var data = [_]c.JSValue{work};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 2, 0, 1, &data)));
    const pending = try s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
    const cleanup = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 0, 2, 1, &data)));
    return h.invoke(s, pending, "finally", &.{cleanup});
}
