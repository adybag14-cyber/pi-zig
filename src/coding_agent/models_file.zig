//! Loader for upstream-compatible `~/.pi/agent/models.json` custom providers.
//!
//! This ports the core static configuration shape used by Pi. Provider IDs are
//! arbitrary strings; each provider/model selects one of the native transports
//! implemented by pi-zig. Parsing a supported API does not claim every upstream
//! compatibility knob is implemented yet; unsupported runtime API modes are
//! surfaced explicitly rather than silently sent through the wrong endpoint.
const std = @import("std");
const Io = std.Io;
const providers = @import("../ai/providers.zig");
const thinking = @import("../ai/thinking.zig");
const metadata = @import("../ai/request_metadata.zig");

pub const Api = @import("../ai/api.zig").Api;

pub const OAuthProvider = enum { radius };

pub const ModelConfig = struct {
    info: providers.ModelInfo,
    api: Api,
    base_url: ?[]const u8 = null,
    context_window: ?u64 = null,
    max_tokens: ?u64 = null,
    sampling_params: []metadata.SamplingParam = &.{},
    headers: []metadata.Header = &.{},
    compat: metadata.Compat = .{},
};

pub const ModelOverride = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    reasoning: ?bool = null,
    thinking_level_map: ?thinking.ThinkingLevelMap = null,
    input_text: ?bool = null,
    input_image: ?bool = null,
    cost: ?providers.ModelCost = null,
    context_window: ?u64 = null,
    max_tokens: ?u64 = null,
    sampling_params: []metadata.SamplingParam = &.{},
    headers: []metadata.Header = &.{},
    compat: metadata.Compat = .{},
};

pub const ProviderConfig = struct {
    id: []const u8,
    name: []const u8,
    base_url: ?[]const u8,
    api_key: ?[]const u8,
    api: ?Api,
    oauth: ?OAuthProvider = null,
    auth_header: bool = false,
    headers: []metadata.Header = &.{},
    compat: metadata.Compat = .{},
    models: []ModelConfig,
    model_overrides: []ModelOverride = &.{},

    pub fn findOverride(self: *const ProviderConfig, model_id: []const u8) ?*const ModelOverride {
        for (self.model_overrides) |*override| {
            if (std.mem.eql(u8, override.id, model_id)) return override;
        }
        return null;
    }
};

pub const ModelsFile = struct {
    gpa: std.mem.Allocator,
    parsed: ?std.json.Parsed(std.json.Value) = null,
    providers: []ProviderConfig = &.{},
    model_infos: []providers.ModelInfo = &.{},

    pub fn deinit(self: *ModelsFile) void {
        for (self.providers) |provider| {
            for (provider.models) |model| deinitModelConfig(self.gpa, model);
            self.gpa.free(provider.models);
            for (provider.model_overrides) |override| deinitModelOverride(self.gpa, override);
            if (provider.model_overrides.len > 0) self.gpa.free(provider.model_overrides);
            if (provider.headers.len > 0) self.gpa.free(provider.headers);
        }
        if (self.providers.len > 0) self.gpa.free(self.providers);
        if (self.model_infos.len > 0) self.gpa.free(self.model_infos);
        if (self.parsed) |*parsed| parsed.deinit();
        self.* = undefined;
    }

    pub fn findProvider(self: *const ModelsFile, id: []const u8) ?*const ProviderConfig {
        for (self.providers) |*provider| {
            if (std.ascii.eqlIgnoreCase(provider.id, id)) return provider;
        }
        return null;
    }

    pub fn findModel(self: *const ModelsFile, provider_id: []const u8, model_id: []const u8) ?*const ModelConfig {
        const provider = self.findProvider(provider_id) orelse return null;
        for (provider.models) |*model| {
            if (std.mem.eql(u8, model.info.id, model_id)) return model;
        }
        return null;
    }
};

fn deinitSampling(gpa: std.mem.Allocator, params: []metadata.SamplingParam) void {
    for (params) |param| gpa.free(param.value_json);
    if (params.len > 0) gpa.free(params);
}

fn deinitCost(gpa: std.mem.Allocator, cost: providers.ModelCost) void {
    if (cost.tiers.len > 0) gpa.free(cost.tiers);
}

fn deinitModelConfig(gpa: std.mem.Allocator, model: ModelConfig) void {
    deinitSampling(gpa, model.sampling_params);
    if (model.headers.len > 0) gpa.free(model.headers);
    deinitCost(gpa, model.info.cost);
}

fn deinitModelOverride(gpa: std.mem.Allocator, override: ModelOverride) void {
    deinitSampling(gpa, override.sampling_params);
    if (override.headers.len > 0) gpa.free(override.headers);
    if (override.cost) |cost| deinitCost(gpa, cost);
}

fn parseHeaders(gpa: std.mem.Allocator, object: std.json.ObjectMap, field_name: []const u8) ![]metadata.Header {
    const value = object.get(field_name) orelse return &.{};
    if (value != .object) return error.InvalidModelConfig;
    var out: std.ArrayList(metadata.Header) = .empty;
    errdefer out.deinit(gpa);
    var it = value.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) return error.InvalidModelConfig;
        try out.append(gpa, .{ .name = entry.key_ptr.*, .value = entry.value_ptr.string });
    }
    return try out.toOwnedSlice(gpa);
}

fn parseSamplingParams(gpa: std.mem.Allocator, object: std.json.ObjectMap) ![]metadata.SamplingParam {
    const value = object.get("samplingParams") orelse return &.{};
    if (value != .object) return error.InvalidModelConfig;
    var out: std.ArrayList(metadata.SamplingParam) = .empty;
    errdefer {
        for (out.items) |param| gpa.free(param.value_json);
        out.deinit(gpa);
    }
    var it = value.object.iterator();
    while (it.next()) |entry| {
        var buf: std.Io.Writer.Allocating = .init(gpa);
        errdefer buf.deinit();
        try std.json.Stringify.value(entry.value_ptr.*, .{}, &buf.writer);
        const raw = try buf.toOwnedSlice();
        try out.append(gpa, .{ .name = entry.key_ptr.*, .value_json = raw });
    }
    return try out.toOwnedSlice(gpa);
}

fn optionalCompatBool(object: std.json.ObjectMap, name: []const u8) !?bool {
    const value = object.get(name) orelse return null;
    if (value != .bool) return error.InvalidModelConfig;
    return value.bool;
}

fn optionalChatTemplateValues(object: std.json.ObjectMap, name: []const u8) !?std.json.ObjectMap {
    const value = object.get(name) orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    var it = value.object.iterator();
    while (it.next()) |entry| {
        const item = entry.value_ptr.*;
        switch (item) {
            .string, .integer, .float, .bool, .null => {},
            .object => {
                const variable = item.object.get("$var") orelse return error.InvalidModelConfig;
                if (variable != .string or
                    (!std.mem.eql(u8, variable.string, "thinking.enabled") and !std.mem.eql(u8, variable.string, "thinking.effort")))
                    return error.InvalidModelConfig;
                if (item.object.get("omitWhenOff")) |omit| if (omit != .bool) return error.InvalidModelConfig;
            },
            else => return error.InvalidModelConfig,
        }
    }
    return value.object;
}

fn validateStringArray(value: std.json.Value) ![]const std.json.Value {
    if (value != .array) return error.InvalidModelConfig;
    for (value.array.items) |item| if (item != .string) return error.InvalidModelConfig;
    return value.array.items;
}

fn validatePercentileCutoffs(value: std.json.Value) !void {
    if (value == .integer or value == .float) return;
    if (value != .object) return error.InvalidModelConfig;
    var it = value.object.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!std.mem.eql(u8, key, "p50") and !std.mem.eql(u8, key, "p75") and !std.mem.eql(u8, key, "p90") and !std.mem.eql(u8, key, "p99")) return error.InvalidModelConfig;
        if (entry.value_ptr.* != .integer and entry.value_ptr.* != .float) return error.InvalidModelConfig;
    }
}

fn parseOpenRouterRouting(compat: std.json.ObjectMap) !?metadata.OpenRouterRouting {
    const value = compat.get("openRouterRouting") orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    const o = value.object;
    var out: metadata.OpenRouterRouting = .{};
    if (o.get("allow_fallbacks")) |v| {
        if (v != .bool) return error.InvalidModelConfig;
        out.allow_fallbacks = v.bool;
    }
    if (o.get("require_parameters")) |v| {
        if (v != .bool) return error.InvalidModelConfig;
        out.require_parameters = v.bool;
    }
    if (o.get("data_collection")) |v| {
        if (v != .string or (!std.mem.eql(u8, v.string, "deny") and !std.mem.eql(u8, v.string, "allow"))) return error.InvalidModelConfig;
        out.data_collection = v.string;
    }
    if (o.get("zdr")) |v| {
        if (v != .bool) return error.InvalidModelConfig;
        out.zdr = v.bool;
    }
    if (o.get("enforce_distillable_text")) |v| {
        if (v != .bool) return error.InvalidModelConfig;
        out.enforce_distillable_text = v.bool;
    }
    if (o.get("order")) |v| out.order = try validateStringArray(v);
    if (o.get("only")) |v| out.only = try validateStringArray(v);
    if (o.get("ignore")) |v| out.ignore = try validateStringArray(v);
    if (o.get("quantizations")) |v| out.quantizations = try validateStringArray(v);
    if (o.get("sort")) |v| {
        if (v == .string) {
            out.sort = v;
        } else if (v == .object) {
            var it = v.object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const item = entry.value_ptr.*;
                if (std.mem.eql(u8, key, "by")) {
                    if (item != .string) return error.InvalidModelConfig;
                } else if (std.mem.eql(u8, key, "partition")) {
                    if (item != .string and item != .null) return error.InvalidModelConfig;
                } else return error.InvalidModelConfig;
            }
            out.sort = v;
        } else return error.InvalidModelConfig;
    }
    if (o.get("max_price")) |v| {
        if (v != .object) return error.InvalidModelConfig;
        var it = v.object.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            if (!std.mem.eql(u8, key, "prompt") and !std.mem.eql(u8, key, "completion") and !std.mem.eql(u8, key, "image") and !std.mem.eql(u8, key, "audio") and !std.mem.eql(u8, key, "request")) return error.InvalidModelConfig;
            const item = entry.value_ptr.*;
            if (item != .integer and item != .float and item != .string) return error.InvalidModelConfig;
        }
        out.max_price = v.object;
    }
    if (o.get("preferred_min_throughput")) |v| {
        try validatePercentileCutoffs(v);
        out.preferred_min_throughput = v;
    }
    if (o.get("preferred_max_latency")) |v| {
        try validatePercentileCutoffs(v);
        out.preferred_max_latency = v;
    }
    return out;
}

fn parseVercelGatewayRouting(compat: std.json.ObjectMap) !?metadata.VercelGatewayRouting {
    const value = compat.get("vercelGatewayRouting") orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    var out: metadata.VercelGatewayRouting = .{};
    if (value.object.get("only")) |v| out.only = try validateStringArray(v);
    if (value.object.get("order")) |v| out.order = try validateStringArray(v);
    return out;
}

fn parseCompat(object: std.json.ObjectMap) !metadata.Compat {
    const value = object.get("compat") orelse return .{};
    if (value != .object) return error.InvalidModelConfig;
    const compat = value.object;
    var out: metadata.Compat = .{
        .supports_store = try optionalCompatBool(compat, "supportsStore"),
        .supports_developer_role = try optionalCompatBool(compat, "supportsDeveloperRole"),
        .supports_reasoning_effort = try optionalCompatBool(compat, "supportsReasoningEffort"),
        .supports_usage_in_streaming = try optionalCompatBool(compat, "supportsUsageInStreaming"),
        .supports_finish_reason = try optionalCompatBool(compat, "supportsFinishReason"),
        .zai_tool_stream = try optionalCompatBool(compat, "zaiToolStream"),
        .supports_strict_mode = try optionalCompatBool(compat, "supportsStrictMode"),
        .supports_openai_grammar_tools = try optionalCompatBool(compat, "supportsOpenAIGrammarTools"),
        .supports_tool_search = try optionalCompatBool(compat, "supportsToolSearch"),
        .supports_tool_references = try optionalCompatBool(compat, "supportsToolReferences"),
        .supports_eager_tool_input_streaming = try optionalCompatBool(compat, "supportsEagerToolInputStreaming"),
        .supports_cache_control_on_tools = try optionalCompatBool(compat, "supportsCacheControlOnTools"),
        .supports_temperature = try optionalCompatBool(compat, "supportsTemperature"),
        .force_adaptive_thinking = try optionalCompatBool(compat, "forceAdaptiveThinking"),
        .supports_strict_tools = try optionalCompatBool(compat, "supportsStrictTools"),
        .requires_tool_result_name = try optionalCompatBool(compat, "requiresToolResultName"),
        .requires_assistant_after_tool_result = try optionalCompatBool(compat, "requiresAssistantAfterToolResult"),
        .requires_thinking_as_text = try optionalCompatBool(compat, "requiresThinkingAsText"),
        .requires_reasoning_content_on_assistant_messages = try optionalCompatBool(compat, "requiresReasoningContentOnAssistantMessages"),
        .allow_empty_signature = try optionalCompatBool(compat, "allowEmptySignature"),
        .supports_long_cache_retention = try optionalCompatBool(compat, "supportsLongCacheRetention"),
        .supports_explicit_prompt_cache_mode = try optionalCompatBool(compat, "supportsExplicitPromptCacheMode"),
        .send_session_affinity_headers = try optionalCompatBool(compat, "sendSessionAffinityHeaders"),
        .chat_template_kwargs = try optionalChatTemplateValues(compat, "chatTemplateKwargs"),
        .chat_template_args = try optionalChatTemplateValues(compat, "chatTemplateArgs"),
        .openrouter_routing = try parseOpenRouterRouting(compat),
        .vercel_gateway_routing = try parseVercelGatewayRouting(compat),
    };
    if (stringField(compat, "deferredToolsMode")) |mode| {
        out.deferred_tools_mode = metadata.DeferredToolsMode.parse(mode) orelse return error.InvalidModelConfig;
    }
    if (stringField(compat, "maxTokensField")) |field| {
        out.max_tokens_field = metadata.MaxTokensField.parse(field) orelse return error.InvalidModelConfig;
    }
    if (stringField(compat, "thinkingFormat")) |format| {
        out.thinking_format = metadata.ThinkingFormat.parse(format) orelse return error.InvalidModelConfig;
    }
    if (stringField(compat, "sessionAffinityFormat")) |format| {
        out.session_affinity_format = metadata.SessionAffinityFormat.parse(format) orelse return error.InvalidModelConfig;
    }
    if (stringField(compat, "cacheControlFormat")) |format| {
        out.cache_control_format = metadata.CacheControlFormat.parse(format) orelse return error.InvalidModelConfig;
    }
    return out;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return if (value == .string) value.string else null;
}

fn boolField(object: std.json.ObjectMap, name: []const u8, default: bool) bool {
    const value = object.get(name) orelse return default;
    return if (value == .bool) value.bool else default;
}

fn optionalBoolField(object: std.json.ObjectMap, name: []const u8) ?bool {
    const value = object.get(name) orelse return null;
    return if (value == .bool) value.bool else null;
}

fn intField(object: std.json.ObjectMap, name: []const u8) ?u64 {
    const value = object.get(name) orelse return null;
    if (value != .integer or value.integer < 0) return null;
    return @intCast(value.integer);
}

fn numberValue(value: std.json.Value) ?f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => null,
    };
}

fn parseInput(object: std.json.ObjectMap) struct { text: ?bool, image: ?bool } {
    const value = object.get("input") orelse return .{ .text = null, .image = null };
    if (value != .array) return .{ .text = null, .image = null };
    var text = false;
    var image = false;
    for (value.array.items) |item| {
        if (item != .string) continue;
        if (std.mem.eql(u8, item.string, "text")) text = true;
        if (std.mem.eql(u8, item.string, "image")) image = true;
    }
    return .{ .text = text, .image = image };
}

fn parseCostTiers(gpa: std.mem.Allocator, cost_object: std.json.ObjectMap) ![]const providers.ModelCostTier {
    const value = cost_object.get("tiers") orelse return &.{};
    if (value != .array) return error.InvalidModelConfig;
    var out: std.ArrayList(providers.ModelCostTier) = .empty;
    errdefer out.deinit(gpa);
    for (value.array.items) |item| {
        if (item != .object) return error.InvalidModelConfig;
        const threshold_v = item.object.get("inputTokensAbove") orelse return error.InvalidModelConfig;
        const threshold: u64 = if (threshold_v == .integer and threshold_v.integer >= 0) @intCast(threshold_v.integer) else return error.InvalidModelConfig;
        const input = item.object.get("input") orelse return error.InvalidModelConfig;
        const output = item.object.get("output") orelse return error.InvalidModelConfig;
        const cache_read = item.object.get("cacheRead") orelse return error.InvalidModelConfig;
        const cache_write = item.object.get("cacheWrite") orelse return error.InvalidModelConfig;
        try out.append(gpa, .{
            .input_tokens_above = threshold,
            .input = numberValue(input) orelse return error.InvalidModelConfig,
            .output = numberValue(output) orelse return error.InvalidModelConfig,
            .cache_read = numberValue(cache_read) orelse return error.InvalidModelConfig,
            .cache_write = numberValue(cache_write) orelse return error.InvalidModelConfig,
        });
    }
    return try out.toOwnedSlice(gpa);
}

fn parseCost(gpa: std.mem.Allocator, object: std.json.ObjectMap) !?providers.ModelCost {
    const value = object.get("cost") orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    const input = value.object.get("input") orelse return error.InvalidModelConfig;
    const output = value.object.get("output") orelse return error.InvalidModelConfig;
    const cache_read = value.object.get("cacheRead") orelse return error.InvalidModelConfig;
    const cache_write = value.object.get("cacheWrite") orelse return error.InvalidModelConfig;
    return .{
        .input = numberValue(input) orelse return error.InvalidModelConfig,
        .output = numberValue(output) orelse return error.InvalidModelConfig,
        .cache_read = numberValue(cache_read) orelse return error.InvalidModelConfig,
        .cache_write = numberValue(cache_write) orelse return error.InvalidModelConfig,
        .tiers = try parseCostTiers(gpa, value.object),
    };
}

fn parsePartialCost(gpa: std.mem.Allocator, object: std.json.ObjectMap) !?providers.ModelCost {
    const value = object.get("cost") orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    var cost: providers.ModelCost = .{};
    if (value.object.get("input")) |v| cost.input = numberValue(v) orelse return error.InvalidModelConfig;
    if (value.object.get("output")) |v| cost.output = numberValue(v) orelse return error.InvalidModelConfig;
    if (value.object.get("cacheRead")) |v| cost.cache_read = numberValue(v) orelse return error.InvalidModelConfig;
    if (value.object.get("cacheWrite")) |v| cost.cache_write = numberValue(v) orelse return error.InvalidModelConfig;
    cost.tiers = try parseCostTiers(gpa, value.object);
    return cost;
}

fn parseThinkingMap(object: std.json.ObjectMap, name: []const u8) !?thinking.ThinkingLevelMap {
    const value = object.get(name) orelse return null;
    if (value != .object) return error.InvalidModelConfig;
    var map = thinking.ThinkingLevelMap{};
    inline for (std.meta.fields(thinking.ThinkingLevel)) |field| {
        if (value.object.get(field.name)) |entry| {
            const slot = &@field(map, field.name);
            if (entry == .null) {
                slot.* = .unsupported;
            } else if (entry == .string) {
                slot.* = .{ .mapped = entry.string };
            } else {
                return error.InvalidModelConfig;
            }
        }
    }
    return map;
}

fn inheritedApi(provider_id: []const u8) ?Api {
    if (std.ascii.eqlIgnoreCase(provider_id, "google-vertex")) return .google_vertex;
    const builtin = providers.Provider.fromString(provider_id) orelse return null;
    if (builtin == .mistral) return .mistral_conversations;
    if (builtin == .radius) return .pi_messages;
    if (builtin == .amazon_bedrock) return .bedrock_converse_stream;
    return switch (builtin.transport()) {
        .openai, .mock => .openai_completions,
        .anthropic => .anthropic_messages,
        .google => .google_generative_ai,
        else => null,
    };
}

pub fn load(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !ModelsFile {
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{ .gpa = gpa },
        else => return err,
    };
    defer gpa.free(raw);
    return parseFromSlice(gpa, raw);
}

/// Parse an upstream-compatible models.json document from memory. Extension
/// provider registration uses the same validator and runtime metadata path as
/// the on-disk file, avoiding a weaker second provider dialect.
pub fn parseFromSlice(gpa: std.mem.Allocator, raw: []const u8) !ModelsFile {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidModelsJson;
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelsJson;
    const providers_value = parsed.value.object.get("providers") orelse return .{ .gpa = gpa, .parsed = parsed };
    if (providers_value != .object) return error.InvalidModelsJson;

    var provider_list: std.ArrayList(ProviderConfig) = .empty;
    errdefer {
        for (provider_list.items) |provider| {
            for (provider.models) |model| deinitModelConfig(gpa, model);
            gpa.free(provider.models);
            for (provider.model_overrides) |override| deinitModelOverride(gpa, override);
            if (provider.model_overrides.len > 0) gpa.free(provider.model_overrides);
            if (provider.headers.len > 0) gpa.free(provider.headers);
        }
        provider_list.deinit(gpa);
    }
    var all_models: std.ArrayList(providers.ModelInfo) = .empty;
    errdefer all_models.deinit(gpa);

    var provider_it = providers_value.object.iterator();
    while (provider_it.next()) |entry| {
        const provider_id = entry.key_ptr.*;
        if (entry.value_ptr.* != .object) return error.InvalidProviderConfig;
        const object = entry.value_ptr.object;
        const provider_name = stringField(object, "name") orelse provider_id;
        const base_url = stringField(object, "baseUrl");
        const api_key = stringField(object, "apiKey");
        const oauth: ?OAuthProvider = if (stringField(object, "oauth")) |oauth_name|
            if (std.mem.eql(u8, oauth_name, "radius")) .radius else return error.UnsupportedProviderOAuth
        else
            null;
        if (oauth == .radius and base_url == null) return error.MissingBaseUrl;
        const provider_api = if (stringField(object, "api")) |api_name|
            Api.parse(api_name) orelse return error.UnsupportedModelApi
        else if (oauth == .radius)
            Api.pi_messages
        else
            inheritedApi(provider_id);
        const provider_headers = try parseHeaders(gpa, object, "headers");
        errdefer if (provider_headers.len > 0) gpa.free(provider_headers);
        const provider_compat = try parseCompat(object);

        var model_list: std.ArrayList(ModelConfig) = .empty;
        errdefer model_list.deinit(gpa);
        if (object.get("models")) |models_value| {
            if (models_value != .array) return error.InvalidProviderConfig;
            for (models_value.array.items) |model_value| {
                if (model_value != .object) return error.InvalidModelConfig;
                const model_object = model_value.object;
                const model_id = stringField(model_object, "id") orelse return error.InvalidModelConfig;
                const model_name = stringField(model_object, "name") orelse model_id;
                const model_api = if (stringField(model_object, "api")) |api_name|
                    Api.parse(api_name) orelse return error.UnsupportedModelApi
                else
                    provider_api orelse return error.MissingModelApi;
                const model_base_url = stringField(model_object, "baseUrl");
                if (base_url == null and model_base_url == null and providers.Provider.fromString(provider_id) == null and !std.ascii.eqlIgnoreCase(provider_id, "google-vertex")) {
                    return error.MissingBaseUrl;
                }
                const model_input = parseInput(model_object);
                const context_window = intField(model_object, "contextWindow");
                const max_tokens = intField(model_object, "maxTokens");
                if (context_window != null and context_window.? == 0) return error.InvalidModelConfig;
                if (max_tokens != null and max_tokens.? == 0) return error.InvalidModelConfig;
                const sampling_params = try parseSamplingParams(gpa, model_object);
                errdefer deinitSampling(gpa, sampling_params);
                const model_headers = try parseHeaders(gpa, model_object, "headers");
                errdefer if (model_headers.len > 0) gpa.free(model_headers);
                const model_compat = metadata.Compat.merge(provider_compat, try parseCompat(model_object));
                const info = providers.ModelInfo{
                    .provider = model_api.nativeProvider(),
                    .provider_id = provider_id,
                    .api = model_api,
                    .id = model_id,
                    .display = model_name,
                    .base_url = model_base_url orelse base_url,
                    .reasoning = boolField(model_object, "reasoning", false),
                    .thinking_level_map = try parseThinkingMap(model_object, "thinkingLevelMap"),
                    .input_text = model_input.text orelse true,
                    .input_image = model_input.image orelse false,
                    .context_window = context_window orelse 128_000,
                    .max_tokens = max_tokens orelse 16_384,
                    .cost = (try parseCost(gpa, model_object)) orelse .{},
                };
                try model_list.append(gpa, .{
                    .info = info,
                    .api = model_api,
                    .base_url = model_base_url,
                    .context_window = context_window,
                    .max_tokens = max_tokens,
                    .sampling_params = sampling_params,
                    .headers = model_headers,
                    .compat = model_compat,
                });
                try all_models.append(gpa, info);
            }
        }

        var override_list: std.ArrayList(ModelOverride) = .empty;
        errdefer override_list.deinit(gpa);
        if (object.get("modelOverrides")) |overrides_value| {
            if (overrides_value != .object) return error.InvalidProviderConfig;
            var override_it = overrides_value.object.iterator();
            while (override_it.next()) |override_entry| {
                if (override_entry.value_ptr.* != .object) return error.InvalidModelConfig;
                const override_object = override_entry.value_ptr.object;
                try override_list.append(gpa, .{
                    .id = override_entry.key_ptr.*,
                    .name = stringField(override_object, "name"),
                    .reasoning = optionalBoolField(override_object, "reasoning"),
                    .thinking_level_map = try parseThinkingMap(override_object, "thinkingLevelMap"),
                    .input_text = parseInput(override_object).text,
                    .input_image = parseInput(override_object).image,
                    .cost = try parsePartialCost(gpa, override_object),
                    .context_window = intField(override_object, "contextWindow"),
                    .max_tokens = intField(override_object, "maxTokens"),
                    .sampling_params = try parseSamplingParams(gpa, override_object),
                    .headers = try parseHeaders(gpa, override_object, "headers"),
                    .compat = try parseCompat(override_object),
                });
            }
        }

        try provider_list.append(gpa, .{
            .id = provider_id,
            .name = provider_name,
            .base_url = base_url,
            .api_key = api_key,
            .api = provider_api,
            .oauth = oauth,
            .auth_header = boolField(object, "authHeader", false),
            .headers = provider_headers,
            .compat = provider_compat,
            .models = try model_list.toOwnedSlice(gpa),
            .model_overrides = try override_list.toOwnedSlice(gpa),
        });
    }

    return .{
        .gpa = gpa,
        .parsed = parsed,
        .providers = try provider_list.toOwnedSlice(gpa),
        .model_infos = try all_models.toOwnedSlice(gpa),
    };
}

test "models.json loads arbitrary provider id and OpenAI-compatible models" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"my-company-proxy":{"name":"Corp Proxy","baseUrl":"https://proxy.example/v1","api":"openai-completions","apiKey":"$CORP_KEY","models":[{"id":"gpt-x","name":"GPT X","reasoning":true,"contextWindow":128000,"maxTokens":4096}]}}}
        ,
    });

    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    try std.testing.expectEqual(@as(usize, 1), file.providers.len);
    try std.testing.expectEqualStrings("my-company-proxy", file.providers[0].id);
    try std.testing.expectEqualStrings("$CORP_KEY", file.providers[0].api_key.?);
    try std.testing.expectEqual(@as(usize, 1), file.model_infos.len);
    const model = file.model_infos[0];
    try std.testing.expectEqualStrings("my-company-proxy", model.providerName());
    try std.testing.expect(model.provider == .openai);
    try std.testing.expect(model.reasoning);
    try std.testing.expectEqual(@as(u64, 128000), file.providers[0].models[0].context_window.?);
}

test "models.json accepts native pi-messages providers and radius inheritance" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = "{\"providers\":{\"radius\":{\"baseUrl\":\"https://radius.example\",\"models\":[{\"id\":\"auto\"}]},\"other-radius\":{\"baseUrl\":\"https://other.example\",\"api\":\"pi-messages\",\"models\":[{\"id\":\"r2\"}]}}}",
    });

    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const builtin = file.findModel("radius", "auto").?;
    try std.testing.expect(builtin.api == .pi_messages);
    try std.testing.expect(builtin.info.provider == .radius);
    const custom = file.findModel("other-radius", "r2").?;
    try std.testing.expect(custom.api == .pi_messages);
    try std.testing.expect(custom.info.provider == .radius);
    try std.testing.expectEqualStrings("other-radius", custom.info.providerName());
}

test "models.json accepts Bedrock API and built-in inheritance" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = "{\"providers\":{\"amazon-bedrock\":{\"baseUrl\":\"https://bedrock-runtime.eu-west-2.amazonaws.com\",\"models\":[{\"id\":\"anthropic.claude-test\"}]},\"corp-bedrock\":{\"baseUrl\":\"https://bedrock-proxy.example\",\"api\":\"bedrock-converse-stream\",\"apiKey\":\"$BEDROCK_PROXY_TOKEN\",\"models\":[{\"id\":\"profile/test\"}]}}}",
    });

    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const builtin = file.findModel("amazon-bedrock", "anthropic.claude-test").?;
    try std.testing.expect(builtin.api == .bedrock_converse_stream);
    try std.testing.expect(builtin.info.provider == .amazon_bedrock);
    const custom = file.findModel("corp-bedrock", "profile/test").?;
    try std.testing.expect(custom.api == .bedrock_converse_stream);
    try std.testing.expect(custom.info.provider == .amazon_bedrock);
    try std.testing.expectEqualStrings("corp-bedrock", custom.info.providerName());
}

test "models.json supports provider api inheritance and per-model API override" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"mixed":{"baseUrl":"https://example.test","api":"openai-completions","models":[{"id":"chat"},{"id":"claude","api":"anthropic-messages"}]}}}
        ,
    });
    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    try std.testing.expect(file.providers[0].models[0].api == .openai_completions);
    try std.testing.expect(file.providers[0].models[1].api == .anthropic_messages);
    try std.testing.expect(file.providers[0].models[1].info.provider == .anthropic);
}

test "models.json recognizes responses API but marks current runtime unsupported" {
    try std.testing.expect(Api.parse("openai-responses").? == .openai_responses);
    try std.testing.expect(Api.openai_responses.runtimeSupported());
    try std.testing.expect(Api.openai_completions.runtimeSupported());
}

test "models.json parses modelOverrides without fabricating omitted fields" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"openai":{"modelOverrides":{"gpt-4o":{"name":"My GPT","reasoning":true,"contextWindow":99999},"gpt-4.1":{"reasoning":false}}}}}
        ,
    });
    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const provider = file.findProvider("openai").?;
    try std.testing.expectEqual(@as(usize, 2), provider.model_overrides.len);
    const a = provider.findOverride("gpt-4o").?;
    try std.testing.expectEqualStrings("My GPT", a.name.?);
    try std.testing.expect(a.reasoning.?);
    try std.testing.expectEqual(@as(u64, 99999), a.context_window.?);
    const b = provider.findOverride("gpt-4.1").?;
    try std.testing.expect(!b.reasoning.?);
    try std.testing.expect(b.name == null);
}

test "models.json preserves thinkingLevelMap null holes and mapped max" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"corp":{"baseUrl":"https://example.test/v1","api":"openai-completions","models":[{"id":"r","reasoning":true,"thinkingLevelMap":{"minimal":null,"xhigh":"very_high","max":"maximum"}}]}}}
        ,
    });
    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const model = file.providers[0].models[0].info;
    var levels_buf: [7]thinking.ThinkingLevel = undefined;
    const levels = model.supportedThinkingLevels(&levels_buf);
    try std.testing.expectEqualSlices(thinking.ThinkingLevel, &.{ .off, .low, .medium, .high, .xhigh, .max }, levels);
    try std.testing.expectEqual(thinking.ThinkingLevel.low, model.clampThinkingLevel(.minimal));
    try std.testing.expectEqual(thinking.ThinkingLevel.max, model.clampThinkingLevel(.max));
}

test "models.json parses request metadata and applies upstream custom-model defaults" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"corp":{"baseUrl":"https://example.test/v1","api":"openai-completions","headers":{"X-Provider":"$P_HEADER"},"compat":{"supportsDeveloperRole":true,"supportsUsageInStreaming":true},"models":[{"id":"m","headers":{"X-Model":"literal"},"samplingParams":{"temperature":0.2,"top_p":0.9},"compat":{"supportsDeveloperRole":false,"maxTokensField":"max_tokens","thinkingFormat":"qwen"}}],"modelOverrides":{"m":{"headers":{"X-Override":"$O_HEADER"},"samplingParams":{"top_p":0.5},"compat":{"supportsReasoningEffort":false}}}}}}
    });
    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const provider = file.findProvider("corp").?;
    const model = file.findModel("corp", "m").?;
    const override = provider.findOverride("m").?;
    try std.testing.expectEqual(@as(u64, 128_000), model.info.context_window);
    try std.testing.expectEqual(@as(u64, 16_384), model.info.max_tokens);
    try std.testing.expectEqual(@as(usize, 1), provider.headers.len);
    try std.testing.expectEqual(@as(usize, 1), model.headers.len);
    try std.testing.expectEqual(@as(usize, 2), model.sampling_params.len);
    try std.testing.expectEqual(@as(usize, 1), override.sampling_params.len);
    try std.testing.expectEqual(false, model.compat.supports_developer_role.?);
    try std.testing.expectEqual(true, model.compat.supports_usage_in_streaming.?);
    try std.testing.expect(model.compat.max_tokens_field.? == .max_tokens);
    try std.testing.expect(model.compat.thinking_format.? == .qwen);
    try std.testing.expectEqual(false, override.compat.supports_reasoning_effort.?);
}

test "models.json parses cache retention and session affinity compat" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"corp":{"baseUrl":"https://example.test/v1","api":"openai-responses","compat":{"supportsLongCacheRetention":true,"supportsExplicitPromptCacheMode":true,"sendSessionAffinityHeaders":true,"sessionAffinityFormat":"openai-nosession","cacheControlFormat":"anthropic"},"models":[{"id":"m"}]}}}
    });
    var file = try load(gpa, io, agent_dir);
    defer file.deinit();
    const compat = file.providers[0].models[0].compat;
    try std.testing.expectEqual(true, compat.supports_long_cache_retention.?);
    try std.testing.expectEqual(true, compat.supports_explicit_prompt_cache_mode.?);
    try std.testing.expectEqual(true, compat.send_session_affinity_headers.?);
    try std.testing.expect(compat.session_affinity_format.? == .openai_nosession);
    try std.testing.expect(compat.cache_control_format.? == .anthropic);
}

test "models.json parses chat-template compat variables" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"corp":{"baseUrl":"https://example.test/v1","api":"openai-completions","models":[{"id":"r","reasoning":true,"thinkingLevelMap":{"high":"very_high"},"compat":{"thinkingFormat":"chat-template","chatTemplateKwargs":{"enable":{"$var":"thinking.enabled"},"effort":{"$var":"thinking.effort","omitWhenOff":true},"constant":7}}}]}}}
    });
    var file = try load(gpa, io, root);
    defer file.deinit();
    const model = file.findModel("corp", "r").?;
    try std.testing.expect(model.compat.thinking_format.? == .chat_template);
    const kwargs = model.compat.chat_template_kwargs.?;
    try std.testing.expect(kwargs.get("enable").? == .object);
    try std.testing.expectEqual(@as(i64, 7), kwargs.get("constant").?.integer);
}

test "models.json merges OpenRouter and Vercel routing compat by field" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"openrouter":{"baseUrl":"https://openrouter.ai/api/v1","api":"openai-completions","compat":{"openRouterRouting":{"order":["anthropic","google"],"data_collection":"deny"},"vercelGatewayRouting":{"order":["first"]}},"models":[{"id":"m","compat":{"openRouterRouting":{"only":["anthropic"],"zdr":true},"vercelGatewayRouting":{"only":["second"]}}}]}}}
    });
    var file = try load(gpa, io, root);
    defer file.deinit();
    const compat = file.findModel("openrouter", "m").?.compat;
    const openrouter = compat.openrouter_routing.?;
    try std.testing.expectEqualStrings("deny", openrouter.data_collection.?);
    try std.testing.expect(openrouter.zdr.?);
    try std.testing.expectEqualStrings("anthropic", openrouter.order.?[0].string);
    try std.testing.expectEqualStrings("anthropic", openrouter.only.?[0].string);
    const vercel = compat.vercel_gateway_routing.?;
    try std.testing.expectEqualStrings("first", vercel.order.?[0].string);
    try std.testing.expectEqualStrings("second", vercel.only.?[0].string);
}

test "models.json accepts custom Radius OAuth provider without static models" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"radius-dev":{"name":"Radius Dev","baseUrl":"http://localhost:8788","oauth":"radius"}}}
    });
    var file = try load(gpa, io, root);
    defer file.deinit();
    const provider = file.findProvider("radius-dev").?;
    try std.testing.expect(provider.oauth.? == .radius);
    try std.testing.expect(provider.api.? == .pi_messages);
    try std.testing.expectEqual(@as(usize, 0), provider.models.len);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"radius-bad":{"oauth":"radius"}}}
    });
    try std.testing.expectError(error.MissingBaseUrl, load(gpa, io, root));
}
