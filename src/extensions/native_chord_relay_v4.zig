//! Actual b45 relayed hold state units, origin stamping and once-only cleanup.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const Method = enum(c_int) { origin_id, client, current, ready, open, want_state, resync, shape, state, close };
fn callback(ctx: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return invoke(engine, receiver, captures[0], if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(magic)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn waitExecutor(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return addWaiter(engine, captures[0], captures[1], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn addWaiter(engine: *h.Engine, relay: c.JSValue, bindings: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = (try h.actor(&s, relay, bindings, .RelayRef)).data;
    const waiter = try s.record();
    try h.field(&s, waiter, "resolve", resolve);
    try h.field(&s, waiter, "reject", reject);
    _ = try h.invoke(&s, try s.get(owned, "waiters"), "add", &.{waiter});
    return c.pi_js_undefined();
}
fn settle(s: *Scope, owned: c.JSValue, method: [*:0]const u8, value: c.JSValue) !void {
    const waiters = try s.get(owned, "waiters");
    var iterator = try js.Iterator.init(s.engine, waiters, try h.iteratorSymbol(s));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |waiter| {
        defer s.engine.freeValue(waiter);
        _ = try h.invoke(s, waiter, method, &.{value});
    }
    _ = try h.invoke(s, waiters, "clear", &.{});
}
fn resend(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], "resync", &.{captures[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn invoke(engine: *h.Engine, relay: c.JSValue, bindings: c.JSValue, args: []const c.JSValue, method: Method) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const owned = (try h.actor(&s, relay, bindings, .RelayRef)).data;
    const origin = try s.get(relay, "origin");
    const original = try s.get(relay, "frame");
    const arg = h.arg(args, 0);
    if (method == .origin_id) return js.get(engine, original, "id");
    if (method == .client) return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(try s.get(relay, "originTag"))));
    if (method == .current) {
        if (try h.flag(&s, relay, "closed")) return c.pi_js_bool(engine.context, 0);
        const open = try s.get(origin, "open");
        if (c.JS_ToBool(engine.context, open) == 0) return s.result(open);
        return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, try s.get(origin, "generation"), try s.get(relay, "generation"))));
    }
    if (method == .ready) {
        const promise = try s.keep(try js.global(engine, "Promise"));
        if (try h.flag(&s, relay, "closed")) return js.invoke(engine, promise, "reject", &.{try h.errorValue(&s, bindings, "gone", &.{try s.text("relayed hold closed")}, c.pi_js_undefined())});
        if (!c.JS_IsUndefined(try s.get(relay, "down"))) return js.invoke(engine, promise, "resolve", &.{try s.get(relay, "down")});
        var captures = [_]c.JSValue{ relay, bindings };
        const executor = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, waitExecutor, "", 2, 0, 2, &captures)));
        return js.builtin(engine, "Promise", &.{executor});
    }
    if (try h.flag(&s, relay, "closed")) return c.pi_js_undefined();
    if (method == .open) {
        try h.field(&s, relay, "down", arg);
        try h.field(&s, relay, "downId", try h.invoke(&s, arg, "nextId", &.{}));
        _ = try h.invoke(&s, try s.get(arg, "relayedRefs"), "set", &.{ try s.get(relay, "downId"), relay });
        const at = try s.get(original, "at");
        const token = try s.get(original, "token");
        const input = try s.get(original, "input");
        const frame = try s.record();
        try h.field(&s, frame, "t", try s.text("hold"));
        try h.field(&s, frame, "id", try s.get(relay, "downId"));
        inline for (.{ "at", "token", "input", "principal" }, .{ at, token, input, try s.get(relay, "principal") }) |name, value| try h.field(&s, frame, name, value);
        if (!c.JS_IsUndefined(try s.get(relay, "originTag"))) try h.field(&s, frame, "origin", try s.get(relay, "originTag"));
        if (!try h.flag(&s, relay, "stateWanted")) try h.field(&s, frame, "state", c.pi_js_bool(engine.context, 0));
        if (c.JS_IsStrictEqual(engine.context, try s.get(original, "again"), c.pi_js_bool(engine.context, 1))) try h.field(&s, frame, "again", c.pi_js_bool(engine.context, 1));
        _ = try h.invoke(&s, arg, "send", &.{frame});
        try settle(&s, owned, "resolve", arg);
        return c.pi_js_undefined();
    }
    const origin_id = try s.get(relay, "originId");
    if (method == .want_state or method == .resync) {
        if (method == .want_state) {
            if (c.JS_IsStrictEqual(engine.context, arg, try s.get(relay, "stateWanted"))) return c.pi_js_undefined();
            try h.field(&s, relay, "stateWanted", arg);
            if (c.JS_ToBool(engine.context, arg) == 0) {
                _ = try h.invoke(&s, origin, "dropHoldState", &.{origin_id});
                _ = try h.invoke(&s, try s.get(relay, "awaiting"), "clear", &.{});
            }
        } else _ = try h.invoke(&s, try s.get(relay, "awaiting"), "add", &.{arg});
        const down = try s.get(relay, "down");
        if (!h.nullish(down)) {
            const frame = try s.record();
            try h.field(&s, frame, "t", try s.text(if (method == .resync) "resync" else if (c.JS_ToBool(engine.context, arg) != 0) "sub" else "unsub"));
            try h.field(&s, frame, "hold", try s.get(relay, "downId"));
            if (method == .resync) try h.field(&s, frame, "m", arg);
            _ = try h.invoke(&s, down, "send", &.{frame});
        }
        return c.pi_js_undefined();
    }
    if (method == .shape) {
        if (!try h.flag(&s, owned, "shaped")) {
            try h.field(&s, owned, "shaped", c.pi_js_bool(engine.context, 1));
            if (!c.JS_IsStrictEqual(engine.context, try s.get(original, "again"), c.pi_js_bool(engine.context, 1))) try h.field(&s, relay, "urgent", try s.keep(try js.builtin(engine, "Set", &.{try s.get(arg, "state")})));
        }
        const frame = try s.record();
        try js.spreadInto(engine, frame, arg);
        try h.field(&s, frame, "id", origin_id);
        _ = try h.invoke(&s, origin, "send", &.{frame});
        return c.pi_js_undefined();
    }
    if (method == .state) {
        const member = try s.get(arg, "m");
        const awaiting = try s.get(relay, "awaiting");
        if (c.JS_ToBool(engine.context, try h.invoke(&s, awaiting, "has", &.{member})) != 0) {
            if (try s.equal(try s.get(arg, "as"), "ops")) return c.pi_js_undefined();
            _ = try h.invoke(&s, awaiting, "delete", &.{member});
        }
        const frame = try s.record();
        try js.spreadInto(engine, frame, arg);
        try h.field(&s, frame, "hold", origin_id);
        const urgent = try s.get(relay, "urgent");
        if (!h.nullish(urgent) and c.JS_IsStrictEqual(engine.context, try h.invoke(&s, urgent, "delete", &.{member}), c.pi_js_bool(engine.context, 1))) {
            _ = try h.invoke(&s, origin, "send", &.{frame});
            return c.pi_js_undefined();
        }
        const overflow = try s.record();
        var captures = [_]c.JSValue{ relay, member };
        try js.define(engine, overflow, "resync", try engine.checked(c.JS_NewCFunctionData2(engine.context, resend, "", 0, 0, 2, &captures)));
        _ = try h.invoke(&s, origin, "sendState", &.{ frame, overflow });
        return c.pi_js_undefined();
    }
    try h.field(&s, relay, "closed", c.pi_js_bool(engine.context, 1));
    const options = h.arg(args, 1);
    const calls = try h.values(&s, try s.get(relay, "calls"));
    for (0..try h.length(&s, calls)) |index| _ = try h.invoke(&s, try s.at(calls, index), "cancel", &.{ arg, try s.get(options, "releaseDown") });
    _ = try h.invoke(&s, origin, "dropHoldState", &.{origin_id});
    const served = try h.invoke(&s, try s.get(origin, "served"), "get", &.{origin_id});
    if (!h.nullish(served) and try s.equal(try s.get(served, "kind"), "relay")) _ = try h.invoke(&s, try s.get(origin, "served"), "delete", &.{origin_id});
    const down = try s.get(relay, "down");
    if (!c.JS_IsUndefined(down)) {
        _ = try h.invoke(&s, try s.get(down, "relayedRefs"), "delete", &.{try s.get(relay, "downId")});
        if (try h.flag(&s, options, "releaseDown")) {
            const frame = try s.record();
            try h.field(&s, frame, "t", try s.text("release"));
            try h.field(&s, frame, "id", try s.get(relay, "downId"));
            _ = try h.invoke(&s, down, "send", &.{frame});
        }
    }
    try settle(&s, owned, "reject", arg);
    if (try h.flag(&s, options, "notify")) {
        const frame = try s.record();
        try h.field(&s, frame, "t", try s.text("gone"));
        try h.field(&s, frame, "id", origin_id);
        try h.field(&s, frame, "error", try h.invoke(&s, try s.get(bindings, "Wire"), "toWireError", &.{arg}));
        _ = try h.invoke(&s, origin, "send", &.{frame});
    }
    return c.pi_js_undefined();
}
fn construct(engine: *h.Engine, target: c.JSValue, args: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const relay = try s.keep(try h.allocate(engine, target, captures[0], .RelayRef));
    inline for (.{ "origin", "frame", "principal", "originTag" }, 0..) |name, index| try h.field(&s, relay, name, h.arg(args, index));
    try h.field(&s, relay, "down", c.pi_js_undefined());
    try h.field(&s, relay, "downId", c.JS_NewInt32(engine.context, 0));
    try h.field(&s, relay, "closed", c.pi_js_bool(engine.context, 0));
    try h.field(&s, relay, "stateWanted", c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, try s.get(h.arg(args, 1), "state"), c.pi_js_bool(engine.context, 0)))));
    try h.field(&s, relay, "generation", try s.get(h.arg(args, 0), "generation"));
    try h.field(&s, relay, "urgent", c.pi_js_undefined());
    try h.field(&s, relay, "awaiting", try h.set(&s));
    try h.field(&s, relay, "calls", try h.map(&s));
    const owned = (try h.actor(&s, relay, captures[0], .RelayRef)).data;
    try h.field(&s, owned, "waiters", try h.set(&s));
    try h.field(&s, owned, "shaped", c.pi_js_bool(engine.context, 0));
    return s.result(relay);
}
pub fn install(engine: *h.Engine, bindings: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    try h.register(&s, bindings, .RelayRef);
    const prototype = try s.record();
    try js.define(engine, bindings, "RelayRef", try @import("native_class.zig").constructor(engine, "RelayRef", 4, prototype, construct, &.{bindings}));
    inline for (.{ .{ "originId", Method.origin_id, 0, true }, .{ "client", Method.client, 0, true }, .{ "current", Method.current, 0, true }, .{ "ready", Method.ready, 0, false }, .{ "open", Method.open, 1, false }, .{ "wantState", Method.want_state, 1, false }, .{ "resync", Method.resync, 1, false }, .{ "shape", Method.shape, 1, false }, .{ "state", Method.state, 1, false }, .{ "close", Method.close, 2, false } }) |item| try h.define(&s, prototype, bindings, item[0], callback, @intFromEnum(item[1]), item[2], item[3], false);
    try @import("native_chord_relay_v2.zig").installCalls(engine, bindings);
}
