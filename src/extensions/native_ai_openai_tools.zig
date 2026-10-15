//! Actual OpenAI grammar and JSON-schema tool conversion.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
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
fn strictNode(scope: *Scope, schema: c.JSValue, reason: *c.JSValue, steps: *usize) anyerror!void {
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
            try strictNode(scope, child, reason, steps);
        }
    }
    const items = try scope.get(schema, "items");
    if (!c.JS_IsUndefined(items)) {
        if (try v.array(scope, items)) {
            reason.* = try scope.text("tuple schemas are unsupported");
            return error.UnsupportedStrictJsonSchema;
        }
        try strictNode(scope, items, reason, steps);
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
        try strictNode(scope, property, reason, steps);
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
fn makeStrict(scope: *Scope, schema: c.JSValue, reason: *c.JSValue) !c.JSValue {
    const clone = try scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{schema});
    if (!try object(scope, clone)) {
        reason.* = try scope.text("root schema must have type object");
        return error.UnsupportedStrictJsonSchema;
    }
    var steps: usize = 0;
    try strictNode(scope, clone, reason, &steps);
    if (!try v.eq(scope, try scope.get(clone, "type"), "object")) {
        reason.* = try scope.text("root schema must have type object");
        return error.UnsupportedStrictJsonSchema;
    }
    return clone;
}
pub fn grammar(scope: *Scope, tool: c.JSValue, supported: bool) !c.JSValue {
    const config = try scope.get(tool, "constrainedSampling");
    if (!scope.truthy(config) or !try v.eq(scope, try scope.get(config, "type"), "grammar") or !supported) return c.pi_js_undefined();
    const variants = try scope.get(config, "variants");
    const lark = try scope.get(variants, "openai_lark");
    const regex = try scope.get(variants, "openai_regex");
    const has_lark = c.JS_IsString(lark) and try v.length(scope, try scope.invoke(lark, "trim", &.{})) > 0;
    const has_regex = c.JS_IsString(regex) and try v.length(scope, try scope.invoke(regex, "trim", &.{})) > 0;
    var reason: ?[]const u8 = null;
    if (!has_lark and !has_regex) reason = "no supported grammar variant was provided";
    const schema = try scope.get(tool, "parameters");
    if (reason == null and !try v.eq(scope, try scope.get(schema, "type"), "object")) reason = "grammar constrained sampling requires an object parameter schema";
    const required = try scope.get(schema, "required");
    if (reason == null and (!try v.array(scope, required) or try v.length(scope, required) != 1 or !c.JS_IsString(try v.at(scope, required, 0)))) reason = "grammar constrained sampling requires exactly one required string property";
    const property = if (reason == null) try v.at(scope, required, 0) else c.pi_js_undefined();
    const properties = try scope.get(schema, "properties");
    const declaration = if (reason == null and !v.nullish(properties)) try scope.own(try v.js.getKey(scope.engine, properties, property)) else c.pi_js_undefined();
    if (reason == null and !scope.truthy(declaration)) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" cannot use grammar constrained sampling: grammar constrained sampling requires a properties entry for ")), try scope.concat(try scope.stringify(property), try scope.text("."))));
    if (reason == null and !try v.eq(scope, try v.optional(scope, declaration, "type"), "string")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" cannot use grammar constrained sampling: grammar constrained sampling property ")), try scope.concat(try scope.stringify(property), try scope.text(" must have type string."))));
    if (reason) |why| return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" cannot use grammar constrained sampling: ")), try scope.concat(try scope.text(why), try scope.text("."))));
    const result = try scope.object();
    try scope.put(result, "format", try scope.text(if (has_lark) "lark" else "regex"));
    try scope.put(result, "definition", if (has_lark) lark else regex);
    try scope.put(result, "inputProperty", property);
    return result;
}
pub fn grammarProperties(engine: *v.em.Engine, tools: c.JSValue, supported: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    var rows = try v.iterator(&scope, if (v.nullish(tools)) try scope.array() else tools);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |tool| {
        defer engine.freeValue(tool);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const config = try grammar(&row, tool, supported);
        if (row.truthy(config)) _ = try row.invoke(result, "set", &.{ try row.get(tool, "name"), try row.get(config, "inputProperty") });
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn convert(engine: *v.em.Engine, tools: c.JSValue, compat: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            return convertTool(&row, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
        }
    };
    return v.js.invoke(engine, tools, "map", &.{try scope.own(try @import("native_node_function.zig").create(engine, "", 1, Adapter.call, &.{compat}))});
}
fn convertTool(scope: *Scope, tool: c.JSValue, compat: c.JSValue) !c.JSValue {
    const config = try grammar(scope, tool, scope.truthy(try scope.get(compat, "supportsOpenAIGrammarTools")));
    const result = try scope.object();
    const body = try scope.object();
    if (scope.truthy(config)) {
        try scope.put(result, "type", try scope.text("custom"));
        try scope.put(body, "name", try scope.get(tool, "name"));
        try scope.put(body, "description", try scope.get(tool, "description"));
        const format = try scope.object();
        try scope.put(format, "type", try scope.text("grammar"));
        const grammar_format = try scope.object();
        try scope.put(grammar_format, "syntax", try scope.get(config, "format"));
        try scope.put(grammar_format, "definition", try scope.get(config, "definition"));
        try scope.put(format, "grammar", grammar_format);
        try scope.put(body, "format", format);
        try scope.put(result, "custom", body);
    } else {
        const supports_strict = !scope.equal(try scope.get(compat, "supportsStrictMode"), c.pi_js_bool(scope.engine.context, 0));
        const sampling = try scope.get(tool, "constrainedSampling");
        var strict = false;
        var reason = c.pi_js_undefined();
        if (scope.truthy(sampling) and try v.eq(scope, try scope.get(sampling, "type"), "json_schema")) {
            if (supports_strict) {
                _ = makeStrict(scope, try scope.get(tool, "parameters"), &reason) catch |err| {
                    if (err != error.UnsupportedStrictJsonSchema) return err;
                    if (try v.eq(scope, try scope.get(sampling, "strict"), "require")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" requires JSON-schema constrained sampling, but ")), try scope.concat(reason, try scope.text("."))));
                    reason = c.pi_js_undefined();
                    return convertFunction(scope, tool, result, body, supports_strict, false);
                };
                strict = true;
            } else if (try v.eq(scope, try scope.get(sampling, "strict"), "require")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" requires JSON-schema constrained sampling, but strict tools are unsupported.")));
        }
        return convertFunction(scope, tool, result, body, supports_strict, strict);
    }
    return c.JS_DupValue(scope.engine.context, result);
}
fn convertFunction(scope: *Scope, tool: c.JSValue, result: c.JSValue, body: c.JSValue, supported: bool, strict: bool) !c.JSValue {
    try scope.put(result, "type", try scope.text("function"));
    try scope.put(body, "name", try scope.get(tool, "name"));
    try scope.put(body, "description", try scope.get(tool, "description"));
    var reason = c.pi_js_undefined();
    try scope.put(body, "parameters", if (strict) try makeStrict(scope, try scope.get(tool, "parameters"), &reason) else try scope.get(tool, "parameters"));
    if (supported) try scope.put(body, "strict", c.pi_js_bool(scope.engine.context, @intFromBool(strict)));
    try scope.put(result, "function", body);
    return c.JS_DupValue(scope.engine.context, result);
}
