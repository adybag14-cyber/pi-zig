//! Actual b45 placement resolution and remote binding identity.
const h = @import("native_chord_host_values.zig");
const js = h.js;
const c = h.c;
const Scope = h.Scope;
pub fn elsewhere(s: *Scope, bindings: c.JSValue, host: c.JSValue, token: c.JSValue, input: c.JSValue) !c.JSValue {
    const placement = try s.get(try s.get(token, "description"), "host");
    if (!try s.equal(try s.get(token, "scope"), "remote") or c.JS_IsUndefined(placement)) return c.pi_js_undefined();
    const label = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.get(token, "name"), try s.text(" input") }));
    const normalized = try s.keep(try @import("native_chord_normalization.zig").normalize(s.engine, try s.get(bindings, "errors"), try s.get(token, "input"), input, label));
    const at = try s.keep(try @import("native_chord_contracts_v4.zig").resolveHost(s.engine, try s.get(try s.get(bindings, "errors"), "ChordError"), try s.get(token, "name"), placement, normalized));
    if (c.JS_IsStrictEqual(s.engine.context, at, try s.get(host, "name"))) return c.pi_js_undefined();
    const location = try s.record();
    try h.field(s, location, "at", at);
    try h.field(s, location, "input", normalized);
    return location;
}
pub fn remoteKey(s: *Scope, bindings: c.JSValue, host: c.JSValue, token: c.JSValue, normalized: c.JSValue, principal: c.JSValue) !c.JSValue {
    const identity = try s.keep(try @import("native_chord_identity.zig").canonicalIdentity(s.engine, try s.get(token, "input"), normalized));
    const data = (try h.actor(s, host, bindings, .HostImpl)).data;
    const part = if (c.JS_ToBool(s.engine.context, try h.invoke(s, host, "isSelf", &.{principal})) != 0) try s.text("host") else try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("p:"), try s.keep(try js.call(s.engine, try s.get(data, "principalKey"), host, &.{principal})) }));
    return s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ try s.text("@"), try s.get(token, "name"), try s.text("\x00"), identity, try s.text("\x00"), part, try s.text("\x00"), try s.get(token, "fingerprint") }));
}
pub fn checkProvider(s: *Scope, bindings: c.JSValue, host: c.JSValue, token: c.JSValue, provider: c.JSValue, normalized: c.JSValue) !void {
    const placement = try s.get(try s.get(try s.get(provider, "contract"), "description"), "host");
    if (c.JS_IsUndefined(placement)) return;
    const chord_error = try s.get(try s.get(bindings, "errors"), "ChordError");
    const name = try s.get(token, "name");
    const at = try s.keep(try @import("native_chord_contracts_v4.zig").resolveHost(s.engine, chord_error, name, placement, normalized));
    if (!c.JS_IsStrictEqual(s.engine.context, at, try s.get(host, "name"))) {
        const repeated_at = try s.keep(try @import("native_chord_contracts_v4.zig").resolveHost(s.engine, chord_error, name, placement, normalized));
        _ = try h.invalid(s, bindings, "placement", &.{ name, try s.text(" with this input lives on "), repeated_at, try s.text(", not "), try s.get(host, "name") });
    }
}
