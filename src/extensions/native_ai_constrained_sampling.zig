//! Actual shared strict JSON schema conversion with provider keyword checks.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub const KeywordCheck = *const fn (*Scope, c.JSValue, c.JSValue) anyerror!bool;
fn object(scope: *Scope, value: c.JSValue) !bool {
    return c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value) and !try v.array(scope, value);
}
fn schemaNull(scope: *Scope, schema: c.JSValue, steps: *usize) anyerror!bool {
    try @import("native_ai_budget.zig").step(scope.engine, steps);
    if (!try object(scope, schema)) return false;
    const kind = try scope.get(schema, "type");
    if (try v.eq(scope, kind, "null") or (try v.array(scope, kind) and scope.truthy(try scope.invoke(kind, "includes", &.{try scope.text("null")})))) return true;
    const enumeration = try scope.get(schema, "enum");
    if (c.JS_IsNull(try scope.get(schema, "const")) or (try v.array(scope, enumeration) and scope.truthy(try scope.invoke(enumeration, "includes", &.{c.pi_js_null()})))) return true;
    const choices = try scope.get(schema, "anyOf");
    if (!try v.array(scope, choices)) return false;
    var rows = try v.iterator(scope, choices);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |child| {
        defer scope.engine.freeValue(child);
        if (try schemaNull(scope, child, steps)) return true;
    }
    return false;
}
fn structured(scope: *Scope, schema: c.JSValue) !bool {
    if (!try object(scope, schema)) return false;
    const kind = try scope.get(schema, "type");
    if (c.JS_IsString(kind)) return try v.eq(scope, kind, "object") or try v.eq(scope, kind, "array") or !c.JS_IsUndefined(try scope.get(schema, "properties")) or !c.JS_IsUndefined(try scope.get(schema, "items"));
    return (try v.array(scope, kind) and (scope.truthy(try scope.invoke(kind, "includes", &.{try scope.text("object")})) or scope.truthy(try scope.invoke(kind, "includes", &.{try scope.text("array")})))) or !c.JS_IsUndefined(try scope.get(schema, "properties")) or !c.JS_IsUndefined(try scope.get(schema, "items"));
}
fn strictNode(scope: *Scope, schema: c.JSValue, reason: *c.JSValue, steps: *usize, predicate: ?KeywordCheck) anyerror!void {
    try @import("native_ai_budget.zig").step(scope.engine, steps);
    if (!try object(scope, schema)) {
        reason.* = try scope.text("boolean schemas are unsupported");
        return error.UnsupportedStrictJsonSchema;
    }
    inline for (.{ "$ref", "$defs", "definitions", "allOf", "oneOf", "patternProperties", "dependentSchemas", "dependencies", "unevaluatedProperties", "propertyNames", "contains", "prefixItems", "not", "if", "then", "else" }) |key| {
        if (!c.JS_IsUndefined(try scope.get(schema, key))) {
            reason.* = try scope.text(key ++ " schemas are unsupported");
            return error.UnsupportedStrictJsonSchema;
        }
    }
    if (predicate) |check| {
        var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{schema}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const key = try v.at(scope, entry, 0);
            const value = try v.at(scope, entry, 1);
            if (try check(scope, key, value)) {
                reason.* = try scope.concat(try scope.concat(try scope.concat(key, try scope.text(": ")), try scope.invoke(try scope.global("JSON"), "stringify", &.{value})), try scope.text(" is unsupported"));
                return error.UnsupportedStrictJsonSchema;
            }
        }
    }
    const any_of = try scope.get(schema, "anyOf");
    if (!c.JS_IsUndefined(any_of)) {
        if (!try v.array(scope, any_of) or try v.length(scope, any_of) == 0) {
            reason.* = try scope.text("anyOf must contain at least one schema");
            return error.UnsupportedStrictJsonSchema;
        }
        var rows = try v.iterator(scope, any_of);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |child| {
            defer scope.engine.freeValue(child);
            if (try structured(scope, child)) {
                reason.* = try scope.text("object and array unions are unsupported");
                return error.UnsupportedStrictJsonSchema;
            }
            try strictNode(scope, child, reason, steps, predicate);
        }
    }
    const items = try scope.get(schema, "items");
    if (!c.JS_IsUndefined(items)) {
        if (try v.array(scope, items)) {
            reason.* = try scope.text("tuple schemas are unsupported");
            return error.UnsupportedStrictJsonSchema;
        }
        try strictNode(scope, items, reason, steps, predicate);
    }
    const is_object = try v.eq(scope, try scope.get(schema, "type"), "object");
    const raw_properties = try scope.get(schema, "properties");
    if (!c.JS_IsUndefined(raw_properties) and !is_object) {
        reason.* = try scope.text("properties require type object");
        return error.UnsupportedStrictJsonSchema;
    }
    if (!is_object) return;
    const additional = try scope.get(schema, "additionalProperties");
    if (!c.JS_IsUndefined(additional) and !scope.equal(additional, c.pi_js_bool(scope.engine.context, 0))) {
        reason.* = try scope.text("schema-valued or true additionalProperties is unsupported");
        return error.UnsupportedStrictJsonSchema;
    }
    if (!c.JS_IsUndefined(raw_properties) and !try object(scope, raw_properties)) {
        reason.* = try scope.text("object properties must be a schema map");
        return error.UnsupportedStrictJsonSchema;
    }
    const raw_required = try scope.get(schema, "required");
    if (!c.JS_IsUndefined(raw_required)) {
        if (!try v.array(scope, raw_required)) {
            reason.* = try scope.text("object required must be a string array");
            return error.UnsupportedStrictJsonSchema;
        }
        var rows = try v.iterator(scope, raw_required);
        defer rows.deinit();
        errdefer rows.closePreserving();
        while (try rows.next()) |key| {
            defer scope.engine.freeValue(key);
            if (!c.JS_IsString(key)) {
                reason.* = try scope.text("object required must be a string array");
                return error.UnsupportedStrictJsonSchema;
            }
        }
    }
    const properties = if (v.nullish(raw_properties)) try scope.object() else raw_properties;
    const names = try scope.invoke(try scope.global("Object"), "keys", &.{properties});
    const required = try scope.own(try v.js.builtin(scope.engine, "Set", &.{if (try v.array(scope, raw_required)) raw_required else try scope.array()}));
    var keys = try v.iterator(scope, try scope.invoke(required, "values", &.{}));
    defer keys.deinit();
    errdefer keys.closePreserving();
    while (try keys.next()) |key| {
        defer scope.engine.freeValue(key);
        if (!scope.truthy(try scope.invoke(names, "includes", &.{key}))) {
            reason.* = try scope.text("required contains an unknown property");
            return error.UnsupportedStrictJsonSchema;
        }
    }
    var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{properties}));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const key = try v.at(scope, entry, 0);
        const property = try v.at(scope, entry, 1);
        try strictNode(scope, property, reason, steps, predicate);
        if (!scope.truthy(try scope.invoke(required, "has", &.{key})) and !try schemaNull(scope, property, steps)) {
            const nullable = try scope.object();
            try scope.put(nullable, "type", try scope.text("null"));
            const variants = try scope.array();
            _ = try scope.invoke(variants, "push", &.{ property, nullable });
            const wrapper = try scope.object();
            try scope.put(wrapper, "anyOf", variants);
            try v.js.setKey(scope.engine, properties, key, wrapper);
        }
    }
    try scope.set(schema, "required", names);
    try scope.set(schema, "additionalProperties", c.pi_js_bool(scope.engine.context, 0));
}
pub fn makeStrict(scope: *Scope, schema: c.JSValue, reason: *c.JSValue, predicate: ?KeywordCheck) !c.JSValue {
    const clone = try scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{schema});
    if (!try object(scope, clone)) {
        reason.* = try scope.text("root schema must have type object");
        return error.UnsupportedStrictJsonSchema;
    }
    var steps: usize = 0;
    try strictNode(scope, clone, reason, &steps, predicate);
    if (!try v.eq(scope, try scope.get(clone, "type"), "object")) {
        reason.* = try scope.text("root schema must have type object");
        return error.UnsupportedStrictJsonSchema;
    }
    return clone;
}
