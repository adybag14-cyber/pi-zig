//! Source prepareRecord: record the candidate before validation, defer exclusive dependency closures.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn prepare(s: *Scope, bindings: c.JSValue, reload: c.JSValue, record: c.JSValue) anyerror!c.JSValue {
    const service = try h.invoke(s, try s.get(reload, "services"), "get", &.{try s.get(record, "typeName")});
    const run = try h.invoke(s, record, "run", &.{ service, try s.get(record, "decls") });
    const candidate = try s.record();
    inline for (.{ "record", "service", "run" }, .{ record, service, run }) |name, value| try h.field(s, candidate, name, value);
    inline for (.{ "reasons", "atGate", "replaced" }) |name| try h.field(s, candidate, name, try s.list());
    inline for (.{ "migrated", "derived" }) |name| try h.field(s, candidate, name, try h.map(s));
    try h.field(s, candidate, "staged", c.pi_js_undefined());
    _ = try h.invoke(s, try s.get(reload, "candidates"), "set", &.{ record, candidate });
    const bumped = !c.JS_IsStrictEqual(s.engine.context, try s.get(service, "stateVersion"), try s.get(record, "stateVersion"));
    if (bumped) try js.push(s.engine, try s.get(candidate, "reasons"), try r.concat(s, &.{ try s.text("state version "), try s.get(record, "stateVersion"), try s.text(" -> "), try s.get(service, "stateVersion") }));
    const decls = try s.get(run, "decls");
    var cells = try r.iterate(s, try s.get(decls, "cells"));
    defer cells.deinit();
    errdefer cells.closePreserving();
    while (try cells.next()) |entry| {
        defer s.engine.freeValue(entry);
        const name = try s.at(entry, 0);
        const cell = try s.at(entry, 1);
        if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(try s.get(record, "decls"), "cells"), "get", &.{name}), cell) or try @import("native_chord_canonical.zig").deepEqual(s.engine, try s.get(cell, "schema"), try h.invoke(s, try s.get(decls, "cellSchemas"), "get", &.{name}))) continue;
        if (!bumped) return h.invalid(s, bindings, "state", &.{ try s.get(record, "address"), try s.text(": schema of state "), name, try s.text(" changed without a state-version bump") });
    }
    const migrate = try r.optional(s, try s.get(try s.get(service, "options"), "state"), "migrate");
    const names = try s.keys(if (h.nullish(migrate)) try s.record() else migrate);
    for (0..try h.length(s, names)) |index| {
        const name = try s.at(names, index);
        if (!try r.has(s, try s.get(decls, "cells"), name)) return h.invalid(s, bindings, "state", &.{ try s.get(record, "address"), try s.text(": migrate for undeclared state "), name });
    }
    const deferred = try h.set(s);
    const resources = try s.get(try s.get(run, "created"), "resources");
    var created = try r.iterate(s, resources);
    defer created.deinit();
    errdefer created.closePreserving();
    while (try created.next()) |resource| {
        defer s.engine.freeValue(resource);
        var must_defer = try h.flag(s, resource, "exclusive");
        if (!must_defer) {
            const deps = try s.get(resource, "deps");
            for (0..try h.length(s, deps)) |index| if (try r.has(s, deferred, try s.at(deps, index))) {
                must_defer = true;
                break;
            };
        }
        if (must_defer) _ = try h.invoke(s, deferred, "add", &.{resource});
    }
    var waiting = try r.iterate(s, deferred);
    defer waiting.deinit();
    errdefer waiting.closePreserving();
    while (try waiting.next()) |resource| {
        defer s.engine.freeValue(resource);
        try js.push(s.engine, try s.get(candidate, "atGate"), resource);
        const old = try h.invoke(s, try s.get(try s.get(record, "decls"), "resources"), "get", &.{try s.get(resource, "key")});
        if (try h.flag(s, resource, "exclusive") and !h.nullish(old) and try h.flag(s, old, "exclusive") and try s.equal(try s.get(old, "state"), "open")) try js.push(s.engine, try s.get(candidate, "replaced"), old);
    }
    if (try r.index(s, deferred, "size") > 0) try js.push(s.engine, try s.get(candidate, "reasons"), try s.text("exclusive resource replaced"));
    if (try h.length(s, try s.get(candidate, "reasons")) == 0) try @import("native_chord_reload_candidate.zig").dryRun(s, bindings, candidate);
    const open = try s.list();
    for (0..try h.length(s, resources)) |index| {
        const resource = try s.at(resources, index);
        if (!try r.has(s, deferred, resource)) try js.push(s.engine, open, resource);
    }
    return h.invoke(s, record, "open", &.{ open, try s.get(try s.get(run, "created"), "holds"), try s.get(try s.get(reload, "abort"), "signal") });
}
