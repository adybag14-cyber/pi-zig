//! Actual b45 per-view listeners over the shared binding member state.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const Method = enum(c_int) { value, hydration, subscribe, events, deliver, stop };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn safe(s: *Scope, binding: c.JSValue, listener: c.JSValue, value: c.JSValue) !void {
    const result = js.call(s.engine, listener, c.pi_js_undefined(), &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try h.invoke(s, try s.get(binding, "host"), "report", &.{s.engine.captured_exception orelse return err});
        return;
    };
    s.engine.freeValue(result);
}
fn snap(s: *Scope, value: c.JSValue) !c.JSValue {
    const event = try s.record();
    try h.field(s, event, "type", try s.text("snap"));
    try h.field(s, event, "value", value);
    return event;
}
fn wait(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "whenHydrated", &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn off(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return remove(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn remove(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = (try h.actor(&s, captures[0], captures[1], .ViewReadable)).data;
    if (c.JS_ToBool(engine.context, captures[4]) != 0) _ = try h.invoke(&s, try s.get(owned, "unseen"), "delete", &.{captures[3]});
    _ = try h.invoke(&s, captures[2], "delete", &.{captures[3]});
    if (!try @import("native_chord_object.zig").nonempty(&s, try s.get(owned, "values")) and !try @import("native_chord_object.zig").nonempty(&s, try s.get(owned, "events"))) {
        _ = try h.invoke(&s, try s.get(try s.get(captures[0], "view"), "binding"), "unlisten", &.{ try s.get(owned, "name"), captures[0] });
    }
    return c.pi_js_undefined();
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, arg: c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = (try h.actor(&s, receiver, bindings, .ViewReadable)).data;
    const view = try s.get(receiver, "view");
    const binding = try s.get(view, "binding");
    const name = try s.get(owned, "name");
    if (method == .value) {
        if (try h.flag(&s, view, "ended")) return h.throwValue(&s, try h.invoke(&s, view, "terminalError", &.{}));
        return js.invoke(engine, binding, "read", &.{name});
    }
    if (method == .hydration) {
        if (try h.flag(&s, binding, "hydrated")) return c.pi_js_undefined();
        const hydration = try s.record();
        try h.field(&s, hydration, "hydrated", c.pi_js_bool(engine.context, 0));
        var captures = [_]c.JSValue{binding};
        try js.define(engine, hydration, "whenHydrated", try engine.checked(c.JS_NewCFunctionData2(engine.context, wait, "whenHydrated", 0, 0, 1, &captures)));
        return s.result(hydration);
    }
    if (method == .subscribe or method == .events) {
        const set = try s.get(owned, if (method == .subscribe) "values" else "events");
        _ = try h.invoke(&s, set, "add", &.{arg});
        if (!try h.flag(&s, view, "ended")) _ = try h.invoke(&s, binding, "listen", &.{ name, receiver });
        const readable = !try h.flag(&s, view, "ended") and c.JS_ToBool(engine.context, try h.invoke(&s, binding, "readable", &.{name})) != 0;
        if (readable) {
            const member = try h.invoke(&s, try s.get(binding, "members"), "get", &.{name});
            const value = if (h.nullish(member)) c.pi_js_undefined() else try s.get(member, "value");
            try safe(&s, binding, arg, if (method == .subscribe) value else try snap(&s, value));
        } else if (method == .events) _ = try h.invoke(&s, try s.get(owned, "unseen"), "add", &.{arg});
        var captures = [_]c.JSValue{ receiver, bindings, set, arg, c.pi_js_bool(engine.context, @intFromBool(method == .events)) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, off, "", 0, 0, 5, &captures));
    }
    if (method == .stop) {
        inline for (.{ "values", "events", "unseen" }) |field| _ = try h.invoke(&s, try s.get(owned, field), "clear", &.{});
        _ = try h.invoke(&s, binding, "unlisten", &.{ name, receiver });
        return c.pi_js_undefined();
    }
    const listeners = try h.snapshot(&s, try s.get(owned, "events"));
    for (0..try h.length(&s, listeners)) |index| {
        const listener = try s.at(listeners, index);
        if (c.JS_ToBool(engine.context, try h.invoke(&s, try s.get(owned, "unseen"), "delete", &.{listener})) == 0) {
            try safe(&s, binding, listener, arg);
        } else if (!try s.equal(try s.get(arg, "type"), "ops")) try safe(&s, binding, listener, try snap(&s, try s.get(arg, "value")));
    }
    const values = try h.snapshot(&s, try s.get(owned, "values"));
    for (0..try h.length(&s, values)) |index| try safe(&s, binding, try s.at(values, index), try s.get(arg, "value"));
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .ViewReadable));
    const owned = (try h.actor(&s, result, captures[0], .ViewReadable)).data;
    try h.field(&s, result, "view", h.arg(args, 0));
    try h.field(&s, owned, "name", h.arg(args, 1));
    inline for (.{ "values", "events", "unseen" }) |field| try h.field(&s, owned, field, try h.set(&s));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ViewReadable);
    const prototype = try s.record();
    try js.define(engine, bindings, "ViewReadable", try @import("native_class.zig").constructor(engine, "ViewReadable", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "subscribe", Method.subscribe, 1, false }, .{ "events", Method.events, 1, false }, .{ "deliver", Method.deliver, 1, false }, .{ "stop", Method.stop, 0, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
    const atom = try js.atom(engine, try s.get(bindings, "HYDRATION"));
    defer c.JS_FreeAtom(engine.context, atom);
    var captures = [_]c.JSValue{bindings};
    const getter = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "get [chord.hydration]", 0, @intFromEnum(Method.hydration), 1, &captures));
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
