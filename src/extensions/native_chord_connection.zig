//! Actual Connection owner, public methods, keepalive and the latest already-closed constructor guard.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const consumer = @import("native_chord_connection_consumer.zig");
const provider = @import("native_chord_connection_provider.zig");
const Method = enum(c_int) { open, name, send, next_id, when_synced, mark_synced, revoke, hold, release, call, sub, unsub };
const Event = enum(c_int) { closed, receive, ping };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return invoke(engine, captures[0], receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, bindings: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (method) {
        .open => return consumer.open(&s, receiver),
        .name => return consumer.getName(&s, bindings, receiver),
        .next_id => return consumer.nextId(&s, (try h.actor(&s, receiver, bindings, .Connection)).data),
        .when_synced => return consumer.whenSynced(&s, bindings, receiver),
        .hold => return consumer.hold(&s, receiver, h.arg(args, 0)),
        .call => return consumer.call(&s, bindings, receiver, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2), h.arg(args, 3), h.arg(args, 4)),
        .sub => return consumer.sub(&s, receiver, h.arg(args, 0), h.arg(args, 1), h.arg(args, 2)),
        .send => try consumer.send(&s, receiver, h.arg(args, 0)),
        .mark_synced => try consumer.markSynced(&s, bindings, receiver, h.arg(args, 0)),
        .revoke => try consumer.revoke(&s, bindings, receiver, h.arg(args, 0)),
        .release => try consumer.release(&s, receiver, h.arg(args, 0)),
        .unsub => try consumer.unsub(&s, receiver, h.arg(args, 0)),
    }
    return c.pi_js_undefined();
}
fn event(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return onEvent(engine, captures[0], captures[1], @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn onEvent(engine: *h.Engine, bindings: c.JSValue, receiver: c.JSValue, kind: Event, value: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const data = (try h.actor(&s, receiver, bindings, .Connection)).data;
    switch (kind) {
        .closed => try @import("native_chord_connection_lifetime.zig").closed(&s, bindings, receiver, data, value, provider.dropServed),
        .receive => try @import("native_chord_connection_dispatch.zig").receive(&s, bindings, receiver, data, value, provider.handlers),
        .ping => {
            const elapsed = try s.keep(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, try s.builtin("Date", "now", &.{}), try s.get(data, "lastSeen"))));
            const expired = try s.keep(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, elapsed, try s.get(data, "timeout"))));
            if (c.JS_ToBool(engine.context, expired) != 0) {
                _ = try h.invoke(&s, try s.get(receiver, "link"), "close", &.{try s.text("ping timeout")});
            } else {
                const message = try s.record();
                try h.field(&s, message, "t", try s.text("ping"));
                const sequence = try s.keep(try engine.checked(c.JS_PiIncrement(engine.context, try s.get(data, "pingSequence"))));
                try h.field(&s, data, "pingSequence", sequence);
                try h.field(&s, message, "n", sequence);
                _ = try h.invoke(&s, receiver, "send", &.{message});
            }
        },
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const bindings = captures[0];
    const result = try s.keep(try h.allocate(engine, target, bindings, .Connection));
    const data = (try h.actor(&s, result, bindings, .Connection)).data;
    inline for (.{ "host", "link", "role", "peer", "principal", "restamp" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "generation", c.JS_NewInt32(engine.context, 0));
    inline for (.{ "peerEpoch", "synced" }) |name| try h.field(&s, result, name, c.pi_js_undefined());
    try h.field(&s, result, "fencedEpochs", try h.set(&s));
    try h.field(&s, data, "admitted", try h.map(&s));
    try h.field(&s, data, "parentName", c.pi_js_undefined());
    try h.field(&s, data, "syncWaiters", try h.set(&s));
    try h.field(&s, data, "nextId", c.JS_NewInt32(engine.context, 1));
    try h.field(&s, data, "lastSeen", try s.builtin("Date", "now", &.{}));
    try h.field(&s, data, "pinger", c.pi_js_undefined());
    inline for (.{ "remotes", "calls", "subs", "served", "incoming", "feeds", "relaySubs", "relayedHolds", "relayedCalls", "relayedSubs", "votes" }) |name| try h.field(&s, result, name, try h.map(&s));
    const host = h.arg(args, 0);
    const link = h.arg(args, 1);
    const config = h.arg(args, 2);
    try h.field(&s, result, "host", host);
    try h.field(&s, result, "link", link);
    inline for (.{ "role", "peer", "principal", "restamp" }) |name| try h.field(&s, result, name, try s.get(config, name));
    const fenced = try s.equal(try s.get(result, "role"), "downstream") and try s.equal(try s.get(try s.get(result, "peer"), "kind"), "host");
    try h.field(&s, result, "synced", c.pi_js_bool(engine.context, @intFromBool(!fenced)));
    var roots = [_]c.JSValue{ bindings, result };
    inline for (.{ .{ "onClose", Event.closed }, .{ "receive", Event.receive } }) |entry| {
        const observer = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, event, "", 1, @intFromEnum(entry[1]), 2, &roots)));
        _ = try h.invoke(&s, link, entry[0], &.{observer});
    }
    const hello = try s.record();
    try h.field(&s, hello, "t", try s.text("hello"));
    inline for (.{ "name", "kind" }) |name| try h.field(&s, hello, name, try s.get(host, name));
    try h.field(&s, hello, "epoch", try s.get(try s.get(host, "current"), "id"));
    _ = try h.invoke(&s, result, "send", &.{hello});
    const configured_interval = try s.get(config, "pingInterval");
    const interval = if (h.nullish(configured_interval)) c.JS_NewInt32(engine.context, 15000) else configured_interval;
    const configured_timeout = try s.get(config, "pingTimeout");
    const timeout = if (h.nullish(configured_timeout)) c.JS_NewInt32(engine.context, 45000) else configured_timeout;
    if (try h.flag(&s, link, "closed")) return s.result(result);
    try h.field(&s, data, "pingSequence", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, data, "timeout", timeout);
    const pinger = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, event, "", 0, @intFromEnum(Event.ping), 2, &roots)));
    const timer = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "setInterval")), c.pi_js_undefined(), &.{ pinger, interval }));
    try h.field(&s, data, "pinger", timer);
    const unref = try s.get(timer, "unref");
    if (!h.nullish(unref)) _ = try s.keep(try js.call(engine, unref, timer, &.{}));
    return s.result(result);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .Connection);
    const prototype = try s.record();
    try js.define(engine, bindings, "Connection", try @import("native_class.zig").constructor(engine, "Connection", 3, prototype, construct, &.{bindings}));
    inline for (.{ .{ "open", Method.open, 0, true }, .{ "name", Method.name, 0, true }, .{ "send", Method.send, 1, false }, .{ "nextId", Method.next_id, 0, false }, .{ "whenSynced", Method.when_synced, 0, false }, .{ "markSynced", Method.mark_synced, 1, false }, .{ "revoke", Method.revoke, 1, false }, .{ "hold", Method.hold, 1, false }, .{ "release", Method.release, 1, false }, .{ "call", Method.call, 5, false }, .{ "sub", Method.sub, 3, false }, .{ "unsub", Method.unsub, 1, false } }) |entry| try h.define(&s, prototype, bindings, entry[0], callback, @intFromEnum(entry[1]), entry[2], entry[3], false);
}
