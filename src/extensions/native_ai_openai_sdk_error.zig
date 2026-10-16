//! The pinned SDK APIError functional message/field algorithm. Errors are real
//! intrinsic VM Error instances; this helper does not invent a JS SDK brand.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn factory(engine: *v.em.Engine, headers: c.JSValue) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var scope: Scope = .{ .engine = host };
            defer scope.deinit();
            return c.JS_DupValue(host.context, try create(&scope, argument(args, 0), argument(args, 1), argument(args, 2), roots[0]));
        }
    };
    return @import("native_node_function.zig").createArrow(engine, "", 3, Adapter.call, &.{headers});
}
pub fn create(scope: *Scope, status: c.JSValue, body: c.JSValue, fallback: c.JSValue, headers: c.JSValue) !c.JSValue {
    var message = try v.optional(scope, body, "message");
    if (scope.truthy(message)) {
        if (c.JS_IsString(try scope.get(body, "message"))) message = try scope.get(body, "message") else message = try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(body, "message")});
    } else if (scope.truthy(body)) message = try scope.invoke(try scope.global("JSON"), "stringify", &.{body}) else message = fallback;
    if (scope.truthy(status) and scope.truthy(message)) message = try scope.concat(try scope.concat(try scope.stringify(status), try scope.text(" ")), try scope.stringify(message)) else if (scope.truthy(status)) message = try scope.concat(try scope.stringify(status), try scope.text(" status code (no body)")) else if (!scope.truthy(message)) message = try scope.text("(no status code or body)");
    message = try scope.stringify(message);
    const result = try scope.own(try scope.engine.checked(c.JS_NewError(scope.engine.context)));
    if (c.JS_DefinePropertyValueStr(scope.engine.context, result, "message", c.JS_DupValue(scope.engine.context, message), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(scope.engine);
    try scope.put(result, "status", status);
    try scope.put(result, "headers", headers);
    try scope.put(result, "requestID", if (v.nullish(headers)) c.pi_js_undefined() else try scope.invoke(headers, "get", &.{try scope.text("x-request-id")}));
    try scope.put(result, "error", body);
    inline for (.{ "code", "param", "type" }) |key| try scope.put(result, key, try v.optional(scope, body, key));
    return result;
}
