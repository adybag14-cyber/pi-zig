//! Source1692 service construction and lifetime admission.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn hostLifetime(s: *Scope, service: c.JSValue) !bool {
    return s.equal(try s.get(try s.get(service, "options"), "lifetime"), "host");
}
pub fn make(s: *Scope, bindings: c.JSValue, contract: c.JSValue, factory: c.JSValue, options: c.JSValue, facet: c.JSValue) anyerror!c.JSValue {
    const lifetime = r.default(s, try s.get(options, "lifetime"), try s.text("referenced"));
    if (!try s.equal(lifetime, "referenced") and !try s.equal(lifetime, "host")) return h.typeError(s, &.{ try s.get(contract, "name"), try s.text(": unknown lifetime "), try s.keep(try js.call(s.engine, try s.keep(try js.global(s.engine, "String")), c.pi_js_undefined(), &.{lifetime})) });
    if (try s.equal(lifetime, "host")) {
        if (!try s.equal(try s.get(contract, "scope"), "local")) return h.typeError(s, &.{ try s.get(contract, "name"), try s.text(": lifetime \"host\" needs a local type (remote types are referenced)") });
        if (!c.JS_IsUndefined(try s.get(options, "linger"))) return h.typeError(s, &.{ try s.get(contract, "name"), try s.text(": an object of lifetime \"host\" does not linger (it lives as long as the host)") });
        const normalized = @import("native_chord_normalization.zig").normalize(s.engine, try s.get(bindings, "errors"), try s.get(contract, "input"), try s.record(), try r.concat(s, &.{ try s.get(contract, "name"), try s.text(" input") })) catch |err| {
            if (err != error.JavaScriptException) return err;
            return h.typeError(s, &.{ try s.get(contract, "name"), try s.text(": lifetime \"host\" needs an input that accepts {} (the object's one address)") });
        };
        _ = try s.keep(normalized);
    }
    const service = try s.record();
    inline for (.{ "contract", "factory", "options", "facet" }, .{ contract, factory, options, facet }) |name, value| try h.field(s, service, name, value);
    return service;
}
