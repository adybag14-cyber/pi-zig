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

    pub fn fromString(s: []const u8) ?Provider {
        if (std.ascii.eqlIgnoreCase(s, "amazon-bedrock")) return .amazon_bedrock;
        if (std.ascii.eqlIgnoreCase(s, "cloudflare-workers-ai")) return .cloudflare_workers_ai;
        if (std.ascii.eqlIgnoreCase(s, "cloudflare-ai-gateway")) return .cloudflare_ai_gateway;
        if (std.ascii.eqlIgnoreCase(s, "github-copilot")) return .github_copilot;
        if (std.ascii.eqlIgnoreCase(s, "kimi-coding")) return .kimi_coding;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan")) return .qwen_token_plan;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan-cn")) return .qwen_token_plan_cn;
        if (std.ascii.eqlIgnoreCase(s, "qwen-token-plan-individual")) return .qwen_token_plan_individual;
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
            else => @tagName(self),
        };
    }

    /// Native wire/API implementation used for requests.
    pub fn transport(self: Provider) Provider {
        return switch (self) {
            .groq, .together, .deepseek, .ollama, .openrouter, .xai, .mistral, .fireworks, .cerebras, .lmstudio, .vllm, .perplexity, .nvidia, .cloudflare_workers_ai, .cloudflare_ai_gateway, .github_copilot, .baseten, .qwen_token_plan, .qwen_token_plan_cn, .qwen_token_plan_individual => .openai,
            .kimi_coding => .anthropic,
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

/// Models represented by provider implementations that pi-zig can actually dispatch.
/// This is a curated runtime catalog, not a generated LOC surface.
pub const known_models = [_]ModelInfo{
    // OpenAI
    .{ .provider = .openai, .id = "gpt-4o-mini", .display = "OpenAI GPT-4o mini" },
    .{ .provider = .openai, .id = "gpt-4o", .display = "OpenAI GPT-4o" },
    .{ .provider = .openai, .id = "gpt-4.1", .display = "OpenAI GPT-4.1" },
    .{ .provider = .openai, .id = "gpt-4.1-mini", .display = "OpenAI GPT-4.1 mini" },
    .{ .provider = .openai, .id = "gpt-4.1-nano", .display = "OpenAI GPT-4.1 nano" },
    .{ .provider = .openai, .id = "o3-mini", .display = "OpenAI o3-mini", .reasoning = true },
    .{ .provider = .openai, .id = "o4-mini", .display = "OpenAI o4-mini", .reasoning = true },
    .{ .provider = .openai, .id = "gpt-5", .display = "OpenAI GPT-5", .reasoning = true },
    .{ .provider = .openai, .id = "gpt-5-mini", .display = "OpenAI GPT-5 mini", .reasoning = true },

    // Anthropic
    .{ .provider = .anthropic, .id = "claude-sonnet-4-20250514", .display = "Anthropic Claude Sonnet 4", .reasoning = true },
    .{ .provider = .anthropic, .id = "claude-opus-4-20250514", .display = "Anthropic Claude Opus 4", .reasoning = true },
    .{ .provider = .anthropic, .id = "claude-3-5-haiku-latest", .display = "Anthropic Claude 3.5 Haiku" },
    .{ .provider = .anthropic, .id = "claude-3-5-sonnet-latest", .display = "Anthropic Claude 3.5 Sonnet" },
    .{ .provider = .anthropic, .id = "claude-3-opus-latest", .display = "Anthropic Claude 3 Opus" },
    .{ .provider = .anthropic, .id = "claude-haiku-4-5-20251001", .display = "Anthropic Claude Haiku 4.5" },

    // Google
    .{ .provider = .google, .id = "gemini-2.0-flash", .display = "Google Gemini 2.0 Flash" },
    .{ .provider = .google, .id = "gemini-2.0-flash-lite", .display = "Google Gemini 2.0 Flash Lite" },
    .{ .provider = .google, .id = "gemini-1.5-pro", .display = "Google Gemini 1.5 Pro" },
    .{ .provider = .google, .id = "gemini-1.5-flash", .display = "Google Gemini 1.5 Flash" },
    .{ .provider = .google, .id = "gemini-2.5-pro", .display = "Google Gemini 2.5 Pro", .reasoning = true },
    .{ .provider = .google, .id = "gemini-2.5-flash", .display = "Google Gemini 2.5 Flash", .reasoning = true },

    // xAI
    .{ .provider = .xai, .id = "grok-3", .display = "xAI Grok 3" },
    .{ .provider = .xai, .id = "grok-3-mini", .display = "xAI Grok 3 mini", .reasoning = true },
    .{ .provider = .xai, .id = "grok-2", .display = "xAI Grok 2" },

    // Groq
    .{ .provider = .groq, .id = "llama-3.3-70b-versatile", .display = "Groq Llama 3.3 70B" },
    .{ .provider = .groq, .id = "llama-3.1-8b-instant", .display = "Groq Llama 3.1 8B" },
    .{ .provider = .groq, .id = "mixtral-8x7b-32768", .display = "Groq Mixtral 8x7B" },

    // DeepSeek
    .{ .provider = .deepseek, .id = "deepseek-chat", .display = "DeepSeek Chat" },
    .{ .provider = .deepseek, .id = "deepseek-reasoner", .display = "DeepSeek Reasoner", .reasoning = true },

    // Mistral
    .{ .provider = .mistral, .api = .mistral_conversations, .id = "mistral-large-latest", .display = "Mistral Large" },
    .{ .provider = .mistral, .api = .mistral_conversations, .id = "mistral-small-latest", .display = "Mistral Small" },
    .{ .provider = .mistral, .api = .mistral_conversations, .id = "codestral-latest", .display = "Mistral Codestral" },

    // Together / Fireworks / Cerebras / NVIDIA
    .{ .provider = .together, .id = "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo", .display = "Together Llama 3.1 70B" },
    .{ .provider = .fireworks, .id = "accounts/fireworks/models/llama-v3p1-70b-instruct", .display = "Fireworks Llama 3.1 70B" },
    .{ .provider = .cerebras, .id = "llama3.1-70b", .display = "Cerebras Llama 3.1 70B" },
    .{ .provider = .nvidia, .id = "meta/llama-3.1-70b-instruct", .display = "NVIDIA Llama 3.1 70B" },

    // OpenRouter IDs can legitimately contain slashes/colon suffixes.
    .{ .provider = .openrouter, .id = "openrouter/auto", .display = "OpenRouter Auto" },
    .{ .provider = .openrouter, .id = "anthropic/claude-sonnet-4", .display = "OpenRouter Claude Sonnet 4" },

    // Local OpenAI-compatible runtimes
    .{ .provider = .ollama, .id = "llama3.2", .display = "Ollama Llama 3.2" },
    .{ .provider = .ollama, .id = "llama3.1", .display = "Ollama Llama 3.1" },
    .{ .provider = .ollama, .id = "qwen2.5-coder", .display = "Ollama Qwen2.5 Coder" },
    .{ .provider = .ollama, .id = "codellama", .display = "Ollama Code Llama" },
    .{ .provider = .lmstudio, .id = "local-model", .display = "LM Studio local model" },
    .{ .provider = .vllm, .id = "local-model", .display = "vLLM local model" },

    // Baseten generated catalog (pi-ai v0.84.1).
    .{ .provider = .baseten, .id = "deepseek-ai/DeepSeek-V4-Flash-0731", .display = "Deepseek V4 Flash 0731", .reasoning = true, .context_window = 1_048_576, .max_tokens = 1_048_576, .cost = .{ .input = 0.13, .output = 0.26, .cache_read = 0.028, .cache_write = 0 }, .compat = baseten_base_compat },
    .{ .provider = .baseten, .id = "deepseek-ai/DeepSeek-V4-Pro", .display = "Deepseek V4 Pro", .reasoning = true, .thinking_level_map = map_all_efforts, .context_window = 262_144, .max_tokens = 262_144, .cost = .{ .input = 1.74, .output = 3.48, .cache_read = 0.145, .cache_write = 0 }, .compat = baseten_openai_compat },
    .{ .provider = .baseten, .id = "moonshotai/Kimi-K2.5", .display = "Kimi K2.5", .reasoning = true, .input_image = true, .thinking_level_map = map_toggle_high, .context_window = 262_000, .max_tokens = 262_000, .cost = .{ .input = 0.6, .output = 3, .cache_read = 0.12, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "moonshotai/Kimi-K2.6", .display = "Kimi K2.6", .reasoning = true, .input_image = true, .thinking_level_map = map_toggle_high, .context_window = 262_000, .max_tokens = 262_000, .cost = .{ .input = 0.95, .output = 4, .cache_read = 0.16, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "moonshotai/Kimi-K2.7-Code", .display = "Kimi K2.7 Code", .reasoning = true, .input_image = true, .thinking_level_map = map_toggle_high, .context_window = 262_000, .max_tokens = 262_000, .cost = .{ .input = 0.95, .output = 4, .cache_read = 0.16, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "moonshotai/Kimi-K3", .display = "Kimi K3", .reasoning = true, .input_image = true, .thinking_level_map = map_none_low_high_max, .context_window = 1_048_576, .max_tokens = 262_144, .cost = .{ .input = 3, .output = 15, .cache_read = 0, .cache_write = 0 }, .compat = baseten_openai_compat },
    .{ .provider = .baseten, .id = "nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B", .display = "Nemotron Ultra", .reasoning = true, .thinking_level_map = map_toggle_high, .context_window = 202_800, .max_tokens = 202_800, .cost = .{ .input = 0.6, .output = 2.4, .cache_read = 0.12, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "nvidia/Nemotron-120B-A12B", .display = "Nemotron Super", .reasoning = true, .thinking_level_map = map_toggle_high, .context_window = 202_800, .max_tokens = 202_800, .cost = .{ .input = 0.3, .output = 0.75, .cache_read = 0.06, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "openai/gpt-oss-120b", .display = "OpenAI GPT 120B", .reasoning = true, .thinking_level_map = map_all_efforts, .context_window = 128_072, .max_tokens = 128_072, .cost = .{ .input = 0.1, .output = 0.5, .cache_read = 0, .cache_write = 0 }, .compat = baseten_openai_compat },
    .{ .provider = .baseten, .id = "thinkingmachines/inkling", .display = "Inkling", .reasoning = true, .input_image = true, .thinking_level_map = map_all_efforts, .context_window = 1_048_576, .max_tokens = 32_768, .cost = .{ .input = 1, .output = 4.05, .cache_read = 0, .cache_write = 0 }, .compat = baseten_openai_compat },
    .{ .provider = .baseten, .id = "thinkingmachines/inkling-small", .display = "Inkling Small", .reasoning = true, .input_image = true, .thinking_level_map = map_all_efforts, .context_window = 1_048_576, .max_tokens = 32_768, .cost = .{ .input = 0.5, .output = 1.2, .cache_read = 0.1, .cache_write = 0 }, .compat = baseten_openai_compat },
    .{ .provider = .baseten, .id = "zai-org/GLM-4.7", .display = "GLM 4.7", .reasoning = true, .thinking_level_map = map_toggle_high, .context_window = 200_000, .max_tokens = 200_000, .cost = .{ .input = 0.6, .output = 2.2, .cache_read = 0.12, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "zai-org/GLM-5", .display = "GLM 5", .reasoning = true, .thinking_level_map = map_toggle_high, .context_window = 202_800, .max_tokens = 202_800, .cost = .{ .input = 0.95, .output = 3.15, .cache_read = 0.2, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "zai-org/GLM-5.1", .display = "GLM 5.1", .reasoning = true, .thinking_level_map = map_toggle_high, .context_window = 202_800, .max_tokens = 202_800, .cost = .{ .input = 1.3, .output = 4.3, .cache_read = 0.26, .cache_write = 0 }, .compat = baseten_template_compat },
    .{ .provider = .baseten, .id = "zai-org/GLM-5.2", .display = "GLM 5.2", .reasoning = true, .thinking_level_map = map_none_high_max, .context_window = 1_048_576, .max_tokens = 262_144, .cost = .{ .input = 1.4, .output = 4.4, .cache_read = 0.3, .cache_write = 0 }, .compat = baseten_template_effort_compat },
    .{ .provider = .baseten, .id = "zai-org/GLM-5.2-Fast", .display = "GLM 5.2 Fast", .reasoning = true, .thinking_level_map = map_none_high_max, .context_window = 524_288, .max_tokens = 262_144, .cost = .{ .input = 2.1, .output = 6.6, .cache_read = 0.21, .cache_write = 0 }, .compat = baseten_template_effort_compat },

    // Qwen Token Plan international catalog (pi-ai v0.84.1).
    .{ .provider = .qwen_token_plan, .id = "MiniMax-M2.5", .display = "MiniMax-M2.5", .reasoning = true, .context_window = 196_608, .max_tokens = 32_768, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "deepseek-v3.2", .display = "DeepSeek V3.2", .reasoning = true, .context_window = 131_072, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "deepseek-v4-flash", .display = "DeepSeek V4 Flash", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "deepseek-v4-flash-0731", .display = "DeepSeek V4 Flash 0731", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "deepseek-v4-pro", .display = "DeepSeek V4 Pro", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "glm-5", .display = "GLM-5", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 202_752, .max_tokens = 16_384, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "glm-5.1", .display = "GLM-5.1", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 202_752, .max_tokens = 128_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "glm-5.2", .display = "GLM-5.2", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "kimi-k2.5", .display = "Kimi K2.5", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 98_304, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "kimi-k2.6", .display = "Kimi K2.6", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 262_144, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "kimi-k2.7-code", .display = "Kimi K2.7 Code", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 262_144, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "qwen3.6-flash", .display = "Qwen3.6 Flash", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "qwen3.6-plus", .display = "Qwen3.6 Plus", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "qwen3.7-max", .display = "Qwen3.7 Max", .reasoning = true, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "qwen3.7-plus", .display = "Qwen3.7 Plus", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan, .id = "qwen3.8-max", .display = "Qwen3.8 Max", .reasoning = true, .input_image = true, .thinking_level_map = map_qwen38, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },

    // Qwen Token Plan China mirrors the broad catalog on its Beijing endpoint.
    .{ .provider = .qwen_token_plan_cn, .id = "MiniMax-M2.5", .display = "MiniMax-M2.5", .reasoning = true, .context_window = 196_608, .max_tokens = 32_768, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "deepseek-v3.2", .display = "DeepSeek V3.2", .reasoning = true, .context_window = 131_072, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "deepseek-v4-flash", .display = "DeepSeek V4 Flash", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "deepseek-v4-flash-0731", .display = "DeepSeek V4 Flash 0731", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "deepseek-v4-pro", .display = "DeepSeek V4 Pro", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "glm-5", .display = "GLM-5", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 202_752, .max_tokens = 16_384, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "glm-5.1", .display = "GLM-5.1", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 202_752, .max_tokens = 128_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "glm-5.2", .display = "GLM-5.2", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "kimi-k2.5", .display = "Kimi K2.5", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 98_304, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "kimi-k2.6", .display = "Kimi K2.6", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 262_144, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "kimi-k2.7-code", .display = "Kimi K2.7 Code", .reasoning = true, .input_image = true, .context_window = 262_144, .max_tokens = 262_144, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "qwen3.6-flash", .display = "Qwen3.6 Flash", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "qwen3.6-plus", .display = "Qwen3.6 Plus", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "qwen3.7-max", .display = "Qwen3.7 Max", .reasoning = true, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "qwen3.7-plus", .display = "Qwen3.7 Plus", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_cn, .id = "qwen3.8-max", .display = "Qwen3.8 Max", .reasoning = true, .input_image = true, .thinking_level_map = map_qwen38, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },

    // Qwen Token Plan Individual intentionally exposes only subscription-documented models.
    .{ .provider = .qwen_token_plan_individual, .id = "deepseek-v4-flash-0731", .display = "DeepSeek V4 Flash 0731", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "deepseek-v4-pro", .display = "DeepSeek V4 Pro", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 384_000, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "glm-5.2", .display = "GLM-5.2", .reasoning = true, .thinking_level_map = map_high_max, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "qwen3.6-flash", .display = "Qwen3.6 Flash", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "qwen3.7-max", .display = "Qwen3.7 Max", .reasoning = true, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "qwen3.7-plus", .display = "Qwen3.7 Plus", .reasoning = true, .input_image = true, .context_window = 1_000_000, .max_tokens = 65_536, .compat = qwen_no_effort_compat },
    .{ .provider = .qwen_token_plan_individual, .id = "qwen3.8-max", .display = "Qwen3.8 Max", .reasoning = true, .input_image = true, .thinking_level_map = map_qwen38, .context_window = 1_000_000, .max_tokens = 131_072, .compat = qwen_effort_compat },

    // GitHub Copilot is a mixed-API provider. Public identity stays
    // `github-copilot`, while each model selects its native wire transport.
    // API selection follows upstream generation: Claude 4/5 -> Anthropic,
    // gpt-5*/grok-4.5/oswe/mai -> Responses, remaining models -> Chat Completions.
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_completions, .id = "gpt-4.1", .display = "GitHub Copilot GPT-4.1", .input_image = true },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_completions, .id = "gpt-4o", .display = "GitHub Copilot GPT-4o", .input_image = true },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_completions, .id = "gemini-3-flash-preview", .display = "GitHub Copilot Gemini 3 Flash Preview", .reasoning = true, .input_image = true },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_completions, .id = "grok-code-fast-1", .display = "GitHub Copilot Grok Code Fast 1", .reasoning = true },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "grok-4.5", .display = "GitHub Copilot Grok 4.5", .reasoning = true },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5", .display = "GitHub Copilot GPT-5", .reasoning = true, .input_image = true, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" } } },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5-mini", .display = "GitHub Copilot GPT-5 mini", .reasoning = true, .input_image = true, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" } } },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5.1-codex", .display = "GitHub Copilot GPT-5.1 Codex", .reasoning = true, .input_image = true, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" } } },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5.2-codex", .display = "GitHub Copilot GPT-5.2 Codex", .reasoning = true, .input_image = true, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" } } },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5.3-codex", .display = "GitHub Copilot GPT-5.3 Codex", .reasoning = true, .input_image = true, .context_window = 1_000_000, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" } } },
    .{ .provider = .openai, .provider_id = "github-copilot", .api = .openai_responses, .id = "gpt-5.5", .display = "GitHub Copilot GPT-5.5", .reasoning = true, .input_image = true, .context_window = 1_000_000, .thinking_level_map = .{ .off = .unsupported, .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" } } },
    .{ .provider = .anthropic, .provider_id = "github-copilot", .api = .anthropic_messages, .id = "claude-haiku-4.5", .display = "GitHub Copilot Claude Haiku 4.5", .input_image = true },
    .{ .provider = .anthropic, .provider_id = "github-copilot", .api = .anthropic_messages, .id = "claude-sonnet-4.5", .display = "GitHub Copilot Claude Sonnet 4.5", .reasoning = true, .input_image = true },
    .{ .provider = .anthropic, .provider_id = "github-copilot", .api = .anthropic_messages, .id = "claude-sonnet-4.6", .display = "GitHub Copilot Claude Sonnet 4.6", .reasoning = true, .input_image = true, .context_window = 1_000_000, .thinking_level_map = .{ .minimal = .{ .mapped = "low" }, .max = .{ .mapped = "max" } } },
    .{ .provider = .anthropic, .provider_id = "github-copilot", .api = .anthropic_messages, .id = "claude-opus-4.7", .display = "GitHub Copilot Claude Opus 4.7", .reasoning = true, .input_image = true, .context_window = 1_000_000, .thinking_level_map = .{ .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" }, .max = .{ .mapped = "max" } } },
    .{ .provider = .anthropic, .provider_id = "github-copilot", .api = .anthropic_messages, .id = "claude-opus-5", .display = "GitHub Copilot Claude Opus 5", .reasoning = true, .input_image = true, .context_window = 1_000_000, .thinking_level_map = .{ .minimal = .{ .mapped = "low" }, .xhigh = .{ .mapped = "xhigh" }, .max = .{ .mapped = "max" } } },

    // Kimi For Coding subscription models use Anthropic Messages with Kimi OAuth/API-key auth.
    .{ .provider = .kimi_coding, .api = .anthropic_messages, .id = "kimi-for-coding", .display = "Kimi For Coding", .reasoning = true, .cost = .{ .input = 0.95, .output = 4, .cache_read = 0.19, .cache_write = 0 } },
    .{ .provider = .kimi_coding, .api = .anthropic_messages, .id = "k3", .display = "Kimi K3", .reasoning = true, .max_tokens = 131_072, .thinking_level_map = .{ .off = .unsupported, .minimal = .unsupported, .low = .{ .mapped = "low" }, .medium = .unsupported, .high = .{ .mapped = "high" }, .xhigh = .unsupported, .max = .{ .mapped = "max" } }, .cost = .{ .input = 3, .output = 15, .cache_read = 0.3, .cache_write = 0 } },
    .{ .provider = .kimi_coding, .api = .anthropic_messages, .id = "kimi-for-coding-highspeed", .display = "Kimi For Coding Highspeed", .reasoning = true, .cost = .{ .input = 1.9, .output = 8, .cache_read = 0.38, .cache_write = 0 } },

    // Amazon Bedrock (curated executable entry; full authoritative catalog is separate)
    .{ .provider = .amazon_bedrock, .api = .bedrock_converse_stream, .id = "anthropic.claude-sonnet-4-20250514-v1:0", .display = "Amazon Bedrock Claude Sonnet 4", .reasoning = true, .input_image = true },

    // Radius / Pi-native gateway
    .{ .provider = .radius, .api = .pi_messages, .id = "auto", .display = "Radius Auto", .context_window = 128_000, .max_tokens = 16_384 },

    .{ .provider = .mock, .id = "mock", .display = "Mock (scripted)", .context_window = 1_000_000, .max_tokens = 1_000_000 },
};

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
        .openai,                .anthropic,             .google,         .openrouter,  .xai,        .groq,            .deepseek,
        .together,              .fireworks,             .mistral,        .cerebras,    .perplexity, .nvidia,          .radius,
        .cloudflare_workers_ai, .cloudflare_ai_gateway, .github_copilot, .kimi_coding, .baseten,    .qwen_token_plan, .qwen_token_plan_individual,
        .qwen_token_plan_cn,    .amazon_bedrock,
    };
    for (priority) |p| if (hasUsableCredential(p, null, environ)) return p;
    return .openai;
}

pub fn defaultModel(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "gpt-4o-mini",
        .anthropic => "claude-sonnet-4-20250514",
        .google => "gemini-2.0-flash",
        .mock => "mock",
        .groq => "llama-3.3-70b-versatile",
        .together => "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo",
        .deepseek => "deepseek-chat",
        .ollama => "llama3.2",
        .openrouter => "openrouter/auto",
        .xai => "grok-3",
        .mistral => "mistral-large-latest",
        .fireworks => "accounts/fireworks/models/llama-v3p1-70b-instruct",
        .cerebras => "llama3.1-70b",
        .lmstudio, .vllm => "local-model",
        .perplexity => "sonar",
        .nvidia => "meta/llama-3.1-70b-instruct",
        .radius => "auto",
        .cloudflare_workers_ai => "@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        .cloudflare_ai_gateway => "workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast",
        .amazon_bedrock => "anthropic.claude-sonnet-4-20250514-v1:0",
        .github_copilot => "gpt-5-mini",
        .kimi_coding => "kimi-for-coding",
        .baseten => "zai-org/GLM-5.2",
        .qwen_token_plan, .qwen_token_plan_cn => "qwen3.7-max",
        .qwen_token_plan_individual => "qwen3.8-max",
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

test "catalog has distinct gateway provider ids" {
    var saw_groq = false;
    var saw_openrouter = false;
    for (known_models) |m| {
        saw_groq = saw_groq or m.provider == .groq;
        saw_openrouter = saw_openrouter or m.provider == .openrouter;
    }
    try std.testing.expect(saw_groq and saw_openrouter);
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
        if (model.provider != .kimi_coding) continue;
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
        switch (model.provider) {
            .qwen_token_plan => broad_count += 1,
            .qwen_token_plan_cn => cn_count += 1,
            .qwen_token_plan_individual => individual_count += 1,
            else => {},
        }
        if (model.provider == .baseten and std.mem.eql(u8, model.id, "zai-org/GLM-5.2")) baseten_glm = model;
        if (model.provider == .qwen_token_plan and std.mem.eql(u8, model.id, "qwen3.8-max")) qwen38 = model;
    }
    try std.testing.expectEqual(@as(usize, 16), broad_count);
    try std.testing.expectEqual(@as(usize, 16), cn_count);
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
