//! Original OpenAI-completions compatibility detection and explicit overrides.
//! Private provider implementation component, not a transport qualification.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const c = em.c;
fn equal(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn includes(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.truthy(try scope.invoke(value, "includes", &.{try scope.text(text)}));
}
fn starts(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.truthy(try scope.invoke(value, "startsWith", &.{try scope.text(text)}));
}
fn flag(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: bool) !void {
    return scope.put(target, name, c.pi_js_bool(scope.engine.context, @intFromBool(value)));
}
fn detect(scope: *Scope, model: c.JSValue) !c.JSValue {
    const provider = try scope.get(model, "provider");
    const base = try scope.get(model, "baseUrl");
    const zai = try equal(scope, provider, "zai") or try equal(scope, provider, "zai-coding-cn") or try includes(scope, base, "api.z.ai") or try includes(scope, base, "open.bigmodel.cn");
    const together = try equal(scope, provider, "together") or try includes(scope, base, "api.together.ai") or try includes(scope, base, "api.together.xyz");
    const moonshot = try equal(scope, provider, "moonshotai") or try equal(scope, provider, "moonshotai-cn") or try includes(scope, base, "api.moonshot.");
    const openrouter = try equal(scope, provider, "openrouter") or try includes(scope, base, "openrouter.ai");
    const cloudflare_workers = try equal(scope, provider, "cloudflare-workers-ai") or try includes(scope, base, "api.cloudflare.com");
    const cloudflare_gateway = try equal(scope, provider, "cloudflare-ai-gateway") or try includes(scope, base, "gateway.ai.cloudflare.com");
    const nvidia = try equal(scope, provider, "nvidia") or try includes(scope, base, "integrate.api.nvidia.com");
    const ant_ling = try equal(scope, provider, "ant-ling") or try includes(scope, base, "api.ant-ling.com");
    const cerebras = try equal(scope, provider, "cerebras") or try includes(scope, base, "cerebras.ai");
    const deepseek = try equal(scope, provider, "deepseek") or try includes(scope, try scope.invoke(base, "toLowerCase", &.{}), "deepseek.com");
    const nonstandard = nvidia or cerebras or try equal(scope, provider, "xai") or try includes(scope, base, "api.x.ai") or together or try includes(scope, base, "chutes.ai") or deepseek or zai or moonshot or try equal(scope, provider, "opencode") or try includes(scope, base, "opencode.ai") or cloudflare_workers or cloudflare_gateway or ant_ling;
    const max_tokens = try includes(scope, base, "chutes.ai") or deepseek or moonshot or cloudflare_gateway or together or nvidia or ant_ling or zai;
    const grok = try equal(scope, provider, "xai") or try includes(scope, base, "api.x.ai");
    const developer_model = openrouter and (try starts(scope, try scope.get(model, "id"), "anthropic/") or try starts(scope, try scope.get(model, "id"), "openai/"));
    const cache_format = if (try equal(scope, provider, "openrouter") and try starts(scope, try scope.get(model, "id"), "anthropic/")) try scope.text("anthropic") else c.pi_js_undefined();
    const result = try scope.object();
    try flag(scope, result, "supportsStore", !nonstandard);
    try flag(scope, result, "supportsDeveloperRole", developer_model or (!nonstandard and !openrouter));
    try flag(scope, result, "supportsReasoningEffort", !grok and !zai and !moonshot and !together and !cloudflare_gateway and !nvidia and !ant_ling);
    try flag(scope, result, "supportsUsageInStreaming", true);
    try flag(scope, result, "supportsFinishReason", true);
    try scope.put(result, "maxTokensField", try scope.text(if (max_tokens) "max_tokens" else "max_completion_tokens"));
    inline for (.{ "requiresToolResultName", "requiresAssistantAfterToolResult", "requiresThinkingAsText" }) |name| try flag(scope, result, name, false);
    try flag(scope, result, "requiresReasoningContentOnAssistantMessages", deepseek);
    try scope.put(result, "thinkingFormat", try scope.text(if (deepseek) "deepseek" else if (zai) "zai" else if (together) "together" else if (ant_ling) "ant-ling" else if (openrouter) "openrouter" else "openai"));
    inline for (.{ "openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs" }) |name| try scope.put(result, name, try scope.object());
    inline for (.{ "zaiToolStream", "supportsThinkingTokenBudget", "supportsStrictMode", "supportsOpenAIGrammarTools", "supportsMidConvoSystemMessages", "supportsMidConvoToolAdditions" }) |name| try flag(scope, result, name, false);
    try scope.put(result, "thinkingTokenBudgetField", c.pi_js_undefined());
    try scope.put(result, "cacheControlFormat", cache_format);
    try flag(scope, result, "sendSessionAffinityHeaders", openrouter);
    try scope.put(result, "sessionAffinityFormat", try scope.text(if (openrouter) "openrouter" else "openai"));
    try flag(scope, result, "supportsLongCacheRetention", !(together or cloudflare_workers or cloudflare_gateway or nvidia or ant_ling));
    return result;
}
pub fn resolve(engine: *em.Engine, model: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const detected = try detect(&scope, model);
    if (!scope.truthy(try scope.get(model, "compat"))) return c.JS_DupValue(engine.context, detected);
    const result = try scope.object();
    inline for (.{ "supportsStore", "supportsDeveloperRole", "supportsReasoningEffort", "supportsUsageInStreaming", "supportsFinishReason", "maxTokensField", "requiresToolResultName", "requiresAssistantAfterToolResult", "requiresThinkingAsText", "requiresReasoningContentOnAssistantMessages", "thinkingFormat", "openRouterRouting", "vercelGatewayRouting", "chatTemplateKwargs", "chatTemplateArgs", "zaiToolStream", "supportsThinkingTokenBudget", "thinkingTokenBudgetField", "supportsStrictMode", "supportsOpenAIGrammarTools", "supportsMidConvoSystemMessages", "supportsMidConvoToolAdditions", "cacheControlFormat", "sendSessionAffinityHeaders", "sessionAffinityFormat", "supportsLongCacheRetention" }) |name| {
        // Source reads model.compat separately for each property; retain those
        // getter side effects instead of capturing a convenient snapshot.
        const configured = try scope.get(try scope.get(model, "compat"), name);
        try scope.put(result, name, if (temp.nullish(configured)) (if (comptime std.mem.eql(u8, name, "openRouterRouting")) try scope.object() else try scope.get(detected, name)) else configured);
    }
    try scope.put(result, "vllmPriority", try scope.get(try scope.get(model, "compat"), "vllmPriority"));
    return c.JS_DupValue(engine.context, result);
}
const std = @import("std");
