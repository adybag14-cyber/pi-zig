//! Source rollback: discard staged listeners, unwind candidates, restore closed resources and old tasks.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
pub fn rollback(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!c.JSValue {
    if (try h.flag(s, reload, "rolledBack")) return c.pi_js_undefined();
    try r.put(s, reload, "rolledBack", c.pi_js_bool(s.engine.context, 1));
    _ = try h.invoke(s, try s.get(reload, "abort"), "abort", &.{try h.errorValue(s, bindings, "aborted", &.{try s.text("reload aborted")}, c.pi_js_undefined())});
    var facet_runs = try r.mapIterator(s, try s.get(reload, "facetRuns"), "values");
    defer facet_runs.deinit();
    errdefer facet_runs.closePreserving();
    while (try facet_runs.next()) |run| {
        defer s.engine.freeValue(run);
        _ = try h.invoke(s, run, "abort", &.{try h.errorValue(s, bindings, "aborted", &.{try s.text("reload aborted")}, c.pi_js_undefined())});
    }
    const host = try s.get(reload, "host");
    var candidates = try r.mapIterator(s, try s.get(reload, "candidates"), "values");
    defer candidates.deinit();
    errdefer candidates.closePreserving();
    while (try candidates.next()) |candidate| {
        defer s.engine.freeValue(candidate);
        const staged = try s.get(candidate, "staged");
        if (!h.nullish(staged)) _ = try h.invoke(s, staged, "discard", &.{});
    }
    var deferred = try r.mapIterator(s, try s.get(reload, "deferred"), "values");
    defer deferred.deinit();
    errdefer deferred.closePreserving();
    while (try deferred.next()) |staged| {
        defer s.engine.freeValue(staged);
        _ = try h.invoke(s, staged, "discard", &.{});
    }
    const work = try s.record();
    inline for (.{ "bindings", "reload", "host" }, .{ bindings, reload, host }) |name, value| try h.field(s, work, name, value);
    try h.field(s, work, "candidates", try h.invoke(s, try s.get(reload, "candidates"), "values", &.{}));
    return step(s.engine, work, c.pi_js_undefined(), false, 0);
}
fn step(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, phase: c_int) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (rejected) return h.throwValue(&s, value);
    const reload = try s.get(work, "reload");
    const host = try s.get(work, "host");
    const bindings = try s.get(work, "bindings");
    if (phase == 0) {
        if (try r.next(&s, try s.get(work, "candidates"))) |candidate| {
            const record = try s.get(candidate, "object");
            const run = try s.get(candidate, "run");
            _ = try h.invoke(&s, try s.get(record, "pending"), "delete", &.{try s.get(run, "decls")});
            const pending = try r.reportPending(&s, host, try h.invoke(&s, record, "unwind", &.{run}));
            return h.wait(step, engine, work, pending, 0);
        }
        try h.field(&s, work, "closed", try h.invoke(&s, try s.get(reload, "closed"), "values", &.{}));
        return step(engine, work, c.pi_js_undefined(), false, 1);
    }
    if (phase == 2) {
        return step(engine, work, c.pi_js_undefined(), false, 1);
    }
    if (phase == 1) {
        while (try r.next(&s, try s.get(work, "closed"))) |entry| {
            const record = try s.at(entry, 0);
            const resource = try s.at(entry, 1);
            if (!try s.equal(try s.get(resource, "state"), "closed")) continue;
            const restored = try s.record();
            inline for (.{ "host", "object", "resource", "bindings" }, .{ host, record, resource, bindings }) |name, item| try h.field(&s, restored, name, item);
            const controller = try s.keep(try js.builtin(engine, "AbortController", &.{}));
            const opened = try h.invoke(&s, resource, "open", &.{ try s.get(controller, "signal"), try s.get(record, "openOrder") });
            const handled = try s.keep(try h.wait(restore, engine, restored, opened, 0));
            return h.wait(step, engine, work, handled, 2);
        }
        var gated = try r.iterate(&s, try s.get(reload, "gated"));
        defer gated.deinit();
        errdefer gated.closePreserving();
        while (try gated.next()) |candidate| {
            defer engine.freeValue(candidate);
            const record = try s.get(candidate, "object");
            if (c.JS_IsUndefined(try s.get(record, "gate"))) continue;
            _ = try h.invoke(&s, record, "openGate", &.{});
            _ = try h.invoke(&s, record, "startTasks", &.{});
        }
        try h.field(&s, work, "objects", try h.values(&s, try s.get(host, "objects")));
        try h.field(&s, work, "recordIndex", c.JS_NewInt32(engine.context, 0));
        try h.field(&s, work, "reason", try h.errorValue(&s, bindings, "gone", &.{try s.text("reload aborted; type not served")}, c.pi_js_undefined()));
        return step(engine, work, c.pi_js_undefined(), false, 3);
    }
    const records = try s.get(work, "objects");
    while (try r.index(&s, work, "recordIndex") < try h.length(&s, records)) {
        const record = try s.at(records, try r.advance(&s, work, "recordIndex"));
        if (try r.has(&s, try s.get(try s.get(host, "current"), "services"), try s.get(record, "typeName"))) continue;
        const pending = try r.reportPending(&s, host, try h.invoke(&s, record, "dispose", &.{ c.pi_js_bool(engine.context, 1), try s.get(work, "reason") }));
        return h.wait(step, engine, work, pending, 3);
    }
    try r.put(&s, host, "pending", c.pi_js_undefined());
    try r.put(&s, host, "gating", c.pi_js_undefined());
    return c.pi_js_undefined();
}
fn restore(engine: *h.Engine, work: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (!rejected) return c.pi_js_undefined();
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const resource = try s.get(work, "resource");
    const record = try s.get(work, "object");
    _ = try h.invoke(&s, resource, "markUnavailable", &.{});
    const options = try s.record();
    try h.field(&s, options, "cause", value);
    _ = try h.invoke(&s, try s.get(work, "host"), "report", &.{try h.errorValue(&s, try s.get(work, "bindings"), "unavailable", &.{ try s.get(record, "address"), try s.text(": resource "), try s.get(resource, "key"), try s.text(" could not be restored") }, options)});
    return c.pi_js_undefined();
}
