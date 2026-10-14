//! Actual immutable revision publication, hydration cursors and reentrant order.
const r = @import("native_chord_replicated_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const Method = enum(c_int) { value, snapshot, subscribe, publish };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn defaultReport(engine: *h.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try r.reportAsync(&s, h.arg(args, 0));
    return c.pi_js_undefined();
}
pub fn reporter(s: *Scope) !c.JSValue {
    return s.keep(try @import("native_node_function.zig").create(s.engine, "reportErrorAsync", 1, defaultReport, &.{}));
}
fn off(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return unsubscribe(engine, captures[0], captures[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn unsubscribe(engine: *h.Engine, subscriber: c.JSValue, listeners: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    _ = try h.invoke(&s, subscriber, "close", &.{});
    _ = try h.invoke(&s, listeners, "delete", &.{subscriber});
    return c.pi_js_undefined();
}
fn delivery(s: *Scope, kind: []const u8, sequence: c.JSValue) !c.JSValue {
    const value = try s.record();
    try h.field(s, value, "kind", try s.text(kind));
    try h.field(s, value, "sequence", sequence);
    return value;
}
fn frame(s: *Scope, value: c.JSValue, context: c.JSValue, detail: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "value", value);
    try h.field(s, result, "context", context);
    try h.field(s, result, "delivery", detail);
    return result;
}
fn publishPending(s: *Scope, owned: c.JSValue) !void {
    const publications = try s.get(owned, "publications");
    const listeners = try s.get(owned, "listeners");
    while (true) {
        const publication = try h.invoke(s, publications, "shift", &.{});
        if (c.JS_IsUndefined(publication)) return;
        const detail = try delivery(s, "update", try s.get(publication, "sequence"));
        const current = try h.snapshot(s, listeners);
        var iterator = try js.Iterator.init(s.engine, current, try h.iteratorSymbol(s));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |entry| {
            defer s.engine.freeValue(entry);
            const pair = try js.pair(s.engine, entry, try h.iteratorSymbol(s));
            defer for (pair) |value| s.engine.freeValue(value);
            if (c.JS_ToBool(s.engine.context, try r.binary(s, 5, try s.get(publication, "sequence"), pair[1])) != 0) continue;
            _ = try h.invoke(s, pair[0], "push", &.{try frame(s, try s.get(publication, "value"), try s.get(publication, "context"), detail)});
            _ = try h.invoke(s, pair[0], "drain", &.{});
        }
    }
}
fn invoke(engine: *h.Engine, publisher: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = try r.own(&s, publisher, bindings, .ReplicatedPublisher);
    if (method == .value) return s.result(try s.get(owned, "value"));
    if (method == .snapshot) {
        const value = try s.record();
        inline for (.{ "value", "sequence" }) |field| try h.field(&s, value, field, try s.get(owned, field));
        return s.result(value);
    }
    if (method == .subscribe) {
        const snapshot = try h.invoke(&s, publisher, "snapshot", &.{});
        const value = try s.get(snapshot, "value");
        const sequence = try s.get(snapshot, "sequence");
        const subscriber = try h.construct(&s, bindings, "StateSubscriber", &.{ h.arg(args, 0), try s.get(owned, "reportError") });
        const listeners = try s.get(owned, "listeners");
        _ = try h.invoke(&s, listeners, "set", &.{ subscriber, sequence });
        _ = try h.invoke(&s, subscriber, "push", &.{try frame(&s, value, try s.get(bindings, "background"), try delivery(&s, "hydrate", sequence))});
        _ = try h.invoke(&s, subscriber, "drain", &.{});
        var captures = [_]c.JSValue{ subscriber, listeners };
        return engine.checked(c.JS_NewCFunctionData2(engine.context, off, "", 0, 0, 2, &captures));
    }
    try h.field(&s, owned, "value", h.arg(args, 0));
    const sequence = try r.binary(&s, 0, try s.get(owned, "sequence"), c.JS_NewInt32(engine.context, 1));
    try h.field(&s, owned, "sequence", sequence);
    const publication = try s.record();
    inline for (.{ "value", "sequence", "context" }, .{ h.arg(args, 0), sequence, h.arg(args, 1) }) |name, value| try h.field(&s, publication, name, value);
    _ = try h.invoke(&s, try s.get(owned, "publications"), "push", &.{publication});
    if (try h.flag(&s, owned, "delivering")) return c.pi_js_undefined();
    try h.field(&s, owned, "delivering", c.pi_js_bool(engine.context, 1));
    publishPending(&s, owned) catch |err| {
        try h.field(&s, owned, "delivering", c.pi_js_bool(engine.context, 0));
        return err;
    };
    try h.field(&s, owned, "delivering", c.pi_js_bool(engine.context, 0));
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const publisher = try s.keep(try h.allocate(engine, target, captures[0], .ReplicatedPublisher));
    const owned = try r.own(&s, publisher, captures[0], .ReplicatedPublisher);
    try h.field(&s, owned, "value", h.arg(args, 0));
    try h.field(&s, owned, "sequence", c.JS_NewInt32(engine.context, 0));
    const error_reporter = h.arg(args, 1);
    try h.field(&s, owned, "reportError", if (c.JS_IsUndefined(error_reporter)) try reporter(&s) else error_reporter);
    try h.field(&s, owned, "listeners", try h.map(&s));
    try h.field(&s, owned, "publications", try s.list());
    try h.field(&s, owned, "delivering", c.pi_js_bool(engine.context, 0));
    return s.result(publisher);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .ReplicatedPublisher);
    const prototype = try s.record();
    try js.define(engine, bindings, "ReplicatedStatePublisher", try @import("native_class.zig").constructor(engine, "ReplicatedStatePublisher", 1, prototype, construct, &.{bindings}));
    inline for (.{ .{ "value", Method.value, 0, true }, .{ "snapshot", Method.snapshot, 0, false }, .{ "subscribe", Method.subscribe, 1, false }, .{ "publish", Method.publish, 2, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
}
