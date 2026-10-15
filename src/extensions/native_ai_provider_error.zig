//! Actual shared SDK/provider HTTP error normalization and display formatting.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn string(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global("String"), c.pi_js_undefined(), &.{value});
}
pub fn safeJson(scope: *Scope, value: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const serialized = scope.invoke(try scope.global("JSON"), "stringify", &.{value}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return string(scope, value);
    };
    return if (c.JS_IsUndefined(serialized)) string(scope, value) else serialized;
}
fn plain(scope: *Scope, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) return false;
    const prototype = try scope.invoke(try scope.global("Object"), "getPrototypeOf", &.{value});
    if (!c.JS_IsNull(prototype) and !scope.equal(prototype, try scope.get(try scope.global("Object"), "prototype"))) return false;
    return try v.length(scope, try scope.invoke(try scope.global("Object"), "keys", &.{value})) > 0;
}
fn rawBody(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsString(try scope.get(value, "body"))) return scope.get(value, "body");
    if (try plain(scope, try scope.get(value, "error"))) return safeJson(scope, try scope.get(value, "error"));
    const body = try v.optional(scope, try scope.get(value, "$response"), "body");
    if (c.JS_IsString(body)) return body;
    if (c.JS_IsObject(body) and !c.JS_IsFunction(scope.engine.context, body) and try v.js.hasKey(scope.engine, body, try scope.text("pipe")) and c.JS_IsFunction(scope.engine.context, try scope.get(body, "pipe"))) return c.pi_js_undefined();
    if (try plain(scope, body)) return safeJson(scope, body);
    return c.pi_js_undefined();
}
pub fn normalize(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const instance = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    if (instance == 0) {
        try scope.put(result, "message", try safeJson(scope, value));
        try scope.put(result, "messageCarriesBody", c.pi_js_bool(scope.engine.context, 0));
        return result;
    }
    var status = c.pi_js_undefined();
    inline for (.{ "statusCode", "status" }) |key| {
        if (c.JS_IsUndefined(status) and c.JS_IsNumber(try scope.get(value, key))) status = try scope.get(value, key);
    }
    if (c.JS_IsUndefined(status) and c.JS_IsNumber(try v.optional(scope, try scope.get(value, "$metadata"), "httpStatusCode"))) status = try scope.get(try scope.get(value, "$metadata"), "httpStatusCode");
    if (c.JS_IsUndefined(status) and c.JS_IsNumber(try v.optional(scope, try scope.get(value, "$response"), "statusCode"))) status = try scope.get(try scope.get(value, "$response"), "statusCode");
    const raw = try rawBody(scope, value);
    var body = c.pi_js_undefined();
    if (!c.JS_IsUndefined(raw)) {
        const trimmed = try scope.invoke(raw, "trim", &.{});
        if (try v.length(scope, trimmed) > 0) {
            body = trimmed;
            if (try v.length(scope, trimmed) > 4000) {
                body = try scope.concat(try scope.invoke(trimmed, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 4000) }), try scope.text("... [truncated "));
                const difference = try scope.own(try @import("native_image_arithmetic.zig").binary(scope.engine, .subtract, try scope.get(trimmed, "length"), c.JS_NewInt32(scope.engine.context, 4000)));
                body = try scope.concat(try scope.concat(body, try scope.stringify(difference)), try scope.text(" chars]"));
            }
        }
    }
    const carries = c.JS_IsUndefined(body) or scope.truthy(try scope.invoke(try scope.get(value, "message"), "includes", &.{body}));
    try scope.put(result, "status", status);
    try scope.put(result, "body", body);
    try scope.put(result, "message", try scope.get(value, "message"));
    try scope.put(result, "messageCarriesBody", c.pi_js_bool(scope.engine.context, @intFromBool(carries)));
    return result;
}
pub fn format(scope: *Scope, normalized: c.JSValue, prefix: c.JSValue) !c.JSValue {
    const status = try scope.get(normalized, "status");
    const body = try scope.get(normalized, "body");
    const carries = scope.truthy(try scope.get(normalized, "messageCarriesBody"));
    if (carries or c.JS_IsUndefined(status) or c.JS_IsUndefined(body)) {
        if (!c.JS_IsUndefined(prefix) and !c.JS_IsUndefined(status)) return scope.concat(try scope.concat(try scope.concat(try scope.concat(try scope.stringify(prefix), try scope.text(" (")), try scope.stringify(status)), try scope.text("): ")), try scope.stringify(try scope.get(normalized, "message")));
        return scope.get(normalized, "message");
    }
    const lead = if (!c.JS_IsUndefined(prefix)) try scope.concat(try scope.concat(try scope.concat(try scope.stringify(prefix), try scope.text(" (")), try scope.stringify(status)), try scope.text("): ")) else try scope.concat(try scope.stringify(status), try scope.text(": "));
    return scope.concat(lead, try scope.stringify(body));
}
pub fn message(scope: *Scope, value: c.JSValue) !c.JSValue {
    var text = try format(scope, try normalize(scope, value), c.pi_js_undefined());
    const raw = try v.optional(scope, try v.optional(scope, try v.optional(scope, value, "error"), "metadata"), "raw");
    if (scope.truthy(raw) and !scope.truthy(try scope.invoke(text, "includes", &.{try string(scope, raw)}))) text = try scope.concat(try scope.concat(text, try scope.text("\n")), try scope.stringify(raw));
    return text;
}
