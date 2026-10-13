//! Actual Derived lifecycle, external subscriptions and ordered graph publication.
const h = @import("native_chord_host_values.zig");
const base = @import("native_chord_cells.zig");
const graph = @import("native_chord_cells_graph.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const Method = enum(c_int) { value, attach, detach, compute, set_fn, refresh, install };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn read(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "value") catch |err| @import("native_durable.zig").reject(engine, err);
}
fn reader(s: *Scope) !c.JSValue {
    return s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, read, "", 1, 0, 0, null)));
}
fn external(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "refresh", &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn held(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return publish(engine, captures) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn publish(engine: *h.Engine, captures: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, captures[0], "install", &.{captures[1]});
    try graph.install(&s, captures[2]);
    return c.pi_js_undefined();
}
fn refresh(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !void {
    const next = try h.invoke(s, receiver, "compute", &.{try reader(s)});
    const dependents = try graph.compute(s, receiver, next, true);
    var captures = [_]c.JSValue{ receiver, next, dependents };
    const task = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, held, "", 0, 0, 3, &captures)));
    _ = try s.keep(try @import("native_chord_publish.zig").hold(s.engine, bindings, task));
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .Derived)).data;
    if (method == .value) return js.get(engine, data, "value");
    if (method == .set_fn) {
        try h.field(&s, data, "fn", h.arg(args, 0));
        return c.pi_js_undefined();
    }
    if (method == .compute) {
        const function = if (c.JS_IsUndefined(h.arg(args, 1))) try s.get(data, "fn") else args[1];
        const values = try h.invoke(&s, try s.get(receiver, "sources"), "map", &.{h.arg(args, 0)});
        const result = try s.keep(try @import("native_iterator_spread.zig").call(engine, c.pi_js_undefined(), function, values));
        const promise = c.JS_IsInstanceOf(engine.context, result, try s.keep(try js.global(engine, "Promise")));
        if (promise < 0) return js.capture(engine);
        if (promise != 0) return h.typeError(&s, &.{ try s.text("derive "), try s.get(receiver, "key"), try s.text(": fn must be synchronous") });
        return s.result(result);
    }
    if (method == .refresh) {
        refresh(&s, receiver, bindings) catch |err| {
            if (err != error.JavaScriptException) return err;
            const failure = try s.keep(c.JS_DupValue(engine.context, engine.captured_exception orelse return err));
            try base.report(&s, receiver, failure);
        };
        return c.pi_js_undefined();
    }
    if (method == .install) {
        const before = try s.get(data, "value");
        const next = h.arg(args, 0);
        try h.field(&s, data, "value", next);
        const operations = if (c.JS_IsUndefined(before) or c.JS_IsUndefined(next)) replacement: {
            const op = try s.list();
            try js.push(engine, op, try s.text("r"));
            try js.push(engine, op, if (h.nullish(next)) c.pi_js_null() else next);
            const result = try s.list();
            try js.push(engine, result, op);
            break :replacement result;
        } else try s.keep(try @import("native_chord_delta_diff.zig").diffRevisions(engine, before, next));
        if (try h.length(&s, operations) > 0) {
            const event = try s.record();
            try h.field(&s, event, "type", try s.text("ops"));
            try h.field(&s, event, "ops", operations);
            try h.field(&s, event, "value", next);
            _ = try h.invoke(&s, try s.get(receiver, "fanout"), "emit", &.{event});
        }
        return c.pi_js_undefined();
    }
    if (method == .attach) {
        const precomputed = h.arg(args, 0);
        const next = if (!h.nullish(precomputed) and c.JS_ToBool(engine.context, try h.invoke(&s, precomputed, "has", &.{receiver})) != 0) try h.invoke(&s, precomputed, "get", &.{receiver}) else try h.invoke(&s, receiver, "compute", &.{try reader(&s)});
        try h.field(&s, data, "value", next);
    }
    const symbol = try h.iteratorSymbol(&s);
    var iterator = try js.Iterator.init(engine, try s.get(receiver, "sources"), symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |source| {
        defer engine.freeValue(source);
        if (try base.isSource(&s, bindings, source)) {
            _ = try h.invoke(&s, try s.get(source, "dependents"), if (method == .attach) "add" else "delete", &.{receiver});
        } else if (method == .attach) {
            // Resolve push before calling subscribe, as in external.push(source.subscribe(...)).
            const subscriptions = try s.get(data, "external");
            const push = try s.get(subscriptions, "push");
            var captures = [_]c.JSValue{receiver};
            const listener = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, external, "", 0, 0, 1, &captures)));
            const unsubscribe = try h.invoke(&s, source, "subscribe", &.{listener});
            _ = try s.keep(try js.call(engine, push, subscriptions, &.{unsubscribe}));
        }
    }
    if (method == .detach) {
        const subscriptions = try h.invoke(&s, try s.get(data, "external"), "splice", &.{c.JS_NewInt32(engine.context, 0)});
        var unsubscribes = try js.Iterator.init(engine, subscriptions, symbol);
        defer unsubscribes.deinit();
        errdefer unsubscribes.closePreserving();
        while (try unsubscribes.next()) |unsubscribe| {
            defer engine.freeValue(unsubscribe);
            _ = try s.keep(try js.call(engine, unsubscribe, c.pi_js_undefined(), &.{}));
        }
    }
    return c.pi_js_undefined();
}
fn checkSource(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return checkedSource(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn checkedSource(engine: *h.Engine, source: c.JSValue, key: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (!c.JS_IsObject(source) or c.JS_IsFunction(engine.context, source) or !c.JS_IsFunction(engine.context, try s.get(source, "subscribe")) or !try js.hasKey(engine, source, try s.text("value"))) return h.typeError(&s, &.{ try s.text("derive "), key, try s.text(": sources must be readables") });
    return s.result(source);
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .Derived));
    try base.initialize(&s, bindings, result, h.arg(args, 0), h.arg(args, 3));
    const data = (try h.actor(&s, result, bindings, .Derived)).data;
    try h.field(&s, data, "external", try s.list());
    var values = [_]c.JSValue{h.arg(args, 0)};
    const check = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, checkSource, "", 1, 0, 1, &values)));
    try h.field(&s, result, "sources", try h.invoke(&s, h.arg(args, 1), "map", &.{check}));
    try h.field(&s, data, "fn", h.arg(args, 2));
    try h.field(&s, data, "value", c.pi_js_undefined());
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .Derived);
    const source = try s.get(bindings, "Source");
    const prototype = try s.keep(try engine.checked(c.JS_NewObjectProto(engine.context, try s.get(source, "prototype"))));
    const constructor = try s.keep(try @import("native_class.zig").constructor(engine, "Derived", 4, prototype, construct, &.{bindings}));
    if (c.JS_SetPrototype(engine.context, constructor, source) < 0) return js.capture(engine);
    try h.field(&s, bindings, "Derived", constructor);
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "attach", Method.attach, 1, false }, .{ "detach", Method.detach, 0, false }, .{ "compute", Method.compute, 1, false }, .{ "setFn", Method.set_fn, 1, false }, .{ "refresh", Method.refresh, 0, false }, .{ "install", Method.install, 1, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
