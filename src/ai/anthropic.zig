//! Anthropic Messages API + tools (complete + stream SSE).
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const constrained = @import("constrained_sampling.zig");
const stream_mod = @import("stream.zig");
const metadata = @import("request_metadata.zig");
const providers = @import("providers.zig");
const cost_mod = @import("cost.zig");
const cloudflare = @import("cloudflare.zig");
const copilot = @import("github_copilot.zig");
const anthropic_oauth = @import("../auth/anthropic_oauth.zig");

pub const TokenRefreshFn = *const fn (*anyopaque, *AnthropicClient, i64) anyerror!void;
pub const AuthMode = enum { api_key, bearer, oauth };

pub const AnthropicClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Process/provider proxy environment.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback.
    proxy_url: ?[]const u8 = null,
    /// Provider-internal request retry settings.
    provider_retry: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    provider_id: []const u8 = "anthropic",
    api_id: []const u8 = "anthropic-messages",
    thinking: ai.ThinkingLevel = .off,
    abort_flag: ?*bool = null,
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    custom_headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    model_cost: providers.ModelCost = .{},
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,
    auth_mode: AuthMode = .api_key,

    pub fn client(self: *AnthropicClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
            .completeOptionsFn = completeOptionsImpl,
            .streamFn = streamImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        const self: *AnthropicClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, options, false, null, null);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn streamImpl(
        ptr: *anyopaque,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        const self: *AnthropicClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, true, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn ensureTokenFresh(self: *AnthropicClient) !void {
        const expires = self.token_expiration_ms orelse return;
        const refresh_fn = self.token_refresh_fn orelse return;
        const ctx = self.token_refresh_ctx orelse return;
        const now_ms = std.Io.Clock.real.now(self.io).toMilliseconds();
        if (now_ms < expires) return;
        try refresh_fn(ctx, self, now_ms);
    }

    fn request(
        self: *AnthropicClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        try self.ensureTokenFresh();
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model, .tool_id_mode = .sanitize64 });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const effective_cache_retention: metadata.CacheRetention = ai.resolveCacheRetention(self.cache_retention, request_options);
        const effective_session_id: ?[]const u8 = ai.resolveSessionAffinity(self.session_id, request_options);
        const payload = try buildRequestBodyConfiguredCompatCachedSampling(gpa, self.model, effective_messages, tools_json, streaming, self.thinking, effective_max_tokens, self.compat, effective_cache_retention, self.sampling_params);
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/v1/messages", .{self.base_url});
        defer gpa.free(url);

        var retry_index: usize = 0;
        while (true) {
            const result = self.requestOnce(gpa, payload, url, messages, effective_session_id, effective_cache_retention, streaming, on_delta, delta_ctx) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (err == error.ProviderStreamInterruptedAfterOutput or retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            if (std.mem.eql(u8, result.stop_reason, "error") and
                retry_index < self.provider_retry.max_retries and
                retry_mod.isRetryableProviderResponse(result.providerRetryMeta()))
            {
                var retry_response = result;
                const delay_ms = retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, retry_response.provider_retry_after_ms) catch |err| {
                    retry_response.deinit(gpa);
                    return err;
                };
                retry_response.deinit(gpa);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            }
            return result;
        }
    }

    fn requestOnce(
        self: *AnthropicClient,
        gpa: std.mem.Allocator,
        payload: []const u8,
        url: []const u8,
        messages: []const ai.ChatMessage,
        session_id: ?[]const u8,
        cache_retention: metadata.CacheRetention,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHttpHeader(gpa, &headers, "content-type", "application/json");
        const oauth_mode = self.auth_mode == .oauth or anthropic_oauth.isOAuthAccessToken(self.api_key);
        var owned_bearer: ?[]u8 = null;
        defer if (owned_bearer) |value| gpa.free(value);
        if (cloudflare.isAIGateway(self.provider_id)) {
            owned_bearer = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
            try putHttpHeader(gpa, &headers, "cf-aig-authorization", owned_bearer.?);
        } else if (copilot.isCopilot(self.provider_id) or oauth_mode or self.auth_mode == .bearer) {
            owned_bearer = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
            try putHttpHeader(gpa, &headers, "authorization", owned_bearer.?);
            try putHttpHeader(gpa, &headers, "anthropic-dangerous-direct-browser-access", "true");
        } else {
            try putHttpHeader(gpa, &headers, "x-api-key", self.api_key);
        }
        try putHttpHeader(gpa, &headers, "anthropic-version", "2023-06-01");
        try putHttpHeader(gpa, &headers, "accept", if (streaming) "text/event-stream" else "application/json");
        if (!oauth_mode) if (session_id) |sid| if (cache_retention != .none and self.compat.send_session_affinity_headers == true)
            try putHttpHeader(gpa, &headers, "x-session-affinity", sid);
        const needs_fine_grained = std.mem.indexOf(u8, payload, "\"tools\":[") != null and self.compat.supports_eager_tool_input_streaming == false;
        var owned_beta: ?[]u8 = null;
        defer if (owned_beta) |value| gpa.free(value);
        if (oauth_mode) {
            owned_beta = if (needs_fine_grained)
                try gpa.dupe(u8, "claude-code-20250219,oauth-2025-04-20,fine-grained-tool-streaming-2025-05-14")
            else
                try gpa.dupe(u8, "claude-code-20250219,oauth-2025-04-20");
            try putHttpHeader(gpa, &headers, "anthropic-beta", owned_beta.?);
            try putHttpHeader(gpa, &headers, "user-agent", "claude-cli/2.1.75");
            try putHttpHeader(gpa, &headers, "x-app", "cli");
        } else if (needs_fine_grained) {
            try putHttpHeader(gpa, &headers, "anthropic-beta", "fine-grained-tool-streaming-2025-05-14");
        }
        if (std.ascii.eqlIgnoreCase(self.provider_id, "kimi-coding")) {
            try putHttpHeader(gpa, &headers, "User-Agent", "KimiCLI/1.5");
        }
        if (copilot.isCopilot(self.provider_id)) {
            try putHttpHeader(gpa, &headers, "User-Agent", copilot.USER_AGENT);
            try putHttpHeader(gpa, &headers, "Editor-Version", copilot.EDITOR_VERSION);
            try putHttpHeader(gpa, &headers, "Editor-Plugin-Version", copilot.EDITOR_PLUGIN_VERSION);
            try putHttpHeader(gpa, &headers, "Copilot-Integration-Id", copilot.INTEGRATION_ID);
            const dynamic = copilot.infer(messages);
            try putHttpHeader(gpa, &headers, "X-Initiator", dynamic.initiator);
            try putHttpHeader(gpa, &headers, "Openai-Intent", "conversation-edits");
            if (dynamic.has_vision) try putHttpHeader(gpa, &headers, "Copilot-Vision-Request", "true");
        }
        for (self.custom_headers) |header| try putHttpHeader(gpa, &headers, header.name, header.value);

        var live = AnthropicLiveSse.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
        defer live.deinit();
        const fetch_result = http_fetch.fetchControlled(&http_client, .{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .keep_alive = false,
            .extra_headers = headers.items,
            .response_writer = &live.writer,
        }, self.provider_retry.timeout_ms, self.abort_flag) catch |err| {
            if (self.abort_flag) |f| {
                if (@atomicLoad(bool, f, .acquire)) {
                    return .{
                        .content = try gpa.dupe(u8, "aborted"),
                        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                        .provider = try gpa.dupe(u8, self.provider_id),
                        .model = try gpa.dupe(u8, self.model),
                        .stop_reason = try gpa.dupe(u8, "aborted"),
                    };
                }
            }
            if (streaming and live.body.items.len > 0) return error.ProviderStreamInterruptedAfterOutput;
            return err;
        };
        const status = fetch_result.status;
        try live.flushTrailing();
        if (live.aborted) {
            return .{
                .content = try gpa.dupe(u8, "aborted"),
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, self.provider_id),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "aborted"),
            };
        }
        if (status < 200 or status >= 300) {
            const body = try live.body.toOwnedSlice(gpa);
            defer gpa.free(body);
            const snippet = if (body.len > 800) body[0..800] else body;
            const content = try std.fmt.allocPrint(gpa, "HTTP {d} from anthropic: {s}", .{ status, snippet });
            return .{
                .content = content,
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, self.provider_id),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "error"),
                .provider_status = fetch_result.provider.status,
                .provider_retry_after_ms = fetch_result.provider.retry_after_ms,
                .provider_should_retry = fetch_result.provider.should_retry,
            };
        }
        if (streaming) {
            var resp = try live.acc.finish();
            live.acc = stream_mod.Accumulator.init(gpa);
            resp.provider = try gpa.dupe(u8, self.provider_id);
            if (live.thinking_signature.items.len > 0) resp.thinking_signature = try gpa.dupe(u8, live.thinking_signature.items);
            resp.model = try gpa.dupe(u8, self.model);
            if (live.response_id.len > 0) resp.response_id = try gpa.dupe(u8, live.response_id);
            if (live.response_model.len > 0 and !std.mem.eql(u8, live.response_model, self.model)) resp.response_model = try gpa.dupe(u8, live.response_model);
            if (live.raw_stop_reason.len > 0) resp.raw_stop_reason = try gpa.dupe(u8, live.raw_stop_reason);
            resp.usage = live.usage;
            _ = cost_mod.calculate(self.model_cost, &resp.usage);
            if (live.stop_reason.len > 0) {
                if (resp.stop_reason.len > 0) gpa.free(resp.stop_reason);
                resp.stop_reason = try gpa.dupe(u8, live.stop_reason);
            }
            try resp.ensureStopReason(gpa);
            return resp;
        }
        const response_json = try live.body.toOwnedSlice(gpa);
        defer gpa.free(response_json);
        var resp = try parseAnthropicResponse(gpa, response_json);
        try normalizeRequestedModel(gpa, &resp, self.model);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, self.provider_id);
        _ = cost_mod.calculate(self.model_cost, &resp.usage);
        try resp.ensureStopReason(gpa);
        return resp;
    }
};

fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "aborted"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "aborted"),
    };
}

fn normalizeRequestedModel(gpa: std.mem.Allocator, response: *ai.ModelResponse, requested_model: []const u8) !void {
    if (response.model.len == 0) {
        response.model = try gpa.dupe(u8, requested_model);
        return;
    }
    if (std.mem.eql(u8, response.model, requested_model)) return;
    const requested_copy = try gpa.dupe(u8, requested_model);
    if (response.response_model.len > 0) gpa.free(response.response_model);
    response.response_model = response.model;
    response.model = requested_copy;
}

fn putHttpHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    for (headers.items) |*header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            header.* = .{ .name = name, .value = value };
            return;
        }
    }
    try headers.append(gpa, .{ .name = name, .value = value });
}

fn observeAnthropicSignature(gpa: std.mem.Allocator, event_name: []const u8, data: []const u8, out: *std.ArrayList(u8)) !void {
    if (!std.mem.eql(u8, event_name, "content_block_start") and !std.mem.eql(u8, event_name, "content_block_delta")) return;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, data, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    if (std.mem.eql(u8, event_name, "content_block_start")) {
        const block = parsed.value.object.get("content_block") orelse return;
        if (block != .object) return;
        if (block.object.get("signature")) |sig| {
            if (sig == .string and sig.string.len > 0) try out.appendSlice(gpa, sig.string);
        } else if (block.object.get("data")) |redacted| {
            if (redacted == .string and redacted.string.len > 0) try out.appendSlice(gpa, redacted.string);
        }
        return;
    }
    const delta = parsed.value.object.get("delta") orelse return;
    if (delta != .object) return;
    const typ = delta.object.get("type") orelse return;
    if (typ != .string or !std.mem.eql(u8, typ.string, "signature_delta")) return;
    if (delta.object.get("signature")) |sig| {
        if (sig == .string and sig.string.len > 0) try out.appendSlice(gpa, sig.string);
    }
}

/// Incremental Anthropic SSE: tracks event: lines + data: JSON, emits deltas as chunks arrive.
const AnthropicLiveSse = struct {
    gpa: std.mem.Allocator,
    writer: std.Io.Writer,
    line: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    acc: stream_mod.Accumulator,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    streaming: bool,
    abort_flag: ?*bool = null,
    aborted: bool = false,
    usage: ai.Usage = .{},
    stop_reason: []const u8 = "",
    response_id: []u8 = &.{},
    response_model: []u8 = &.{},
    raw_stop_reason: []u8 = &.{},
    thinking_signature: std.ArrayList(u8) = .empty,
    event_name: []u8 = &.{},
    event_owned: bool = false,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .flush = std.Io.Writer.noopFlush,
    };

    fn init(gpa: std.mem.Allocator, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, streaming: bool, abort_flag: ?*bool) AnthropicLiveSse {
        return .{
            .gpa = gpa,
            .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
            .acc = stream_mod.Accumulator.init(gpa),
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .streaming = streaming,
            .abort_flag = abort_flag,
        };
    }

    fn deinit(self: *AnthropicLiveSse) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.thinking_signature.deinit(self.gpa);
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.response_model.len > 0) self.gpa.free(self.response_model);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        if (self.event_owned and self.event_name.len > 0) self.gpa.free(self.event_name);
        self.acc.deinit();
        self.* = undefined;
    }

    fn flushTrailing(self: *AnthropicLiveSse) !void {
        if (self.streaming and self.line.items.len > 0) {
            try self.handleLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }

    fn feed(self: *AnthropicLiveSse, chunk: []const u8) !void {
        if (self.abort_flag) |f| {
            if (@atomicLoad(bool, f, .acquire)) {
                self.aborted = true;
                return error.WriteFailed;
            }
        }
        try self.body.appendSlice(self.gpa, chunk);
        if (!self.streaming) return;
        for (chunk) |c| {
            if (c == '\n') {
                try self.handleLine(self.line.items);
                self.line.clearRetainingCapacity();
            } else if (c != '\r') {
                try self.line.append(self.gpa, c);
            }
        }
    }

    fn handleLine(self: *AnthropicLiveSse, line: []const u8) !void {
        const t = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, t, "event:")) {
            if (self.event_owned and self.event_name.len > 0) self.gpa.free(self.event_name);
            self.event_name = try self.gpa.dupe(u8, std.mem.trim(u8, t["event:".len..], " \t"));
            self.event_owned = true;
            return;
        }
        if (!std.mem.startsWith(u8, t, "data:")) return;
        const data = std.mem.trim(u8, t["data:".len..], " \t");
        const ename = if (self.event_name.len > 0) self.event_name else "message";
        observeAnthropicUsage(ename, data, &self.usage, &self.stop_reason);
        try self.observeMetadata(ename, data);
        try observeAnthropicSignature(self.gpa, ename, data, &self.thinking_signature);
        if (try stream_mod.parseAnthropicEvent(self.gpa, ename, data)) |delta| {
            defer stream_mod.freeDelta(self.gpa, delta);
            try self.acc.onDelta(delta);
            if (self.on_delta) |h| h(self.delta_ctx, delta);
        }
    }

    fn observeMetadata(self: *AnthropicLiveSse, event_name: []const u8, data: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, data, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        if (std.mem.eql(u8, event_name, "message_start")) {
            const message = parsed.value.object.get("message") orelse return;
            if (message != .object) return;
            if (self.response_id.len == 0) if (message.object.get("id")) |id| if (id == .string and id.string.len > 0) {
                self.response_id = try self.gpa.dupe(u8, id.string);
            };
            if (self.response_model.len == 0) if (message.object.get("model")) |model| if (model == .string and model.string.len > 0) {
                self.response_model = try self.gpa.dupe(u8, model.string);
            };
        } else if (std.mem.eql(u8, event_name, "message_delta")) {
            const delta = parsed.value.object.get("delta") orelse return;
            if (delta != .object) return;
            if (delta.object.get("stop_reason")) |reason| if (reason == .string and reason.string.len > 0) {
                if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
                self.raw_stop_reason = try self.gpa.dupe(u8, reason.string);
            };
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *AnthropicLiveSse = @fieldParentPtr("writer", w);
        if (w.end > 0) {
            self.feed(w.buffer[0..w.end]) catch return error.WriteFailed;
            w.end = 0;
        }
        if (data.len == 0) return 0;
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |part| {
            self.feed(part) catch return error.WriteFailed;
            n += part.len;
        }
        const pattern = data[data.len - 1];
        var s = splat;
        while (s > 0) : (s -= 1) {
            self.feed(pattern) catch return error.WriteFailed;
            n += pattern.len;
        }
        return n;
    }
};

/// Consume full Anthropic SSE body via shipped parsers (production stream path).
pub fn consumeAnthropicStreamBody(
    gpa: std.mem.Allocator,
    sse_body: []const u8,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    model: []const u8,
) !ai.ModelResponse {
    var acc = stream_mod.Accumulator.init(gpa);
    defer acc.deinit();

    var current_event: []const u8 = "message";
    var event_owned: ?[]u8 = null;
    defer if (event_owned) |e| gpa.free(e);

    var it = std.mem.splitScalar(u8, sse_body, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "event:")) {
            if (event_owned) |e| gpa.free(e);
            event_owned = try gpa.dupe(u8, std.mem.trim(u8, t["event:".len..], " \t"));
            current_event = event_owned.?;
        } else if (std.mem.startsWith(u8, t, "data:")) {
            const data = std.mem.trim(u8, t["data:".len..], " \t");
            if (try stream_mod.parseAnthropicEvent(gpa, current_event, data)) |delta| {
                defer stream_mod.freeDelta(gpa, delta);
                try acc.onDelta(delta);
                if (on_delta) |h| h(delta_ctx, delta);
            }
        }
    }

    var resp = try acc.finish();
    resp.provider = try gpa.dupe(u8, "anthropic");
    resp.model = try gpa.dupe(u8, model);
    try resp.ensureStopReason(gpa);
    return resp;
}

fn appendAnthropicToolUses(gpa: std.mem.Allocator, w: anytype, tool_calls_json: []const u8, first_block: *bool) !void {
    _ = gpa;
    // Expect OpenAI format: [{"id":"...","type":"function","function":{"name":"...","arguments":"..."}}]
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, tool_calls_json, .{}) catch {
        // Fallback: empty
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id = item.object.get("id");
        const fn_obj = item.object.get("function");
        if (id == null or fn_obj == null or id.? != .string or fn_obj.? != .object) continue;
        const name = fn_obj.?.object.get("name");
        const args = fn_obj.?.object.get("arguments");
        if (name == null or args == null or name.? != .string or args.? != .string) continue;
        if (!first_block.*) try w.writeAll(",");
        first_block.* = false;
        try w.writeAll("{\"type\":\"tool_use\",\"id\":");
        try std.json.Stringify.value(id.?.string, .{}, w);
        try w.writeAll(",\"name\":");
        try std.json.Stringify.value(name.?.string, .{}, w);
        try w.writeAll(",\"input\":");
        // arguments is a JSON string — embed raw if valid object else wrap
        try w.writeAll(args.?.string);
        try w.writeAll("}");
    }
}

fn toolCallsContainName(gpa: std.mem.Allocator, calls_json: []const u8, name: []const u8) !bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, calls_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        const n = fn_obj.object.get("name") orelse continue;
        if (n == .string and std.mem.eql(u8, n.string, name)) return true;
    }
    return false;
}

fn isDeferredToolName(gpa: std.mem.Allocator, messages: []const ai.ChatMessage, name: []const u8) !bool {
    var used = false;
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "assistant")) {
            if (msg.tool_calls_json) |calls| if (try toolCallsContainName(gpa, calls, name)) {
                used = true;
            };
        } else if (std.mem.eql(u8, msg.role, "tool")) {
            for (msg.added_tool_names) |added| {
                if (std.mem.eql(u8, added, name) and !used) return true;
            }
        }
    }
    return false;
}

fn deferredToolModeActive(gpa: std.mem.Allocator, tools_json: []const u8, messages: []const ai.ChatMessage, enabled: bool) !bool {
    if (!enabled) return false;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    var valid: usize = 0;
    var deferred: usize = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        const n = fn_obj.object.get("name") orelse continue;
        if (n != .string) continue;
        valid += 1;
        if (try isDeferredToolName(gpa, messages, n.string)) deferred += 1;
    }
    // Anthropic cannot start with an all-deferred catalog.
    return deferred > 0 and deferred < valid;
}

pub fn convertToolsToAnthropic(gpa: std.mem.Allocator, tools_json: []const u8) ![]u8 {
    return convertToolsToAnthropicCached(gpa, tools_json, false, false, &.{}, false, .{});
}

fn convertToolsToAnthropicCached(
    gpa: std.mem.Allocator,
    tools_json: []const u8,
    add_cache: bool,
    long_ttl: bool,
    messages: []const ai.ChatMessage,
    deferred_active: bool,
    compat: metadata.Compat,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return try gpa.dupe(u8, "[]");

    var valid_count: usize = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        const name = fn_obj.object.get("name") orelse continue;
        if (name == .string) valid_count += 1;
    }
    var remaining_cacheable = valid_count;
    if (deferred_active) {
        remaining_cacheable = 0;
        for (parsed.value.array.items) |item| {
            const function = constrained.functionSpec(item) orelse continue;
            const tool_name = function.get("name") orelse continue;
            if (tool_name != .string) continue;
            if (!try isDeferredToolName(gpa, messages, tool_name.string)) remaining_cacheable += 1;
        }
    }
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        const name = fn_obj.object.get("name") orelse continue;
        const desc = fn_obj.object.get("description");
        const params = fn_obj.object.get("parameters");
        if (name != .string) continue;
        if (!first) try out.writer.writeAll(",");
        first = false;
        try out.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(name.string, .{}, &out.writer);
        try out.writer.writeAll(",\"description\":");
        if (desc) |d| {
            if (d == .string) try std.json.Stringify.value(d.string, .{}, &out.writer) else try out.writer.writeAll("\"\"");
        } else try out.writer.writeAll("\"\"");
        const strict = try constrained.resolveJsonSchemaStrict(item, compat.supports_strict_tools == true);
        try out.writer.writeAll(",\"input_schema\":");
        if (strict == true) {
            // Strict constrained sampling retains the provider's full schema.
            // Non-strict Anthropic tools deliberately use only the legacy
            // type/properties/required subset for broad proxy compatibility.
            if (params) |p| {
                try std.json.Stringify.value(p, .{}, &out.writer);
            } else {
                try out.writer.writeAll("{\"type\":\"object\",\"properties\":{},\"required\":[]}");
            }
        } else {
            try out.writer.writeAll("{\"type\":\"object\",\"properties\":");
            if (params) |p| {
                if (p == .object) {
                    if (p.object.get("properties")) |properties| try std.json.Stringify.value(properties, .{}, &out.writer) else try out.writer.writeAll("{}");
                } else try out.writer.writeAll("{}");
            } else try out.writer.writeAll("{}");
            try out.writer.writeAll(",\"required\":");
            if (params) |p| {
                if (p == .object) {
                    if (p.object.get("required")) |required| try std.json.Stringify.value(required, .{}, &out.writer) else try out.writer.writeAll("[]");
                } else try out.writer.writeAll("[]");
            } else try out.writer.writeAll("[]");
            try out.writer.writeAll("}");
        }
        if (compat.supports_eager_tool_input_streaming != false) {
            try out.writer.writeAll(",\"eager_input_streaming\":true");
        }
        if (strict == true) try out.writer.writeAll(",\"strict\":true");
        const is_deferred = deferred_active and try isDeferredToolName(gpa, messages, name.string);
        if (is_deferred) try out.writer.writeAll(",\"defer_loading\":true");
        if (add_cache and compat.supports_cache_control_on_tools != false and !is_deferred and remaining_cacheable == 1) {
            try out.writer.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
            if (long_ttl) try out.writer.writeAll(",\"ttl\":\"1h\"");
            try out.writer.writeAll("}");
        }
        if (!is_deferred and remaining_cacheable > 0) remaining_cacheable -= 1;
        try out.writer.writeAll("}");
    }
    try out.writer.writeAll("]");
    return try out.toOwnedSlice();
}

fn anthropicU64(value: ?std.json.Value) ?u64 {
    const v = value orelse return null;
    if (v != .integer or v.integer < 0) return null;
    return @intCast(v.integer);
}

fn mergeAnthropicUsage(value: std.json.Value, usage: *ai.Usage) void {
    if (value != .object) return;
    if (anthropicU64(value.object.get("input_tokens"))) |v| usage.input = v;
    if (anthropicU64(value.object.get("output_tokens"))) |v| usage.output = v;
    if (anthropicU64(value.object.get("cache_read_input_tokens"))) |v| usage.cache_read = v;
    if (anthropicU64(value.object.get("cache_creation_input_tokens"))) |v| usage.cache_write = v;
    if (value.object.get("cache_creation")) |cache_creation| {
        if (cache_creation == .object) {
            if (anthropicU64(cache_creation.object.get("ephemeral_1h_input_tokens"))) |v| usage.cache_write_1h = v;
        }
    }
    if (value.object.get("output_tokens_details")) |details| {
        if (details == .object and details.object.get("thinking_tokens") != null) {
            usage.reasoning = anthropicU64(details.object.get("thinking_tokens")) orelse 0;
        }
    }
    usage.normalizeTotal();
}

fn observeAnthropicUsage(event_name: []const u8, data: []const u8, usage: *ai.Usage, stop_reason: *[]const u8) void {
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    if (std.mem.eql(u8, event_name, "message_start")) {
        if (parsed.value.object.get("message")) |msg| {
            if (msg == .object) if (msg.object.get("usage")) |u| mergeAnthropicUsage(u, usage);
        }
    } else if (std.mem.eql(u8, event_name, "message_delta")) {
        if (parsed.value.object.get("usage")) |u| mergeAnthropicUsage(u, usage);
        if (parsed.value.object.get("delta")) |delta| {
            if (delta == .object) if (delta.object.get("stop_reason")) |sr| {
                if (sr == .string) {
                    if (std.mem.eql(u8, sr.string, "tool_use")) stop_reason.* = "toolUse" else if (std.mem.eql(u8, sr.string, "max_tokens")) stop_reason.* = "length" else if (std.mem.eql(u8, sr.string, "end_turn") or std.mem.eql(u8, sr.string, "stop_sequence")) stop_reason.* = "stop";
                }
            };
        }
    }
}

pub fn parseAnthropicResponse(gpa: std.mem.Allocator, response_json: []const u8) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;

    const content_arr = parsed.value.object.get("content") orelse return error.InvalidResponse;
    if (content_arr != .array) return error.InvalidResponse;

    var text_parts: std.ArrayList(u8) = .empty;
    errdefer text_parts.deinit(gpa);
    var thinking_parts: std.ArrayList(u8) = .empty;
    errdefer thinking_parts.deinit(gpa);
    var thinking_signature: ?[]u8 = null;
    errdefer if (thinking_signature) |sig| gpa.free(sig);
    var tcs: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (tcs.items) |*tc| tc.deinit(gpa);
        tcs.deinit(gpa);
    }

    for (content_arr.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string) continue;
        if (std.mem.eql(u8, typ.string, "text")) {
            if (block.object.get("text")) |t| {
                if (t == .string) {
                    if (text_parts.items.len > 0) try text_parts.appendSlice(gpa, "\n");
                    try text_parts.appendSlice(gpa, t.string);
                }
            }
        } else if (std.mem.eql(u8, typ.string, "thinking")) {
            if (block.object.get("thinking")) |t| {
                if (t == .string) {
                    if (thinking_parts.items.len > 0) try thinking_parts.appendSlice(gpa, "\n");
                    try thinking_parts.appendSlice(gpa, t.string);
                }
            }
            if (thinking_signature == null) {
                if (block.object.get("signature")) |sig| if (sig == .string) {
                    thinking_signature = try gpa.dupe(u8, sig.string);
                };
            }
        } else if (std.mem.eql(u8, typ.string, "redacted_thinking")) {
            if (thinking_signature == null) {
                if (block.object.get("data")) |sig| if (sig == .string) {
                    thinking_signature = try gpa.dupe(u8, sig.string);
                };
            }
        } else if (std.mem.eql(u8, typ.string, "tool_use")) {
            const id = block.object.get("id") orelse continue;
            const name = block.object.get("name") orelse continue;
            const input = block.object.get("input") orelse continue;
            if (id != .string or name != .string) continue;
            var args_aw: std.Io.Writer.Allocating = .init(gpa);
            defer args_aw.deinit();
            try std.json.Stringify.value(input, .{}, &args_aw.writer);
            try tcs.append(gpa, .{
                .id = try gpa.dupe(u8, id.string),
                .name = try gpa.dupe(u8, name.string),
                .arguments = try args_aw.toOwnedSlice(),
            });
        }
    }

    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usage")) |u| mergeAnthropicUsage(u, &usage);

    var model_out: []const u8 = "";
    if (parsed.value.object.get("model")) |m| {
        if (m == .string) model_out = try gpa.dupe(u8, m.string);
    }

    var response_id: []const u8 = "";
    if (parsed.value.object.get("id")) |id| {
        if (id == .string and id.string.len > 0) response_id = try gpa.dupe(u8, id.string);
    }
    var stop_reason: []const u8 = "";
    var raw_stop_reason: []const u8 = "";
    if (parsed.value.object.get("stop_reason")) |sr| {
        if (sr == .string) {
            raw_stop_reason = try gpa.dupe(u8, sr.string);
            if (std.mem.eql(u8, sr.string, "tool_use") or std.mem.eql(u8, sr.string, "toolUse")) {
                stop_reason = try gpa.dupe(u8, "toolUse");
            } else if (std.mem.eql(u8, sr.string, "max_tokens")) {
                stop_reason = try gpa.dupe(u8, "length");
            } else if (std.mem.eql(u8, sr.string, "end_turn") or std.mem.eql(u8, sr.string, "stop")) {
                stop_reason = try gpa.dupe(u8, "stop");
            } else {
                stop_reason = try gpa.dupe(u8, sr.string);
            }
        }
    }

    var resp: ai.ModelResponse = .{
        .content = try text_parts.toOwnedSlice(gpa),
        .thinking = if (thinking_parts.items.len > 0) try thinking_parts.toOwnedSlice(gpa) else "",
        .thinking_signature = thinking_signature orelse "",
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "anthropic"),
        .model = model_out,
        .response_id = response_id,
        .raw_stop_reason = raw_stop_reason,
        .stop_reason = stop_reason,
        .usage = usage,
    };
    thinking_signature = null; // ownership moved into response
    try resp.ensureStopReason(gpa);
    return resp;
}

/// Build Anthropic /v1/messages JSON body (caller frees). Non-streaming.
pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
) ![]u8 {
    return buildRequestBodyOpts(gpa, model, messages, tools_json, false);
}

/// Build Anthropic body; when `stream` is true includes `"stream":true`.
pub fn buildRequestBodyOpts(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
) ![]u8 {
    return buildRequestBodyFull(gpa, model, messages, tools_json, stream, .off);
}

pub fn buildRequestBodyFull(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
    thinking: ai.ThinkingLevel,
) ![]u8 {
    return buildRequestBodyConfigured(gpa, model, messages, tools_json, stream, thinking, 0);
}

pub fn buildRequestBodyConfigured(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
    thinking: ai.ThinkingLevel,
    max_tokens: u64,
) ![]u8 {
    return buildRequestBodyConfiguredCompat(gpa, model, messages, tools_json, stream, thinking, max_tokens, .{});
}

pub fn buildRequestBodyConfiguredCompat(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
    thinking: ai.ThinkingLevel,
    max_tokens: u64,
    compat: metadata.Compat,
) ![]u8 {
    return buildRequestBodyConfiguredCompatCached(gpa, model, messages, tools_json, stream, thinking, max_tokens, compat, .short);
}

pub fn buildRequestBodyConfiguredCompatCached(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
    thinking: ai.ThinkingLevel,
    max_tokens: u64,
    compat: metadata.Compat,
    cache_retention: metadata.CacheRetention,
) ![]u8 {
    return buildRequestBodyConfiguredCompatCachedSampling(gpa, model, messages, tools_json, stream, thinking, max_tokens, compat, cache_retention, &.{});
}

fn writeAnthropicMediaContent(
    w: *std.Io.Writer,
    content: []const u8,
    image_b64: ?[]const u8,
    image_mime: ?[]const u8,
    images: []const ai.ChatImage,
    cache_control: bool,
    long_ttl: bool,
) !void {
    const image_count: usize = @intFromBool(image_b64 != null) + images.len;
    if (image_count == 0) {
        try std.json.Stringify.value(content, .{}, w);
        return;
    }
    try w.writeByte('[');
    var wrote = false;
    if (std.mem.trim(u8, content, " \\t\\r\\n").len > 0) {
        try w.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(content, .{}, w);
        try w.writeByte('}');
        wrote = true;
    }
    if (!wrote) {
        try w.writeAll("{\"type\":\"text\",\"text\":\"(see attached image)\"}");
        wrote = true;
    }
    var image_index: usize = 0;
    while (image_index < image_count) : (image_index += 1) {
        const image: ai.ChatImage = if (image_index == 0 and image_b64 != null)
            .{ .data_b64 = image_b64.?, .mime_type = image_mime orelse "image/png" }
        else
            images[image_index - @intFromBool(image_b64 != null)];
        if (wrote) try w.writeByte(',');
        try w.writeAll("{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":");
        try std.json.Stringify.value(image.mime_type, .{}, w);
        try w.writeAll(",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, w);
        try w.writeByte('}');
        if (cache_control and image_index + 1 == image_count) {
            try w.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
            if (long_ttl) try w.writeAll(",\"ttl\":\"1h\"");
            try w.writeByte('}');
        }
        try w.writeByte('}');
        wrote = true;
    }
    try w.writeByte(']');
}

fn writeAnthropicSiblingMedia(w: *std.Io.Writer, msg: ai.ChatMessage, first: *bool) !void {
    if (std.mem.trim(u8, msg.content, " \\t\\r\\n").len > 0) {
        if (!first.*) try w.writeAll(",");
        first.* = false;
        try w.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(msg.content, .{}, w);
        try w.writeAll("}");
    }
    var image_index: usize = 0;
    while (image_index < msg.imageCount()) : (image_index += 1) {
        const image = msg.imageAt(image_index).?;
        if (!first.*) try w.writeByte(',');
        first.* = false;
        try w.writeAll("{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":");
        try std.json.Stringify.value(image.mime_type, .{}, w);
        try w.writeAll(",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, w);
        try w.writeAll("}}");
    }
}

pub fn buildRequestBodyConfiguredCompatCachedSampling(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    stream: bool,
    thinking: ai.ThinkingLevel,
    max_tokens: u64,
    compat: metadata.Compat,
    cache_retention: metadata.CacheRetention,
    sampling_params: []const metadata.SamplingParam,
) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    const replay_messages = repaired.messages.items;
    const cache_enabled = compat.cache_control_format == .anthropic and cache_retention != .none;
    const long_ttl = cache_enabled and cache_retention == .long and compat.supports_long_cache_retention == true;

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.print(",\"max_tokens\":{d}", .{if (max_tokens > 0) max_tokens else 8192});
    if (stream) try w.writeAll(",\"stream\":true");
    if (thinking != .off and compat.force_adaptive_thinking == true) {
        try w.writeAll(",\"thinking\":{\"type\":\"adaptive\",\"display\":\"summarized\"}");
        if (thinking.openaiEffort()) |effort| {
            try w.writeAll(",\"output_config\":{\"effort\":");
            try std.json.Stringify.value(effort, .{}, w);
            try w.writeAll("}");
        }
    } else if (thinking.anthropicBudget()) |budget| {
        try w.writeAll(",\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":");
        try w.print("{d}", .{budget});
        try w.writeAll(",\"display\":\"summarized\"}");
    }

    var system_parts: std.ArrayList([]const u8) = .empty;
    defer system_parts.deinit(gpa);
    for (replay_messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system")) {
            try system_parts.append(gpa, msg.content);
        }
    }
    if (system_parts.items.len > 0) {
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(gpa);
        for (system_parts.items, 0..) |part, i| {
            if (i > 0) try joined.appendSlice(gpa, "\n\n");
            try joined.appendSlice(gpa, part);
        }
        try w.writeAll(",\"system\":");
        if (cache_enabled) {
            try w.writeAll("[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(joined.items, .{}, w);
            try w.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
            if (long_ttl) try w.writeAll(",\"ttl\":\"1h\"");
            try w.writeAll("}}]");
        } else {
            try std.json.Stringify.value(joined.items, .{}, w);
        }
    }

    var last_cache_message: ?usize = null;
    for (replay_messages, 0..) |msg, i| {
        if (std.mem.eql(u8, msg.role, "user") or std.mem.eql(u8, msg.role, "tool")) last_cache_message = i;
    }
    const deferred_active = try deferredToolModeActive(gpa, tools_json, replay_messages, compat.supports_tool_references == true);
    var loaded_deferred = std.StringHashMap(void).init(gpa);
    defer loaded_deferred.deinit();

    try w.writeAll(",\"messages\":[");
    var first = true;
    var msg_index: usize = 0;
    while (msg_index < replay_messages.len) : (msg_index += 1) {
        const msg = replay_messages[msg_index];
        if (std.mem.eql(u8, msg.role, "system")) continue;
        if (!first) try w.writeAll(",");
        first = false;

        if (std.mem.eql(u8, msg.role, "tool")) {
            try w.writeAll("{\"role\":\"user\",\"content\":[");
            var first_result = true;
            var sibling_media: std.ArrayList(ai.ChatMessage) = .empty;
            defer sibling_media.deinit(gpa);
            var j = msg_index;
            while (j < replay_messages.len and std.mem.eql(u8, replay_messages[j].role, "tool")) : (j += 1) {
                const tool_msg = replay_messages[j];
                if (!first_result) try w.writeAll(",");
                first_result = false;
                try w.writeAll("{\"type\":\"tool_result\",\"tool_use_id\":");
                try std.json.Stringify.value(tool_msg.tool_call_id orelse "", .{}, w);
                var refs: std.ArrayList([]const u8) = .empty;
                defer refs.deinit(gpa);
                if (deferred_active) {
                    for (tool_msg.added_tool_names) |added| {
                        if (loaded_deferred.contains(added)) continue;
                        if (!try isDeferredToolName(gpa, replay_messages, added)) continue;
                        try loaded_deferred.put(added, {});
                        try refs.append(gpa, added);
                    }
                }
                try w.writeAll(",\"content\":");
                if (refs.items.len > 0) {
                    try w.writeAll("[");
                    for (refs.items, 0..) |name, ri| {
                        if (ri > 0) try w.writeAll(",");
                        try w.writeAll("{\"type\":\"tool_reference\",\"tool_name\":");
                        try std.json.Stringify.value(name, .{}, w);
                        try w.writeAll("}");
                    }
                    try w.writeAll("]");
                    if (tool_msg.content.len > 0 or tool_msg.hasImages()) try sibling_media.append(gpa, tool_msg);
                } else {
                    try writeAnthropicMediaContent(w, tool_msg.content, tool_msg.image_b64, tool_msg.image_mime, tool_msg.images, false, false);
                }
                if (tool_msg.tool_is_error) try w.writeAll(",\"is_error\":true");
                if (cache_enabled and last_cache_message != null and last_cache_message.? == j) {
                    try w.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
                    if (long_ttl) try w.writeAll(",\"ttl\":\"1h\"");
                    try w.writeAll("}");
                }
                try w.writeAll("}");
            }
            for (sibling_media.items) |sibling| try writeAnthropicSiblingMedia(w, sibling, &first_result);
            try w.writeAll("]}");
            if (j > 0) msg_index = j - 1;
        } else if (std.mem.eql(u8, msg.role, "assistant")) {
            try w.writeAll("{\"role\":\"assistant\",\"content\":[");
            var first_block = true;
            if (msg.thinking) |thought| {
                if (thought.len > 0 or msg.thinking_signature != null) {
                    if (!first_block) try w.writeAll(",");
                    first_block = false;
                    const signature = msg.thinking_signature orelse "";
                    if (signature.len > 0 or compat.allow_empty_signature == true) {
                        try w.writeAll("{\"type\":\"thinking\",\"thinking\":");
                        try std.json.Stringify.value(thought, .{}, w);
                        try w.writeAll(",\"signature\":");
                        try std.json.Stringify.value(signature, .{}, w);
                        try w.writeAll("}");
                    } else {
                        try w.writeAll("{\"type\":\"text\",\"text\":");
                        try std.json.Stringify.value(thought, .{}, w);
                        try w.writeAll("}");
                    }
                }
            }
            if (msg.content.len > 0) {
                if (!first_block) try w.writeAll(",");
                first_block = false;
                try w.writeAll("{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll("}");
            }
            if (msg.tool_calls_json) |calls| try appendAnthropicToolUses(gpa, w, calls, &first_block);
            try w.writeAll("]}");
        } else {
            try w.writeAll("{\"role\":");
            try std.json.Stringify.value(msg.role, .{}, w);
            try w.writeAll(",\"content\":");
            const cache_here = cache_enabled and last_cache_message != null and last_cache_message.? == msg_index and std.mem.eql(u8, msg.role, "user");
            if (msg.hasImages()) {
                try writeAnthropicMediaContent(w, msg.content, msg.image_b64, msg.image_mime, msg.images, cache_here, long_ttl);
            } else if (cache_here) {
                try w.writeAll("[{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
                if (long_ttl) try w.writeAll(",\"ttl\":\"1h\"");
                try w.writeAll("}}]");
            } else {
                try std.json.Stringify.value(msg.content, .{}, w);
            }
            try w.writeAll("}");
        }
    }
    try w.writeAll("]");

    if (tools_json.len > 2) {
        const anthropic_tools = try convertToolsToAnthropicCached(gpa, tools_json, cache_enabled, long_ttl, replay_messages, deferred_active, compat);
        defer gpa.free(anthropic_tools);
        try w.writeAll(",\"tools\":");
        try w.writeAll(anthropic_tools);
    }
    for (sampling_params) |param| {
        const reserved = std.mem.eql(u8, param.name, "model") or std.mem.eql(u8, param.name, "messages") or
            std.mem.eql(u8, param.name, "tools") or std.mem.eql(u8, param.name, "stream") or
            std.mem.eql(u8, param.name, "max_tokens") or std.mem.eql(u8, param.name, "thinking") or
            std.mem.eql(u8, param.name, "system") or std.mem.eql(u8, param.name, "output_config");
        if (reserved) continue;
        if (std.mem.eql(u8, param.name, "temperature") and (thinking != .off or compat.supports_temperature == false)) continue;
        try w.writeAll(",");
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeAll(":");
        try w.writeAll(param.value_json);
    }
    try w.writeAll("}");
    return try body.toOwnedSlice();
}

test "convertToolsToAnthropic maps OpenAI function schema" {
    const gpa = std.testing.allocator;
    const openai_tools =
        \\[{"type":"function","function":{"name":"read","description":"Read a file","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}}]
    ;
    const out = try convertToolsToAnthropic(gpa, openai_tools);
    defer gpa.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"name\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"input_schema\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\"type\":\"function\"") == null);
}

test "buildRequestBody includes model tools and tool_use shape" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "system", .content = "sys" },
        .{ .role = "user", .content = "hi" },
        .{
            .role = "assistant",
            .content = "calling",
            .tool_calls_json =
            \\[{"id":"c1","type":"function","function":{"name":"read","arguments":"{\"path\":\"a.txt\"}"}}]
            ,
        },
    };
    const tools =
        \\[{"type":"function","function":{"name":"read","description":"r","parameters":{"type":"object"}}}]
    ;
    const body = try buildRequestBody(gpa, "claude-test", &msgs, tools);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"model\":\"claude-test\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"system\":\"sys\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"tool_use\"") != null);
}

test "buildRequestBodyFull includes thinking budget_tokens" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyFull(gpa, "claude-test", &msgs, "[]", false, .medium);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"budget_tokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"enabled\"") != null);
}

test "mutating client.model changes subsequent buildRequestBody" {
    const gpa = std.testing.allocator;
    var client = AnthropicClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "k",
        .base_url = "https://api.anthropic.com",
        .model = "old-claude",
    };
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "x" }};
    const b1 = try buildRequestBody(gpa, client.model, &msgs, "[]");
    defer gpa.free(b1);
    try std.testing.expect(std.mem.indexOf(u8, b1, "old-claude") != null);

    client.model = "new-claude";
    const b2 = try buildRequestBody(gpa, client.model, &msgs, "[]");
    defer gpa.free(b2);
    try std.testing.expect(std.mem.indexOf(u8, b2, "new-claude") != null);
    try std.testing.expect(std.mem.indexOf(u8, b2, "old-claude") == null);
}

test "parseAnthropicResponse extracts text and tool_use" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"id":"msg_1","model":"claude-test","stop_reason":"tool_use","usage":{"input_tokens":3,"output_tokens":7},"content":[{"type":"text","text":"Working"},{"type":"tool_use","id":"tu1","name":"read","input":{"path":"a.txt"}}]}
    ;
    var resp = try parseAnthropicResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Working", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "a.txt") != null);
    try std.testing.expectEqualStrings("anthropic", resp.provider);
    try std.testing.expectEqualStrings("claude-test", resp.model);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
    try std.testing.expectEqualStrings("msg_1", resp.response_id);
    try std.testing.expectEqualStrings("tool_use", resp.raw_stop_reason);
    try std.testing.expectEqual(@as(u64, 3), resp.usage.input);
}

test "buildRequestBodyOpts stream true for Anthropic" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyOpts(gpa, "claude", &msgs, "[]", true);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream\":true") != null);
}

test "consumeAnthropicStreamBody multi-chunk via shipped path" {
    const gpa = std.testing.allocator;
    const fixture =
        \\event: content_block_delta
        \\data: {"delta":{"type":"text_delta","text":"Hi "}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"text_delta","text":"there"}}
        \\event: content_block_start
        \\data: {"content_block":{"type":"tool_use","id":"tu1","name":"bash"}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"input_json_delta","partial_json":"{\"command\":"}}
        \\event: content_block_delta
        \\data: {"delta":{"type":"input_json_delta","partial_json":"\"echo\"}"}}
        \\event: message_stop
        \\data: {}
        \\
    ;
    const C = struct {
        n: usize = 0,
        fn onDelta(ptr: ?*anyopaque, d: ai.StreamDelta) void {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (d.kind == .text_delta) self.n += 1;
        }
    };
    var c = C{};
    var resp = try consumeAnthropicStreamBody(gpa, fixture, C.onDelta, &c, "claude-stream");
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Hi there", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("bash", resp.tool_calls[0].name);
    try std.testing.expect(c.n >= 2);
    try std.testing.expectEqualStrings("anthropic", resp.provider);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
}

test "Anthropic response preserves thinking signature" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"model":"claude-test","stop_reason":"end_turn","content":[{"type":"thinking","thinking":"secret plan","signature":"sig-opaque"},{"type":"text","text":"answer"}]}
    ;
    var resp = try parseAnthropicResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("secret plan", resp.thinking);
    try std.testing.expectEqualStrings("sig-opaque", resp.thinking_signature);
}

test "Anthropic replay uses signature and empty-signature compatibility" {
    const gpa = std.testing.allocator;
    const signed = [_]ai.ChatMessage{.{ .role = "assistant", .content = "answer", .thinking = "plan", .thinking_signature = "sig123" }};
    const body = try buildRequestBodyConfiguredCompat(gpa, "claude", &signed, "[]", false, .off, 100, .{});
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"thinking\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"signature\":\"sig123\"") != null);

    const unsigned = [_]ai.ChatMessage{.{ .role = "assistant", .content = "answer", .thinking = "unfinished" }};
    const normal = try buildRequestBodyConfiguredCompat(gpa, "claude", &unsigned, "[]", false, .off, 100, .{});
    defer gpa.free(normal);
    try std.testing.expect(std.mem.indexOf(u8, normal, "\"thinking\":\"unfinished\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, normal, "\"type\":\"text\",\"text\":\"unfinished\"") != null);

    const compatible = try buildRequestBodyConfiguredCompat(gpa, "claude", &unsigned, "[]", false, .off, 100, .{ .allow_empty_signature = true });
    defer gpa.free(compatible);
    try std.testing.expect(std.mem.indexOf(u8, compatible, "\"thinking\":\"unfinished\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, compatible, "\"signature\":\"\"") != null);
}

test "Anthropic signature_delta is accumulated" {
    const gpa = std.testing.allocator;
    var sig: std.ArrayList(u8) = .empty;
    defer sig.deinit(gpa);
    try observeAnthropicSignature(gpa, "content_block_start", "{\"content_block\":{\"type\":\"thinking\",\"signature\":\"abc\"}}", &sig);
    try observeAnthropicSignature(gpa, "content_block_delta", "{\"delta\":{\"type\":\"signature_delta\",\"signature\":\"def\"}}", &sig);
    try std.testing.expectEqualStrings("abcdef", sig.items);
}

test "anthropic cache-control marks system last user and last tool with 1h ttl" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "system", .content = "sys" },
        .{ .role = "user", .content = "hello" },
    };
    const tools =
        \\[{"type":"function","function":{"name":"read","description":"read","parameters":{"type":"object"}}},{"type":"function","function":{"name":"bash","description":"bash","parameters":{"type":"object"}}}]
    ;
    const body = try buildRequestBodyConfiguredCompatCached(gpa, "claude", &msgs, tools, false, .off, 100, .{
        .cache_control_format = .anthropic,
        .supports_long_cache_retention = true,
    }, .long);
    defer gpa.free(body);
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, body, pos, "\"cache_control\"")) |i| {
        count += 1;
        pos = i + 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"ttl\":\"1h\"") != null);

    const none_body = try buildRequestBodyConfiguredCompatCached(gpa, "claude", &msgs, tools, false, .off, 100, .{
        .cache_control_format = .anthropic,
        .supports_long_cache_retention = true,
    }, .none);
    defer gpa.free(none_body);
    try std.testing.expect(std.mem.indexOf(u8, none_body, "cache_control") == null);
}

test "Anthropic deferred tools use root defer_loading and tool_reference boundary" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"immediate","description":"now","parameters":{"type":"object"}}},{"type":"function","function":{"name":"late_tool","description":"later","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const msgs = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"immediate\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "loaded after result", .tool_call_id = "c1", .tool_name = "immediate", .added_tool_names = &added },
    };
    const body = try buildRequestBodyConfiguredCompatCached(gpa, "claude", &msgs, tools, false, .off, 100, .{ .supports_tool_references = true }, .short);
    defer gpa.free(body);
    const late_at = std.mem.indexOf(u8, body, "\"name\":\"late_tool\"") orelse return error.TestUnexpectedResult;
    const late_tail = body[late_at..];
    try std.testing.expect(std.mem.indexOf(u8, late_tail, "\"defer_loading\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"content\":[{\"type\":\"tool_reference\",\"tool_name\":\"late_tool\"}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "{\"type\":\"text\",\"text\":\"loaded after result\"}") != null);
}

test "Anthropic all-deferred catalog falls back to immediate tools" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"late_tool","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const msgs = [_]ai.ChatMessage{
        .{ .role = "tool", .content = "result", .tool_call_id = "c1", .tool_name = "other", .added_tool_names = &added },
    };
    const body = try buildRequestBodyConfiguredCompatCached(gpa, "claude", &msgs, tools, false, .off, 100, .{ .supports_tool_references = true }, .short);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "defer_loading") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "tool_reference") == null);
}

test "Anthropic compat emits eager strict adaptive sampling and gates tool cache" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"strict_tool","parameters":{"type":"object","properties":{"x":{"type":"string"}},"required":["x"],"additionalProperties":false,"title":"StrictToolInput"}},"constrainedSampling":{"type":"json_schema","strict":"prefer"}}]
    ;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const params = [_]metadata.SamplingParam{
        .{ .name = "temperature", .value_json = "0.7" },
        .{ .name = "top_p", .value_json = "0.9" },
    };
    const adaptive = try buildRequestBodyConfiguredCompatCachedSampling(gpa, "claude", &msgs, tools, false, .high, 1000, .{
        .force_adaptive_thinking = true,
        .supports_strict_tools = true,
        .supports_eager_tool_input_streaming = true,
        .cache_control_format = .anthropic,
        .supports_cache_control_on_tools = false,
    }, .short, &params);
    defer gpa.free(adaptive);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"thinking\":{\"type\":\"adaptive\",\"display\":\"summarized\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"output_config\":{\"effort\":\"high\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"eager_input_streaming\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"strict\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"additionalProperties\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"title\":\"StrictToolInput\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"top_p\":0.9") != null);
    try std.testing.expect(std.mem.indexOf(u8, adaptive, "\"temperature\":0.7") == null);
    const tool_at = std.mem.indexOf(u8, adaptive, "\"name\":\"strict_tool\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, adaptive[tool_at..], "cache_control") == null);

    const plain = try buildRequestBodyConfiguredCompatCachedSampling(gpa, "claude", &msgs, tools, false, .off, 1000, .{ .supports_temperature = true }, .none, &params);
    defer gpa.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "\"temperature\":0.7") != null);
}

test "Anthropic serializes user and tool images as base64 blocks" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "user", .content = "look", .image_b64 = "AQID", .image_mime = "image/png", .images = &.{.{ .data_b64 = "BAUG", .mime_type = "image/webp" }} },
        .{ .role = "tool", .content = "captured", .tool_call_id = "c1", .tool_name = "shot", .image_b64 = "AA==", .image_mime = "image/jpeg", .images = &.{.{ .data_b64 = "AQ==", .mime_type = "image/gif" }} },
    };
    const body = try buildRequestBody(gpa, "claude-test", &messages, "[]");
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"image\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"media_type\":\"image/png\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"media_type\":\"image/jpeg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"media_type\":\"image/webp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"media_type\":\"image/gif\"") != null);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, body, "\"type\":\"image\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"tool_result\"") != null);
}

test "Kimi Anthropic request uses adaptive summarized thinking and preserves empty signature" {
    const gpa = std.testing.allocator;
    const metadata_mod = @import("request_metadata.zig");
    const compat = metadata_mod.detectAnthropicCompat("kimi-coding", "kimi-for-coding");
    const msgs = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .thinking = "internal reasoning", .thinking_signature = "" },
        .{ .role = "user", .content = "continue" },
    };
    const body = try buildRequestBodyConfiguredCompatCachedSampling(gpa, "kimi-for-coding", &msgs, "[]", false, .medium, 8192, compat, .short, &.{});
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinking\":{\"type\":\"adaptive\",\"display\":\"summarized\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"output_config\":{\"effort\":\"medium\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"thinking\",\"thinking\":\"internal reasoning\",\"signature\":\"\"") != null);
}
