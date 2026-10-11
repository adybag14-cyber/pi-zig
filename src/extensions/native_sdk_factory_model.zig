//! Factory initial-model subset of the original findInitialModel algorithm.
//! Provider defaults are copied from model-resolver.ts SHA D9C26FAA20B3173B5E567B00C5635E2BA5F8501C54CB3AC126610EEA4FF6D5A8.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const defaults = .{
    .{ "amazon-bedrock", "us.anthropic.claude-opus-4-6-v1" },
    .{ "ant-ling", "Ring-2.6-1T" },
    .{ "anthropic", "claude-opus-4-8" },
    .{ "openai", "gpt-5.5" },
    .{ "azure", "gpt-5.4" },
    .{ "openai-codex", "gpt-6.1-sol" },
    .{ "radius", "balanced" },
    .{ "nvidia", "nvidia/nemotron-3-ultra-550b-a55b" },
    .{ "deepseek", "deepseek-v4-pro" },
    .{ "google", "gemini-3.1-pro-preview" },
    .{ "google-vertex", "gemini-3.1-pro-preview" },
    .{ "github-copilot", "gpt-5.4" },
    .{ "openrouter", "moonshotai/kimi-k2.6" },
    .{ "vercel-ai-gateway", "zai/glm-5.1" },
    .{ "xai", "grok-4.7" },
    .{ "groq", "openai/gpt-oss-120b" },
    .{ "cerebras", "gpt-oss-120b" },
    .{ "zai", "glm-5.3" },
    .{ "zai-coding-cn", "glm-5.3" },
    .{ "mistral", "devstral-medium-latest" },
    .{ "minimax", "MiniMax-M2.7" },
    .{ "minimax-cn", "MiniMax-M2.7" },
    .{ "moonshotai", "kimi-k2.6" },
    .{ "moonshotai-cn", "kimi-k2.6" },
    .{ "huggingface", "moonshotai/Kimi-K2.6" },
    .{ "fireworks", "accounts/fireworks/models/kimi-k3" },
    .{ "together", "moonshotai/Kimi-K3" },
    .{ "baseten", "zai-org/GLM-5.2" },
    .{ "opencode", "kimi-k2.6" },
    .{ "opencode-go", "kimi-k3" },
    .{ "kimi-coding", "kimi-for-coding" },
    .{ "meta", "muse-spark-1.3" },
    .{ "cloudflare-workers-ai", "@cf/moonshotai/kimi-k2.6" },
    .{ "cloudflare-ai-gateway", "workers-ai/@cf/moonshotai/kimi-k2.6" },
    .{ "qwen-token-plan", "qwen3.7-max" },
    .{ "qwen-token-plan-cn", "qwen3.7-max" },
    .{ "qwen-token-plan-individual", "qwen3.8-max" },
    .{ "xiaomi", "mimo-v2.5-pro" },
    .{ "xiaomi-token-plan-cn", "mimo-v2.5-pro" },
    .{ "xiaomi-token-plan-ams", "mimo-v2.5-pro" },
    .{ "xiaomi-token-plan-sgp", "mimo-v2.5-pro" },
};
pub fn select(engine: *em.Engine, runtime: c.JSValue, settings: c.JSValue) !c.JSValue {
    const provider = try js.invoke(engine, settings, "getDefaultProvider", &.{});
    defer engine.freeValue(provider);
    const id = try js.invoke(engine, settings, "getDefaultModel", &.{});
    defer engine.freeValue(id);
    if (c.JS_ToBool(engine.context, provider) == 1 and c.JS_ToBool(engine.context, id) == 1) {
        const candidate = try js.invoke(engine, runtime, "getModel", &.{ provider, id });
        defer engine.freeValue(candidate);
        if (c.JS_ToBool(engine.context, candidate) == 1) {
            const checker = try js.get(engine, runtime, "hasConfiguredAuth");
            defer engine.freeValue(checker);
            const actual_provider = try js.get(engine, candidate, "provider");
            defer engine.freeValue(actual_provider);
            const configured = try js.call(engine, checker, runtime, &.{actual_provider});
            defer engine.freeValue(configured);
            if (c.JS_ToBool(engine.context, configured) == 1) return c.JS_DupValue(engine.context, candidate);
        }
    }
    const snapshot = try js.invoke(engine, runtime, "getAvailableSnapshot", &.{});
    defer engine.freeValue(snapshot);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    const available = try js.collect(engine, snapshot, symbol);
    defer engine.freeValue(available);
    const length = try js.get(engine, available, "length");
    defer engine.freeValue(length);
    const positive = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, length, c.JS_NewInt32(engine.context, 0)));
    defer engine.freeValue(positive);
    if (c.JS_ToBool(engine.context, positive) != 1) return c.pi_js_undefined();
    inline for (defaults) |entry| {
        const provider_name = try sdk.text(engine, entry[0]);
        defer engine.freeValue(provider_name);
        const model_id = try sdk.text(engine, entry[1]);
        defer engine.freeValue(model_id);
        var roots = [_]c.JSValue{ provider_name, model_id };
        const predicate = try engine.checked(c.JS_NewCFunctionData2(engine.context, matches, "", 1, 0, roots.len, &roots));
        defer engine.freeValue(predicate);
        const found = try js.invoke(engine, available, "find", &.{predicate});
        if (c.JS_ToBool(engine.context, found) == 1) return found;
        engine.freeValue(found);
    }
    return engine.checked(c.JS_GetPropertyUint32(engine.context, available, 0));
}
fn matches(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const row = if (argc > 0) argv[0] else c.pi_js_undefined();
    const provider = js.get(engine, row, "provider") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(provider);
    if (!c.JS_IsStrictEqual(engine.context, provider, roots[0])) return c.pi_js_bool(context, 0);
    const id = js.get(engine, row, "id") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(id);
    return c.pi_js_bool(context, @intFromBool(c.JS_IsStrictEqual(engine.context, id, roots[1])));
}
