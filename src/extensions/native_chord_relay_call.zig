//! Actual async relayCall: race route readiness with cancellation, forward once, always remove route waiter.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
fn noop(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_undefined();
}
fn errorValue(s: *Scope, work: c.JSValue) !c.JSValue {
    const options = try s.record();
    try h.field(s, options, "cause", try s.get(try s.get(work, "signal"), "reason"));
    return h.errorValue(s, try s.get(work, "bindings"), "aborted", &.{try s.text("call cancelled")}, options);
}
fn abort(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, phase: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return aborted(engine, captures[0], captures[1], phase != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn aborted(engine: *h.Engine, work: c.JSValue, target: c.JSValue, forwarding: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const failure = try errorValue(&s, work);
    if (forwarding) {
        _ = try h.invoke(&s, target, "cancel", &.{ failure, c.pi_js_bool(engine.context, 1) });
    } else {
        _ = try s.keep(try js.call(engine, target, c.pi_js_undefined(), &.{failure}));
    }
    return c.pi_js_undefined();
}
fn executor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, phase: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return execute(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), phase != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn execute(engine: *h.Engine, work: c.JSValue, resolve: c.JSValue, reject: c.JSValue, forwarded: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const signal = try s.get(work, "signal");
    const target = if (forwarded) target: {
        const pending = try s.record();
        try h.field(&s, pending, "resolve", resolve);
        try h.field(&s, pending, "reject", reject);
        break :target try h.construct(&s, try s.get(work, "bindings"), "RelayCall", &.{ try s.get(work, "relay"), try s.get(try s.get(work, "frame"), "id"), try h.invoke(&s, try s.get(work, "down"), "nextId", &.{}), pending });
    } else reject;
    var captures = [_]c.JSValue{ work, target };
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, abort, "onAbort", 0, @intFromBool(forwarded), 2, &captures)));
    if (!forwarded) try h.field(&s, work, "onAbort", listener);
    const options = try s.record();
    try h.field(&s, options, "once", c.pi_js_bool(engine.context, 1));
    _ = try h.invoke(&s, signal, "addEventListener", &.{ try s.text("abort"), listener, options });
    if (forwarded) {
        const root = try s.get(work, "root");
        const down = try s.get(work, "down");
        _ = try h.invoke(&s, try s.get(work, "host"), "rootSent", &.{ try s.get(root, "rootId"), down });
        const message = try s.record();
        try h.field(&s, message, "t", try s.text("call"));
        try h.field(&s, message, "id", try s.get(target, "downId"));
        try h.field(&s, message, "hold", try s.get(try s.get(work, "relay"), "downId"));
        const incoming = try s.get(work, "frame");
        inline for (.{ "member", "args" }) |name| try h.field(&s, message, name, try s.get(incoming, name));
        try h.field(&s, message, "root", root);
        _ = try h.invoke(&s, down, "send", &.{message});
    }
    return c.pi_js_undefined();
}
fn promise(s: *Scope, work: c.JSValue, forwarded: bool) !c.JSValue {
    var captures = [_]c.JSValue{work};
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, executor, "", 2, @intFromBool(forwarded), 1, &captures)));
    return s.keep(try js.builtin(s.engine, "Promise", &.{callback}));
}
fn cleanup(s: *Scope, work: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(work, "signal"), "removeEventListener", &.{ try s.text("abort"), try s.get(work, "onAbort") });
}
fn continuation(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (phase == 2 or rejected) {
        try cleanup(&s, work);
        return if (rejected) h.throwValue(&s, value) else s.result(value);
    }
    return forward(&s, work, value) catch |err| {
        // JavaScript finally may replace an exception only when cleanup itself throws.
        const failure = if (err == error.JavaScriptException) engine.captured_exception else null;
        const original = if (failure) |owned| c.JS_DupValue(engine.context, owned) else null;
        defer if (original) |owned| engine.freeValue(owned);
        try cleanup(&s, work);
        if (original) |owned| return h.throwValue(&s, owned);
        return err;
    };
}
fn forward(s: *Scope, work: c.JSValue, down: c.JSValue) !c.JSValue {
    if (try h.flag(s, try s.get(work, "relay"), "closed")) return h.throwValue(s, try h.errorValue(s, try s.get(work, "bindings"), "gone", &.{try s.text("relayed hold closed")}, c.pi_js_undefined()));
    try h.field(s, work, "down", down);
    return h.wait(continuation, s.engine, work, try promise(s, work, true), 2);
}
fn begin(engine: *h.Engine, bindings: c.JSValue, relay: c.JSValue, incoming: c.JSValue, root: c.JSValue, signal: c.JSValue, host: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const work = try s.record();
    inline for (.{ "bindings", "relay", "frame", "root", "signal", "host" }, .{ bindings, relay, incoming, root, signal, host }) |name, value| try h.field(&s, work, name, value);
    if (try h.flag(&s, signal, "aborted")) return h.throwValue(&s, try errorValue(&s, work));
    const ignored = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, noop, "", 0, 0, 0, null)));
    try h.field(&s, work, "onAbort", ignored);
    const cancellation = try promise(&s, work, false);
    _ = try h.invoke(&s, cancellation, "catch", &.{ignored});
    return race(&s, work, cancellation) catch |err| {
        const failure = if (err == error.JavaScriptException) engine.captured_exception else null;
        const original = if (failure) |owned| c.JS_DupValue(engine.context, owned) else null;
        defer if (original) |owned| engine.freeValue(owned);
        try cleanup(&s, work);
        if (original) |owned| return h.throwValue(&s, owned);
        return err;
    };
}
fn race(s: *Scope, work: c.JSValue, cancellation: c.JSValue) !c.JSValue {
    const promise_type = try s.keep(try js.global(s.engine, "Promise"));
    const race_function = try s.get(promise_type, "race");
    const ready = try h.invoke(s, try s.get(work, "relay"), "ready", &.{});
    const promises = try s.list();
    try js.push(s.engine, promises, ready);
    try js.push(s.engine, promises, cancellation);
    const raced = try s.keep(try js.call(s.engine, race_function, promise_type, &.{promises}));
    return h.wait(continuation, s.engine, work, raced, 1);
}
pub fn call(engine: *h.Engine, bindings: c.JSValue, relay: c.JSValue, incoming: c.JSValue, root: c.JSValue, signal: c.JSValue, host: c.JSValue) !c.JSValue {
    const pending = begin(engine, bindings, relay, incoming, root, signal, host) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(pending);
    return @import("native_durable.zig").resolvedPromise(engine, pending);
}
