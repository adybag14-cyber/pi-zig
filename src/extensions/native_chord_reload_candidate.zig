//! Source Reload candidate validation, state migration, provider and hold compatibility.
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const js = r.js;
const c = r.c;
const Scope = r.Scope;
const schema = @import("native_chord_host_record_schema.zig");
fn kindOf(s: *Scope, behavior: c.JSValue) !c.JSValue {
    return if (c.JS_IsString(try s.get(behavior, "kind"))) s.get(behavior, "kind") else c.pi_js_undefined();
}
fn memberSchemas(s: *Scope, bindings: c.JSValue, service: c.JSValue, behavior: c.JSValue) !c.JSValue {
    const schemas = try h.map(s);
    const contract = try s.get(service, "contract");
    if (!try s.equal(try s.get(contract, "scope"), "remote")) return schemas;
    const kind = try kindOf(s, behavior);
    const raw = try s.key(try s.get(try s.get(contract, "description"), "variants"), r.default(s, kind, try s.text("")));
    const entries = try s.entries(r.default(s, raw, try s.record()));
    for (0..try h.length(s, entries)) |index| {
        const entry = try s.at(entries, index);
        const description = try s.at(entry, 1);
        const source = try s.key(behavior, try s.at(entry, 0));
        if (!try s.equal(try s.get(description, "kind"), "state") or !try schema.source(s, bindings, source)) continue;
        const old = try h.invoke(s, schemas, "get", &.{source});
        const list = if (h.nullish(old)) try s.list() else try h.snapshot(s, old);
        try js.push(s.engine, list, try s.get(description, "schema"));
        _ = try h.invoke(s, schemas, "set", &.{ source, list });
    }
    return schemas;
}
fn compare(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return compareEntries(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compareEntries(engine: *h.Engine, a: c.JSValue, b: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const left = try s.get(try s.at(a, 1), "seq");
    const right = try s.get(try s.at(b, 1), "seq");
    return engine.checked(c.JS_PiBinaryOperator(engine.context, 1, left, right));
}
fn readSource(ctx: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    return readValue(engine, captures[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn readValue(engine: *h.Engine, values: c.JSValue, source: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return if (try r.has(&s, values, source)) js.invoke(engine, values, "get", &.{source}) else js.get(engine, source, "value");
}
pub fn dryRun(s: *Scope, bindings: c.JSValue, candidate: c.JSValue) anyerror!void {
    const run = try s.get(candidate, "run");
    const migrated = try s.get(candidate, "migrated");
    const service = try s.get(candidate, "service");
    const record = try s.get(candidate, "record");
    const exposed = try memberSchemas(s, bindings, service, try s.get(run, "behavior"));
    var migration_iter = try r.iterate(s, migrated);
    defer migration_iter.deinit();
    errdefer migration_iter.closePreserving();
    while (try migration_iter.next()) |entry| {
        defer s.engine.freeValue(entry);
        const cell = try s.at(entry, 0);
        const value = try s.at(entry, 1);
        const schemas = try h.invoke(s, exposed, "get", &.{cell});
        if (h.nullish(schemas)) continue;
        var iter = try r.iterate(s, schemas);
        defer iter.deinit();
        errdefer iter.closePreserving();
        while (try iter.next()) |check| {
            defer s.engine.freeValue(check);
            try schema.assertValid(s, bindings, "state", try r.concat(s, &.{ try s.get(record, "address"), try s.text(": migrated state "), try s.get(cell, "key") }), check, value);
        }
    }
    const values = try r.copyMap(s, migrated);
    const decls = try s.get(run, "decls");
    const derives = try h.snapshot(s, try s.get(decls, "derives"));
    const sorter = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, compare, "", 2, 0, 0, null)));
    _ = try h.invoke(s, derives, "sort", &.{sorter});
    var iter = try r.iterate(s, derives);
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |entry| {
        defer s.engine.freeValue(entry);
        const name = try s.at(entry, 0);
        const derived = try s.at(entry, 1);
        var captures = [_]c.JSValue{values};
        const read = try s.keep(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, readSource, "", 1, 0, 1, &captures)));
        const value = try h.invoke(s, derived, "compute", &.{ read, try h.invoke(s, try s.get(decls, "deriveFns"), "get", &.{name}) });
        const schemas = try h.invoke(s, exposed, "get", &.{derived});
        if (!h.nullish(schemas)) {
            var checks = try r.iterate(s, schemas);
            defer checks.deinit();
            errdefer checks.closePreserving();
            while (try checks.next()) |check| {
                defer s.engine.freeValue(check);
                try schema.assertValid(s, bindings, "state", try r.concat(s, &.{ try s.get(record, "address"), try s.text(": derived "), name }), check, value);
            }
        }
        _ = try h.invoke(s, values, "set", &.{ derived, value });
    }
    try js.setKey(s.engine, candidate, try s.text("derived"), values);
}
pub fn migrate(s: *Scope, bindings: c.JSValue, candidate: c.JSValue) anyerror!void {
    const record = try s.get(candidate, "record");
    const service = try s.get(candidate, "service");
    const run = try s.get(candidate, "run");
    const raw = try r.optional(s, try s.get(try s.get(service, "options"), "state"), "migrate");
    const functions = if (h.nullish(raw)) try s.record() else raw;
    const bumped = !c.JS_IsStrictEqual(s.engine.context, try s.get(service, "stateVersion"), try s.get(record, "stateVersion"));
    const decls = try s.get(run, "decls");
    var iter = try r.iterate(s, try s.get(decls, "cells"));
    defer iter.deinit();
    errdefer iter.closePreserving();
    while (try iter.next()) |entry| {
        defer s.engine.freeValue(entry);
        const name = try s.at(entry, 0);
        const cell = try s.at(entry, 1);
        if (!c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, try s.get(try s.get(record, "decls"), "cells"), "get", &.{name}), cell)) continue;
        const target_schema = try h.invoke(s, try s.get(decls, "cellSchemas"), "get", &.{name});
        const function = try s.key(functions, name);
        const value = if (bumped and !c.JS_IsUndefined(function)) blk: {
            const cloned = try s.keep(try @import("native_chord_clone.zig").clone(s.engine, try s.get(cell, "value")));
            break :blk try s.keep(try js.call(s.engine, function, c.pi_js_undefined(), &.{ cloned, try s.get(record, "stateVersion") }));
        } else if (!try @import("native_chord_canonical.zig").deepEqual(s.engine, try s.get(cell, "schema"), target_schema)) try s.get(cell, "value") else continue;
        try schema.assertValid(s, bindings, "state", try r.concat(s, &.{ try s.get(record, "address"), try s.text(": migrated state "), name }), target_schema, value);
        _ = try h.invoke(s, try s.get(candidate, "migrated"), "set", &.{ cell, value });
    }
    try dryRun(s, bindings, candidate);
}
pub fn checkProviders(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!void {
    const host = try s.get(reload, "host");
    const services = try s.get(reload, "services");
    const changed = try s.get(reload, "changed");
    var names = try r.iterate(s, changed);
    defer names.deinit();
    errdefer names.closePreserving();
    while (try names.next()) |name| {
        defer s.engine.freeValue(name);
        const next = try s.get(try h.invoke(s, services, "get", &.{name}), "contract");
        const old = try r.optional(s, try h.invoke(s, try s.get(try s.get(host, "current"), "services"), "get", &.{name}), "contract");
        if (c.JS_IsUndefined(old) or !c.JS_IsStrictEqual(s.engine.context, try s.get(old, "version"), try s.get(next, "version"))) continue;
        const why = try s.keep(try @import("native_chord_contracts.zig").coverage(s.engine, try s.get(next, "description"), try s.get(old, "description")));
        if (!c.JS_IsUndefined(why)) _ = try h.throwValue(s, try h.errorValue(s, bindings, "contract_mismatch", &.{ name, try s.text("@"), try s.get(next, "version"), try s.text(" changed incompatibly without a version bump ("), why, try s.text(")") }, c.pi_js_undefined()));
    }
    const facets = try r.copyMap(s, try s.get(host, "facets"));
    var updates = try r.iterate(s, try s.get(reload, "facets"));
    defer updates.deinit();
    errdefer updates.closePreserving();
    while (try updates.next()) |facet| {
        defer s.engine.freeValue(facet);
        _ = try h.invoke(s, facets, "set", &.{ try s.get(facet, "name"), facet });
    }
    const removes = try s.get(try s.get(reload, "options"), "remove");
    var removed = try r.iterate(s, if (h.nullish(removes)) try s.list() else removes);
    defer removed.deinit();
    errdefer removed.closePreserving();
    while (try removed.next()) |name| {
        defer s.engine.freeValue(name);
        _ = try h.invoke(s, facets, "delete", &.{name});
    }
    var all = try r.mapIterator(s, facets, "values");
    defer all.deinit();
    errdefer all.closePreserving();
    while (try all.next()) |facet| {
        defer s.engine.freeValue(facet);
        const uses = try s.get(facet, "uses");
        var tokens = try r.iterate(s, if (h.nullish(uses)) try s.list() else uses);
        defer tokens.deinit();
        errdefer tokens.closePreserving();
        while (try tokens.next()) |token| {
            defer s.engine.freeValue(token);
            const service = try h.invoke(s, services, "get", &.{try s.get(token, "name")});
            if (!c.JS_IsUndefined(service) and try r.has(s, changed, try s.get(token, "name"))) _ = try h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(service, "contract"), try s.get(try s.get(service, "options"), "accepts"), token });
        }
    }
}
pub fn checkHolds(s: *Scope, bindings: c.JSValue, reload: c.JSValue) anyerror!void {
    const dropped = try h.set(s);
    var candidates = try r.mapIterator(s, try s.get(reload, "candidates"), "values");
    defer candidates.deinit();
    errdefer candidates.closePreserving();
    while (try candidates.next()) |candidate| {
        defer s.engine.freeValue(candidate);
        const record = try s.get(candidate, "record");
        var holds = try r.mapIterator(s, try s.get(try s.get(record, "decls"), "holds"), "values");
        defer holds.deinit();
        errdefer holds.closePreserving();
        while (try holds.next()) |hold| {
            defer s.engine.freeValue(hold);
            const kept = try h.values(s, try s.get(try s.get(try s.get(candidate, "run"), "decls"), "holds"));
            if (c.JS_ToBool(s.engine.context, try h.invoke(s, kept, "includes", &.{hold})) == 0) _ = try h.invoke(s, dropped, "add", &.{hold});
        }
    }
    const host = try s.get(reload, "host");
    var records = try r.mapIterator(s, try s.get(host, "records"), "values");
    defer records.deinit();
    errdefer records.closePreserving();
    while (try records.next()) |record| {
        defer s.engine.freeValue(record);
        const service = try h.invoke(s, try s.get(reload, "services"), "get", &.{try s.get(record, "typeName")});
        if (c.JS_IsUndefined(service) or !try r.has(s, try s.get(reload, "changed"), try s.get(record, "typeName"))) continue;
        var holds = try r.iterate(s, try s.get(record, "holds"));
        defer holds.deinit();
        errdefer holds.closePreserving();
        while (try holds.next()) |hold| {
            defer s.engine.freeValue(hold);
            if (c.JS_IsStrictEqual(s.engine.context, hold, try h.invoke(s, try s.get(host, "eager"), "get", &.{try s.get(record, "typeName")}))) continue;
            if (!try r.has(s, dropped, hold) and !try s.equal(try s.get(hold, "owner"), "client")) _ = try h.invoke(s, try s.get(bindings, "contracts"), "bind", &.{ try s.get(service, "contract"), try s.get(try s.get(service, "options"), "accepts"), try s.get(hold, "contract") });
        }
    }
}
