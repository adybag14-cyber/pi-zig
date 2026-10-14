//! Actual b45 object-owned cell initialization after resources/references open.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const async_work = @import("native_chord_async_work.zig");
fn invokeInit(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.call(engine, captures[0], c.pi_js_undefined(), &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn cellOpened(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) {
        try async_work.complete(&s, work, value, true);
        return;
    }
    if (!try h.flag(&s, try s.get(work, "signal"), "aborted")) _ = try h.invoke(&s, try s.get(work, "cell"), "initialize", &.{value});
    try async_work.complete(&s, work, c.pi_js_undefined(), false);
}
fn oneCell(engine: *h.Engine, object: c.JSValue, signal: c.JSValue, declaration: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    // Source destructures [cell, init] through its iterator, not numeric reads.
    var iterator = try js.Iterator.init(engine, declaration, try h.iteratorSymbol(&s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const cell = try s.keep((try iterator.next()) orelse c.pi_js_undefined());
    const init = try s.keep((try iterator.next()) orelse c.pi_js_undefined());
    try iterator.close();
    try h.field(&s, work, "cell", cell);
    try h.field(&s, work, "signal", signal);
    const host = try s.get(object, "host");
    const root = try s.get(host, "root");
    var values = [_]c.JSValue{init};
    const callback = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, invokeInit, "", 1, 0, 1, &values)));
    const options = try s.record();
    try h.field(&s, options, "signal", signal);
    const pending = try s.keep(try js.call(engine, root, host, &.{ callback, options }));
    try async_work.wait(cellOpened, &s, work, pending, 0);
    return async_work.result(&s, work);
}
fn mapper(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return oneCell(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn isRejected(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const status = s.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "status") catch |err| return @import("native_durable.zig").reject(engine, err);
    const rejected = s.equal(status, "rejected") catch |err| return @import("native_durable.zig").reject(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(rejected));
}
fn allSettled(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) {
        try async_work.complete(&s, work, value, true);
        return;
    }
    const predicate = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, isRejected, "", 1, 0, 0, null)));
    const failure = try h.invoke(&s, value, "find", &.{predicate});
    try async_work.complete(&s, work, if (c.JS_IsUndefined(failure)) c.pi_js_undefined() else try s.get(failure, "reason"), !c.JS_IsUndefined(failure));
}
pub fn initCells(engine: *h.Engine, object: c.JSValue, run: c.JSValue, signal: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    const inits = try s.get(try s.get(run, "created"), "inits");
    if (try h.length(&s, inits) == 0) {
        try async_work.complete(&s, work, c.pi_js_undefined(), false);
        return async_work.result(&s, work);
    }
    const promise = try s.keep(try js.global(engine, "Promise"));
    const all = try s.get(promise, "allSettled");
    var captures = [_]c.JSValue{ object, signal };
    const map = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, mapper, "", 1, 0, 2, &captures)));
    const async_prototype = try s.keep(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, map, async_prototype) < 0) return js.capture(engine);
    const jobs = try h.invoke(&s, inits, "map", &.{map});
    const pending = try s.keep(try js.call(engine, all, promise, &.{jobs}));
    try async_work.wait(allSettled, &s, work, pending, 0);
    return async_work.result(&s, work);
}
