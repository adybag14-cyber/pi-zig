//! Actual behavior/member schema admission through TypeBox Check/Clean/Errors.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
pub fn source(s: *Scope, bindings: c.JSValue, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value)) return false;
    const source_type = try s.get(bindings, "Source");
    if (c.JS_IsUndefined(source_type)) return false;
    const instance = c.JS_IsInstanceOf(s.engine.context, value, source_type);
    if (instance < 0) return js.capture(s.engine);
    return instance != 0;
}
pub fn readable(s: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(s.engine.context, value) and c.JS_IsFunction(s.engine.context, try s.get(value, "events")) and c.JS_IsFunction(s.engine.context, try s.get(value, "subscribe"));
}
fn fail(s: *Scope, bindings: c.JSValue, contract: c.JSValue, parts: []const c.JSValue) !void {
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, parts));
    _ = try h.invalid(s, bindings, "behavior", &.{ try s.get(contract, "name"), try s.text(": "), message });
}
pub fn validate(engine: *h.Engine, bindings: c.JSValue, service: c.JSValue, behavior: c.JSValue) anyerror!void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const contract = try s.get(service, "contract");
    const promise_type = try s.keep(try js.global(engine, "Promise"));
    const promise = c.JS_IsInstanceOf(engine.context, behavior, promise_type);
    if (promise < 0) return js.capture(engine);
    if (promise != 0) {
        _ = try h.invalid(&s, bindings, "behavior", &.{ try s.get(contract, "name"), try s.text(": factories must be synchronous") });
    }
    if (!c.JS_IsObject(behavior) or c.JS_IsFunction(engine.context, behavior)) try fail(&s, bindings, contract, &.{try s.text("factory must return an object")});
    const variants = try s.get(try s.get(contract, "description"), "variants");
    const remote = try s.equal(try s.get(contract, "scope"), "remote");
    var members = c.pi_js_undefined();
    if (remote) {
        const kind = try s.get(behavior, "kind");
        members = try s.key(variants, kind);
        if (!c.JS_IsString(kind) or c.JS_IsUndefined(members)) {
            const text = try s.keep(try js.call(engine, try s.keep(try js.global(engine, "String")), c.pi_js_undefined(), &.{kind}));
            try fail(&s, bindings, contract, &.{ try s.text("unknown variant "), text });
        }
        const keys = try s.keys(behavior);
        for (0..try h.length(&s, keys)) |index| {
            const key = try s.at(keys, index);
            if (!try s.equal(key, "kind") and c.JS_IsUndefined(try s.key(members, key))) try fail(&s, bindings, contract, &.{ key, try s.text(" is not in variant "), kind });
        }
    } else {
        members = try s.get(variants, "");
        if (h.nullish(members)) members = try s.record();
    }
    const entries = try s.entries(members);
    for (0..try h.length(&s, entries)) |index| {
        const entry = try s.at(entries, index);
        const name = try s.at(entry, 0);
        const description = try s.at(entry, 1);
        const value = try s.key(behavior, name);
        const kind = try s.get(description, "kind");
        if (try s.equal(kind, "method") and !c.JS_IsFunction(engine.context, value)) try fail(&s, bindings, contract, &.{ name, try s.text(" must be a method") });
        if (try s.equal(kind, "state") and !try source(&s, bindings, value) and !try readable(&s, value)) try fail(&s, bindings, contract, &.{ name, try s.text(" must be a cell, a derivation or a held object's state member") });
        if (try s.equal(kind, "opaque") and c.JS_IsUndefined(value)) try fail(&s, bindings, contract, &.{ name, try s.text(" is missing") });
    }
}
pub fn assertValid(s: *Scope, bindings: c.JSValue, reason: []const u8, what: c.JSValue, schema: c.JSValue, value: c.JSValue) anyerror!void {
    const context = try s.record();
    if (try @import("native_tool_validation.zig").checkWithContext(s.engine, context, schema, value)) return;
    const validator = try s.keep(try @import("native_tool_validator_cache.zig").compileFresh(s.engine, schema));
    const errors = try h.invoke(s, validator, "Errors", &.{value});
    const details = try h.invoke(s, errors, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 3) });
    const summaries = try s.list();
    for (0..try h.length(s, details)) |index| {
        const item = try s.at(details, index);
        const path = try s.get(item, "instancePath");
        try js.push(s.engine, summaries, try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ if (c.JS_ToBool(s.engine.context, path) != 0) path else try s.text("/"), try s.text(" "), try s.get(item, "message") })));
    }
    const message = try s.keep(try @import("native_utf16.zig").concat(s.engine, &.{ what, try s.text(": "), try h.invoke(s, summaries, "join", &.{try s.text("; ")}) }));
    const failure = try h.invoke(s, try s.get(bindings, "errors"), "invalid", &.{ try s.text(reason), message, details });
    _ = try h.throwValue(s, failure);
}
pub fn clean(s: *Scope, schema: c.JSValue, value: c.JSValue) !c.JSValue {
    const cloned = try s.keep(try @import("native_chord_clone.zig").clone(s.engine, value));
    return s.keep(try @import("native_chord_normalization.zig").clean(s.engine, try s.record(), schema, cloned));
}
pub fn refresh(engine: *h.Engine, record: c.JSValue, bindings: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const schemas = try h.map(&s);
    const installed = try h.values(&s, try s.get(record, "behaviors"));
    for (0..try h.length(&s, installed)) |index| {
        const item = try s.at(installed, index);
        const contract = try s.get(try s.get(item, "service"), "contract");
        if (!try s.equal(try s.get(contract, "scope"), "remote")) continue;
        const behavior = try s.get(item, "behavior");
        const kind = try s.get(behavior, "kind");
        const members = try s.key(try s.get(try s.get(contract, "description"), "variants"), if (h.nullish(kind)) try s.text("") else kind);
        if (h.nullish(members)) continue;
        const entries = try s.entries(members);
        for (0..try h.length(&s, entries)) |slot| {
            const entry = try s.at(entries, slot);
            const description = try s.at(entry, 1);
            const value = try s.key(behavior, try s.at(entry, 0));
            if (!try s.equal(try s.get(description, "kind"), "state") or !try source(&s, bindings, value)) continue;
            var list = try h.invoke(&s, schemas, "get", &.{value});
            if (h.nullish(list)) list = try s.list();
            try js.push(engine, list, try s.get(description, "schema"));
            _ = try h.invoke(&s, schemas, "set", &.{ value, list });
        }
    }
    const decls = try h.snapshot(&s, try h.invoke(&s, record, "allDecls", &.{}));
    for (0..try h.length(&s, decls)) |index| {
        const set = try s.at(decls, index);
        inline for (.{ "cells", "derives" }) |name| {
            const values = try h.values(&s, try s.get(set, name));
            for (0..try h.length(&s, values)) |slot| {
                const value = try s.at(values, slot);
                const list = try h.invoke(&s, schemas, "get", &.{value});
                try h.field(&s, value, "schemas", if (h.nullish(list)) try s.list() else list);
            }
        }
    }
    return c.pi_js_undefined();
}
