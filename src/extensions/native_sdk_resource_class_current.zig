//! Source pre-trust/current extension set. The real cached loader is a mandatory
//! imported dependency; no class assembly is advertised by this module.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const spread = @import("native_sdk_resource_spread.zig");
const replacement = @import("native_sdk_extension_replacements.zig");
const c = em.c;
const Callback = enum(c_int) { enabled, path, nonbuiltin, metadata };
pub fn install(engine: *em.Engine, prototype: c.JSValue, load_extensions_cached: c.JSValue) !void {
    if (!c.JS_IsFunction(engine.context, load_extensions_cached)) return error.NativeResourceCachedLoaderRequired;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{ load_extensions_cached, try scope.own(try @import("native_sdk_extension_package_warnings.zig").create(engine)) };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "loadCurrentExtensionSet", 1, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "loadCurrentExtensionSet", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, loader, if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return observed(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn observed(engine: *em.Engine, kind: Callback, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = switch (kind) {
        .enabled => try scope.get(input, "enabled"),
        .path => try scope.get(input, "path"),
        .nonbuiltin => c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("builtin:")})))),
        .metadata => value: {
            const entry = try scope.array();
            try scope.index(entry, 0, try scope.get(input, "path"));
            try scope.index(entry, 1, try scope.get(input, "metadata"));
            break :value entry;
        },
    };
    return c.JS_DupValue(engine.context, value);
}
fn collection(scope: *Scope, values: c.JSValue, name: [*:0]const u8, kind: Callback) !c.JSValue {
    const method = try scope.get(values, name);
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), 0, null)));
    return scope.call(method, values, &.{function});
}
fn begin(engine: *em.Engine, loader: c.JSValue, options: c.JSValue, deps: [*c]c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, loader);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, options, deps) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, options: c.JSValue, deps: [*c]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "options", options);
    try scope.put(owner, "cachedLoader", deps[0]);
    try scope.put(owner, "collectWarnings", deps[1]);
    const loader = try scope.get(owner, "agent");
    try flow.wait(packagesResolved, engine, owner, try scope.invoke(try scope.get(loader, "packageManager"), "resolve", &.{}), 0);
}
fn packagesResolved(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "resolvedPaths", value);
    const loader = try scope.get(owner, "agent");
    const manager = try scope.get(loader, "packageManager");
    const resolve = try scope.get(manager, "resolveExtensionSources");
    const additional = try scope.get(loader, "additionalExtensionPaths");
    const options = try scope.object();
    try scope.put(options, "temporary", c.pi_js_bool(engine.context, 1));
    try flow.wait(cliResolved, engine, owner, try scope.call(resolve, manager, &.{ additional, options }), 0);
}
fn cliResolved(engine: *em.Engine, owner: c.JSValue, cli: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, cli);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const loader = try scope.get(owner, "agent");
    const resolved = try scope.get(owner, "resolvedPaths");
    const enabled = try collection(&scope, try collection(&scope, try scope.get(resolved, "extensions"), "filter", .enabled), "map", .path);
    const cli_enabled = try collection(&scope, try collection(&scope, try scope.get(cli, "extensions"), "filter", .enabled), "map", .path);
    const paths = try collection(&scope, if (scope.truthy(try scope.get(loader, "noExtensions"))) cli_enabled else try scope.invoke(loader, "mergePaths", &.{ cli_enabled, enabled }), "filter", .nonbuiltin);
    const map_constructor = try scope.global("Map");
    const all = try scope.array();
    var index: u32 = 0;
    try spread.literal(&scope, all, try scope.get(resolved, "extensions"), &index);
    try spread.literal(&scope, all, try scope.get(cli, "extensions"), &index);
    var map_args = [_]c.JSValue{try collection(&scope, all, "map", .metadata)};
    const metadata = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, map_args.len, &map_args)));
    const warnings = try scope.call(try scope.get(owner, "collectWarnings"), c.pi_js_undefined(), &.{ paths, metadata });
    try scope.put(owner, "warnings", warnings);
    const loaded = try scope.call(try scope.get(owner, "cachedLoader"), c.pi_js_undefined(), &.{ paths, try scope.get(loader, "cwd"), try scope.get(loader, "eventBus") });
    try flow.wait(pathsLoaded, engine, owner, loaded, 0);
}
fn pathsLoaded(engine: *em.Engine, owner: c.JSValue, result: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, result);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try replacement.mergeWarnings(&scope, result, try scope.get(owner, "warnings"));
    if (!scope.truthy(try scope.get(try scope.get(owner, "options"), "includeInlineFactories"))) return flow.settle(engine, owner, false, result);
    try scope.put(owner, "result", result);
    const loader = try scope.get(owner, "agent");
    try flow.wait(factoriesLoaded, engine, owner, try scope.invoke(loader, "loadExtensionFactories", &.{try scope.get(result, "runtime")}), 0);
}
fn factoriesLoaded(engine: *em.Engine, owner: c.JSValue, inline_result: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, inline_result);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.get(owner, "result");
    const extensions = try scope.get(result, "extensions");
    _ = try spread.call(&scope, try scope.get(extensions, "push"), extensions, try scope.get(inline_result, "extensions"));
    const errors = try scope.get(result, "errors");
    _ = try spread.call(&scope, try scope.get(errors, "push"), errors, try scope.get(inline_result, "errors"));
    const warnings = try scope.array();
    try scope.set(result, "extensions", try replacement.omit(&scope, try scope.get(result, "extensions"), warnings));
    try replacement.mergeWarnings(&scope, result, warnings);
    try flow.settle(engine, owner, false, result);
}
