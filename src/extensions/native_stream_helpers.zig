//! Small native stream intrinsics, independent of Env readers/RPC/filesystems.
const js = @import("native_js_values.zig");
pub const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
pub fn optional(scope: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (nullish(object)) c.pi_js_undefined() else scope.get(object, key);
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn throw(scope: *Scope, reason: c.JSValue) anyerror {
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
pub fn resolved(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_durable.zig").resolvedPromise(scope.engine, value));
}
