//! Shared exact Source5ab cache preference and normalized64 tool-call IDs.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
pub fn normalizeId(engine: *v.em.Engine) !c.JSValue {
    const Adapter = struct {
        fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            var scope: Scope = .{ .engine = host };
            defer scope.deinit();
            const regex = try scope.own(try v.js.builtin(host, "RegExp", &.{ try scope.text("[^a-zA-Z0-9_-]"), try scope.text("g") }));
            const sanitized = try scope.invoke(if (args.len > 0) args[0] else c.pi_js_undefined(), "replace", &.{ regex, try scope.text("_") });
            return v.js.invoke(host, sanitized, "slice", &.{ c.JS_NewInt32(host.context, 0), c.JS_NewInt32(host.context, 64) });
        }
    };
    return @import("native_node_function.zig").create(engine, "normalizeToolCallId", 1, Adapter.call, &.{});
}
pub fn retention(scope: *Scope, options: c.JSValue) !c.JSValue {
    const configured = try v.optional(scope, options, "cacheRetention");
    if (scope.truthy(configured)) return configured;
    const environment = try scope.own(try @import("native_ai_env_keys.zig").create(scope.engine, .{}));
    const value = try scope.invoke(environment, "getProviderEnvValue", &.{ try scope.text("PI_CACHE_RETENTION"), try v.optional(scope, options, "env") });
    return scope.text(if (try v.eq(scope, value, "long")) "long" else "short");
}
