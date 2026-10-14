//! Actual b45 byte windows, lazy units, bounded state slots and overflow recovery.
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
pub fn initialize(s: *Scope, data: c.JSValue) !void {
    try h.field(s, data, "pending", try h.map(s));
    try h.field(s, data, "pendingBytes", c.JS_NewInt32(s.engine.context, 0));
}
fn stateKey(s: *Scope, hold: c.JSValue, member: c.JSValue) !c.JSValue {
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("s"), hold, try s.text("\x00"), member }));
}
pub fn unitKey(s: *Scope, hold: c.JSValue) !c.JSValue {
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("u"), hold }));
}
fn invokeFunction(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !void {
    _ = try s.keep(try js.call(s.engine, try s.get(receiver, name), receiver, &.{}));
}
fn subtract(s: *Scope, data: c.JSValue, slot: c.JSValue) !void {
    try h.field(s, data, "pendingBytes", try binary(s, 1, try s.get(data, "pendingBytes"), try s.get(slot, "size")));
}
fn resetSlot(s: *Scope, slot: c.JSValue, base: c.JSValue, lazy: bool) !void {
    try h.field(s, slot, "base", base);
    try h.field(s, slot, "ops", try s.list());
    try h.field(s, slot, "size", c.JS_NewInt32(s.engine.context, 0));
    try h.field(s, slot, "lazy", c.pi_js_bool(s.engine.context, @intFromBool(lazy)));
}
fn hasResend(s: *Scope, overflow: c.JSValue) !bool {
    const atom = try js.atom(s.engine, try s.text("resend"));
    defer c.JS_FreeAtom(s.engine.context, atom);
    const result = c.JS_HasProperty(s.engine.context, overflow, atom);
    if (result < 0) return js.capture(s.engine);
    return result != 0;
}
fn drop(s: *Scope, data: c.JSValue, slot: c.JSValue) !void {
    try subtract(s, data, slot);
    // Assignment ordering follows Source: lazy is retained until overflow kind
    // has been checked, including its observable `in` operation.
    try h.field(s, slot, "base", c.pi_js_undefined());
    try h.field(s, slot, "ops", try s.list());
    try h.field(s, slot, "size", c.JS_NewInt32(s.engine.context, 0));
    const overflow = try s.get(slot, "overflow");
    if (try hasResend(s, overflow)) {
        try h.field(s, slot, "lazy", c.pi_js_bool(s.engine.context, 1));
        return;
    }
    _ = try h.invoke(s, try s.get(data, "pending"), "delete", &.{try stateKey(s, try s.get(slot, "hold"), try s.get(slot, "m"))});
    try invokeFunction(s, overflow, "resync");
}
fn makeRoom(s: *Scope, data: c.JSValue, size: c.JSValue, current: c.JSValue) !void {
    const slots = try h.snapshot(s, try h.invoke(s, try s.get(data, "pending"), "values", &.{}));
    for (0..try h.length(s, slots)) |index| {
        if (flag(s, try binary(s, 5, try binary(s, 0, try s.get(data, "pendingBytes"), size), try s.get(data, "pendingCap")))) return;
        const slot = try s.at(slots, index);
        if (try s.equal(try s.get(slot, "kind"), "state") and !c.JS_IsStrictEqual(s.engine.context, slot, current) and flag(s, try binary(s, 6, try s.get(slot, "size"), c.JS_NewInt32(s.engine.context, 0)))) try drop(s, data, slot);
    }
    if (flag(s, try binary(s, 6, try binary(s, 0, try s.get(data, "pendingBytes"), size), try s.get(data, "pendingCap")))) try drop(s, data, current);
}
pub fn sendState(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, frame: c.JSValue, overflow: c.JSValue) !void {
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    const key = try stateKey(s, try s.get(frame, "hold"), try s.get(frame, "m"));
    const pending = try s.get(data, "pending");
    var slot = try h.invoke(s, pending, "get", &.{key});
    if (c.JS_IsUndefined(slot) and !try full(s, data)) {
        _ = try h.invoke(s, receiver, "send", &.{frame});
        return;
    }
    if (!h.nullish(slot) and try s.equal(try s.get(slot, "kind"), "unit")) return;
    if (c.JS_IsUndefined(slot)) {
        slot = try s.record();
        try h.field(s, slot, "kind", try s.text("state"));
        try h.field(s, slot, "hold", try s.get(frame, "hold"));
        try h.field(s, slot, "m", try s.get(frame, "m"));
        try resetSlot(s, slot, c.pi_js_undefined(), false);
        try h.field(s, slot, "overflow", overflow);
        _ = try h.invoke(s, pending, "set", &.{ key, slot });
    }
    if (!try s.equal(try s.get(frame, "as"), "ops")) {
        try subtract(s, data, slot);
        try resetSlot(s, slot, frame, false);
        return;
    }
    if (try h.flag(s, slot, "lazy")) return;
    const size = try s.get(try s.builtin("JSON", "stringify", &.{try s.get(frame, "ops")}), "length");
    if (flag(s, try binary(s, 6, try binary(s, 0, try s.get(data, "pendingBytes"), size), try s.get(data, "pendingCap")))) try makeRoom(s, data, size, slot);
    if (try h.flag(s, slot, "lazy") or !c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, pending, "get", &.{key}), slot)) return;
    const ops = try s.get(frame, "ops");
    var iterator = try js.Iterator.init(s.engine, if (h.nullish(ops)) try s.list() else ops, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |op| {
        defer s.engine.freeValue(op);
        _ = try h.invoke(s, try s.get(slot, "ops"), "push", &.{op});
    }
    try h.field(s, slot, "size", try binary(s, 0, try s.get(slot, "size"), size));
    try h.field(s, data, "pendingBytes", try binary(s, 0, try s.get(data, "pendingBytes"), size));
}
pub fn resetLater(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, hold: c.JSValue, member: c.JSValue, resend: c.JSValue) !void {
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    const pending = try s.get(data, "pending");
    const key = try stateKey(s, hold, member);
    var slot = try h.invoke(s, pending, "get", &.{key});
    if (!h.nullish(slot) and try s.equal(try s.get(slot, "kind"), "unit")) return;
    if (c.JS_IsUndefined(slot)) {
        slot = try s.record();
        try h.field(s, slot, "kind", try s.text("state"));
        try h.field(s, slot, "hold", hold);
        try h.field(s, slot, "m", member);
        try resetSlot(s, slot, c.pi_js_undefined(), true);
        const overflow = try s.record();
        try h.field(s, overflow, "resend", resend);
        try h.field(s, slot, "overflow", overflow);
        _ = try h.invoke(s, pending, "set", &.{ key, slot });
    } else {
        try subtract(s, data, slot);
        try resetSlot(s, slot, c.pi_js_undefined(), true);
    }
    try flush(s, receiver, data);
}
pub fn queueUnit(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, hold: c.JSValue, callback: c.JSValue) !void {
    const data = (try h.actor(s, receiver, bindings, .Connection)).data;
    const pending = try s.get(data, "pending");
    const key = try unitKey(s, hold);
    if (!flag(s, try h.invoke(s, pending, "has", &.{key}))) {
        const slot = try s.record();
        try h.field(s, slot, "kind", try s.text("unit"));
        try h.field(s, slot, "hold", hold);
        try h.field(s, slot, "flush", callback);
        _ = try h.invoke(s, pending, "set", &.{ key, slot });
    }
    try flush(s, receiver, data);
}
pub fn dropState(s: *Scope, data: c.JSValue, hold: c.JSValue, member: c.JSValue) !void {
    const pending = try s.get(data, "pending");
    const key = try stateKey(s, hold, member);
    const slot = try h.invoke(s, pending, "get", &.{key});
    if (h.nullish(slot) or !try s.equal(try s.get(slot, "kind"), "state")) return;
    try subtract(s, data, slot);
    _ = try h.invoke(s, pending, "delete", &.{try stateKey(s, hold, member)});
}
pub fn dropHoldState(s: *Scope, data: c.JSValue, hold: c.JSValue) !void {
    const pending = try s.get(data, "pending");
    var iterator = try r.iterate(s, pending);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        const slot = try s.at(entry, 1);
        if (!c.JS_IsStrictEqual(s.engine.context, try s.get(slot, "hold"), hold)) continue;
        if (try s.equal(try s.get(slot, "kind"), "state")) try subtract(s, data, slot);
        _ = try h.invoke(s, pending, "delete", &.{try s.at(entry, 0)});
    }
}
pub fn waiting(s: *Scope, data: c.JSValue) !c.JSValue {
    const result = try s.record();
    try h.field(s, result, "slots", try s.get(try s.get(data, "pending"), "size"));
    try h.field(s, result, "bytes", try s.get(data, "pendingBytes"));
    return result;
}
pub fn flush(s: *Scope, receiver: c.JSValue, data: c.JSValue) !void {
    const pending = try s.get(data, "pending");
    var iterator = try r.iterate(s, pending);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        if (try full(s, data)) {
            try iterator.close();
            return;
        }
        const slot = try s.at(entry, 1);
        _ = try h.invoke(s, pending, "delete", &.{try s.at(entry, 0)});
        if (try s.equal(try s.get(slot, "kind"), "unit")) {
            try invokeFunction(s, slot, "flush");
            continue;
        }
        try subtract(s, data, slot);
        if (try h.flag(s, slot, "lazy")) {
            const overflow = try s.get(slot, "overflow");
            if (try hasResend(s, overflow)) try invokeFunction(s, overflow, "resend");
            continue;
        }
        if (!c.JS_IsUndefined(try s.get(slot, "base"))) _ = try h.invoke(s, receiver, "send", &.{try s.get(slot, "base")});
        if (try h.length(s, try s.get(slot, "ops")) > 0) {
            const frame = try s.record();
            try h.field(s, frame, "t", try s.text("state"));
            try h.field(s, frame, "hold", try s.get(slot, "hold"));
            try h.field(s, frame, "m", try s.get(slot, "m"));
            try h.field(s, frame, "as", try s.text("ops"));
            try h.field(s, frame, "ops", try s.get(slot, "ops"));
            _ = try h.invoke(s, receiver, "send", &.{frame});
        }
    }
}
pub fn onAck(s: *Scope, bindings: c.JSValue, receiver: c.JSValue, data: c.JSValue, n: c.JSValue) !void {
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(data, "peerAcks"), c.pi_js_bool(s.engine.context, 1)) or flag(s, try binary(s, 4, n, try s.get(data, "acked"))) or flag(s, try binary(s, 6, n, try s.get(data, "sent")))) {
        const reason = try r.concat(s, &.{ try s.text("ack "), n, try s.text(" outside "), try s.get(data, "acked"), try s.text(".."), try s.get(data, "sent") });
        try dispatch.violation(s, bindings, receiver, reason);
        return;
    }
    const removed = try h.invoke(s, try s.get(data, "unacked"), "splice", &.{ c.JS_NewInt32(s.engine.context, 0), try binary(s, 1, n, try s.get(data, "acked")) });
    var iterator = try r.iterate(s, removed);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |size| {
        defer s.engine.freeValue(size);
        try h.field(s, data, "unackedBytes", try binary(s, 1, try s.get(data, "unackedBytes"), size));
    }
    try h.field(s, data, "acked", n);
    try flush(s, receiver, data);
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
        try h.field(s, versions, "local", c.JS_NewInt32(s.engine.context, 4));
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
    if (close) _ = try h.invoke(s, try s.get(receiver, "link"), "close", &.{try s.text("protocol-version 4")});
}
