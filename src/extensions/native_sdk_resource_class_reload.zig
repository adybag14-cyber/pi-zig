//! Ordinary Source reload orchestration with real async boundaries. Installation
//! requires actual cache/timing/context dependencies; it supplies no placeholders.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const body = @import("native_async_body.zig");
const af = body.native;
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
fn guardVoid(engine: *em.Engine, generation: u64, result: anyerror!void) anyerror!void {
    const value: anyerror!c.JSValue = if (result) |_| c.pi_js_undefined() else |err| err;
    _ = try guards.guard(engine, generation, value);
}
fn guardAction(engine: *em.Engine, generation: u64, result: anyerror!af.Action) anyerror!af.Action {
    return result catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| try body.rethrowRecognizedAllocation(engine, reason, generation);
        return err;
    };
}
const spread = @import("native_sdk_resource_spread.zig");
const replacement = @import("native_sdk_extension_replacements.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub const Dependencies = struct { reset_timings: c.JSValue, clear_extension_cache: c.JSValue, load_project_context_files: c.JSValue, resolve_prompt_input: c.JSValue };
const Import = enum(usize) { reset, clear, context, prompt, exists, warnings };
const Callback = enum(c_int) { enabled, path, skill, extension_enabled, diagnostic, append_input, present, exists, resolved };
const Stage = enum(c_int) { trust_extensions, trust_resolved, settings_reloaded, packages_resolved, cli_resolved, extensions_loaded };
pub fn install(engine: *em.Engine, prototype: c.JSValue, deps: Dependencies) !void {
    inline for (.{ deps.reset_timings, deps.clear_extension_cache, deps.load_project_context_files, deps.resolve_prompt_input }) |function| if (!c.JS_IsFunction(engine.context, function)) return error.NativeResourceReloadDependenciesRequired;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, engine.native_io orelse return error.NativeResourceReloadRequiresIo);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const roots = [_]c.JSValue{ deps.reset_timings, deps.clear_extension_cache, deps.load_project_context_files, deps.resolve_prompt_input, try scope.get(engine.native_module_values.get("node:fs").?, "existsSync"), try scope.own(try @import("native_sdk_extension_package_warnings.zig").create(engine)) };
    const function = try scope.own(try af.createResumable(engine, "reload", 1, reloadBody, &roots));
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "reload", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn reloadBody(engine: *em.Engine, loader: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    const generation = engine.native_allocation_generation;
    return reloadStep(engine, loader, args, roots, state, completion, input) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            try body.rethrowRecognizedAllocation(engine, reason, generation);
            if (c.JS_IsUncatchableError(reason)) return err;
            engine.captured_exception = null;
            return .{ .thrown = reason };
        };
        return body.failure(engine, err);
    };
}
fn reloadStep(engine: *em.Engine, loader: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishAction(&scope, guardAction(engine, generation, reloadStepScoped(&scope, engine, loader, args, roots, state, completion, input)));
}
fn reloadStepScoped(scope: *Scope, engine: *em.Engine, loader: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .start) {
        const owner = try body.init(scope, state);
        try scope.put(owner, "agent", loader);
        try initialize(engine, owner, if (args.len > 0) args[0] else c.pi_js_undefined(), roots);
    } else {
        if (completion == .rejected) {
            try body.enterRejectedContinuation(engine);
            return .{ .thrown = c.JS_DupValue(engine.context, input) };
        }
        const stage: Stage = @enumFromInt(try body.stage(scope, state.*));
        switch (stage) {
            .trust_extensions => try trustExtensionsLoaded(engine, state.*, input, false, 0),
            .trust_resolved => try trustResolved(engine, state.*, input, false, 0),
            .settings_reloaded => try settingsReloaded(engine, state.*, input, false, 0),
            .packages_resolved => try packagesResolved(engine, state.*, input, false, 0),
            .cli_resolved => try cliResolved(engine, state.*, input, false, 0),
            .extensions_loaded => try extensionsLoaded(engine, state.*, input, false, 0),
        }
    }
    return body.action(scope, state.*);
}
fn wait(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, waitScoped(&scope, engine, owner, value, stage)), owner);
}
fn waitScoped(scope: *Scope, _: *em.Engine, owner: c.JSValue, value: c.JSValue, stage: Stage) !void {
    try body.wait(scope, owner, value, @intFromEnum(stage));
}
fn settle(engine: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, settleScoped(&scope, engine, owner, rejected, value)), owner);
}
fn settleScoped(scope: *Scope, _: *em.Engine, owner: c.JSValue, rejected: bool, value: c.JSValue) !void {
    if (rejected) try body.reject(scope, owner, value) else try body.resolve(scope, owner, value);
}
fn set(engine: *em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try engine.checkNativeEntry();
    if (c.JS_SetPropertyStr(engine.context, target, name, c.JS_DupValue(engine.context, value)) < 0) return js.capture(engine);
    _ = try engine.checked(c.pi_js_undefined());
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return observed(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn observed(engine: *em.Engine, kind: Callback, input: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishValue(&scope, guards.guard(engine, generation, observedScoped(&scope, engine, kind, input, roots)));
}
fn observedScoped(scope: *Scope, engine: *em.Engine, kind: Callback, input: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    const result = switch (kind) {
        .enabled => try scope.get(input, "enabled"),
        .path => try scope.get(input, "path"),
        .skill => try scope.invoke(roots[0], "mapSkillPath", &.{ input, roots[1] }),
        .extension_enabled => value: {
            if (!scope.truthy(try scope.invoke(input, "startsWith", &.{try scope.text("builtin:")}))) break :value c.pi_js_bool(engine.context, 1);
            const disabled = try scope.get(roots[0], "disabledBuiltinExtensions");
            const has = try scope.get(disabled, "has");
            break :value c.pi_js_bool(engine.context, @intFromBool(!scope.truthy(try scope.call(has, disabled, &.{try scope.invoke(input, "slice", &.{c.JS_NewInt32(engine.context, 8)})}))));
        },
        .diagnostic => c.pi_js_bool(engine.context, @intFromBool(scope.equal(try scope.get(input, "path"), roots[0]))),
        .append_input => try scope.call(roots[0], c.pi_js_undefined(), &.{ input, try scope.text("append system prompt") }),
        .present => c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(input))),
        .exists => try scope.call(roots[0], c.pi_js_undefined(), &.{input}),
        .resolved => try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, input, c.pi_js_undefined(), c.pi_js_undefined())),
    };
    return c.JS_DupValue(engine.context, result);
}
fn collection(scope: *Scope, values: c.JSValue, method_name: [*:0]const u8, kind: Callback, roots: []c.JSValue) !c.JSValue {
    const method = try scope.get(values, method_name);
    const function = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(kind), @intCast(roots.len), roots.ptr)));
    return scope.call(method, values, &.{function});
}
fn imported(scope: *Scope, owner: c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    const deps = try scope.get(owner, "deps");
    const function = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, deps, @intFromEnum(kind))));
    return scope.call(function, c.pi_js_undefined(), args);
}
fn importValue(scope: *Scope, owner: c.JSValue, kind: Import) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, try scope.get(owner, "deps"), @intFromEnum(kind))));
}
fn iterate(scope: *Scope, input: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, input, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn initialize(engine: *em.Engine, owner: c.JSValue, options: c.JSValue, roots: []const c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, initializeScoped(&scope, engine, owner, options, roots)), owner);
}
fn initializeScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, options: c.JSValue, roots: []const c.JSValue) !void {
    const deps = try scope.array();
    inline for (0..6) |index| try scope.index(deps, index, roots[index]);
    try scope.put(owner, "deps", deps);
    try scope.put(owner, "options", options);
    try scope.put(owner, "preTrustExtensions", c.pi_js_undefined());
    _ = try imported(scope, owner, .reset, &.{try scope.text("extensions")});
    const loader = try scope.get(owner, "agent");
    if (scope.truthy(try scope.get(loader, "loaded"))) _ = try imported(scope, owner, .clear, &.{});
    if (!temp.nullish(options) and scope.truthy(try scope.get(options, "resolveProjectTrust"))) {
        return wait(engine, owner, try scope.invoke(loader, "loadProjectTrustExtensions", &.{}), .trust_extensions);
    }
    try reloadSettings(engine, owner);
}
fn trustExtensionsLoaded(engine: *em.Engine, owner: c.JSValue, result: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, trustExtensionsLoadedScoped(&scope, engine, owner, result, rejected, 0)), owner);
}
fn trustExtensionsLoadedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, result: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, result);

    try scope.put(owner, "preTrustExtensions", result);
    const options = try scope.get(owner, "options");
    const resolve = try scope.get(options, "resolveProjectTrust");
    const input = try scope.object();
    try scope.put(input, "extensionsResult", result);
    try wait(engine, owner, try scope.call(resolve, options, &.{input}), .trust_resolved);
}
fn trustResolved(engine: *em.Engine, owner: c.JSValue, trusted: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, trustResolvedScoped(&scope, engine, owner, trusted, rejected, 0)), owner);
}
fn trustResolvedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, trusted: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, trusted);

    const loader = try scope.get(owner, "agent");
    _ = try scope.invoke(try scope.get(loader, "settingsManager"), "setProjectTrusted", &.{trusted});
    try reloadSettings(engine, owner);
}
fn reloadSettings(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, reloadSettingsScoped(&scope, engine, owner)), owner);
}
fn reloadSettingsScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue) !void {
    const loader = try scope.get(owner, "agent");
    try wait(engine, owner, try scope.invoke(try scope.get(loader, "settingsManager"), "reload", &.{}), .settings_reloaded);
}
fn settingsReloaded(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, settingsReloadedScoped(&scope, engine, owner, value, rejected, 0)), owner);
}
fn settingsReloadedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, value);

    const loader = try scope.get(owner, "agent");
    try wait(engine, owner, try scope.invoke(try scope.get(loader, "packageManager"), "resolve", &.{}), .packages_resolved);
}
fn packagesResolved(engine: *em.Engine, owner: c.JSValue, resolved: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, packagesResolvedScoped(&scope, engine, owner, resolved, rejected, 0)), owner);
}
fn packagesResolvedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, resolved: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, resolved);

    try scope.put(owner, "resolvedPaths", resolved);
    const loader = try scope.get(owner, "agent");
    const manager = try scope.get(loader, "packageManager");
    const resolve = try scope.get(manager, "resolveExtensionSources");
    const additional = try scope.get(loader, "additionalExtensionPaths");
    const options = try scope.object();
    try scope.put(options, "temporary", c.pi_js_bool(engine.context, 1));
    try wait(engine, owner, try scope.call(resolve, manager, &.{ additional, options }), .cli_resolved);
}
fn enabledResources(scope: *Scope, resources: c.JSValue, metadata: c.JSValue) !c.JSValue {
    var iterator = try iterate(scope, resources);
    const generation = scope.engine.native_allocation_generation;
    var completion = owned.Completion.initValue(scope.engine, guards.guard(scope.engine, generation, enabledResourcesItems(scope, resources, metadata, &iterator)));
    completion.release(iterator.next_function);
    completion.release(iterator.iterator);
    return completion.finishValue();
}
fn retireItem(scope: *Scope, value: c.JSValue, generation: u64, result: anyerror!void) !void {
    var completion = owned.Completion.initVoid(scope.engine, guardVoid(scope.engine, generation, result));
    completion.release(value);
    return completion.finishVoid();
}
fn retireIterator(scope: *Scope, iterator: *js.Iterator, generation: u64, result: anyerror!void) !void {
    var completion = owned.Completion.initVoid(scope.engine, guardVoid(scope.engine, generation, result));
    completion.release(iterator.next_function);
    completion.release(iterator.iterator);
    return completion.finishVoid();
}
fn enabledResourcesItems(scope: *Scope, resources: c.JSValue, metadata: c.JSValue, iterator: *js.Iterator) !c.JSValue {
    errdefer iterator.closePreserving();
    while (try iterator.next()) |resource| {
        const generation = scope.engine.native_allocation_generation;
        try retireItem(scope, resource, generation, enabledResource(scope, resource, metadata));
    }
    return collection(scope, resources, "filter", .enabled, &.{});
}
fn enabledResource(scope: *Scope, resource: c.JSValue, metadata: c.JSValue) !void {
    const has = try scope.get(metadata, "has");
    if (!scope.truthy(try scope.call(has, metadata, &.{try scope.get(resource, "path")}))) {
        const set = try scope.get(metadata, "set");
        _ = try scope.call(set, metadata, &.{ try scope.get(resource, "path"), try scope.get(resource, "metadata") });
    }
}
fn enabledPaths(scope: *Scope, resources: c.JSValue, metadata: c.JSValue) !c.JSValue {
    return collection(scope, try enabledResources(scope, resources, metadata), "map", .path, &.{});
}
fn cliMetadata(scope: *Scope, resources: c.JSValue, metadata: c.JSValue) !void {
    var iterator = try iterate(scope, resources);
    const generation = scope.engine.native_allocation_generation;
    return retireIterator(scope, &iterator, generation, cliMetadataItems(scope, metadata, &iterator));
}
fn cliMetadataItems(scope: *Scope, metadata: c.JSValue, iterator: *js.Iterator) !void {
    errdefer iterator.closePreserving();
    while (try iterator.next()) |resource| {
        const generation = scope.engine.native_allocation_generation;
        try retireItem(scope, resource, generation, cliMetadataItem(scope, resource, metadata));
    }
}
fn cliMetadataItem(scope: *Scope, resource: c.JSValue, metadata: c.JSValue) !void {
    const has = try scope.get(metadata, "has");
    if (!scope.truthy(try scope.call(has, metadata, &.{try scope.get(resource, "path")}))) {
        const set = try scope.get(metadata, "set");
        const path = try scope.get(resource, "path");
        const info = try scope.object();
        try scope.put(info, "source", try scope.text("cli"));
        try scope.put(info, "scope", try scope.text("temporary"));
        try scope.put(info, "origin", try scope.text("top-level"));
        _ = try scope.call(set, metadata, &.{ path, info });
    }
}
fn cliResolved(engine: *em.Engine, owner: c.JSValue, cli: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, cliResolvedScoped(&scope, engine, owner, cli, rejected, 0)), owner);
}
fn cliResolvedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, cli: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, cli);

    const loader = try scope.get(owner, "agent");
    try set(scope.engine, loader, "resourceMetadataByPath", try scope.own(try js.builtin(engine, "Map", &.{})));
    const metadata = try scope.get(loader, "resourceMetadataByPath");
    try scope.put(owner, "metadata", metadata);
    inline for (.{ "extensionSkillSourceInfos", "extensionPromptSourceInfos", "extensionThemeSourceInfos" }) |field| try set(scope.engine, loader, field, try scope.own(try js.builtin(engine, "Map", &.{})));
    const resolved = try scope.get(owner, "resolvedPaths");
    const extensions = try enabledPaths(scope, try scope.get(resolved, "extensions"), metadata);
    const skill_resources = try enabledResources(scope, try scope.get(resolved, "skills"), metadata);
    const prompts = try enabledPaths(scope, try scope.get(resolved, "prompts"), metadata);
    const themes = try enabledPaths(scope, try scope.get(resolved, "themes"), metadata);
    var skill_roots = [_]c.JSValue{ loader, metadata };
    const skills = try collection(scope, skill_resources, "map", .skill, &skill_roots);
    try cliMetadata(scope, try scope.get(cli, "extensions"), metadata);
    try cliMetadata(scope, try scope.get(cli, "skills"), metadata);
    const cli_extensions = try enabledPaths(scope, try scope.get(cli, "extensions"), metadata);
    const cli_skills = try enabledPaths(scope, try scope.get(cli, "skills"), metadata);
    const cli_prompts = try enabledPaths(scope, try scope.get(cli, "prompts"), metadata);
    const cli_themes = try enabledPaths(scope, try scope.get(cli, "themes"), metadata);
    inline for (.{ .{ "skills", skills }, .{ "prompts", prompts }, .{ "themes", themes }, .{ "cliSkills", cli_skills }, .{ "cliPrompts", cli_prompts }, .{ "cliThemes", cli_themes } }) |entry| try scope.put(owner, entry[0], entry[1]);
    const merged = if (scope.truthy(try scope.get(loader, "noExtensions"))) cli_extensions else try scope.invoke(loader, "mergePaths", &.{ cli_extensions, extensions });
    var extension_roots = [_]c.JSValue{loader};
    const paths = try collection(scope, merged, "filter", .extension_enabled, &extension_roots);
    try scope.put(owner, "warnings", try imported(scope, owner, .warnings, &.{ paths, metadata }));
    try wait(engine, owner, try scope.invoke(loader, "loadFinalExtensionSet", &.{ paths, try scope.get(owner, "preTrustExtensions") }), .extensions_loaded);
}
fn localPath(scope: *Scope, input: c.JSValue) !bool {
    const trimmed = try scope.invoke(input, "trim", &.{});
    inline for (.{ "npm:", "git:", "github:", "http:", "https:", "ssh:", "builtin:" }) |prefix| if (scope.truthy(try scope.invoke(trimmed, "startsWith", &.{try scope.text(prefix)}))) return false;
    return true;
}
fn missingExtensions(scope: *Scope, owner: c.JSValue, loader: c.JSValue, result: c.JSValue) !void {
    var iterator = try iterate(scope, try scope.get(loader, "additionalExtensionPaths"));
    const generation = scope.engine.native_allocation_generation;
    return retireIterator(scope, &iterator, generation, missingExtensionItems(scope, owner, loader, result, &iterator));
}
fn missingExtensionItems(scope: *Scope, owner: c.JSValue, loader: c.JSValue, result: c.JSValue, iterator: *js.Iterator) !void {
    errdefer iterator.closePreserving();
    while (try iterator.next()) |path| {
        const generation = scope.engine.native_allocation_generation;
        try retireItem(scope, path, generation, missingExtensionItem(scope, owner, loader, result, path));
    }
}
fn missingExtensionItem(scope: *Scope, owner: c.JSValue, loader: c.JSValue, result: c.JSValue, path: c.JSValue) !void {
    if (!try localPath(scope, path)) return;
    const resolved = try scope.invoke(loader, "resolveResourcePath", &.{path});
    if (scope.truthy(try imported(scope, owner, .exists, &.{resolved}))) return;
    const errors = try scope.get(result, "errors");
    const push = try scope.get(errors, "push");
    const row = try scope.object();
    try scope.put(row, "path", resolved);
    try scope.put(row, "error", try scope.concat(try scope.text("Extension path does not exist: "), try scope.stringify(resolved)));
    _ = try scope.call(push, errors, &.{row});
}
fn override(scope: *Scope, loader: c.JSValue, field: [*:0]const u8, input: c.JSValue) !c.JSValue {
    return if (scope.truthy(try scope.get(loader, field))) scope.invoke(loader, field, &.{input}) else input;
}
fn resourcePaths(scope: *Scope, owner: c.JSValue, loader: c.JSValue, disabled_field: [*:0]const u8, cli_field: [*:0]const u8, enabled_field: [*:0]const u8, additional_field: [*:0]const u8) !c.JSValue {
    const disabled = scope.truthy(try scope.get(loader, disabled_field));
    const merge = try scope.get(loader, "mergePaths");
    const cli = try scope.get(owner, cli_field);
    var primary = cli;
    if (!disabled) {
        primary = try scope.array();
        var index: u32 = 0;
        try spread.literal(scope, primary, cli, &index);
        try spread.literal(scope, primary, try scope.get(owner, enabled_field), &index);
    }
    return scope.call(merge, loader, &.{ primary, try scope.get(loader, additional_field) });
}
fn missingResourcePaths(scope: *Scope, owner: c.JSValue, loader: c.JSValue, additional_field: [*:0]const u8, diagnostics_field: [*:0]const u8, message: []const u8, check_local: bool) !void {
    var iterator = try iterate(scope, try scope.get(loader, additional_field));
    const generation = scope.engine.native_allocation_generation;
    return retireIterator(scope, &iterator, generation, missingResourceItems(scope, owner, loader, diagnostics_field, message, check_local, &iterator));
}
fn missingResourceItems(scope: *Scope, owner: c.JSValue, loader: c.JSValue, diagnostics_field: [*:0]const u8, message: []const u8, check_local: bool, iterator: *js.Iterator) !void {
    errdefer iterator.closePreserving();
    while (try iterator.next()) |path| {
        const generation = scope.engine.native_allocation_generation;
        try retireItem(scope, path, generation, missingResourceItem(scope, owner, loader, diagnostics_field, message, check_local, path));
    }
}
fn missingResourceItem(scope: *Scope, owner: c.JSValue, loader: c.JSValue, diagnostics_field: [*:0]const u8, message: []const u8, check_local: bool, path: c.JSValue) !void {
    if (check_local and !try localPath(scope, path)) return;
    const resolved = try scope.invoke(loader, "resolveResourcePath", &.{path});
    if (scope.truthy(try imported(scope, owner, .exists, &.{resolved}))) return;
    var roots = [_]c.JSValue{resolved};
    if (scope.truthy(try collection(scope, try scope.get(loader, diagnostics_field), "some", .diagnostic, &roots))) return;
    const diagnostics = try scope.get(loader, diagnostics_field);
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("error"));
    try scope.put(row, "message", try scope.text(message));
    try scope.put(row, "path", resolved);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn extensionsLoaded(engine: *em.Engine, owner: c.JSValue, result: c.JSValue, rejected: bool, _: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    const generation = engine.native_allocation_generation;
    return owned.finishRecorded(&scope, guardVoid(engine, generation, extensionsLoadedScoped(&scope, engine, owner, result, rejected, 0)), owner);
}
fn extensionsLoadedScoped(scope: *Scope, engine: *em.Engine, owner: c.JSValue, result: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return settle(engine, owner, true, result);

    const loader = try scope.get(owner, "agent");
    const metadata = try scope.get(owner, "metadata");
    try replacement.mergeWarnings(scope, result, try scope.get(owner, "warnings"));
    try missingExtensions(scope, owner, loader, result);
    try set(scope.engine, loader, "extensionsResult", try override(scope, loader, "extensionsOverride", result));
    const apply = try scope.get(loader, "applyExtensionSourceInfo");
    _ = try scope.call(apply, loader, &.{ try scope.get(try scope.get(loader, "extensionsResult"), "extensions"), metadata });
    const skills = try resourcePaths(scope, owner, loader, "noSkills", "cliSkills", "skills", "additionalSkillPaths");
    try set(scope.engine, loader, "lastSkillPaths", skills);
    _ = try scope.invoke(loader, "updateSkillsFromPaths", &.{ skills, metadata });
    try missingResourcePaths(scope, owner, loader, "additionalSkillPaths", "skillDiagnostics", "Skill path does not exist", true);
    const prompts = try resourcePaths(scope, owner, loader, "noPromptTemplates", "cliPrompts", "prompts", "additionalPromptTemplatePaths");
    try set(scope.engine, loader, "lastPromptPaths", prompts);
    _ = try scope.invoke(loader, "updatePromptsFromPaths", &.{ prompts, metadata });
    try missingResourcePaths(scope, owner, loader, "additionalPromptTemplatePaths", "promptDiagnostics", "Prompt template path does not exist", true);
    const themes = try resourcePaths(scope, owner, loader, "noThemes", "cliThemes", "themes", "additionalThemePaths");
    try set(scope.engine, loader, "lastThemePaths", themes);
    _ = try scope.invoke(loader, "updateThemesFromPaths", &.{ themes, metadata });
    try missingResourcePaths(scope, owner, loader, "additionalThemePaths", "themeDiagnostics", "Theme path does not exist", false);
    try finishPrompts(scope, owner, loader);
    try set(scope.engine, loader, "loaded", c.pi_js_bool(engine.context, 1));
    try settle(engine, owner, false, c.pi_js_undefined());
}
fn finishPrompts(scope: *Scope, owner: c.JSValue, loader: c.JSValue) !void {
    const agents = try scope.object();
    var files: c.JSValue = undefined;
    if (scope.truthy(try scope.get(loader, "noContextFiles"))) {
        files = try scope.array();
    } else {
        const load_context = try importValue(scope, owner, .context);
        const options = try scope.object();
        try scope.put(options, "cwd", try scope.get(loader, "cwd"));
        try scope.put(options, "agentDir", try scope.get(loader, "agentDir"));
        files = try scope.call(load_context, c.pi_js_undefined(), &.{options});
    }
    try scope.put(agents, "agentsFiles", files);
    const resolved_agents = try override(scope, loader, "agentsFilesOverride", agents);
    try set(scope.engine, loader, "agentsFiles", try scope.get(resolved_agents, "agentsFiles"));
    var system_source = try scope.get(loader, "systemPromptSource");
    if (temp.nullish(system_source)) system_source = try scope.invoke(loader, "discoverSystemPromptFile", &.{});
    const base_system = try imported(scope, owner, .prompt, &.{ system_source, try scope.text("system prompt") });
    try set(scope.engine, loader, "systemPrompt", try override(scope, loader, "systemPromptOverride", base_system));
    const system_path = if (scope.truthy(system_source) and scope.truthy(try imported(scope, owner, .exists, &.{system_source}))) try scope.own(try @import("native_sdk_source_paths.zig").resolve(scope.engine, system_source, c.pi_js_undefined(), c.pi_js_undefined())) else c.pi_js_undefined();
    try set(scope.engine, loader, "systemPromptSourcePath", system_path);
    var append_sources = try scope.get(loader, "appendSystemPromptSource");
    if (!scope.truthy(append_sources)) {
        const discovered = try scope.invoke(loader, "discoverAppendSystemPromptFile", &.{});
        append_sources = try scope.array();
        if (scope.truthy(discovered)) try scope.index(append_sources, 0, discovered);
    }
    var prompt_roots = [_]c.JSValue{try importValue(scope, owner, .prompt)};
    const mapped = try collection(scope, append_sources, "map", .append_input, &prompt_roots);
    const base_append = try collection(scope, mapped, "filter", .present, &.{});
    try set(scope.engine, loader, "appendSystemPrompt", try override(scope, loader, "appendSystemPromptOverride", base_append));
    var exists_roots = [_]c.JSValue{try importValue(scope, owner, .exists)};
    const existing = try collection(scope, append_sources, "filter", .exists, &exists_roots);
    try set(scope.engine, loader, "appendSystemPromptSourcePaths", try collection(scope, existing, "map", .resolved, &.{}));
}
