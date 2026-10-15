//! Actual provider constructors. Declarative constants do not infer APIs or auth.
//! All constructor and OAuth callbacks are retained real module values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const helpers = @import("native_ai_auth_helpers.zig");
const auth = @import("native_ai_provider_auth_methods.zig");
const specs = @import("native_ai_provider_specs.zig");
const wrappers = @import("native_ai_provider_wrappers.zig");
const catalog = @import("native_ai_catalog_values.zig");
pub const Dependencies = struct { models: c.JSValue, apis: c.JSValue, oauth: c.JSValue };
pub const api_constructor_names = [_][:0]const u8{ "anthropicMessagesApi", "openAICompletionsApi", "openAIResponsesApi", "openAICodexResponsesApi", "azureOpenAIResponsesApi", "googleGenerativeAIApi", "googleVertexApi", "mistralConversationsApi", "bedrockConverseStreamApi", "piMessagesApi", "openAIDecisionsApi", "typesafeSystemOneApi", "cloudflareWorkersAISystemOneApi", "openrouterImagesApi" };
const oauth_loader_names = [_][:0]const u8{ "loadAnthropicOAuth", "loadOpenAICodexOAuth", "loadOpenAIChatGPTOAuth", "loadGitHubCopilotOAuth", "loadOpenRouterOAuth", "loadKimiCodingOAuth", "loadMetaOAuth", "loadXaiOAuth", "loadRadiusOAuth" };
pub fn create(engine: *v.em.Engine, actual_api_constructors: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return createWithDependencies(engine, .{ .models = try s.own(try @import("native_ai_models_namespace.zig").create(engine)), .apis = actual_api_constructors, .oauth = try s.own(try @import("native_ai_oauth_loader.zig").namespace(engine)) });
}
pub fn createWithDependencies(engine: *v.em.Engine, dependencies: Dependencies) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    inline for (.{ "createProvider", "createModels" }) |name| {
        const function = try s.get(dependencies.models, name);
        if (!c.JS_IsFunction(engine.context, function)) return error.NativeModelsConstructorRequired;
        try s.put(state, name, function);
    }
    const apis = try s.object();
    inline for (api_constructor_names) |name| {
        const function = try s.get(dependencies.apis, name.ptr);
        if (!c.JS_IsFunction(engine.context, function)) return error.NativeProviderApiConstructorRequired;
        try s.put(apis, name.ptr, function);
    }
    try s.put(state, "apis", apis);
    const oauth = try s.object();
    inline for (oauth_loader_names) |name| {
        const function = try s.get(dependencies.oauth, name.ptr);
        if (!c.JS_IsFunction(engine.context, function)) return error.NativeOAuthLoaderRequired;
        try s.put(oauth, name.ptr, function);
    }
    try s.put(state, "oauth", oauth);
    // These two Source auth objects are module lexical constants.
    try s.put(state, "bedrockAuth", try s.own(try auth.create(engine, .bedrock)));
    try s.put(state, "vertexAuth", try s.own(try auth.create(engine, .vertex)));
    const module_exports = try s.object();
    inline for (specs.providers) |spec| {
        const Factory = struct {
            fn call(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                if (comptime std.mem.eql(u8, spec.id, "radius")) return @import("native_ai_provider_radius.zig").create(host, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined());
                return construct(host, roots[0], spec);
            }
        };
        try s.put(module_exports, spec.function.ptr, try s.own(try functions.create(engine, spec.function, 0, Factory.call, &.{state})));
    }
    const Builtins = struct {
        fn providers(host: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const result = try local.array();
            inline for (specs.providers, 0..) |spec, index| try local.index(result, index, try local.call(try local.get(roots[0], spec.function.ptr), c.pi_js_undefined(), &.{}));
            return c.JS_DupValue(host.context, result);
        }
        fn models(host: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = host };
            defer local.deinit();
            const instance = try local.call(roots[1], c.pi_js_undefined(), &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
            const provider_values = try local.call(try local.get(roots[0], "builtinProviders"), c.pi_js_undefined(), &.{});
            var iterator = try v.iterator(&local, provider_values);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |provider| {
                defer host.freeValue(provider);
                const set = try local.get(instance, "setProvider");
                _ = try local.call(set, instance, &.{provider});
            }
            return c.JS_DupValue(host.context, instance);
        }
    };
    try s.put(module_exports, "builtinProviders", try s.own(try functions.create(engine, "builtinProviders", 0, Builtins.providers, &.{module_exports})));
    try s.put(module_exports, "builtinModels", try s.own(try functions.create(engine, "builtinModels", 1, Builtins.models, &.{ module_exports, try s.get(state, "createModels") })));
    const queries = try s.own(try catalog.namespace(engine));
    try s.put(module_exports, "personalizeOpenRouterCatalog", try s.own(try @import("native_ai_provider_openrouter.zig").create(engine)));
    inline for (.{ "getBuiltinModel", "getBuiltinImageModel", "getBuiltinClassifierModel", "getBuiltinProviders", "getBuiltinModelDataGeneratedAt", "getBuiltinModels", "getBuiltinImageModels", "getBuiltinClassifierModels", "getAllBuiltinModels" }) |name| try s.put(module_exports, name, try s.get(queries, name));
    return c.JS_DupValue(engine.context, module_exports);
}
/// Exact providers/all.ts runtime export surface, retaining factory identities.
pub fn all(engine: *v.em.Engine, constructors: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const module_exports = try s.object();
    inline for (.{ "radiusProvider", "builtinProviders", "builtinModels", "getBuiltinModel", "getBuiltinImageModel", "getBuiltinClassifierModel", "getBuiltinProviders", "getBuiltinModelDataGeneratedAt", "getBuiltinModels", "getBuiltinImageModels", "getBuiltinClassifierModels", "getAllBuiltinModels" }) |name| try s.put(module_exports, name, try s.get(constructors, name));
    return c.JS_DupValue(engine.context, module_exports);
}
fn catalogValues(s: *Scope, provider: c.JSValue, kind: specs.CatalogKind) !c.JSValue {
    const object = try s.global("Object");
    const values = try s.get(object, "values");
    const group = try s.own(try switch (kind) {
        .chat => catalog.providerChatCatalog(s.engine, provider),
        .image => catalog.providerImageCatalog(s.engine, provider),
        .classifier => catalog.providerClassifierCatalog(s.engine, provider),
    });
    return s.call(values, object, &.{group});
}
fn modelsFor(s: *Scope, comptime spec: specs.Spec) !c.JSValue {
    const provider = try s.text(spec.id);
    if (spec.catalogs.len == 1) return catalogValues(s, provider, spec.catalogs[0]);
    const result = try s.array();
    var index: u32 = 0;
    inline for (spec.catalogs) |kind| {
        var iterator = try v.iterator(s, try catalogValues(s, provider, kind));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |model| {
            defer s.engine.freeValue(model);
            try s.index(result, index, model);
            index += 1;
        }
    }
    return result;
}
fn authFor(s: *Scope, state: c.JSValue, comptime spec: specs.Spec) !c.JSValue {
    const result = try s.object();
    const api_key = switch (spec.auth) {
        .none => c.pi_js_undefined(),
        .bedrock => try s.get(state, "bedrockAuth"),
        .vertex => try s.get(state, "vertexAuth"),
        .anthropic => try s.own(try auth.create(s.engine, .anthropic)),
        .cloudflare_workers => try s.own(try auth.create(s.engine, .cloudflare_workers)),
        .cloudflare_gateway => try s.own(try auth.create(s.engine, .cloudflare_gateway)),
        .env => value: {
            const names = try s.array();
            inline for (spec.env_vars, 0..) |name, index| try s.index(names, index, try s.text(name));
            break :value try s.own(try helpers.envApiKeyAuth(s.engine, try s.text(spec.auth_label.?), names));
        },
    };
    if (spec.auth != .none) try s.put(result, "apiKey", api_key);
    if (spec.oauth) |flow_spec| {
        const input = try s.object();
        try s.put(input, "name", try s.text(flow_spec.name));
        if (flow_spec.subscription) try s.put(input, "isSubscription", c.JS_NewBool(s.engine.context, true));
        if (flow_spec.label) |label| try s.put(input, "loginLabel", try s.text(label));
        try s.put(input, "load", try s.get(try s.get(state, "oauth"), flow_spec.loader.ptr));
        try s.put(result, "oauth", try s.own(try helpers.lazyOAuth(s.engine, input)));
    }
    return result;
}
fn apiFor(s: *Scope, state: c.JSValue, binding: specs.Api, wrapper: specs.Wrapper, classify: bool) !c.JSValue {
    const operation = try s.call(try s.get(try s.get(state, "apis"), binding.constructor.ptr), c.pi_js_undefined(), &.{});
    return switch (wrapper) {
        .none => operation,
        .cloudflare => s.own(if (classify) try wrappers.classifier(s.engine, operation) else try wrappers.streams(s.engine, .cloudflare, operation)),
        .opencode => s.own(try wrappers.streams(s.engine, .opencode, operation)),
        .azure => s.own(try @import("native_ai_provider_azure.zig").streams(s.engine, operation)),
    };
}
fn putKey(s: *Scope, object: c.JSValue, key: []const u8, value: c.JSValue) !void {
    const atom = try v.js.atom(s.engine, try s.text(key));
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DefinePropertyValue(s.engine.context, object, atom, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E) < 0) return v.js.capture(s.engine);
}
fn construct(engine: *v.em.Engine, state: c.JSValue, comptime spec: specs.Spec) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const constructor = try s.get(state, "createProvider");
    const input = try s.object();
    try s.put(input, "id", try s.text(spec.id));
    try s.put(input, "name", try s.text(spec.name));
    if (spec.base_url) |base| try s.put(input, "baseUrl", try s.text(base));
    try s.put(input, "auth", try authFor(&s, state, spec));
    try s.put(input, "models", try modelsFor(&s, spec));
    if (comptime std.mem.eql(u8, spec.id, "github-copilot")) try s.put(input, "filterModels", try s.own(try wrappers.filter(engine, true)));
    if (comptime std.mem.eql(u8, spec.id, "openai")) try s.put(input, "filterAllModels", try s.own(try wrappers.filter(engine, false)));
    if (spec.api.len > 0) {
        if (spec.api_map) {
            const operations = try s.object();
            inline for (spec.api) |binding| try putKey(&s, operations, binding.id, try apiFor(&s, state, binding, if (spec.wrapper == .azure and !std.mem.eql(u8, binding.id, "openai-completions")) .none else spec.wrapper, false));
            try s.put(input, "api", operations);
        } else try s.put(input, "api", try apiFor(&s, state, spec.api[0], spec.wrapper, false));
    }
    if (spec.images.len > 0) {
        const operations = try s.object();
        inline for (spec.images) |binding| try putKey(&s, operations, binding.id, try apiFor(&s, state, binding, .none, false));
        try s.put(input, "images", operations);
    }
    if (spec.classifiers.len > 0) {
        const operations = try s.object();
        inline for (spec.classifiers) |binding| try putKey(&s, operations, binding.id, try apiFor(&s, state, binding, if (spec.wrapper == .cloudflare) .cloudflare else .none, true));
        try s.put(input, "classifiers", operations);
    }
    return v.js.call(engine, constructor, c.pi_js_undefined(), &.{input});
}
