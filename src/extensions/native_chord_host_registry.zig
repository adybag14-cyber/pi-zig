//! Actual epoch registry construction, conflict admission and FIFO publication.
const h = @import("native_chord_host_values.zig");
const Scope = h.Scope;
const js = h.js;
const c = h.c;
const ViewMethod = enum(c_int) { table, get, subscribe, unsubscribe };
fn table(s: *Scope, host: c.JSValue, registry: c.JSValue, context: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const epoch = if (c.JS_IsUndefined(context)) try s.get(host, "current") else try h.invoke(s, try s.get(host, "epochs"), "get", &.{try s.get(context, "epoch")});
    if (c.JS_IsUndefined(epoch)) {
        const id = if (h.nullish(context)) c.pi_js_undefined() else try s.get(context, "epoch");
        return h.throwValue(s, try h.errorValue(s, bindings, "superseded", &.{ try s.text("epoch "), id, try s.text(" is retired") }, c.pi_js_undefined()));
    }
    const value = try h.invoke(s, try s.get(epoch, "tables"), "get", &.{try s.get(registry, "name")});
    return if (h.nullish(value)) s.get(bindings, "emptyTable") else value;
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return viewInvoke(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, @enumFromInt(operation), data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn viewInvoke(engine: *h.Engine, args: []const c.JSValue, method: ViewMethod, data: [*c]c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (method == .unsubscribe) return js.invoke(engine, data[0], "delete", &.{data[1]});
    const host = data[0];
    const registry = data[1];
    const bindings = data[2];
    if (method == .table) return s.result(try table(&s, host, registry, h.arg(args, 0), bindings));
    if (method == .get) return js.invoke(engine, try table(&s, host, registry, h.arg(args, 1), bindings), "get", &.{h.arg(args, 0)});
    const owned = try h.actor(&s, host, bindings, .HostImpl);
    const subscribers = try s.get(owned.data, "subscribers");
    var listeners = try h.invoke(&s, subscribers, "get", &.{try s.get(registry, "name")});
    if (c.JS_IsUndefined(listeners)) {
        listeners = try h.set(&s);
        _ = try h.invoke(&s, subscribers, "set", &.{ try s.get(registry, "name"), listeners });
    }
    const listener = h.arg(args, 0);
    _ = try h.invoke(&s, listeners, "add", &.{listener});
    const current = try table(&s, host, registry, c.pi_js_undefined(), bindings);
    _ = try s.keep(try js.call(engine, listener, c.pi_js_undefined(), &.{ current, try s.get(try s.get(host, "current"), "id") }));
    var captures = [_]c.JSValue{ listeners, listener };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "", 0, @intFromEnum(ViewMethod.unsubscribe), 2, &captures));
}
pub fn view(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, registry: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.record();
    inline for (.{ .{ "table", ViewMethod.table, 1 }, .{ "get", ViewMethod.get, 2 }, .{ "subscribe", ViewMethod.subscribe, 1 } }) |item| {
        var captures = [_]c.JSValue{ host, registry, bindings };
        try js.define(engine, result, item[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, item[0], item[2], @intFromEnum(item[1]), 3, &captures)));
    }
    return s.result(result);
}
fn compareEntries(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return compare(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined(), data[0]) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn compare(engine: *h.Engine, left: c.JSValue, right: c.JSValue, order: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const a = try h.invoke(&s, order, "get", &.{try s.at(left, 0)});
    const b = try h.invoke(&s, order, "get", &.{try s.at(right, 0)});
    var x: f64 = undefined;
    var y: f64 = undefined;
    if (c.JS_ToFloat64(engine.context, &x, a) < 0 or c.JS_ToFloat64(engine.context, &y, b) < 0) return js.capture(engine);
    return c.JS_NewFloat64(engine.context, x - y);
}
pub fn build(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, input: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const by_registry = try h.map(&s);
    const symbol = try s.keep(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, input, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |pair| {
        defer engine.freeValue(pair);
        const fields = try js.pair(engine, pair, symbol);
        defer for (fields) |field| engine.freeValue(field);
        const record = fields[0];
        const decls = fields[1];
        const registrations = try h.values(&s, try s.get(decls, "registrations"));
        const count = try h.length(&s, registrations);
        for (0..count) |index| {
            const registration = try s.at(registrations, index);
            const registry = try s.get(registration, "registry");
            const key = try s.get(registration, "key");
            const value = try s.get(registration, "value");
            var entries = try h.invoke(&s, by_registry, "get", &.{try s.get(registry, "name")});
            if (c.JS_IsUndefined(entries)) {
                entries = try h.map(&s);
                _ = try h.invoke(&s, by_registry, "set", &.{ try s.get(registry, "name"), entries });
            }
            const existing = try h.invoke(&s, entries, "get", &.{key});
            if (!c.JS_IsUndefined(existing) and !c.JS_IsStrictEqual(engine.context, try s.get(existing, "record"), record) and try s.equal(try s.get(registry, "conflict"), "error")) return h.invalid(&s, bindings, "registry_conflict", &.{ try s.get(registry, "name"), try s.text(": "), key, try s.text(" registered by "), try s.get(try s.get(existing, "record"), "address"), try s.text(" and "), try s.get(record, "address") });
            const entry = try s.record();
            try h.field(&s, entry, "value", value);
            try h.field(&s, entry, "record", record);
            _ = try h.invoke(&s, entries, "set", &.{ key, entry });
            const owned = try h.actor(&s, host, bindings, .HostImpl);
            const orders = try s.get(owned.data, "order");
            var order = try h.invoke(&s, orders, "get", &.{try s.get(registry, "name")});
            if (c.JS_IsUndefined(order)) {
                order = try h.map(&s);
                _ = try h.invoke(&s, orders, "set", &.{ try s.get(registry, "name"), order });
            }
            if (c.JS_ToBool(engine.context, try h.invoke(&s, order, "has", &.{key})) == 0) _ = try h.invoke(&s, order, "set", &.{ key, try s.get(order, "size") });
        }
    }
    const tables = try h.map(&s);
    const registries = try h.entries(&s, by_registry);
    const count = try h.length(&s, registries);
    for (0..count) |index| {
        const pair = try s.at(registries, index);
        const name = try s.at(pair, 0);
        const entries = try s.at(pair, 1);
        const owned = try h.actor(&s, host, bindings, .HostImpl);
        const order = try h.invoke(&s, try s.get(owned.data, "order"), "get", &.{name});
        var captures = [_]c.JSValue{order};
        const comparator = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, compareEntries, "", 2, 0, 1, &captures)));
        const sorted = try h.invoke(&s, try h.entries(&s, entries), "sort", &.{comparator});
        const result = try h.map(&s);
        const size = try h.length(&s, sorted);
        for (0..size) |position| {
            const item = try s.at(sorted, position);
            _ = try h.invoke(&s, result, "set", &.{ try s.at(item, 0), try s.get(try s.at(item, 1), "value") });
        }
        _ = try h.invoke(&s, tables, "set", &.{ name, result });
    }
    return s.result(tables);
}
fn same(s: *Scope, left: c.JSValue, right: c.JSValue) !bool {
    if (!c.JS_IsStrictEqual(s.engine.context, try s.get(left, "size"), try s.get(right, "size"))) return false;
    const keys = try h.snapshot(s, try h.invoke(s, left, "keys", &.{}));
    const entries = try h.entries(s, right);
    const count = try h.length(s, entries);
    for (0..count) |index| {
        const entry = try s.at(entries, index);
        const key = try s.at(entry, 0);
        if (!c.JS_IsStrictEqual(s.engine.context, try s.at(keys, index), key) or !c.JS_IsStrictEqual(s.engine.context, try h.invoke(s, left, "get", &.{key}), try s.at(entry, 1))) return false;
    }
    return true;
}
fn notification(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(context.?);
    return notify(engine, data) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn notify(engine: *h.Engine, data: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const count = try h.length(&s, data[0]);
    for (0..count) |index| {
        const result = js.call(engine, try s.at(data[0], index), c.pi_js_undefined(), &.{ data[1], data[2] }) catch |err| {
            if (err != error.JavaScriptException) return err;
            const failure = engine.captured_exception orelse return err;
            _ = try h.invoke(&s, data[3], "report", &.{failure});
            continue;
        };
        engine.freeValue(result);
    }
    return c.pi_js_undefined();
}
pub fn installTables(engine: *h.Engine, bindings: c.JSValue, host: c.JSValue, epoch: c.JSValue, tables: c.JSValue, all: bool) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const before = try s.get(epoch, "tables");
    try h.field(&s, epoch, "tables", tables);
    if (!c.JS_IsStrictEqual(engine.context, epoch, try s.get(host, "current"))) return;
    const owned = try h.actor(&s, host, bindings, .HostImpl);
    const subscribers = try h.entries(&s, try s.get(owned.data, "subscribers"));
    const count = try h.length(&s, subscribers);
    for (0..count) |index| {
        const pair = try s.at(subscribers, index);
        const name = try s.at(pair, 0);
        const listeners = try s.at(pair, 1);
        const raw_next = try h.invoke(&s, tables, "get", &.{name});
        const next = if (h.nullish(raw_next)) try s.get(bindings, "emptyTable") else raw_next;
        const raw_previous = try h.invoke(&s, before, "get", &.{name});
        const previous = if (h.nullish(raw_previous)) try s.get(bindings, "emptyTable") else raw_previous;
        if (!all and try same(&s, previous, next)) continue;
        const current = try h.snapshot(&s, listeners);
        var captures = [_]c.JSValue{ current, next, try s.get(epoch, "id"), host };
        const task = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, notification, "", 0, 0, 4, &captures)));
        try @import("native_chord_publish.zig").enqueue(engine, bindings, task);
    }
}
