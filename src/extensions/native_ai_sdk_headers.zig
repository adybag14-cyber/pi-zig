//! Native nullable header composition from pinned Anthropic SDK 0.129.0.
//! Inputs and output retain genuine Headers/Set objects and guest iterators.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;

pub fn install(engine: *v.em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try state(&scope);
}
fn state(scope: *Scope) !c.JSValue {
    const key = "\x00native-sdk-nullable-headers";
    if (scope.engine.native_module_values.get(key)) |existing| return existing;
    const result = try scope.object();
    try scope.put(result, "brand", try scope.invoke(try scope.global("Symbol"), "for", &.{try scope.text("brand.privateNullableHeaders")}));
    const values = try scope.array();
    try scope.index(values, 0, try scope.text("x-stainless-helper"));
    try scope.put(result, "append", try scope.own(try v.js.builtin(scope.engine, "Set", &.{values})));
    const retained = c.JS_DupValue(scope.engine.context, result);
    scope.engine.native_module_values.put(scope.engine.gpa, key, retained) catch |err| {
        scope.engine.freeValue(retained);
        return err;
    };
    return result;
}
fn trimmed(scope: *Scope, input: c.JSValue) !c.JSValue {
    const Trim = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return v.js.invoke(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "trim", &.{});
        }
    };
    const method = try scope.get(input, "map");
    const callback = try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Trim.call, &.{}));
    return scope.call(method, input, &.{callback});
}
pub fn appendValue(scope: *Scope, existing: c.JSValue, addition: c.JSValue) !c.JSValue {
    const tokens = if (scope.truthy(existing)) nonempty: {
        const values = try trimmed(scope, try scope.invoke(existing, "split", &.{try scope.text(",")}));
        const filter = try scope.get(values, "filter");
        break :nonempty try scope.call(filter, values, &.{try scope.global("Boolean")});
    } else try scope.array();
    var rows = try v.iterator(scope, try trimmed(scope, try scope.invoke(addition, "split", &.{try scope.text(",")})));
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |token| {
        defer scope.engine.freeValue(token);
        if (scope.truthy(token) and !scope.truthy(try scope.invoke(tokens, "includes", &.{token}))) _ = try scope.invoke(tokens, "push", &.{token});
    }
    return scope.invoke(tokens, "join", &.{try scope.text(", ")});
}
fn consume(scope: *Scope, owner: c.JSValue, seen: c.JSValue, name: c.JSValue, value: c.JSValue, clear: bool, append: c.JSValue) !void {
    const headers = try scope.get(owner, "values");
    const nulls = try scope.get(owner, "nulls");
    const lower = try scope.invoke(name, "toLowerCase", &.{});
    if (scope.truthy(try scope.invoke(append, "has", &.{lower}))) {
        if (clear) return;
        if (c.JS_IsNull(value)) {
            _ = try scope.invoke(headers, "delete", &.{name});
            _ = try scope.invoke(nulls, "add", &.{lower});
        } else {
            const method = try scope.get(headers, "set");
            const old = try scope.invoke(headers, "get", &.{name});
            _ = try scope.call(method, headers, &.{ name, try appendValue(scope, old, value) });
            _ = try scope.invoke(nulls, "delete", &.{lower});
        }
        return;
    }
    if (clear or !scope.truthy(try scope.invoke(seen, "has", &.{lower}))) {
        _ = try scope.invoke(headers, "delete", &.{name});
        _ = try scope.invoke(seen, "add", &.{lower});
        if (clear) return;
    }
    if (c.JS_IsNull(value)) {
        _ = try scope.invoke(headers, "delete", &.{name});
        _ = try scope.invoke(nulls, "add", &.{lower});
    } else {
        _ = try scope.invoke(headers, "append", &.{ name, value });
        _ = try scope.invoke(nulls, "delete", &.{lower});
    }
}
fn directRows(scope: *Scope, owner: c.JSValue, seen: c.JSValue, rows: c.JSValue, append: c.JSValue) !void {
    var entries = try v.iterator(scope, rows);
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer scope.engine.freeValue(entry);
        try consume(scope, owner, seen, try v.at(scope, entry, 0), try v.at(scope, entry, 1), false, append);
    }
}
fn sourceRows(scope: *Scope, owner: c.JSValue, seen: c.JSValue, source: c.JSValue, module: c.JSValue) !void {
    if (!scope.truthy(source)) return;
    const append = try scope.get(module, "append");
    if (try v.js.has(scope.engine, source, try scope.get(module, "brand"))) {
        const values = try scope.get(source, "values");
        const nulls = try scope.get(source, "nulls");
        try directRows(scope, owner, seen, try scope.invoke(values, "entries", &.{}), append);
        var removed = try v.iterator(scope, nulls);
        defer removed.deinit();
        errdefer removed.closePreserving();
        while (try removed.next()) |name| {
            defer scope.engine.freeValue(name);
            try consume(scope, owner, seen, name, c.pi_js_null(), false, append);
        }
        return;
    }
    const branded = c.JS_IsInstanceOf(scope.engine.context, source, try scope.global("Headers"));
    if (branded < 0) return v.js.capture(scope.engine);
    var clear = false;
    const entries = if (branded == 1) try scope.invoke(source, "entries", &.{}) else if (try v.array(scope, source)) source else rows: {
        clear = true;
        break :rows try scope.invoke(try scope.global("Object"), "entries", &.{source});
    };
    var rows = try v.iterator(scope, entries);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const name = try v.at(scope, entry, 0);
        if (!c.JS_IsString(name)) return v.js.typeError(scope.engine, "expected header name to be a string");
        const test_value = try v.at(scope, entry, 1);
        const values = if (try v.array(scope, test_value)) try v.at(scope, entry, 1) else singleton: {
            const result = try scope.array();
            try scope.index(result, 0, try v.at(scope, entry, 1));
            break :singleton result;
        };
        var did_clear = false;
        var members = try v.iterator(scope, values);
        defer members.deinit();
        errdefer members.closePreserving();
        while (try members.next()) |value| {
            defer scope.engine.freeValue(value);
            if (c.JS_IsUndefined(value)) continue;
            if (clear and !did_clear) {
                did_clear = true;
                try consume(scope, owner, seen, name, c.pi_js_undefined(), true, append);
            }
            try consume(scope, owner, seen, name, value, false, append);
        }
    }
}
/// Borrowed result rooted in scope: { [SDK brand]: true, values: Headers, nulls: Set }.
pub fn build(scope: *Scope, sources: []const c.JSValue) !c.JSValue {
    const module = try state(scope);
    const result = try scope.object();
    try scope.put(result, "values", try scope.own(try v.js.builtin(scope.engine, "Headers", &.{})));
    try scope.put(result, "nulls", try scope.own(try v.js.builtin(scope.engine, "Set", &.{})));
    for (sources) |source| {
        const seen = try scope.own(try v.js.builtin(scope.engine, "Set", &.{}));
        try sourceRows(scope, result, seen, source, module);
    }
    const brand = try v.js.atom(scope.engine, try scope.get(module, "brand"));
    defer c.JS_FreeAtom(scope.engine.context, brand);
    if (c.JS_DefinePropertyValue(scope.engine.context, result, brand, c.pi_js_bool(scope.engine.context, 1), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
    return result;
}
