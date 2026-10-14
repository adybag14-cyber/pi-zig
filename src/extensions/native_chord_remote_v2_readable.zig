//! Actual subscribed remote state: per-feed decoder, reset hydration and reconnect lifetime.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { value, subscribe, events, bind, detach, stop };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn report(s: *Scope, data: c.JSValue, failure: c.JSValue) !void {
    _ = try h.invoke(s, try s.get(try s.get(data, "handle"), "host"), "report", &.{failure});
}
fn safe(s: *Scope, data: c.JSValue, listener: c.JSValue, value: c.JSValue) !void {
    const returned = js.call(s.engine, listener, c.pi_js_undefined(), &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        try report(s, data, s.engine.captured_exception orelse return err);
        return;
    };
    s.engine.freeValue(returned);
}
fn off(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return remove(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn remove(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, captures[1], "delete", &.{captures[2]});
    _ = try h.invoke(&s, captures[0], "bind", &.{});
    return c.pi_js_undefined();
}
fn incoming(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return receive(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn receive(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, frame: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .RemoteReadable)).data;
    const error_value = try s.get(frame, "error");
    if (!c.JS_IsUndefined(error_value)) {
        try report(&s, data, try h.invoke(&s, try s.get(bindings, "Wire"), "fromWireError", &.{error_value}));
        return c.pi_js_undefined();
    }
    const first_ops = try s.get(frame, "ops");
    if (c.JS_IsUndefined(first_ops) and !try js.hasKey(engine, frame, try s.text("snap")) and !try js.hasKey(engine, frame, try s.text("reset"))) return c.pi_js_undefined();
    const event = try s.record();
    const codec = try s.get(bindings, "DeltaCodec");
    const operations = try s.get(frame, "ops");
    if (!c.JS_IsUndefined(operations)) {
        const decoded = try h.invoke(&s, try s.get(data, "decoder"), "decode", &.{try s.get(frame, "ops")});
        const next = try h.invoke(&s, codec, "applyImmutable", &.{ try s.get(data, "value"), decoded });
        try h.field(&s, data, "value", next);
        try h.field(&s, event, "type", try s.text("ops"));
        try h.field(&s, event, "ops", decoded);
        try h.field(&s, event, "value", next);
    } else {
        try h.field(&s, data, "decoder", try h.invoke(&s, codec, "decoder", &.{}));
        const next = try s.get(frame, if (try js.hasKey(engine, frame, try s.text("snap"))) "snap" else "reset");
        try h.field(&s, data, "value", next);
        try h.field(&s, event, "type", try s.text("reset"));
        try h.field(&s, event, "value", next);
    }
    const event_listeners = try h.snapshot(&s, try s.get(data, "events"));
    for (0..try h.length(&s, event_listeners)) |index| try safe(&s, data, try s.at(event_listeners, index), event);
    const value_listeners = try h.snapshot(&s, try s.get(data, "values"));
    for (0..try h.length(&s, value_listeners)) |index| try safe(&s, data, try s.at(value_listeners, index), try s.get(data, "value"));
    return c.pi_js_undefined();
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .RemoteReadable)).data;
    if (method == .value) return js.get(engine, data, "value");
    if (method == .subscribe or method == .events) {
        const listeners = try s.get(data, if (method == .subscribe) "values" else "events");
        _ = try h.invoke(&s, listeners, "add", &.{h.arg(args, 0)});
        const value = if (method == .subscribe) try s.get(data, "value") else event: {
            const event = try s.record();
            try h.field(&s, event, "type", try s.text("snap"));
            try h.field(&s, event, "value", try s.get(data, "value"));
            break :event event;
        };
        try safe(&s, data, h.arg(args, 0), value);
        _ = try h.invoke(&s, receiver, "bind", &.{});
        var captures = [_]c.JSValue{ receiver, listeners, h.arg(args, 0) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, off, "", 0, 0, 3, &captures));
    }
    if (method == .detach) {
        try h.field(&s, data, "sub", c.pi_js_undefined());
        return c.pi_js_undefined();
    }
    if (method == .stop) {
        inline for (.{ "values", "events" }) |name| _ = try h.invoke(&s, try s.get(data, name), "clear", &.{});
        _ = try h.invoke(&s, receiver, "bind", &.{});
        return c.pi_js_undefined();
    }
    var value_count: f64 = 0;
    var event_count: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &value_count, try s.get(try s.get(data, "values"), "size")) < 0 or c.JS_ToFloat64(engine.context, &event_count, try s.get(try s.get(data, "events"), "size")) < 0) return js.capture(engine);
    const listening = value_count + event_count > 0;
    if (!listening) try h.field(&s, data, "value", c.pi_js_undefined());
    const binding = if (listening) try s.get(try s.get(data, "handle"), "binding") else c.pi_js_undefined();
    const sub = try s.get(data, "sub");
    const old_channel = if (h.nullish(sub)) c.pi_js_undefined() else try s.get(sub, "channel");
    if (!c.JS_IsUndefined(binding) and c.JS_IsStrictEqual(engine.context, old_channel, try s.get(binding, "channel"))) return c.pi_js_undefined();
    if (!c.JS_IsUndefined(sub)) {
        const next_channel = if (h.nullish(binding)) c.pi_js_undefined() else try s.get(binding, "channel");
        if (!c.JS_IsStrictEqual(engine.context, old_channel, next_channel) or c.JS_IsUndefined(binding)) _ = try h.invoke(&s, old_channel, "unsub", &.{try s.get(sub, "id")});
        try h.field(&s, data, "sub", c.pi_js_undefined());
    }
    if (c.JS_IsUndefined(binding)) return c.pi_js_undefined();
    const channel = try s.get(binding, "channel");
    try h.field(&s, data, "decoder", try h.invoke(&s, try s.get(bindings, "DeltaCodec"), "decoder", &.{}));
    var captures = [_]c.JSValue{ receiver, bindings };
    const sink = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, incoming, "", 1, 0, 2, &captures)));
    const id = try h.invoke(&s, channel, "sub", &.{ try s.get(binding, "id"), try s.get(data, "name"), sink });
    const installed = try s.record();
    try h.field(&s, installed, "channel", channel);
    try h.field(&s, installed, "id", id);
    try h.field(&s, data, "sub", installed);
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .RemoteReadable));
    const data = (try h.actor(&s, result, captures[0], .RemoteReadable)).data;
    try h.field(&s, data, "handle", h.arg(args, 0));
    try h.field(&s, data, "name", h.arg(args, 1));
    inline for (.{ "values", "events" }) |name| try h.field(&s, data, name, try h.set(&s));
    try h.field(&s, data, "sub", c.pi_js_undefined());
    try h.field(&s, data, "decoder", try h.invoke(&s, try s.get(captures[0], "DeltaCodec"), "decoder", &.{}));
    try h.field(&s, data, "value", c.pi_js_undefined());
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RemoteReadable);
    const prototype = try s.record();
    try js.define(engine, bindings, "RemoteReadable", try @import("native_class.zig").constructor(engine, "RemoteReadable", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "subscribe", Method.subscribe, 1, false }, .{ "events", Method.events, 1, false }, .{ "bind", Method.bind, 0, false }, .{ "detach", Method.detach, 0, false }, .{ "stop", Method.stop, 0, false } }) |entry| try h.define(&s, prototype, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], entry[3], false);
}
