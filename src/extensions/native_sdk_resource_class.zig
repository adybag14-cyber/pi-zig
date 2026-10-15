//! Ordinary Source DefaultResourceLoader constructor and cache getters.
//! Assembly must supply the actual native DefaultPackageManager constructor.
//! Missing reload/discovery bodies remain absent until their genuine ports are
//! installed; this constructor is private and does not replace SDK exports.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
const fields = .{
    "cwd", "agentDir", "settingsManager", "eventBus", "packageManager", "additionalExtensionPaths", "additionalSkillPaths", "additionalPromptTemplatePaths", "additionalThemePaths", "extensionFactories", "builtinExtensions", "noExtensions", "disabledBuiltinExtensions", "noSkills", "noPromptTemplates", "noThemes", "noContextFiles", "systemPromptSource", "appendSystemPromptSource", "extensionsOverride", "skillsOverride", "promptsOverride", "themesOverride", "agentsFilesOverride", "systemPromptOverride", "appendSystemPromptOverride", "extensionsResult", "skills", "skillDiagnostics", "prompts", "promptDiagnostics", "themes", "themeDiagnostics", "agentsFiles", "systemPrompt", "systemPromptSourcePath", "appendSystemPrompt", "appendSystemPromptSourcePaths", "lastSkillPaths", "extensionSkillSourceInfos", "extensionPromptSourceInfos", "extensionThemeSourceInfos", "resourceMetadataByPath", "lastPromptPaths", "lastThemePaths", "loaded",
};
const Getter = enum(c_int) { getExtensions, getSkills, getPrompts, getThemes, getAgentsFiles, getSystemPrompt, getSystemPromptSource, getAppendSystemPrompt, getAppendSystemPromptSources };
const Predicate = enum(c_int) { inline_factory, builtin_factory, builtin_pair, source_path };
pub fn constructor(engine: *em.Engine, prototype: c.JSValue, settings_manager: c.JSValue, package_manager: c.JSValue) !c.JSValue {
    if (!c.JS_IsConstructor(engine.context, settings_manager) or !c.JS_IsConstructor(engine.context, package_manager)) return error.RequiredActualNativeResourceLoaderDependencies;
    const is_builtin = try @import("native_node_function.zig").create(engine, "isBuiltinExtension", 1, builtinPredicate, &.{});
    defer engine.freeValue(is_builtin);
    return @import("native_class.zig").constructor(engine, "DefaultResourceLoader", 1, prototype, construct, &.{ settings_manager, package_manager, is_builtin });
}
fn builtinPredicate(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return mapped(engine, .builtin_factory, if (args.len > 0) args[0] else c.pi_js_undefined());
}
pub fn installGetters(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Getter)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, getCallback, field.name, 0, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn builtin(scope: *Scope, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const constructor_value = try scope.global(name);
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor_value, @intCast(args.len), @constCast(args.ptr))));
}
fn predicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return mapped(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn mapped(engine: *em.Engine, kind: Predicate, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .source_path) {
        const result = try scope.object();
        try scope.put(result, "path", input);
        return c.JS_DupValue(engine.context, result);
    }
    if (kind == .builtin_pair) {
        const pair = try scope.array();
        try scope.index(pair, 0, try scope.get(input, "name"));
        try scope.index(pair, 1, input);
        return c.JS_DupValue(engine.context, pair);
    }
    const is_builtin = !c.JS_IsFunction(engine.context, input) and scope.equal(try scope.get(input, "builtin"), c.pi_js_bool(engine.context, 1));
    return c.pi_js_bool(engine.context, @intFromBool(if (kind == .inline_factory) !is_builtin else is_builtin));
}
fn collection(scope: *Scope, input: c.JSValue, name: [*:0]const u8, kind: Predicate) !c.JSValue {
    const function = try scope.get(input, name);
    const callback = try scope.own(try scope.engine.checked(c.pi_js_function_magic(scope.engine.context, predicate, "", 1, @intFromEnum(kind))));
    return scope.call(function, input, &.{callback});
}
fn assignOption(scope: *Scope, receiver: c.JSValue, options: c.JSValue, destination: [*:0]const u8, key: [*:0]const u8) !void {
    try scope.set(receiver, destination, try scope.get(options, key));
}
fn construct(engine: *em.Engine, target: c.JSValue, args: []const c.JSValue, dependencies: []const c.JSValue) !c.JSValue {
    const loader = try @import("native_class.zig").object(engine, target);
    errdefer engine.freeValue(loader);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (fields) |name| try scope.put(loader, name, c.pi_js_undefined());
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    try scope.set(loader, "cwd", try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined())));
    try scope.set(loader, "agentDir", try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "agentDir"), c.pi_js_undefined(), c.pi_js_undefined())));
    const settings = try scope.get(options, "settingsManager");
    const selected_settings = if (temp.nullish(settings)) value: {
        const create = try scope.get(dependencies[0], "create");
        break :value try scope.call(create, dependencies[0], &.{ try scope.get(loader, "cwd"), try scope.get(loader, "agentDir") });
    } else settings;
    try scope.set(loader, "settingsManager", selected_settings);
    const bus = try scope.get(options, "eventBus");
    try scope.set(loader, "eventBus", if (temp.nullish(bus)) try scope.own(try @import("native_sdk_event_bus.zig").create(engine)) else bus);
    const supplied_factories = try scope.get(options, "extensionFactories");
    const factories = if (temp.nullish(supplied_factories)) try scope.array() else supplied_factories;
    try scope.set(loader, "extensionFactories", try collection(&scope, factories, "filter", .inline_factory));
    const map_constructor = try scope.global("Map");
    // Source passes its imported named ordinary function directly. Keep one
    // constructible function per class binding, including its prototype and
    // stable identity across all constructor calls.
    const builtin_factories = try scope.invoke(factories, "filter", &.{dependencies[2]});
    var map_args = [_]c.JSValue{try collection(&scope, builtin_factories, "map", .builtin_pair)};
    try scope.set(loader, "builtinExtensions", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, map_args.len, &map_args))));
    const package_options = try scope.object();
    inline for (.{ "cwd", "agentDir", "settingsManager" }) |name| try scope.put(package_options, name, try scope.get(loader, name));
    try scope.put(package_options, "builtinExtensions", try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, try scope.invoke(try scope.get(loader, "builtinExtensions"), "keys", &.{}), null)));
    var package_args = [_]c.JSValue{package_options};
    try scope.set(loader, "packageManager", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, dependencies[1], package_args.len, &package_args))));
    inline for (.{ "additionalExtensionPaths", "additionalSkillPaths", "additionalPromptTemplatePaths", "additionalThemePaths" }) |name| {
        const supplied = try scope.get(options, name);
        try scope.set(loader, name, if (temp.nullish(supplied)) try scope.array() else supplied);
    }
    const no_extensions = try scope.get(options, "noExtensions");
    try scope.set(loader, "noExtensions", if (temp.nullish(no_extensions)) c.pi_js_bool(engine.context, 0) else no_extensions);
    const set_constructor = try scope.global("Set");
    var set_args = [_]c.JSValue{try scope.get(options, "disabledBuiltinExtensions")};
    try scope.set(loader, "disabledBuiltinExtensions", try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, set_constructor, set_args.len, &set_args))));
    inline for (.{ "noSkills", "noPromptTemplates", "noThemes", "noContextFiles" }) |name| {
        const supplied = try scope.get(options, name);
        try scope.set(loader, name, if (temp.nullish(supplied)) c.pi_js_bool(engine.context, 0) else supplied);
    }
    try assignOption(&scope, loader, options, "systemPromptSource", "systemPrompt");
    try assignOption(&scope, loader, options, "appendSystemPromptSource", "appendSystemPrompt");
    inline for (.{ "extensionsOverride", "skillsOverride", "promptsOverride", "themesOverride", "agentsFilesOverride", "systemPromptOverride", "appendSystemPromptOverride" }) |name| try assignOption(&scope, loader, options, name, name);
    const extensions = try scope.object();
    try scope.put(extensions, "extensions", try scope.array());
    try scope.put(extensions, "errors", try scope.array());
    try scope.put(extensions, "runtime", try scope.own(try @import("native_sdk_resource_runtime_owners.zig").create(engine)));
    try scope.set(loader, "extensionsResult", extensions);
    inline for (.{ "skills", "skillDiagnostics", "prompts", "promptDiagnostics", "themes", "themeDiagnostics", "agentsFiles", "appendSystemPrompt", "appendSystemPromptSourcePaths", "lastSkillPaths" }) |name| try scope.set(loader, name, try scope.array());
    inline for (.{ "extensionSkillSourceInfos", "extensionPromptSourceInfos", "extensionThemeSourceInfos", "resourceMetadataByPath" }) |name| try scope.set(loader, name, try builtin(&scope, "Map", &.{}));
    try scope.set(loader, "lastPromptPaths", try scope.array());
    try scope.set(loader, "lastThemePaths", try scope.array());
    try scope.set(loader, "loaded", c.pi_js_bool(engine.context, 0));
    return loader;
}
fn getCallback(context: ?*c.JSContext, loader: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return get(engine, loader, @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn get(engine: *em.Engine, loader: c.JSValue, kind: Getter) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = switch (kind) {
        .getExtensions => try scope.get(loader, "extensionsResult"),
        .getSystemPrompt => try scope.get(loader, "systemPrompt"),
        .getAppendSystemPrompt => try scope.get(loader, "appendSystemPrompt"),
        .getSkills, .getPrompts, .getThemes => wrapper: {
            const result = try scope.object();
            const key: [*:0]const u8 = switch (kind) {
                .getSkills => "skills",
                .getPrompts => "prompts",
                else => "themes",
            };
            const diagnostics: [*:0]const u8 = switch (kind) {
                .getSkills => "skillDiagnostics",
                .getPrompts => "promptDiagnostics",
                else => "themeDiagnostics",
            };
            try scope.put(result, key, try scope.get(loader, key));
            try scope.put(result, "diagnostics", try scope.get(loader, diagnostics));
            break :wrapper result;
        },
        .getAgentsFiles => wrapper: {
            const result = try scope.object();
            try scope.put(result, "agentsFiles", try scope.get(loader, "agentsFiles"));
            break :wrapper result;
        },
        .getSystemPromptSource => source: {
            if (!scope.truthy(try scope.get(loader, "systemPromptSourcePath"))) break :source c.pi_js_undefined();
            const result = try scope.object();
            try scope.put(result, "path", try scope.get(loader, "systemPromptSourcePath"));
            break :source result;
        },
        .getAppendSystemPromptSources => try collection(&scope, try scope.get(loader, "appendSystemPromptSourcePaths"), "map", .source_path),
    };
    return c.JS_DupValue(engine.context, value);
}
