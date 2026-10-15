//! Ordinary AgentSession.setActiveToolsByName over live registry/loadout APIs.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, dispatch, "setActiveToolsByName", 1));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "setActiveToolsByName", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return set(engine, session, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn removed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const found = scope.invoke(roots[0], "has", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(found)));
}
fn set(engine: *em.Engine, session: c.JSValue, tool_names: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const previous = try scope.invoke(session, "getActiveToolNames", &.{});
    _ = try scope.invoke(session, "_setActiveTools", &.{tool_names});
    // Constructor evaluation precedes the current names call. Source does not
    // copy the previous collection or consult pending tools before this point.
    const constructor = try scope.global("Set");
    var args = [_]c.JSValue{try scope.invoke(session, "getActiveToolNames", &.{})};
    const active = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args)));
    const some = try scope.get(previous, "some");
    var roots = [_]c.JSValue{active};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, removed, "", 1, 0, roots.len, &roots)));
    if (scope.truthy(try scope.call(some, previous, &.{callback}))) _ = try scope.invoke(try scope.get(session, "_pendingToolNames"), "clear", &.{});
    return c.pi_js_undefined();
}
