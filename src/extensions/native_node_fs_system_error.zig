//! Source-specific ERR_SYSTEM_ERROR used by WriteStream's exhausted retries.
//! The context is the actual supplied string, including its live inherited
//! properties. General internal/errors stack/inspection parity is not claimed.
const em = @import("engine.zig"); const c = em.c;
const std = @import("std");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const fnc = @import("native_node_function.zig");
const class = @import("native_class.zig");
const core = @import("native_node_stream.zig");
const cache_key = "pi-native:private/fs-system-error";
fn define(scope: *Scope, value: c.JSValue, name: [*:0]const u8, item: c.JSValue, flags: c_int) !void {
    if (c.JS_DefinePropertyValueStr(scope.engine.context, value, name, c.JS_DupValue(scope.engine.context, item), flags) < 0) return js.capture(scope.engine);
}
fn accessor(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const context = roots[0];
    const name = try engine.toString(roots[1]); defer engine.gpa.free(name); const terminated = try engine.gpa.dupeZ(u8, name); defer engine.gpa.free(terminated);
    if (scope.truthy(roots[2])) {
        var value = core.arg(args, 0);
        if (scope.truthy(roots[3])) {
            if (scope.truthy(value)) {
                const buffer = try scope.get(engine.native_module_values.get("node:buffer").?, "Buffer");
                const from = try scope.get(buffer, "from");
                value = try scope.call(from, buffer, &.{try scope.invoke(value, "toString", &.{})});
            } else value = c.pi_js_undefined();
        }
        try scope.set(context, terminated, value); return c.pi_js_undefined();
    }
    if (scope.truthy(roots[3])) {
        const present = !core.nullish(try scope.get(context, terminated));
        const value = try scope.get(context, terminated);
        return c.JS_DupValue(engine.context, if (present) try scope.invoke(value, "toString", &.{}) else value);
    }
    return c.JS_DupValue(engine.context, try scope.get(context, terminated));
}
fn addAccessor(scope: *Scope, value: c.JSValue, context: c.JSValue, name: [*:0]const u8, path: bool) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name); if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine); defer c.JS_FreeAtom(scope.engine.context, atom);
    const get = try scope.own(try fnc.createMethod(scope.engine, "get", 0, accessor, &.{ context, try scope.text(std.mem.span(name)), c.pi_js_bool(scope.engine.context, 0), c.pi_js_bool(scope.engine.context, @intFromBool(path)) }));
    const set = try scope.own(try fnc.createArrow(scope.engine, "set", 1, accessor, &.{ context, try scope.text(std.mem.span(name)), c.pi_js_bool(scope.engine.context, 1), c.pi_js_bool(scope.engine.context, @intFromBool(path)) }));
    if (c.JS_DefinePropertyGetSet(scope.engine.context, value, atom, c.JS_DupValue(scope.engine.context, get), c.JS_DupValue(scope.engine.context, set), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(scope.engine);
}
fn toString(engine: *em.Engine, receiver: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); var text = try scope.stringify(try scope.get(receiver, "name"));
    text = try scope.concat(text, try scope.text(" [")); text = try scope.concat(text, try scope.stringify(try scope.get(receiver, "code")));
    text = try scope.concat(text, try scope.text("]: ")); text = try scope.concat(text, try scope.stringify(try scope.get(receiver, "message"))); return c.JS_DupValue(engine.context, text);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); const node_error = scope.truthy(roots[2]);
    const key = if (node_error) try scope.text("ERR_SYSTEM_ERROR") else core.arg(args, 0); const context = core.arg(args, if (node_error) 0 else 1);
    if (!scope.equal(key, try scope.text("ERR_SYSTEM_ERROR"))) return error.RequiredOtherSystemErrorMessageRegistration;
    const value = try scope.own(try engine.checked(c.JS_CallConstructor2(engine.context, roots[0], target, 0, null)));
    var message = try scope.concat(try scope.text("A system error occurred: "), try scope.stringify(try scope.get(context, "syscall")));
    message = try scope.concat(message, try scope.text(" returned ")); message = try scope.concat(message, try scope.stringify(try scope.get(context, "code")));
    message = try scope.concat(message, try scope.text(" (")); message = try scope.concat(message, try scope.stringify(try scope.get(context, "message"))); message = try scope.concat(message, try scope.text(")"));
    // Source deliberately reloads path/dest after the undefined test.
    inline for (.{ "path", "dest" }, .{ " ", " => " }) |name, prefix| if (!c.JS_IsUndefined(try scope.get(context, name))) { message = try scope.concat(message, try scope.text(prefix)); message = try scope.concat(message, try scope.stringify(try scope.get(context, name))); };
    try scope.set(value, "code", key);
    const atom = try js.atom(engine, roots[1]); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyValue(engine.context, value, atom, c.pi_js_bool(engine.context, 1), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    try define(&scope, value, "name", try scope.text("SystemError"), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try define(&scope, value, "message", message, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    try define(&scope, value, "info", context, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE);
    try addAccessor(&scope, value, context, "errno", false); try addAccessor(&scope, value, context, "syscall", false);
    inline for (.{ "path", "dest" }) |name| if (!c.JS_IsUndefined(try scope.get(context, name))) try addAccessor(&scope, value, context, name, true);
    return c.JS_DupValue(engine.context, value);
}
fn constructor(scope: *Scope) !c.JSValue {
    return scope.own(try @import("native_node_system_errors.zig").constructor(scope.engine, "ERR_SYSTEM_ERROR"));
}
pub fn retryFailure(scope: *Scope, vector: bool) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(if (vector) "writev failed" else "write failed")};
    return scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try constructor(scope), args.len, &args));
}
/// Genuine ERR_SYSTEM_ERROR over an actual native operation context. Reuse the
/// same existing class/prototype/accessor algorithm, not a label-only Error.
pub fn fromContext(engine: *em.Engine, context: c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var args = [_]c.JSValue{context};
    return engine.checked(c.JS_CallConstructor(engine.context, try constructor(&scope), args.len, &args));
}
pub fn install(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    // Source classes exist at module evaluation. Pin them before the writer
    // can execute hooks; late global Function mutation cannot intercept errors.
    _ = try constructor(&scope);
}
