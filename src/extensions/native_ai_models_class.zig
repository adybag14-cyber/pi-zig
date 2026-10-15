//! Actual ModelsImpl constructor and prototype assembly. All 38 actual method
//! implementations are required; no bound registry or incomplete map is used.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const classes = @import("native_class.zig");
pub const Dependencies = struct {
    methods: c.JSValue,
    credential_store_constructor: c.JSValue,
    models_store_constructor: c.JSValue,
    default_auth_context: c.JSValue,
};
// Declaration order is observable through the actual class prototype.
pub const method_names = .{
    "setProvider",              "deleteProvider",       "clearProviders",        "getProviders",            "getProvider",   "getModels",                "getAllModels",    "getModelsOfType",     "getModel",  "getModelOfType",
    "supersedeProviderRefresh", "beginProviderRefresh", "publishProviderModels", "runProviderRefreshPhase", "refresh",       "resolveRefreshCredential", "readCredential",  "checkProviderAuth",   "checkAuth", "getAuthenticatedProviders",
    "getAvailable",             "getAvailableOfType",   "getAllAvailable",       "getAuth",                 "login",         "logout",                   "requireProvider", "requireChatProvider", "applyAuth", "stream",
    "complete",                 "streamSimple",         "completeSimple",        "streamDeferred",          "fetchDeferred", "cancelDeferred",           "generateImages",  "classify",
};
pub fn create(engine: *v.em.Engine, dependencies: Dependencies) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (!c.JS_IsConstructor(engine.context, dependencies.credential_store_constructor) or !c.JS_IsConstructor(engine.context, dependencies.models_store_constructor) or !c.JS_IsFunction(engine.context, dependencies.default_auth_context)) return error.ActualModelsConstructorDependenciesRequired;
    const prototype = try s.object();
    const constructor = try s.own(try classes.constructor(engine, "ModelsImpl", 1, prototype, construct, &.{ dependencies.credential_store_constructor, dependencies.models_store_constructor, dependencies.default_auth_context }));
    inline for (method_names) |name| {
        const method = try s.get(dependencies.methods, name);
        if (!c.JS_IsFunction(engine.context, method) or c.JS_IsConstructor(engine.context, method)) return error.ActualModelsMethodRequired;
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, c.JS_DupValue(engine.context, method), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    return c.JS_DupValue(engine.context, constructor);
}
fn newMap(s: *Scope) !c.JSValue {
    return s.own(try v.js.builtin(s.engine, "Map", &.{}));
}
fn argument(args: []const c.JSValue, index: usize) c.JSValue {
    return if (args.len > index) args[index] else c.pi_js_undefined();
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.own(try classes.object(engine, target));
    // TypeScript class fields initialize in declaration order before the
    // constructor body reads the caller's options getters.
    try s.put(result, "providers", try newMap(&s));
    inline for (.{ "credentials", "modelsStore", "authContext" }) |name| try s.put(result, name, c.pi_js_undefined());
    inline for (.{ "refreshGenerations", "refreshControllers", "publicationChains" }) |name| try s.put(result, name, try newMap(&s));
    const options = argument(args, 0);
    const credentials = try v.optional(&s, options, "credentials");
    try s.set(result, "credentials", if (v.nullish(credentials)) try s.own(try engine.checked(c.JS_CallConstructor(engine.context, roots[0], 0, null))) else credentials);
    const models_store = try v.optional(&s, options, "modelsStore");
    try s.set(result, "modelsStore", if (v.nullish(models_store)) try s.own(try engine.checked(c.JS_CallConstructor(engine.context, roots[1], 0, null))) else models_store);
    const auth_context = try v.optional(&s, options, "authContext");
    try s.set(result, "authContext", if (v.nullish(auth_context)) try s.call(roots[2], c.pi_js_undefined(), &.{}) else auth_context);
    return c.JS_DupValue(engine.context, result);
}
