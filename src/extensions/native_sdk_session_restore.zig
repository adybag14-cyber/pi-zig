//! Latest AgentSession transcript tool restoration, preserving live calls.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.JS_NewCFunction(engine.context, dispatch, "_restoreToolsFromTranscript", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_restoreToolsFromTranscript", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return restore(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn allowed(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.invoke(engine, roots[0], "_isAllowedTool", &.{if (argc > 0) argv[0] else c.pi_js_undefined()}) catch |err| sdk.fail(engine, err);
}
fn name(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "name") catch |err| sdk.fail(engine, err);
}
pub fn restore(engine: *em.Engine, session: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const modifiers = if (c.JS_IsUndefined(supplied)) try scope.array() else supplied;
    _ = try scope.invoke(try scope.get(session, "_pendingToolNames"), "clear", &.{});
    const context = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionContext", &.{});
    const current = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(engine, try scope.get(context, "messages")));
    if (!scope.truthy(current)) return c.pi_js_undefined();
    const tools = try scope.get(current, "toolsAdded");
    const base = try scope.invoke(if (c.JS_IsNull(tools) or c.JS_IsUndefined(tools)) try scope.array() else tools, "map", &.{try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, name, "", 1)))});
    const names = try scope.own(try @import("native_sdk_tool_modifiers.zig").apply(engine, base, modifiers));
    const set_constructor = try scope.global("Set");
    const filter = try scope.get(names, "filter");
    var roots = [_]c.JSValue{session};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, allowed, "", 1, 0, roots.len, &roots)));
    var args = [_]c.JSValue{try scope.call(filter, names, &.{callback})};
    const pending = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, args.len, &args)));
    try scope.set(session, "_pendingToolNames", pending);
    _ = try scope.invoke(session, "_setActiveTools", &.{names});
    return c.pi_js_undefined();
}
