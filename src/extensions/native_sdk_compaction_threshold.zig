//! Actual ordinary threshold method, preserving live receiver access and the
//! imported lexical estimate/policy bindings captured by the session module.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue, dependencies: c.JSValue) !void {
    var roots = [_]c.JSValue{dependencies};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, callback, "_exceedsCompactionThreshold", 2, 0, roots.len, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_exceedsCompactionThreshold", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return exceeds(engine, receiver, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn exceeds(engine: *em.Engine, session: c.JSValue, dependencies: c.JSValue, model: c.JSValue, projection: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const window = try scope.get(model, "contextWindow");
    if (scope.truthy(try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 5, window, c.JS_NewInt32(engine.context, 0)))))) return c.pi_js_bool(engine.context, 0);
    const should_compact = try scope.get(dependencies, "shouldCompact");
    const estimate_context = try scope.get(dependencies, "estimateProjectedContextTokens");
    const branch = try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{});
    const estimate = try scope.call(estimate_context, c.pi_js_undefined(), &.{ projection, branch });
    const tokens = try scope.get(estimate, "tokens");
    const live_window = try scope.get(model, "contextWindow");
    const settings_manager = try scope.get(session, "settingsManager");
    const settings = try scope.invoke(settings_manager, "getCompactionSettings", &.{try scope.get(session, "model")});
    return c.JS_DupValue(engine.context, try scope.call(should_compact, c.pi_js_undefined(), &.{ tokens, live_window, settings }));
}
