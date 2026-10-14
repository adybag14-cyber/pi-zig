//! Source Reload.install: install prevalidated state, preserve eager identity and notify compatible holds.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn start(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, mode: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return js.invoke(engine, captures[0], if (mode == 0) "startTasks" else "startEager", if (mode == 0) &.{} else &.{captures[1]}) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn queue(s: *Scope, starts: c.JSValue, owner: c.JSValue, service: ?c.JSValue) !void {
    var data = [_]c.JSValue{ owner, service orelse c.pi_js_undefined() };
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, start, "", 0, @intFromBool(service != null), 2, &data)));
    try js.push(s.engine, starts, callback);
}
pub fn install(s: *Scope, bindings: c.JSValue, reload: c.JSValue, starts: c.JSValue, candidate: c.JSValue, epoch: c.JSValue) anyerror!void {
    const host = try s.get(reload, "host");
    const record = try s.get(candidate, "record");
    const run = try s.get(candidate, "run");
    const service = try s.get(candidate, "service");
    const decls = try s.get(run, "decls");
    const gated = try h.length(s, try s.get(candidate, "reasons")) > 0;
    _ = try h.invoke(s, try s.get(record, "pending"), "delete", &.{decls});
    _ = try h.invoke(s, record, "stopTasks", &.{});
    if (gated) {
        const kept = try r.copySet(s, try h.invoke(s, try s.get(decls, "derives"), "values", &.{}));
        var derived_iter = try r.mapIterator(s, try s.get(try s.get(record, "decls"), "derives"), "values");
        defer derived_iter.deinit();
        errdefer derived_iter.closePreserving();
        while (try derived_iter.next()) |derived| {
            defer s.engine.freeValue(derived);
            if (!try r.has(s, kept, derived)) _ = try h.invoke(s, derived, "detach", &.{});
        }
    }
    try r.put(s, record, "decls", decls);
    try r.put(s, record, "service", service);
    try r.put(s, record, "stateVersion", try s.get(service, "stateVersion"));
    const installed = try s.record();
    inline for (.{ "epoch", "service", "behavior", "decls" }, .{ epoch, service, try s.get(run, "behavior"), decls }) |name, value| try h.field(s, installed, name, value);
    _ = try h.invoke(s, try s.get(record, "behaviors"), "set", &.{ epoch, installed });
    if (gated) {
        try r.put(s, record, "minEpoch", epoch);
        const old_epochs = try h.snapshot(s, try h.invoke(s, try s.get(record, "behaviors"), "keys", &.{}));
        for (0..try h.length(s, old_epochs)) |index| {
            const old = try s.at(old_epochs, index);
            if (!c.JS_IsStrictEqual(s.engine.context, old, epoch)) _ = try h.invoke(s, host, "retireBehavior", &.{ record, old });
        }
    }
    _ = try h.invoke(s, record, "refreshSchemas", &.{});
    var derivations = try r.iterate(s, try s.get(decls, "derives"));
    defer derivations.deinit();
    errdefer derivations.closePreserving();
    while (try derivations.next()) |entry| {
        defer s.engine.freeValue(entry);
        _ = try h.invoke(s, try s.at(entry, 1), "setFn", &.{try h.invoke(s, try s.get(decls, "deriveFns"), "get", &.{try s.at(entry, 0)})});
    }
    var cells = try r.iterate(s, try s.get(decls, "cells"));
    defer cells.deinit();
    errdefer cells.closePreserving();
    while (try cells.next()) |entry| {
        defer s.engine.freeValue(entry);
        const cell = try s.at(entry, 1);
        const schema = try h.invoke(s, try s.get(decls, "cellSchemas"), "get", &.{try s.at(entry, 0)});
        if (try r.has(s, try s.get(candidate, "migrated"), cell)) {
            _ = try h.invoke(s, cell, "reset", &.{ try h.invoke(s, try s.get(candidate, "migrated"), "get", &.{cell}), schema });
        } else try r.put(s, cell, "schema", schema);
    }
    const created_derives = try s.get(try s.get(run, "created"), "derives");
    const created = try r.copySet(s, created_derives);
    var new_derives = try r.iterate(s, created_derives);
    defer new_derives.deinit();
    errdefer new_derives.closePreserving();
    while (try new_derives.next()) |derived| {
        defer s.engine.freeValue(derived);
        _ = try h.invoke(s, derived, "attach", &.{try s.get(candidate, "derived")});
    }
    var all_derives = try r.mapIterator(s, try s.get(decls, "derives"), "values");
    defer all_derives.deinit();
    errdefer all_derives.closePreserving();
    while (try all_derives.next()) |derived| {
        defer s.engine.freeValue(derived);
        if (!try r.has(s, created, derived)) _ = try h.invoke(s, derived, "refresh", &.{});
    }
    const staged = try s.get(candidate, "staged");
    if (!h.nullish(staged)) _ = try h.invoke(s, staged, "activate", &.{});
    try queue(s, starts, record, null);
    _ = try h.invoke(s, record, "openGate", &.{});
    const eager = try h.invoke(s, try s.get(host, "eager"), "get", &.{try s.get(record, "typeName")});
    if (!h.nullish(eager) and c.JS_IsStrictEqual(s.engine.context, try s.get(eager, "record"), record) and !c.JS_IsStrictEqual(s.engine.context, try s.get(try s.get(eager, "contract"), "fingerprint"), try s.get(try s.get(service, "contract"), "fingerprint"))) {
        const replacement = try h.construct(s, bindings, "HandleImpl", &.{ record, try s.get(service, "contract"), try s.text("host") });
        _ = try h.invoke(s, record, "addHold", &.{replacement});
        _ = try h.invoke(s, try s.get(host, "eager"), "set", &.{ try s.get(record, "typeName"), replacement });
        _ = try h.invoke(s, eager, "release", &.{});
    }
    const holds = try h.snapshot(s, try s.get(record, "holds"));
    for (0..try h.length(s, holds)) |index| {
        const handle = try s.at(holds, index);
        if (try s.equal(try s.get(handle, "owner"), "client")) {
            _ = h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(service, "contract"), try s.get(try s.get(service, "options"), "accepts"), try s.get(handle, "contract") }) catch |err| {
                if (err != error.JavaScriptException) return err;
                const options = try s.record();
                try h.field(s, options, "cause", try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception.?)));
                const reason = try h.errorValue(s, bindings, "upgrade_required", &.{ try s.get(record, "typeName"), try s.text(" changed; reload the web facets") }, options);
                _ = try h.invoke(s, handle, "gone", &.{reason});
                _ = try h.invoke(s, record, "release", &.{handle});
                continue;
            };
        }
        _ = try h.invoke(s, handle, "shapeChanged", &.{});
    }
}
