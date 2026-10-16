//! Ordinary DefaultPackageManager constructor, with live SettingsManager identity.
//! This private class is assembled only after genuine resolver bodies are added.
//! Unimplemented public methods are absent rather than returning empty resources.
const data = @import("native_sdk_package_data.zig");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
pub fn constructor(engine: *em.Engine, prototype: c.JSValue) !c.JSValue {
    return @import("native_class.zig").constructor(engine, "DefaultPackageManager", 1, prototype, construct, &.{});
}
pub fn installProgress(engine: *em.Engine, prototype: c.JSValue) !void {
    const function = try engine.checked(c.pi_js_function_magic(engine.context, setProgress, "setProgressCallback", 1, 0));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "setProgressCallback", function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const manager = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(manager);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "cwd", "agentDir", "settingsManager", "builtinExtensions", "globalNpmRoot", "globalNpmRootCommandKey", "progressCallback" }) |field| try data.put(scope.engine, manager, field, c.pi_js_undefined());
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    try scope.set(manager, "cwd", try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined())));
    try scope.set(manager, "agentDir", try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "agentDir"), c.pi_js_undefined(), c.pi_js_undefined())));
    try scope.set(manager, "settingsManager", try scope.get(options, "settingsManager"));
    const builtins = try scope.get(options, "builtinExtensions");
    try scope.set(manager, "builtinExtensions", if (temp.nullish(builtins)) try scope.array() else builtins);
    return manager;
}
fn setProgress(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    scope.set(manager, "progressCallback", if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
