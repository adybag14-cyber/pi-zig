//! Concrete actual SDK assembly. The application supplies its real imported
//! namespaces once; this module constructs the ordinary classes and factory
//! over those exact identities. No SDK.Kind model/session default participates.
//! This API is intentionally unselected until the application dependencies and
//! native runtime gates qualify. Shape validation cannot establish provenance.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub const Inputs = struct {
    ai: c.JSValue,
    compat: c.JSValue,
    agent_core: c.JSValue,
    sdk_namespace: c.JSValue,
    /// Completed actual ordinary loader constructor from its own assembly.
    /// Never read the legacy Kind.resource_loader constructor from sdk_namespace.
    resource_loader: c.JSValue,
    typebox_graph: c.JSValue,
    /// Actual native_ai_provider_factories.create result. It contains all42
    /// ordinary factories, all.ts exports and personalizeOpenRouterCatalog.
    provider_factories: c.JSValue,
    paths: c.JSValue,
    path_utilities: c.JSValue,
    filesystem: c.JSValue,
    filesystem_promises: c.JSValue,
    configuration: c.JSValue,
    process: c.JSValue,
    shell: c.JSValue,
    /// The one actual resolver namespace created before auth storage. Composer
    /// and AuthStorage share its cache and exact resolveConfigValue function.
    config_values: c.JSValue,
    management_http: c.JSValue,
    abort: c.JSValue,
    auth_storage: c.JSValue,
    timing: c.JSValue,
};
fn required(scope: *Scope, namespace: c.JSValue, name: [*:0]const u8) !c.JSValue {
    if (!c.JS_IsObject(namespace)) return error.RequiredActualSdkAssemblyNamespace;
    const value = try scope.get(namespace, name);
    if (!c.JS_IsFunction(scope.engine.context, value)) return error.RequiredActualSdkAssemblyFunction;
    return value;
}
fn functions(scope: *Scope, target: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| try scope.put(target, name, try required(scope, namespace, name));
}
/// Returns one assembly graph. Retain this result at the application's module
/// owner, as for its other ESM namespace caches, rather than assembling twice.
pub fn create(engine: *em.Engine, inputs: Inputs) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const imports = try scope.object();
    try functions(&scope, imports, inputs.paths, .{ "join", "dirname", "basename", "parse", "resolve" });
    try functions(&scope, imports, inputs.path_utilities, .{ "normalizePath", "getFileRevision", "resolvePath" });
    try functions(&scope, imports, inputs.configuration, .{ "getAgentDir", "getDefaultSessionDir", "getDocsPath", "getPiUserAgent" });
    try functions(&scope, imports, inputs.filesystem, .{ "existsSync", "mkdirSync", "copyFileSync" });
    try functions(&scope, imports, inputs.filesystem_promises, .{"readFile"});
    try functions(&scope, imports, inputs.abort, .{ "operationSignal", "raceWithAbortSignal" });
    try functions(&scope, imports, inputs.timing, .{"time"});
    try functions(&scope, imports, inputs.agent_core, .{ "Agent", "setDefaultStreamFn" });
    try functions(&scope, imports, inputs.sdk_namespace, .{ "SessionManager", "SettingsManager" });
    if (!c.JS_IsConstructor(engine.context, inputs.resource_loader)) return error.RequiredActualOrdinaryResourceLoader;
    try scope.put(imports, "DefaultResourceLoader", inputs.resource_loader);
    try functions(&scope, imports, inputs.ai, .{ "createModels", "ModelsError", "lazyStream", "normalizeContext", "clampThinkingLevel", "assertChatModel", "assertImageModel", "assertClassifierModel", "assertClassifierInputSupported", "imageErrorResult", "classifierErrorResult" });
    try scope.put(imports, "streamSimple", try required(&scope, inputs.compat, "streamSimple"));
    try scope.put(imports, "process", inputs.process);
    try scope.put(imports, "constants", try scope.get(inputs.filesystem, "constants"));
    try scope.put(imports, "FileAuthStorageBackend", try required(&scope, inputs.auth_storage, "FileAuthStorageBackend"));
    try scope.put(imports, "DefaultAuthStorage", try required(&scope, inputs.auth_storage, "AuthStorage"));
    const text = try scope.own(try @import("native_sdk_model_text_production.zig").create(engine));
    try functions(&scope, imports, text, .{ "stripBom", "stripJsonComments" });
    const config_values = inputs.config_values;
    inline for (.{ "resolveConfigValue", "clearConfigValueCache", "getConfigValueEnvVarNames", "isConfigValueConfigured", "resolveHeadersOrThrow" }) |name| _ = try required(&scope, config_values, name);
    const composer = try scope.object();
    try @import("native_provider_composer_production.zig").install(engine, composer, .{
        .isModelType = try required(&scope, inputs.ai, "isModelType"),
        .lazyStream = try required(&scope, inputs.ai, "lazyStream"),
        .getApiProvider = try required(&scope, inputs.compat, "getApiProvider"),
        .imageErrorResult = try required(&scope, inputs.ai, "imageErrorResult"),
        .classifierErrorResult = try required(&scope, inputs.ai, "classifierErrorResult"),
        .configValues = config_values,
    });
    try functions(&scope, imports, composer, .{ "composeModelProvider", "configuredRequestAuthStatus", "resolveCompatibilityRequestConfig", "resolveConfiguredModelHeaders", "validateExtensionProvider" });
    const virtual = try scope.own(try @import("native_sdk_virtual_models_production.zig").create(engine, inputs.ai));
    try functions(&scope, imports, virtual, .{ "createVirtualModel", "withVirtualModels", "isVirtualModel", "findLatestResponse" });
    const remote = try scope.own(try @import("native_sdk_remote_catalog_provider.zig").create(engine, .{
        .get_model_type = try required(&scope, inputs.ai, "getModelType"),
        .is_model_type = try required(&scope, inputs.ai, "isModelType"),
        .fetch_with_retry = try required(&scope, inputs.management_http, "fetchWithRetry"),
        .get_pi_user_agent = try required(&scope, inputs.configuration, "getPiUserAgent"),
        .version = try scope.get(inputs.configuration, "VERSION"),
    }));
    try functions(&scope, imports, remote, .{ "withRemoteCatalog", "withPersonalizedCatalog" });
    try scope.put(imports, "personalizeOpenRouterCatalog", try required(&scope, inputs.provider_factories, "personalizeOpenRouterCatalog"));
    // Preserve the exact all.ts binding identities and its ordinary namespace
    // export surface. These functions construct real providers on every call.
    const catalog = try scope.object();
    try functions(&scope, catalog, inputs.provider_factories, .{ "radiusProvider", "builtinProviders", "builtinModels", "getBuiltinModel", "getBuiltinImageModel", "getBuiltinClassifierModel", "getBuiltinProviders", "getBuiltinModelDataGeneratedAt", "getBuiltinModels", "getBuiltinImageModels", "getBuiltinClassifierModels", "getAllBuiltinModels" });
    try scope.put(imports, "builtinProviderCatalog", catalog);
    const stores = try scope.own(try @import("native_sdk_models_store_production.zig").create(engine, imports));
    try functions(&scope, imports, stores, .{ "FileModelsStore", "InMemoryCodingAgentModelsStore" });
    const configuration = try scope.own(try @import("native_sdk_model_config_production.zig").create(engine, imports, inputs.typebox_graph));
    try scope.put(imports, "ModelConfig", try required(&scope, configuration, "ModelConfig"));
    const credentials = try scope.own(try @import("native_sdk_runtime_credentials_production.zig").constructor(engine));
    try scope.put(imports, "RuntimeCredentials", credentials);
    const model = try scope.own(try @import("native_sdk_model_runtime_production.zig").exports(engine, imports));
    const model_runtime = try required(&scope, model, "ModelRuntime");
    try @import("native_sdk_model_runtime_create_production.zig").install(engine, model_runtime, imports);
    try scope.put(imports, "ModelRuntime", model_runtime);
    const lifecycle = try scope.own(try @import("native_sdk_agent_session_runtime_production.zig").create(engine, imports));
    try functions(&scope, imports, lifecycle, .{ "AgentSessionRuntime", "assertSessionCwdExists" });
    const helpers = try scope.own(try @import("native_sdk_factory_import_helpers.zig").create(engine, try scope.get(imports, "getDocsPath"), try scope.get(imports, "join")));
    try functions(&scope, imports, helpers, .{ "findInitialModel", "formatNoModelsAvailableMessage", "getToolListError", "isToolModifier", "applyToolModifiers", "createToolNameMatcher" });
    // sdk.ts imports this same virtual-models binding, not a second wrapper.
    try scope.put(imports, "getBranchSelection", try required(&scope, virtual, "getBranchSelection"));
    inline for (.{ "DEFAULT_THINKING_LEVEL", "DEFAULT_TOOL_NAMES" }) |name| try scope.put(imports, name, try scope.get(helpers, name));
    const shared_ai = try scope.own(try @import("native_sdk_session_ai_assembly.zig").create(engine, inputs.compat));
    const factory = try scope.own(try @import("native_sdk_factory_production.zig").compose(engine, .{
        .ai = inputs.ai,
        .compat = inputs.compat,
        .sdk_namespace = inputs.sdk_namespace,
        .shared_ai = shared_ai,
        .install_session_exports = @import("native_sdk_session_platform_composition.zig").install,
    }, imports));
    const exports = try scope.object();
    try js.spreadInto(engine, exports, factory);
    try js.spreadInto(engine, exports, model);
    try js.spreadInto(engine, exports, lifecycle);
    try js.spreadInto(engine, exports, configuration);
    try js.spreadInto(engine, exports, stores);
    try scope.put(exports, "RuntimeCredentials", credentials);
    const graph = try scope.object();
    try scope.put(graph, "exports", exports);
    try scope.put(graph, "imports", imports);
    try scope.put(graph, "ai", inputs.ai);
    try scope.put(graph, "compat", inputs.compat);
    try scope.put(graph, "typebox", inputs.typebox_graph);
    try scope.put(graph, "providerFactories", inputs.provider_factories);
    try scope.put(graph, "builtinProviderCatalog", catalog);
    try scope.put(graph, "sharedAi", shared_ai);
    try scope.put(graph, "configValues", config_values);
    try scope.put(graph, "configuration", inputs.configuration);
    try scope.put(graph, "shell", inputs.shell);
    try scope.put(graph, "timing", inputs.timing);
    try scope.put(graph, "composer", composer);
    try scope.put(graph, "virtual", virtual);
    try scope.put(graph, "remote", remote);
    return c.JS_DupValue(engine.context, graph);
}
/// Explicit application selection after a fully constructed graph exists.
/// Root owns calling this at its module-authority boundary and qualifying it.
/// Preflight captures all replacements before changing any public binding.
pub fn select(engine: *em.Engine, sdk_namespace: c.JSValue, graph: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const replacement = try scope.object();
    try functions(&scope, replacement, try scope.get(graph, "exports"), .{ "ModelRuntime", "AgentSession", "AgentSessionRuntime", "createAgentSession", "createAgentSessionServices", "createAgentSessionFromServices", "createAgentSessionRuntime" });
    try js.spreadInto(engine, sdk_namespace, replacement);
}
