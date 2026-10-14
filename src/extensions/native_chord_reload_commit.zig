//! Source publication: one synchronous epoch install, queued starts after coordinator frames.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const install_api = @import("native_chord_reload_install.zig");
fn publication(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return publishAndStart(engine, captures[0], captures[1], captures[2], captures[3]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn publishAndStart(engine: *h.Engine, bindings: c.JSValue, reload: c.JSValue, starts: c.JSValue, before: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const report = try publish(&s, bindings, reload, starts);
    if (!h.nullish(before)) _ = try s.keep(try js.call(engine, before, c.pi_js_undefined(), &.{}));
    const pending = try h.invoke(&s, starts, "splice", &.{c.JS_NewInt32(engine.context, 0)});
    var iter = try r.iterate(&s, pending);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |start| {
        defer engine.freeValue(start);
        _ = try s.keep(try js.call(engine, start, c.pi_js_undefined(), &.{}));
    }
    return s.result(report);
}
pub fn commit(s: *Scope, bindings: c.JSValue, reload: c.JSValue, starts: c.JSValue, before: c.JSValue) anyerror!c.JSValue {
    var data = [_]c.JSValue{ bindings, reload, starts, before };
    const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, publication, "", 0, 0, 4, &data)));
    return @import("native_chord_publish.zig").hold(s.engine, bindings, callback) catch |err| {
        if (err != error.JavaScriptException) return err;
        const failure = try s.keep(c.JS_DupValue(s.engine.context, s.engine.captured_exception.?));
        _ = try h.invoke(s, try s.get(reload, "host"), "fail", &.{failure});
        return h.throwValue(s, try r.reloadError(s, bindings, failure));
    };
}
fn publish(s: *Scope, bindings: c.JSValue, reload: c.JSValue, starts: c.JSValue) anyerror!c.JSValue {
    const host = try s.get(reload, "host");
    const previous = try s.get(host, "current");
    const next = try s.get(host, "pending");
    try r.put(s, host, "pending", c.pi_js_undefined());
    _ = try h.invoke(s, try s.get(host, "codeVersions"), "set", &.{ try s.get(next, "id"), next });
    try r.put(s, host, "previous", previous);
    try r.put(s, host, "current", next);
    const prepared = try s.list();
    const records = try h.values(s, try s.get(host, "objects"));
    for (0..try h.length(s, records)) |index| {
        const record = try s.at(records, index);
        if (try r.has(s, try s.get(reload, "removed"), try s.get(record, "typeName"))) continue;
        const candidate = try h.invoke(s, try s.get(reload, "candidates"), "get", &.{record});
        if (c.JS_IsUndefined(candidate)) {
            const installed = try h.invoke(s, try s.get(record, "implementations"), "get", &.{try s.get(previous, "id")});
            if (!c.JS_IsUndefined(installed)) {
                const copied = try s.record();
                try js.spreadInto(s.engine, copied, installed);
                try h.field(s, copied, "codeVersion", try s.get(next, "id"));
                _ = try h.invoke(s, try s.get(record, "implementations"), "set", &.{ try s.get(next, "id"), copied });
            }
            continue;
        }
        if (!try s.equal(try s.get(record, "status"), "live")) continue;
        _ = try h.invoke(s, reload, "install", &.{ candidate, try s.get(next, "id") });
        try js.push(s.engine, prepared, try s.get(record, "address"));
    }
    var candidates = try r.mapIterator(s, try s.get(reload, "candidates"), "values");
    defer candidates.deinit();
    errdefer candidates.closePreserving();
    while (try candidates.next()) |candidate| {
        defer s.engine.freeValue(candidate);
        const record = try s.get(candidate, "object");
        if (try s.equal(try s.get(record, "status"), "live")) continue;
        const staged = try s.get(candidate, "staged");
        if (!h.nullish(staged)) _ = try h.invoke(s, staged, "discard", &.{});
        const run = try s.get(candidate, "run");
        _ = try h.invoke(s, try s.get(record, "pending"), "delete", &.{try s.get(run, "decls")});
        _ = try r.reportPending(s, host, try h.invoke(s, record, "unwind", &.{run}));
    }
    var deferred = try r.iterate(s, try s.get(reload, "deferred"));
    defer deferred.deinit();
    errdefer deferred.closePreserving();
    while (try deferred.next()) |entry| {
        defer s.engine.freeValue(entry);
        const record = try s.at(entry, 0);
        const staged = try s.at(entry, 1);
        if (!try s.equal(try s.get(record, "status"), "live")) {
            _ = try h.invoke(s, staged, "discard", &.{});
            continue;
        }
        try r.put(s, record, "deferredRuntime", c.pi_js_bool(s.engine.context, 0));
        _ = try h.invoke(s, staged, "activate", &.{});
        try install_api.queue(s, starts, record, null);
    }
    _ = try h.invoke(s, host, "installTables", &.{ next, try s.get(reload, "tables"), c.pi_js_bool(s.engine.context, 1) });
    const reason = try h.errorValue(s, bindings, "gone", &.{try s.text("type no longer served")}, c.pi_js_undefined());
    const after = try h.values(s, try s.get(host, "objects"));
    for (0..try h.length(s, after)) |index| {
        const record = try s.at(after, index);
        if (try r.has(s, try s.get(reload, "removed"), try s.get(record, "typeName"))) _ = try r.reportPending(s, host, try h.invoke(s, record, "dispose", &.{ c.pi_js_bool(s.engine.context, 1), reason }));
    }
    var removed = try r.iterate(s, try s.get(reload, "removed"));
    defer removed.deinit();
    errdefer removed.closePreserving();
    while (try removed.next()) |name| {
        defer s.engine.freeValue(name);
        _ = try h.invoke(s, try s.get(host, "hostObjects"), "delete", &.{name});
    }
    var facets = try r.iterate(s, try s.get(reload, "facets"));
    defer facets.deinit();
    errdefer facets.closePreserving();
    while (try facets.next()) |facet| {
        defer s.engine.freeValue(facet);
        _ = try h.invoke(s, try s.get(host, "facets"), "set", &.{ try s.get(facet, "name"), facet });
    }
    const removes = try s.get(try s.get(reload, "options"), "remove");
    var names = try r.iterate(s, if (h.nullish(removes)) try s.list() else removes);
    defer names.deinit();
    errdefer names.closePreserving();
    while (try names.next()) |name| {
        defer s.engine.freeValue(name);
        _ = try h.invoke(s, try s.get(host, "facets"), "delete", &.{name});
    }
    var facet_runs = try r.iterate(s, try s.get(reload, "facetRuns"));
    defer facet_runs.deinit();
    errdefer facet_runs.closePreserving();
    while (try facet_runs.next()) |entry| {
        defer s.engine.freeValue(entry);
        try install_api.queueFacet(s, starts, host, try s.at(entry, 0), try s.at(entry, 1));
    }
    var removed_runs = try r.iterate(s, if (h.nullish(removes)) try s.list() else removes);
    defer removed_runs.deinit();
    errdefer removed_runs.closePreserving();
    while (try removed_runs.next()) |name| {
        defer s.engine.freeValue(name);
        try install_api.queueFacet(s, starts, host, name, c.pi_js_undefined());
    }
    try r.put(s, host, "gating", c.pi_js_undefined());
    var services = try r.iterate(s, try s.get(reload, "services"));
    defer services.deinit();
    errdefer services.closePreserving();
    while (try services.next()) |entry| {
        defer s.engine.freeValue(entry);
        const name = try s.at(entry, 0);
        const service = try s.at(entry, 1);
        if (try @import("native_chord_service.zig").hostLifetime(s, service) and try r.has(s, try s.get(reload, "changed"), name)) {
            const eager = try h.invoke(s, try s.get(host, "hostObjects"), "get", &.{name});
            const status = try r.optional(s, try r.optional(s, eager, "object"), "status");
            if (!try s.equal(status, "live")) try install_api.queue(s, starts, host, service);
        }
        const pinned = try h.invoke(s, try s.get(host, "hostObjects"), "get", &.{name});
        if (!try @import("native_chord_service.zig").hostLifetime(s, service) and !c.JS_IsUndefined(pinned)) {
            _ = try h.invoke(s, try s.get(host, "hostObjects"), "delete", &.{name});
            try install_api.queueRelease(s, starts, pinned);
        }
    }
    const report = try s.record();
    try h.field(s, report, "codeVersion", try s.get(next, "id"));
    try h.field(s, report, "previous", try s.get(previous, "id"));
    try h.field(s, report, "changed", try h.snapshot(s, try s.get(reload, "changed")));
    try h.field(s, report, "removed", try h.snapshot(s, try s.get(reload, "removed")));
    try h.field(s, report, "prepared", prepared);
    try h.field(s, report, "gated", try @import("native_chord_reload_table.zig").addresses(s, try s.get(reload, "gated")));
    return report;
}
