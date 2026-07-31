//! Provider catalog and API key resolution from environment.
//! Catalog lists 40+ common model ids across OpenAI / Anthropic / Google / OpenAI-compatible gateways.
const std = @import("std");
const config = @import("../config.zig");

pub const Provider = enum {
    openai,
    anthropic,
    google,
    mock,
    /// OpenAI-compatible gateways (Groq, Together, DeepSeek, Ollama, OpenRouter, xAI, Mistral, Fireworks, …)
    openai_compat,

    pub fn fromString(s: []const u8) ?Provider {
        if (std.mem.eql(u8, s, "openai")) return .openai;
        if (std.mem.eql(u8, s, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, s, "google") or std.mem.eql(u8, s, "gemini")) return .google;
        if (std.mem.eql(u8, s, "mock")) return .mock;
        if (std.mem.eql(u8, s, "openai_compat") or std.mem.eql(u8, s, "compat") or
            std.mem.eql(u8, s, "groq") or std.mem.eql(u8, s, "together") or
            std.mem.eql(u8, s, "deepseek") or std.mem.eql(u8, s, "ollama") or
            std.mem.eql(u8, s, "openrouter") or std.mem.eql(u8, s, "xai") or
            std.mem.eql(u8, s, "mistral") or std.mem.eql(u8, s, "fireworks") or
            std.mem.eql(u8, s, "cerebras") or std.mem.eql(u8, s, "sambanova") or
            std.mem.eql(u8, s, "perplexity") or std.mem.eql(u8, s, "cohere") or
            std.mem.eql(u8, s, "azure") or std.mem.eql(u8, s, "github") or
            std.mem.eql(u8, s, "nvidia") or std.mem.eql(u8, s, "llama") or
            std.mem.eql(u8, s, "lmstudio") or std.mem.eql(u8, s, "vllm"))
            return .openai_compat;
        return null;
    }

    pub fn name(self: Provider) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .mock => "mock",
            .openai_compat => "openai_compat",
        };
    }

    /// Transport family used by ClientPool (openai_compat uses OpenAI client).
    pub fn transport(self: Provider) Provider {
        return switch (self) {
            .openai_compat => .openai,
            else => self,
        };
    }
};

pub const ModelInfo = struct {
    provider: Provider,
    id: []const u8,
    display: []const u8,
};

/// 40+ catalog entries spanning first-party + common OpenAI-compatible endpoints.
pub const known_models = [_]ModelInfo{
    // OpenAI
    .{ .provider = .openai, .id = "gpt-4o-mini", .display = "OpenAI GPT-4o mini" },
    .{ .provider = .openai, .id = "gpt-4o", .display = "OpenAI GPT-4o" },
    .{ .provider = .openai, .id = "gpt-4.1", .display = "OpenAI GPT-4.1" },
    .{ .provider = .openai, .id = "gpt-4.1-mini", .display = "OpenAI GPT-4.1 mini" },
    .{ .provider = .openai, .id = "gpt-4.1-nano", .display = "OpenAI GPT-4.1 nano" },
    .{ .provider = .openai, .id = "o3-mini", .display = "OpenAI o3-mini" },
    .{ .provider = .openai, .id = "o4-mini", .display = "OpenAI o4-mini" },
    .{ .provider = .openai, .id = "gpt-5", .display = "OpenAI GPT-5" },
    .{ .provider = .openai, .id = "gpt-5-mini", .display = "OpenAI GPT-5 mini" },
    // Anthropic
    .{ .provider = .anthropic, .id = "claude-sonnet-4-20250514", .display = "Anthropic Claude Sonnet 4" },
    .{ .provider = .anthropic, .id = "claude-opus-4-20250514", .display = "Anthropic Claude Opus 4" },
    .{ .provider = .anthropic, .id = "claude-3-5-haiku-latest", .display = "Anthropic Claude 3.5 Haiku" },
    .{ .provider = .anthropic, .id = "claude-3-5-sonnet-latest", .display = "Anthropic Claude 3.5 Sonnet" },
    .{ .provider = .anthropic, .id = "claude-3-opus-latest", .display = "Anthropic Claude 3 Opus" },
    .{ .provider = .anthropic, .id = "claude-haiku-4-5-20251001", .display = "Anthropic Claude Haiku 4.5" },
    // Google
    .{ .provider = .google, .id = "gemini-2.0-flash", .display = "Google Gemini 2.0 Flash" },
    .{ .provider = .google, .id = "gemini-2.0-flash-lite", .display = "Google Gemini 2.0 Flash Lite" },
    .{ .provider = .google, .id = "gemini-1.5-pro", .display = "Google Gemini 1.5 Pro" },
    .{ .provider = .google, .id = "gemini-1.5-flash", .display = "Google Gemini 1.5 Flash" },
    .{ .provider = .google, .id = "gemini-2.5-pro", .display = "Google Gemini 2.5 Pro" },
    .{ .provider = .google, .id = "gemini-2.5-flash", .display = "Google Gemini 2.5 Flash" },
    // OpenAI-compatible: xAI
    .{ .provider = .openai_compat, .id = "grok-3", .display = "xAI Grok 3" },
    .{ .provider = .openai_compat, .id = "grok-3-mini", .display = "xAI Grok 3 mini" },
    .{ .provider = .openai_compat, .id = "grok-2", .display = "xAI Grok 2" },
    // Groq
    .{ .provider = .openai_compat, .id = "llama-3.3-70b-versatile", .display = "Groq Llama 3.3 70B" },
    .{ .provider = .openai_compat, .id = "llama-3.1-8b-instant", .display = "Groq Llama 3.1 8B" },
    .{ .provider = .openai_compat, .id = "mixtral-8x7b-32768", .display = "Groq Mixtral 8x7B" },
    // DeepSeek
    .{ .provider = .openai_compat, .id = "deepseek-chat", .display = "DeepSeek Chat" },
    .{ .provider = .openai_compat, .id = "deepseek-reasoner", .display = "DeepSeek Reasoner" },
    // Mistral
    .{ .provider = .openai_compat, .id = "mistral-large-latest", .display = "Mistral Large" },
    .{ .provider = .openai_compat, .id = "mistral-small-latest", .display = "Mistral Small" },
    .{ .provider = .openai_compat, .id = "codestral-latest", .display = "Mistral Codestral" },
    // Together / Fireworks / Cerebras common ids
    .{ .provider = .openai_compat, .id = "meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo", .display = "Together Llama 3.1 70B" },
    .{ .provider = .openai_compat, .id = "accounts/fireworks/models/llama-v3p1-70b-instruct", .display = "Fireworks Llama 3.1 70B" },
    .{ .provider = .openai_compat, .id = "llama3.1-70b", .display = "Cerebras Llama 3.1 70B" },
    // OpenRouter aliases
    .{ .provider = .openai_compat, .id = "openrouter/auto", .display = "OpenRouter Auto" },
    .{ .provider = .openai_compat, .id = "anthropic/claude-sonnet-4", .display = "OpenRouter Claude Sonnet 4" },
    // Local llama / Ollama / LM Studio / vLLM
    .{ .provider = .openai_compat, .id = "llama3.2", .display = "Ollama Llama 3.2" },
    .{ .provider = .openai_compat, .id = "llama3.1", .display = "Ollama Llama 3.1" },
    .{ .provider = .openai_compat, .id = "qwen2.5-coder", .display = "Ollama Qwen2.5 Coder" },
    .{ .provider = .openai_compat, .id = "codellama", .display = "Ollama Code Llama" },
    .{ .provider = .openai_compat, .id = "local-model", .display = "Local OpenAI-compat (LM Studio/vLLM)" },
    // Mock
    .{ .provider = .mock, .id = "mock", .display = "Mock (scripted)" },
};

/// Resolve API key for a provider from explicit key or environment.
pub fn resolveApiKey(provider: Provider, explicit: ?[]const u8, environ: *const std.process.Environ.Map) ?[]const u8 {
    if (explicit) |k| return k;
    if (environ.get(config.ENV_API_KEY)) |k| return k;
    return switch (provider) {
        .openai, .openai_compat => environ.get(config.ENV_OPENAI_KEY) orelse environ.get("GROQ_API_KEY") orelse environ.get("OPENROUTER_API_KEY") orelse environ.get("XAI_API_KEY") orelse environ.get("DEEPSEEK_API_KEY") orelse environ.get("TOGETHER_API_KEY") orelse environ.get("FIREWORKS_API_KEY") orelse environ.get("MISTRAL_API_KEY"),
        .anthropic => environ.get(config.ENV_ANTHROPIC_KEY),
        .google => environ.get(config.ENV_GOOGLE_KEY) orelse environ.get(config.ENV_GEMINI_KEY),
        .mock => null,
    };
}

pub fn resolveProvider(explicit: ?[]const u8, environ: *const std.process.Environ.Map) Provider {
    if (explicit) |p| {
        if (Provider.fromString(p)) |prov| return prov;
    }
    if (environ.get(config.ENV_PROVIDER)) |p| {
        if (Provider.fromString(p)) |prov| return prov;
    }
    // Prefer whichever key is set
    if (environ.get(config.ENV_OPENAI_KEY) != null) return .openai;
    if (environ.get(config.ENV_ANTHROPIC_KEY) != null) return .anthropic;
    if (environ.get(config.ENV_GOOGLE_KEY) != null or environ.get(config.ENV_GEMINI_KEY) != null) return .google;
    if (environ.get("GROQ_API_KEY") != null or environ.get("OPENROUTER_API_KEY") != null or
        environ.get("XAI_API_KEY") != null or environ.get("DEEPSEEK_API_KEY") != null)
        return .openai_compat;
    return .openai;
}

pub fn defaultModel(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "gpt-4o-mini",
        .anthropic => "claude-sonnet-4-20250514",
        .google => "gemini-2.0-flash",
        .mock => "mock",
        .openai_compat => "local-model",
    };
}

pub fn defaultBaseUrl(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "https://api.openai.com/v1",
        .anthropic => "https://api.anthropic.com",
        .google => "https://generativelanguage.googleapis.com/v1beta",
        .mock => "",
        .openai_compat => "http://127.0.0.1:11434/v1", // Ollama default; override with --base-url
    };
}

/// Suggested base URL for named openai_compat gateways.
pub fn compatBaseUrl(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "groq")) return "https://api.groq.com/openai/v1";
    if (std.mem.eql(u8, name, "together")) return "https://api.together.xyz/v1";
    if (std.mem.eql(u8, name, "deepseek")) return "https://api.deepseek.com/v1";
    if (std.mem.eql(u8, name, "ollama") or std.mem.eql(u8, name, "llama")) return "http://127.0.0.1:11434/v1";
    if (std.mem.eql(u8, name, "openrouter")) return "https://openrouter.ai/api/v1";
    if (std.mem.eql(u8, name, "xai")) return "https://api.x.ai/v1";
    if (std.mem.eql(u8, name, "mistral")) return "https://api.mistral.ai/v1";
    if (std.mem.eql(u8, name, "fireworks")) return "https://api.fireworks.ai/inference/v1";
    if (std.mem.eql(u8, name, "cerebras")) return "https://api.cerebras.ai/v1";
    if (std.mem.eql(u8, name, "lmstudio")) return "http://127.0.0.1:1234/v1";
    if (std.mem.eql(u8, name, "vllm")) return "http://127.0.0.1:8000/v1";
    if (std.mem.eql(u8, name, "perplexity")) return "https://api.perplexity.ai";
    return null;
}

test "provider from string" {
    try std.testing.expect(Provider.fromString("openai").? == .openai);
    try std.testing.expect(Provider.fromString("gemini").? == .google);
    try std.testing.expect(Provider.fromString("groq").? == .openai_compat);
    try std.testing.expect(Provider.fromString("ollama").? == .openai_compat);
    try std.testing.expect(Provider.fromString("nope") == null);
}

test "catalog has 40+ models" {
    try std.testing.expect(known_models.len >= 40);
}

test "resolveApiKey prefers explicit" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    const k = resolveApiKey(.openai, "sk-test", &env);
    try std.testing.expectEqualStrings("sk-test", k.?);
}

test "compat base urls" {
    try std.testing.expectEqualStrings("https://api.x.ai/v1", compatBaseUrl("xai").?);
    try std.testing.expect(compatBaseUrl("unknown") == null);
}
