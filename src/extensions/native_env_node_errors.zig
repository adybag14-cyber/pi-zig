//! NodeExecutionEnv error identity, Node errno fields and FileError mapping.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const c = js.c;
fn instance(scope: *Scope, value: c.JSValue, constructor: c.JSValue) !bool {
    const answer = c.JS_IsInstanceOf(scope.engine.context, value, constructor);
    if (answer < 0) return js.capture(scope.engine);
    return answer != 0;
}
pub fn fileError(scope: *Scope, bindings: c.JSValue, failure: c.JSValue, fallback: c.JSValue) !c.JSValue {
    const constructor = try scope.get(bindings, "FileError");
    if (try instance(scope, failure, constructor)) return failure;
    const cause = try scope.call(try scope.get(bindings, "toError"), c.pi_js_undefined(), &.{failure});
    const base = try scope.global("Error");
    var node = false;
    if (try instance(scope, failure, base)) {
        const atom = c.JS_NewAtom(scope.engine.context, "code");
        defer c.JS_FreeAtom(scope.engine.context, atom);
        const has = c.JS_HasProperty(scope.engine.context, failure, atom);
        if (has < 0) return js.capture(scope.engine);
        node = has != 0;
    }
    const path = if (node and c.JS_IsString(try scope.get(failure, "path"))) try scope.get(failure, "path") else fallback;
    var code: []const u8 = "unknown";
    if (node) {
        const raw = try scope.get(failure, "code");
        inline for (.{ .{ "ABORT_ERR", "aborted" }, .{ "ENOENT", "not_found" }, .{ "EACCES", "permission_denied" }, .{ "EPERM", "permission_denied" }, .{ "ENOTDIR", "not_directory" }, .{ "EISDIR", "is_directory" }, .{ "EINVAL", "invalid" } }) |mapping| if (scope.equal(raw, try scope.text(mapping[0]))) {
            code = mapping[1];
        };
    }
    const args = [_]c.JSValue{ try scope.text(code), try scope.get(if (node) failure else cause, "message"), path, cause };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
}
pub fn failed(scope: *Scope, bindings: c.JSValue, reason: c.JSValue, fallback: c.JSValue) !c.JSValue {
    return h.values.result(scope, false, try fileError(scope, bindings, reason, fallback));
}
pub fn expected(scope: *Scope, bindings: c.JSValue, code: []const u8, message: []const u8, path: c.JSValue) !c.JSValue {
    const args = [_]c.JSValue{ try scope.text(code), try scope.text(message), path };
    const constructor = try scope.get(bindings, "FileError");
    const error_value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
    return h.values.result(scope, false, error_value);
}
pub fn aborted(scope: *Scope, bindings: c.JSValue, context: c.JSValue, path: c.JSValue) !?c.JSValue {
    const signal = try scope.get(context, "abortSignal");
    if (!h.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return try expected(scope, bindings, "aborted", "aborted", path);
    return null;
}
pub const SystemFailure = struct { code: []const u8, description: []const u8, errno: i32, syscall: []const u8, path: ?[]const u8 = null, destination: ?[]const u8 = null };
pub fn systemError(scope: *Scope, fields: SystemFailure) !c.JSValue {
    const engine = scope.engine;
    const beginning = try scope.concat(try scope.concat(try scope.text(fields.code), try scope.text(": ")), try scope.text(fields.description));
    var message = try scope.concat(try scope.concat(beginning, try scope.text(", ")), try scope.text(fields.syscall));
    if (fields.path) |path| message = try scope.concat(try scope.concat(try scope.concat(message, try scope.text(" '")), try scope.text(path)), try scope.text("'"));
    if (fields.destination) |destination| message = try scope.concat(try scope.concat(try scope.concat(message, try scope.text(" -> '")), try scope.text(destination)), try scope.text("'"));
    const value = try scope.own(try engine.checked(c.JS_NewError(engine.context)));
    if (c.JS_DefinePropertyValueStr(engine.context, value, "message", c.JS_DupValue(engine.context, message), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try scope.put(value, "errno", c.JS_NewInt32(engine.context, fields.errno));
    try scope.put(value, "code", try scope.text(fields.code));
    try scope.put(value, "syscall", try scope.text(fields.syscall));
    if (fields.path) |path| try scope.put(value, "path", try scope.text(path));
    if (fields.destination) |destination| try scope.put(value, "dest", try scope.text(destination));
    return value;
}
