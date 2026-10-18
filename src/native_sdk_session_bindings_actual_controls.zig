//! Parameterized genuine-session control. Root supplies the qualified real
//! factory namespace/options/bindings; no substitute constructor or transport.
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_session_bindings_values.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const c = em.c;
pub fn createAndBind(engine: *em.Engine, factory: c.JSValue, options: c.JSValue, bindings: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    const result = owned.finishValue(&scope, run(&scope, factory, options, bindings));
    return engine.checked(engine.leaveNativeInvocation(&invocation, if (result) |value| value else |err| @import("extensions/native_sdk.zig").fail(engine, err)));
}
fn run(scope: *Scope, factory: c.JSValue, options: c.JSValue, bindings: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const create = try scope.get(factory, "createAgentSession");
    const pending = try scope.call(create, c.pi_js_undefined(), &.{options});
    const result = try scope.own(try engine.awaitValue(pending));
    const session = try scope.get(result, "session");
    const constructor = try scope.get(factory, "AgentSession");
    const generation = engine.native_allocation_generation;
    const instance = c.JS_IsInstanceOf(engine.context, session, constructor);
    try scope.status(if (instance < 0) -1 else 0, generation);
    if (instance == 0 or (engine.native_sdk_class != 0 and c.JS_GetOpaque(session, engine.native_sdk_class) != null)) return error.GenuineSessionRequired;
    const function = try scope.get(session, "bindExtensions");
    if (!c.JS_IsAsyncFunction(function)) return error.GenuineSessionBindingAsyncFunctionRequired;
    _ = try scope.own(try engine.awaitValue(try scope.call(function, session, &.{bindings})));
    return c.JS_DupValue(engine.context, result);
}
