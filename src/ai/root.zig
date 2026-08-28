//! AI package: native provider clients and model metadata.
const std = @import("std");

pub const providers = @import("providers.zig");
pub const http_proxy = @import("http_proxy.zig");
pub const http_fetch = @import("http_fetch.zig");
pub const bootstrap_http = @import("bootstrap_http.zig");
pub const openai = @import("openai.zig");
pub const openai_responses = @import("openai_responses.zig");
pub const codex_websocket = @import("codex_websocket.zig");
pub const anthropic = @import("anthropic.zig");
pub const google = @import("google.zig");
pub const google_adc = @import("google_adc.zig");
pub const mistral = @import("mistral.zig");
pub const bedrock = @import("bedrock.zig");
pub const pi_messages = @import("pi_messages.zig");
pub const radius_config = @import("radius_config.zig");
pub const mock = @import("mock.zig");
pub const stream = @import("stream.zig");
pub const images = @import("images.zig");
pub const image_process = @import("image_process.zig");
pub const openrouter_images = @import("openrouter_images.zig");
pub const thinking = @import("thinking.zig");
pub const catalog = @import("catalog.zig");
pub const request_metadata = @import("request_metadata.zig");
pub const retry = @import("retry.zig");
pub const github_copilot = @import("github_copilot.zig");
pub const tool_arguments = @import("tool_arguments.zig");
pub const cost = @import("cost.zig");
pub const api = @import("api.zig");

pub const Provider = providers.Provider;
pub const resolveApiKey = providers.resolveApiKey;
pub const resolveProvider = providers.resolveProvider;
pub const StreamDelta = stream.StreamDelta;
pub const StreamHandler = stream.StreamHandler;

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    arguments: []const u8,
    /// Opaque Gemini function-call thought signature. Safe to replay only to the same provider/model.
    thought_signature: []const u8 = "",

    pub fn deinit(self: *ToolCall, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.name);
        gpa.free(self.arguments);
        if (self.thought_signature.len > 0) gpa.free(self.thought_signature);
        self.* = undefined;
    }
};

pub const Usage = cost.Usage;
pub const Cost = cost.Cost;

pub const ModelResponse = struct {
    content: []const u8,
    /// Provider-returned reasoning/thinking text retained for replay.
    thinking: []const u8 = "",
    /// Opaque provider signature for thinking continuity (Anthropic/redacted blocks).
    thinking_signature: []const u8 = "",
    tool_calls: []ToolCall,
    provider: []const u8 = "",
    /// API protocol identity used to produce this assistant response.
    api: []const u8 = "",
    /// Requested model identity. Routers may report a different response_model.
    model: []const u8 = "",
    response_id: []const u8 = "",
    response_model: []const u8 = "",
    /// Raw JSON array of redacted provider/runtime diagnostics. Diagnostics are
    /// server-side metadata and are never replayed into model context.
    diagnostics_json: []const u8 = "",
    /// Provider/API error text kept separate from partial assistant content.
    error_message: []const u8 = "",
    /// Provider-native terminal reason preserved alongside normalized stop_reason.
    raw_stop_reason: []const u8 = "",
    stop_reason: []const u8 = "",
    usage: Usage = .{},
    /// Request-local HTTP metadata used only by the provider retry wrapper.
    /// Session and protocol serializers intentionally omit these fields.
    provider_status: ?u16 = null,
    provider_retry_after_ms: ?u64 = null,
    provider_should_retry: ?bool = null,

    pub fn deinit(self: *ModelResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.thinking.len > 0) gpa.free(self.thinking);
        if (self.thinking_signature.len > 0) gpa.free(self.thinking_signature);
        for (self.tool_calls) |*tc| tc.deinit(gpa);
        gpa.free(self.tool_calls);
        if (self.provider.len > 0) gpa.free(self.provider);
        if (self.api.len > 0) gpa.free(self.api);
        if (self.model.len > 0) gpa.free(self.model);
        if (self.response_id.len > 0) gpa.free(self.response_id);
        if (self.response_model.len > 0) gpa.free(self.response_model);
        if (self.diagnostics_json.len > 0) gpa.free(self.diagnostics_json);
        if (self.error_message.len > 0) gpa.free(self.error_message);
        if (self.raw_stop_reason.len > 0) gpa.free(self.raw_stop_reason);
        if (self.stop_reason.len > 0) gpa.free(self.stop_reason);
        self.* = undefined;
    }

    pub fn providerRetryMeta(self: ModelResponse) retry.ProviderResponseMeta {
        return .{
            .status = self.provider_status,
            .retry_after_ms = self.provider_retry_after_ms,
            .should_retry = self.provider_should_retry,
        };
    }

    pub fn ensureStopReason(self: *ModelResponse, gpa: std.mem.Allocator) !void {
        if (self.stop_reason.len > 0) return;
        self.stop_reason = try gpa.dupe(u8, if (self.tool_calls.len > 0) "toolUse" else "stop");
    }

    /// Replace the protocol identity with owned storage. Concrete clients call
    /// this at their ModelClient boundary so success/error/abort responses all
    /// retain the API that produced them.
    pub fn setApi(self: *ModelResponse, gpa: std.mem.Allocator, api_name: []const u8) !void {
        if (self.api.len > 0) gpa.free(self.api);
        self.api = try gpa.dupe(u8, api_name);
    }

    pub fn normalizeToolArguments(self: *ModelResponse, gpa: std.mem.Allocator) !void {
        for (self.tool_calls) |*tool_call| {
            const normalized = try tool_arguments.normalize(gpa, tool_call.arguments);
            gpa.free(tool_call.arguments);
            tool_call.arguments = normalized;
        }
    }
};

pub const ChatImage = struct {
    data_b64: []const u8,
    mime_type: []const u8,
};

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
    /// Internal allocator-ownership marker used by context projections that
    /// synthesize summary wrappers. Provider serializers ignore this field.
    owned_content: bool = false,
    /// Extension custom-message identity. Providers ignore it, while the
    /// pre-provider context hook uses it to filter or retain injected context.
    custom_type: ?[]const u8 = null,
    /// Original assistant model identity. Used to gate provider-specific opaque replay metadata.
    provider: ?[]const u8 = null,
    api: ?[]const u8 = null,
    model: ?[]const u8 = null,
    response_id: ?[]const u8 = null,
    response_model: ?[]const u8 = null,
    raw_stop_reason: ?[]const u8 = null,
    /// Replayed assistant thinking/reasoning text, when the provider exposed it.
    thinking: ?[]const u8 = null,
    thinking_signature: ?[]const u8 = null,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,
    tool_name: ?[]const u8 = null,
    /// Tool definitions that became available at this tool-result boundary.
    /// Used by deferred-tool transports to replay client-side tool loading.
    added_tool_names: []const []const u8 = &.{},
    /// Native tool-result failure bit, preserved for Pi-native transports.
    tool_is_error: bool = false,
    /// Historical assistant terminal metadata. Pi-native gateways replay this
    /// verbatim instead of fabricating zero usage / a guessed stop reason.
    stop_reason: ?[]const u8 = null,
    /// ISO-8601 session timestamp when available. Used to reject stale usage
    /// snapshots after compaction/branch prefix insertion.
    timestamp: ?[]const u8 = null,
    usage: Usage = .{},
    /// Legacy single-image representation retained for old JSONL/checkpoint
    /// readers. New callers should populate `images`; adapters serialize both.
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
    /// Ordered image blocks carried by this message. The text projection stays
    /// in `content`, matching the native rewrite's compact message structure.
    images: []const ChatImage = &.{},

    pub fn imageCount(self: ChatMessage) usize {
        return @as(usize, @intFromBool(self.image_b64 != null)) + self.images.len;
    }

    pub fn hasImages(self: ChatMessage) bool {
        return self.image_b64 != null or self.images.len > 0;
    }

    pub fn imageAt(self: ChatMessage, index: usize) ?ChatImage {
        if (self.image_b64) |data| {
            if (index == 0) return .{ .data_b64 = data, .mime_type = self.image_mime orelse "image/png" };
            const adjusted = index - 1;
            if (adjusted < self.images.len) return self.images[adjusted];
            return null;
        }
        if (index < self.images.len) return self.images[index];
        return null;
    }
};

pub const ThinkingLevel = thinking.ThinkingLevel;

pub const CompletionOptions = struct {
    /// Request-local output cap. Zero preserves the model/provider default.
    max_tokens: u64 = 0,
    /// Detached one-shot work such as compaction and branch summaries must not
    /// reuse the live conversation prompt cache or session-affinity identity.
    isolate_cache: bool = false,
};

pub fn resolveMaxTokens(configured: u64, requested: u64) u64 {
    if (requested == 0) return configured;
    if (configured == 0) return requested;
    return @min(configured, requested);
}

pub fn resolveCacheRetention(configured: request_metadata.CacheRetention, options: CompletionOptions) request_metadata.CacheRetention {
    return if (options.isolate_cache) .none else configured;
}

pub fn resolveSessionAffinity(configured: ?[]const u8, options: CompletionOptions) ?[]const u8 {
    return if (options.isolate_cache) null else configured;
}

pub const StreamCompleteFn = *const fn (*anyopaque, std.mem.Allocator, []const ChatMessage, []const u8, ?StreamHandler, ?*anyopaque) anyerror!ModelResponse;
pub const CompleteOptionsFn = *const fn (*anyopaque, std.mem.Allocator, []const ChatMessage, []const u8, CompletionOptions) anyerror!ModelResponse;
pub const FetchDeferredFn = *const fn (*anyopaque, std.mem.Allocator, []const u8, []const u8, ?StreamHandler, ?*anyopaque) anyerror!ModelResponse;
pub const CancelDeferredFn = *const fn (*anyopaque, []const u8, []const u8) anyerror!void;

pub const ModelClient = struct {
    ptr: *anyopaque,
    completeFn: *const fn (*anyopaque, std.mem.Allocator, []const ChatMessage, []const u8) anyerror!ModelResponse,
    completeOptionsFn: ?CompleteOptionsFn = null,
    streamFn: ?StreamCompleteFn = null,
    fetchDeferredFn: ?FetchDeferredFn = null,
    cancelDeferredFn: ?CancelDeferredFn = null,

    pub fn complete(self: ModelClient, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8) !ModelResponse {
        return self.completeFn(self.ptr, gpa, messages, tools_json);
    }

    pub fn completeWithOptions(self: ModelClient, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8, options: CompletionOptions) !ModelResponse {
        if (self.completeOptionsFn) |complete_options| return complete_options(self.ptr, gpa, messages, tools_json, options);
        return self.complete(gpa, messages, tools_json);
    }

    pub fn completeStreaming(self: ModelClient, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8, on_delta: ?StreamHandler, delta_ctx: ?*anyopaque) !ModelResponse {
        if (self.streamFn) |sf| return sf(self.ptr, gpa, messages, tools_json, on_delta, delta_ctx);
        const resp = try self.complete(gpa, messages, tools_json);
        if (on_delta) |h| {
            if (resp.content.len > 0) h(delta_ctx, .{ .kind = .text_delta, .text = resp.content });
            for (resp.tool_calls) |tc| h(delta_ctx, .{ .kind = .tool_call_delta, .tool_call_id = tc.id, .tool_name = tc.name, .tool_arguments = tc.arguments });
            h(delta_ctx, .{ .kind = .done });
        }
        return resp;
    }

    pub fn fetchDeferred(
        self: ModelClient,
        gpa: std.mem.Allocator,
        handle_json: []const u8,
        options_json: []const u8,
        on_delta: ?StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ModelResponse {
        const fetch = self.fetchDeferredFn orelse return error.DeferredResponsesUnsupported;
        return fetch(self.ptr, gpa, handle_json, options_json, on_delta, delta_ctx);
    }

    pub fn cancelDeferred(self: ModelClient, handle_json: []const u8, options_json: []const u8) !void {
        const cancel = self.cancelDeferredFn orelse return error.DeferredResponsesUnsupported;
        return cancel(self.ptr, handle_json, options_json);
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "request-local output caps respect configured model limits" {
    try std.testing.expectEqual(@as(u64, 0), resolveMaxTokens(0, 0));
    try std.testing.expectEqual(@as(u64, 4096), resolveMaxTokens(4096, 0));
    try std.testing.expectEqual(@as(u64, 2048), resolveMaxTokens(0, 2048));
    try std.testing.expectEqual(@as(u64, 1024), resolveMaxTokens(1024, 2048));
    try std.testing.expectEqual(@as(u64, 2048), resolveMaxTokens(8192, 2048));

    const live: CompletionOptions = .{};
    const isolated: CompletionOptions = .{ .isolate_cache = true };
    try std.testing.expect(resolveCacheRetention(.long, live) == .long);
    try std.testing.expect(resolveCacheRetention(.long, isolated) == .none);
    try std.testing.expectEqualStrings("session", resolveSessionAffinity("session", live).?);
    try std.testing.expect(resolveSessionAffinity("session", isolated) == null);
}

test "chat messages expose legacy and ordered image arrays" {
    const message: ChatMessage = .{
        .role = "tool",
        .content = "capture",
        .image_b64 = "AA==",
        .image_mime = "image/jpeg",
        .images = &.{
            .{ .data_b64 = "AQ==", .mime_type = "image/png" },
            .{ .data_b64 = "Ag==", .mime_type = "image/webp" },
        },
    };
    try std.testing.expect(message.hasImages());
    try std.testing.expectEqual(@as(usize, 3), message.imageCount());
    try std.testing.expectEqualStrings("image/jpeg", message.imageAt(0).?.mime_type);
    try std.testing.expectEqualStrings("AQ==", message.imageAt(1).?.data_b64);
    try std.testing.expect(message.imageAt(3) == null);
}
