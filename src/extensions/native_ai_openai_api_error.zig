//! Pinned OpenAI6.40 functional API-error fields and message policy.
//! Private native values; does not claim a JavaScript SDK constructor identity.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn response(scope: *Scope, status: c.JSValue, body: c.JSValue, headers: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const parsed = scope.invoke(try scope.global("JSON"), "parse", &.{body}) catch |err| parsed: {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        break :parsed c.pi_js_undefined();
    };
    const error_body = try v.optional(scope, parsed, "error");
    var message = try v.optional(scope, error_body, "message");
    if (scope.truthy(message)) {
        if (!c.JS_IsString(try scope.get(error_body, "message"))) message = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(error_body, "message")}) else message = try scope.get(error_body, "message");
    } else if (scope.truthy(error_body)) message = try scope.invoke(try scope.global("JSON"), "stringify", &.{error_body}) else message = body;
    if (scope.truthy(status) and scope.truthy(message)) message = try scope.concat(try scope.concat(try scope.stringify(status), try scope.text(" ")), try scope.stringify(message)) else if (scope.truthy(status)) message = try scope.concat(try scope.stringify(status), try scope.text(" status code (no body)")) else if (!scope.truthy(message)) message = try scope.text("(no status code or body)");
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{message}));
    try scope.put(result, "status", status);
    try scope.put(result, "headers", headers);
    try scope.put(result, "requestID", if (v.nullish(headers)) c.pi_js_undefined() else try scope.invoke(headers, "get", &.{try scope.text("x-request-id")}));
    try scope.put(result, "error", error_body);
    inline for (.{ "code", "param", "type" }) |key| try scope.put(result, key, try v.optional(scope, error_body, key));
    return result;
}
pub const Connection = enum { failed, timeout, aborted };
pub fn connection(scope: *Scope, kind: Connection, cause: c.JSValue) !c.JSValue {
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text(switch (kind) {
        .failed => "Connection error.",
        .timeout => "Request timed out.",
        .aborted => "Request was aborted.",
    })}));
    inline for (.{ "status", "headers", "requestID", "error", "code", "param", "type" }) |key| try scope.put(result, key, c.pi_js_undefined());
    if (kind == .failed and scope.truthy(cause)) try scope.put(result, "cause", cause);
    return result;
}
