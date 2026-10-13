//! Shared native continuations for the Source RemoteExecutionEnv and retained readers.
const js = @import("native_js_values.zig");
pub const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
pub const errors = @import("native_env_list_files.zig");
pub const values = @import("native_env_values.zig");
pub const path = @import("native_env_remote_path.zig");
pub const c = js.c;
pub fn nullish(value: c.JSValue) bool {
    return c.JS_IsNull(value) or c.JS_IsUndefined(value);
}
pub fn optional(scope: *Scope, object: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (nullish(object)) c.pi_js_undefined() else scope.get(object, key);
}
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
pub fn wait(comptime callback: *const fn (*js.Engine, c.JSValue, c.JSValue, bool, c_int) anyerror!c.JSValue, scope: *Scope, captures: c.JSValue, pending: c.JSValue, stage: anytype) !c.JSValue {
    var promises = try errors.intrinsics(scope, captures);
    return scope.own(try awaiting.continueWith(callback, scope.engine, &promises, captures, pending, @intFromEnum(stage)));
}
pub fn throw(scope: *Scope, reason: c.JSValue) anyerror {
    _ = c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, reason));
    return js.capture(scope.engine);
}
pub fn fieldError(scope: *Scope, captures: c.JSValue, code: []const u8, message: []const u8) !c.JSValue {
    return errors.errorResult(scope, captures, try scope.text(code), try scope.text(message), try scope.get(captures, "path"), c.pi_js_undefined());
}
pub fn rejected(scope: *Scope, err: anyerror) !c.JSValue {
    return scope.own(try scope.engine.checked(@import("native_durable.zig").rejectedPromise(scope.engine, err)));
}
pub fn resolved(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.own(try @import("native_durable.zig").resolvedPromise(scope.engine, value));
}
pub fn request(scope: *Scope, receiver: c.JSValue, op: []const u8, json: c.JSValue, options: ?c.JSValue) !c.JSValue {
    const connection = try scope.get(receiver, "connection");
    return if (options) |given| scope.invoke(connection, "request", &.{ try scope.text(op), json, given }) else scope.invoke(connection, "request", &.{ try scope.text(op), json });
}
pub fn handle(scope: *Scope, bindings: c.JSValue, receiver: c.JSValue, reply: c.JSValue, resolved_path: c.JSValue) !c.JSValue {
    const args = [_]c.JSValue{ receiver, try scope.get(try scope.get(reply, "json"), "handle"), try scope.get(reply, "session"), resolved_path };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.get(bindings, "Handle"), args.len, @constCast(&args))));
}
pub fn handleRequest(scope: *Scope, retained: c.JSValue, op: []const u8, json: ?c.JSValue, options: ?c.JSValue) !c.JSValue {
    return scope.invoke(retained, "request", &.{ try scope.text(op), json orelse c.pi_js_undefined(), options orelse c.pi_js_undefined() });
}
pub fn fileInfo(scope: *Scope, captures: c.JSValue, remote: c.JSValue, paths: c.JSValue) !c.JSValue {
    const resolved_path = try scope.get(captures, "path");
    if (scope.equal(try scope.get(remote, "kind"), try scope.text("other"))) return fieldError(scope, captures, "invalid", "Unsupported file type");
    const result = try scope.object();
    try scope.put(result, "name", try scope.invoke(paths, "basename", &.{resolved_path}));
    try scope.put(result, "path", resolved_path);
    try scope.put(result, "kind", try scope.get(remote, "kind"));
    try scope.put(result, "size", try scope.get(remote, "size"));
    const seconds = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 2, try scope.get(remote, "mtimeSec"), c.JS_NewInt32(scope.engine.context, 1000))));
    const nanos = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 3, try scope.get(remote, "mtimeNsec"), c.JS_NewInt32(scope.engine.context, 1_000_000))));
    try scope.put(result, "mtimeMs", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 0, seconds, nanos))));
    return values.result(scope, true, result);
}
pub fn validInteger(scope: *Scope, value: c.JSValue, positive: bool) !bool {
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isSafeInteger", &.{value}))) return false;
    const threshold = c.JS_NewInt32(scope.engine.context, if (positive) 1 else 0);
    return !scope.truthy(try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 4, value, threshold))));
}
pub fn signalOptions(scope: *Scope, captures: c.JSValue) !c.JSValue {
    const options = try scope.object();
    const context = try scope.get(captures, "context");
    if (scope.truthy(try scope.get(context, "abortSignal"))) try scope.put(options, "signal", try scope.get(context, "abortSignal"));
    return options;
}
