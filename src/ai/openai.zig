//! OpenAI-compatible chat completions + tools (complete + stream:true SSE).
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const stream_mod = @import("stream.zig");
const metadata = @import("request_metadata.zig");
const providers = @import("providers.zig");
const cost_mod = @import("cost.zig");
const cloudflare = @import("cloudflare.zig");
const copilot = @import("github_copilot.zig");
const constrained = @import("constrained_sampling.zig");
const thinking_mod = @import("thinking.zig");

pub const TokenRefreshFn = *const fn (*anyopaque, *OpenAIClient, i64) anyerror!void;

pub const OpenAIClient = struct {
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
    provider_id: []const u8 = "openai",
    api_id: []const u8 = "openai-completions",
    thinking: ai.ThinkingLevel = .off,
    reasoning: bool = true,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    custom_headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    model_cost: providers.ModelCost = .{},
    /// Cooperative cancel checked during SSE drain.
    abort_flag: ?*bool = null,
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,

    pub fn client(self: *OpenAIClient) ai.ModelClient {
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
        const self: *OpenAIClient = @ptrCast(@alignCast(ptr));
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
        const self: *OpenAIClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, true, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn ensureTokenFresh(self: *OpenAIClient) !void {
        const expires = self.token_expiration_ms orelse return;
        const refresh_fn = self.token_refresh_fn orelse return;
        const ctx = self.token_refresh_ctx orelse return;
        const now_ms = std.Io.Clock.real.now(self.io).toMilliseconds();
        if (now_ms < expires) return;
        try refresh_fn(ctx, self, now_ms);
    }

    fn request(
        self: *OpenAIClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        try self.ensureTokenFresh();
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const effective_cache_retention: metadata.CacheRetention = ai.resolveCacheRetention(self.cache_retention, request_options);
        const effective_session_id: ?[]const u8 = ai.resolveSessionAffinity(self.session_id, request_options);
        const payload = try buildRequestBodyConfigured(gpa, self.model, effective_messages, tools_json, .{
            .stream = streaming,
            .thinking = self.thinking,
            .reasoning = self.reasoning,
            .thinking_level_map = self.thinking_level_map,
            .max_tokens = effective_max_tokens,
            .sampling_params = self.sampling_params,
            .compat = self.compat,
            .session_id = if (effective_cache_retention != .none and effective_session_id != null and
                (std.mem.indexOf(u8, self.base_url, "api.openai.com") != null or
                    (effective_cache_retention == .long and self.compat.supports_long_cache_retention == true))) effective_session_id else null,
            .cache_retention = effective_cache_retention,
        });
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/chat/completions", .{self.base_url});
        defer gpa.free(url);

        var retry_index: usize = 0;
        while (true) {
            const result = self.requestOnce(gpa, payload, url, tools_json, messages, effective_session_id, streaming, on_delta, delta_ctx) catch |err| {
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
        self: *OpenAIClient,
        gpa: std.mem.Allocator,
        payload: []const u8,
        url: []const u8,
        tools_json: []const u8,
        messages: []const ai.ChatMessage,
        session_id: ?[]const u8,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{
            .allocator = gpa,
            .io = self.io,
        };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });

        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHttpHeader(gpa, &headers, "content-type", "application/json");
        if (cloudflare.isAIGateway(self.provider_id)) {
            try putHttpHeader(gpa, &headers, "cf-aig-authorization", authorization);
        } else {
            try putHttpHeader(gpa, &headers, "authorization", authorization);
        }
        try putHttpHeader(gpa, &headers, "accept", if (streaming) "text/event-stream" else "application/json");
        if (session_id) |sid| try appendSessionAffinityHeaders(gpa, &headers, self.provider_id, sid, self.compat);
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
        // Custom headers are last for normal OpenAI-compatible transports, matching upstream override semantics.
        for (self.custom_headers) |header| try putHttpHeader(gpa, &headers, header.name, header.value);

        // Live SSE writer: parse complete lines as HTTP body chunks drain into us
        var live = LiveSseWriter.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
        live.attachBuffer();
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
            const response_json = try live.body.toOwnedSlice(gpa);
            defer gpa.free(response_json);
            var response = try httpErrorResponse(gpa, self.provider_id, status, response_json);
            response.provider_status = fetch_result.provider.status;
            response.provider_retry_after_ms = fetch_result.provider.retry_after_ms;
            response.provider_should_retry = fetch_result.provider.should_retry;
            return response;
        }
        if (streaming) {
            if (self.compat.supports_finish_reason == true and !live.saw_finish_reason) return error.StreamEndedWithoutFinishReason;
            var resp = try live.acc.finish();
            for (resp.tool_calls) |*tool_call| {
                if (try constrained.normalizeGrammarArguments(gpa, tools_json, self.compat.supports_openai_grammar_tools == true, tool_call.name, tool_call.arguments)) |normalized| {
                    gpa.free(tool_call.arguments);
                    tool_call.arguments = normalized;
                }
            }
            for (resp.tool_calls) |*tool_call| {
                for (live.reasoning_details.items) |detail| {
                    if (std.mem.eql(u8, detail.id, tool_call.id)) {
                        tool_call.thought_signature = try gpa.dupe(u8, detail.json);
                        break;
                    }
                }
            }
            // Accumulator.finish() duplicates its output; it does not consume the
            // accumulator buffers. Keep them attached so live.deinit() releases them.
            resp.provider = try gpa.dupe(u8, self.provider_id);
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
        var resp = try parseOpenAIResponseConfigured(gpa, response_json, tools_json, self.compat);
        try normalizeRequestedModel(gpa, &resp, self.model);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, self.provider_id);
        _ = cost_mod.calculate(self.model_cost, &resp.usage);
        try resp.ensureStopReason(gpa);
        return resp;
    }
};

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

fn appendSessionAffinityHeaders(
    gpa: std.mem.Allocator,
    headers: *std.ArrayList(std.http.Header),
    provider_id: []const u8,
    sid: []const u8,
    compat: metadata.Compat,
) !void {
    if (compat.send_session_affinity_headers != true) return;
    const format = compat.session_affinity_format orelse
        if (std.ascii.eqlIgnoreCase(provider_id, "openrouter")) metadata.SessionAffinityFormat.openrouter else metadata.SessionAffinityFormat.openai;
    switch (format) {
        .openrouter => try putHttpHeader(gpa, headers, "x-session-id", sid),
        .openai => {
            try putHttpHeader(gpa, headers, "session_id", sid);
            try putHttpHeader(gpa, headers, "x-client-request-id", sid);
            try putHttpHeader(gpa, headers, "x-session-affinity", sid);
        },
        .openai_nosession => {
            try putHttpHeader(gpa, headers, "x-client-request-id", sid);
            try putHttpHeader(gpa, headers, "x-session-affinity", sid);
        },
    }
}

const ReasoningDetail = struct {
    id: []const u8,
    json: []const u8,

    fn deinit(self: *ReasoningDetail, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.json);
        self.* = undefined;
    }
};

fn isEncryptedReasoningDetail(value: std.json.Value) bool {
    if (value != .object) return false;
    const typ = value.object.get("type") orelse return false;
    const id = value.object.get("id") orelse return false;
    const data = value.object.get("data") orelse return false;
    return typ == .string and std.mem.eql(u8, typ.string, "reasoning.encrypted") and
        id == .string and id.string.len > 0 and data == .string and data.string.len > 0;
}

fn serializeReasoningDetail(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

/// HTTP response_writer that accumulates body AND parses OpenAI SSE lines as they arrive.
const LiveSseWriter = struct {
    gpa: std.mem.Allocator,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
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
    saw_finish_reason: bool = false,
    reasoning_details: std.ArrayList(ReasoningDetail) = .empty,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .flush = std.Io.Writer.noopFlush,
    };

    fn init(gpa: std.mem.Allocator, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, streaming: bool, abort_flag: ?*bool) LiveSseWriter {
        // Unbuffered writer so every write goes through drain (safe with by-value return).
        return .{
            .gpa = gpa,
            .writer = .{
                .vtable = &vtable,
                .buffer = &.{},
                .end = 0,
            },
            .acc = stream_mod.Accumulator.init(gpa),
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .streaming = streaming,
            .abort_flag = abort_flag,
        };
    }

    /// Bind the Writer's backing storage after the containing struct has reached
    /// its stable stack address. A zero-length buffer triggers an assertion in
    /// Zig 0.16's Reader.stream fast path during real HTTP response transfer.
    fn attachBuffer(self: *LiveSseWriter) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }

    fn deinit(self: *LiveSseWriter) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.acc.deinit();
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.response_model.len > 0) self.gpa.free(self.response_model);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        for (self.reasoning_details.items) |*detail| detail.deinit(self.gpa);
        self.reasoning_details.deinit(self.gpa);
        self.* = undefined;
    }

    fn flushTrailing(self: *LiveSseWriter) !void {
        // Flush any buffered Writer bytes into body/SSE path
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if (self.streaming and self.line.items.len > 0) {
            try self.handleLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }

    fn feed(self: *LiveSseWriter, chunk: []const u8) !void {
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

    fn handleLine(self: *LiveSseWriter, line: []const u8) !void {
        const t = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, t, "data:")) return;
        const data = std.mem.trim(u8, t["data:".len..], " \t");
        observeOpenAIChunk(data, &self.usage, &self.stop_reason, &self.saw_finish_reason);
        try self.observeResponseMetadata(data);
        try self.observeReasoningDetails(data);
        if (try stream_mod.parseOpenAISseData(self.gpa, data)) |delta| {
            defer stream_mod.freeDelta(self.gpa, delta);
            try self.acc.onDelta(delta);
            if (self.on_delta) |h| h(self.delta_ctx, delta);
        }
    }

    fn observeResponseMetadata(self: *LiveSseWriter, data: []const u8) !void {
        const trimmed = std.mem.trim(u8, data, " \t\r\n");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "[DONE]")) return;
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, trimmed, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        if (self.response_id.len == 0) if (parsed.value.object.get("id")) |id| if (id == .string and id.string.len > 0) {
            self.response_id = try self.gpa.dupe(u8, id.string);
        };
        if (self.response_model.len == 0) if (parsed.value.object.get("model")) |model| if (model == .string and model.string.len > 0) {
            self.response_model = try self.gpa.dupe(u8, model.string);
        };
        if (parsed.value.object.get("choices")) |choices| if (choices == .array and choices.array.items.len > 0) {
            const first = choices.array.items[0];
            if (first == .object) if (first.object.get("finish_reason")) |fr| if (fr == .string and fr.string.len > 0) {
                if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
                self.raw_stop_reason = try self.gpa.dupe(u8, fr.string);
            };
        };
    }

    fn observeReasoningDetails(self: *LiveSseWriter, data: []const u8) !void {
        const trimmed = std.mem.trim(u8, data, " \t\r\n");
        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "[DONE]")) return;
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, trimmed, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const choices = parsed.value.object.get("choices") orelse return;
        if (choices != .array or choices.array.items.len == 0) return;
        const first = choices.array.items[0];
        if (first != .object) return;
        const delta = first.object.get("delta") orelse return;
        if (delta != .object) return;
        const details = delta.object.get("reasoning_details") orelse return;
        if (details != .array) return;
        for (details.array.items) |detail| {
            if (!isEncryptedReasoningDetail(detail)) continue;
            const id_value = detail.object.get("id").?;
            var replaced = false;
            for (self.reasoning_details.items) |*existing| {
                if (std.mem.eql(u8, existing.id, id_value.string)) {
                    self.gpa.free(existing.json);
                    existing.json = try serializeReasoningDetail(self.gpa, detail);
                    replaced = true;
                    break;
                }
            }
            if (!replaced) try self.reasoning_details.append(self.gpa, .{
                .id = try self.gpa.dupe(u8, id_value.string),
                .json = try serializeReasoningDetail(self.gpa, detail),
            });
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *LiveSseWriter = @fieldParentPtr("writer", w);
        // Consume buffered writer contents first
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

fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "aborted"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "aborted"),
    };
}

fn httpErrorResponse(gpa: std.mem.Allocator, provider: []const u8, status: u16, body: []const u8) !ai.ModelResponse {
    const snippet = if (body.len > 800) body[0..800] else body;
    const content = try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s}", .{ status, provider, snippet });
    return .{
        .content = content,
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, ""),
        .stop_reason = try gpa.dupe(u8, "error"),
    };
}

/// Consume a full OpenAI SSE response body through the shipped stream parsers.
/// This is the same path production streamFn uses after HTTP fetch.
pub fn consumeOpenAIStreamBody(
    gpa: std.mem.Allocator,
    sse_body: []const u8,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    model: []const u8,
) !ai.ModelResponse {
    var acc = stream_mod.Accumulator.init(gpa);
    defer acc.deinit();

    var it = std.mem.splitScalar(u8, sse_body, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "data:")) continue;
        const data = std.mem.trim(u8, t["data:".len..], " \t");
        if (try stream_mod.parseOpenAISseData(gpa, data)) |delta| {
            defer stream_mod.freeDelta(gpa, delta);
            try acc.onDelta(delta);
            if (on_delta) |h| h(delta_ctx, delta);
        }
    }

    var resp = try acc.finish();
    resp.provider = try gpa.dupe(u8, "openai");
    resp.model = try gpa.dupe(u8, model);
    try resp.ensureStopReason(gpa);
    return resp;
}

fn jsonU64(value: ?std.json.Value) u64 {
    const v = value orelse return 0;
    if (v != .integer or v.integer < 0) return 0;
    return @intCast(v.integer);
}

pub fn parseOpenAIUsage(value: std.json.Value) ai.Usage {
    if (value != .object) return .{};
    const prompt = jsonU64(value.object.get("prompt_tokens"));
    const output = jsonU64(value.object.get("completion_tokens"));
    var cached: u64 = 0;
    var cache_write: u64 = 0;
    if (value.object.get("prompt_tokens_details")) |details| {
        if (details == .object) {
            cached = jsonU64(details.object.get("cached_tokens"));
            cache_write = jsonU64(details.object.get("cache_write_tokens"));
        }
    }
    const cache_read = if (cache_write > 0) cached -| @min(cached, cache_write) else cached;
    const uncached = prompt -| @min(prompt, cache_read + cache_write);
    var reasoning: ?u64 = null;
    if (value.object.get("completion_tokens_details")) |details| {
        if (details == .object and details.object.get("reasoning_tokens") != null) {
            reasoning = jsonU64(details.object.get("reasoning_tokens"));
        }
    }
    var usage: ai.Usage = .{
        .input = uncached,
        .output = output,
        .cache_read = cache_read,
        .cache_write = cache_write,
        .reasoning = reasoning,
    };
    usage.normalizeTotal();
    return usage;
}

fn observeOpenAIChunk(data: []const u8, usage: *ai.Usage, stop_reason: *[]const u8, saw_finish_reason: *bool) void {
    const trimmed = std.mem.trim(u8, data, " \\t\\r\\n");
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "[DONE]")) return;
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, trimmed, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    if (parsed.value.object.get("usage")) |raw| usage.* = parseOpenAIUsage(raw);
    if (parsed.value.object.get("choices")) |choices| {
        if (choices == .array and choices.array.items.len > 0) {
            const first = choices.array.items[0];
            if (first == .object) {
                if (first.object.get("finish_reason")) |fr| {
                    if (fr == .string and fr.string.len > 0) {
                        saw_finish_reason.* = true;
                        if (std.mem.eql(u8, fr.string, "tool_calls")) stop_reason.* = "toolUse" else if (std.mem.eql(u8, fr.string, "length")) stop_reason.* = "length" else if (std.mem.eql(u8, fr.string, "stop")) stop_reason.* = "stop";
                    }
                }
            }
        }
    }
}

pub fn parseOpenAIResponse(gpa: std.mem.Allocator, response_json: []const u8) !ai.ModelResponse {
    return parseOpenAIResponseConfigured(gpa, response_json, "[]", .{});
}

fn parseOpenAIResponseConfigured(gpa: std.mem.Allocator, response_json: []const u8, tools_json: []const u8, compat: metadata.Compat) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;

    const choices = parsed.value.object.get("choices") orelse return error.InvalidResponse;
    if (choices != .array or choices.array.items.len == 0) return error.InvalidResponse;
    const first = choices.array.items[0];
    if (first != .object) return error.InvalidResponse;
    const message = first.object.get("message") orelse return error.InvalidResponse;
    if (message != .object) return error.InvalidResponse;

    const content_v = message.object.get("content");
    const content: []const u8 = if (content_v) |cv| switch (cv) {
        .string => cv.string,
        .null => "",
        else => "",
    } else "";
    const thinking_v = message.object.get("reasoning_content") orelse message.object.get("reasoning");
    const thinking_text: []const u8 = if (thinking_v) |tv| if (tv == .string) tv.string else "" else "";

    var tcs: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (tcs.items) |*tc| tc.deinit(gpa);
        tcs.deinit(gpa);
    }

    if (message.object.get("tool_calls")) |tc_val| {
        if (tc_val == .array) {
            for (tc_val.array.items) |tc_item| {
                if (tc_item != .object) continue;
                const id = tc_item.object.get("id") orelse continue;
                if (id != .string) continue;
                var name_string: []const u8 = "";
                var args_string: []const u8 = "";
                var owned_args: ?[]u8 = null;
                defer if (owned_args) |value| gpa.free(value);
                if (tc_item.object.get("function")) |fn_obj| {
                    if (fn_obj != .object) continue;
                    const name = fn_obj.object.get("name") orelse continue;
                    const args = fn_obj.object.get("arguments") orelse continue;
                    if (name != .string or args != .string) continue;
                    name_string = name.string;
                    args_string = args.string;
                } else if (tc_item.object.get("custom")) |custom_obj| {
                    if (custom_obj != .object) continue;
                    const name = custom_obj.object.get("name") orelse continue;
                    const input = custom_obj.object.get("input") orelse continue;
                    if (name != .string or input != .string) continue;
                    name_string = name.string;
                    owned_args = (try constrained.normalizeGrammarArguments(gpa, tools_json, compat.supports_openai_grammar_tools == true, name.string, input.string)) orelse try constrained.wrapGrammarInput(gpa, "input", input.string);
                    args_string = owned_args.?;
                } else continue;
                var thought_signature: []const u8 = "";
                if (message.object.get("reasoning_details")) |details| {
                    if (details == .array) {
                        for (details.array.items) |detail| {
                            if (!isEncryptedReasoningDetail(detail)) continue;
                            const detail_id = detail.object.get("id").?;
                            if (std.mem.eql(u8, detail_id.string, id.string)) {
                                thought_signature = try serializeReasoningDetail(gpa, detail);
                                break;
                            }
                        }
                    }
                }
                errdefer if (thought_signature.len > 0) gpa.free(thought_signature);
                try tcs.append(gpa, .{
                    .id = try gpa.dupe(u8, id.string),
                    .name = try gpa.dupe(u8, name_string),
                    .arguments = try gpa.dupe(u8, args_string),
                    .thought_signature = thought_signature,
                });
            }
        }
    }

    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usage")) |u| usage = parseOpenAIUsage(u);

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
    if (first.object.get("finish_reason")) |fr| {
        if (fr == .string) {
            raw_stop_reason = try gpa.dupe(u8, fr.string);
            if (std.mem.eql(u8, fr.string, "tool_calls")) {
                stop_reason = try gpa.dupe(u8, "toolUse");
            } else if (std.mem.eql(u8, fr.string, "length")) {
                stop_reason = try gpa.dupe(u8, "length");
            } else if (std.mem.eql(u8, fr.string, "stop")) {
                stop_reason = try gpa.dupe(u8, "stop");
            } else {
                stop_reason = try gpa.dupe(u8, fr.string);
            }
        }
    }

    var resp: ai.ModelResponse = .{
        .content = try gpa.dupe(u8, content),
        .thinking = if (thinking_text.len > 0) try gpa.dupe(u8, thinking_text) else "",
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "openai"),
        .model = model_out,
        .response_id = response_id,
        .raw_stop_reason = raw_stop_reason,
        .stop_reason = stop_reason,
        .usage = usage,
    };
    try resp.ensureStopReason(gpa);
    return resp;
}

pub const RequestOptions = struct {
    stream: bool = false,
    thinking: ai.ThinkingLevel = .off,
    reasoning: bool = true,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    max_tokens: u64 = 0,
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
};

fn hasSampling(params: []const metadata.SamplingParam, name: []const u8) bool {
    for (params) |param| if (std.mem.eql(u8, param.name, name)) return true;
    return false;
}

fn mappedThinkingValue(map: ?thinking_mod.ThinkingLevelMap, level: ai.ThinkingLevel, fallback: ?[]const u8) ?[]const u8 {
    const m = map orelse return fallback;
    return switch (m.entry(level)) {
        .absent => fallback,
        .unsupported => null,
        .mapped => |value| value,
    };
}

fn explicitlyMappedThinkingValue(map: ?thinking_mod.ThinkingLevelMap, level: ai.ThinkingLevel) ?[]const u8 {
    const m = map orelse return null;
    return switch (m.entry(level)) {
        .mapped => |value| value,
        else => null,
    };
}

fn thinkingLevelUnsupported(map: ?thinking_mod.ThinkingLevelMap, level: ai.ThinkingLevel) bool {
    const m = map orelse return false;
    return switch (m.entry(level)) {
        .unsupported => true,
        else => false,
    };
}

fn templateValueResolves(value: std.json.Value, options: RequestOptions) bool {
    if (value != .object) return switch (value) {
        .string, .integer, .float, .bool, .null => true,
        else => false,
    };
    const variable = value.object.get("$var") orelse return false;
    if (variable != .string) return false;
    const omit_when_off = if (value.object.get("omitWhenOff")) |omit| omit == .bool and omit.bool else false;
    const enabled = options.thinking != .off;
    if (!enabled and omit_when_off) return false;
    if (std.mem.eql(u8, variable.string, "thinking.enabled")) return true;
    if (!std.mem.eql(u8, variable.string, "thinking.effort")) return false;
    return mappedThinkingValue(options.thinking_level_map, options.thinking, options.thinking.openaiEffort()) != null;
}

fn writeTemplateValue(w: anytype, value: std.json.Value, options: RequestOptions) !bool {
    if (value != .object) {
        switch (value) {
            .string, .integer, .float, .bool, .null => {
                try std.json.Stringify.value(value, .{}, w);
                return true;
            },
            else => return false,
        }
    }
    const variable = value.object.get("$var") orelse return false;
    if (variable != .string) return false;
    const omit_when_off = if (value.object.get("omitWhenOff")) |omit| omit == .bool and omit.bool else false;
    const enabled = options.thinking != .off;
    if (!enabled and omit_when_off) return false;
    if (std.mem.eql(u8, variable.string, "thinking.enabled")) {
        try w.writeAll(if (enabled) "true" else "false");
        return true;
    }
    if (!std.mem.eql(u8, variable.string, "thinking.effort")) return false;
    const resolved = mappedThinkingValue(options.thinking_level_map, options.thinking, options.thinking.openaiEffort()) orelse return false;
    try std.json.Stringify.value(resolved, .{}, w);
    return true;
}

fn writeChatTemplateObject(w: anytype, field_name: []const u8, values: ?std.json.ObjectMap, options: RequestOptions) !void {
    const object = values orelse return;
    var count: usize = 0;
    var count_it = object.iterator();
    while (count_it.next()) |entry| {
        if (templateValueResolves(entry.value_ptr.*, options)) count += 1;
    }
    if (count == 0) return;

    try w.writeAll(",");
    try std.json.Stringify.value(field_name, .{}, w);
    try w.writeAll(":{");
    var first = true;
    var it = object.iterator();
    while (it.next()) |entry| {
        if (!templateValueResolves(entry.value_ptr.*, options)) continue;
        if (!first) try w.writeAll(",");
        first = false;
        try std.json.Stringify.value(entry.key_ptr.*, .{}, w);
        try w.writeAll(":");
        _ = try writeTemplateValue(w, entry.value_ptr.*, options);
    }
    try w.writeAll("}");
}

fn writeThinkingFields(w: anytype, options: RequestOptions) !void {
    if (!options.reasoning) return;
    const enabled = options.thinking != .off;
    const raw_effort = options.thinking.openaiEffort();
    const mapped_effort = mappedThinkingValue(options.thinking_level_map, options.thinking, raw_effort);
    const format = options.compat.thinking_format;

    if (format == .zai) {
        if (!hasSampling(options.sampling_params, "thinking")) {
            try w.writeAll(if (enabled) ",\"thinking\":{\"type\":\"enabled\",\"clear_thinking\":false}" else ",\"thinking\":{\"type\":\"disabled\"}");
        }
        if (enabled and options.compat.supports_reasoning_effort == true and mapped_effort != null and !hasSampling(options.sampling_params, "reasoning_effort")) {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(mapped_effort.?, .{}, w);
        }
        return;
    }
    if (format == .qwen) {
        if (!hasSampling(options.sampling_params, "enable_thinking"))
            try w.print(",\"enable_thinking\":{s}", .{if (enabled) "true" else "false"});
        if (enabled and options.compat.supports_reasoning_effort != false and mapped_effort != null and !hasSampling(options.sampling_params, "reasoning_effort")) {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(mapped_effort.?, .{}, w);
        }
        return;
    }
    if (format == .qwen_chat_template) {
        if (!hasSampling(options.sampling_params, "chat_template_kwargs")) {
            try w.print(",\"chat_template_kwargs\":{{\"enable_thinking\":{s},\"preserve_thinking\":true}}", .{if (enabled) "true" else "false"});
        }
        return;
    }
    if (format == .chat_template) {
        if (!hasSampling(options.sampling_params, "chat_template_kwargs"))
            try writeChatTemplateObject(w, "chat_template_kwargs", options.compat.chat_template_kwargs, options);
        return;
    }
    if (format == .baseten) {
        if (!hasSampling(options.sampling_params, "chat_template_args")) {
            if (options.compat.chat_template_args != null) {
                try writeChatTemplateObject(w, "chat_template_args", options.compat.chat_template_args, options);
            } else {
                // Generated Baseten models all use
                // { enable_thinking: { $var: "thinking.enabled" } }. Keep the
                // static catalog allocation-free while preserving that wire shape.
                try w.print(",\"chat_template_args\":{{\"enable_thinking\":{s}}}", .{if (enabled) "true" else "false"});
            }
        }
        if (options.compat.supports_reasoning_effort == true and mapped_effort != null and !hasSampling(options.sampling_params, "reasoning_effort")) {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(mapped_effort.?, .{}, w);
        }
        return;
    }
    if (format == .deepseek) {
        if (!hasSampling(options.sampling_params, "thinking")) {
            if (enabled) {
                try w.writeAll(",\"thinking\":{\"type\":\"enabled\"}");
            } else if (!thinkingLevelUnsupported(options.thinking_level_map, .off)) {
                try w.writeAll(",\"thinking\":{\"type\":\"disabled\"}");
            }
        }
        if (enabled and options.compat.supports_reasoning_effort == true and mapped_effort != null and !hasSampling(options.sampling_params, "reasoning_effort")) {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(mapped_effort.?, .{}, w);
        }
        return;
    }
    if (format == .openrouter) {
        const openrouter_effort: ?[]const u8 = if (enabled)
            mapped_effort
        else
            mappedThinkingValue(options.thinking_level_map, .off, "none");
        if (openrouter_effort != null and !hasSampling(options.sampling_params, "reasoning")) {
            try w.writeAll(",\"reasoning\":{\"effort\":");
            try std.json.Stringify.value(openrouter_effort.?, .{}, w);
            try w.writeAll("}");
        }
        return;
    }
    if (format == .ant_ling) {
        if (enabled) {
            if (explicitlyMappedThinkingValue(options.thinking_level_map, options.thinking)) |effort| {
                if (!hasSampling(options.sampling_params, "reasoning")) {
                    try w.writeAll(",\"reasoning\":{\"effort\":");
                    try std.json.Stringify.value(effort, .{}, w);
                    try w.writeAll("}");
                }
            }
        }
        return;
    }
    if (format == .together) {
        if (!hasSampling(options.sampling_params, "reasoning"))
            try w.print(",\"reasoning\":{{\"enabled\":{s}}}", .{if (enabled) "true" else "false"});
        if (enabled and options.compat.supports_reasoning_effort == true and mapped_effort != null and !hasSampling(options.sampling_params, "reasoning_effort")) {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(mapped_effort.?, .{}, w);
        }
        return;
    }
    if (format == .string_thinking) {
        const string_value: ?[]const u8 = if (enabled)
            mapped_effort
        else
            mappedThinkingValue(options.thinking_level_map, .off, "none");
        if (string_value != null and !hasSampling(options.sampling_params, "thinking")) {
            try w.writeAll(",\"thinking\":");
            try std.json.Stringify.value(string_value.?, .{}, w);
        }
        return;
    }

    // OpenAI-style reasoning_effort. A mapped `off` string may explicitly
    // disable reasoning; an explicit null/unsupported hole omits the field.
    if (options.compat.supports_reasoning_effort != false and !hasSampling(options.sampling_params, "reasoning_effort")) {
        const effort: ?[]const u8 = if (enabled)
            mapped_effort
        else
            explicitlyMappedThinkingValue(options.thinking_level_map, .off);
        if (effort) |value| {
            try w.writeAll(",\"reasoning_effort\":");
            try std.json.Stringify.value(value, .{}, w);
        }
    }
}

fn isToolIdChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

fn sanitizeToolIdPart(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, raw.len);
    for (raw, 0..) |c, i| out[i] = if (isToolIdChar(c)) c else '_';
    return out;
}

/// Responses can persist IDs as `call_id|item_id`. Chat Completions accepts one
/// function-call ID, so derive one stable safe ID and use it for both the
/// assistant call and its tool-result replay.
fn normalizeToolCallId(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    const bar = std.mem.indexOfScalar(u8, raw, '|') orelse return gpa.dupe(u8, raw);
    const call = try sanitizeToolIdPart(gpa, raw[0..bar]);
    defer gpa.free(call);
    const item = try sanitizeToolIdPart(gpa, raw[bar + 1 ..]);
    defer gpa.free(item);
    const combined = if (item.len > 0)
        try std.fmt.allocPrint(gpa, "{s}_{s}", .{ call, item })
    else
        try gpa.dupe(u8, call);
    if (combined.len <= 40) return combined;
    defer gpa.free(combined);
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(raw);
    const hash = hasher.final();
    var suffix_buf: [8]u8 = undefined;
    _ = try std.fmt.bufPrint(&suffix_buf, "{x:0>8}", .{@as(u32, @truncate(hash))});
    const prefix_len = @min(call.len, 31);
    return std.fmt.allocPrint(gpa, "{s}_{s}", .{ call[0..prefix_len], suffix_buf[0..] });
}

fn writeReasoningDetailsFromToolCalls(gpa: std.mem.Allocator, w: anytype, raw: []const u8) !bool {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array) return false;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try out.writer.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const signature = item.object.get("thoughtSignature") orelse continue;
        if (signature != .string or signature.string.len == 0) continue;
        var detail = std.json.parseFromSlice(std.json.Value, gpa, signature.string, .{}) catch continue;
        defer detail.deinit();
        if (!isEncryptedReasoningDetail(detail.value)) continue;
        if (!first) try out.writer.writeAll(",");
        first = false;
        try std.json.Stringify.value(detail.value, .{}, &out.writer);
    }
    try out.writer.writeAll("]");
    if (first) return false;
    try w.writeAll(",\"reasoning_details\":");
    try w.writeAll(out.written());
    return true;
}

fn writeNormalizedToolCalls(
    gpa: std.mem.Allocator,
    w: anytype,
    raw: []const u8,
    tools_json: []const u8,
    supports_grammar: bool,
) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch {
        try w.writeAll(raw);
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) {
        try w.writeAll(raw);
        return;
    }
    try w.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id_v = item.object.get("id") orelse continue;
        const fn_v = item.object.get("function") orelse continue;
        if (id_v != .string or fn_v != .object) continue;
        const name_v = fn_v.object.get("name") orelse continue;
        const args_v = fn_v.object.get("arguments") orelse continue;
        if (name_v != .string or args_v != .string) continue;
        const id = try normalizeToolCallId(gpa, id_v.string);
        defer gpa.free(id);
        if (!first) try w.writeAll(",");
        first = false;
        try w.writeAll("{\"id\":");
        try std.json.Stringify.value(id, .{}, w);
        if (try constrained.extractGrammarInput(gpa, tools_json, supports_grammar, name_v.string, args_v.string)) |input| {
            defer gpa.free(input);
            try w.writeAll(",\"type\":\"custom\",\"custom\":{\"name\":");
            try std.json.Stringify.value(name_v.string, .{}, w);
            try w.writeAll(",\"input\":");
            try std.json.Stringify.value(input, .{}, w);
            try w.writeAll("}}");
        } else {
            try w.writeAll(",\"type\":\"function\",\"function\":{\"name\":");
            try std.json.Stringify.value(name_v.string, .{}, w);
            try w.writeAll(",\"arguments\":");
            try std.json.Stringify.value(args_v.string, .{}, w);
            try w.writeAll("}}");
        }
    }
    try w.writeAll("]");
}

fn writeAnthropicCacheControlField(w: anytype, long_ttl: bool) !void {
    try w.writeAll(",\"cache_control\":{\"type\":\"ephemeral\"");
    if (long_ttl) try w.writeAll(",\"ttl\":\"1h\"");
    try w.writeAll("}");
}

fn writeFunctionToolConfigured(w: anytype, item: std.json.Value, strict_override: ?bool, supports_strict: bool, add_cache: bool, long_ttl: bool) !void {
    const function = constrained.functionSpec(item) orelse return error.InvalidToolSchema;
    const name = function.get("name") orelse return error.InvalidToolSchema;
    if (name != .string) return error.InvalidToolSchema;
    try w.writeAll("{\"type\":\"function\",\"function\":{\"name\":");
    try std.json.Stringify.value(name.string, .{}, w);
    if (function.get("description")) |description| if (description == .string) {
        try w.writeAll(",\"description\":");
        try std.json.Stringify.value(description.string, .{}, w);
    };
    try w.writeAll(",\"parameters\":");
    if (function.get("parameters")) |parameters| try std.json.Stringify.value(parameters, .{}, w) else try w.writeAll("{\"type\":\"object\"}");
    if (supports_strict) {
        const strict = strict_override orelse if (function.get("strict")) |value| value == .bool and value.bool else false;
        try w.print(",\"strict\":{s}", .{if (strict) "true" else "false"});
    }
    try w.writeAll("}");
    if (add_cache) try writeAnthropicCacheControlField(w, long_ttl);
    try w.writeAll("}");
}

fn historyToolCallsContainName(gpa: std.mem.Allocator, calls_json: []const u8, name: []const u8) !bool {
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

fn isKimiDeferredName(gpa: std.mem.Allocator, messages: []const ai.ChatMessage, name: []const u8) !bool {
    var used = false;
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "assistant")) {
            if (msg.tool_calls_json) |calls| if (try historyToolCallsContainName(gpa, calls, name)) {
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

fn nameSelected(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

fn writeToolsConfiguredSelected(
    gpa: std.mem.Allocator,
    w: anytype,
    tools_json: []const u8,
    compat: metadata.Compat,
    messages: []const ai.ChatMessage,
    exclude_kimi_deferred: bool,
    only_names: ?[]const []const u8,
    cache_last_tool: bool,
    cache_long_ttl: bool,
) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch {
        try w.writeAll(tools_json);
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) {
        try w.writeAll(tools_json);
        return;
    }
    const supports_strict = compat.supports_strict_mode != false;
    const supports_grammar = compat.supports_openai_grammar_tools == true;
    var selected_count: usize = 0;
    for (parsed.value.array.items) |item| {
        const name = constrained.toolName(item) orelse continue;
        if (only_names) |names| if (!nameSelected(names, name)) continue;
        if (exclude_kimi_deferred and try isKimiDeferredName(gpa, messages, name)) continue;
        selected_count += 1;
    }
    var remaining = selected_count;
    try w.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        const name = constrained.toolName(item) orelse continue;
        if (only_names) |names| if (!nameSelected(names, name)) continue;
        if (exclude_kimi_deferred and try isKimiDeferredName(gpa, messages, name)) continue;
        if (!first) try w.writeAll(",");
        first = false;
        const add_cache = cache_last_tool and remaining == 1;
        if (remaining > 0) remaining -= 1;
        if (try constrained.resolveGrammar(item, supports_grammar)) |grammar| {
            try w.writeAll("{\"type\":\"custom\",\"custom\":{\"name\":");
            try std.json.Stringify.value(name, .{}, w);
            if (constrained.functionSpec(item).?.get("description")) |description| if (description == .string) {
                try w.writeAll(",\"description\":");
                try std.json.Stringify.value(description.string, .{}, w);
            };
            try w.writeAll(",\"format\":{\"type\":\"grammar\",\"grammar\":{\"syntax\":");
            try std.json.Stringify.value(grammar.syntax, .{}, w);
            try w.writeAll(",\"definition\":");
            try std.json.Stringify.value(grammar.definition, .{}, w);
            try w.writeAll("}}}");
            if (add_cache) try writeAnthropicCacheControlField(w, cache_long_ttl);
            try w.writeAll("}");
        } else {
            const strict = try constrained.resolveJsonSchemaStrict(item, supports_strict);
            try writeFunctionToolConfigured(w, item, strict, supports_strict, add_cache, cache_long_ttl);
        }
    }
    try w.writeAll("]");
}

fn writeToolsConfigured(gpa: std.mem.Allocator, w: anytype, tools_json: []const u8, compat: metadata.Compat) !void {
    return writeToolsConfiguredSelected(gpa, w, tools_json, compat, &.{}, false, null, false, false);
}

fn writeStringRoutingArray(w: anytype, values: []const std.json.Value) !void {
    try w.writeAll("[");
    for (values, 0..) |value, index| {
        if (index > 0) try w.writeAll(",");
        try std.json.Stringify.value(value.string, .{}, w);
    }
    try w.writeAll("]");
}

fn writeOpenRouterRouting(w: anytype, routing: metadata.OpenRouterRouting) !void {
    try w.writeAll("{");
    var first = true;
    const Field = struct {
        fn prefix(writer: anytype, is_first: *bool, name: []const u8) !void {
            if (!is_first.*) try writer.writeAll(",");
            is_first.* = false;
            try std.json.Stringify.value(name, .{}, writer);
            try writer.writeAll(":");
        }
    };
    if (routing.allow_fallbacks) |v| {
        try Field.prefix(w, &first, "allow_fallbacks");
        try w.writeAll(if (v) "true" else "false");
    }
    if (routing.require_parameters) |v| {
        try Field.prefix(w, &first, "require_parameters");
        try w.writeAll(if (v) "true" else "false");
    }
    if (routing.data_collection) |v| {
        try Field.prefix(w, &first, "data_collection");
        try std.json.Stringify.value(v, .{}, w);
    }
    if (routing.zdr) |v| {
        try Field.prefix(w, &first, "zdr");
        try w.writeAll(if (v) "true" else "false");
    }
    if (routing.enforce_distillable_text) |v| {
        try Field.prefix(w, &first, "enforce_distillable_text");
        try w.writeAll(if (v) "true" else "false");
    }
    if (routing.order) |v| {
        try Field.prefix(w, &first, "order");
        try writeStringRoutingArray(w, v);
    }
    if (routing.only) |v| {
        try Field.prefix(w, &first, "only");
        try writeStringRoutingArray(w, v);
    }
    if (routing.ignore) |v| {
        try Field.prefix(w, &first, "ignore");
        try writeStringRoutingArray(w, v);
    }
    if (routing.quantizations) |v| {
        try Field.prefix(w, &first, "quantizations");
        try writeStringRoutingArray(w, v);
    }
    if (routing.sort) |v| {
        try Field.prefix(w, &first, "sort");
        try std.json.Stringify.value(v, .{}, w);
    }
    if (routing.max_price) |v| {
        try Field.prefix(w, &first, "max_price");
        try std.json.Stringify.value(std.json.Value{ .object = v }, .{}, w);
    }
    if (routing.preferred_min_throughput) |v| {
        try Field.prefix(w, &first, "preferred_min_throughput");
        try std.json.Stringify.value(v, .{}, w);
    }
    if (routing.preferred_max_latency) |v| {
        try Field.prefix(w, &first, "preferred_max_latency");
        try std.json.Stringify.value(v, .{}, w);
    }
    try w.writeAll("}");
}

fn writeVercelGatewayRouting(w: anytype, routing: metadata.VercelGatewayRouting) !void {
    try w.writeAll("{\"gateway\":{");
    var first = true;
    if (routing.only) |values| {
        try w.writeAll("\"only\":");
        try writeStringRoutingArray(w, values);
        first = false;
    }
    if (routing.order) |values| {
        if (!first) try w.writeAll(",");
        try w.writeAll("\"order\":");
        try writeStringRoutingArray(w, values);
    }
    try w.writeAll("}}");
}

/// Build OpenAI chat/completions JSON body (caller frees). Non-streaming.
pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
) ![]u8 {
    return buildRequestBodyOpts(gpa, model, messages, tools_json, false);
}

/// Build OpenAI chat/completions JSON body; when `stream` is true includes `"stream":true`.
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
    return buildRequestBodyConfigured(gpa, model, messages, tools_json, .{ .stream = stream, .thinking = thinking });
}

pub fn buildRequestBodyConfigured(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    options: RequestOptions,
) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    const replay_messages = repaired.messages.items;
    const cache_anthropic = options.compat.cache_control_format == .anthropic and options.cache_retention != .none;
    const cache_long_ttl = cache_anthropic and options.cache_retention == .long and options.compat.supports_long_cache_retention == true;
    var first_instruction_index: ?usize = null;
    var last_cacheable_conversation_index: ?usize = null;
    for (replay_messages, 0..) |message, index| {
        if (first_instruction_index == null and std.mem.eql(u8, message.role, "system")) first_instruction_index = index;
        const conversation = std.mem.eql(u8, message.role, "user") or std.mem.eql(u8, message.role, "assistant") or std.mem.eql(u8, message.role, "tool");
        if (!conversation) continue;
        const has_text = message.content.len > 0 or message.hasImages() or
            (std.mem.eql(u8, message.role, "assistant") and options.compat.requires_thinking_as_text == true and message.thinking != null and message.thinking.?.len > 0);
        if (has_text) last_cacheable_conversation_index = index;
    }

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    if (options.stream and !hasSampling(options.sampling_params, "stream")) try w.writeAll(",\"stream\":true");
    if (options.stream and options.compat.supports_usage_in_streaming != false and !hasSampling(options.sampling_params, "stream_options")) {
        try w.writeAll(",\"stream_options\":{\"include_usage\":true}");
    }
    if (options.compat.supports_store == true and !hasSampling(options.sampling_params, "store")) try w.writeAll(",\"store\":false");
    if (options.session_id) |sid| {
        if (!hasSampling(options.sampling_params, "prompt_cache_key")) {
            const key = sid[0..@min(sid.len, 64)];
            try w.writeAll(",\"prompt_cache_key\":");
            try std.json.Stringify.value(key, .{}, w);
        }
        if (options.cache_retention == .long and options.compat.supports_long_cache_retention == true and !hasSampling(options.sampling_params, "prompt_cache_retention"))
            try w.writeAll(",\"prompt_cache_retention\":\"24h\"");
    }
    if (options.max_tokens > 0) {
        const field = options.compat.max_tokens_field orelse metadata.MaxTokensField.max_completion_tokens;
        if (!hasSampling(options.sampling_params, field.jsonName())) {
            try w.writeAll(",\"");
            try w.writeAll(field.jsonName());
            try w.print("\":{d}", .{options.max_tokens});
        }
    }
    try writeThinkingFields(w, options);
    try w.writeAll(",\"messages\":[");
    var first_message = true;
    var last_role: ?[]const u8 = null;
    for (replay_messages, 0..) |msg, msg_index| {
        if (options.compat.requires_assistant_after_tool_result == true and
            last_role != null and std.mem.eql(u8, last_role.?, "tool") and std.mem.eql(u8, msg.role, "user"))
        {
            if (!first_message) try w.writeAll(",");
            first_message = false;
            try w.writeAll("{\"role\":\"assistant\",\"content\":\"I have processed the tool results.\"}");
        }
        if (!first_message) try w.writeAll(",");
        first_message = false;
        try w.writeAll("{\"role\":");
        const role = if (std.mem.eql(u8, msg.role, "system") and options.compat.supports_developer_role == true) "developer" else msg.role;
        try std.json.Stringify.value(role, .{}, w);
        var replay_content_owned: ?[]u8 = null;
        defer if (replay_content_owned) |owned| gpa.free(owned);
        const replay_content: []const u8 = if (std.mem.eql(u8, msg.role, "assistant") and
            msg.thinking != null and msg.thinking.?.len > 0 and options.compat.requires_thinking_as_text == true)
        blk: {
            replay_content_owned = if (msg.content.len > 0)
                try std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ msg.thinking.?, msg.content })
            else
                try gpa.dupe(u8, msg.thinking.?);
            break :blk replay_content_owned.?;
        } else msg.content;
        const add_cache_to_message = cache_anthropic and
            ((first_instruction_index != null and first_instruction_index.? == msg_index) or
                (last_cacheable_conversation_index != null and last_cacheable_conversation_index.? == msg_index));
        if (msg.hasImages()) {
            try w.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(replay_content, .{}, w);
            if (add_cache_to_message) try writeAnthropicCacheControlField(w, cache_long_ttl);
            try w.writeByte('}');
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                try w.writeAll(",{\"type\":\"image_url\",\"image_url\":{\"url\":");
                const data_url = try std.fmt.allocPrint(gpa, "data:{s};base64,{s}", .{ image.mime_type, image.data_b64 });
                defer gpa.free(data_url);
                try std.json.Stringify.value(data_url, .{}, w);
                try w.writeAll("}}");
            }
            try w.writeByte(']');
        } else {
            try w.writeAll(",\"content\":");
            if (add_cache_to_message and replay_content.len > 0) {
                try w.writeAll("[{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(replay_content, .{}, w);
                try writeAnthropicCacheControlField(w, cache_long_ttl);
                try w.writeAll("}]");
            } else {
                try std.json.Stringify.value(replay_content, .{}, w);
            }
        }
        if (msg.tool_call_id) |tid| {
            const normalized_tid = try normalizeToolCallId(gpa, tid);
            defer gpa.free(normalized_tid);
            try w.writeAll(",\"tool_call_id\":");
            try std.json.Stringify.value(normalized_tid, .{}, w);
            if (options.compat.requires_tool_result_name == true and msg.tool_name != null) {
                try w.writeAll(",\"name\":");
                try std.json.Stringify.value(msg.tool_name.?, .{}, w);
            }
        }
        if (msg.tool_calls_json) |tcj| {
            try w.writeAll(",\"tool_calls\":");
            try writeNormalizedToolCalls(gpa, w, tcj, tools_json, options.compat.supports_openai_grammar_tools == true);
            _ = try writeReasoningDetailsFromToolCalls(gpa, w, tcj);
        }
        if (std.mem.eql(u8, msg.role, "assistant") and options.compat.requires_thinking_as_text != true) {
            const needs_reasoning_content = options.compat.requires_reasoning_content_on_assistant_messages == true or options.compat.thinking_format == .deepseek;
            if (needs_reasoning_content) {
                try w.writeAll(",\"reasoning_content\":");
                try std.json.Stringify.value(msg.thinking orelse "", .{}, w);
            }
        }
        try w.writeAll("}");
        if (options.compat.deferred_tools_mode == .kimi and std.mem.eql(u8, msg.role, "tool") and
            (msg_index + 1 == replay_messages.len or !std.mem.eql(u8, replay_messages[msg_index + 1].role, "tool")))
        {
            var group_start = msg_index;
            while (group_start > 0 and std.mem.eql(u8, replay_messages[group_start - 1].role, "tool")) group_start -= 1;
            var names: std.ArrayList([]const u8) = .empty;
            defer names.deinit(gpa);
            var gi = group_start;
            while (gi <= msg_index) : (gi += 1) {
                for (replay_messages[gi].added_tool_names) |name| {
                    if (!nameSelected(names.items, name)) try names.append(gpa, name);
                }
            }
            if (names.items.len > 0) {
                var selected: std.Io.Writer.Allocating = .init(gpa);
                defer selected.deinit();
                try writeToolsConfiguredSelected(gpa, &selected.writer, tools_json, options.compat, replay_messages, false, names.items, false, false);
                if (!std.mem.eql(u8, selected.written(), "[]")) {
                    try w.writeAll(",{\"role\":\"system\",\"tools\":");
                    try w.writeAll(selected.written());
                    try w.writeAll("}");
                }
            }
        }
        last_role = msg.role;
    }
    try w.writeAll("]");
    if (tools_json.len > 2) {
        try w.writeAll(",\"tools\":");
        try writeToolsConfiguredSelected(gpa, w, tools_json, options.compat, replay_messages, options.compat.deferred_tools_mode == .kimi, null, cache_anthropic, cache_long_ttl);
        if (options.stream and options.compat.zai_tool_stream == true and !hasSampling(options.sampling_params, "tool_stream")) {
            try w.writeAll(",\"tool_stream\":true");
        }
    }
    if (options.compat.openrouter_routing) |routing| if (!hasSampling(options.sampling_params, "provider")) {
        try w.writeAll(",\"provider\":");
        try writeOpenRouterRouting(w, routing);
    };
    if (options.compat.vercel_gateway_routing) |routing| if (!hasSampling(options.sampling_params, "providerOptions") and (routing.only != null or routing.order != null)) {
        try w.writeAll(",\"providerOptions\":");
        try writeVercelGatewayRouting(w, routing);
    };
    // Upstream applies samplingParams last. We avoid duplicate named fields
    // above where possible; arbitrary provider-specific keys are preserved.
    for (options.sampling_params) |param| {
        try w.writeAll(",");
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeAll(":");
        try w.writeAll(param.value_json);
    }
    try w.writeAll("}");
    return try body.toOwnedSlice();
}

test "buildRequestBody includes tools and messages" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "user", .content = "hi" },
    };
    const body = try buildRequestBody(gpa, "gpt-4o-mini", &msgs, "[{\"type\":\"function\"}]");
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"model\":\"gpt-4o-mini\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"user\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tools\":") != null);
}

test "OpenAI chat serializes every ordered image attachment" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{
        .role = "user",
        .content = "compare",
        .image_b64 = "AQID",
        .image_mime = "image/png",
        .images = &.{
            .{ .data_b64 = "BAUG", .mime_type = "image/jpeg" },
            .{ .data_b64 = "BwgJ", .mime_type = "image/webp" },
        },
    }};
    const body = try buildRequestBody(gpa, "gpt-4o", &messages, "[]");
    defer gpa.free(body);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "\"type\":\"image_url\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/png;base64,AQID") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/jpeg;base64,BAUG") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/webp;base64,BwgJ") != null);
}

test "buildRequestBodyFull includes reasoning_effort for thinking" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyFull(gpa, "o3-mini", &msgs, "[]", false, .high);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\":\"high\"") != null);
}

test "buildRequestBodyFull omits reasoning_effort when off" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyFull(gpa, "gpt-4o", &msgs, "[]", false, .off);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "reasoning_effort") == null);
}

test "mutating OpenAIClient.model changes subsequent request body model" {
    const gpa = std.testing.allocator;
    var client = OpenAIClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "k",
        .base_url = "https://api.openai.com/v1",
        .model = "old-gpt",
    };
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "x" }};
    const b1 = try buildRequestBody(gpa, client.model, &msgs, "[]");
    defer gpa.free(b1);
    try std.testing.expect(std.mem.indexOf(u8, b1, "old-gpt") != null);
    client.model = "new-gpt";
    const b2 = try buildRequestBody(gpa, client.model, &msgs, "[]");
    defer gpa.free(b2);
    try std.testing.expect(std.mem.indexOf(u8, b2, "new-gpt") != null);
}

test "parseOpenAIResponse extracts tool calls" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"id":"chatcmpl_1","model":"gpt-4o-mini","choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":"hi","tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"path\":\"f\"}"}}]}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    ;
    var resp = try parseOpenAIResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hi", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expectEqualStrings("openai", resp.provider);
    try std.testing.expectEqualStrings("gpt-4o-mini", resp.model);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
    try std.testing.expectEqualStrings("chatcmpl_1", resp.response_id);
    try std.testing.expectEqualStrings("tool_calls", resp.raw_stop_reason);
    try std.testing.expectEqual(@as(u64, 10), resp.usage.input);
    try std.testing.expectEqual(@as(u64, 15), resp.usage.total_tokens);
}

test "buildRequestBodyOpts stream true includes stream flag" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyOpts(gpa, "gpt-4o-mini", &msgs, "[]", true);
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream\":true") != null);
    const body2 = try buildRequestBodyOpts(gpa, "gpt-4o-mini", &msgs, "[]", false);
    defer gpa.free(body2);
    try std.testing.expect(std.mem.indexOf(u8, body2, "\"stream\":true") == null);
}

test "consumeOpenAIStreamBody multi-chunk text and tool fragment via shipped path" {
    const gpa = std.testing.allocator;
    const fixture =
        \\data: {"choices":[{"delta":{"content":"Hel"}}]}
        \\data: {"choices":[{"delta":{"content":"lo "}}]}
        \\data: {"choices":[{"delta":{"content":"world"}}]}
        \\data: {"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"name":"read","arguments":"{\"p\""}}]}}]}
        \\data: {"choices":[{"delta":{"tool_calls":[{"id":"c1","function":{"arguments":":\"a\"}"}}]}}]}
        \\data: [DONE]
        \\
    ;
    const C = struct {
        n: usize = 0,
        fn onDelta(ptr: ?*anyopaque, d: ai.StreamDelta) void {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (d.kind == .text_delta and d.text.len > 0) self.n += 1;
        }
    };
    var c = C{};
    var resp = try consumeOpenAIStreamBody(gpa, fixture, C.onDelta, &c, "gpt-test");
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Hello world", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "a") != null);
    try std.testing.expect(c.n >= 3);
    try std.testing.expectEqualStrings("openai", resp.provider);
    try std.testing.expectEqualStrings("gpt-test", resp.model);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
}

test "LiveSseWriter binds Zig 0.16 backing buffer and releases streamed accumulator" {
    const gpa = std.testing.allocator;
    var live = LiveSseWriter.init(gpa, null, null, true, null);
    live.attachBuffer();
    defer live.deinit();

    try std.testing.expect(live.writer.buffer.len == live.buf.len);
    try live.writer.writeAll(
        "data: {\"choices\":[{\"delta\":{\"content\":\"stream-regression-ok\"}}]}\n\n" ++
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" ++
            "data: [DONE]\n\n",
    );
    try live.flushTrailing();

    var response = try live.acc.finish();
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("stream-regression-ok", response.content);
}

test "configured OpenAI request applies compat and sampling last" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "system", .content = "sys" },
        .{ .role = "tool", .content = "done", .tool_call_id = "call-1", .tool_name = "read" },
    };
    const sampling = [_]metadata.SamplingParam{
        .{ .name = "temperature", .value_json = "0.25" },
        .{ .name = "max_tokens", .value_json = "77" },
    };
    const body = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .stream = true,
        .thinking = .high,
        .max_tokens = 1234,
        .sampling_params = &sampling,
        .compat = .{
            .supports_developer_role = true,
            .supports_usage_in_streaming = true,
            .supports_reasoning_effort = true,
            .max_tokens_field = .max_tokens,
            .requires_tool_result_name = true,
            .thinking_format = .openai,
        },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"developer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stream_options\":{\"include_usage\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\":\"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_tokens\":1234") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"max_tokens\":77") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"temperature\":0.25") != null);
}

test "configured OpenAI request supports qwen thinking toggle" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyConfigured(gpa, "q", &msgs, "[]", .{
        .thinking = .off,
        .compat = .{ .thinking_format = .qwen },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"enable_thinking\":false") != null);
}

test "compat inserts assistant bridge after tool result before user" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "c1" },
        .{ .role = "user", .content = "continue" },
    };
    const body = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .compat = .{ .requires_assistant_after_tool_result = true },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "I have processed the tool results.") != null);
    const tool_pos = std.mem.indexOf(u8, body, "\"role\":\"tool\"").?;
    const bridge_pos = std.mem.indexOf(u8, body, "I have processed the tool results.").?;
    const user_pos = std.mem.lastIndexOf(u8, body, "\"role\":\"user\"").?;
    try std.testing.expect(tool_pos < bridge_pos and bridge_pos < user_pos);
}

test "compat adds empty reasoning content to replayed assistant" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "assistant", .content = "answer" }};
    const body = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .compat = .{ .requires_reasoning_content_on_assistant_messages = true },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_content\":\"\"") != null);
}

test "compat supports qwen chat template string thinking and ant ling fields" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const qwen = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{ .thinking = .high, .compat = .{ .thinking_format = .qwen_chat_template } });
    defer gpa.free(qwen);
    try std.testing.expect(std.mem.indexOf(u8, qwen, "\"chat_template_kwargs\":{\"enable_thinking\":true,\"preserve_thinking\":true}") != null);
    const string_mode = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{ .thinking = .high, .compat = .{ .thinking_format = .string_thinking } });
    defer gpa.free(string_mode);
    try std.testing.expect(std.mem.indexOf(u8, string_mode, "\"thinking\":\"high\"") != null);
    const ant_map = thinking_mod.ThinkingLevelMap{ .high = .{ .mapped = "very_high" } };
    const ant = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{ .thinking = .high, .thinking_level_map = ant_map, .compat = .{ .thinking_format = .ant_ling } });
    defer gpa.free(ant);
    try std.testing.expect(std.mem.indexOf(u8, ant, "\"reasoning\":{\"effort\":\"very_high\"}") != null);
}

test "responses pipe tool ids normalize consistently for completions replay" {
    const gpa = std.testing.allocator;
    const raw_id = "call/$one|fc/+item/with=a-very-very-long-suffix-that-needs-hashing";
    const tool_calls = try std.fmt.allocPrint(gpa, "[{{\"id\":\"{s}\",\"type\":\"function\",\"function\":{{\"name\":\"read\",\"arguments\":\"{{}}\"}}}}]", .{raw_id});
    defer gpa.free(tool_calls);
    const msgs = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .tool_calls_json = tool_calls },
        .{ .role = "tool", .content = "ok", .tool_call_id = raw_id },
    };
    const body = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{});
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const messages = parsed.value.object.get("messages").?.array.items;
    const call_id = messages[0].object.get("tool_calls").?.array.items[0].object.get("id").?.string;
    const result_id = messages[1].object.get("tool_call_id").?.string;
    try std.testing.expectEqualStrings(call_id, result_id);
    try std.testing.expect(call_id.len <= 40);
    try std.testing.expect(std.mem.indexOfScalar(u8, call_id, '|') == null);
}

test "thinking replay supports text and reasoning_content compatibility modes" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "assistant", .content = "answer", .thinking = "plan" }};
    const text_mode = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .compat = .{ .requires_thinking_as_text = true },
    });
    defer gpa.free(text_mode);
    try std.testing.expect(std.mem.indexOf(u8, text_mode, "\"content\":\"plan\\n\\nanswer\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_mode, "reasoning_content") == null);

    const deepseek_mode = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .compat = .{ .thinking_format = .deepseek, .requires_reasoning_content_on_assistant_messages = true },
    });
    defer gpa.free(deepseek_mode);
    try std.testing.expect(std.mem.indexOf(u8, deepseek_mode, "\"reasoning_content\":\"plan\"") != null);
}

test "OpenAI compat strips strict and enables z.ai tool streaming" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const tools =
        \\[{"type":"function","function":{"name":"read","description":"read","parameters":{"type":"object"},"strict":true}}]
    ;
    const body = try buildRequestBodyConfigured(gpa, "zai-model", &msgs, tools, .{
        .stream = true,
        .compat = .{ .supports_strict_mode = false, .zai_tool_stream = true },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tool_stream\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"strict\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"read\"") != null);
}

test "OpenAI stream observer distinguishes missing finish reason" {
    const gpa = std.testing.allocator;
    var without = LiveSseWriter.init(gpa, null, null, true, null);
    without.attachBuffer();
    defer without.deinit();
    try without.feed("data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\n");
    try without.flushTrailing();
    try std.testing.expect(!without.saw_finish_reason);

    var with = LiveSseWriter.init(gpa, null, null, true, null);
    with.attachBuffer();
    defer with.deinit();
    try with.feed("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n");
    try with.flushTrailing();
    try std.testing.expect(with.saw_finish_reason);
    try std.testing.expectEqualStrings("stop", with.stop_reason);
}

test "OpenAI encrypted reasoning detail round-trips with tool call" {
    const gpa = std.testing.allocator;
    const response_json =
        \\{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_7","type":"function","function":{"name":"read","arguments":"{}"}}],"reasoning_details":[{"type":"reasoning.encrypted","id":"call_7","data":"opaque-data"}]}}]}
    ;
    var resp = try parseOpenAIResponse(gpa, response_json);
    defer resp.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].thought_signature, "reasoning.encrypted") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].thought_signature, "opaque-data") != null);

    var call_json: std.Io.Writer.Allocating = .init(gpa);
    defer call_json.deinit();
    try call_json.writer.writeAll("[{\"id\":\"call_7\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"},\"thoughtSignature\":");
    try std.json.Stringify.value(resp.tool_calls[0].thought_signature, .{}, &call_json.writer);
    try call_json.writer.writeAll("}]");
    const messages = [_]ai.ChatMessage{.{ .role = "assistant", .content = "", .tool_calls_json = call_json.written() }};
    const body = try buildRequestBodyConfigured(gpa, "reasoner", &messages, "[]", .{});
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_details\":[{") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "opaque-data") != null);
}

test "OpenAI streaming reasoning detail attaches even when it arrives before tool call" {
    const gpa = std.testing.allocator;
    var live = LiveSseWriter.init(gpa, null, null, true, null);
    live.attachBuffer();
    defer live.deinit();
    try live.feed(
        "data: {\"choices\":[{\"delta\":{\"reasoning_details\":[{\"type\":\"reasoning.encrypted\",\"id\":\"call_stream\",\"data\":\"cipher\"}]}}]}\n\n" ++
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_stream\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]}}]}\n\n" ++
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
    );
    try live.flushTrailing();
    var resp = try live.acc.finish();
    defer resp.deinit(gpa);
    for (resp.tool_calls) |*tool_call| {
        for (live.reasoning_details.items) |detail| {
            if (std.mem.eql(u8, detail.id, tool_call.id)) tool_call.thought_signature = try gpa.dupe(u8, detail.json);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].thought_signature, "cipher") != null);
}

test "OpenAI and Vercel routing preferences use distinct request fields and sampling wins" {
    const gpa = std.testing.allocator;
    var routing_doc = try std.json.parseFromSlice(std.json.Value, gpa,
        \\{"order":["anthropic","amazon-bedrock"],"only":["anthropic"],"ignore":["bad"],"quantizations":["fp16"],"sort":{"by":"price","partition":"model"},"max_price":{"prompt":10,"completion":"20"},"preferred_min_throughput":{"p50":100,"p90":50},"preferred_max_latency":3}
    , .{});
    defer routing_doc.deinit();
    const r = routing_doc.value.object;
    const openrouter_routing = metadata.OpenRouterRouting{
        .allow_fallbacks = true,
        .require_parameters = false,
        .data_collection = "deny",
        .zdr = true,
        .order = r.get("order").?.array.items,
        .only = r.get("only").?.array.items,
        .ignore = r.get("ignore").?.array.items,
        .quantizations = r.get("quantizations").?.array.items,
        .sort = r.get("sort").?,
        .max_price = r.get("max_price").?.object,
        .preferred_min_throughput = r.get("preferred_min_throughput").?,
        .preferred_max_latency = r.get("preferred_max_latency").?,
    };
    const vercel_routing = metadata.VercelGatewayRouting{
        .only = r.get("only").?.array.items,
        .order = r.get("order").?.array.items,
    };
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const body = try buildRequestBodyConfigured(gpa, "router-model", &msgs, "[]", .{
        .compat = .{ .openrouter_routing = openrouter_routing, .vercel_gateway_routing = vercel_routing },
    });
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const provider = parsed.value.object.get("provider").?.object;
    try std.testing.expect(provider.get("allow_fallbacks").?.bool);
    try std.testing.expectEqualStrings("deny", provider.get("data_collection").?.string);
    try std.testing.expectEqualStrings("anthropic", provider.get("only").?.array.items[0].string);
    try std.testing.expectEqualStrings("price", provider.get("sort").?.object.get("by").?.string);
    const gateway = parsed.value.object.get("providerOptions").?.object.get("gateway").?.object;
    try std.testing.expectEqualStrings("anthropic", gateway.get("only").?.array.items[0].string);
    try std.testing.expectEqualStrings("anthropic", gateway.get("order").?.array.items[0].string);

    const overridden = try buildRequestBodyConfigured(gpa, "router-model", &msgs, "[]", .{
        .compat = .{ .openrouter_routing = openrouter_routing, .vercel_gateway_routing = vercel_routing },
        .sampling_params = &.{
            .{ .name = "provider", .value_json = "{\"only\":[\"custom\"]}" },
            .{ .name = "providerOptions", .value_json = "{\"gateway\":{\"only\":[\"custom-gateway\"]}}" },
        },
    });
    defer gpa.free(overridden);
    var parsed_override = try std.json.parseFromSlice(std.json.Value, gpa, overridden, .{});
    defer parsed_override.deinit();
    try std.testing.expectEqualStrings("custom", parsed_override.value.object.get("provider").?.object.get("only").?.array.items[0].string);
    try std.testing.expectEqualStrings("custom-gateway", parsed_override.value.object.get("providerOptions").?.object.get("gateway").?.object.get("only").?.array.items[0].string);
}

test "OpenAI anthropic cache control marks first instruction last conversation and last tool" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system prompt" },
        .{ .role = "user", .content = "first" },
        .{ .role = "assistant", .content = "answer" },
        .{ .role = "user", .content = "last" },
    };
    const tools =
        \\[{"type":"function","function":{"name":"one","description":"first","parameters":{"type":"object"}}},{"type":"function","function":{"name":"two","description":"second","parameters":{"type":"object"}}}]
    ;
    const body = try buildRequestBodyConfigured(gpa, "anthropic/router", &msgs, tools, .{
        .cache_retention = .long,
        .compat = .{ .cache_control_format = .anthropic, .supports_long_cache_retention = true },
    });
    defer gpa.free(body);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);

    var cache_count: usize = 0;
    var ttl_count: usize = 0;
    var rest = body;
    while (std.mem.indexOf(u8, rest, "\"cache_control\"")) |pos| {
        cache_count += 1;
        rest = rest[pos + 1 ..];
    }
    rest = body;
    while (std.mem.indexOf(u8, rest, "\"ttl\":\"1h\"")) |pos| {
        ttl_count += 1;
        rest = rest[pos + 1 ..];
    }
    try std.testing.expectEqual(@as(usize, 3), cache_count);
    try std.testing.expectEqual(@as(usize, 3), ttl_count);

    const root_tools = parsed.value.object.get("tools").?.array.items;
    try std.testing.expect(root_tools[0].object.get("cache_control") == null);
    try std.testing.expect(root_tools[1].object.get("cache_control") != null);
    const messages = parsed.value.object.get("messages").?.array.items;
    try std.testing.expect(messages[0].object.get("content").?.array.items[0].object.get("cache_control") != null);
    try std.testing.expect(messages[messages.len - 1].object.get("content").?.array.items[0].object.get("cache_control") != null);
}

test "OpenAI session affinity headers require explicit enable flag" {
    const gpa = std.testing.allocator;
    var headers: std.ArrayList(std.http.Header) = .empty;
    defer headers.deinit(gpa);

    try appendSessionAffinityHeaders(gpa, &headers, "openrouter", "session-1", .{ .session_affinity_format = .openrouter });
    try std.testing.expectEqual(@as(usize, 0), headers.items.len);

    try appendSessionAffinityHeaders(gpa, &headers, "openrouter", "session-1", .{ .send_session_affinity_headers = true, .session_affinity_format = .openrouter });
    try std.testing.expectEqual(@as(usize, 1), headers.items.len);
    try std.testing.expectEqualStrings("x-session-id", headers.items[0].name);
    try std.testing.expectEqualStrings("session-1", headers.items[0].value);

    headers.clearRetainingCapacity();
    try appendSessionAffinityHeaders(gpa, &headers, "openai", "session-2", .{ .send_session_affinity_headers = true, .session_affinity_format = .openai_nosession });
    try std.testing.expectEqual(@as(usize, 2), headers.items.len);
    try std.testing.expectEqualStrings("x-client-request-id", headers.items[0].name);
    try std.testing.expectEqualStrings("x-session-affinity", headers.items[1].name);
}

test "chat completions cache key clamps and long retention emits 24h" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const sid = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-EXTRA-LONG";
    const body = try buildRequestBodyConfigured(gpa, "gpt", &msgs, "[]", .{
        .session_id = sid,
        .cache_retention = .long,
        .compat = .{ .supports_long_cache_retention = true },
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"prompt_cache_key\":\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-E\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"prompt_cache_retention\":\"24h\"") != null);
}

test "Kimi deferred tools are injected after tool-result group" {
    const gpa = std.testing.allocator;
    const tools =
        \\[{"type":"function","function":{"name":"immediate","parameters":{"type":"object"}}},{"type":"function","function":{"name":"late_tool","parameters":{"type":"object"}}}]
    ;
    const added = [_][]const u8{"late_tool"};
    const msgs = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .tool_calls_json = "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"immediate\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "one", .tool_call_id = "c1", .tool_name = "immediate", .added_tool_names = &added },
        .{ .role = "tool", .content = "two", .tool_call_id = "c2", .tool_name = "immediate" },
        .{ .role = "user", .content = "continue" },
    };
    const body = try buildRequestBodyConfigured(gpa, "kimi", &msgs, tools, .{ .compat = .{ .deferred_tools_mode = .kimi } });
    defer gpa.free(body);
    const root_tools = std.mem.indexOf(u8, body, "\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"immediate\"") orelse return error.TestUnexpectedResult;
    const injected = std.mem.indexOf(u8, body, "{\"role\":\"system\",\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"late_tool\"") orelse return error.TestUnexpectedResult;
    try std.testing.expect(injected < root_tools); // messages serialize before the root tools field
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, body, "\"name\":\"late_tool\""));
    try std.testing.expect(std.mem.indexOf(u8, body[root_tools..], "\"name\":\"late_tool\"") == null);
}

test "chat-template and baseten resolve variables through thinking level map" {
    const gpa = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa,
        \\{"kwargs":{"enabled":{"$var":"thinking.enabled"},"effort":{"$var":"thinking.effort"},"constant":"fixed","skip":{"$var":"thinking.effort","omitWhenOff":true}},"args":{"do_reason":{"$var":"thinking.enabled"},"effort":{"$var":"thinking.effort"}}}
    , .{});
    defer parsed.deinit();
    const kwargs = parsed.value.object.get("kwargs").?.object;
    const args = parsed.value.object.get("args").?.object;
    const map = thinking_mod.ThinkingLevelMap{
        .off = .{ .mapped = "disabled" },
        .high = .{ .mapped = "very_high" },
    };
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};

    const chat = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .thinking_level_map = map,
        .compat = .{ .thinking_format = .chat_template, .chat_template_kwargs = kwargs },
    });
    defer gpa.free(chat);
    try std.testing.expect(std.mem.indexOf(u8, chat, "\"chat_template_kwargs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, chat, "\"enabled\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, chat, "\"effort\":\"very_high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, chat, "\"constant\":\"fixed\"") != null);

    const off_chat = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .off,
        .thinking_level_map = map,
        .compat = .{ .thinking_format = .chat_template, .chat_template_kwargs = kwargs },
    });
    defer gpa.free(off_chat);
    try std.testing.expect(std.mem.indexOf(u8, off_chat, "\"enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, off_chat, "\"effort\":\"disabled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, off_chat, "\"skip\"") == null);

    const baseten = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .thinking_level_map = map,
        .compat = .{ .thinking_format = .baseten, .chat_template_args = args, .supports_reasoning_effort = true },
    });
    defer gpa.free(baseten);
    try std.testing.expect(std.mem.indexOf(u8, baseten, "\"chat_template_args\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, baseten, "\"reasoning_effort\":\"very_high\"") != null);
}

test "static Baseten compatibility emits generated chat template toggle" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const high = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .thinking_level_map = thinking_mod.ThinkingLevelMap{ .off = .{ .mapped = "none" }, .high = .{ .mapped = "high" } },
        .compat = .{ .thinking_format = .baseten, .supports_reasoning_effort = true },
    });
    defer gpa.free(high);
    try std.testing.expect(std.mem.indexOf(u8, high, "\"chat_template_args\":{\"enable_thinking\":true}") != null);
    try std.testing.expect(std.mem.indexOf(u8, high, "\"reasoning_effort\":\"high\"") != null);

    const off = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .off,
        .reasoning = true,
        .compat = .{ .thinking_format = .baseten },
    });
    defer gpa.free(off);
    try std.testing.expect(std.mem.indexOf(u8, off, "\"chat_template_args\":{\"enable_thinking\":false}") != null);
}

test "thinking dialects respect mapped and explicitly unsupported levels" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const mapped = thinking_mod.ThinkingLevelMap{
        .off = .unsupported,
        .high = .{ .mapped = "ultra" },
    };

    const zai = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .thinking_level_map = mapped,
        .compat = .{ .thinking_format = .zai, .supports_reasoning_effort = true },
    });
    defer gpa.free(zai);
    try std.testing.expect(std.mem.indexOf(u8, zai, "\"thinking\":{\"type\":\"enabled\",\"clear_thinking\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, zai, "\"reasoning_effort\":\"ultra\"") != null);

    const deepseek_off = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .off,
        .thinking_level_map = mapped,
        .compat = .{ .thinking_format = .deepseek },
    });
    defer gpa.free(deepseek_off);
    try std.testing.expect(std.mem.indexOf(u8, deepseek_off, "\"thinking\"") == null);

    const openrouter_off = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .off,
        .thinking_level_map = mapped,
        .compat = .{ .thinking_format = .openrouter },
    });
    defer gpa.free(openrouter_off);
    try std.testing.expect(std.mem.indexOf(u8, openrouter_off, "\"reasoning\"") == null);

    const together = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .thinking_level_map = mapped,
        .compat = .{ .thinking_format = .together, .supports_reasoning_effort = true },
    });
    defer gpa.free(together);
    try std.testing.expect(std.mem.indexOf(u8, together, "\"reasoning_effort\":\"ultra\"") != null);

    const ant_without_map = try buildRequestBodyConfigured(gpa, "m", &msgs, "[]", .{
        .thinking = .high,
        .compat = .{ .thinking_format = .ant_ling },
    });
    defer gpa.free(ant_without_map);
    try std.testing.expect(std.mem.indexOf(u8, ant_without_map, "\"reasoning\"") == null);
}
