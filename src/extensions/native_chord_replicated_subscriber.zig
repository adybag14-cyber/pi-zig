//! Actual per-subscriber serialized delivery and bounded latest-value queue.
const r = @import("native_chord_replicated_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { push, drain, clear, close };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn resumed(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, rejected: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return resumeDelivery(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), rejected != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn resumeDelivery(engine: *h.Engine, subscriber: c.JSValue, bindings: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, subscriber, bindings, .ReplicatedSubscriber);
    if (rejected) try r.report(&s, subscriber, try s.get(owned, "reportError"), value);
    try h.field(&s, owned, "running", c.pi_js_bool(engine.context, 0));
    return invoke(engine, subscriber, bindings, c.pi_js_undefined(), .drain);
}
fn deliver(s: *Scope, subscriber: c.JSValue, bindings: c.JSValue, owned: c.JSValue, frame: c.JSValue) !bool {
    const result = try s.keep(try js.call(s.engine, try s.get(owned, "listener"), subscriber, &.{ try s.get(frame, "value"), try s.get(frame, "context"), try s.get(frame, "delivery") }));
    if (!try r.promiseLike(s, result)) return false;
    // The original Source explicitly uses public Promise.resolve(...).then.
    const resolved = try s.builtin("Promise", "resolve", &.{result});
    var captures = [_]c.JSValue{ subscriber, bindings };
    const fulfilled = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, resumed, "", 0, 0, 2, &captures)));
    const rejected = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, resumed, "", 1, 1, 2, &captures)));
    _ = try h.invoke(s, resolved, "then", &.{ fulfilled, rejected });
    return true;
}
fn invoke(engine: *h.Engine, subscriber: c.JSValue, bindings: c.JSValue, arg: c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, subscriber, bindings, .ReplicatedSubscriber);
    const pending = try s.get(owned, "pending");
    switch (method) {
        .push => {
            if (try h.flag(&s, owned, "closed")) return c.pi_js_undefined();
            if (c.JS_IsStrictEqual(engine.context, try s.get(pending, "length"), c.JS_NewInt32(engine.context, 100))) {
                const hydration = if (try h.flag(&s, owned, "started")) c.pi_js_undefined() else try s.at(pending, 0);
                try js.setKey(engine, pending, try s.text("length"), c.JS_NewInt32(engine.context, 0));
                if (!c.JS_IsUndefined(hydration)) _ = try h.invoke(&s, pending, "push", &.{hydration});
            }
            _ = try h.invoke(&s, pending, "push", &.{arg});
        },
        .clear, .close => {
            if (method == .close) try h.field(&s, owned, "closed", c.pi_js_bool(engine.context, 1));
            try js.setKey(engine, pending, try s.text("length"), c.JS_NewInt32(engine.context, 0));
        },
        .drain => {
            if (try h.flag(&s, owned, "running") or try h.flag(&s, owned, "closed")) return c.pi_js_undefined();
            try h.field(&s, owned, "running", c.pi_js_bool(engine.context, 1));
            while (true) {
                const frame = try h.invoke(&s, pending, "shift", &.{});
                if (c.JS_IsUndefined(frame)) break;
                try h.field(&s, owned, "started", c.pi_js_bool(engine.context, 1));
                const generation = engine.native_allocation_generation;
                const waiting = deliver(&s, subscriber, bindings, owned, frame) catch |err| {
                    const mapped = engine.nativeAllocationError(err, generation);
                    if (mapped != error.JavaScriptException) return mapped;
                    try r.report(&s, subscriber, try s.get(owned, "reportError"), engine.captured_exception orelse return err);
                    continue;
                };
                if (waiting) return c.pi_js_undefined();
            }
            try h.field(&s, owned, "running", c.pi_js_bool(engine.context, 0));
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const subscriber = try s.keep(try h.allocate(engine, target, captures[0], .ReplicatedSubscriber));
    const owned = try r.own(&s, subscriber, captures[0], .ReplicatedSubscriber);
    try h.field(&s, owned, "listener", h.arg(args, 0));
    try h.field(&s, owned, "reportError", h.arg(args, 1));
    try h.field(&s, owned, "pending", try s.list());
    inline for (.{ "running", "started", "closed" }) |field| try h.field(&s, owned, field, c.pi_js_bool(engine.context, 0));
    return s.result(subscriber);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ReplicatedSubscriber);
    const prototype = try s.record();
    try js.define(engine, bindings, "StateSubscriber", try @import("native_class.zig").constructor(engine, "StateSubscriber", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "push", Method.push, 1 }, .{ "drain", Method.drain, 0 }, .{ "clear", Method.clear, 0 }, .{ "close", Method.close, 0 } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], false, false);
}
