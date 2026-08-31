//! Google Generative Language API (generateContent) — text responses.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const metadata = @import("request_metadata.zig");
const providers = @import("providers.zig");
const cost_mod = @import("cost.zig");

pub const AuthMode = enum { query_key, bearer };

pub const BearerRefreshFn = *const fn (ctx: *anyopaque, client: *GoogleClient, now_unix: i64) anyerror!void;
pub const TokenRefreshFn = *const fn (ctx: *anyopaque, client: *GoogleClient, now_ms: i64) anyerror!void;

pub const GoogleClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    /// Process/provider proxy environment.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback.
    proxy_url: ?[]const u8 = null,
    /// Provider-internal request retry settings.
    provider_retry: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    api_key: []const u8,
    auth_mode: AuthMode = .query_key,
    base_url: []const u8,
    model: []const u8,
    provider_id: []const u8 = "google",
    api_id: []const u8 = "google-generative-ai",
    custom_headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    thinking: ai.ThinkingLevel = .off,
    thinking_level_map: ?@import("thinking.zig").ThinkingLevelMap = null,
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    model_cost: providers.ModelCost = .{},
    abort_flag: ?*bool = null,
    /// Provider-defined OAuth refresh that may update either a query API key
    /// or bearer token before every Google request.
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,
    bearer_refresh_ctx: ?*anyopaque = null,
    bearer_refresh_fn: ?BearerRefreshFn = null,
    bearer_expiration_unix: ?i64 = null,
    quota_project_id: ?[]const u8 = null,

    pub fn client(self: *GoogleClient) ai.ModelClient {
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
        const self: *GoogleClient = @ptrCast(@alignCast(ptr));
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
        const self: *GoogleClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, true, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn request(
        self: *GoogleClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        if (self.token_refresh_fn) |refresh| {
            const now_ms = Io.Clock.real.now(self.io).toMilliseconds();
            const should_refresh = self.api_key.len == 0 or (if (self.token_expiration_ms) |expires| expires <= now_ms + 60_000 else true);
            if (should_refresh) try refresh(self.token_refresh_ctx orelse return error.InvalidTokenRefreshContext, self, now_ms);
        }
        if (self.auth_mode == .bearer and self.bearer_refresh_fn != null) {
            const now_unix = Io.Clock.real.now(self.io).toSeconds();
            const should_refresh = self.api_key.len == 0 or (if (self.bearer_expiration_unix) |expires| expires <= now_unix + 60 else true);
            if (should_refresh) try self.bearer_refresh_fn.?(self.bearer_refresh_ctx orelse return error.InvalidBearerRefreshContext, self, now_unix);
        }
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const payload = try buildRequestBodyConfigured(gpa, effective_messages, tools_json, self.provider_id, self.model, .{
            .max_tokens = effective_max_tokens,
            .thinking = self.thinking,
            .thinking_level_map = self.thinking_level_map,
            .sampling_params = self.sampling_params,
            .tool_choice = request_options.tool_choice,
        });
        defer gpa.free(payload);

        const url = try buildRequestUrl(gpa, self.base_url, self.model, self.api_key, self.auth_mode, streaming);
        defer gpa.free(url);

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

        if (streaming) {
            return self.requestStreaming(gpa, payload, url, on_delta, delta_ctx);
        }

        var response_body: std.Io.Writer.Allocating = .init(gpa);
        defer response_body.deinit();

        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHttpHeader(gpa, &headers, "content-type", "application/json");
        try putHttpHeader(gpa, &headers, "User-Agent", ai.pi_user_agent.value);
        const bearer = if (self.auth_mode == .bearer) try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key}) else null;
        defer if (bearer) |value| gpa.free(value);
        if (bearer) |value| try putHttpHeader(gpa, &headers, "authorization", value);
        if (self.quota_project_id) |quota| try putHttpHeader(gpa, &headers, "x-goog-user-project", quota);
        for (self.custom_headers) |header| try putHttpHeader(gpa, &headers, header.name, header.value);

        var retry_index: usize = 0;
        while (true) {
            const fetch_result = http_fetch.fetchControlled(&http_client, .{
                .location = .{ .url = url },
                .method = .POST,
                .payload = payload,
                .keep_alive = false,
                .extra_headers = headers.items,
                .response_writer = &response_body.writer,
            }, self.provider_retry.timeout_ms, self.abort_flag) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                response_body.deinit();
                response_body = .init(gpa);
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            if (fetch_result.status >= 200 and fetch_result.status < 300) break;
            if (retry_index < self.provider_retry.max_retries and retry_mod.isRetryableProviderResponse(fetch_result.provider)) {
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, fetch_result.provider.retry_after_ms);
                retry_index += 1;
                response_body.deinit();
                response_body = .init(gpa);
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            }
            const response_json = try response_body.toOwnedSlice();
            defer gpa.free(response_json);
            const snippet = if (response_json.len > 800) response_json[0..800] else response_json;
            const content = try std.fmt.allocPrint(gpa, "HTTP {d} from google: {s}", .{ fetch_result.status, snippet });
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

        const response_json = try response_body.toOwnedSlice();
        defer gpa.free(response_json);

        var resp = try parseGoogleResponse(gpa, response_json);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, self.provider_id);
        if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
        _ = cost_mod.calculate(self.model_cost, &resp.usage);
        try resp.ensureStopReason(gpa);
        return resp;
    }

    fn requestStreaming(
        self: *GoogleClient,
        gpa: std.mem.Allocator,
        payload: []const u8,
        url: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        var retry_index: usize = 0;
        while (true) {
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
            try putHttpHeader(gpa, &headers, "accept", "text/event-stream");
            try putHttpHeader(gpa, &headers, "User-Agent", ai.pi_user_agent.value);
            const bearer = if (self.auth_mode == .bearer) try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key}) else null;
            defer if (bearer) |value| gpa.free(value);
            if (bearer) |value| try putHttpHeader(gpa, &headers, "authorization", value);
            if (self.quota_project_id) |quota| try putHttpHeader(gpa, &headers, "x-goog-user-project", quota);
            for (self.custom_headers) |header| try putHttpHeader(gpa, &headers, header.name, header.value);

            var live = GoogleLiveSseWriter.init(gpa, on_delta, delta_ctx, self.abort_flag);
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
                if (self.abort_flag) |flag| {
                    if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                }
                if (err == error.ProviderStreamInterruptedAfterOutput or retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            const status = fetch_result.status;
            try live.flushTrailing();
            if (live.aborted) return abortedResponse(gpa, self.provider_id, self.model);
            if (status < 200 or status >= 300) {
                if (retry_index < self.provider_retry.max_retries and retry_mod.isRetryableProviderResponse(fetch_result.provider)) {
                    const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, fetch_result.provider.retry_after_ms);
                    retry_index += 1;
                    if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                    continue;
                }
                const body = try live.body.toOwnedSlice(gpa);
                defer gpa.free(body);
                const snippet = if (body.len > 800) body[0..800] else body;
                return .{
                    .content = try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s}", .{ status, self.provider_id, snippet }),
                    .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                    .provider = try gpa.dupe(u8, self.provider_id),
                    .model = try gpa.dupe(u8, self.model),
                    .stop_reason = try gpa.dupe(u8, "error"),
                    .provider_status = fetch_result.provider.status,
                    .provider_retry_after_ms = fetch_result.provider.retry_after_ms,
                    .provider_should_retry = fetch_result.provider.should_retry,
                };
            }
            var resp = try live.finish(gpa);
            resp.provider = try gpa.dupe(u8, self.provider_id);
            resp.model = try gpa.dupe(u8, self.model);
            _ = cost_mod.calculate(self.model_cost, &resp.usage);
            try resp.ensureStopReason(gpa);
            return resp;
        }
    }
};

pub fn buildRequestUrl(
    gpa: std.mem.Allocator,
    base_url: []const u8,
    model: []const u8,
    api_key: []const u8,
    auth_mode: AuthMode,
    streaming: bool,
) ![]u8 {
    if (auth_mode == .query_key) {
        return if (streaming)
            std.fmt.allocPrint(gpa, "{s}/models/{s}:streamGenerateContent?alt=sse&key={s}", .{ base_url, model, api_key })
        else
            std.fmt.allocPrint(gpa, "{s}/models/{s}:generateContent?key={s}", .{ base_url, model, api_key });
    }
    return if (streaming)
        std.fmt.allocPrint(gpa, "{s}/models/{s}:streamGenerateContent?alt=sse", .{ base_url, model })
    else
        std.fmt.allocPrint(gpa, "{s}/models/{s}:generateContent", .{ base_url, model });
}

pub fn requiresToolCallId(model_id: []const u8) bool {
    if (std.mem.startsWith(u8, model_id, "claude-") or std.mem.startsWith(u8, model_id, "gpt-oss-")) return true;
    var id = model_id;
    if (std.ascii.startsWithIgnoreCase(id, "gemini-live-")) {
        id = id["gemini-live-".len..];
    } else if (std.ascii.startsWithIgnoreCase(id, "gemini-")) {
        id = id["gemini-".len..];
    } else return false;
    var end: usize = 0;
    while (end < id.len and std.ascii.isDigit(id[end])) : (end += 1) {}
    if (end == 0) return false;
    const major = std.fmt.parseInt(u32, id[0..end], 10) catch return false;
    return major >= 3;
}

pub fn supportsMultimodalFunctionResponse(model_id: []const u8) bool {
    var id = model_id;
    if (std.ascii.startsWithIgnoreCase(id, "gemini-live-")) {
        id = id["gemini-live-".len..];
    } else if (std.ascii.startsWithIgnoreCase(id, "gemini-")) {
        id = id["gemini-".len..];
    } else return true;
    var end: usize = 0;
    while (end < id.len and std.ascii.isDigit(id[end])) : (end += 1) {}
    if (end == 0) return true;
    const major = std.fmt.parseInt(u32, id[0..end], 10) catch return true;
    return major >= 3;
}

fn normalizedGoogleToolId(gpa: std.mem.Allocator, id: []const u8) ![]u8 {
    const n = @min(id.len, 64);
    const out = try gpa.alloc(u8, n);
    for (id[0..n], 0..) |c, i| {
        out[i] = if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-') c else '_';
    }
    return out;
}

fn writeGoogleFunctionResponsePart(gpa: std.mem.Allocator, w: *std.Io.Writer, msg: ai.ChatMessage, model_id: []const u8, include_image: bool) !void {
    const has_image = msg.hasImages();
    const response_text = if (msg.content.len > 0) msg.content else if (has_image) "(see attached image)" else "";
    try w.writeAll("{\"functionResponse\":{\"name\":");
    try std.json.Stringify.value(msg.tool_name orelse msg.tool_call_id orelse "tool", .{}, w);
    if (requiresToolCallId(model_id)) {
        if (msg.tool_call_id) |raw_id| {
            const normalized = try normalizedGoogleToolId(gpa, raw_id);
            defer gpa.free(normalized);
            try w.writeAll(",\"id\":");
            try std.json.Stringify.value(normalized, .{}, w);
        }
    }
    try w.writeAll(",\"response\":{");
    try std.json.Stringify.value(if (msg.tool_is_error) "error" else "output", .{}, w);
    try w.writeAll(":");
    try std.json.Stringify.value(response_text, .{}, w);
    try w.writeAll("}");
    if (include_image and has_image) {
        try w.writeAll(",\"parts\":[");
        var image_index: usize = 0;
        while (image_index < msg.imageCount()) : (image_index += 1) {
            if (image_index > 0) try w.writeByte(',');
            const image = msg.imageAt(image_index).?;
            try w.writeAll("{\"inlineData\":{\"mimeType\":");
            try std.json.Stringify.value(image.mime_type, .{}, w);
            try w.writeAll(",\"data\":");
            try std.json.Stringify.value(image.data_b64, .{}, w);
            try w.writeAll("}}");
        }
        try w.writeByte(']');
    }
    try w.writeAll("}}");
}

fn writeGoogleLegacyToolImage(w: *std.Io.Writer, msg: ai.ChatMessage) !void {
    try w.writeAll("{\"role\":\"user\",\"parts\":[{\"text\":\"Tool result image:\"}");
    var image_index: usize = 0;
    while (image_index < msg.imageCount()) : (image_index += 1) {
        const image = msg.imageAt(image_index).?;
        try w.writeAll(",{\"inlineData\":{\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, w);
        try w.writeAll(",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, w);
        try w.writeAll("}}");
    }
    try w.writeAll("]}");
}

pub const GoogleRequestOptions = struct {
    max_tokens: u64 = 0,
    thinking: ai.ThinkingLevel = .off,
    sampling_params: []const metadata.SamplingParam = &.{},
    thinking_level_map: ?@import("thinking.zig").ThinkingLevelMap = null,
    tool_choice: ?ai.ToolChoice = null,
};

pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    provider_id: []const u8,
    model_id: []const u8,
) ![]u8 {
    return buildRequestBodyConfigured(gpa, messages, tools_json, provider_id, model_id, .{});
}

pub fn buildRequestBodyConfigured(
    gpa: std.mem.Allocator,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    provider_id: []const u8,
    model_id: []const u8,
    options: GoogleRequestOptions,
) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    const replay_messages = repaired.messages.items;

    var system_text: ?[]const u8 = null;
    for (replay_messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system")) {
            system_text = msg.content;
            break;
        }
    }

    try w.writeAll("{");
    if (system_text) |sys| {
        try w.writeAll("\"systemInstruction\":{\"parts\":[{\"text\":");
        try std.json.Stringify.value(sys, .{}, w);
        try w.writeAll("}]},");
    }
    try w.writeAll("\"contents\":[");
    var first_message = true;
    var msg_index: usize = 0;
    while (msg_index < replay_messages.len) : (msg_index += 1) {
        const msg = replay_messages[msg_index];
        if (std.mem.eql(u8, msg.role, "system")) continue;

        if (std.mem.eql(u8, msg.role, "tool")) {
            var j = msg_index;
            var group_open = false;
            var first_response = true;
            while (j < replay_messages.len and std.mem.eql(u8, replay_messages[j].role, "tool")) : (j += 1) {
                const tool_msg = replay_messages[j];
                const legacy_image = tool_msg.hasImages() and !supportsMultimodalFunctionResponse(model_id);
                if (!group_open) {
                    if (!first_message) try w.writeAll(",");
                    first_message = false;
                    try w.writeAll("{\"role\":\"user\",\"parts\":[");
                    group_open = true;
                    first_response = true;
                }
                if (!first_response) try w.writeAll(",");
                first_response = false;
                try writeGoogleFunctionResponsePart(gpa, w, tool_msg, model_id, !legacy_image);
                if (legacy_image) {
                    try w.writeAll("]}");
                    group_open = false;
                    try w.writeAll(",");
                    try writeGoogleLegacyToolImage(w, tool_msg);
                    first_message = false;
                }
            }
            if (group_open) try w.writeAll("]}");
            if (j > 0) msg_index = j - 1;
            continue;
        }

        if (!first_message) try w.writeAll(",");
        first_message = false;
        const is_assistant = std.mem.eql(u8, msg.role, "assistant");
        const role = if (is_assistant) "model" else "user";
        const same_identity = is_assistant and msg.provider != null and msg.model != null and
            std.ascii.eqlIgnoreCase(msg.provider.?, provider_id) and std.mem.eql(u8, msg.model.?, model_id);

        try w.writeAll("{\"role\":");
        try std.json.Stringify.value(role, .{}, w);
        try w.writeAll(",\"parts\":[");
        var first_part = true;

        if (is_assistant) {
            if (msg.thinking) |thought| {
                if (thought.len > 0) {
                    try writeGoogleTextPart(w, thought, same_identity, if (same_identity) msg.thinking_signature else null, &first_part);
                }
            }
        }
        if (msg.content.len > 0 or (!is_assistant and !msg.hasImages() and msg.thinking == null)) {
            try writeGoogleTextPart(w, msg.content, false, null, &first_part);
        }
        if (!is_assistant) {
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                if (!first_part) try w.writeByte(',');
                first_part = false;
                try w.writeAll("{\"inlineData\":{\"mimeType\":");
                try std.json.Stringify.value(image.mime_type, .{}, w);
                try w.writeAll(",\"data\":");
                try std.json.Stringify.value(image.data_b64, .{}, w);
                try w.writeAll("}}");
            }
        }

        if (is_assistant) {
            if (msg.tool_calls_json) |calls| {
                try appendGoogleFunctionCalls(gpa, w, calls, same_identity, requiresToolCallId(model_id), &first_part);
            }
        }
        try w.writeAll("]}");
    }
    try w.writeAll("]");
    if (tools_json.len > 2) {
        if (try convertToolsToGoogle(gpa, tools_json)) |decls| {
            defer gpa.free(decls);
            try w.writeAll(",\"tools\":[{\"functionDeclarations\":");
            try w.writeAll(decls);
            try w.writeAll("}]");
        }
        if (options.tool_choice) |choice| {
            try w.writeAll(",\"toolConfig\":{\"functionCallingConfig\":{\"mode\":");
            try std.json.Stringify.value(if (choice == .none) "NONE" else "AUTO", .{}, w);
            try w.writeAll("}}");
        }
    }
    if (options.max_tokens > 0 or options.thinking != .off or options.sampling_params.len > 0) {
        try w.writeAll(",\"generationConfig\":{");
        var first_config = true;
        if (options.max_tokens > 0) {
            try w.writeAll("\"maxOutputTokens\":");
            try w.print("{d}", .{options.max_tokens});
            first_config = false;
        }
        if (options.thinking != .off) {
            if (!first_config) try w.writeAll(",");
            first_config = false;
            try w.writeAll("\"thinkingConfig\":{\"includeThoughts\":true,\"thinkingLevel\":");
            try std.json.Stringify.value(googleThinkingLevelMapped(options.thinking, options.thinking_level_map), .{}, w);
            try w.writeAll("}");
        }
        for (options.sampling_params) |param| {
            if (!first_config) try w.writeAll(",");
            first_config = false;
            try std.json.Stringify.value(param.name, .{}, w);
            try w.writeAll(":");
            try w.writeAll(param.value_json);
        }
        try w.writeAll("}");
    }
    try w.writeAll("}");
    return try body.toOwnedSlice();
}

fn googleThinkingLevel(level: ai.ThinkingLevel) []const u8 {
    return switch (level) {
        .off, .minimal => "MINIMAL",
        .low => "LOW",
        .medium => "MEDIUM",
        .high, .xhigh, .max => "HIGH",
    };
}

fn googleThinkingLevelMapped(level: ai.ThinkingLevel, map: ?@import("thinking.zig").ThinkingLevelMap) []const u8 {
    if (map) |mapping| switch (mapping.entry(level)) {
        .mapped => |value| return value,
        else => {},
    };
    return googleThinkingLevel(level);
}

fn isValidGoogleThoughtSignature(signature: []const u8) bool {
    if (signature.len == 0 or signature.len % 4 != 0) return false;
    var padding = false;
    var padding_count: usize = 0;
    for (signature) |c| {
        if (c == '=') {
            padding = true;
            padding_count += 1;
            if (padding_count > 2) return false;
            continue;
        }
        if (padding) return false;
        if (!(std.ascii.isAlphanumeric(c) or c == '+' or c == '/')) return false;
    }
    return true;
}

fn writeGoogleTextPart(w: anytype, text: []const u8, thought: bool, signature: ?[]const u8, first_part: *bool) !void {
    if (!first_part.*) try w.writeAll(",");
    first_part.* = false;
    try w.writeAll("{\"text\":");
    try std.json.Stringify.value(text, .{}, w);
    if (thought) try w.writeAll(",\"thought\":true");
    if (signature) |sig| {
        if (isValidGoogleThoughtSignature(sig)) {
            try w.writeAll(",\"thoughtSignature\":");
            try std.json.Stringify.value(sig, .{}, w);
        }
    }
    try w.writeAll("}");
}

fn abortedResponse(gpa: std.mem.Allocator, provider_id: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "aborted"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider_id),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "aborted"),
    };
}

const GoogleLiveSseWriter = struct {
    gpa: std.mem.Allocator,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
    line: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    text: std.ArrayList(u8) = .empty,
    thinking: std.ArrayList(u8) = .empty,
    thinking_signature: std.ArrayList(u8) = .empty,
    tool_calls: std.ArrayList(ai.ToolCall) = .empty,
    usage: ai.Usage = .{},
    stop_reason: []const u8 = "",
    response_id: []u8 = &.{},
    raw_stop_reason: []u8 = &.{},
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    abort_flag: ?*bool,
    aborted: bool = false,
    generated_call_index: usize = 0,

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };

    fn init(gpa: std.mem.Allocator, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, abort_flag: ?*bool) GoogleLiveSseWriter {
        return .{
            .gpa = gpa,
            .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .abort_flag = abort_flag,
        };
    }

    fn attachBuffer(self: *GoogleLiveSseWriter) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }

    fn deinit(self: *GoogleLiveSseWriter) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.text.deinit(self.gpa);
        self.thinking.deinit(self.gpa);
        self.thinking_signature.deinit(self.gpa);
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
        for (self.tool_calls.items) |*tc| tc.deinit(self.gpa);
        self.tool_calls.deinit(self.gpa);
        self.* = undefined;
    }

    fn emit(self: *GoogleLiveSseWriter, delta: ai.StreamDelta) void {
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
    }

    fn flushTrailing(self: *GoogleLiveSseWriter) !void {
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if (self.line.items.len > 0) {
            try self.handleLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }

    fn feed(self: *GoogleLiveSseWriter, chunk: []const u8) !void {
        if (self.abort_flag) |flag| {
            if (@atomicLoad(bool, flag, .acquire)) {
                self.aborted = true;
                return error.WriteFailed;
            }
        }
        try self.body.appendSlice(self.gpa, chunk);
        for (chunk) |c| {
            if (c == '\n') {
                try self.handleLine(self.line.items);
                self.line.clearRetainingCapacity();
            } else if (c != '\r') {
                try self.line.append(self.gpa, c);
            }
        }
    }

    fn handleLine(self: *GoogleLiveSseWriter, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "data:")) return;
        const data = std.mem.trim(u8, trimmed["data:".len..], " \t");
        if (data.len == 0 or std.mem.eql(u8, data, "[DONE]")) return;
        try self.observeData(data);
    }

    fn observeData(self: *GoogleLiveSseWriter, data: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, data, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        if (self.response_id.len == 0) if (parsed.value.object.get("responseId")) |id| if (id == .string and id.string.len > 0) {
            self.response_id = try self.gpa.dupe(u8, id.string);
        };
        if (parsed.value.object.get("usageMetadata")) |raw_usage| self.usage = parseGoogleUsage(raw_usage);
        const candidates = parsed.value.object.get("candidates") orelse return;
        if (candidates != .array or candidates.array.items.len == 0) return;
        const candidate = candidates.array.items[0];
        if (candidate != .object) return;
        if (candidate.object.get("finishReason")) |finish_value| {
            if (finish_value == .string and finish_value.string.len > 0) {
                self.stop_reason = mapGoogleStopReason(finish_value.string);
                if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
                self.raw_stop_reason = try self.gpa.dupe(u8, finish_value.string);
            }
        }
        const content = candidate.object.get("content") orelse return;
        if (content != .object) return;
        const parts = content.object.get("parts") orelse return;
        if (parts != .array) return;
        for (parts.array.items) |part| {
            if (part != .object) continue;
            if (part.object.get("text")) |text_value| {
                if (text_value == .string) {
                    const is_thought = if (part.object.get("thought")) |v| v == .bool and v.bool else false;
                    if (is_thought) {
                        try self.thinking.appendSlice(self.gpa, text_value.string);
                        if (self.thinking_signature.items.len == 0) {
                            if (part.object.get("thoughtSignature")) |sig| {
                                if (sig == .string and sig.string.len > 0) try self.thinking_signature.appendSlice(self.gpa, sig.string);
                            }
                        }
                        self.emit(.{ .kind = .thinking_delta, .thinking = text_value.string });
                    } else {
                        try self.text.appendSlice(self.gpa, text_value.string);
                        self.emit(.{ .kind = .text_delta, .text = text_value.string });
                    }
                }
            }
            if (part.object.get("functionCall")) |fc| {
                if (fc != .object) continue;
                const name = if (fc.object.get("name")) |name_value| if (name_value == .string) name_value.string else "" else "";
                var args_writer: std.Io.Writer.Allocating = .init(self.gpa);
                defer args_writer.deinit();
                if (fc.object.get("args")) |args| try std.json.Stringify.value(args, .{}, &args_writer.writer) else try args_writer.writer.writeAll("{}");
                const id = try self.uniqueToolId(fc, name);
                errdefer self.gpa.free(id);
                const signature = if (part.object.get("thoughtSignature")) |sig| if (sig == .string and sig.string.len > 0) try self.gpa.dupe(u8, sig.string) else "" else "";
                errdefer if (signature.len > 0) self.gpa.free(signature);
                const args = try args_writer.toOwnedSlice();
                errdefer self.gpa.free(args);
                const owned_name = try self.gpa.dupe(u8, name);
                errdefer self.gpa.free(owned_name);
                try self.tool_calls.append(self.gpa, .{ .id = id, .name = owned_name, .arguments = args, .thought_signature = signature });
                self.emit(.{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = owned_name, .tool_arguments = args });
            }
        }
    }

    fn uniqueToolId(self: *GoogleLiveSseWriter, fc: std.json.Value, name: []const u8) ![]u8 {
        if (fc == .object) {
            if (fc.object.get("id")) |id_value| {
                if (id_value == .string and id_value.string.len > 0) {
                    var duplicate = false;
                    for (self.tool_calls.items) |tc| if (std.mem.eql(u8, tc.id, id_value.string)) {
                        duplicate = true;
                        break;
                    };
                    if (!duplicate) return self.gpa.dupe(u8, id_value.string);
                }
            }
        }
        self.generated_call_index += 1;
        return std.fmt.allocPrint(self.gpa, "{s}_{d}", .{ if (name.len > 0) name else "call", self.generated_call_index });
    }

    fn finish(self: *GoogleLiveSseWriter, gpa: std.mem.Allocator) !ai.ModelResponse {
        var calls = try gpa.alloc(ai.ToolCall, self.tool_calls.items.len);
        errdefer gpa.free(calls);
        var copied: usize = 0;
        errdefer for (calls[0..copied]) |*tc| tc.deinit(gpa);
        for (self.tool_calls.items, 0..) |tc, i| {
            calls[i] = .{
                .id = try gpa.dupe(u8, tc.id),
                .name = try gpa.dupe(u8, tc.name),
                .arguments = try gpa.dupe(u8, tc.arguments),
                .thought_signature = if (tc.thought_signature.len > 0) try gpa.dupe(u8, tc.thought_signature) else "",
            };
            copied += 1;
        }
        const stop = if (self.stop_reason.len > 0 and !std.mem.eql(u8, self.stop_reason, "stop"))
            self.stop_reason
        else if (calls.len > 0)
            "toolUse"
        else if (self.stop_reason.len > 0)
            self.stop_reason
        else
            "stop";
        return .{
            .content = try gpa.dupe(u8, self.text.items),
            .thinking = if (self.thinking.items.len > 0) try gpa.dupe(u8, self.thinking.items) else "",
            .thinking_signature = if (self.thinking_signature.items.len > 0) try gpa.dupe(u8, self.thinking_signature.items) else "",
            .tool_calls = calls,
            .response_id = if (self.response_id.len > 0) try gpa.dupe(u8, self.response_id) else "",
            .raw_stop_reason = if (self.raw_stop_reason.len > 0) try gpa.dupe(u8, self.raw_stop_reason) else "",
            .stop_reason = try gpa.dupe(u8, stop),
            .usage = self.usage,
        };
    }

    fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *GoogleLiveSseWriter = @fieldParentPtr("writer", writer);
        if (writer.end > 0) {
            self.feed(writer.buffer[0..writer.end]) catch return error.WriteFailed;
            writer.end = 0;
        }
        if (data.len == 0) return 0;
        var total: usize = 0;
        for (data[0 .. data.len - 1]) |part| {
            self.feed(part) catch return error.WriteFailed;
            total += part.len;
        }
        const pattern = data[data.len - 1];
        var remaining = splat;
        while (remaining > 0) : (remaining -= 1) {
            self.feed(pattern) catch return error.WriteFailed;
            total += pattern.len;
        }
        return total;
    }
};

fn mapGoogleStopReason(raw: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(raw, "MAX_TOKENS")) return "length";
    if (std.ascii.eqlIgnoreCase(raw, "STOP")) return "stop";
    if (std.ascii.eqlIgnoreCase(raw, "SAFETY") or std.ascii.eqlIgnoreCase(raw, "RECITATION") or std.ascii.eqlIgnoreCase(raw, "BLOCKLIST")) return "error";
    return "stop";
}

pub fn consumeGoogleStreamBody(gpa: std.mem.Allocator, sse_body: []const u8, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque) !ai.ModelResponse {
    var live = GoogleLiveSseWriter.init(gpa, on_delta, delta_ctx, null);
    live.attachBuffer();
    defer live.deinit();
    try live.feed(sse_body);
    try live.flushTrailing();
    return live.finish(gpa);
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

fn appendGoogleFunctionCalls(gpa: std.mem.Allocator, w: anytype, tool_calls_json: []const u8, preserve_signatures: bool, include_ids: bool, first_part: *bool) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tool_calls_json, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id = item.object.get("id");
        const fn_obj = item.object.get("function");
        if (fn_obj == null or fn_obj.? != .object) continue;
        const name = fn_obj.?.object.get("name");
        const args = fn_obj.?.object.get("arguments");
        if (name == null or name.? != .string) continue;
        if (!first_part.*) try w.writeAll(",");
        first_part.* = false;
        try w.writeAll("{\"functionCall\":{\"name\":");
        try std.json.Stringify.value(name.?.string, .{}, w);
        try w.writeAll(",\"args\":");
        if (args != null and args.? == .string) {
            // arguments is JSON string — embed raw
            try w.writeAll(args.?.string);
        } else {
            try w.writeAll("{}");
        }
        if (include_ids and id != null and id.? == .string) {
            const normalized = try normalizedGoogleToolId(gpa, id.?.string);
            defer gpa.free(normalized);
            try w.writeAll(",\"id\":");
            try std.json.Stringify.value(normalized, .{}, w);
        }
        try w.writeAll("}");
        if (preserve_signatures) {
            if (item.object.get("thoughtSignature")) |sig| {
                if (sig == .string and isValidGoogleThoughtSignature(sig.string)) {
                    try w.writeAll(",\"thoughtSignature\":");
                    try std.json.Stringify.value(sig.string, .{}, w);
                }
            }
        }
        try w.writeAll("}");
    }
}

/// Convert OpenAI tools JSON to Google functionDeclarations array JSON.
pub fn convertToolsToGoogle(gpa: std.mem.Allocator, tools_json: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .array) return null;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_obj = item.object.get("function") orelse continue;
        if (fn_obj != .object) continue;
        const name = fn_obj.object.get("name") orelse continue;
        if (name != .string) continue;
        if (!first) try out.writer.writeAll(",");
        first = false;
        try out.writer.writeAll("{\"name\":");
        try std.json.Stringify.value(name.string, .{}, &out.writer);
        if (fn_obj.object.get("description")) |d| {
            if (d == .string) {
                try out.writer.writeAll(",\"description\":");
                try std.json.Stringify.value(d.string, .{}, &out.writer);
            }
        }
        if (fn_obj.object.get("parameters")) |p| {
            try out.writer.writeAll(",\"parameters\":");
            try std.json.Stringify.value(p, .{}, &out.writer);
        }
        try out.writer.writeAll("}");
    }
    try out.writer.writeAll("]");
    if (first) {
        out.deinit();
        return null;
    }
    return try out.toOwnedSlice();
}

fn googleU64(value: ?std.json.Value) u64 {
    const v = value orelse return 0;
    if (v != .integer or v.integer < 0) return 0;
    return @intCast(v.integer);
}

pub fn parseGoogleUsage(value: std.json.Value) ai.Usage {
    if (value != .object) return .{};
    const prompt = googleU64(value.object.get("promptTokenCount"));
    const cache_read = googleU64(value.object.get("cachedContentTokenCount"));
    const candidates = googleU64(value.object.get("candidatesTokenCount"));
    const thoughts = googleU64(value.object.get("thoughtsTokenCount"));
    var usage: ai.Usage = .{
        .input = prompt -| @min(prompt, cache_read),
        .output = candidates + thoughts,
        .cache_read = cache_read,
        .reasoning = thoughts,
        .total_tokens = googleU64(value.object.get("totalTokenCount")),
    };
    if (usage.total_tokens == 0) usage.normalizeTotal();
    return usage;
}

pub fn parseGoogleResponse(gpa: std.mem.Allocator, response_json: []const u8) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;

    const candidates = parsed.value.object.get("candidates") orelse return error.InvalidResponse;
    if (candidates != .array or candidates.array.items.len == 0) return error.InvalidResponse;
    const first = candidates.array.items[0];
    if (first != .object) return error.InvalidResponse;
    const content = first.object.get("content") orelse return error.InvalidResponse;
    if (content != .object) return error.InvalidResponse;
    const parts = content.object.get("parts") orelse return error.InvalidResponse;
    if (parts != .array) return error.InvalidResponse;

    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(gpa);
    var thinking: std.ArrayList(u8) = .empty;
    errdefer thinking.deinit(gpa);
    var thinking_signature: ?[]u8 = null;
    errdefer if (thinking_signature) |sig| gpa.free(sig);
    var tcs: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (tcs.items) |*tc| tc.deinit(gpa);
        tcs.deinit(gpa);
    }
    var call_i: usize = 0;
    for (parts.array.items) |part| {
        if (part != .object) continue;
        if (part.object.get("text")) |t| {
            if (t == .string) {
                const is_thought = if (part.object.get("thought")) |v| v == .bool and v.bool else false;
                if (is_thought) {
                    if (thinking.items.len > 0) try thinking.appendSlice(gpa, "\n");
                    try thinking.appendSlice(gpa, t.string);
                    if (thinking_signature == null) {
                        if (part.object.get("thoughtSignature")) |sig| {
                            if (sig == .string and sig.string.len > 0) thinking_signature = try gpa.dupe(u8, sig.string);
                        }
                    }
                } else {
                    if (text.items.len > 0) try text.appendSlice(gpa, "\n");
                    try text.appendSlice(gpa, t.string);
                }
            }
        }
        if (part.object.get("functionCall")) |fc| {
            if (fc == .object) {
                const name = if (fc.object.get("name")) |n| (if (n == .string) n.string else "") else "";
                var args_aw: std.Io.Writer.Allocating = .init(gpa);
                defer args_aw.deinit();
                if (fc.object.get("args")) |a| {
                    try std.json.Stringify.value(a, .{}, &args_aw.writer);
                } else {
                    try args_aw.writer.writeAll("{}");
                }
                const id = if (fc.object.get("id")) |id_value|
                    if (id_value == .string and id_value.string.len > 0) try gpa.dupe(u8, id_value.string) else try std.fmt.allocPrint(gpa, "gcall_{d}", .{call_i})
                else
                    try std.fmt.allocPrint(gpa, "gcall_{d}", .{call_i});
                call_i += 1;
                var thought_signature: []const u8 = "";
                if (part.object.get("thoughtSignature")) |sig| {
                    if (sig == .string and sig.string.len > 0) thought_signature = try gpa.dupe(u8, sig.string);
                }
                try tcs.append(gpa, .{
                    .id = id,
                    .name = try gpa.dupe(u8, name),
                    .arguments = try args_aw.toOwnedSlice(),
                    .thought_signature = thought_signature,
                });
            }
        }
    }

    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usageMetadata")) |raw_usage| usage = parseGoogleUsage(raw_usage);
    var response_id: []const u8 = "";
    if (parsed.value.object.get("responseId")) |id| {
        if (id == .string and id.string.len > 0) response_id = try gpa.dupe(u8, id.string);
    }
    var raw_stop_reason: []const u8 = "";
    var normalized_stop: []const u8 = if (call_i > 0) "toolUse" else "stop";
    if (first.object.get("finishReason")) |finish| {
        if (finish == .string and finish.string.len > 0) {
            raw_stop_reason = try gpa.dupe(u8, finish.string);
            const mapped = mapGoogleStopReason(finish.string);
            if (call_i == 0 or !std.mem.eql(u8, mapped, "stop")) normalized_stop = mapped;
        }
    }

    return .{
        .content = try text.toOwnedSlice(gpa),
        .thinking = if (thinking.items.len > 0) try thinking.toOwnedSlice(gpa) else "",
        .thinking_signature = thinking_signature orelse "",
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = "",
        .response_id = response_id,
        .raw_stop_reason = raw_stop_reason,
        .stop_reason = try gpa.dupe(u8, normalized_stop),
        .usage = usage,
    };
}

test "parseGoogleResponse extracts text" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"responseId":"gresp_1","candidates":[{"content":{"parts":[{"text":"hello gemini"}]},"finishReason":"STOP"}]}
    ;
    var resp = try parseGoogleResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hello gemini", resp.content);
    try std.testing.expectEqual(@as(usize, 0), resp.tool_calls.len);
    try std.testing.expectEqualStrings("gresp_1", resp.response_id);
    try std.testing.expectEqualStrings("STOP", resp.raw_stop_reason);
}

test "parseGoogleResponse extracts functionCall tools" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"candidates":[{"content":{"parts":[{"functionCall":{"name":"read","args":{"path":"a.txt"}}}]}}]}
    ;
    var resp = try parseGoogleResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "a.txt") != null);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
}

test "Google tool-call stop reasons preserve length and normal tool use" {
    const gpa = std.testing.allocator;
    const prefix = "{\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"read\",\"args\":{}}}]},\"finishReason\":\"";
    const suffix = "\"}]}";
    const length_json = try std.fmt.allocPrint(gpa, "{s}MAX_TOKENS{s}", .{ prefix, suffix });
    defer gpa.free(length_json);
    var length = try parseGoogleResponse(gpa, length_json);
    defer length.deinit(gpa);
    try std.testing.expectEqualStrings("length", length.stop_reason);

    const stop_json = try std.fmt.allocPrint(gpa, "{s}STOP{s}", .{ prefix, suffix });
    defer gpa.free(stop_json);
    var stopped = try parseGoogleResponse(gpa, stop_json);
    defer stopped.deinit(gpa);
    try std.testing.expectEqualStrings("toolUse", stopped.stop_reason);
}

test "Google request honors mapped thinking levels and provider-neutral tool choice" {
    const gpa = std.testing.allocator;
    const msgs = [_]ai.ChatMessage{.{ .role = "user", .content = "hi" }};
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"parameters\":{\"type\":\"object\"}}}]";
    const body = try buildRequestBodyConfigured(gpa, &msgs, tools, "google", "gemini-test", .{
        .thinking = .xhigh,
        .thinking_level_map = .{ .xhigh = .{ .mapped = "HIGH" } },
        .tool_choice = .none,
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinkingLevel\":\"HIGH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"functionCallingConfig\":{\"mode\":\"NONE\"}") != null);
}

test "convertToolsToGoogle maps functionDeclarations" {
    const gpa = std.testing.allocator;
    const openai =
        \\[{"type":"function","function":{"name":"ls","description":"list","parameters":{"type":"object"}}}]
    ;
    const out = try convertToolsToGoogle(gpa, openai);
    defer if (out) |o| gpa.free(o);
    try std.testing.expect(out != null);
    try std.testing.expect(std.mem.indexOf(u8, out.?, "\"name\":\"ls\"") != null);
}

test "parseGoogleResponse preserves thought signatures" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"candidates":[{"content":{"parts":[{"text":"plan","thought":true,"thoughtSignature":"think-sig"},{"functionCall":{"id":"call-7","name":"read","args":{"path":"a.txt"}},"thoughtSignature":"tool-sig"},{"text":"answer"}]} }],"usageMetadata":{"promptTokenCount":12,"cachedContentTokenCount":2,"candidatesTokenCount":3,"thoughtsTokenCount":4}}
    ;
    var resp = try parseGoogleResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("plan", resp.thinking);
    try std.testing.expectEqualStrings("think-sig", resp.thinking_signature);
    try std.testing.expectEqualStrings("answer", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("call-7", resp.tool_calls[0].id);
    try std.testing.expectEqualStrings("tool-sig", resp.tool_calls[0].thought_signature);
    try std.testing.expectEqual(@as(u64, 10), resp.usage.input);
    try std.testing.expectEqual(@as(u64, 7), resp.usage.output);
    try std.testing.expectEqual(@as(u64, 2), resp.usage.cache_read);
    try std.testing.expectEqual(@as(u64, 4), resp.usage.reasoning.?);
}

test "Vertex express and ADC request URLs keep credentials in the correct channel" {
    const gpa = std.testing.allocator;
    const express = try buildRequestUrl(gpa, "https://aiplatform.googleapis.com/v1/publishers/google", "gemini-2.5-pro", "AIza-test", .query_key, true);
    defer gpa.free(express);
    try std.testing.expectEqualStrings("https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-2.5-pro:streamGenerateContent?alt=sse&key=AIza-test", express);

    const adc = try buildRequestUrl(gpa, "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google", "gemini-2.5-pro", "ya29.token", .bearer, false);
    defer gpa.free(adc);
    try std.testing.expectEqualStrings("https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent", adc);
    try std.testing.expect(std.mem.indexOf(u8, adc, "ya29") == null);
}

test "google request replays signatures only to same provider and model" {
    const gpa = std.testing.allocator;
    const calls =
        \\[{"id":"call-7","type":"function","function":{"name":"read","arguments":"{}"},"thoughtSignature":"dG9vbC1zaWc="}]
    ;
    const same = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "answer", .provider = "google", .model = "gemini-test", .thinking = "plan", .thinking_signature = "dGhpbmstc2ln", .tool_calls_json = calls },
    };
    const same_body = try buildRequestBody(gpa, &same, "[]", "google", "gemini-test");
    defer gpa.free(same_body);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "\"thought\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "dGhpbmstc2ln") != null);
    try std.testing.expect(std.mem.indexOf(u8, same_body, "dG9vbC1zaWc=") != null);

    const switched_body = try buildRequestBody(gpa, &same, "[]", "google", "gemini-other");
    defer gpa.free(switched_body);
    try std.testing.expect(std.mem.indexOf(u8, switched_body, "\"thought\":true") == null);
    try std.testing.expect(std.mem.indexOf(u8, switched_body, "dGhpbmstc2ln") == null);
    try std.testing.expect(std.mem.indexOf(u8, switched_body, "dG9vbC1zaWc=") == null);
    try std.testing.expect(std.mem.indexOf(u8, switched_body, "plan") != null);
}

test "google configured request carries max tokens thinking and sampling" {
    const gpa = std.testing.allocator;
    const sampling = [_]metadata.SamplingParam{
        .{ .name = "temperature", .value_json = "0.2" },
        .{ .name = "topP", .value_json = "0.8" },
    };
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const body = try buildRequestBodyConfigured(gpa, &messages, "[]", "google", "gemini-test", .{
        .max_tokens = 1234,
        .thinking = .high,
        .sampling_params = &sampling,
    });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"maxOutputTokens\":1234") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"includeThoughts\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"thinkingLevel\":\"HIGH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"temperature\":0.2") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"topP\":0.8") != null);
}

test "consumeGoogleStreamBody preserves deltas signatures tools and usage" {
    const gpa = std.testing.allocator;
    const body =
        \\data: {"candidates":[{"content":{"parts":[{"text":"plan ","thought":true,"thoughtSignature":"sig-think"},{"text":"hello "}]}}]}
        \\data: {"candidates":[{"content":{"parts":[{"text":"world"},{"functionCall":{"id":"fc1","name":"read","args":{"path":"a"}},"thoughtSignature":"sig-tool"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":20,"cachedContentTokenCount":5,"candidatesTokenCount":3,"thoughtsTokenCount":2,"totalTokenCount":25}}
        \\
    ;
    var resp = try consumeGoogleStreamBody(gpa, body, null, null);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hello world", resp.content);
    try std.testing.expectEqualStrings("plan ", resp.thinking);
    try std.testing.expectEqualStrings("sig-think", resp.thinking_signature);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("fc1", resp.tool_calls[0].id);
    try std.testing.expectEqualStrings("sig-tool", resp.tool_calls[0].thought_signature);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
    try std.testing.expectEqual(@as(u64, 15), resp.usage.input);
    try std.testing.expectEqual(@as(u64, 5), resp.usage.output);
    try std.testing.expectEqual(@as(u64, 5), resp.usage.cache_read);
    try std.testing.expectEqual(@as(u64, 2), resp.usage.reasoning.?);
}

test "Google tool call IDs follow upstream model-family requirements" {
    try std.testing.expect(!requiresToolCallId("gemini-2.5-pro"));
    try std.testing.expect(requiresToolCallId("gemini-3-pro"));
    try std.testing.expect(requiresToolCallId("gemini-live-3.1-flash"));
    try std.testing.expect(requiresToolCallId("claude-sonnet-4"));
    try std.testing.expect(requiresToolCallId("gpt-oss-120b"));

    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .provider = "google", .model = "gemini-3-pro", .content = "", .tool_calls_json = "[{\"id\":\"call:bad/id.long\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]" },
        .{ .role = "tool", .content = "ok", .tool_call_id = "call:bad/id.long", .tool_name = "read" },
    };
    const body3 = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-3-pro");
    defer gpa.free(body3);
    try std.testing.expect(std.mem.count(u8, body3, "\"id\":\"call_bad_id_long\"") == 2);

    const body2 = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-2.5-pro");
    defer gpa.free(body2);
    try std.testing.expect(std.mem.indexOf(u8, body2, "\"id\":\"call_bad_id_long\"") == null);
}

test "Google replay drops malformed thought signatures" {
    const gpa = std.testing.allocator;
    const calls =
        \\[{{"id":"call-1","type":"function","function":{{"name":"read","arguments":"{}"}},"thoughtSignature":"not-base64!"}}]
    ;
    const messages = [_]ai.ChatMessage{.{ .role = "assistant", .provider = "google", .model = "gemini-3-pro", .content = "ok", .thinking = "thought", .thinking_signature = "bad!", .tool_calls_json = calls }};
    const body = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-3-pro");
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "thoughtSignature") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "thought") != null);
}

test "Google serializes user images as inlineData" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "look", .image_b64 = "AQID", .image_mime = "image/png", .images = &.{.{ .data_b64 = "BAUG", .mime_type = "image/webp" }} }};
    const body = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-3-pro");
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"inlineData\":{\"mimeType\":\"image/webp\",\"data\":\"BAUG\"}") != null);
}

test "Google tool images nest for Gemini 3 and split for Gemini 2" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{ .role = "tool", .content = "captured", .tool_call_id = "call_1", .tool_name = "shot", .image_b64 = "AA==", .image_mime = "image/jpeg", .images = &.{.{ .data_b64 = "AQ==", .mime_type = "image/png" }} }};
    const body3 = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-3-pro");
    defer gpa.free(body3);
    try std.testing.expect(std.mem.indexOf(u8, body3, "\"functionResponse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body3, "\"parts\":[{\"inlineData\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body3, "Tool result image:") == null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body3, "\"inlineData\""));
    const body2 = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-2.5-pro");
    defer gpa.free(body2);
    try std.testing.expect(std.mem.indexOf(u8, body2, "Tool result image:") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body2, "\"inlineData\""));
}

test "Google groups consecutive function responses into one user turn" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "tool", .content = "a", .tool_call_id = "c1", .tool_name = "one" },
        .{ .role = "tool", .content = "b", .tool_call_id = "c2", .tool_name = "two" },
    };
    const body = try buildRequestBody(gpa, &messages, "[]", "google", "gemini-3-pro");
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const contents = parsed.value.object.get("contents").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), contents.len);
    const parts = contents[0].object.get("parts").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), parts.len);
    try std.testing.expect(parts[0].object.get("functionResponse") != null);
    try std.testing.expect(parts[1].object.get("functionResponse") != null);
}
