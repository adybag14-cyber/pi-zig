//! Source1692 local host-lifetime address, normalization and principal identity.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn locate(s: *Scope, bindings: c.JSValue, host: c.JSValue, service: c.JSValue, input: c.JSValue, given_principal: c.JSValue) anyerror!c.JSValue {
    const contract = try s.get(service, "contract");
    const name = try s.get(contract, "name");
    const schema = try s.get(contract, "input");
    const what = try r.concat(s, &.{ name, try s.text(" input") });
    const normalized = try s.keep(try @import("native_chord_normalization.zig").normalize(s.engine, try s.get(bindings, "errors"), schema, input, what));
    const identity = try s.keep(try @import("native_chord_identity.zig").canonicalIdentity(s.engine, schema, normalized));
    var principal = given_principal;
    if (try @import("native_chord_service.zig").hostLifetime(s, service)) {
        const empty = try s.keep(try @import("native_chord_normalization.zig").normalize(s.engine, try s.get(bindings, "errors"), schema, try s.record(), what));
        const empty_identity = try s.keep(try @import("native_chord_identity.zig").canonicalIdentity(s.engine, schema, empty));
        if (!c.JS_IsStrictEqual(s.engine.context, identity, empty_identity)) return h.invalid(s, bindings, "input", &.{ name, try s.text(" has lifetime \"host\": its one object has the empty input") });
        principal = try s.get(host, "principal");
    }
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const key = if (c.JS_IsStrictEqual(s.engine.context, principal, try s.get(host, "principal"))) try s.text("host") else try r.concat(s, &.{ try s.text("p:"), try s.keep(try js.call(s.engine, try s.get(data, "principalKey"), host, &.{principal})) });
    const located = try s.record();
    try h.field(s, located, "address", try r.concat(s, &.{ name, try s.text("\x00"), identity, try s.text("\x00"), key }));
    try h.field(s, located, "normalized", normalized);
    try h.field(s, located, "principal", principal);
    return located;
}
