//! Actual b45 exposed-state hydration and object readyTimeout ownership.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const async_work = @import("native_chord_async_work.zig");
const cells = @import("native_chord_cells_v4.zig");
const Op = enum(c_int) { value, wait, exposed_pending, exposed_name, derived_pending, derived_name, waiting, timeout_executor, timeout };
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn function(s: *Scope, work: c.JSValue, op: Op, arity: c_int) !c.JSValue {
    var values = [_]c.JSValue{work};
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", arity, @intFromEnum(op), 1, &values)));
}
fn entry(s: *Scope, pair: c.JSValue, index: usize) !c.JSValue {
    var iterator = try js.Iterator.init(s.engine, pair, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var result = c.pi_js_undefined();
    for (0..index + 1) |_| {
        s.engine.freeValue(result);
        result = (try iterator.next()) orelse c.pi_js_undefined();
    }
    errdefer s.engine.freeValue(result);
    try iterator.close();
    return s.keep(result);
}
fn appendIterable(s: *Scope, list: c.JSValue, source: c.JSValue) !void {
    var iterator = try js.Iterator.init(s.engine, source, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |value| {
        defer s.engine.freeValue(value);
        try js.push(s.engine, list, value);
    }
}
fn invoke(engine: *h.Engine, work: c.JSValue, args: []const c.JSValue, op: Op) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const value = h.arg(args, 0);
    if (op == .value) return s.result(try entry(&s, value, 1));
    if (op == .wait) return js.invoke(engine, value, "whenHydrated", &.{});
    if (op == .exposed_pending or op == .derived_pending) {
        const hydration = try cells.hydrationOf(&s, try s.get(work, "bindings"), if (op == .exposed_pending) try entry(&s, value, 1) else value);
        if (op == .derived_pending) return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(hydration)));
        const hydrated = if (h.nullish(hydration)) c.pi_js_undefined() else try s.get(hydration, "hydrated");
        return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, hydrated, c.pi_js_bool(engine.context, 0))));
    }
    if (op == .exposed_name) return @import("native_utf16.zig").concat(engine, &.{ try s.get(try s.get(work, "object"), "address"), try s.text("."), try entry(&s, value, 0) });
    if (op == .derived_name) return @import("native_utf16.zig").concat(engine, &.{ try s.text("derive "), try s.get(value, "key") });
    if (op == .waiting) {
        const exposed = try h.invoke(&s, try s.get(work, "exposed"), "filter", &.{try function(&s, work, .exposed_pending, 1)});
        const names = try h.invoke(&s, exposed, "map", &.{try function(&s, work, .exposed_name, 1)});
        const derived = try h.invoke(&s, try s.get(work, "derives"), "filter", &.{try function(&s, work, .derived_pending, 1)});
        const derives = try h.invoke(&s, derived, "map", &.{try function(&s, work, .derived_name, 1)});
        const result = try s.list();
        try appendIterable(&s, result, names);
        try appendIterable(&s, result, derives);
        return s.result(result);
    }
    if (op == .timeout_executor) {
        try h.field(&s, work, "timeoutReject", h.arg(args, 1));
        const timer = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setTimeout")), c.pi_js_undefined(), &.{ try function(&s, work, .timeout, 0), try s.get(work, "ms") }));
        try h.field(&s, work, "timer", timer);
        const unref = try s.get(timer, "unref");
        if (!h.nullish(unref)) _ = try s.keep(try js.call(engine, unref, timer, &.{}));
        return c.pi_js_undefined();
    }
    const waiting = try s.keep(try js.call(engine, try s.get(work, "waiting"), c.pi_js_undefined(), &.{}));
    const suffix = if (try h.length(&s, waiting) == 0) try s.text("") else try r.concat(&s, &.{ try s.text(", waiting on "), try h.invoke(&s, waiting, "join", &.{try s.text(", ")}) });
    const reason = try h.errorValue(&s, try s.get(work, "bindings"), "unavailable", &.{ try s.get(try s.get(work, "object"), "address"), try s.text(" was not ready after "), try s.get(work, "ms"), try s.text(" ms"), suffix, try s.text(" (a reference cycle across hosts?)") }, try r.reason(&s, "ready_timeout"));
    return js.call(engine, try s.get(work, "timeoutReject"), c.pi_js_undefined(), &.{reason});
}
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn withinFinished(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")}));
    try async_work.complete(&s, work, value, rejected);
}
pub fn withinReadyTimeout(engine: *h.Engine, bindings: c.JSValue, object: c.JSValue, pending: c.JSValue, waiting: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    inline for (.{ "bindings", "object", "waiting" }, .{ bindings, object, waiting }) |name, value| try h.field(&s, work, name, value);
    const ms = try s.get(try s.get(object, "host"), "readyTimeout");
    try h.field(&s, work, "ms", ms);
    if (c.JS_ToBool(engine.context, try s.builtin("Number", "isFinite", &.{ms})) == 0) {
        try async_work.complete(&s, work, pending, false);
        return async_work.result(&s, work);
    }
    try h.field(&s, work, "timer", c.pi_js_undefined());
    const timeout = try s.keep(try js.builtin(engine, "Promise", &.{try function(&s, work, .timeout_executor, 2)}));
    const ignored = try s.keep(try engine.checked(c.JS_NewCFunction(engine.context, noop, "noop", 0)));
    _ = try h.invoke(&s, timeout, "catch", &.{ignored});
    const items = try s.list();
    try js.push(engine, items, pending);
    try js.push(engine, items, timeout);
    try async_work.wait(withinFinished, &s, work, try s.builtin("Promise", "race", &.{items}), 0);
    return async_work.result(&s, work);
}
fn hydrationFinished(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try async_work.complete(&s, work, if (rejected) value else c.pi_js_undefined(), rejected);
}
pub fn waitHydrated(engine: *h.Engine, bindings: c.JSValue, object: c.JSValue, run: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    inline for (.{ "bindings", "object" }, .{ bindings, object }) |name, value| try h.field(&s, work, name, value);
    const implementation = try s.get(run, "implementation");
    const exposed = try s.entries(if (h.nullish(implementation)) try s.record() else implementation);
    try h.field(&s, work, "exposed", exposed);
    const derives = try s.get(try s.get(run, "created"), "derives");
    try h.field(&s, work, "derives", derives);
    const sources = try s.list();
    try appendIterable(&s, sources, derives);
    try appendIterable(&s, sources, try h.invoke(&s, exposed, "map", &.{try function(&s, work, .value, 1)}));
    const pending = try cells.unhydrated(&s, bindings, sources);
    if (try h.length(&s, pending) == 0) {
        try async_work.complete(&s, work, c.pi_js_undefined(), false);
        return async_work.result(&s, work);
    }
    const promise = try s.keep(try js.global(engine, "Promise"));
    const all = try s.get(promise, "all");
    const waits = try h.invoke(&s, pending, "map", &.{try function(&s, work, .wait, 1)});
    const joined = try s.keep(try js.call(engine, all, promise, &.{waits}));
    const bounded = try s.keep(try withinReadyTimeout(engine, bindings, object, joined, try function(&s, work, .waiting, 0)));
    try async_work.wait(hydrationFinished, &s, work, bounded, 0);
    return async_work.result(&s, work);
}
