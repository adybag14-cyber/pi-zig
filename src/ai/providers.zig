//! Runtime provider identities, native transport mapping, model metadata, and credentials.
//!
//! Unlike the earlier structural port, named OpenAI-compatible providers are kept as
//! distinct provider identities. This is required for Pi-compatible `provider/model`
//! resolution: `groq/foo` and `openrouter/foo` must never collapse to the same provider.
const std = @import("std");
const config = @import("../config.zig");
const thinking = @import("thinking.zig");
const api_mod = @import("api.zig");
const metadata = @import("request_metadata.zig");
const catalog_generated = @import("catalog_generated.zig");

pub const Provider = enum {
    openai,
    anthropic,
    google,
    mock,

    // Providers served by the native OpenAI-compatible transport today.
    groq,
    together,
    deepseek,
    ollama,
    openrouter,
    xai,
    mistral,
    fireworks,
    cerebras,
    lmstudio,
    vllm,
    perplexity,
    nvidia,
    radius,
    cloudflare_workers_ai,
    cloudflare_ai_gateway,
    amazon_bedrock,
    github_copilot,
    kimi_coding,
    baseten,
    qwen_token_plan,
    qwen_token_plan_cn,
    qwen_token_plan_individual,
    ant_ling,
    azure_openai_responses,
    google_vertex,
    huggingface,
    minimax,
    minimax_cn,
    moonshotai,
    moonshotai_cn,
    opencode,
    opencode_go,
    openai_codex,
    vercel_ai_gateway,
    xiaomi,
    xiaomi_token_plan_ams,
    xiaomi_token_plan_cn,
    xiaomi_token_plan_sgp,
    zai,
    zai_coding_cn,

    pub fn fromString(s: []const u8) ?Provider {
        if (std.ascii.eqlIgnoreCase(s, "amazon-bedrock")) return .amazon_bedrock;
        if (std.ascii.eqlIgnoreCase(s, "cloudflare-workers-ai")) return .cloudflare_workers_ai;
        if (std.ascii.eqlIgnoreCase(s, "cloudflare-ai-gateway")) return .cloudflare_ai_gateway;
        if (std.ascii.eqlIgnoreCase(s, "github-copilot")) return .github_copilot;
        if (std.ascii.eqlIgnoreCase(s, "kimi-coding")) return .kimi_coding;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan")) return .qwen_token_plan;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan-cn")) return .qwen_token_plan_cn;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan-individual")) return .qwen_token_plan_individual;
        if (std.ascii.eqlIgnoreCase(s, "ant-ling")) return .ant_ling;
        if (std.ascii.eqlIgnoreCase(s, "azure-openai-responses")) return .azure_openai_responses;
        if (std.ascii.eqlIgnoreCase(s, "google-vertex")) return .google_vertex;
        if (std.ascii.eqlIgnoreCase(s, "minimax-cn")) return .minimax_cn;
        if (std.ascii.eqlIgnoreCase(s, "moonshotai-cn")) return .moonshotai_cn;
        if (std.ascii.eqlIgnoreCase(s, "opencode-go")) return .opencode_go;
        if (std.ascii.eqlIgnoreCase(s, "openai-codex")) return .openai_codex;
        if (std.ascii.eqlIgnoreCase(s, "vercel-ai-gateway")) return .vercel_ai_gateway;
        if (std.ascii.eqlIgnoreCase(s, "xiaomi-token-plan-ams")) return .xiaomi_token_plan_ams;
        if (std.ascii.eqlIgnoreCase(s, "xiaomi-token-plan-cn")) return .xiaomi_token_plan_cn;
        if (std.ascii.eqlIgnoreCase(s, "xiaomi-token-plan-sgp")) return .xiaomi_token_plan_sgp;
        if (std.ascii.eqlIgnoreCase(s, "zai-coding-cn")) return .zai_coding_cn;
        inline for (std.meta.fields(Provider)) |field| {
            if (std.ascii.eqlIgnoreCase(s, field.name)) return @enumFromInt(field.value);
        }
        if (std.ascii.eqlIgnoreCase(s, "gemini")) return .google;
        if (std.ascii.eqlIgnoreCase(s, "llama")) return .ollama;
        if (std.ascii.eqlIgnoreCase(s, "openai_compat") or std.ascii.eqlIgnoreCase(s, "compat")) return .ollama;
        return null;
    }

    pub fn name(self: Provider) []const u8 {
        return switch (self) {
            .amazon_bedrock => "amazon-bedrock",
            .cloudflare_workers_ai => "cloudflare-workers-ai",
            .cloudflare_ai_gateway => "cloudflare-ai-gateway",
            .github_copilot => "github-copilot",
            .kimi_coding => "kimi-coding",
            .qwen_token_plan => "qwen-token-plan",
            .qwen_token_plan_cn => "qwen-token-plan-cn",
            .qwen_token_plan_individual => "qwen-token-plan-individual",
            .ant_ling => "ant-ling",
            .azure_openai_responses => "azure-openai-responses",
            .google_vertex => "google-vertex",
            .minimax_cn => "minimax-cn",
            .moonshotai_cn => "moonshotai-cn",
            .opencode_go => "opencode-go",
            .openai_codex => "openai-codex",
            .vercel_ai_gateway => "vercel-ai-gateway",
            .xiaomi_token_plan_ams => "xiaomi-token-plan-ams",
            .xiaomi_token_plan_cn => "xiaomi-token-plan-cn",
            .xiaomi_token_plan_sgp => "xiaomi-token-plan-sgp",
            .zai_coding_cn => "zai-coding-cn",
            else => @tagName(self),
        };
    }

    /// Native wire/API implementation used for requests.
    pub fn transport(self: Provider) Provider {
        return switch (self) {
            .groq, .together, .deepseek, .ollama, .openrouter, .xai, .mistral, .fireworks, .cerebras, .lmstudio, .vllm, .perplexity, .nvidia, .cloudflare_workers_ai, .cloudflare_ai_gateway, .github_copilot, .baseten, .qwen_token_plan, .qwen_token_plan_cn, .qwen_token_plan_individual, .ant_ling, .azure_openai_responses, .huggingface, .moonshotai, .moonshotai_cn, .opencode, .opencode_go, .openai_codex, .xiaomi, .xiaomi_token_plan_ams, .xiaomi_token_plan_cn, .xiaomi_token_plan_sgp, .zai, .zai_coding_cn => .openai,
            .kimi_coding, .minimax, .minimax_cn, .vercel_ai_gateway => .anthropic,
            .google_vertex => .google,
            else => self,
        };
    }

    pub fn isOpenAICompatible(self: Provider) bool {
        return self.transport() == .openai and self != .openai;
    }
};

pub const ModelCostRates = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
};

pub const ModelCostTier = struct {
    input_tokens_above: u64,
    input: f64,
    output: f64,
    cache_read: f64,
    cache_write: f64,
};

pub const ModelCost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    tiers: []const ModelCostTier = &.{},
};

pub const ModelInfo = struct {
    /// Native request transport/provider implementation.
    provider: Provider,
    /// Public provider identity. Null means `provider.name()` for built-ins.
    /// Custom models keep arbitrary upstream provider IDs here while reusing
    /// one of the native transports above.
    provider_id: ?[]const u8 = null,
    id: []const u8,
    display: []const u8,
    /// Effective API endpoint. Null selects the native provider default.
    base_url: ?[]const u8 = null,
    reasoning: bool = false,
    thinking_level_map: ?thinking.ThinkingLevelMap = null,
    input_text: bool = true,
    input_image: bool = false,
    context_window: u64 = 0,
    max_tokens: u64 = 0,
    cost: ModelCost = .{},
    /// API protocol can differ between models under the same public provider.
    api: ?api_mod.Api = null,
    /// Generated/provider-owned request compatibility defaults for this model.
    compat: metadata.Compat = .{},
    /// Generated model-scoped request headers and sampling defaults.
    headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},

    pub fn apiKind(self: ModelInfo) api_mod.Api {
        if (self.api) |value| return value;
        return switch (self.provider.transport()) {
            .anthropic => .anthropic_messages,
            .google => .google_generative_ai,
            .amazon_bedrock => .bedrock_converse_stream,
            else => .openai_completions,
        };
    }

    pub fn providerName(self: ModelInfo) []const u8 {
        return self.provider_id orelse self.provider.name();
    }

    pub fn supportedThinkingLevels(self: ModelInfo, out: *[7]thinking.ThinkingLevel) []const thinking.ThinkingLevel {
        return thinking.supported(self.reasoning, self.thinking_level_map, out);
    }

    pub fn clampThinkingLevel(self: ModelInfo, requested: thinking.ThinkingLevel) thinking.ThinkingLevel {
        return thinking.clamp(self.reasoning, self.thinking_level_map, requested);
    }
};

const map_all_efforts = thinking.ThinkingLevelMap{
    .off = .{ .mapped = "none" },
    .minimal = .{ .mapped = "minimal" },
    .low = .{ .mapped = "low" },
    .medium = .{ .mapped = "medium" },
    .high = .{ .mapped = "high" },
    .xhigh = .{ .mapped = "xhigh" },
    .max = .{ .mapped = "max" },
};

const map_toggle_high = thinking.ThinkingLevelMap{
    .off = .{ .mapped = "off" },
    .minimal = .unsupported,
    .low = .unsupported,
    .medium = .unsupported,
    .high = .{ .mapped = "high" },
    .xhigh = .unsupported,
    .max = .unsupported,
};

const map_none_low_high_max = thinking.ThinkingLevelMap{
    .off = .{ .mapped = "none" },
    .minimal = .unsupported,
    .low = .{ .mapped = "low" },
    .medium = .unsupported,
    .high = .{ .mapped = "high" },
    .xhigh = .unsupported,
    .max = .{ .mapped = "max" },
};

const map_none_high_max = thinking.ThinkingLevelMap{
    .off = .{ .mapped = "none" },
    .minimal = .unsupported,
    .low = .unsupported,
    .medium = .unsupported,
    .high = .{ .mapped = "high" },
    .xhigh = .unsupported,
    .max = .{ .mapped = "max" },
};

const map_high_max = thinking.ThinkingLevelMap{
    .minimal = .unsupported,
    .low = .unsupported,
    .medium = .unsupported,
    .high = .{ .mapped = "high" },
    .xhigh = .unsupported,
    .max = .{ .mapped = "max" },
};

const map_qwen38 = thinking.ThinkingLevelMap{
    .minimal = .unsupported,
    .low = .{ .mapped = "low" },
    .medium = .{ .mapped = "medium" },
    .high = .unsupported,
    .xhigh = .{ .mapped = "xhigh" },
    .max = .unsupported,
};

const baseten_base_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = false,
    .supports_usage_in_streaming = true,
    .max_tokens_field = .max_tokens,
    .supports_strict_mode = true,
    .supports_long_cache_retention = false,
};

const baseten_openai_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = true,
    .supports_usage_in_streaming = true,
    .max_tokens_field = .max_tokens,
    .supports_strict_mode = true,
    .supports_long_cache_retention = false,
    .thinking_format = .openai,
};

const baseten_template_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = false,
    .supports_usage_in_streaming = true,
    .max_tokens_field = .max_tokens,
    .supports_strict_mode = true,
    .supports_long_cache_retention = false,
    .thinking_format = .baseten,
};

const baseten_template_effort_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = true,
    .supports_usage_in_streaming = true,
    .max_tokens_field = .max_tokens,
    .supports_strict_mode = true,
    .supports_long_cache_retention = false,
    .thinking_format = .baseten,
};

const qwen_no_effort_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = false,
    .thinking_format = .qwen,
};

const qwen_effort_compat = metadata.Compat{
    .supports_store = false,
    .supports_developer_role = false,
    .supports_reasoning_effort = true,
    .thinking_format = .qwen,
};

/// Exact built-in pi-ai 0.84.1 catalog plus native-only local/runtime entries.
/// The generated rows retain provider identity while selecting a native API transport per model.
const native_extra_models = [_]ModelInfo{
    .{ .provider = .radius, .api = .pi_messages, .id = "auto", .display = "Radius Auto", .base_url = "https://radius.pi.dev", .context_window = 128_000, .max_tokens = 16_384 },
    .{ .provider = .ollama, .id = "llama3.2", .display = "Ollama llama3.2", .base_url = "http://127.0.0.1:11434/v1" },
    .{ .provider = .lmstudio, .id = "local-model", .display = "LM Studio local model", .base_url = "http://127.0.0.1:1234/v1" },
    .{ .provider = .vllm, .id = "local-model", .display = "vLLM local model", .base_url = "http://127.0.0.1:8000/v1" },
    .{ .provider = .perplexity, .id = "sonar", .display = "Perplexity Sonar", .base_url = "https://api.perplexity.ai" },
    .{ .provider = .mock, .id = "mock", .display = "Mock (scripted)", .context_window = 1_000_000, .max_tokens = 1_000_000 },
};

pub const known_models = catalog_generated.rows(ModelInfo) ++ native_extra_models;

pub fn credentialEnvName(provider: Provider) ?[]const u8 {
    return switch (provider) {
        .openai => config.ENV_OPENAI_KEY,
        .anthropic => config.ENV_ANTHROPIC_KEY,
        .google => config.ENV_GOOGLE_KEY,
        .groq => "GROQ_API_KEY",
        .together => "TOGETHER_API_KEY",
        .deepseek => "DEEPSEEK_API_KEY",
        .openrouter => "OPENROUTER_API_KEY",
        .xai => "XAI_API_KEY",
        .mistral => "MISTRAL_API_KEY",
        .fireworks => "FIREWORKS_API_KEY",
        .cerebras => "CEREBRAS_API_KEY",
        .perplexity => "PERPLEXITY_API_KEY",
        .nvidia => "NVIDIA_API_KEY",
        .radius => "RADIUS_API_KEY",
        .cloudflare_workers_ai, .cloudflare_ai_gateway => "CLOUDFLARE_API_KEY",
        .amazon_bedrock => "AWS_BEARER_TOKEN_BEDROCK",
        .github_copilot => "COPILOT_GITHUB_TOKEN",
        .kimi_coding => "KIMI_API_KEY",
        .baseten => "BASETEN_API_KEY",
        .qwen_token_plan, .qwen_token_plan_individual => "QWEN_TOKEN_PLAN_API_KEY",
        .qwen_token_plan_cn => "QWEN_TOKEN_PLAN_CN_API_KEY",
        .ant_ling => "ANT_LING_API_KEY",
        .azure_openai_responses => "AZURE_OPENAI_API_KEY",
        .google_vertex => "GOOGLE_CLOUD_API_KEY",
        .huggingface => "HF_TOKEN",
        .minimax => "MINIMAX_API_KEY",
        .minimax_cn => "MINIMAX_CN_API_KEY",
        .moonshotai, .moonshotai_cn => "MOONSHOT_API_KEY",
        .opencode, .opencode_go => "OPENCODE_API_KEY",
        .openai_codex => null,
        .vercel_ai_gateway => "AI_GATEWAY_API_KEY",
        .xiaomi => "XIAOMI_API_KEY",
        .xiaomi_token_plan_ams => "XIAOMI_TOKEN_PLAN_AMS_API_KEY",
        .xiaomi_token_plan_cn => "XIAOMI_TOKEN_PLAN_CN_API_KEY",
        .xiaomi_token_plan_sgp => "XIAOMI_TOKEN_PLAN_SGP_API_KEY",
        .zai => "ZAI_API_KEY",
        .zai_coding_cn => "ZAI_CODING_CN_API_KEY",
        .ollama, .lmstudio, .vllm, .mock => null,
    };
}

/// Resolve API key for a provider from explicit key, generic PI key, or provider env.
pub fn resolveApiKey(provider: Provider, explicit: ?[]const u8, environ: *const std.process.Environ.Map) ?[]const u8 {
    if (explicit) |k| return k;
    if (environ.get(config.ENV_API_KEY)) |k| return k;
    if (provider == .anthropic) {
        if (environ.get(config.ENV_ANTHROPIC_AUTH_TOKEN)) |k| return k;
        if (environ.get(config.ENV_ANTHROPIC_OAUTH_TOKEN)) |k| return k;
    }
    if (credentialEnvName(provider)) |env_name| {
        if (environ.get(env_name)) |k| return k;
    }
    if (provider == .google) return environ.get(config.ENV_GEMINI_KEY);
    return null;
}

pub fn hasUsableCredential(provider: Provider, explicit: ?[]const u8, environ: *const std.process.Environ.Map) bool {
    if (resolveApiKey(provider, explicit, environ) != null) return true;
    if (provider == .google_vertex) {
        return environ.get("GOOGLE_APPLICATION_CREDENTIALS") != null or
            environ.get("CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE") != null or
            environ.get("GOOGLE_CLOUD_PROJECT") != null or environ.get("GCLOUD_PROJECT") != null;
    }
    if (provider == .amazon_bedrock) {
        const has_access_pair = environ.get("AWS_ACCESS_KEY_ID") != null and environ.get("AWS_SECRET_ACCESS_KEY") != null;
        const has_profile = environ.get("AWS_PROFILE") != null or environ.get("AWS_DEFAULT_PROFILE") != null;
        const has_container = environ.get("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") != null or environ.get("AWS_CONTAINER_CREDENTIALS_FULL_URI") != null;
        const has_web_identity = environ.get("AWS_WEB_IDENTITY_TOKEN_FILE") != null;
        const skip_auth = if (environ.get("AWS_BEDROCK_SKIP_AUTH")) |value| std.mem.eql(u8, value, "1") else false;
        return has_access_pair or has_profile or has_container or has_web_identity or skip_auth;
    }
    return false;
}

pub fn resolveProvider(explicit: ?[]const u8, environ: *const std.process.Environ.Map) Provider {
    if (explicit) |p| if (Provider.fromString(p)) |prov| return prov;
    if (environ.get(config.ENV_PROVIDER)) |p| if (Provider.fromString(p)) |prov| return prov;

    // Match upstream intent: select a configured provider, preserving its real identity.
    const priority = [_]Provider{
        .openai,                .anthropic,             .google,                .openrouter,             .xai,           .groq,              .deepseek,
        .together,              .fireworks,             .mistral,               .cerebras,               .perplexity,    .nvidia,            .radius,
        .cloudflare_workers_ai, .cloudflare_ai_gateway, .github_copilot,        .kimi_coding,            .baseten,       .qwen_token_plan,   .qwen_token_plan_individual,
        .qwen_token_plan_cn,    .amazon_bedrock,        .ant_ling,              .azure_openai_responses, .google_vertex, .huggingface,       .minimax,
        .minimax_cn,            .moonshotai,            .moonshotai_cn,         .opencode,               .opencode_go,   .vercel_ai_gateway, .xiaomi,
        .xiaomi_token_plan_ams, .xiaomi_token_plan_cn,  .xiaomi_token_plan_sgp, .zai,                    .zai_coding_cn,
    };
    for (priority) |p| if (hasUsableCredential(p, null, environ)) return p;
    return .openai;
}

pub fn defaultModel(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "gpt-4o-mini",
        .anthropic => "claude-sonnet-4-6",
        .google => "gemini-2.5-flash",
        .mock => "mock",
        .groq => "llama-3.3-70b-versatile",
        .together => "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        .deepseek => "deepseek-v4-flash",
        .ollama => "llama3.2",
        .openrouter => "openrouter/auto",
        .xai => "grok-4.5",
        .mistral => "mistral-large-latest",
        .fireworks => "accounts/fireworks/models/glm-5p2",
        .cerebras => "gpt-oss-120b",
        .lmstudio, .vllm => "local-model",
        .perplexity => "sonar",
        .nvidia => "deepseek-ai/deepseek-v4-pro-0813",
        .radius => "auto",
        .cloudflare_workers_ai => "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        .cloudflare_ai_gateway => "claude-sonnet-4.6",
        .amazon_bedrock => "anthropic.claude-sonnet-4-6",
        .github_copilot => "gpt-5-mini",
        .kimi_coding => "kimi-for-coding",
        .baseten => "zai-org/GLM-5.2",
        .qwen_token_plan, .qwen_token_plan_cn => "qwen3.7-max",
        .qwen_token_plan_individual => "qwen3.8-max",
        .ant_ling => "Ling-2.6-flash",
        .azure_openai_responses => "gpt-5.2",
        .google_vertex => "gemini-2.5-pro",
        .huggingface => "deepseek-ai/DeepSeek-V3",
        .minimax, .minimax_cn => "MiniMax-M2.7",
        .moonshotai, .moonshotai_cn => "kimi-k2.5",
        .opencode => "big-pickle",
        .opencode_go => "glm-5.2",
        .openai_codex => "gpt-5.6-sol",
        .vercel_ai_gateway => "anthropic/claude-sonnet-4.6",
        .xiaomi => "mimo-v2-flash",
        .xiaomi_token_plan_ams, .xiaomi_token_plan_cn, .xiaomi_token_plan_sgp => "mimo-v2.5",
        .zai, .zai_coding_cn => "glm-5.2",
    };
}

pub fn defaultBaseUrl(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "https://api.openai.com/v1",
        .anthropic => "https://api.anthropic.com",
        .google => "https://generativelanguage.googleapis.com/v1beta",
        .mock => "",
        .groq => "https://api.groq.com/openai/v1",
        .together => "https://api.together.xyz/v1",
        .deepseek => "https://api.deepseek.com/v1",
        .ollama => "http://127.0.0.1:11434/v1",
        .openrouter => "https://openrouter.ai/api/v1",
        .xai => "https://api.x.ai/v1",
        .mistral => "https://api.mistral.ai/v1",
        .fireworks => "https://api.fireworks.ai/inference/v1",
        .cerebras => "https://api.cerebras.ai/v1",
        .lmstudio => "http://127.0.0.1:1234/v1",
        .vllm => "http://127.0.0.1:8000/v1",
        .perplexity => "https://api.perplexity.ai",
        .nvidia => "https://integrate.api.nvidia.com/v1",
        .radius => "https://radius.pi.dev",
        .cloudflare_workers_ai => "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1",
        .cloudflare_ai_gateway => "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/compat",
        .amazon_bedrock => "https://bedrock-runtime.us-east-1.amazonaws.com",
        .github_copilot => "https://api.individual.githubcopilot.com",
        .kimi_coding => "https://api.kimi.com/coding",
        .baseten => "https://inference.baseten.co/v1",
        .qwen_token_plan, .qwen_token_plan_individual => "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
        .qwen_token_plan_cn => "https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
        .ant_ling => "https://api.ant-ling.com/v1",
        .azure_openai_responses => "",
        .google_vertex => "https://aiplatform.googleapis.com/v1/publishers/google",
        .huggingface => "https://router.huggingface.co/v1",
        .minimax => "https://api.minimax.io/anthropic",
        .minimax_cn => "https://api.minimaxi.com/anthropic",
        .moonshotai => "https://api.moonshot.ai/v1",
        .moonshotai_cn => "https://api.moonshot.cn/v1",
        .opencode => "https://opencode.ai/zen/v1",
        .opencode_go => "https://opencode.ai/zen/go/v1",
        .openai_codex => "https://chatgpt.com/backend-api",
        .vercel_ai_gateway => "https://ai-gateway.vercel.sh",
        .xiaomi => "https://api.xiaomimimo.com/v1",
        .xiaomi_token_plan_ams => "https://token-plan-ams.xiaomimimo.com/v1",
        .xiaomi_token_plan_cn => "https://token-plan-cn.xiaomimimo.com/v1",
        .xiaomi_token_plan_sgp => "https://token-plan-sgp.xiaomimimo.com/v1",
        .zai => "https://api.z.ai/api/coding/paas/v4",
        .zai_coding_cn => "https://open.bigmodel.cn/api/coding/paas/v4",
    };
}

/// Compatibility helper retained for CLI callers.
pub fn compatBaseUrl(name: []const u8) ?[]const u8 {
    const p = Provider.fromString(name) orelse return null;
    if (!p.isOpenAICompatible()) return null;
    return defaultBaseUrl(p);
}

test "provider identity is not collapsed" {
    try std.testing.expect(Provider.fromString("openai").? == .openai);
    try std.testing.expect(Provider.fromString("gemini").? == .google);
    try std.testing.expect(Provider.fromString("groq").? == .groq);
    try std.testing.expect(Provider.fromString("OpenRouter").? == .openrouter);
    try std.testing.expect(Provider.fromString("ollama").? == .ollama);
    try std.testing.expect(Provider.fromString("nope") == null);
    try std.testing.expect(.openai == Provider.groq.transport());
}

test "every provider default resolves to its public catalog identity" {
    inline for (std.meta.fields(Provider)) |field| {
        const provider: Provider = @enumFromInt(field.value);
        const wanted = defaultModel(provider);
        var found = false;
        for (known_models) |model| {
            if (std.ascii.eqlIgnoreCase(model.providerName(), provider.name()) and std.mem.eql(u8, model.id, wanted)) {
                found = true;
                break;
            }
        }
        if (!found) std.debug.print("missing default model: {s}/{s}\n", .{ provider.name(), wanted });
        try std.testing.expect(found);
    }
}

test "catalog has distinct gateway provider ids" {
    var saw_groq = false;
    var saw_openrouter = false;
    for (known_models) |m| {
        saw_groq = saw_groq or std.mem.eql(u8, m.providerName(), "groq");
        saw_openrouter = saw_openrouter or std.mem.eql(u8, m.providerName(), "openrouter");
    }
    try std.testing.expect(saw_groq and saw_openrouter);
}

test "generated catalog preserves exact upstream identity cardinality" {
    try std.testing.expectEqual(@as(usize, 1258), catalog_generated.model_count);
    try std.testing.expectEqual(@as(usize, 39), catalog_generated.provider_count);
    try std.testing.expectEqual(@as(usize, 1264), known_models.len);
    try std.testing.expectEqualStrings("0.84.1", catalog_generated.upstream_version);
    try std.testing.expectEqualStrings("0c3347c3bcf0d71a3d2b8b6bf9d8aee899cab258abc50a63a57db1282729ef2f", catalog_generated.source_sha256);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var identities: std.StringHashMap(void) = .init(a);
    defer identities.deinit();
    var public_providers: std.StringHashMap(void) = .init(a);
    defer public_providers.deinit();
    for (known_models[0..catalog_generated.model_count]) |model| {
        const identity = try std.fmt.allocPrint(a, "{s}\x00{s}", .{ model.providerName(), model.id });
        try std.testing.expect(!identities.contains(identity));
        try identities.put(identity, {});
        try public_providers.put(model.providerName(), {});
        try std.testing.expect(Provider.fromString(model.providerName()) != null);
        try std.testing.expect(model.base_url != null);
        try std.testing.expect(model.context_window > 0);
        try std.testing.expect(model.max_tokens > 0);
    }
    try std.testing.expectEqual(@as(usize, 39), public_providers.count());
}

test "catalog exposes the current OpenRouter free capability router" {
    var found: ?ModelInfo = null;
    for (known_models) |model| {
        if (std.mem.eql(u8, model.providerName(), "openrouter") and std.mem.eql(u8, model.id, "openrouter/free")) {
            found = model;
            break;
        }
    }
    const model = found orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("Free Models Router", model.display);
    try std.testing.expect(model.reasoning);
    try std.testing.expect(model.thinking_level_map.?.off == .unsupported);
    try std.testing.expect(model.clampThinkingLevel(.off) == .minimal);
    try std.testing.expect(model.input_text);
    try std.testing.expect(model.input_image);
    try std.testing.expectEqual(@as(u64, 200_000), model.context_window);
    try std.testing.expectEqual(@as(f64, 0), model.cost.input);
    try std.testing.expectEqual(@as(f64, 0), model.cost.output);
}

test "Bedrock ambient AWS access keys count as usable credentials" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_ACCESS_KEY_ID", "AKIA_TEST");
    try env.put("AWS_SECRET_ACCESS_KEY", "secret");
    try std.testing.expect(hasUsableCredential(.amazon_bedrock, null, &env));
    try std.testing.expect(resolveProvider("amazon-bedrock", &env) == .amazon_bedrock);
    try std.testing.expectEqualStrings("amazon-bedrock", Provider.amazon_bedrock.name());
    try std.testing.expect(Provider.fromString("amazon-bedrock") == .amazon_bedrock);
}

test "resolveApiKey uses provider-specific key" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("GROQ_API_KEY", "gsk-test");
    try std.testing.expectEqualStrings("gsk-test", resolveApiKey(.groq, null, &env).?);
    try std.testing.expect(resolveApiKey(.openrouter, null, &env) == null);
}

test "compat base urls preserve provider identity" {
    try std.testing.expectEqualStrings("https://api.x.ai/v1", compatBaseUrl("xai").?);
    try std.testing.expectEqualStrings("https://openrouter.ai/api/v1", compatBaseUrl("openrouter").?);
    try std.testing.expect(compatBaseUrl("unknown") == null);
}

test "Bedrock ambient chain markers count as usable credentials" {
    const gpa = std.testing.allocator;
    inline for (.{
        .{ "AWS_PROFILE", "research" },
        .{ "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/x" },
        .{ "AWS_WEB_IDENTITY_TOKEN_FILE", "/var/run/secrets/eks.amazonaws.com/serviceaccount/token" },
    }) |entry| {
        var env = std.process.Environ.Map.init(gpa);
        defer env.deinit();
        try env.put(entry[0], entry[1]);
        try std.testing.expect(hasUsableCredential(.amazon_bedrock, null, &env));
        try std.testing.expect(resolveProvider(null, &env) == .amazon_bedrock);
    }
}

test "Cloudflare provider identities use scoped credential and endpoint templates" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("CLOUDFLARE_API_KEY", "cf-token");
    try std.testing.expectEqualStrings("cf-token", resolveApiKey(.cloudflare_workers_ai, null, &env).?);
    try std.testing.expectEqualStrings("cf-token", resolveApiKey(.cloudflare_ai_gateway, null, &env).?);
    try std.testing.expectEqualStrings("cloudflare-workers-ai", Provider.cloudflare_workers_ai.name());
    try std.testing.expectEqualStrings("cloudflare-ai-gateway", Provider.cloudflare_ai_gateway.name());
    try std.testing.expect(std.mem.indexOf(u8, defaultBaseUrl(.cloudflare_workers_ai), "{CLOUDFLARE_ACCOUNT_ID}") != null);
    try std.testing.expect(std.mem.indexOf(u8, defaultBaseUrl(.cloudflare_ai_gateway), "{CLOUDFLARE_GATEWAY_ID}") != null);
}

test "GitHub Copilot curated models preserve mixed API and thinking metadata" {
    var gpt53: ?ModelInfo = null;
    var sonnet46: ?ModelInfo = null;
    var opus47: ?ModelInfo = null;
    var grok45: ?ModelInfo = null;
    for (known_models) |model| {
        if (!std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot")) continue;
        if (std.mem.eql(u8, model.id, "gpt-5.3-codex")) gpt53 = model;
        if (std.mem.eql(u8, model.id, "claude-sonnet-4.6")) sonnet46 = model;
        if (std.mem.eql(u8, model.id, "claude-opus-4.7")) opus47 = model;
        if (std.mem.eql(u8, model.id, "grok-4.5")) grok45 = model;
    }
    try std.testing.expect(gpt53 != null and sonnet46 != null and opus47 != null and grok45 != null);
    try std.testing.expect(gpt53.?.provider == .openai);
    try std.testing.expect(gpt53.?.apiKind() == .openai_responses);
    try std.testing.expectEqual(@as(u64, 1_000_000), gpt53.?.context_window);
    try std.testing.expect(gpt53.?.thinking_level_map.?.off == .unsupported);
    try std.testing.expectEqualStrings("low", gpt53.?.thinking_level_map.?.minimal.mapped);
    try std.testing.expectEqualStrings("xhigh", gpt53.?.thinking_level_map.?.xhigh.mapped);
    try std.testing.expect(sonnet46.?.provider == .anthropic);
    try std.testing.expect(sonnet46.?.apiKind() == .anthropic_messages);
    try std.testing.expectEqual(@as(u64, 1_000_000), sonnet46.?.context_window);
    try std.testing.expectEqualStrings("max", sonnet46.?.thinking_level_map.?.max.mapped);
    try std.testing.expectEqualStrings("xhigh", opus47.?.thinking_level_map.?.xhigh.mapped);
    try std.testing.expect(grok45.?.apiKind() == .openai_responses);
}

test "Anthropic env credential precedence is auth token then OAuth then API key" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put(config.ENV_ANTHROPIC_KEY, "api-key");
    try env.put(config.ENV_ANTHROPIC_OAUTH_TOKEN, "sk-ant-oat-env");
    try std.testing.expectEqualStrings("sk-ant-oat-env", resolveApiKey(.anthropic, null, &env).?);
    try env.put(config.ENV_ANTHROPIC_AUTH_TOKEN, "gateway-bearer");
    try std.testing.expectEqualStrings("gateway-bearer", resolveApiKey(.anthropic, null, &env).?);
}

test "Kimi Coding provider is Anthropic Messages with subscription metadata" {
    try std.testing.expect(Provider.fromString("kimi-coding") == .kimi_coding);
    try std.testing.expect(Provider.kimi_coding.transport() == .anthropic);
    try std.testing.expectEqualStrings("KIMI_API_KEY", credentialEnvName(.kimi_coding).?);
    try std.testing.expectEqualStrings("https://api.kimi.com/coding", defaultBaseUrl(.kimi_coding));
    var k3: ?ModelInfo = null;
    var canonical: ?ModelInfo = null;
    var fast: ?ModelInfo = null;
    for (known_models) |model| {
        if (!std.mem.eql(u8, model.providerName(), "kimi-coding")) continue;
        if (std.mem.eql(u8, model.id, "k3")) k3 = model;
        if (std.mem.eql(u8, model.id, "kimi-for-coding")) canonical = model;
        if (std.mem.eql(u8, model.id, "kimi-for-coding-highspeed")) fast = model;
    }
    try std.testing.expect(k3 != null and canonical != null and fast != null);
    try std.testing.expect(k3.?.apiKind() == .anthropic_messages);
    try std.testing.expectEqual(@as(u64, 131_072), k3.?.max_tokens);
    var levels_buf: [7]thinking.ThinkingLevel = undefined;
    try std.testing.expectEqualSlices(thinking.ThinkingLevel, &.{ .low, .high, .max }, k3.?.supportedThinkingLevels(&levels_buf));
    try std.testing.expectApproxEqAbs(@as(f64, 3), k3.?.cost.input, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 15), k3.?.cost.output, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), canonical.?.cost.input, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.9), fast.?.cost.input, 0.0001);
}

test "Baseten and Qwen Token Plan provider contracts match upstream" {
    try std.testing.expectEqualStrings("baseten", Provider.baseten.name());
    try std.testing.expectEqualStrings("qwen-token-plan", Provider.qwen_token_plan.name());
    try std.testing.expectEqualStrings("qwen-token-plan-cn", Provider.qwen_token_plan_cn.name());
    try std.testing.expectEqualStrings("qwen-token-plan-individual", Provider.qwen_token_plan_individual.name());
    try std.testing.expect(Provider.fromString("qwen-token-plan-individual") == .qwen_token_plan_individual);
    try std.testing.expect(Provider.baseten.transport() == .openai);
    try std.testing.expectEqualStrings("BASETEN_API_KEY", credentialEnvName(.baseten).?);
    try std.testing.expectEqualStrings("QWEN_TOKEN_PLAN_API_KEY", credentialEnvName(.qwen_token_plan).?);
    try std.testing.expectEqualStrings("QWEN_TOKEN_PLAN_API_KEY", credentialEnvName(.qwen_token_plan_individual).?);
    try std.testing.expectEqualStrings("QWEN_TOKEN_PLAN_CN_API_KEY", credentialEnvName(.qwen_token_plan_cn).?);
    try std.testing.expectEqualStrings("zai-org/GLM-5.2", defaultModel(.baseten));
    try std.testing.expectEqualStrings("qwen3.7-max", defaultModel(.qwen_token_plan));
    try std.testing.expectEqualStrings("qwen3.7-max", defaultModel(.qwen_token_plan_cn));
    try std.testing.expectEqualStrings("qwen3.8-max", defaultModel(.qwen_token_plan_individual));
    try std.testing.expectEqualStrings("https://inference.baseten.co/v1", defaultBaseUrl(.baseten));
    try std.testing.expectEqualStrings(defaultBaseUrl(.qwen_token_plan), defaultBaseUrl(.qwen_token_plan_individual));
}

test "generated Baseten and Qwen catalogs preserve capability metadata" {
    var baseten_glm: ?ModelInfo = null;
    var qwen38: ?ModelInfo = null;
    var broad_count: usize = 0;
    var cn_count: usize = 0;
    var individual_count: usize = 0;
    for (known_models) |model| {
        if (std.mem.eql(u8, model.providerName(), "qwen-token-plan")) broad_count += 1;
        if (std.mem.eql(u8, model.providerName(), "qwen-token-plan-cn")) cn_count += 1;
        if (std.mem.eql(u8, model.providerName(), "qwen-token-plan-individual")) individual_count += 1;
        if (std.mem.eql(u8, model.providerName(), "baseten") and std.mem.eql(u8, model.id, "zai-org/GLM-5.2")) baseten_glm = model;
        if (std.mem.eql(u8, model.providerName(), "qwen-token-plan") and std.mem.eql(u8, model.id, "qwen3.8-max")) qwen38 = model;
    }
    try std.testing.expectEqual(@as(usize, 18), broad_count);
    try std.testing.expectEqual(@as(usize, 18), cn_count);
    try std.testing.expectEqual(@as(usize, 7), individual_count);
    try std.testing.expect(baseten_glm != null and qwen38 != null);
    try std.testing.expect(baseten_glm.?.compat.thinking_format.? == .baseten);
    try std.testing.expectEqual(true, baseten_glm.?.compat.supports_reasoning_effort.?);
    try std.testing.expectEqual(@as(u64, 1_048_576), baseten_glm.?.context_window);
    var levels_buf: [7]thinking.ThinkingLevel = undefined;
    try std.testing.expectEqualSlices(
        thinking.ThinkingLevel,
        &.{ .off, .high, .max },
        baseten_glm.?.supportedThinkingLevels(&levels_buf),
    );
    try std.testing.expect(qwen38.?.compat.thinking_format.? == .qwen);
    try std.testing.expect(qwen38.?.input_image);
    try std.testing.expectEqualSlices(
        thinking.ThinkingLevel,
        &.{ .off, .low, .medium, .xhigh },
        qwen38.?.supportedThinkingLevels(&levels_buf),
    );
}
