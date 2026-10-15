//! Azure endpoint/version/deployment values resolved with the caller's live env.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
fn environment(scope: *Scope, dependencies: c.JSValue, options: c.JSValue, key: []const u8) !c.JSValue {
    return scope.invoke(try scope.get(dependencies, "env"), "getProviderEnvValue", &.{ try scope.text(key), try v.optional(scope, options, "env") });
}
fn configured(scope: *Scope, dependencies: c.JSValue, options: c.JSValue, key: [*:0]const u8, env_key: []const u8) !c.JSValue {
    const own = try v.optional(scope, options, key);
    return if (scope.truthy(own)) own else environment(scope, dependencies, options, env_key);
}
pub fn resolve(scope: *Scope, dependencies: c.JSValue, model: c.JSValue, options: c.JSValue) !c.JSValue {
    const option_base = try v.optional(scope, options, "azureBaseUrl");
    var base = if (v.nullish(option_base)) c.pi_js_undefined() else try scope.invoke(option_base, "trim", &.{});
    if (!scope.truthy(base)) {
        const env_base = try environment(scope, dependencies, options, "AZURE_OPENAI_BASE_URL");
        base = if (v.nullish(env_base)) c.pi_js_undefined() else try scope.invoke(env_base, "trim", &.{});
    }
    const resource = try configured(scope, dependencies, options, "azureResourceName", "AZURE_OPENAI_RESOURCE_NAME");
    if (!scope.truthy(base) and scope.truthy(resource)) base = try scope.concat(try scope.concat(try scope.text("https://"), try scope.stringify(resource)), try scope.text(".openai.azure.com/openai/v1"));
    if (!scope.truthy(base)) base = try scope.get(model, "baseUrl");
    if (!scope.truthy(base)) return v.errorText(scope, try scope.text("Azure OpenAI base URL is required. Set AZURE_OPENAI_BASE_URL or AZURE_OPENAI_RESOURCE_NAME, or pass azureBaseUrl, azureResourceName, or model.baseUrl."));
    const trimmed = try scope.invoke(try scope.invoke(base, "trim", &.{}), "replace", &.{ try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")})), try scope.text("") });
    const generation = scope.engine.native_allocation_generation;
    const url = scope.own(v.js.builtin(scope.engine, "URL", &.{trimmed}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return v.errorText(scope, try scope.concat(try scope.text("Invalid Azure OpenAI base URL: "), try scope.stringify(base)));
    }) catch |err| return err;
    const host = try scope.get(url, "hostname");
    const path = try scope.invoke(try scope.get(url, "pathname"), "replace", &.{ try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")})), try scope.text("") });
    const azure = scope.truthy(try scope.invoke(host, "endsWith", &.{try scope.text(".openai.azure.com")})) or scope.truthy(try scope.invoke(host, "endsWith", &.{try scope.text(".cognitiveservices.azure.com")})) or scope.truthy(try scope.invoke(host, "endsWith", &.{try scope.text(".ai.azure.com")}));
    if (azure and (try v.eq(scope, path, "") or try v.eq(scope, path, "/") or try v.eq(scope, path, "/openai") or try v.eq(scope, path, "/openai/v1/responses"))) {
        try scope.set(url, "pathname", try scope.text("/openai/v1"));
        try scope.set(url, "search", try scope.text(""));
    }
    const result = try scope.object();
    try scope.put(result, "baseUrl", try scope.invoke(try scope.invoke(url, "toString", &.{}), "replace", &.{ try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")})), try scope.text("") }));
    const version = try configured(scope, dependencies, options, "azureApiVersion", "AZURE_OPENAI_API_VERSION");
    try scope.put(result, "apiVersion", if (scope.truthy(version)) version else try scope.text("v1"));
    var deployment = try v.optional(scope, options, "azureDeploymentName");
    if (!scope.truthy(deployment)) {
        deployment = try scope.get(model, "id");
        const raw = try environment(scope, dependencies, options, "AZURE_OPENAI_DEPLOYMENT_NAME_MAP");
        if (scope.truthy(raw)) {
            var entries = try v.iterator(scope, try scope.invoke(raw, "split", &.{try scope.text(",")}));
            defer entries.deinit();
            errdefer entries.closePreserving();
            while (try entries.next()) |entry| {
                defer scope.engine.freeValue(entry);
                const parts = try scope.invoke(try scope.invoke(entry, "trim", &.{}), "split", &.{ try scope.text("="), c.JS_NewInt32(scope.engine.context, 2) });
                const key = try v.at(scope, parts, 0);
                const value = try v.at(scope, parts, 1);
                if (!scope.truthy(key) or !scope.truthy(value)) continue;
                if (scope.equal(try scope.invoke(key, "trim", &.{}), try scope.get(model, "id"))) deployment = try scope.invoke(value, "trim", &.{});
            }
        }
        if (!scope.truthy(deployment)) deployment = try scope.get(model, "id");
    }
    try scope.put(result, "deployment", deployment);
    return result;
}
pub fn endpoint(scope: *Scope, config: c.JSValue) !c.JSValue {
    const url = try scope.own(try v.js.builtin(scope.engine, "URL", &.{try scope.get(config, "baseUrl")}));
    const path = try scope.invoke(try scope.get(url, "pathname"), "replace", &.{ try scope.own(try v.js.builtin(scope.engine, "RegExp", &.{try scope.text("/+$")})), try scope.text("") });
    try scope.set(url, "pathname", try scope.concat(path, try scope.text("/responses")));
    _ = try scope.invoke(try scope.get(url, "searchParams"), "set", &.{ try scope.text("api-version"), try scope.get(config, "apiVersion") });
    try scope.set(url, "hash", try scope.text(""));
    return scope.invoke(url, "toString", &.{});
}
