//! Actual Source5ab headersToRecord and providerHeadersToRecord value semantics.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

pub fn toRecord(engine: *v.em.Engine, headers: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    var entries = try v.iterator(&scope, try scope.invoke(headers, "entries", &.{}));
    defer entries.deinit();
    errdefer entries.closePreserving();
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    while (try entries.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try v.js.pair(engine, entry, symbol);
        defer for (pair) |value| engine.freeValue(value);
        // Source uses assignment, including its ordinary __proto__ setter.
        try v.js.setKey(engine, result, pair[0], pair[1]);
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn providers(engine: *v.em.Engine, sources: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const merged = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    for (sources) |source| {
        var entries = try v.iterator(&scope, try scope.invoke(try scope.global("Object"), "entries", &.{if (v.nullish(source)) try scope.object() else source}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer engine.freeValue(entry);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const pair = try v.js.pair(engine, entry, symbol);
            defer for (pair) |value| engine.freeValue(value);
            const normalized = try row.invoke(pair[0], "toLowerCase", &.{});
            _ = try row.invoke(merged, "delete", &.{normalized});
            if (!c.JS_IsNull(pair[1])) {
                const value = try row.array();
                try row.index(value, 0, pair[0]);
                try row.index(value, 1, pair[1]);
                _ = try row.invoke(merged, "set", &.{ normalized, value });
            }
        }
    }
    if (!try @import("native_image_arithmetic.zig").compare(engine, .greater, try scope.get(merged, "size"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    const object = try scope.global("Object");
    const from_entries = try scope.get(object, "fromEntries");
    const values = try scope.invoke(merged, "values", &.{});
    return v.js.call(engine, from_entries, object, &.{values});
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (.{ "headersToRecord", "providerHeadersToRecord" }, 0..) |name, index| {
        const Adapter = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                return if (index == 0) toRecord(host, if (args.len > 0) args[0] else c.pi_js_undefined()) else providers(host, args);
            }
        };
        try scope.put(result, name, try scope.own(try @import("native_node_function.zig").create(engine, name, if (index == 0) 1 else 0, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, result);
}
