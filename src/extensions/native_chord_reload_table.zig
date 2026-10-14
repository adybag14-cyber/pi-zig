//! Source Reload service table, staged listeners and report construction.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
fn serve(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return serveInto(engine, captures[0], captures[1], captures[2], if (argc > 0) argv[0..@intCast(argc)] else &.{}) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn serveInto(engine: *h.Engine, reload: c.JSValue, facet: c.JSValue, bindings: c.JSValue, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const options = if (c.JS_IsUndefined(h.arg(args, 2))) try s.record() else h.arg(args, 2);
    const service = try @import("native_chord_service.zig").make(&s, bindings, h.arg(args, 0), h.arg(args, 1), options, try s.get(facet, "name"));
    _ = try h.invoke(&s, try s.get(reload, "host"), "serveInto", &.{ try s.get(reload, "services"), service });
    return c.pi_js_undefined();
}
pub fn load(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!void {
    const facets = try s.get(reload, "facets");
    const replaced = try h.set(s);
    var names = try r.iterate(s, facets);
    defer names.deinit();
    errdefer names.closePreserving();
    while (try names.next()) |facet| {
        defer s.engine.freeValue(facet);
        _ = try h.invoke(s, replaced, "add", &.{try s.get(facet, "name")});
    }
    const removes = try s.get(try s.get(reload, "options"), "remove");
    var removals = try r.iterate(s, if (h.nullish(removes)) try s.list() else removes);
    defer removals.deinit();
    errdefer removals.closePreserving();
    while (try removals.next()) |name| {
        defer s.engine.freeValue(name);
        _ = try h.invoke(s, replaced, "add", &.{name});
    }
    const host = try s.get(reload, "host");
    const current = try s.get(try s.get(host, "current"), "services");
    const old = try h.snapshot(s, current);
    const services = try h.map(s);
    for (0..try h.length(s, old)) |index| {
        const entry = try s.at(old, index);
        const service = try s.at(entry, 1);
        if (!try r.has(s, replaced, try s.get(service, "facet"))) _ = try h.invoke(s, services, "set", &.{ try s.at(entry, 0), service });
    }
    try js.setKey(s.engine, reload, try s.text("services"), services);
    var updates = try r.iterate(s, facets);
    defer updates.deinit();
    errdefer updates.closePreserving();
    while (try updates.next()) |facet| {
        defer s.engine.freeValue(facet);
        const run = try s.keep(try js.builtin(s.engine, "AbortController", &.{}));
        _ = try h.invoke(s, try s.get(reload, "facetRuns"), "set", &.{ try s.get(facet, "name"), run });
        const setup = try s.get(facet, "setup");
        var captures = [_]c.JSValue{ reload, facet, bindings };
        const callback = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, serve, "", 2, 0, 3, &captures)));
        _ = try s.keep(try js.call(s.engine, setup, facet, &.{try h.invoke(s, host, "facetApi", &.{ callback, try s.get(run, "signal") })}));
    }
    var next_services = try r.iterate(s, try s.get(reload, "services"));
    defer next_services.deinit();
    errdefer next_services.closePreserving();
    while (try next_services.next()) |entry| {
        defer s.engine.freeValue(entry);
        const name = try s.at(entry, 0);
        if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, current, "get", &.{name}), try s.at(entry, 1))) _ = try h.invoke(s, try s.get(reload, "changed"), "add", &.{name});
    }
    var old_names = try r.mapIterator(s, current, "keys");
    defer old_names.deinit();
    errdefer old_names.closePreserving();
    while (try old_names.next()) |name| {
        defer s.engine.freeValue(name);
        if (!try r.has(s, try s.get(reload, "services"), name)) _ = try h.invoke(s, try s.get(reload, "removed"), "add", &.{name});
    }
    const pending = try s.record();
    try h.field(s, pending, "id", try h.invoke(s, host, "nextCodeVersionId", &.{try s.get(reload, "codeVersion")}));
    try h.field(s, pending, "services", try s.get(reload, "services"));
    try h.field(s, pending, "tables", try h.map(s));
    try h.field(s, pending, "roots", try h.map(s));
    try h.field(s, pending, "abort", try s.keep(try js.builtin(s.engine, "AbortController", &.{})));
    try js.setKey(s.engine, host, try s.text("pending"), pending);
}
pub fn entries(s: *Scope, reload: c.JSValue) anyerror!c.JSValue {
    const source = try h.invoke(s, try s.get(reload, "host"), "liveDecls", &.{c.pi_js_bool(s.engine.context, 1)});
    const filtered = try s.list();
    const count = try h.length(s, source);
    for (0..count) |index| {
        const entry = try s.at(source, index);
        const record = try s.at(entry, 0);
        if (!try r.has(s, try s.get(reload, "removed"), try s.get(record, "typeName"))) try js.push(s.engine, filtered, entry);
    }
    const result = try s.list();
    for (0..try h.length(s, filtered)) |index| {
        const entry = try s.at(filtered, index);
        const record = try s.at(entry, 0);
        const candidate = try h.invoke(s, try s.get(reload, "candidates"), "get", &.{record});
        const decls = if (h.nullish(candidate)) try s.at(entry, 1) else try s.get(try s.get(candidate, "run"), "decls");
        try js.push(s.engine, result, try r.pair(s, record, if (h.nullish(decls)) try s.at(entry, 1) else decls));
    }
    return result;
}
pub fn stage(s: *Scope, reload: c.JSValue) anyerror!void {
    var candidates = try r.mapIterator(s, try s.get(reload, "candidates"), "values");
    defer candidates.deinit();
    errdefer candidates.closePreserving();
    while (try candidates.next()) |candidate| {
        defer s.engine.freeValue(candidate);
        const record = try s.get(candidate, "object");
        if (try s.equal(try s.get(record, "status"), "live")) try js.setKey(s.engine, candidate, try s.text("staged"), try h.invoke(s, record, "stageListeners", &.{try s.get(try s.get(candidate, "run"), "decls")}));
    }
    var records = try r.mapIterator(s, try s.get(try s.get(reload, "host"), "objects"), "values");
    defer records.deinit();
    errdefer records.closePreserving();
    while (try records.next()) |record| {
        defer s.engine.freeValue(record);
        if (try s.equal(try s.get(record, "status"), "live") and try h.flag(s, record, "deferredRuntime")) _ = try h.invoke(s, try s.get(reload, "deferred"), "set", &.{ record, try h.invoke(s, record, "stageListeners", &.{try s.get(record, "decls")}) });
    }
}
pub fn addresses(s: *Scope, candidates: c.JSValue) !c.JSValue {
    const result = try s.list();
    for (0..try h.length(s, candidates)) |index| try js.push(s.engine, result, try s.get(try s.get(try s.at(candidates, index), "object"), "address"));
    return result;
}
pub fn summary(s: *Scope, reload: c.JSValue) !c.JSValue {
    const live = try s.list();
    const all = try h.values(s, try s.get(reload, "candidates"));
    for (0..try h.length(s, all)) |index| {
        const candidate = try s.at(all, index);
        if (try s.equal(try s.get(try s.get(candidate, "object"), "status"), "live")) try js.push(s.engine, live, candidate);
    }
    const host = try s.get(reload, "host");
    const result = try s.record();
    const pending = try r.optional(s, try s.get(host, "pending"), "id");
    try h.field(s, result, "codeVersion", if (h.nullish(pending)) try s.get(try s.get(host, "current"), "id") else pending);
    try h.field(s, result, "previous", try s.get(try s.get(host, "current"), "id"));
    try h.field(s, result, "changed", try h.snapshot(s, try s.get(reload, "changed")));
    try h.field(s, result, "removed", try h.snapshot(s, try s.get(reload, "removed")));
    try h.field(s, result, "prepared", try addresses(s, live));
    try h.field(s, result, "gated", try addresses(s, try s.get(reload, "gated")));
    return result;
}
