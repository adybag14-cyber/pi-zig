//! Actual b45 provider principal/origin stamping and hold admission.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
const units = @import("native_chord_provider_units_v4.zig");
const dispatch = @import("native_chord_connection_v2_dispatch.zig");
// The genuine onCall body and relayCall helper retain their Source semantics;
// state subscription and hold admission are ported separately below.
pub const onCall = @import("native_chord_connection_v2_provider.zig").onCall;
pub const dropServed = units.dropServed;
fn reply(s: *Scope, bindings: c.JSValue, connection: c.JSValue, id: c.JSValue, reason: c.JSValue) !void {
    const message = try s.record();
    try h.field(s, message, "t", try s.text("gone"));
    try h.field(s, message, "id", id);
    try h.field(s, message, "error", try h.invoke(s, try s.get(bindings, "Wire"), "toWireError", &.{reason}));
    _ = try h.invoke(s, connection, "send", &.{message});
}
fn clientError(s: *Scope, bindings: c.JSValue, reason: c.JSValue) !c.JSValue {
    const chord = c.JS_IsInstanceOf(s.engine.context, reason, try s.get(try s.get(bindings, "errors"), "ChordError"));
    if (chord < 0) return js.capture(s.engine);
    if (chord == 0 or !try s.equal(try s.get(reason, "code"), "contract_mismatch")) return reason;
    const options = try s.record();
    try h.field(s, options, "cause", reason);
    return h.errorValue(s, bindings, "upgrade_required", &.{try s.get(reason, "message")}, options);
}
fn callback(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return observe(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined(), magic != 0) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn observe(engine: *h.Engine, work: c.JSValue, reason: c.JSValue, relay_error: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (relay_error) {
        const options = try s.record();
        try h.field(&s, options, "releaseDown", c.pi_js_bool(engine.context, 1));
        try h.field(&s, options, "notify", c.pi_js_bool(engine.context, 1));
        _ = try h.invoke(&s, try s.get(work, "relay"), "close", &.{ reason, options });
        return c.pi_js_undefined();
    }
    const connection = try s.get(work, "connection");
    const served = try s.get(work, "served");
    const id = try s.get(work, "id");
    if (!c.JS_IsStrictEqual(engine.context, try h.invoke(&s, try s.get(connection, "served"), "get", &.{id}), served)) return c.pi_js_undefined();
    const bindings = try s.get(work, "bindings");
    try units.dropServed(&s, bindings, connection, id, false);
    try reply(&s, bindings, connection, id, reason);
    return c.pi_js_undefined();
}
fn acquire(s: *Scope, bindings: c.JSValue, connection: c.JSValue, frame: c.JSValue, principal: c.JSValue, client: bool) !c.JSValue {
    const chord_error = try s.get(try s.get(bindings, "errors"), "ChordError");
    const token = try s.keep(try @import("native_chord_contracts_v4.zig").contractFromDescription(s.engine, chord_error, try s.get(frame, "token")));
    if (!try s.equal(try s.get(token, "scope"), "remote")) return h.invalid(s, bindings, "token", &.{ try s.get(token, "name"), try s.text(" is local; only remote types cross links") });
    const host = try s.get(connection, "host");
    const at = try s.keep(try @import("native_chord_contracts_v4.zig").resolveHost(s.engine, chord_error, try s.get(token, "name"), try s.get(try s.get(token, "description"), "host"), try s.get(frame, "input")));
    if (!c.JS_IsStrictEqual(s.engine.context, at, try s.get(host, "name"))) return h.invalid(s, bindings, "placement", &.{ try s.get(token, "name"), try s.text(" with this input does not live on "), try s.get(host, "name") });
    const options = try s.record();
    try h.field(s, options, "principal", principal);
    const ref = try h.invoke(s, host, "acquire", &.{ token, try s.get(frame, "input"), options, try s.text(if (client) "client" else "connection") });
    const local = c.JS_IsInstanceOf(s.engine.context, ref, try s.get(bindings, "RefImpl"));
    if (local < 0) return js.capture(s.engine);
    if (local == 0) return h.throwValue(s, try h.errorValue(s, bindings, "unavailable", &.{try s.text("not a local reference")}, c.pi_js_undefined()));
    return ref;
}
pub fn onHold(s: *Scope, bindings: c.JSValue, connection: c.JSValue, _: c.JSValue, frame: c.JSValue) !void {
    const id = try s.get(frame, "id");
    if (c.JS_ToBool(s.engine.context, try h.invoke(s, try s.get(connection, "served"), "has", &.{id})) != 0) {
        const reason = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("duplicate hold id "), try s.get(frame, "id") }));
        return dispatch.violation(s, bindings, connection, reason);
    }
    const downstream = try s.equal(try s.get(connection, "role"), "downstream");
    const given = if (downstream) c.pi_js_undefined() else try s.get(frame, "principal");
    const principal = if (downstream or h.nullish(given)) try s.get(connection, "principal") else given;
    const origin = try s.get(if (downstream) connection else frame, if (downstream) "originId" else "origin");
    const client = !c.JS_IsUndefined(origin);
    const host = try s.get(connection, "host");
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "at"), try s.get(host, "name"))) {
        if (try s.equal(try s.get(connection, "role"), "upstream")) return reply(s, bindings, connection, id, try h.errorValue(s, bindings, "unavailable", &.{ try s.get(host, "name"), try s.text(" does not relay") }, c.pi_js_undefined()));
        const relay = try h.construct(s, bindings, "RelayRef", &.{ connection, frame, principal, origin });
        const served = try s.record();
        try h.field(s, served, "kind", try s.text("relay"));
        try h.field(s, served, "relay", relay);
        _ = try h.invoke(s, try s.get(connection, "served"), "set", &.{ id, served });
        const pending = try h.invoke(s, host, "relay", &.{relay});
        const work = try s.record();
        try h.field(s, work, "relay", relay);
        var captures = [_]c.JSValue{work};
        const observer = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, 1, 1, &captures)));
        _ = try h.invoke(s, pending, "catch", &.{observer});
        return;
    }
    const generation = s.engine.native_allocation_generation;
    const ref = acquire(s, bindings, connection, frame, principal, client) catch |err| {
        const mapped = s.engine.nativeAllocationError(err, generation);
        if (mapped != error.JavaScriptException) return mapped;
        const reason = s.engine.captured_exception orelse return err;
        return reply(s, bindings, connection, id, if (client) try clientError(s, bindings, reason) else reason);
    };
    const served = try s.record();
    try h.field(s, served, "kind", try s.text("local"));
    inline for (.{ "id", "ref", "principal", "origin" }, .{ try s.get(frame, "id"), ref, principal, origin }) |name, value| try h.field(s, served, name, value);
    try h.field(s, served, "wantsState", c.pi_js_bool(s.engine.context, @intFromBool(!c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "state"), c.pi_js_bool(s.engine.context, 0)))));
    try h.field(s, served, "again", c.pi_js_bool(s.engine.context, @intFromBool(c.JS_IsStrictEqual(s.engine.context, try s.get(frame, "again"), c.pi_js_bool(s.engine.context, 1)))));
    try h.field(s, served, "unitSent", c.pi_js_bool(s.engine.context, 0));
    try h.field(s, served, "feeds", try h.map(s));
    _ = try h.invoke(s, try s.get(connection, "served"), "set", &.{ try s.get(frame, "id"), served });
    _ = try h.invoke(s, ref, "onShape", &.{try units.shapeListener(s, bindings, connection, served)});
    const work = try units.workFor(s, bindings, connection, served);
    try h.field(s, work, "id", id);
    var captures = [_]c.JSValue{work};
    const observer = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, callback, "", 1, 0, 1, &captures)));
    _ = try h.invoke(s, try s.get(ref, "goneListeners"), "add", &.{observer});
    if (try s.equal(try s.get(ref, "status"), "live")) try units.unit(s, bindings, connection, served);
}
