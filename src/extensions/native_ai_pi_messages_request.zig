//! Literal pi-messages request and structured HTTP failure values.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn build(scope: *Scope, model: c.JSValue, context: c.JSValue, options: c.JSValue, env: c.JSValue) !c.JSValue {
    const payload = try scope.object();
    try scope.put(payload, "model", try scope.get(model, "id"));
    try scope.put(payload, "context", context);
    const fields = try scope.object();
    inline for (.{ "temperature", "maxTokens", "reasoning" }) |key| try scope.put(fields, key, try v.optional(scope, options, key));
    var retention = try v.optional(scope, options, "cacheRetention");
    if (!scope.truthy(retention)) {
        const legacy = try scope.call(env, c.pi_js_undefined(), &.{ try scope.text("PI_CACHE_RETENTION"), try v.optional(scope, options, "env") });
        retention = if (try v.eq(scope, legacy, "long")) try scope.text("long") else c.pi_js_undefined();
    }
    try scope.put(fields, "cacheRetention", retention);
    inline for (.{ "sessionId", "toolChoice" }) |key| try scope.put(fields, key, try v.optional(scope, options, key));
    try scope.put(payload, "options", fields);
    return payload;
}
pub fn headers(scope: *Scope, options: c.JSValue, api_key: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "authorization", try scope.concat(try scope.text("Bearer "), try scope.stringify(api_key)));
    try scope.put(result, "accept", try scope.text("text/event-stream"));
    try scope.put(result, "content-type", try scope.text("application/json"));
    const source = try v.optional(scope, options, "headers");
    if (!v.nullish(source)) {
        // providerHeadersToRecord normalizes only for deduplication; the final
        // spread retains the winning source spelling and explicit undefined.
        const map = try scope.own(try v.js.builtin(scope.engine, "Map", &.{}));
        var entries = try v.iterator(scope, try scope.invoke(try scope.global("Object"), "entries", &.{source}));
        defer entries.deinit();
        errdefer entries.closePreserving();
        while (try entries.next()) |entry| {
            defer scope.engine.freeValue(entry);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const name = try v.at(&row, entry, 0);
            const value = try v.at(&row, entry, 1);
            const key = try row.invoke(name, "toLowerCase", &.{});
            _ = try row.invoke(map, "delete", &.{key});
            if (!c.JS_IsNull(value)) _ = try row.invoke(map, "set", &.{ key, entry });
        }
        const normalized = try scope.invoke(try scope.global("Object"), "fromEntries", &.{try scope.invoke(map, "values", &.{})});
        try v.js.spreadInto(scope.engine, result, normalized);
    }
    return result;
}
pub fn responseError(scope: *Scope, model: c.JSValue, url: c.JSValue, response: c.JSValue, body: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{body}) catch |err| parsed: {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        break :parsed c.pi_js_undefined();
    };
    const nested = try v.optional(scope, parsed, "error");
    const valid = c.JS_IsObject(nested) and !c.JS_IsFunction(scope.engine.context, nested) and !try v.array(scope, nested);
    const error_body = if (valid) nested else c.pi_js_undefined();
    const raw_message = try v.optional(scope, error_body, "message");
    const raw_code = try v.optional(scope, error_body, "code");
    const code = if (c.JS_IsString(raw_code)) raw_code else c.pi_js_undefined();
    const suffix = if (c.JS_IsString(raw_message)) raw_message else body;
    const status = try scope.get(response, "status");
    const status_text = try scope.get(response, "statusText");
    var text = try scope.concat(try scope.concat(try scope.stringify(status), try scope.text(" ")), try scope.stringify(status_text));
    text = try scope.concat(try scope.concat(text, try scope.text(": ")), try scope.stringify(suffix));
    if (scope.truthy(code)) text = try scope.concat(try scope.concat(try scope.concat(text, try scope.text(" (")), try scope.stringify(code)), try scope.text(")"));
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{text}));
    try scope.set(result, "name", try scope.text("PiMessagesResponseError"));
    try scope.set(result, "code", code);
    const details = try scope.object();
    try scope.put(details, "version", c.JS_NewInt32(scope.engine.context, 1));
    try scope.put(details, "provider", try scope.get(model, "provider"));
    try scope.put(details, "model", try scope.get(model, "id"));
    try scope.put(details, "url", try scope.invoke(url, "toString", &.{}));
    try scope.put(details, "status", status);
    try scope.put(details, "statusText", status_text);
    if (valid) try scope.put(details, "error", error_body) else {
        const truncated = if (try v.length(scope, body) > 8192) try scope.concat(try scope.invoke(body, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 8192) }), try scope.text("…")) else body;
        try scope.put(details, "body", truncated);
    }
    try scope.put(details, "timestampMs", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(result, "diagnosticDetails", details);
    return result;
}
