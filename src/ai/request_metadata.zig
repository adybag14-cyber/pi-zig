//! Typed request metadata shared by models.json parsing and native transports.
//! Only fields that pi-zig currently consumes are represented here. Unsupported
//! upstream compatibility knobs remain unclaimed rather than being silently ignored.
const std = @import("std");

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const SamplingParam = struct {
    name: []const u8,
    /// Canonical JSON for the value. Keeping the raw JSON makes arbitrary
    /// provider-specific sampling fields possible without weakening typing of
    /// the rest of the model schema.
    value_json: []const u8,
};

pub const CacheRetention = enum {
    none,
    short,
    long,

    pub fn parse(value: []const u8) ?CacheRetention {
        if (std.mem.eql(u8, value, "none")) return .none;
        if (std.mem.eql(u8, value, "short")) return .short;
        if (std.mem.eql(u8, value, "long")) return .long;
        return null;
    }
};

pub const SessionAffinityFormat = enum {
    openai,
    openai_nosession,
    openrouter,

    pub fn parse(value: []const u8) ?SessionAffinityFormat {
        if (std.mem.eql(u8, value, "openai")) return .openai;
        if (std.mem.eql(u8, value, "openai-nosession")) return .openai_nosession;
        if (std.mem.eql(u8, value, "openrouter")) return .openrouter;
        return null;
    }
};

pub const OpenRouterRouting = struct {
    allow_fallbacks: ?bool = null,
    require_parameters: ?bool = null,
    data_collection: ?[]const u8 = null,
    zdr: ?bool = null,
    enforce_distillable_text: ?bool = null,
    order: ?[]const std.json.Value = null,
    only: ?[]const std.json.Value = null,
    ignore: ?[]const std.json.Value = null,
    quantizations: ?[]const std.json.Value = null,
    sort: ?std.json.Value = null,
    max_price: ?std.json.ObjectMap = null,
    preferred_min_throughput: ?std.json.Value = null,
    preferred_max_latency: ?std.json.Value = null,

    pub fn merge(base: OpenRouterRouting, overlay: OpenRouterRouting) OpenRouterRouting {
        var out = base;
        inline for (std.meta.fields(OpenRouterRouting)) |field| {
            if (@field(overlay, field.name) != null) @field(out, field.name) = @field(overlay, field.name);
        }
        return out;
    }
};

pub const VercelGatewayRouting = struct {
    only: ?[]const std.json.Value = null,
    order: ?[]const std.json.Value = null,

    pub fn merge(base: VercelGatewayRouting, overlay: VercelGatewayRouting) VercelGatewayRouting {
        return .{
            .only = overlay.only orelse base.only,
            .order = overlay.order orelse base.order,
        };
    }
};

pub const CacheControlFormat = enum {
    anthropic,

    pub fn parse(value: []const u8) ?CacheControlFormat {
        if (std.mem.eql(u8, value, "anthropic")) return .anthropic;
        return null;
    }
};

pub const MaxTokensField = enum {
    max_completion_tokens,
    max_tokens,

    pub fn parse(value: []const u8) ?MaxTokensField {
        if (std.mem.eql(u8, value, "max_completion_tokens")) return .max_completion_tokens;
        if (std.mem.eql(u8, value, "max_tokens")) return .max_tokens;
        return null;
    }

    pub fn jsonName(self: MaxTokensField) []const u8 {
        return switch (self) {
            .max_completion_tokens => "max_completion_tokens",
            .max_tokens => "max_tokens",
        };
    }
};

pub const ThinkingTokenBudgetField = enum {
    thinking_token_budget,
    thinking_budget,
    thinking_budget_tokens,

    pub fn parse(value: []const u8) ?ThinkingTokenBudgetField {
        inline for (std.meta.fields(ThinkingTokenBudgetField)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn jsonName(self: ThinkingTokenBudgetField) []const u8 {
        return @tagName(self);
    }
};

pub const ThinkingFormat = enum {
    openai,
    openrouter,
    together,
    baseten,
    deepseek,
    zai,
    qwen,
    chat_template,
    qwen_chat_template,
    string_thinking,
    ant_ling,

    pub fn parse(value: []const u8) ?ThinkingFormat {
        if (std.mem.eql(u8, value, "openai")) return .openai;
        if (std.mem.eql(u8, value, "openrouter")) return .openrouter;
        if (std.mem.eql(u8, value, "together")) return .together;
        if (std.mem.eql(u8, value, "baseten")) return .baseten;
        if (std.mem.eql(u8, value, "deepseek")) return .deepseek;
        if (std.mem.eql(u8, value, "zai")) return .zai;
        if (std.mem.eql(u8, value, "qwen")) return .qwen;
        if (std.mem.eql(u8, value, "chat-template")) return .chat_template;
        if (std.mem.eql(u8, value, "qwen-chat-template")) return .qwen_chat_template;
        if (std.mem.eql(u8, value, "string-thinking")) return .string_thinking;
        if (std.mem.eql(u8, value, "ant-ling")) return .ant_ling;
        return null;
    }
};

pub const DeferredToolsMode = enum {
    kimi,

    pub fn parse(value: []const u8) ?DeferredToolsMode {
        if (std.mem.eql(u8, value, "kimi")) return .kimi;
        return null;
    }
};

pub const FallbackCostTier = struct {
    input_tokens_above: u64,
    input: f64,
    output: f64,
    cache_read: f64,
    cache_write: f64,
};

pub const FallbackCost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    tiers: []const FallbackCostTier = &.{},
};

pub const AnthropicAllowedFallbackModel = struct {
    provider: []const u8,
    model: []const u8,
    cost: FallbackCost,
};

/// OpenAI-Completions compatibility subset that has native behavior in pi-zig.
/// Optional booleans preserve the semantic difference between omitted and false.
pub const Compat = struct {
    supports_store: ?bool = null,
    supports_developer_role: ?bool = null,
    supports_reasoning_effort: ?bool = null,
    supports_usage_in_streaming: ?bool = null,
    /// If explicitly true, a streamed response must end with finish_reason.
    supports_finish_reason: ?bool = null,
    /// z.ai-compatible gateways can request incremental tool-call streaming.
    zai_tool_stream: ?bool = null,
    /// Some gateways reject the OpenAI function `strict` field entirely.
    supports_strict_mode: ?bool = null,
    supports_openai_grammar_tools: ?bool = null,
    /// OpenAI Responses client-executed tool search / deferred tool loading.
    supports_tool_search: ?bool = null,
    /// OpenAI Responses message-anchored `additional_tools` deferred loading.
    supports_additional_tools: ?bool = null,
    /// Anthropic client-side deferred tool loading through tool_reference blocks.
    supports_tool_references: ?bool = null,
    supports_eager_tool_input_streaming: ?bool = null,
    supports_cache_control_on_tools: ?bool = null,
    supports_temperature: ?bool = null,
    /// vLLM-compatible top-level reasoning token reservation.
    supports_thinking_token_budget: ?bool = null,
    /// Exact top-level field for reasoning token reservation. The legacy
    /// boolean above aliases `thinking_token_budget`.
    thinking_token_budget_field: ?ThinkingTokenBudgetField = null,
    force_adaptive_thinking: ?bool = null,
    supports_strict_tools: ?bool = null,
    /// Kimi/OpenAI-completions transcript-driven deferred tool injection.
    deferred_tools_mode: ?DeferredToolsMode = null,
    max_tokens_field: ?MaxTokensField = null,
    requires_tool_result_name: ?bool = null,
    requires_assistant_after_tool_result: ?bool = null,
    requires_thinking_as_text: ?bool = null,
    requires_reasoning_content_on_assistant_messages: ?bool = null,
    /// Anthropic-compatible providers may accept thinking blocks with signature:"".
    allow_empty_signature: ?bool = null,
    /// First-party Anthropic server-side refusal fallback targets and their
    /// local pricing metadata. An omitted or empty list must not emit the
    /// provider's `fallbacks` request field.
    allowed_fallback_models: ?[]const AnthropicAllowedFallbackModel = null,
    /// Borrowed custom-model representation from models.json. Built-in
    /// generated catalogs use the typed field above; keeping this borrowed
    /// avoids per-model ownership duplication during provider-level merges.
    allowed_fallback_models_json: ?std.json.Array = null,
    /// Prompt-cache/session-affinity controls from upstream Pi.
    supports_long_cache_retention: ?bool = null,
    supports_explicit_prompt_cache_mode: ?bool = null,
    send_session_affinity_headers: ?bool = null,
    session_affinity_format: ?SessionAffinityFormat = null,
    cache_control_format: ?CacheControlFormat = null,
    thinking_format: ?ThinkingFormat = null,
    /// Provider-specific chat-template values. Object maps borrow the parsed
    /// models.json tree, which remains alive for the runtime configuration.
    chat_template_kwargs: ?std.json.ObjectMap = null,
    chat_template_args: ?std.json.ObjectMap = null,
    /// Static generated Baseten catalogs use one canonical template argument.
    /// models.json retains the general ObjectMap representation above.
    chat_template_args_enable_thinking: ?bool = null,
    openrouter_routing: ?OpenRouterRouting = null,
    vercel_gateway_routing: ?VercelGatewayRouting = null,

    pub fn merge(base: Compat, overlay: Compat) Compat {
        var out = base;
        inline for (std.meta.fields(Compat)) |field| {
            if (@field(overlay, field.name) != null) @field(out, field.name) = @field(overlay, field.name);
        }
        if (base.openrouter_routing) |base_routing| if (overlay.openrouter_routing) |overlay_routing| {
            out.openrouter_routing = OpenRouterRouting.merge(base_routing, overlay_routing);
        };
        if (base.vercel_gateway_routing) |base_routing| if (overlay.vercel_gateway_routing) |overlay_routing| {
            out.vercel_gateway_routing = VercelGatewayRouting.merge(base_routing, overlay_routing);
        };
        return out;
    }
};

fn providerIs(provider_id: []const u8, name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, name);
}

fn urlHas(base_url: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, base_url, needle) != null;
}

pub fn detectOpenAIResponsesCompat(provider_id: []const u8, base_url: []const u8, model_id: []const u8) Compat {
    const openrouter = providerIs(provider_id, "openrouter") or urlHas(base_url, "openrouter.ai");
    const grammar = (providerIs(provider_id, "github-copilot") or providerIs(provider_id, "openai") or
        providerIs(provider_id, "openai-codex") or providerIs(provider_id, "azure-openai-responses") or
        providerIs(provider_id, "cloudflare-ai-gateway")) and std.mem.startsWith(u8, model_id, "gpt-5");
    return .{
        .supports_developer_role = true,
        .session_affinity_format = if (openrouter) .openrouter else .openai,
        .supports_long_cache_retention = true,
        .supports_strict_mode = false,
        .supports_openai_grammar_tools = grammar,
        .supports_additional_tools = false,
        .supports_tool_search = false,
        .supports_explicit_prompt_cache_mode = false,
    };
}

/// Upstream-style OpenAI Chat compatibility detection. Explicit models.json
/// compat is layered on top by runtime_config; this function only supplies the
/// provider/base-URL/model defaults that Pi can infer safely.
pub fn detectOpenAICompat(provider_id: []const u8, base_url: []const u8, model_id: []const u8) Compat {
    const is_zai = providerIs(provider_id, "zai") or providerIs(provider_id, "zai-coding-cn") or urlHas(base_url, "api.z.ai") or urlHas(base_url, "open.bigmodel.cn");
    const is_together = providerIs(provider_id, "together") or urlHas(base_url, "api.together.ai") or urlHas(base_url, "api.together.xyz");
    const is_moonshot = providerIs(provider_id, "moonshotai") or providerIs(provider_id, "moonshotai-cn") or urlHas(base_url, "api.moonshot.");
    const is_openrouter = providerIs(provider_id, "openrouter") or urlHas(base_url, "openrouter.ai");
    const is_cloudflare_workers = providerIs(provider_id, "cloudflare-workers-ai") or urlHas(base_url, "api.cloudflare.com");
    const is_cloudflare_gateway = providerIs(provider_id, "cloudflare-ai-gateway") or urlHas(base_url, "gateway.ai.cloudflare.com");
    const is_nvidia = providerIs(provider_id, "nvidia") or urlHas(base_url, "integrate.api.nvidia.com");
    const is_ant_ling = providerIs(provider_id, "ant-ling") or urlHas(base_url, "api.ant-ling.com");
    const is_grok = providerIs(provider_id, "xai") or urlHas(base_url, "api.x.ai");
    const is_deepseek = providerIs(provider_id, "deepseek") or urlHas(base_url, "deepseek.com");
    const is_copilot = providerIs(provider_id, "github-copilot");

    const non_standard = is_nvidia or providerIs(provider_id, "cerebras") or urlHas(base_url, "cerebras.ai") or
        is_grok or is_together or urlHas(base_url, "chutes.ai") or is_deepseek or is_zai or is_moonshot or
        providerIs(provider_id, "opencode") or urlHas(base_url, "opencode.ai") or is_cloudflare_workers or
        is_cloudflare_gateway or is_ant_ling;
    const use_max_tokens = urlHas(base_url, "chutes.ai") or is_moonshot or is_cloudflare_gateway or is_together or is_nvidia or is_ant_ling or is_zai;
    const openrouter_developer = is_openrouter and (std.mem.startsWith(u8, model_id, "anthropic/") or std.mem.startsWith(u8, model_id, "openai/"));

    return .{
        .supports_store = !non_standard and !is_copilot,
        .supports_developer_role = !is_copilot and (openrouter_developer or (!non_standard and !is_openrouter)),
        .supports_reasoning_effort = !is_copilot and !is_grok and !is_zai and !is_moonshot and !is_together and !is_cloudflare_gateway and !is_nvidia and !is_ant_ling,
        .supports_usage_in_streaming = true,
        .supports_finish_reason = true,
        .max_tokens_field = if (use_max_tokens) .max_tokens else .max_completion_tokens,
        .requires_tool_result_name = false,
        .requires_assistant_after_tool_result = false,
        .requires_thinking_as_text = false,
        .requires_reasoning_content_on_assistant_messages = is_deepseek,
        .thinking_format = if (is_deepseek) .deepseek else if (is_zai) .zai else if (is_together) .together else if (is_ant_ling) .ant_ling else if (is_openrouter) .openrouter else .openai,
        .zai_tool_stream = false,
        .supports_strict_mode = !is_moonshot and !is_together and !is_cloudflare_gateway and !is_nvidia,
        .supports_openai_grammar_tools = false,
        .supports_thinking_token_budget = false,
        .cache_control_format = if (providerIs(provider_id, "openrouter") and std.mem.startsWith(u8, model_id, "anthropic/")) .anthropic else null,
        .send_session_affinity_headers = false,
        .session_affinity_format = if (is_openrouter) .openrouter else .openai,
        .supports_long_cache_retention = !is_together and !is_cloudflare_workers and !is_cloudflare_gateway and !is_nvidia and !is_ant_ling,
    };
}

fn modelHasAny(model_id: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| if (std.mem.indexOf(u8, model_id, needle) != null) return true;
    return false;
}

/// Upstream-style Anthropic Messages compatibility defaults. Generated model
/// metadata adds strict/adaptive/temperature overrides, while the transport
/// itself supplies conservative defaults for omitted compat fields.
pub fn detectAnthropicCompat(provider_id: []const u8, model_id: []const u8) Compat {
    const first_party = providerIs(provider_id, "anthropic");
    const kimi_coding = providerIs(provider_id, "kimi-coding");
    const adaptive = kimi_coding or modelHasAny(model_id, &.{
        "opus-4-6", "opus-4.6", "opus-4-7",   "opus-4.7",   "opus-4-8", "opus-4.8",
        "opus-5",   "opus.5",   "sonnet-4-6", "sonnet-4.6", "sonnet-5", "sonnet.5",
        "fable-5",
    });
    const temperature_unsupported = modelHasAny(model_id, &.{
        "opus-4-7", "opus-4.7", "opus-4-8", "opus-4.8", "opus-5", "opus.5",
    });
    const copilot_eager_unsupported = providerIs(provider_id, "github-copilot") and
        (std.mem.eql(u8, model_id, "claude-haiku-4.5") or std.mem.eql(u8, model_id, "claude-sonnet-4") or
            std.mem.eql(u8, model_id, "claude-sonnet-4.5"));

    var tool_references = false;
    if (first_party and std.mem.indexOf(u8, model_id, "haiku") == null and std.mem.startsWith(u8, model_id, "claude-")) {
        const rest = model_id["claude-".len..];
        const family_end = std.mem.indexOfScalar(u8, rest, '-') orelse rest.len;
        const family = rest[0..family_end];
        if (std.mem.eql(u8, family, "opus") or std.mem.eql(u8, family, "sonnet") or std.mem.eql(u8, family, "fable")) {
            const version_start = if (family_end < rest.len) family_end + 1 else rest.len;
            const version_rest = rest[version_start..];
            const major_end = std.mem.indexOfScalar(u8, version_rest, '-') orelse version_rest.len;
            const major = std.fmt.parseInt(u32, version_rest[0..major_end], 10) catch 0;
            var minor: u32 = 0;
            if (major_end < version_rest.len) {
                const minor_rest = version_rest[major_end + 1 ..];
                const minor_end = std.mem.indexOfScalar(u8, minor_rest, '-') orelse minor_rest.len;
                // A YYYYMMDD suffix is a release date, not a minor version.
                if (minor_end > 0 and minor_end < 8) minor = std.fmt.parseInt(u32, minor_rest[0..minor_end], 10) catch 0;
            }
            tool_references = major > 4 or (major == 4 and minor >= 5);
        }
    }

    return .{
        .supports_eager_tool_input_streaming = !copilot_eager_unsupported,
        .supports_long_cache_retention = true,
        .send_session_affinity_headers = false,
        .supports_cache_control_on_tools = true,
        .supports_temperature = !temperature_unsupported,
        .allow_empty_signature = kimi_coding and (std.mem.eql(u8, model_id, "k3") or std.mem.eql(u8, model_id, "kimi-for-coding")),
        .supports_strict_tools = first_party,
        .supports_tool_references = tool_references,
        .force_adaptive_thinking = adaptive,
    };
}

test "GitHub Copilot compatibility follows generated API restrictions" {
    const chat = detectOpenAICompat("github-copilot", "https://api.individual.githubcopilot.com", "gpt-4.1");
    try std.testing.expectEqual(false, chat.supports_store.?);
    try std.testing.expectEqual(false, chat.supports_developer_role.?);
    try std.testing.expectEqual(false, chat.supports_reasoning_effort.?);

    const responses = detectOpenAIResponsesCompat("github-copilot", "https://api.individual.githubcopilot.com", "gpt-5.3-codex");
    try std.testing.expectEqual(true, responses.supports_openai_grammar_tools.?);
    const old_model = detectOpenAIResponsesCompat("github-copilot", "https://api.individual.githubcopilot.com", "gpt-4.1");
    try std.testing.expectEqual(false, old_model.supports_openai_grammar_tools.?);

    const haiku = detectAnthropicCompat("github-copilot", "claude-haiku-4.5");
    try std.testing.expectEqual(false, haiku.supports_eager_tool_input_streaming.?);
    const sonnet46 = detectAnthropicCompat("github-copilot", "claude-sonnet-4.6");
    try std.testing.expectEqual(true, sonnet46.supports_eager_tool_input_streaming.?);
}

test "Anthropic compat detection matches first-party tool references and adaptive models" {
    const sonnet45 = detectAnthropicCompat("anthropic", "claude-sonnet-4-5-20250929");
    try std.testing.expectEqual(true, sonnet45.supports_tool_references.?);
    try std.testing.expectEqual(true, sonnet45.supports_strict_tools.?);
    try std.testing.expectEqual(true, sonnet45.supports_eager_tool_input_streaming.?);

    const haiku45 = detectAnthropicCompat("anthropic", "claude-haiku-4-5-20251001");
    try std.testing.expectEqual(false, haiku45.supports_tool_references.?);

    const opus48 = detectAnthropicCompat("proxy", "claude-opus-4-8");
    try std.testing.expectEqual(true, opus48.force_adaptive_thinking.?);
    try std.testing.expectEqual(false, opus48.supports_temperature.?);
    try std.testing.expectEqual(false, opus48.supports_strict_tools.?);
    try std.testing.expectEqual(false, opus48.supports_tool_references.?);

    const old = detectAnthropicCompat("anthropic", "claude-sonnet-4-20250514");
    try std.testing.expectEqual(false, old.supports_tool_references.?);
    try std.testing.expectEqual(false, old.force_adaptive_thinking.?);
}

test "compat merge preserves base and applies explicit false" {
    const base = Compat{ .supports_developer_role = true, .supports_usage_in_streaming = true };
    const overlay = Compat{ .supports_developer_role = false, .max_tokens_field = .max_tokens };
    const out = Compat.merge(base, overlay);
    try std.testing.expectEqual(false, out.supports_developer_role.?);
    try std.testing.expectEqual(true, out.supports_usage_in_streaming.?);
    try std.testing.expect(out.max_tokens_field.? == .max_tokens);
}

test "cache and affinity compatibility names parse" {
    try std.testing.expect(CacheRetention.parse("none").? == .none);
    try std.testing.expect(CacheRetention.parse("short").? == .short);
    try std.testing.expect(CacheRetention.parse("long").? == .long);
    try std.testing.expect(SessionAffinityFormat.parse("openai").? == .openai);
    try std.testing.expect(SessionAffinityFormat.parse("openai-nosession").? == .openai_nosession);
    try std.testing.expect(SessionAffinityFormat.parse("openrouter").? == .openrouter);
    try std.testing.expect(CacheControlFormat.parse("anthropic").? == .anthropic);
}

test "Responses compat detection matches upstream defaults" {
    const direct = detectOpenAIResponsesCompat("corp", "https://example.test/v1", "gpt-4o");
    try std.testing.expectEqual(true, direct.supports_developer_role.?);
    try std.testing.expectEqual(false, direct.supports_strict_mode.?);
    try std.testing.expectEqual(true, direct.supports_long_cache_retention.?);
    try std.testing.expect(direct.session_affinity_format.? == .openai);
    const routed = detectOpenAIResponsesCompat("custom", "https://openrouter.ai/api/v1", "model");
    try std.testing.expect(routed.session_affinity_format.? == .openrouter);
}

test "OpenAI compat detection matches major provider families" {
    const openrouter = detectOpenAICompat("openrouter", "https://openrouter.ai/api/v1", "anthropic/claude-sonnet-4");
    try std.testing.expectEqual(true, openrouter.supports_developer_role.?);
    try std.testing.expect(openrouter.thinking_format.? == .openrouter);
    try std.testing.expect(openrouter.session_affinity_format.? == .openrouter);
    try std.testing.expect(openrouter.cache_control_format.? == .anthropic);

    const deepseek = detectOpenAICompat("corp", "https://api.deepseek.com/v1", "deepseek-reasoner");
    try std.testing.expectEqual(true, deepseek.requires_reasoning_content_on_assistant_messages.?);
    try std.testing.expect(deepseek.thinking_format.? == .deepseek);
    try std.testing.expect(deepseek.max_tokens_field.? == .max_completion_tokens);

    const together = detectOpenAICompat("together", "https://api.together.xyz/v1", "x");
    try std.testing.expectEqual(false, together.supports_strict_mode.?);
    try std.testing.expectEqual(false, together.supports_long_cache_retention.?);
    try std.testing.expect(together.max_tokens_field.? == .max_tokens);
}

test "Kimi Coding Anthropic compat forces adaptive thinking and empty signatures selectively" {
    const canonical = detectAnthropicCompat("kimi-coding", "kimi-for-coding");
    try std.testing.expectEqual(true, canonical.force_adaptive_thinking.?);
    try std.testing.expectEqual(true, canonical.allow_empty_signature.?);
    const k3 = detectAnthropicCompat("kimi-coding", "k3");
    try std.testing.expectEqual(true, k3.force_adaptive_thinking.?);
    try std.testing.expectEqual(true, k3.allow_empty_signature.?);
    const fast = detectAnthropicCompat("kimi-coding", "kimi-for-coding-highspeed");
    try std.testing.expectEqual(true, fast.force_adaptive_thinking.?);
    try std.testing.expectEqual(false, fast.allow_empty_signature.?);
}
