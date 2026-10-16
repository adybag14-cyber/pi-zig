//! Actual live-settings/default package resolution orchestration. Its Source
//! pattern helpers and dynamic discovery/transport bodies are mandatory; this
//! module does not assemble a partial DefaultPackageManager class.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub const Dependencies = struct { apply_autoload_disabled_patterns: c.JSValue, get_override_patterns: c.JSValue, is_enabled_by_overrides: c.JSValue, config_dir: c.JSValue };
pub fn install(engine: *em.Engine, prototype: c.JSValue, deps: Dependencies) !void {
    inline for (.{ deps.apply_autoload_disabled_patterns, deps.get_override_patterns, deps.is_enabled_by_overrides }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.NativePackagePatternBodiesRequired;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, engine.native_io orelse return error.NativePackageResolveRequiresIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const types = try scope.array();
    inline for (.{ "extensions", "skills", "prompts", "themes" }, 0..) |name, index| try scope.index(types, index, try scope.text(name));
    var roots = [_]c.JSValue{ deps.apply_autoload_disabled_patterns, deps.get_override_patterns, deps.is_enabled_by_overrides, try scope.get(engine.native_module_values.get("node:path").?, "join"), types, deps.config_dir };
    const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "resolve", 1, 0, roots.len, &roots)));
    if (c.JS_SetPrototype(engine.context, function, try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)))) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "resolve", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn dispatch(context: ?*c.JSContext, manager: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return begin(engine, manager, if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn iterable(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn fallback(scope: *Scope, value: c.JSValue) !c.JSValue {
    return if (temp.nullish(value)) scope.array() else value;
}
fn packages(scope: *Scope, result: c.JSValue, values: c.JSValue, selected_scope: []const u8) !void {
    var iterator = try iterable(scope, values);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |package| {
        defer scope.engine.freeValue(package);
        const push = try scope.get(result, "push");
        const entry = try scope.object();
        try scope.put(entry, "pkg", package);
        try scope.put(entry, "scope", try scope.text(selected_scope));
        _ = try scope.call(push, result, &.{entry});
    }
}
fn begin(engine: *em.Engine, manager: c.JSValue, on_missing: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, manager);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initialize(engine, pending.owner, manager, on_missing, roots) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initialize(engine: *em.Engine, owner: c.JSValue, manager: c.JSValue, on_missing: c.JSValue, roots: [*c]c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const imports = try scope.array();
    inline for (0..6) |index| try scope.index(imports, index, roots[index]);
    try scope.put(owner, "imports", imports);
    const accumulator = try scope.invoke(manager, "createAccumulator", &.{});
    try scope.put(owner, "accumulator", accumulator);
    const global = try scope.invoke(try scope.get(manager, "settingsManager"), "getGlobalSettings", &.{});
    const project = try scope.invoke(try scope.get(manager, "settingsManager"), "getProjectSettings", &.{});
    try scope.put(owner, "global", global);
    try scope.put(owner, "project", project);
    const all = try scope.array();
    try packages(&scope, all, try fallback(&scope, try scope.get(project, "packages")), "project");
    try packages(&scope, all, try fallback(&scope, try scope.get(global, "packages")), "user");
    const deduped = try scope.invoke(manager, "dedupePackages", &.{all});
    try flow.wait(packagesResolved, engine, owner, try scope.invoke(manager, "resolvePackageSources", &.{ deduped, accumulator, on_missing }), 0);
}
fn imported(scope: *Scope, owner: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, try scope.get(owner, "imports"), index)));
}
fn metadata(scope: *Scope, selected_scope: []const u8) !c.JSValue {
    const info = try scope.object();
    try scope.put(info, "source", try scope.text("local"));
    try scope.put(info, "scope", try scope.text(selected_scope));
    try scope.put(info, "origin", try scope.text("top-level"));
    return info;
}
fn packagesResolved(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const manager = try scope.get(owner, "agent");
    const accumulator = try scope.get(owner, "accumulator");
    const global = try scope.get(owner, "global");
    const project = try scope.get(owner, "project");
    const global_base = try scope.get(manager, "agentDir");
    const project_base = try scope.call(try imported(&scope, owner, 3), c.pi_js_undefined(), &.{ try scope.get(manager, "cwd"), try imported(&scope, owner, 5) });
    var iterator = try iterable(&scope, try imported(&scope, owner, 4));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |resource_type| {
        defer engine.freeValue(resource_type);
        const target = try scope.invoke(manager, "getTargetMap", &.{ accumulator, resource_type });
        const global_entries = try fallback(&scope, try scope.own(try js.getKey(engine, global, resource_type)));
        const project_entries = try fallback(&scope, try scope.own(try js.getKey(engine, project, resource_type)));
        const project_resolve = try scope.get(manager, "resolveLocalEntries");
        _ = try scope.call(project_resolve, manager, &.{ project_entries, resource_type, target, try metadata(&scope, "project"), project_base });
        const global_resolve = try scope.get(manager, "resolveLocalEntries");
        _ = try scope.call(global_resolve, manager, &.{ global_entries, resource_type, target, try metadata(&scope, "user"), global_base });
    }
    _ = try scope.invoke(manager, "addAutoDiscoveredResources", &.{ accumulator, global, project, global_base, project_base });
    try builtins(&scope, owner, manager, accumulator, global, project, global_base, project_base);
    const finish = try scope.get(manager, "toResolvedPaths");
    try flow.settle(engine, owner, false, try scope.call(finish, manager, &.{accumulator}));
}
fn builtins(scope: *Scope, owner: c.JSValue, manager: c.JSValue, accumulator: c.JSValue, global: c.JSValue, project: c.JSValue, global_base: c.JSValue, project_base: c.JSValue) !void {
    var iterator = try iterable(scope, try scope.get(manager, "builtinExtensions"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |name| {
        defer scope.engine.freeValue(name);
        const path = try scope.concat(try scope.text("builtin:"), try scope.stringify(name));
        const apply = try imported(scope, owner, 0);
        const paths = try scope.array();
        try scope.index(paths, 0, path);
        const get_patterns = try imported(scope, owner, 1);
        const patterns = try scope.call(get_patterns, c.pi_js_undefined(), &.{try fallback(scope, try scope.get(project, "extensions"))});
        const enabled_map = try scope.call(apply, c.pi_js_undefined(), &.{ paths, patterns, project_base });
        const enabled = try scope.invoke(enabled_map, "get", &.{path});
        const add = try scope.get(manager, "addResource");
        const target = try scope.get(accumulator, "extensions");
        const info = try scope.object();
        try scope.put(info, "source", try scope.text("builtin"));
        try scope.put(info, "scope", try scope.text(if (c.JS_IsUndefined(enabled)) "user" else "project"));
        try scope.put(info, "origin", try scope.text("top-level"));
        const final_enabled = if (temp.nullish(enabled)) try scope.call(try imported(scope, owner, 2), c.pi_js_undefined(), &.{ path, try fallback(scope, try scope.get(global, "extensions")), global_base }) else enabled;
        _ = try scope.call(add, manager, &.{ target, path, info, final_enabled });
    }
}
