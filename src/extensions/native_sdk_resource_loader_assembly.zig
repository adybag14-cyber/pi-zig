//! Actual ordinary DefaultResourceLoader over required actual package and
//! extension-loader imports. This graph supplies no partial package constructor,
//! empty extension initializer, fake MCP module or substitute chalk renderer.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub const Inputs = struct {
    settings_manager: c.JSValue,
    /// Complete actual DefaultPackageManager, including real transport methods.
    package_manager: c.JSValue,
    configuration: c.JSValue,
    timing: c.JSValue,
    chalk_default: c.JSValue,
    load_extension_from_factory: c.JSValue,
    load_extensions_cached: c.JSValue,
};
pub const declaration_order = .{ "getExtensions", "getSkills", "getPrompts", "getThemes", "getAgentsFiles", "getSystemPrompt", "getSystemPromptSource", "getAppendSystemPrompt", "getAppendSystemPromptSources", "extendResources", "loadProjectTrustExtensions", "reload", "loadCurrentExtensionSet", "resolveExtensionLoadPath", "loadExtensionPaths", "loadFinalExtensionSet", "addExtensionConflictDiagnostics", "mapSkillPath", "normalizeExtensionPaths", "updateSkillsFromPaths", "updatePromptsFromPaths", "updateThemesFromPaths", "applyExtensionSourceInfo", "findSourceInfoForPath", "getDefaultSourceInfoForPath", "mergePaths", "resolveResourcePath", "loadThemes", "loadThemesFromDir", "loadThemeFromFile", "loadExtensionFactories", "dedupePrompts", "dedupeThemes", "discoverSystemPromptFile", "discoverAppendSystemPromptFile", "isUnderPath", "detectExtensionConflicts" };
fn require(scope: *Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const function = try scope.get(namespace, name);
    if (!c.JS_IsFunction(scope.engine.context, function)) return error.RequiredActualResourceLoaderImport;
    return function;
}
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsConstructor(engine.context, inputs.settings_manager) or !c.JS_IsConstructor(engine.context, inputs.package_manager) or !c.JS_IsFunction(engine.context, inputs.load_extension_from_factory) or !c.JS_IsFunction(engine.context, inputs.load_extensions_cached)) return error.RequiredActualResourceLoaderImports;
    // Shape checks expose incomplete composition before constructing a loader;
    // they cannot establish provenance or native transport qualification.
    const package_prototype = try scope.get(inputs.package_manager, "prototype");
    inline for (.{ "setProgressCallback", "resolve", "resolveExtensionSources", "resolvePackageSources", "resolveLocalEntries", "addAutoDiscoveredResources" }) |name| _ = try require(&scope, package_prototype, name);
    const config_dir = try scope.get(inputs.configuration, "CONFIG_DIR_NAME");
    if (!c.JS_IsString(config_dir)) return error.RequiredActualResourceLoaderConfiguration;
    const load_skills = try scope.own(try @import("native_sdk_skill_loader.zig").create(engine, config_dir, try require(&scope, inputs.configuration, "getAgentDir")));
    const load_prompts = try scope.own(try @import("native_sdk_prompt_loader.zig").create(engine, config_dir));
    const context = try scope.own(try @import("native_sdk_resource_context.zig").create(engine, inputs.chalk_default));
    const clear_cache = try scope.own(try @import("native_sdk_extension_cache.zig").createClear(engine));
    const staging = try scope.object();
    try @import("native_sdk_resource_class.zig").installGetters(engine, staging);
    inline for (.{ @import("native_sdk_resource_class_extend.zig"), @import("native_sdk_resource_class_paths.zig"), @import("native_sdk_resource_class_trust.zig"), @import("native_sdk_resource_class_final.zig"), @import("native_sdk_resource_class_theme_update.zig") }) |module| try module.install(engine, staging);
    try @import("native_sdk_resource_class_sources.zig").install(engine, staging, config_dir);
    try @import("native_sdk_resource_class_themes.zig").install(engine, staging, config_dir);
    try @import("native_sdk_resource_class_skill_update.zig").install(engine, staging, load_skills);
    try @import("native_sdk_resource_class_prompt_update.zig").install(engine, staging, load_prompts);
    try @import("native_sdk_resource_class_current.zig").install(engine, staging, inputs.load_extensions_cached);
    try @import("native_sdk_resource_class_factories.zig").install(engine, staging, inputs.load_extension_from_factory);
    try @import("native_sdk_resource_class_load_paths.zig").install(engine, staging, .{ .load_extensions_cached = inputs.load_extensions_cached, .load_extension_from_factory = inputs.load_extension_from_factory });
    try @import("native_sdk_resource_class_reload.zig").install(engine, staging, .{
        .reset_timings = try require(&scope, inputs.timing, "resetTimings"),
        .clear_extension_cache = clear_cache,
        .load_project_context_files = try require(&scope, context, "loadProjectContextFiles"),
        .resolve_prompt_input = try require(&scope, context, "resolvePromptInput"),
    });
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_sdk_resource_class.zig").constructor(engine, prototype, inputs.settings_manager, inputs.package_manager));
    inline for (declaration_order) |name| {
        const atom = c.JS_NewAtom(engine.context, name);
        defer c.JS_FreeAtom(engine.context, atom);
        var descriptor: c.JSPropertyDescriptor = undefined;
        const found = c.JS_GetOwnProperty(engine.context, &descriptor, staging, atom);
        if (found < 0) return js.capture(engine);
        if (found == 0) return error.MissingActualResourceLoaderMethod;
        defer engine.freeValue(descriptor.value);
        defer engine.freeValue(descriptor.getter);
        defer engine.freeValue(descriptor.setter);
        if (!c.JS_IsFunction(engine.context, descriptor.value)) return error.RequiredActualResourceLoaderMethod;
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, descriptor.value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return c.JS_DupValue(engine.context, constructor);
}
