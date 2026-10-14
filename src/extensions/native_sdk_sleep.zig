//! Coding-agent sleep: actual global Promise/timer/signal calls and roots.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
pub fn sleep(engine: *em.Engine, milliseconds: c.JSValue, signal: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const constructor = try scope.global("Promise");
    var roots = [_]c.JSValue{ milliseconds, signal };
    const executor = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "", 2, 0, roots.len, &roots)));
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, @constCast(&[_]c.JSValue{executor})));
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    initialize(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn aborted(scope: *Scope, reject: c.JSValue) !void {
    const constructor = try scope.global("Error");
    const message = try scope.text("Aborted");
    const reason = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 1, @constCast(&[_]c.JSValue{message}))));
    _ = try scope.call(reject, c.pi_js_undefined(), &.{reason});
}
fn initialize(engine: *em.Engine, milliseconds: c.JSValue, signal: c.JSValue, resolve: c.JSValue, reject: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!temp.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) return aborted(&scope, reject);
    const timeout = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ resolve, milliseconds });
    if (!temp.nullish(signal)) {
        const add_listener = try scope.get(signal, "addEventListener");
        var roots = [_]c.JSValue{ timeout, reject };
        const listener = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, cancel, "", 0, 0, roots.len, &roots)));
        _ = try scope.call(add_listener, signal, &.{ try scope.text("abort"), listener });
    }
}
fn cancel(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    onCancel(engine, roots[0], roots[1]) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn onCancel(engine: *em.Engine, timeout: c.JSValue, reject: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timeout});
    try aborted(&scope, reject);
}
