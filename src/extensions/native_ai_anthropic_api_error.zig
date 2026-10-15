//! Pinned Anthropic SDK error-class bodies, implemented through direct QuickJS C.
//! The actual class chain supplies the brand used by strict-tool fallback.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const Kind = enum { base, api, abort, connection, timeout, inherited };
fn construct(comptime kind: Kind) @import("native_class.zig").Construct {
    const Adapter = struct {
        fn call(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            var scope: Scope = .{ .engine = engine };
            defer scope.deinit();
            if (kind == .base) return engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, @intCast(args.len), @constCast(args.ptr)));
            var status = arg(args, 0);
            var body = arg(args, 1);
            var message = arg(args, 2);
            var headers = arg(args, 3);
            var error_type = arg(args, 4);
            var cause = c.pi_js_undefined();
            if (kind == .abort or kind == .connection or kind == .timeout) {
                const options = if (kind != .connection and (args.len == 0 or c.JS_IsUndefined(args[0]))) try scope.object() else arg(args, 0);
                message = try scope.get(options, "message");
                cause = if (kind == .connection) try scope.get(options, "cause") else c.pi_js_undefined();
                if (kind == .timeout) {
                    if (v.nullish(message)) message = try scope.text("Request timed out.");
                    // The timeout subclass delegates through the connection
                    // constructor, whose fallback uses || rather than ??.
                    if (!scope.truthy(message)) message = try scope.text("Connection error.");
                } else if (!scope.truthy(message)) message = try scope.text(if (kind == .abort) "Request was aborted." else "Connection error.");
                status = c.pi_js_undefined();
                body = c.pi_js_undefined();
                headers = c.pi_js_undefined();
                error_type = c.pi_js_undefined();
            }
            const text = try scope.invoke(try scope.get(roots[1], "api"), "makeMessage", &.{ status, body, message });
            var error_args = [_]c.JSValue{try scope.stringify(text)};
            const result = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, 1, &error_args)));
            try scope.set(result, "status", status);
            try scope.set(result, "headers", headers);
            try scope.set(result, "requestID", if (v.nullish(headers)) c.pi_js_undefined() else try scope.invoke(headers, "get", &.{try scope.text("request-id")}));
            try scope.set(result, "workspaceID", if (v.nullish(headers)) c.pi_js_undefined() else try scope.invoke(headers, "get", &.{try scope.text("anthropic-workspace-id")}));
            try scope.set(result, "error", body);
            try scope.set(result, "type", if (v.nullish(error_type)) c.pi_js_null() else error_type);
            if (scope.truthy(cause)) try scope.set(result, "cause", cause);
            return c.JS_DupValue(engine.context, result);
        }
    };
    return Adapter.call;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
pub fn makeMessage(scope: *Scope, status: c.JSValue, body: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const description = try v.optional(scope, body, "message");
    var message = if (scope.truthy(description)) if (c.JS_IsString(try scope.get(body, "message"))) try scope.get(body, "message") else try scope.invoke(try scope.global("JSON"), "stringify", &.{try scope.get(body, "message")}) else if (scope.truthy(body)) try scope.invoke(try scope.global("JSON"), "stringify", &.{body}) else fallback;
    if (scope.truthy(status) and scope.truthy(message)) return scope.concat(try scope.concat(try scope.stringify(status), try scope.text(" ")), try scope.stringify(message));
    if (scope.truthy(status)) return scope.concat(try scope.stringify(status), try scope.text(" status code (no body)"));
    if (scope.truthy(message)) return message;
    message = try scope.text("(no status code or body)");
    return message;
}
fn add(scope: *Scope, namespace: c.JSValue, name: [:0]const u8, length: u8, parent: c.JSValue, error_root: c.JSValue, box: c.JSValue, comptime kind: Kind) !c.JSValue {
    const prototype = try scope.own(try scope.engine.checked(c.JS_NewObjectProto(scope.engine.context, try scope.get(parent, "prototype"))));
    const constructor = try scope.own(try @import("native_class.zig").constructor(scope.engine, name, length, prototype, construct(kind), &.{ error_root, box }));
    if (c.JS_SetPrototype(scope.engine.context, constructor, parent) < 0) return v.js.capture(scope.engine);
    try scope.put(namespace, name.ptr, constructor);
    return constructor;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const cache_key = "pi-internal/anthropic-sdk-errors";
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const box = try scope.object();
    const error_constructor = try scope.global("Error");
    const base = try add(&scope, result, "AnthropicError", 0, error_constructor, error_constructor, box, .base);
    const api = try add(&scope, result, "APIError", 5, base, error_constructor, box, .api);
    try scope.put(box, "api", api);
    _ = try add(&scope, result, "APIUserAbortError", 0, api, error_constructor, box, .abort);
    const connection = try add(&scope, result, "APIConnectionError", 1, api, error_constructor, box, .connection);
    _ = try add(&scope, result, "APIConnectionTimeoutError", 0, connection, error_constructor, box, .timeout);
    inline for (.{ "BadRequestError", "AuthenticationError", "PermissionDeniedError", "NotFoundError", "ConflictError", "UnprocessableEntityError", "RateLimitError", "InternalServerError" }) |name| _ = try add(&scope, result, name, 0, api, error_constructor, box, .inherited);
    const Static = struct {
        fn message(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            return c.JS_DupValue(host.context, try makeMessage(&row, arg(args, 0), arg(args, 1), arg(args, 2)));
        }
        fn generate(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var row: Scope = .{ .engine = host };
            defer row.deinit();
            return c.JS_DupValue(host.context, try generateValue(&row, roots[0], arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3)));
        }
    };
    const make_message = try scope.own(try @import("native_node_function.zig").createArrow(engine, "makeMessage", 3, Static.message, &.{}));
    const generate = try scope.own(try @import("native_node_function.zig").createArrow(engine, "generate", 4, Static.generate, &.{result}));
    if (c.JS_DefinePropertyValueStr(engine.context, api, "makeMessage", c.JS_DupValue(engine.context, make_message), (c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE)) < 0 or c.JS_DefinePropertyValueStr(engine.context, api, "generate", c.JS_DupValue(engine.context, generate), (c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE)) < 0) return v.js.capture(engine);
    const cached = c.JS_DupValue(engine.context, result);
    engine.native_module_values.put(engine.gpa, cache_key, cached) catch |err| {
        engine.freeValue(cached);
        return err;
    };
    return c.JS_DupValue(engine.context, result);
}
pub fn generateValue(scope: *Scope, namespace: c.JSValue, status: c.JSValue, body: c.JSValue, message: c.JSValue, headers: c.JSValue) !c.JSValue {
    if (!scope.truthy(status) or !scope.truthy(headers)) {
        const options = try scope.object();
        try scope.put(options, "message", message);
        try scope.put(options, "cause", try castToError(scope, body));
        const constructor = try scope.get(namespace, "APIConnectionError");
        var args = [_]c.JSValue{options};
        return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, &args)));
    }
    var name: [*:0]const u8 = "APIError";
    inline for (.{ .{ 400, "BadRequestError" }, .{ 401, "AuthenticationError" }, .{ 403, "PermissionDeniedError" }, .{ 404, "NotFoundError" }, .{ 409, "ConflictError" }, .{ 422, "UnprocessableEntityError" }, .{ 429, "RateLimitError" } }) |pair| if (scope.equal(status, c.JS_NewInt32(scope.engine.context, pair[0]))) {
        name = pair[1];
    };
    if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater_equal, status, c.JS_NewInt32(scope.engine.context, 500))) name = "InternalServerError";
    const constructor = try scope.get(namespace, name);
    var args = [_]c.JSValue{ status, body, message, headers, try v.optional(scope, try v.optional(scope, body, "error"), "type") };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
}
fn crossRealm(scope: *Scope, value: c.JSValue) !c.JSValue {
    const prototype = try scope.get(try scope.global("Object"), "prototype");
    const tag = try scope.call(try scope.get(prototype, "toString"), value, &.{});
    if (!try v.eq(scope, tag, "[object Error]") and !try v.eq(scope, tag, "[object DOMException]")) return c.pi_js_undefined();
    const cause = try scope.get(value, "cause");
    const options = try scope.object();
    if (scope.truthy(cause)) try scope.put(options, "cause", cause);
    const result = try scope.own(try v.js.builtin(scope.engine, "Error", &.{ try scope.get(value, "message"), options }));
    if (scope.truthy(try scope.get(value, "stack"))) try scope.set(result, "stack", try scope.get(value, "stack"));
    if (scope.truthy(try scope.get(value, "cause")) and !scope.truthy(try scope.get(result, "cause"))) try scope.set(result, "cause", try scope.get(value, "cause"));
    if (scope.truthy(try scope.get(value, "name"))) try scope.set(result, "name", try scope.get(value, "name"));
    return result;
}
fn castToError(scope: *Scope, value: c.JSValue) !c.JSValue {
    const branded = c.JS_IsInstanceOf(scope.engine.context, value, try scope.global("Error"));
    if (branded < 0) return v.js.capture(scope.engine);
    if (branded == 1) return value;
    if (c.JS_IsObject(value) and !c.JS_IsFunction(scope.engine.context, value)) {
        const generation = scope.engine.native_allocation_generation;
        const converted = crossRealm(scope, value) catch |err| suppressed: {
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            break :suppressed c.pi_js_undefined();
        };
        if (!c.JS_IsUndefined(converted)) return converted;
        var serialized_ok = true;
        const serialized = scope.invoke(try scope.global("JSON"), "stringify", &.{value}) catch |err| suppressed: {
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            serialized_ok = false;
            break :suppressed c.pi_js_undefined();
        };
        if (serialized_ok) return scope.own(try v.js.builtin(scope.engine, "Error", &.{serialized}));
    }
    return scope.own(try v.js.builtin(scope.engine, "Error", &.{value}));
}
