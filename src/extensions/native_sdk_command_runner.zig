//! Actual session-owned command action state and callback receiver.
//! The actual factory calls the real public constructor with five live refs.
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
    const resources = try sdk.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(resources);
    const extensions = try js.invoke(engine, resources, "getExtensions", &.{});
    defer engine.freeValue(extensions);
    const runtime = try sdk.get(engine, extensions, "runtime");
    defer engine.freeValue(runtime);
    const rows = try sdk.get(engine, extensions, "extensions");
    defer engine.freeValue(rows);
    const cwd = try sdk.get(engine, owner.data, "_sdkToolCwd");
    defer engine.freeValue(cwd);
    const normalized = try @import("native_sdk_settings.zig").normalizePath(engine, cwd);
    defer engine.freeValue(normalized);
    const requested = try engine.toString(normalized);
    defer engine.gpa.free(requested);
    const current = try sdk.cwd(engine);
    defer engine.gpa.free(current);
    const path = try @import("node_path.zig").resolve(engine.gpa, current, &.{requested}, if (@import("builtin").os.tag == .windows) .win32 else .posix);
    defer engine.gpa.free(path);
    const working = try sdk.text(engine, path);
    defer engine.freeValue(working);
    const manager = try sdk.publicField(owner, "sessionManager");
    defer engine.freeValue(manager);
    const registry = try sdk.get(engine, owner.data, "modelRegistry");
    defer engine.freeValue(registry);
    var args = [_]c.JSValue{ rows, runtime, working, manager, registry };
    const constructor = engine.native_sdk_command_runner_constructor orelse return error.NativeSDKRunnerConstructorUnavailable;
    const runner = try engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
    defer engine.freeValue(runner);
    try sdk.put(engine, owner.data, "_sdkCommandRunner", c.JS_DupValue(engine.context, runner));
    try sdk.put(engine, session, "_extensionRunner", c.JS_DupValue(engine.context, runner));
    try @import("native_sdk_factory_core.zig").bind(engine, session, runner);
    try @import("native_sdk_factory_core.zig").applyBindings(engine, owner, session, runner);
}
const Method = enum(c_int) { resolveRegisteredCommands, getRegisteredCommands, getCommand, getCommandDiagnostics };
pub fn getPrototype(engine: *em.Engine) !c.JSValue {
    if (engine.native_sdk_command_runner_prototype) |value| return c.JS_DupValue(engine.context, value);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (@import("std").meta.fields(Method)) |field| {
        const callback = try engine.checked(c.pi_js_function_magic(engine.context, method, field.name, if (field.value == @intFromEnum(Method.getCommand)) 1 else 0, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, result, field.name, callback, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
    try @import("native_sdk_public_runner.zig").installPrototype(engine, result);
    engine.native_sdk_command_runner_prototype = c.JS_DupValue(engine.context, result);
    return result;
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return methodValue(engine, receiver, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn methodValue(engine: *em.Engine, receiver: c.JSValue, operation: Method, name: c.JSValue) !c.JSValue {
    switch (operation) {
        .resolveRegisteredCommands => {
            const rows = try sdk.get(engine, receiver, "extensions");
            defer engine.freeValue(rows);
            return @import("native_sdk_command_resolution.zig").resolveForRunner(engine, rows, receiver);
        },
        .getRegisteredCommands => {
            // Ordinary assignment intentionally invokes an inherited setter
            // before the dynamic resolver lookup. This pure method has no
            // session lease gate: retained Source runners still resolve rows.
            if (c.JS_SetPropertyStr(engine.context, receiver, "commandDiagnostics", try sdk.array(engine)) < 0) return js.capture(engine);
            return js.invoke(engine, receiver, "resolveRegisteredCommands", &.{});
        },
        .getCommandDiagnostics => return sdk.get(engine, receiver, "commandDiagnostics"),
        .getCommand => {
            const commands = try js.invoke(engine, receiver, "resolveRegisteredCommands", &.{});
            defer engine.freeValue(commands);
            var roots = [_]c.JSValue{name};
            const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, matches, "", 1, 0, roots.len, &roots));
            defer engine.freeValue(predicate);
            return js.invoke(engine, commands, "find", &.{predicate});
        },
    }
}
fn matches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const name = sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "invocationName") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(name);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(context, name, roots[0])));
}
pub fn bind(owner: *sdk.State) !void {
    const engine = owner.engine;
    const runner = try sdk.get(engine, owner.data, "_sdkCommandRunner");
    defer engine.freeValue(runner);
    const actions = try sdk.get(engine, owner.data, "extension_commandContextActions");
    defer engine.freeValue(actions);
    const ignored = try js.invoke(engine, runner, "bindCommandContext", &.{actions});
    engine.freeValue(ignored);
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
