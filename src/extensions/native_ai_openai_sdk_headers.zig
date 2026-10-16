//! Pinned OpenAI6.40 internal/headers merge for this native client's actual
//! non-branded HeadersLike sources. Produces real Headers plus null tombstones;
//! no runtime identity is inferred or generated here.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub const Built = struct { values: c.JSValue, nulls: c.JSValue };
pub const Layer = union(enum) { plain: c.JSValue, nullable: Built };
fn readonlyArray(scope: *Scope, value: c.JSValue) !bool {
    // values.mjs's isReadonlyArray retains the initial wrapper, not the
    // rebound isArray export. That wrapper rereads Array.isArray each call.
    const predicate = try scope.get(try scope.global("Array"), "isArray");
    return scope.truthy(try scope.call(predicate, c.pi_js_undefined(), &.{value}));
}
fn apply(scope: *Scope, target: c.JSValue, nulls: c.JSValue, seen: c.JSValue, name: c.JSValue, value: c.JSValue) !void {
    const normalized = try scope.invoke(name, "toLowerCase", &.{});
    if (!scope.truthy(try scope.invoke(seen, "has", &.{normalized}))) {
        _ = try scope.invoke(target, "delete", &.{name});
        _ = try scope.invoke(seen, "add", &.{normalized});
    }
    if (c.JS_IsNull(value)) {
        _ = try scope.invoke(target, "delete", &.{name});
        _ = try scope.invoke(nulls, "add", &.{normalized});
    } else {
        _ = try scope.invoke(target, "append", &.{ name, value });
        _ = try scope.invoke(nulls, "delete", &.{normalized});
    }
}
pub fn build(engine: *v.em.Engine, sources: []const c.JSValue) !Built {
    const generation = engine.native_allocation_generation;
    return buildPlain(engine, sources) catch |err| return engine.nativeAllocationError(err, generation);
}
fn buildPlain(engine: *v.em.Engine, sources: []const c.JSValue) !Built {
    const layers = try engine.gpa.alloc(Layer, sources.len);
    defer engine.gpa.free(layers);
    for (sources, layers) |source, *layer| layer.* = .{ .plain = source };
    return buildMixed(engine, layers);
}
/// The constructor's early nullable merge is an actual Headers/Set pair. Keep
/// its tombstones when layering it after SDK/auth defaults at request time.
pub fn buildMixed(engine: *v.em.Engine, sources: []const Layer) !Built {
    const generation = engine.native_allocation_generation;
    return buildValues(engine, sources) catch |err| return engine.nativeAllocationError(err, generation);
}
fn buildValues(engine: *v.em.Engine, sources: []const Layer) !Built {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const target = try scope.own(try v.js.builtin(engine, "Headers", &.{}));
    const nulls = try scope.own(try v.js.builtin(engine, "Set", &.{}));
    for (sources) |layer| {
        const seen = try scope.own(try v.js.builtin(engine, "Set", &.{}));
        const source = switch (layer) {
            .plain => |value| value,
            .nullable => |prepared| {
                var entries = try v.iterator(&scope, try scope.invoke(prepared.values, "entries", &.{}));
                defer entries.deinit();
                errdefer entries.closePreserving();
                while (try entries.next()) |entry| {
                    defer engine.freeValue(entry);
                    const fields = try v.js.pair(engine, entry, try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
                    defer for (fields) |field| engine.freeValue(field);
                    try apply(&scope, target, nulls, seen, fields[0], fields[1]);
                }
                var removed = try v.iterator(&scope, prepared.nulls);
                defer removed.deinit();
                errdefer removed.closePreserving();
                while (try removed.next()) |name| {
                    defer engine.freeValue(name);
                    try apply(&scope, target, nulls, seen, name, c.pi_js_null());
                }
                continue;
            },
        };
        if (!scope.truthy(source)) continue;
        const instance = c.JS_IsInstanceOf(engine.context, source, try scope.global("Headers"));
        if (instance < 0) return v.js.capture(engine);
        const record = instance == 0 and !try readonlyArray(&scope, source);
        const entries = if (instance != 0) try scope.invoke(source, "entries", &.{}) else if (!record) source else try scope.invoke(try scope.global("Object"), "entries", &.{source});
        var rows = try v.iterator(&scope, entries);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |entry| {
            defer engine.freeValue(entry);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            const name = try v.at(&row, entry, 0);
            if (!c.JS_IsString(name)) return v.js.typeError(engine, "expected header name to be a string");
            const values = if (try readonlyArray(&row, try v.at(&row, entry, 1))) try v.at(&row, entry, 1) else single: {
                const result = try row.array();
                try row.index(result, 0, try v.at(&row, entry, 1));
                break :single result;
            };
            var items = try v.iterator(&row, values);
            defer items.deinit();
            errdefer items.closePreserving();
            var cleared = false;
            while (try items.next()) |value| {
                defer engine.freeValue(value);
                if (c.JS_IsUndefined(value)) continue;
                // Each object key overwrites, whereas tuple/Headers sources
                // append repeated names after their first per-source clear.
                if (record and !cleared) {
                    cleared = true;
                    try apply(&row, target, nulls, seen, name, c.pi_js_null());
                }
                try apply(&row, target, nulls, seen, name, value);
            }
        }
    }
    return .{ .values = c.JS_DupValue(engine.context, target), .nulls = c.JS_DupValue(engine.context, nulls) };
}
