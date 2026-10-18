//! Ordinary DefaultPackageManager constructor, with live SettingsManager identity.
//! This private class is assembled only after genuine resolver bodies are added.
//! Unimplemented public methods are absent rather than returning empty resources.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const owned = @import("native_sdk_owned_completion.zig");
const guest = @import("native_sdk_guest_operation.zig");
const guards = @import("native_agent_af_values.zig");
fn root(s: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(s, value); }
fn get(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return guest.get(s, target, name);
}
fn write(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue, define: bool) !void {
    return if (define) guest.put(s, target, name, value) else guest.set(s, target, name, value);
}
pub fn constructor(engine: *em.Engine, prototype: c.JSValue) !c.JSValue {
    return @import("native_class.zig").constructor(engine, "DefaultPackageManager", 1, prototype, construct, &.{});
}
pub fn installProgress(engine: *em.Engine, prototype: c.JSValue) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    installProgressBody(engine, prototype) catch |err| {
        _ = try engine.checked(engine.leaveNativeInvocation(&invocation, sdk.fail(engine, err)));
        unreachable;
    };
    engine.freeValue(try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())));
}
fn installProgressBody(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.pi_js_function_magic(engine.context, setProgress, "setProgressCallback", 1, 0));
    var boundary: guest.Boundary = .{ .engine = engine }; try boundary.begin();
    const status = c.JS_DefinePropertyValueStr(engine.context, prototype, "setProgressCallback", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE);
    try boundary.finishStatus(status);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const manager = try @import("native_class.zig").object(engine, target);
    var scope: Scope = .{ .engine = engine };
    var completion = owned.Completion.initValue(engine, constructBody(&scope, manager, args));
    completion.releaseScope(&scope);
    completion.release(manager);
    return completion.finishValue();
}
fn constructBody(scope: *Scope, manager: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const engine = scope.engine;
    inline for (.{ "cwd", "agentDir", "settingsManager", "builtinExtensions", "globalNpmRoot", "globalNpmRootCommandKey", "progressCallback" }) |field| try write(scope, manager, field, c.pi_js_undefined(), true);
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    try write(scope, manager, "cwd", try root(scope, try @import("native_sdk_source_paths.zig").resolve(engine, try get(scope, options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined())), false);
    try write(scope, manager, "agentDir", try root(scope, try @import("native_sdk_source_paths.zig").resolve(engine, try get(scope, options, "agentDir"), c.pi_js_undefined(), c.pi_js_undefined())), false);
    try write(scope, manager, "settingsManager", try get(scope, options, "settingsManager"), false);
    const builtins = try get(scope, options, "builtinExtensions");
    try write(scope, manager, "builtinExtensions", if (temp.nullish(builtins)) try root(scope, try sdk.array(engine)) else builtins, false);
    return c.JS_DupValue(engine.context, manager);
}
fn setProgress(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    engine.checkNativeEntry() catch |err| return sdk.fail(engine, err);
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var scope: Scope = .{ .engine = engine };
    owned.finishVoid(&scope, write(&scope, manager, "progressCallback", if (argc > 0) argv[0] else c.pi_js_undefined(), false)) catch |err|
        return engine.leaveNativeInvocation(&invocation, sdk.fail(engine, err));
    return engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
}
