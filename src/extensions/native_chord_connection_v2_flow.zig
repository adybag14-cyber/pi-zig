//! Actual protocol-v2 byte window, bounded coalesced state slots, acknowledgement bursts and mismatch fencing.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const dispatch = @import("native_chord_connection_v2_dispatch.zig");
fn binary(s: *Scope, operation: c_int, a: c.JSValue, b: c.JSValue) !c.JSValue {
    return s.keep(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, operation, a, b)));
}
fn flag(s: *Scope, value: c.JSValue) bool {
    return c.JS_ToBool(s.engine.context, value) != 0;
}
pub fn full(s: *Scope, data: c.JSValue) !bool {
    return c.JS_IsStrictEqual(s.engine.context, try s.get(data, "peerAcks"), c.pi_js_bool(s.engine.context, 1)) and flag(s, try binary(s, 7, try s.get(data, "unackedBytes"), try s.get(data, "window")));
}
pub fn send(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue) !void {
    const size = r.default(s, try h.invoke(s, try s.get(receiver, "link"), "send", &.{frame}), c.JS_NewInt32(s.engine.context, 0));
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    if (c.JS_IsStrictEqual(s.engine.context, try s.get(data, "peerAcks"), c.pi_js_bool(s.engine.context, 0))) return;
    try h.field(s, data, "sent", try s.keep(try s.engine.checked(c.JS_PiIncrement(s.engine.context, try s.get(data, "sent")))));
    try js.push(s.engine, try s.get(data, "unacked"), size);
    try h.field(s, data, "unackedBytes", try binary(s, 0, try s.get(data, "unackedBytes"), size));
}
pub fn sendState(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue) !bool {
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    const pending = try s.get(data, "pendingState");
    var slot = try h.invoke(s, pending, "get", &.{try s.get(frame, "id")});
    if (c.JS_IsUndefined(slot) and !try full(s, data)) {
        _ = try h.invoke(s, receiver, "send", &.{frame});
        return true;
    }
    if (c.JS_IsUndefined(slot)) {
        slot = try s.record();
        try h.field(s, slot, "base", c.pi_js_undefined());
        try h.field(s, slot, "ops", try s.list());
        try h.field(s, slot, "size", c.JS_NewInt32(s.engine.context, 0));
        _ = try h.invoke(s, pending, "set", &.{ try s.get(frame, "id"), slot });
    }
    if (c.JS_IsUndefined(try s.get(frame, "ops"))) {
        try h.field(s, slot, "base", frame);
        try h.field(s, slot, "ops", try s.list());
        try h.field(s, slot, "size", c.JS_NewInt32(s.engine.context, 0));
        return true;
    }
    const size = try s.get(try s.builtin("JSON", "stringify", &.{try s.get(frame, "ops")}), "length");
    const sum = try binary(s, 0, try s.get(slot, "size"), size);
    const bound = try binary(s, 2, try s.get(data, "window"), c.JS_NewInt32(s.engine.context, 4));
    if (flag(s, try binary(s, 6, sum, bound))) return false;
    var iterator = try r.iterate(s, try s.get(frame, "ops"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer s.engine.freeValue(op);
        try js.push(s.engine, try s.get(slot, "ops"), op);
    }
    try h.field(s, slot, "size", try binary(s, 0, try s.get(slot, "size"), size));
    return true;
}
pub fn onAck(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, n: c.JSValue) anyerror!void {
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(data, "peerAcks"), c.pi_js_bool(s.engine.context, 1)) or flag(s, try binary(s, 4, n, try s.get(data, "acked"))) or flag(s, try binary(s, 6, n, try s.get(data, "sent")))) return dispatch.violation(s, bindings, receiver, try r.concat(s, &.{ try s.text("ack "), n, try s.text(" outside "), try s.get(data, "acked"), try s.text(".."), try s.get(data, "sent") }));
    const removed = try h.invoke(s, try s.get(data, "unacked"), "splice", &.{ c.JS_NewInt32(s.engine.context, 0), try binary(s, 1, n, try s.get(data, "acked")) });
    var sizes = try r.iterate(s, removed);
    defer sizes.deinit();
    errdefer sizes.closePreserving();
    while (try sizes.next()) |size| {
        defer s.engine.freeValue(size);
        try h.field(s, data, "unackedBytes", try binary(s, 1, try s.get(data, "unackedBytes"), size));
    }
    try h.field(s, data, "acked", n);
    const pending = try s.get(data, "pendingState");
    var iterator = try r.iterate(s, pending);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        if (try full(s, data)) {
            try iterator.close();
            return;
        }
        const id = try s.at(entry, 0);
        const slot = try s.at(entry, 1);
        _ = try h.invoke(s, pending, "delete", &.{id});
        if (!c.JS_IsUndefined(try s.get(slot, "base"))) _ = try h.invoke(s, receiver, "send", &.{try s.get(slot, "base")});
        if (try h.length(s, try s.get(slot, "ops")) > 0) {
            const frame = try s.record();
            try h.field(s, frame, "t", try s.text("state"));
            try h.field(s, frame, "id", id);
            try h.field(s, frame, "ops", try s.get(slot, "ops"));
            _ = try h.invoke(s, receiver, "send", &.{frame});
        }
    }
}
fn ack(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return acknowledge(engine, captures[0], captures[1]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn acknowledge(engine: *h.Engine, receiver: c.JSValue, data: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.field(&s, data, "ackTimer", c.pi_js_undefined());
    const frame = try s.record();
    try h.field(&s, frame, "t", try s.text("ack"));
    try h.field(&s, frame, "n", try s.get(data, "received"));
    _ = try h.invoke(&s, try s.get(receiver, "link"), "send", &.{frame});
    return c.pi_js_undefined();
}
pub fn scheduleAck(s: *Scope, receiver: c.JSValue, data: c.JSValue) !void {
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(data, "peerAcks"), c.pi_js_bool(s.engine.context, 1)) or !c.JS_IsUndefined(try s.get(data, "ackTimer")) or !try h.flag(s, receiver, "open")) return;
    var captures = [_]c.JSValue{ receiver, data };
    const callback_value = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, ack, "", 0, 0, 2, &captures)));
    const timer = try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "setTimeout")), c.pi_js_undefined(), &.{ callback_value, c.JS_NewInt32(s.engine.context, 0) }));
    try h.field(s, data, "ackTimer", timer);
    const unref = try s.get(timer, "unref");
    if (!h.nullish(unref)) _ = try s.keep(try js.call(s.engine, unref, timer, &.{}));
}
pub fn mismatch(s: *Scope, receiver: c.JSValue, data: c.JSValue, peer: c.JSValue, close: bool) anyerror!void {
    if (try h.flag(s, data, "mismatched")) return;
    try h.field(s, data, "mismatched", c.pi_js_bool(s.engine.context, 1));
    const handler = try s.get(data, "onProtocolMismatch");
    if (!h.nullish(handler)) {
        const versions = try s.record();
        try h.field(s, versions, "local", c.JS_NewInt32(s.engine.context, 2));
        try h.field(s, versions, "peer", peer);
        const called = js.call(s.engine, handler, receiver, &.{versions}) catch |err| {
            if (err != error.JavaScriptException) return err;
            _ = try h.invoke(s, try s.get(receiver, "host"), "report", &.{s.engine.captured_exception orelse return err});
            return closeAfter(s, receiver, close);
        };
        _ = try s.keep(called);
    }
    try closeAfter(s, receiver, close);
}
fn closeAfter(s: *Scope, receiver: c.JSValue, close: bool) !void {
    if (close) _ = try h.invoke(s, try s.get(receiver, "link"), "close", &.{try s.text("protocol-version 2")});
}
