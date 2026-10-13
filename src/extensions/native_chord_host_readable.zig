//! Actual stable late-bound Handle state member readable and publication rebinds.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { value, subscribe, events, bind, stop };
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn host(s: *Scope, data: c.JSValue) !c.JSValue {
    return s.get(try s.get(try s.get(data, "handle"), "record"), "host");
}
fn safe(s: *Scope, data: c.JSValue, listener: c.JSValue, value: c.JSValue) !void {
    const result = js.call(s.engine, listener, c.pi_js_undefined(), &.{value}) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try h.invoke(s, try host(s, data), "report", &.{s.engine.captured_exception orelse return err});
        return;
    };
    s.engine.freeValue(result);
}
fn current(s: *Scope, data: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const handle = try s.get(data, "handle");
    const name = try s.get(data, "name");
    const view = try h.invoke(s, handle, "currentView", &.{});
    if (c.JS_IsUndefined(view) or c.JS_ToBool(s.engine.context, try h.invoke(s, handle, "inVariant", &.{ view, name })) == 0) return c.pi_js_undefined();
    const value = try s.key(view, name);
    return if (try @import("native_chord_host_record_schema.zig").source(s, bindings, value) or try @import("native_chord_host_record_schema.zig").readable(s, value)) value else c.pi_js_undefined();
}
fn unlisten(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return remove(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn remove(engine: *h.Engine, data: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, data[2], "delete", &.{data[3]});
    _ = try h.invoke(&s, data[0], "bind", &.{});
    return c.pi_js_undefined();
}
fn upstream(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return receive(engine, data[0], data[1], data[2], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn receive(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, first: c.JSValue, event: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .MemberReadable)).data;
    const is_first = try h.flag(&s, first, "value");
    try h.field(&s, first, "value", c.pi_js_bool(engine.context, 0));
    const value = try s.get(event, "value");
    if (is_first and c.JS_IsStrictEqual(engine.context, value, try s.get(data, "seen"))) return c.pi_js_undefined();
    try h.field(&s, data, "seen", value);
    const translated = if (!is_first) event else blk: {
        const reset = try s.record();
        try h.field(&s, reset, "type", try s.text("reset"));
        try h.field(&s, reset, "value", value);
        break :blk reset;
    };
    var captures = [_]c.JSValue{ receiver, bindings, try h.snapshot(&s, try s.get(data, "events")), try h.snapshot(&s, try s.get(data, "values")), translated, value };
    const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, publish, "", 0, 0, 6, &captures)));
    try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
    return c.pi_js_undefined();
}
fn publish(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return published(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn published(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, captures[0], captures[1], .MemberReadable)).data;
    inline for (.{ "events", "values" }, 0..) |name, index| {
        const set = try s.get(data, name);
        const listeners = captures[index + 2];
        for (0..try h.length(&s, listeners)) |slot| {
            const listener = try s.at(listeners, slot);
            if (c.JS_ToBool(engine.context, try h.invoke(&s, set, "has", &.{listener})) != 0) try safe(&s, data, listener, captures[index + 4]);
        }
    }
    return c.pi_js_undefined();
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .MemberReadable)).data;
    if (method == .value) {
        const source = try current(&s, data, bindings);
        return if (c.JS_IsUndefined(source)) c.pi_js_undefined() else js.get(engine, source, "value");
    }
    if (method == .subscribe or method == .events) {
        const set = try s.get(data, if (method == .events) "events" else "values");
        _ = try h.invoke(&s, set, "add", &.{h.arg(args, 0)});
        const value = try s.get(receiver, "value");
        try h.field(&s, data, "seen", value);
        const announced = if (method == .subscribe) value else blk: {
            const event = try s.record();
            try h.field(&s, event, "type", try s.text("snap"));
            try h.field(&s, event, "value", value);
            break :blk event;
        };
        try safe(&s, data, h.arg(args, 0), announced);
        _ = try h.invoke(&s, receiver, "bind", &.{});
        var captures = [_]c.JSValue{ receiver, bindings, set, h.arg(args, 0) };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, unlisten, "", 0, 0, 4, &captures));
    }
    if (method == .stop) {
        _ = try h.invoke(&s, try s.get(data, "values"), "clear", &.{});
        _ = try h.invoke(&s, try s.get(data, "events"), "clear", &.{});
    }
    const listened = try @import("native_chord_host_record.zig").nonempty(&s, try s.get(data, "values")) or try @import("native_chord_host_record.zig").nonempty(&s, try s.get(data, "events"));
    const source = if (listened) try current(&s, data, bindings) else c.pi_js_undefined();
    if (c.JS_IsStrictEqual(engine.context, source, try s.get(data, "source"))) return c.pi_js_undefined();
    const previous = try s.get(data, "upstream");
    if (!c.JS_IsUndefined(previous)) _ = try s.keep(try js.call(engine, previous, c.pi_js_undefined(), &.{}));
    try h.field(&s, data, "upstream", c.pi_js_undefined());
    try h.field(&s, data, "source", source);
    if (c.JS_IsUndefined(source)) return c.pi_js_undefined();
    const first = try s.record();
    try h.field(&s, first, "value", c.pi_js_bool(engine.context, 1));
    var captures = [_]c.JSValue{ receiver, bindings, first };
    const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, upstream, "", 1, 0, 3, &captures)));
    try h.field(&s, data, "upstream", try h.invoke(&s, source, "events", &.{listener}));
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, values[0], .MemberReadable));
    const data = (try h.actor(&s, result, values[0], .MemberReadable)).data;
    try h.field(&s, data, "handle", h.arg(args, 0));
    try h.field(&s, data, "name", h.arg(args, 1));
    inline for (.{ "values", "events" }) |name| try h.field(&s, data, name, try h.set(&s));
    inline for (.{ "source", "upstream", "seen" }) |name| try h.field(&s, data, name, c.pi_js_undefined());
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .MemberReadable);
    const prototype = try s.record();
    try js.define(engine, bindings, "MemberReadable", try @import("native_class.zig").constructor(engine, "MemberReadable", 2, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "subscribe", Method.subscribe, 1, false }, .{ "events", Method.events, 1, false }, .{ "bind", Method.bind, 0, false }, .{ "stop", Method.stop, 0, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
