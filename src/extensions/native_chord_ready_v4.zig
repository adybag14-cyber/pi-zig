//! Actual b45 awaitReady/raceSignal lifecycle. Private graph dependency.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const async_work = @import("native_chord_async_work.zig");
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn abortCallback(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return abortRace(engine, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn abortRace(engine: *h.Engine, work: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const signal = try s.get(work, "signal");
    const options = try s.record();
    try h.field(&s, options, "cause", try s.get(signal, "reason"));
    const failure = try h.errorValue(&s, try s.get(work, "bindings"), "aborted", &.{try s.text("call aborted")}, options);
    return js.call(engine, try s.get(work, "abortReject"), c.pi_js_undefined(), &.{failure});
}
fn raceExecutor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return installAbort(engine, captures[0], if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn installAbort(engine: *h.Engine, work: c.JSValue, reject: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.field(&s, work, "abortReject", reject);
    var values = [_]c.JSValue{work};
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, abortCallback, "onAbort", 0, 0, 1, &values)));
    try h.field(&s, work, "onAbort", listener);
    const options = try s.record();
    try h.field(&s, options, "once", c.pi_js_bool(engine.context, 1));
    _ = try h.invoke(&s, try s.get(work, "signal"), "addEventListener", &.{ try s.text("abort"), listener, options });
    return c.pi_js_undefined();
}
fn raceFinished(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, try s.get(work, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(work, "onAbort") });
    try async_work.complete(&s, work, value, rejected);
}
fn startRace(s: *Scope, work: c.JSValue, promise: c.JSValue) !void {
    const signal = try s.get(work, "signal");
    if (try h.flag(s, signal, "aborted")) {
        const options = try s.record();
        try h.field(s, options, "cause", try s.get(signal, "reason"));
        try async_work.complete(s, work, try h.errorValue(s, try s.get(work, "bindings"), "aborted", &.{try s.text("call aborted")}, options), true);
        return;
    }
    try h.field(s, work, "onAbort", try s.keep(try s.engine.checked(c.JS_NewCFunction(s.engine.context, noop, "noop", 0))));
    var values = [_]c.JSValue{work};
    const executor = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, raceExecutor, "", 2, 0, 1, &values)));
    const aborted = try s.keep(try js.builtin(s.engine, "Promise", &.{executor}));
    const items = try s.list();
    try js.push(s.engine, items, promise);
    try js.push(s.engine, items, aborted);
    try async_work.wait(raceFinished, s, work, try s.builtin("Promise", "race", &.{items}), 0);
}
pub fn raceSignal(engine: *h.Engine, bindings: c.JSValue, promise: c.JSValue, signal: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    try h.field(&s, work, "bindings", bindings);
    try h.field(&s, work, "signal", signal);
    startRace(&s, work, promise) catch |err| try async_work.rejectError(&s, work, err);
    return async_work.result(&s, work);
}
fn timeoutCallback(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return expire(engine, captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn expire(engine: *h.Engine, work: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const failure = try h.errorValue(&s, try s.get(work, "bindings"), "unavailable", &.{ try s.get(try s.get(work, "ref"), "address"), try s.text(" was not ready after "), try s.get(work, "ms"), try s.text(" ms") }, try r.reason(&s, "ready_timeout"));
    return js.invoke(engine, try s.get(work, "timeout"), "abort", &.{failure});
}
fn cleanup(s: *Scope, work: c.JSValue) !void {
    _ = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "clearTimeout")), c.pi_js_undefined(), &.{try s.get(work, "timer")}));
    _ = try h.invoke(s, try s.get(work, "linked"), "release", &.{});
}
fn rejectedReason(s: *Scope, work: c.JSValue, value: c.JSValue) !c.JSValue {
    _ = try h.invoke(s, try s.get(work, "ref"), "release", &.{});
    const reason = try s.get(try s.get(try s.get(work, "linked"), "signal"), "reason");
    const chord = c.JS_IsInstanceOf(s.engine.context, reason, try s.get(try s.get(try s.get(work, "bindings"), "errors"), "ChordError"));
    if (chord < 0) return js.capture(s.engine);
    return if (chord != 0 and try s.equal(try s.get(reason, "reason"), "ready_timeout")) reason else value;
}
fn readyFinished(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const reason = if (rejected) rejectedReason(&s, work, value) catch |err| {
        try cleanup(&s, work);
        return err;
    } else c.pi_js_undefined();
    try cleanup(&s, work);
    try async_work.complete(&s, work, reason, rejected);
}
fn readyRace(s: *Scope, work: c.JSValue, linked: c.JSValue) !void {
    const pending = try s.keep(try raceSignal(s.engine, try s.get(work, "bindings"), try s.get(try s.get(work, "ref"), "ready"), try s.get(linked, "signal")));
    try async_work.wait(readyFinished, s, work, pending, 0);
}
fn startReady(s: *Scope, work: c.JSValue, signals: c.JSValue) !void {
    const timeout = try s.keep(try js.builtin(s.engine, "AbortController", &.{}));
    try h.field(s, work, "timeout", timeout);
    var timer = c.pi_js_undefined();
    if (c.JS_ToBool(s.engine.context, try s.builtin("Number", "isFinite", &.{try s.get(work, "ms")})) != 0) {
        var values = [_]c.JSValue{work};
        const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, timeoutCallback, "", 0, 0, 1, &values)));
        timer = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "setTimeout")), c.pi_js_undefined(), &.{ callback, try s.get(work, "ms") }));
    }
    try h.field(s, work, "timer", timer);
    if (!h.nullish(timer)) {
        const unref = try s.get(timer, "unref");
        if (!h.nullish(unref)) _ = try s.keep(try js.call(s.engine, unref, timer, &.{}));
    }
    const sources = try s.list();
    var iterator = try js.Iterator.init(s.engine, signals, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |source| {
        defer s.engine.freeValue(source);
        try js.push(s.engine, sources, source);
    }
    try js.push(s.engine, sources, try s.get(timeout, "signal"));
    const linked = try @import("native_chord_signal.zig").linked(s, sources);
    try h.field(s, work, "linked", linked);
    readyRace(s, work, linked) catch |err| {
        _ = @import("native_durable.zig").reject(s.engine, err);
        const failure = try s.keep(c.JS_GetException(s.engine.context));
        try readyFinished(s.engine, work, failure, true, 0);
    };
}
pub fn awaitReady(engine: *h.Engine, bindings: c.JSValue, ref: c.JSValue, signals: c.JSValue, ms: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try async_work.create(&s);
    inline for (.{ "bindings", "ref", "ms" }, .{ bindings, ref, ms }) |name, value| try h.field(&s, work, name, value);
    startReady(&s, work, signals) catch |err| try async_work.rejectError(&s, work, err);
    return async_work.result(&s, work);
}
