//! Actual Connection relay holds/calls: live waiters, forwarding maps and once-only settlement.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const Method = enum(c_int) { origin_id, current, ready, open, subscribe, unsubscribe, close, finish, cancel, resync };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return invoke(engine, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic), captures[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn put(s: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try js.setKey(s.engine, object, try s.text(@import("std").mem.span(name)), value);
}
fn frame(s: *Scope, tag: []const u8, id: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "t", try s.text(tag));
    try h.field(s, result, "id", id);
    return result;
}
fn send(s: *Scope, connection: c.JSValue, message: c.JSValue) !void {
    _ = try h.invoke(s, connection, "send", &.{message});
}
fn holdData(s: *Scope, receiver: c.JSValue, bindings: c.JSValue) !c.JSValue {
    return (try h.actor(s, receiver, bindings, .RelayRef)).data;
}
fn waitExecutor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return addWaiter(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn addWaiter(engine: *h.Engine, receiver: c.JSValue, bindings: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const waiters = try s.get(try holdData(&s, receiver, bindings), "waiters");
    const pending = try s.record();
    try h.field(&s, pending, "resolve", resolve);
    try h.field(&s, pending, "reject", reject);
    _ = try h.invoke(&s, waiters, "add", &.{pending});
    return c.pi_js_undefined();
}
fn forwardSub(s: *Scope, receiver: c.JSValue, origin_id: c.JSValue, entry: c.JSValue) !void {
    const down = try s.get(receiver, "down");
    const id = try h.invoke(s, down, "nextId", &.{});
    try put(s, entry, "downId", id);
    const mapping = try s.record();
    try h.field(s, mapping, "relay", receiver);
    try h.field(s, mapping, "originSubId", origin_id);
    _ = try h.invoke(s, try s.get(down, "relayedSubs"), "set", &.{ id, mapping });
    const message = try frame(s, "sub", id);
    try h.field(s, message, "hold", try s.get(receiver, "downId"));
    try h.field(s, message, "member", try s.get(entry, "member"));
    try send(s, down, message);
}
fn settleWaiters(s: *Scope, receiver: c.JSValue, bindings: c.JSValue, method: [*:0]const u8, value: c.JSValue) !void {
    const waiters = try s.get(try holdData(s, receiver, bindings), "waiters");
    var iterator = try js.Iterator.init(s.engine, waiters, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pending| {
        defer s.engine.freeValue(pending);
        _ = try h.invoke(s, pending, method, &.{value});
    }
    _ = try h.invoke(s, waiters, "clear", &.{});
}
fn invoke(engine: *h.Engine, receiver: c.JSValue, args: []const c.JSValue, method: Method, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .resync) {
        const id = h.arg(args, 0);
        const entry = try h.invoke(&s, try s.get(receiver, "subs"), "get", &.{id});
        _ = try h.invoke(&s, try s.get(receiver, "origin"), "dropState", &.{id});
        if (h.nullish(entry) or c.JS_IsUndefined(try s.get(entry, "downId")) or c.JS_IsUndefined(try s.get(receiver, "down"))) return c.pi_js_undefined();
        const down = try s.get(receiver, "down");
        _ = try h.invoke(&s, try s.get(down, "relayedSubs"), "delete", &.{try s.get(entry, "downId")});
        try send(&s, down, try frame(&s, "unsub", try s.get(entry, "downId")));
        try forwardSub(&s, receiver, id, entry);
        return c.pi_js_undefined();
    }
    if (method == .origin_id) return js.get(engine, try s.get(receiver, "frame"), "id");
    if (method == .current) {
        if (try h.flag(&s, receiver, "closed")) return c.pi_js_bool(engine.context, 0);
        const origin = try s.get(receiver, "origin");
        const open = try s.get(origin, "open");
        if (c.JS_ToBool(engine.context, open) == 0) return s.result(open);
        return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, try s.get(try s.get(receiver, "origin"), "generation"), try s.get(receiver, "generation"))));
    }
    if (method == .ready) {
        if (try h.flag(&s, receiver, "closed")) return js.invoke(engine, try s.keep(try js.global(engine, "Promise")), "reject", &.{try h.errorValue(&s, bindings, "gone", &.{try s.text("relayed hold closed")}, c.pi_js_undefined())});
        const down = try s.get(receiver, "down");
        if (!c.JS_IsUndefined(down)) return js.invoke(engine, try s.keep(try js.global(engine, "Promise")), "resolve", &.{try s.get(receiver, "down")});
        const promise = try s.keep(try js.global(engine, "Promise"));
        var captures = [_]c.JSValue{ receiver, bindings };
        const executor = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, waitExecutor, "", 2, 0, 2, &captures)));
        var arguments = [_]c.JSValue{executor};
        return engine.checked(c.JS_CallConstructor(engine.context, promise, 1, &arguments));
    }
    if (method == .open) {
        if (try h.flag(&s, receiver, "closed")) return c.pi_js_undefined();
        const down = h.arg(args, 0);
        try put(&s, receiver, "down", down);
        try put(&s, receiver, "downId", try h.invoke(&s, down, "nextId", &.{}));
        _ = try h.invoke(&s, try s.get(down, "relayedRefs"), "set", &.{ try s.get(receiver, "downId"), receiver });
        const message = try s.record();
        try js.spreadInto(engine, message, try s.get(receiver, "frame"));
        try h.field(&s, message, "id", try s.get(receiver, "downId"));
        try h.field(&s, message, "principal", try s.get(receiver, "principal"));
        if (try h.flag(&s, receiver, "client")) try h.field(&s, message, "client", c.pi_js_bool(engine.context, 1));
        try send(&s, down, message);
        const subs = try s.get(receiver, "subs");
        var iterator = try js.Iterator.init(engine, subs, try h.iteratorSymbol(&s));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |pair| {
            defer engine.freeValue(pair);
            const values = try js.pair(engine, pair, try h.iteratorSymbol(&s));
            defer for (values) |value| engine.freeValue(value);
            if (c.JS_IsUndefined(try s.get(values[1], "downId"))) try forwardSub(&s, receiver, values[0], values[1]);
        }
        try settleWaiters(&s, receiver, bindings, "resolve", down);
        return c.pi_js_undefined();
    }
    if (method == .subscribe) {
        const entry = try s.record();
        try h.field(&s, entry, "member", h.arg(args, 1));
        try h.field(&s, entry, "downId", c.pi_js_undefined());
        _ = try h.invoke(&s, try s.get(receiver, "subs"), "set", &.{ h.arg(args, 0), entry });
        _ = try h.invoke(&s, try s.get(try s.get(receiver, "origin"), "relaySubs"), "set", &.{ h.arg(args, 0), receiver });
        if (!c.JS_IsUndefined(try s.get(receiver, "down"))) try forwardSub(&s, receiver, h.arg(args, 0), entry);
        return c.pi_js_undefined();
    }
    if (method == .unsubscribe) {
        const id = h.arg(args, 0);
        const subs = try s.get(receiver, "subs");
        const entry = try h.invoke(&s, subs, "get", &.{id});
        if (c.JS_IsUndefined(entry)) return c.pi_js_undefined();
        _ = try h.invoke(&s, subs, "delete", &.{id});
        _ = try h.invoke(&s, try s.get(try s.get(receiver, "origin"), "relaySubs"), "delete", &.{id});
        _ = try h.invoke(&s, try s.get(receiver, "origin"), "dropState", &.{id});
        const down_id = try s.get(entry, "downId");
        if (!c.JS_IsUndefined(down_id) and !c.JS_IsUndefined(try s.get(receiver, "down"))) {
            const down = try s.get(receiver, "down");
            _ = try h.invoke(&s, try s.get(down, "relayedSubs"), "delete", &.{try s.get(entry, "downId")});
            if (c.JS_IsUndefined(h.arg(args, 1)) or c.JS_ToBool(engine.context, h.arg(args, 1)) != 0) try send(&s, down, try frame(&s, "unsub", try s.get(entry, "downId")));
        }
        return c.pi_js_undefined();
    }
    if (method == .close) {
        if (try h.flag(&s, receiver, "closed")) return c.pi_js_undefined();
        try put(&s, receiver, "closed", c.pi_js_bool(engine.context, 1));
        const failure = h.arg(args, 0);
        const options = h.arg(args, 1);
        const calls = try h.values(&s, try s.get(receiver, "calls"));
        for (0..try h.length(&s, calls)) |index| _ = try h.invoke(&s, try s.at(calls, index), "cancel", &.{ failure, try s.get(options, "releaseDown") });
        const keys = try h.snapshot(&s, try h.invoke(&s, try s.get(receiver, "subs"), "keys", &.{}));
        for (0..try h.length(&s, keys)) |index| _ = try h.invoke(&s, receiver, "unsubscribe", &.{ try s.at(keys, index), try s.get(options, "releaseDown") });
        const origin = try s.get(receiver, "origin");
        const served = try s.get(origin, "served");
        const current = try h.invoke(&s, served, "get", &.{try s.get(receiver, "originId")});
        if (!h.nullish(current) and try s.equal(try s.get(current, "kind"), "relay")) _ = try h.invoke(&s, try s.get(try s.get(receiver, "origin"), "served"), "delete", &.{try s.get(receiver, "originId")});
        if (!c.JS_IsUndefined(try s.get(receiver, "down"))) {
            const down = try s.get(receiver, "down");
            _ = try h.invoke(&s, try s.get(down, "relayedRefs"), "delete", &.{try s.get(receiver, "downId")});
            if (try h.flag(&s, options, "releaseDown")) try send(&s, try s.get(receiver, "down"), try frame(&s, "release", try s.get(receiver, "downId")));
        }
        try settleWaiters(&s, receiver, bindings, "reject", failure);
        if (try h.flag(&s, options, "notify")) {
            const message = try frame(&s, "gone", try s.get(receiver, "originId"));
            try h.field(&s, message, "error", try h.invoke(&s, try s.get(bindings, "Wire"), "toWireError", &.{failure}));
            try send(&s, try s.get(receiver, "origin"), message);
        }
        return c.pi_js_undefined();
    }
    const data = (try h.actor(&s, receiver, bindings, .RelayCall)).data;
    if (try h.flag(&s, data, "settled")) return c.pi_js_undefined();
    if (method == .cancel) {
        if (c.JS_ToBool(engine.context, h.arg(args, 1)) != 0) {
            const down = try s.get(try s.get(receiver, "relay"), "down");
            if (!h.nullish(down)) try send(&s, down, try frame(&s, "cancel", try s.get(receiver, "downId")));
        }
        _ = try h.invoke(&s, receiver, "finish", &.{h.arg(args, 0)});
        return c.pi_js_undefined();
    }
    try h.field(&s, data, "settled", c.pi_js_bool(engine.context, 1));
    const relay = try s.get(receiver, "relay");
    _ = try h.invoke(&s, try s.get(relay, "calls"), "delete", &.{try s.get(receiver, "originId")});
    const down = try s.get(relay, "down");
    if (!h.nullish(down)) _ = try h.invoke(&s, try s.get(down, "relayedCalls"), "delete", &.{try s.get(receiver, "downId")});
    const pending = try s.get(data, "pending");
    if (c.JS_IsUndefined(h.arg(args, 0))) _ = try h.invoke(&s, pending, "resolve", &.{h.arg(args, 1)}) else _ = try h.invoke(&s, pending, "reject", &.{h.arg(args, 0)});
    return c.pi_js_undefined();
}
fn constructHold(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .RelayRef));
    inline for (.{ "origin", "frame", "principal", "client", "generation", "down" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "downId", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, result, "closed", c.pi_js_bool(engine.context, 0));
    inline for (.{ "calls", "subs" }) |name| try h.field(&s, result, name, try h.map(&s));
    try h.field(&s, try holdData(&s, result, captures[0]), "waiters", try h.set(&s));
    inline for (.{ "origin", "frame", "principal", "client" }, 0..) |name, index| try h.field(&s, result, name, h.arg(args, index));
    try h.field(&s, result, "generation", try s.get(h.arg(args, 0), "generation"));
    return s.result(result);
}
fn constructCall(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.keep(try h.allocate(engine, target, captures[0], .RelayCall));
    inline for (.{ "relay", "originId", "downId" }, 0..) |name, index| try h.field(&s, result, name, h.arg(args, index));
    const data = (try h.actor(&s, result, captures[0], .RelayCall)).data;
    try h.field(&s, data, "pending", h.arg(args, 3));
    try h.field(&s, data, "settled", c.pi_js_bool(engine.context, 0));
    const relay = h.arg(args, 0);
    _ = try h.invoke(&s, try s.get(relay, "calls"), "set", &.{ h.arg(args, 1), result });
    const down = try s.get(relay, "down");
    if (!h.nullish(down)) _ = try h.invoke(&s, try s.get(down, "relayedCalls"), "set", &.{ h.arg(args, 2), result });
    return s.result(result);
}
pub fn installCalls(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RelayCall);
    const call = try s.record();
    try js.define(engine, bindings, "RelayCall", try @import("native_class.zig").constructor(engine, "RelayCall", 4, call, constructCall, &.{bindings}));
    inline for (.{ .{ "finish", Method.finish, 2 }, .{ "cancel", Method.cancel, 2 } }) |entry| try h.define(&s, call, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], false, false);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    inline for (.{ h.Kind.RelayRef, h.Kind.RelayCall }) |kind| try h.register(&s, bindings, kind);
    const hold = try s.record();
    try js.define(engine, bindings, "RelayRef", try @import("native_class.zig").constructor(engine, "RelayRef", 4, hold, constructHold, &.{bindings}));
    try h.define(&s, hold, bindings, "resync", callback, @intFromEnum(Method.resync), 1, false, false);
    inline for (.{ .{ "originId", Method.origin_id, 0, true }, .{ "current", Method.current, 0, true }, .{ "ready", Method.ready, 0, false }, .{ "open", Method.open, 1, false }, .{ "subscribe", Method.subscribe, 2, false }, .{ "unsubscribe", Method.unsubscribe, 1, false }, .{ "close", Method.close, 2, false } }) |entry| try h.define(&s, hold, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], entry[3], false);
    const call = try s.record();
    try js.define(engine, bindings, "RelayCall", try @import("native_class.zig").constructor(engine, "RelayCall", 4, call, constructCall, &.{bindings}));
    inline for (.{ .{ "finish", Method.finish, 2 }, .{ "cancel", Method.cancel, 2 } }) |entry| try h.define(&s, call, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], false, false);
}
