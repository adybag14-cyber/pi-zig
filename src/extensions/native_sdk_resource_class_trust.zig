//! Ordinary Source pre-trust bootstrap, retaining real settings and loader refs.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.own(try engine.checked(c.pi_js_function_magic(engine.context, dispatch, "loadProjectTrustExtensions", 0, 0)));
    const parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "loadProjectTrustExtensions", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, loader) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, loader: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, loader);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, loader) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, loader: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    _ = try scope.invoke(try scope.get(loader, "settingsManager"), "setProjectTrusted", &.{c.pi_js_bool(engine.context, 0)});
    const settings = try scope.get(loader, "settingsManager");
    try flow.wait(reloaded, engine, owner, try scope.invoke(settings, "reload", &.{}), 0);
}
fn reloaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const loader = try scope.get(owner, "agent");
    const load = try scope.get(loader, "loadCurrentExtensionSet");
    const options = try scope.object();
    try scope.put(options, "includeInlineFactories", c.pi_js_bool(engine.context, 1));
    try flow.settle(engine, owner, false, try scope.call(load, loader, &.{options}));
}
