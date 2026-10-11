//! Actual session-owned command action state and callback receiver.
//! This narrow runner value does not implement the full ExtensionRunner class.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
pub const Action = enum(c_int) { waitForIdle, newSession, fork, navigateTree, switchSession, reload };
fn slot(action: Action) [*:0]const u8 {
    return switch (action) {
        .waitForIdle => "waitForIdleFn",
        .newSession => "newSessionHandler",
        .fork => "forkHandler",
        .navigateTree => "navigateTreeHandler",
        .switchSession => "switchSessionHandler",
        .reload => "reloadHandler",
    };
}
pub fn initialize(owner: *sdk.State, session: c.JSValue) !void {
    const engine = owner.engine;
    const runner = try sdk.object(engine);
    defer engine.freeValue(runner);
    inline for (@import("std").meta.fields(Action)) |field| {
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, defaultAction, "", 0, field.value, 0, null));
        try sdk.put(engine, runner, slot(@enumFromInt(field.value)), callback);
    }
    try sdk.put(engine, owner.data, "_sdkCommandRunner", c.JS_DupValue(engine.context, runner));
    try sdk.put(engine, session, "_extensionRunner", c.JS_DupValue(engine.context, runner));
}
pub fn bind(owner: *sdk.State) !void {
    const engine = owner.engine;
    const runner = try sdk.get(engine, owner.data, "_sdkCommandRunner");
    defer engine.freeValue(runner);
    const actions = try sdk.get(engine, owner.data, "extension_commandContextActions");
    defer engine.freeValue(actions);
    if (c.JS_ToBool(engine.context, actions) != 1) return;
    // Source binds each getter once in this order. Rebinding with no new
    // actions reuses the saved object and observes its getters again.
    inline for (@import("std").meta.fields(Action)) |field| try sdk.put(engine, runner, slot(@enumFromInt(field.value)), try sdk.get(engine, actions, field.name));
}
pub fn invoke(owner: *sdk.State, action: Action, args: []const c.JSValue) !c.JSValue {
    const engine = owner.engine;
    const runner = try sdk.get(engine, owner.data, "_sdkCommandRunner");
    defer engine.freeValue(runner);
    const function = try sdk.get(engine, runner, slot(action));
    defer engine.freeValue(function);
    const count: usize = switch (action) {
        .newSession => 1,
        .fork, .navigateTree, .switchSession => 2,
        else => 0,
    };
    var forwarded = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined() };
    for (0..@min(count, args.len)) |index| forwarded[index] = args[index];
    return js.call(engine, function, runner, forwarded[0..count]);
}
fn defaultAction(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return defaultValue(engine, @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn defaultValue(engine: *em.Engine, action: Action) !c.JSValue {
    if (action == .waitForIdle or action == .reload) return sdk.promise(engine, c.pi_js_undefined());
    const result = try sdk.object(engine);
    defer engine.freeValue(result);
    try sdk.put(engine, result, "cancelled", c.pi_js_bool(engine.context, 0));
    return sdk.promise(engine, result);
}
