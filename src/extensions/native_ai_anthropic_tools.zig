//! Actual Source5ab Anthropic strict-tool conversion and deferred placeholder.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const strict_schema = @import("native_ai_constrained_sampling.zig");
fn unsupported(scope: *Scope, key: c.JSValue, value: c.JSValue) !bool {
    inline for (.{ "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "maxItems", "uniqueItems", "minContains", "maxContains", "minProperties", "maxProperties" }) |candidate| if (try v.eq(scope, key, candidate)) return true;
    if (try v.eq(scope, key, "minItems")) return !scope.equal(value, c.JS_NewInt32(scope.engine.context, 0)) and !scope.equal(value, c.JS_NewInt32(scope.engine.context, 1));
    if (try v.eq(scope, key, "format")) {
        if (!c.JS_IsString(value)) return true;
        inline for (.{ "date-time", "time", "date", "duration", "email", "hostname", "uri", "ipv4", "ipv6", "uuid" }) |format| if (try v.eq(scope, value, format)) return false;
        return true;
    }
    return false;
}
pub fn converter(engine: *v.em.Engine, oauth: bool, compatibility: c.JSValue, cache: c.JSValue, disabled: bool) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return convert(host, if (args.len > 0) args[0] else c.pi_js_undefined(), c.JS_ToBool(host.context, roots[0]) == 1, roots[1], roots[2], c.JS_ToBool(host.context, roots[3]) == 1);
        }
    };
    return @import("native_node_function.zig").create(engine, "convertToolDefinitions", 1, Adapter.call, &.{ c.pi_js_bool(engine.context, @intFromBool(oauth)), compatibility, cache, c.pi_js_bool(engine.context, @intFromBool(disabled)) });
}
fn strict(scope: *Scope, tool: c.JSValue, supported: bool, disabled: bool) !bool {
    const config = try scope.get(tool, "constrainedSampling");
    if (!scope.truthy(config) or !try v.eq(scope, try scope.get(config, "type"), "json_schema")) return false;
    if (disabled and try v.eq(scope, try scope.get(config, "strict"), "prefer")) return false;
    var reason = try scope.text("strict tools are unsupported");
    if (supported) {
        _ = strict_schema.makeStrict(scope, try scope.get(tool, "parameters"), &reason, unsupported) catch |err| {
            if (err != error.UnsupportedStrictJsonSchema) return err;
            if (!try v.eq(scope, try scope.get(config, "strict"), "require")) return false;
            return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" requires JSON-schema constrained sampling, but ")), reason), try scope.text(".")));
        };
        return true;
    }
    if (try v.eq(scope, try scope.get(config, "strict"), "require")) return v.errorText(scope, try scope.concat(try scope.concat(try scope.concat(try scope.text("Tool \""), try scope.stringify(try scope.get(tool, "name"))), try scope.text("\" requires JSON-schema constrained sampling, but ")), try scope.concat(reason, try scope.text("."))));
    return false;
}
pub fn convert(engine: *v.em.Engine, tools: c.JSValue, oauth: bool, compatibility: c.JSValue, cache: c.JSValue, disabled: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array();
    if (!scope.truthy(tools)) return c.JS_DupValue(engine.context, result);
    const count = try v.length(&scope, tools);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        const tool = try v.at(&row, tools, index);
        const required = try strict(&row, tool, row.truthy(try row.get(compatibility, "supportsStrictTools")), disabled);
        var reason = c.pi_js_undefined();
        const parameters = if (required) try strict_schema.makeStrict(&row, try row.get(tool, "parameters"), &reason, null) else try row.get(tool, "parameters");
        const schema = if (required) try v.spread(&row, parameters) else try row.object();
        try row.put(schema, "type", try row.text("object"));
        const properties = try row.get(parameters, "properties");
        const names = try row.get(parameters, "required");
        try row.put(schema, "properties", if (v.nullish(properties)) try row.object() else properties);
        try row.put(schema, "required", if (v.nullish(names)) try row.array() else names);
        const definition = try row.object();
        const name = try row.get(tool, "name");
        try row.put(definition, "name", if (oauth) try @import("native_ai_anthropic_messages.zig").canonicalName(&row, name) else name);
        try row.put(definition, "description", try row.get(tool, "description"));
        if (row.truthy(try row.get(compatibility, "supportsEagerToolInputStreaming"))) try row.put(definition, "eager_input_streaming", c.pi_js_bool(engine.context, 1));
        if (required) try row.put(definition, "strict", c.pi_js_bool(engine.context, 1));
        try row.put(definition, "input_schema", schema);
        if (!c.JS_IsUndefined(cache) and index + 1 == count) try row.put(definition, "cache_control", cache);
        _ = try row.invoke(result, "push", &.{definition});
    }
    return c.JS_DupValue(engine.context, result);
}
pub fn hasPreferred(scope: *Scope, original: c.JSValue, converted: c.JSValue) !c.JSValue {
    var index: u32 = 0;
    while (index < try v.length(scope, original)) : (index += 1) {
        const definition = try v.at(scope, converted, index);
        const config = try scope.get(try v.at(scope, original, index), "constrainedSampling");
        if (scope.equal(try scope.get(definition, "strict"), c.pi_js_bool(scope.engine.context, 1)) and scope.truthy(config) and try v.eq(scope, try scope.get(config, "type"), "json_schema") and try v.eq(scope, try scope.get(config, "strict"), "prefer")) return c.pi_js_bool(scope.engine.context, 1);
    }
    return c.pi_js_bool(scope.engine.context, 0);
}
pub fn placeholder(scope: *Scope) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "name", try scope.text("__pi_deferred_placeholder__"));
    try scope.put(result, "description", try scope.text("Reserved placeholder. Never available. Never call this."));
    const schema = try scope.object();
    try scope.put(schema, "type", try scope.text("object"));
    try scope.put(schema, "properties", try scope.object());
    try scope.put(schema, "required", try scope.array());
    try scope.put(result, "input_schema", schema);
    try scope.put(result, "defer_loading", c.pi_js_bool(scope.engine.context, 1));
    return result;
}
