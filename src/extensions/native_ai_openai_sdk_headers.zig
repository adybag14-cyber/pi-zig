//! Pinned OpenAI6.40 internal/headers merge for this native client's actual
//! non-branded HeadersLike sources. Produces real Headers plus null tombstones;
//! no runtime identity is inferred or generated here.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const array_key = "\x00native-openai-sdk-header-array-predicate";
pub const Built = struct { values: c.JSValue, nulls: c.JSValue };
fn readonlyArray(scope: *Scope, value: c.JSValue) !bool {
    const engine = scope.engine;
    const predicate = if (engine.native_module_values.get(array_key)) |cached| cached else capture: {
        const function = try scope.get(try scope.global("Array"), "isArray");
        const retained = c.JS_DupValue(engine.context, function);
        engine.native_module_values.put(engine.gpa, array_key, retained) catch |err| {
            engine.freeValue(retained);
            return err;
        };
        break :capture retained;
    };
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
    return buildValues(engine, sources) catch |err| return engine.nativeAllocationError(err, generation);
}
fn buildValues(engine: *v.em.Engine, sources: []const c.JSValue) !Built {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const target = try scope.own(try v.js.builtin(engine, "Headers", &.{}));
    const nulls = try scope.own(try v.js.builtin(engine, "Set", &.{}));
    for (sources) |source| {
        const seen = try scope.own(try v.js.builtin(engine, "Set", &.{}));
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
