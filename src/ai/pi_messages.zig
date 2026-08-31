//! Native `pi-messages` transport.
//!
//! Upstream Pi's pi-messages API posts `{model, context, options}` to
//! `<baseUrl>/messages` and consumes an SSE stream containing Pi-native
//! assistant-message events. This implementation translates the native
//! pi-zig ChatMessage/tool representation into that wire format and translates
//! streamed Pi events back into ModelResponse/StreamDelta without a Node runtime.
const std = @import("std");
const Io = std.Io;
const http_proxy = @import("http_proxy.zig");
const http_fetch = @import("http_fetch.zig");
const retry_mod = @import("retry.zig");
const ai = @import("root.zig");
const context_estimate = @import("context_estimate.zig");
const transcript_repair = @import("transcript_repair.zig");
const metadata = @import("request_metadata.zig");
const stream_mod = @import("stream.zig");

pub const TokenRefreshFn = *const fn (*anyopaque, *PiMessagesClient, i64) anyerror!void;

pub const PiMessagesClient = struct {
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
    provider_id: []const u8 = "radius",
    api_id: []const u8 = "pi-messages",
    thinking: ai.ThinkingLevel = .off,
    custom_headers: []const metadata.Header = &.{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    abort_flag: ?*bool = null,
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    debug: bool = false,
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,

    pub fn client(self: *PiMessagesClient) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl, .completeOptionsFn = completeOptionsImpl, .streamFn = streamImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        const self: *PiMessagesClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, options, null, null);
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
        const self: *PiMessagesClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn ensureTokenFresh(self: *PiMessagesClient) !void {
        const expires = self.token_expiration_ms orelse return;
        const refresh_fn = self.token_refresh_fn orelse return;
        const ctx = self.token_refresh_ctx orelse return;
        const now_ms: i64 = @intCast(@divTrunc(std.Io.Clock.real.now(self.io).nanoseconds, std.time.ns_per_ms));
        if (now_ms < expires) return;
        try refresh_fn(ctx, self, now_ms);
    }

    fn request(
        self: *PiMessagesClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        request_options: ai.CompletionOptions,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        try self.ensureTokenFresh();
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const payload = try buildRequestBody(gpa, self.model, effective_messages, tools_json, .{
            .thinking = self.thinking,
            .max_tokens = effective_max_tokens,
            .session_id = ai.resolveSessionAffinity(self.session_id, request_options),
            .cache_retention = ai.resolveCacheRetention(self.cache_retention, request_options),
            .tool_choice = request_options.tool_choice,
        });
        defer gpa.free(payload);

        var url = if (std.mem.endsWith(u8, self.base_url, "/"))
            try std.fmt.allocPrint(gpa, "{s}messages", .{self.base_url})
        else
            try std.fmt.allocPrint(gpa, "{s}/messages", .{self.base_url});
        defer gpa.free(url);
        if (self.debug) {
            const old = url;
            url = try std.fmt.allocPrint(gpa, "{s}{s}debug=1", .{ old, if (std.mem.indexOfScalar(u8, old, '?') == null) "?" else "&" });
            gpa.free(old);
        }

        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });

        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHeader(gpa, &headers, "authorization", authorization);
        try putHeader(gpa, &headers, "accept", "text/event-stream");
        try putHeader(gpa, &headers, "content-type", "application/json");
        for (self.custom_headers) |header| try putHeader(gpa, &headers, header.name, header.value);

        var retry_index: usize = 0;
        while (true) {
            var live = PiMessagesLive.init(gpa, self.provider_id, self.model, on_delta, delta_ctx, self.abort_flag);
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
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (live.body.items.len > 0 or retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            try live.flushTrailing();
            if (live.aborted) return abortedResponse(gpa, self.provider_id, self.model);

            const status = fetch_result.status;
            if (status < 200 or status >= 300) {
                if (retry_index < self.provider_retry.max_retries and retry_mod.isRetryableProviderResponse(fetch_result.provider)) {
                    const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, fetch_result.provider.retry_after_ms);
                    retry_index += 1;
                    if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                    continue;
                }
                const response_body = try live.body.toOwnedSlice(gpa);
                defer gpa.free(response_body);
                var response = try httpErrorResponse(gpa, self.provider_id, self.model, status, response_body);
                response.provider_status = fetch_result.provider.status;
                response.provider_retry_after_ms = fetch_result.provider.retry_after_ms;
                response.provider_should_retry = fetch_result.provider.should_retry;
                return response;
            }
            if (!live.terminal) return streamEndedResponse(gpa, self.provider_id, self.model);
            return try live.finish();
        }
    }
};

pub const BuildOptions = struct {
    thinking: ai.ThinkingLevel = .off,
    max_tokens: u64 = 0,
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    tool_choice: ?ai.ToolChoice = null,
};

pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    options: BuildOptions,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"context\":{");

    var wrote_context = false;
    // Pi context has one systemPrompt field. Agent-generated ChatMessages put it
    // first, but merge multiple system records deterministically if present.
    var system_count: usize = 0;
    for (messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) system_count += 1;
    }
    if (system_count > 0) {
        try w.writeAll("\"systemPrompt\":");
        if (system_count == 1) {
            for (messages) |message| if (std.mem.eql(u8, message.role, "system")) {
                try std.json.Stringify.value(message.content, .{}, w);
                break;
            };
        } else {
            var merged: std.ArrayList(u8) = .empty;
            defer merged.deinit(gpa);
            var first = true;
            for (messages) |message| {
                if (!std.mem.eql(u8, message.role, "system")) continue;
                if (!first) try merged.appendSlice(gpa, "\n\n");
                first = false;
                try merged.appendSlice(gpa, message.content);
            }
            try std.json.Stringify.value(merged.items, .{}, w);
        }
        wrote_context = true;
    }

    if (wrote_context) try w.writeByte(',');
    try w.writeAll("\"messages\":[");
    var first_message = true;
    for (messages) |message| {
        if (std.mem.eql(u8, message.role, "system")) continue;
        if (!first_message) try w.writeByte(',');
        first_message = false;
        try writeContextMessage(gpa, w, message);
    }
    try w.writeByte(']');

    if (try writePiTools(gpa, w, tools_json)) {
        // writePiTools prefixes its own comma.
    }
    try w.writeAll("},\"options\":{");

    var first_option = true;
    if (options.max_tokens > 0) {
        try w.print("\"maxTokens\":{d}", .{options.max_tokens});
        first_option = false;
    }
    if (options.thinking != .off) {
        if (!first_option) try w.writeByte(',');
        try w.writeAll("\"reasoning\":");
        try std.json.Stringify.value(@tagName(options.thinking), .{}, w);
        first_option = false;
    }
    if (options.cache_retention != .short) {
        if (!first_option) try w.writeByte(',');
        try w.writeAll("\"cacheRetention\":");
        try std.json.Stringify.value(@tagName(options.cache_retention), .{}, w);
        first_option = false;
    }
    if (options.session_id) |session_id| {
        if (!first_option) try w.writeByte(',');
        try w.writeAll("\"sessionId\":");
        try std.json.Stringify.value(session_id, .{}, w);
        first_option = false;
    }
    if (options.tool_choice) |choice| {
        if (!first_option) try w.writeByte(',');
        try w.writeAll("\"toolChoice\":");
        try std.json.Stringify.value(choice.jsonName(), .{}, w);
    }
    try w.writeAll("}}");
    return out.toOwnedSlice();
}

fn writeContextMessage(gpa: std.mem.Allocator, w: *std.Io.Writer, message: ai.ChatMessage) !void {
    if (std.mem.eql(u8, message.role, "user")) {
        try w.writeAll("{\"role\":\"user\",\"content\":");
        if (message.hasImages()) {
            try w.writeByte('[');
            var wrote = false;
            if (message.content.len > 0) {
                try w.writeAll("{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(message.content, .{}, w);
                try w.writeByte('}');
                wrote = true;
            }
            var image_index: usize = 0;
            while (image_index < message.imageCount()) : (image_index += 1) {
                const image = message.imageAt(image_index).?;
                if (wrote) try w.writeByte(',');
                try w.writeAll("{\"type\":\"image\",\"data\":");
                try std.json.Stringify.value(image.data_b64, .{}, w);
                try w.writeAll(",\"mimeType\":");
                try std.json.Stringify.value(image.mime_type, .{}, w);
                try w.writeByte('}');
                wrote = true;
            }
            try w.writeByte(']');
        } else {
            try std.json.Stringify.value(message.content, .{}, w);
        }
        try w.writeAll(",\"timestamp\":0}");
        return;
    }

    if (std.mem.eql(u8, message.role, "tool") or std.mem.eql(u8, message.role, "toolResult")) {
        try w.writeAll("{\"role\":\"toolResult\",\"toolCallId\":");
        try std.json.Stringify.value(message.tool_call_id orelse "", .{}, w);
        try w.writeAll(",\"toolName\":");
        try std.json.Stringify.value(message.tool_name orelse "", .{}, w);
        try w.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(message.content, .{}, w);
        try w.writeAll("}],\"isError\":");
        try w.writeAll(if (message.tool_is_error) "true" else "false");
        try w.writeAll(",\"timestamp\":0}");
        return;
    }

    // Unknown conversational roles are intentionally represented as user text
    // rather than emitting an invalid pi-messages role.
    if (!std.mem.eql(u8, message.role, "assistant")) {
        try w.writeAll("{\"role\":\"user\",\"content\":");
        try std.json.Stringify.value(message.content, .{}, w);
        try w.writeAll(",\"timestamp\":0}");
        return;
    }

    try w.writeAll("{\"role\":\"assistant\",\"content\":[");
    var first_content = true;
    if (message.thinking) |thinking| if (thinking.len > 0) {
        try w.writeAll("{\"type\":\"thinking\",\"thinking\":");
        try std.json.Stringify.value(thinking, .{}, w);
        if (message.thinking_signature) |signature| if (signature.len > 0) {
            try w.writeAll(",\"thinkingSignature\":");
            try std.json.Stringify.value(signature, .{}, w);
        };
        try w.writeByte('}');
        first_content = false;
    };
    if (message.content.len > 0) {
        if (!first_content) try w.writeByte(',');
        try w.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(message.content, .{}, w);
        try w.writeByte('}');
        first_content = false;
    }
    if (message.tool_calls_json) |tool_calls| {
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, tool_calls, .{}) catch null;
        if (parsed) |*doc| {
            defer doc.deinit();
            if (doc.value == .array) {
                for (doc.value.array.items) |tool_call| {
                    if (tool_call != .object) continue;
                    const id_value = tool_call.object.get("id") orelse continue;
                    const fn_value = tool_call.object.get("function") orelse continue;
                    if (id_value != .string or fn_value != .object) continue;
                    const name_value = fn_value.object.get("name") orelse continue;
                    if (name_value != .string) continue;
                    if (!first_content) try w.writeByte(',');
                    first_content = false;
                    try w.writeAll("{\"type\":\"toolCall\",\"id\":");
                    try std.json.Stringify.value(id_value.string, .{}, w);
                    try w.writeAll(",\"name\":");
                    try std.json.Stringify.value(name_value.string, .{}, w);
                    try w.writeAll(",\"arguments\":");
                    if (fn_value.object.get("arguments")) |arguments| {
                        if (arguments == .string) {
                            var args_doc = std.json.parseFromSlice(std.json.Value, gpa, arguments.string, .{}) catch null;
                            if (args_doc) |*args| {
                                defer args.deinit();
                                try std.json.Stringify.value(args.value, .{}, w);
                            } else try w.writeAll("{}");
                        } else {
                            try std.json.Stringify.value(arguments, .{}, w);
                        }
                    } else try w.writeAll("{}");
                    try w.writeByte('}');
                }
            }
        }
    }
    try w.writeAll("],\"api\":\"pi-messages\",\"provider\":");
    try std.json.Stringify.value(message.provider orelse "unknown", .{}, w);
    try w.writeAll(",\"model\":");
    try std.json.Stringify.value(message.model orelse "unknown", .{}, w);
    try w.writeAll(",\"usage\":");
    try writeUsage(w, message.usage);
    try w.writeAll(",\"stopReason\":");
    try std.json.Stringify.value(message.stop_reason orelse if (message.tool_calls_json != null) "toolUse" else "stop", .{}, w);
    if (message.response_id) |response_id| if (response_id.len > 0) {
        try w.writeAll(",\"responseId\":");
        try std.json.Stringify.value(response_id, .{}, w);
    };
    try w.writeAll(",\"timestamp\":0}");
}

fn writeUsage(w: *std.Io.Writer, usage: ai.Usage) !void {
    try w.writeAll("{\"input\":");
    try w.print("{d}", .{usage.input});
    try w.writeAll(",\"output\":");
    try w.print("{d}", .{usage.output});
    try w.writeAll(",\"cacheRead\":");
    try w.print("{d}", .{usage.cache_read});
    try w.writeAll(",\"cacheWrite\":");
    try w.print("{d}", .{usage.cache_write});
    if (usage.cache_write_1h) |value| {
        try w.writeAll(",\"cacheWrite1h\":");
        try w.print("{d}", .{value});
    }
    if (usage.reasoning) |value| {
        try w.writeAll(",\"reasoning\":");
        try w.print("{d}", .{value});
    }
    try w.writeAll(",\"totalTokens\":");
    try w.print("{d}", .{usage.total()});
    try w.writeAll(",\"cost\":{\"input\":");
    try std.json.Stringify.value(usage.cost.input, .{}, w);
    try w.writeAll(",\"output\":");
    try std.json.Stringify.value(usage.cost.output, .{}, w);
    try w.writeAll(",\"cacheRead\":");
    try std.json.Stringify.value(usage.cost.cache_read, .{}, w);
    try w.writeAll(",\"cacheWrite\":");
    try std.json.Stringify.value(usage.cost.cache_write, .{}, w);
    try w.writeAll(",\"total\":");
    try std.json.Stringify.value(usage.cost.total, .{}, w);
    try w.writeAll("}}");
}

/// Convert the OpenAI-shaped native tool schema into Pi Context.tools.
/// Returns true when a tools field was emitted.
fn writePiTools(gpa: std.mem.Allocator, w: *std.Io.Writer, tools_json: []const u8) !bool {
    if (tools_json.len == 0) return false;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch return false;
    defer parsed.deinit();
    if (parsed.value != .array or parsed.value.array.items.len == 0) return false;

    var valid_count: usize = 0;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_value = item.object.get("function") orelse continue;
        if (fn_value != .object) continue;
        const name = fn_value.object.get("name") orelse continue;
        const params = fn_value.object.get("parameters") orelse continue;
        if (name != .string or params != .object) continue;
        valid_count += 1;
    }
    if (valid_count == 0) return false;

    try w.writeAll(",\"tools\":[");
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const fn_value = item.object.get("function") orelse continue;
        if (fn_value != .object) continue;
        const name = fn_value.object.get("name") orelse continue;
        const params = fn_value.object.get("parameters") orelse continue;
        if (name != .string or params != .object) continue;
        if (!first) try w.writeByte(',');
        first = false;
        try w.writeAll("{\"name\":");
        try std.json.Stringify.value(name.string, .{}, w);
        try w.writeAll(",\"description\":");
        if (fn_value.object.get("description")) |description| {
            if (description == .string) try std.json.Stringify.value(description.string, .{}, w) else try std.json.Stringify.value("", .{}, w);
        } else try std.json.Stringify.value("", .{}, w);
        try w.writeAll(",\"parameters\":");
        try std.json.Stringify.value(params, .{}, w);
        try w.writeByte('}');
    }
    try w.writeByte(']');
    return true;
}

fn putHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    for (headers.items) |*header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) {
            header.* = .{ .name = name, .value = value };
            return;
        }
    }
    try headers.append(gpa, .{ .name = name, .value = value });
}

fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try gpa.dupe(u8, "aborted"),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "aborted"),
    };
}

fn httpErrorResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8, status: u16, body: []const u8) !ai.ModelResponse {
    var message: []const u8 = body;
    var code: []const u8 = "";
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch null;
    if (parsed) |*doc| {
        defer doc.deinit();
        if (doc.value == .object) if (doc.value.object.get("error")) |err_value| if (err_value == .object) {
            if (err_value.object.get("message")) |v| {
                if (v == .string) message = v.string;
            }
            if (err_value.object.get("code")) |v| {
                if (v == .string) code = v.string;
            }
        };
        const content = if (code.len > 0)
            try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s} ({s})", .{ status, provider, message, code })
        else
            try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s}", .{ status, provider, message });
        return .{
            .content = content,
            .tool_calls = try gpa.alloc(ai.ToolCall, 0),
            .provider = try gpa.dupe(u8, provider),
            .model = try gpa.dupe(u8, model),
            .stop_reason = try gpa.dupe(u8, "error"),
        };
    }
    const snippet = if (body.len > 8192) body[0..8192] else body;
    return .{
        .content = try std.fmt.allocPrint(gpa, "HTTP {d} from {s}: {s}", .{ status, provider, snippet }),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "error"),
    };
}

fn streamEndedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{
        .content = try std.fmt.allocPrint(gpa, "{s} stream ended without a terminal event", .{provider}),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        .provider = try gpa.dupe(u8, provider),
        .model = try gpa.dupe(u8, model),
        .stop_reason = try gpa.dupe(u8, "error"),
    };
}

const PiMessagesLive = struct {
    gpa: std.mem.Allocator,
    provider: []const u8,
    model: []const u8,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
    line: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    acc: stream_mod.Accumulator,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    abort_flag: ?*bool = null,
    aborted: bool = false,
    terminal: bool = false,
    terminal_error: bool = false,
    stop_reason: []u8 = &.{},
    error_message: []u8 = &.{},
    response_id: []u8 = &.{},
    thinking_signature: []u8 = &.{},
    usage: ai.Usage = .{},

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };

    fn init(
        gpa: std.mem.Allocator,
        provider: []const u8,
        model: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
        abort_flag: ?*bool,
    ) PiMessagesLive {
        return .{
            .gpa = gpa,
            .provider = provider,
            .model = model,
            .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 },
            .acc = stream_mod.Accumulator.init(gpa),
            .on_delta = on_delta,
            .delta_ctx = delta_ctx,
            .abort_flag = abort_flag,
        };
    }

    fn attachBuffer(self: *PiMessagesLive) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }

    fn deinit(self: *PiMessagesLive) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.acc.deinit();
        if (self.stop_reason.len > 0) self.gpa.free(self.stop_reason);
        if (self.error_message.len > 0) self.gpa.free(self.error_message);
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.thinking_signature.len > 0) self.gpa.free(self.thinking_signature);
        self.* = undefined;
    }

    fn flushTrailing(self: *PiMessagesLive) !void {
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if (self.line.items.len > 0) {
            try self.handleLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }

    fn feed(self: *PiMessagesLive, chunk: []const u8) !void {
        if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) {
            self.aborted = true;
            return error.WriteFailed;
        };
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

    fn handleLine(self: *PiMessagesLive, raw_line: []const u8) !void {
        const line_trimmed = std.mem.trim(u8, raw_line, " \t");
        if (!std.mem.startsWith(u8, line_trimmed, "data:")) return;
        const data = std.mem.trim(u8, line_trimmed[5..], " \t");
        if (data.len == 0 or std.mem.eql(u8, data, "[DONE]")) return;
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, data, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const typ = parsed.value.object.get("type") orelse return;
        if (typ != .string) return;

        if (std.mem.eql(u8, typ.string, "text_delta")) {
            const delta = stringField(parsed.value.object, "delta") orelse return;
            try self.pushDelta(.{ .kind = .text_delta, .text = delta });
            return;
        }
        if (std.mem.eql(u8, typ.string, "thinking_delta")) {
            const delta = stringField(parsed.value.object, "delta") orelse return;
            try self.pushDelta(.{ .kind = .thinking_delta, .thinking = delta });
            return;
        }
        if (std.mem.eql(u8, typ.string, "thinking_end")) {
            if (stringField(parsed.value.object, "contentSignature")) |signature| {
                if (self.thinking_signature.len > 0) self.gpa.free(self.thinking_signature);
                self.thinking_signature = try self.gpa.dupe(u8, signature);
            }
            return;
        }
        if (std.mem.eql(u8, typ.string, "toolcall_start")) {
            const id = stringField(parsed.value.object, "id") orelse "";
            const name = stringField(parsed.value.object, "toolName") orelse "";
            try self.pushDelta(.{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = name });
            return;
        }
        if (std.mem.eql(u8, typ.string, "toolcall_delta")) {
            const delta = stringField(parsed.value.object, "delta") orelse "";
            try self.pushDelta(.{ .kind = .tool_call_delta, .tool_arguments = delta });
            return;
        }
        if (std.mem.eql(u8, typ.string, "toolcall_end")) {
            // The streamed delta buffer is authoritative for normal Pi backends.
            // If a backend emitted no deltas, seed the final toolCall here.
            if (parsed.value.object.get("toolCall")) |tool_call| if (tool_call == .object) {
                const id = stringField(tool_call.object, "id") orelse "";
                const name = stringField(tool_call.object, "name") orelse "";
                if (!accHasTool(&self.acc, id)) {
                    var args_buf: std.Io.Writer.Allocating = .init(self.gpa);
                    defer args_buf.deinit();
                    if (tool_call.object.get("arguments")) |arguments| try std.json.Stringify.value(arguments, .{}, &args_buf.writer) else try args_buf.writer.writeAll("{}");
                    try self.pushDelta(.{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = name, .tool_arguments = args_buf.written() });
                }
            };
            return;
        }
        if (std.mem.eql(u8, typ.string, "done") or std.mem.eql(u8, typ.string, "error")) {
            self.terminal = true;
            self.terminal_error = std.mem.eql(u8, typ.string, "error");
            if (stringField(parsed.value.object, "reason")) |reason| {
                if (self.stop_reason.len > 0) self.gpa.free(self.stop_reason);
                self.stop_reason = try self.gpa.dupe(u8, reason);
            }
            if (stringField(parsed.value.object, "errorMessage")) |message| {
                if (self.error_message.len > 0) self.gpa.free(self.error_message);
                self.error_message = try self.gpa.dupe(u8, message);
            }
            if (stringField(parsed.value.object, "responseId")) |response_id| {
                if (self.response_id.len > 0) self.gpa.free(self.response_id);
                self.response_id = try self.gpa.dupe(u8, response_id);
            }
            if (parsed.value.object.get("usage")) |usage| {
                if (usage == .object) self.usage = parseUsage(usage.object);
            }
            if (self.on_delta) |handler| handler(self.delta_ctx, .{ .kind = if (self.terminal_error) .err else .done });
            return;
        }
    }

    fn pushDelta(self: *PiMessagesLive, delta: ai.StreamDelta) !void {
        try self.acc.onDelta(delta);
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
    }

    fn finish(self: *PiMessagesLive) !ai.ModelResponse {
        var response = try self.acc.finish();
        response.provider = try self.gpa.dupe(u8, self.provider);
        response.model = try self.gpa.dupe(u8, self.model);
        response.usage = self.usage;
        if (self.thinking_signature.len > 0) response.thinking_signature = try self.gpa.dupe(u8, self.thinking_signature);
        const reason = if (self.stop_reason.len > 0) self.stop_reason else if (response.tool_calls.len > 0) "toolUse" else "stop";
        response.stop_reason = try self.gpa.dupe(u8, reason);
        if (self.stop_reason.len > 0) response.raw_stop_reason = try self.gpa.dupe(u8, self.stop_reason);
        if (self.response_id.len > 0) response.response_id = try self.gpa.dupe(u8, self.response_id);
        if (self.terminal_error and self.error_message.len > 0) {
            if (response.content.len > 0) self.gpa.free(response.content);
            response.content = try self.gpa.dupe(u8, self.error_message);
        }
        return response;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *PiMessagesLive = @fieldParentPtr("writer", w);
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

fn accHasTool(acc: *const stream_mod.Accumulator, id: []const u8) bool {
    if (id.len == 0) return acc.tool_ids.items.len > 0;
    for (acc.tool_ids.items) |existing| if (std.mem.eql(u8, existing, id)) return true;
    return false;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn numberToU64(value: std.json.Value) u64 {
    return switch (value) {
        .integer => |n| if (n > 0) @intCast(n) else 0,
        .float => |n| if (n > 0) @intFromFloat(n) else 0,
        else => 0,
    };
}

fn numberToF64(value: std.json.Value) f64 {
    return switch (value) {
        .integer => |n| @floatFromInt(n),
        .float => |n| n,
        else => 0,
    };
}

fn parseUsage(object: std.json.ObjectMap) ai.Usage {
    var usage: ai.Usage = .{};
    if (object.get("input")) |v| usage.input = numberToU64(v);
    if (object.get("output")) |v| usage.output = numberToU64(v);
    if (object.get("cacheRead")) |v| usage.cache_read = numberToU64(v);
    if (object.get("cacheWrite")) |v| usage.cache_write = numberToU64(v);
    if (object.get("totalTokens")) |v| usage.total_tokens = numberToU64(v);
    if (object.get("reasoning")) |v| usage.reasoning = numberToU64(v);
    if (object.get("cacheWrite1h")) |v| usage.cache_write_1h = numberToU64(v);
    if (object.get("cost")) |cost| if (cost == .object) {
        if (cost.object.get("input")) |v| usage.cost.input = numberToF64(v);
        if (cost.object.get("output")) |v| usage.cost.output = numberToF64(v);
        if (cost.object.get("cacheRead")) |v| usage.cost.cache_read = numberToF64(v);
        if (cost.object.get("cacheWrite")) |v| usage.cost.cache_write = numberToF64(v);
        if (cost.object.get("total")) |v| usage.cost.total = numberToF64(v);
    };
    if (usage.total_tokens == 0) usage.normalizeTotal();
    return usage;
}

pub fn consumePiMessagesStreamBody(
    gpa: std.mem.Allocator,
    body: []const u8,
    provider: []const u8,
    model: []const u8,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
) !ai.ModelResponse {
    var live = PiMessagesLive.init(gpa, provider, model, on_delta, delta_ctx, null);
    live.attachBuffer();
    defer live.deinit();
    try live.feed(body);
    try live.flushTrailing();
    if (!live.terminal) return streamEndedResponse(gpa, provider, model);
    return live.finish();
}

test "pi-messages request serializes native context tools and options" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = "system prompt" },
        .{ .role = "user", .content = "Hello", .image_b64 = "AA==", .image_mime = "image/png", .images = &.{.{ .data_b64 = "AQ==", .mime_type = "image/jpeg" }} },
        .{ .role = "assistant", .content = "I will read", .provider = "radius", .model = "auto", .thinking = "plan", .tool_calls_json = "[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"a.txt\\\"}\"}}]", .stop_reason = "toolUse", .response_id = "prev_resp", .usage = .{ .input = 11, .output = 7, .cache_read = 3, .cache_write = 2, .reasoning = 4, .total_tokens = 23, .cost = .{ .input = 0.1, .output = 0.2, .cache_read = 0.03, .cache_write = 0.04, .total = 0.37 } } },
        .{ .role = "tool", .content = "file text", .tool_call_id = "call_1", .tool_name = "read", .tool_is_error = false },
    };
    const tools = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"description\":\"Read file\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}}}]";
    const body = try buildRequestBody(gpa, "auto", &messages, tools, .{ .thinking = .high, .max_tokens = 100, .session_id = "session-1", .cache_retention = .long });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"model\":\"auto\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"systemPrompt\":\"system prompt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"role\":\"toolResult\"") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "\"type\":\"image\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "\"data\":\"AA==\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"data\":\"AQ==\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"arguments\":{\"path\":\"a.txt\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"input\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"totalTokens\":23") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"total\":3.7e-1") != null or std.mem.indexOf(u8, body, "\"total\":0.37") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"stopReason\":\"toolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"responseId\":\"prev_resp\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"tools\":[{\"name\":\"read\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"maxTokens\":100") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning\":\"high\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"cacheRetention\":\"long\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"sessionId\":\"session-1\"") != null);
}

test "pi-messages stream accumulates text thinking tools and backend usage" {
    const gpa = std.testing.allocator;
    const fixture =
        "data: {\"type\":\"start\"}\n\n" ++
        "data: {\"type\":\"thinking_delta\",\"contentIndex\":0,\"delta\":\"plan\"}\n\n" ++
        "data: {\"type\":\"thinking_end\",\"contentIndex\":0,\"content\":\"plan\",\"contentSignature\":\"sig-1\"}\n\n" ++
        "data: {\"type\":\"text_delta\",\"contentIndex\":1,\"delta\":\"Hel\"}\n\n" ++
        "data: {\"type\":\"text_delta\",\"contentIndex\":1,\"delta\":\"lo\"}\n\n" ++
        "data: {\"type\":\"toolcall_start\",\"contentIndex\":2,\"id\":\"call_1\",\"toolName\":\"read\"}\n\n" ++
        "data: {\"type\":\"toolcall_delta\",\"contentIndex\":2,\"delta\":\"{\\\"path\\\":\"}\n\n" ++
        "data: {\"type\":\"toolcall_delta\",\"contentIndex\":2,\"delta\":\"\\\"a.txt\\\"}\"}\n\n" ++
        "data: {\"type\":\"toolcall_end\",\"contentIndex\":2,\"toolCall\":{\"type\":\"toolCall\",\"id\":\"call_1\",\"name\":\"read\",\"arguments\":{\"path\":\"a.txt\"}}}\n\n" ++
        "data: {\"type\":\"done\",\"reason\":\"toolUse\",\"usage\":{\"input\":10,\"output\":5,\"cacheRead\":2,\"cacheWrite\":1,\"totalTokens\":18,\"cost\":{\"input\":0.1,\"output\":0.2,\"cacheRead\":0.01,\"cacheWrite\":0.02,\"total\":0.33}},\"responseId\":\"resp_1\"}\n\n";
    var response = try consumePiMessagesStreamBody(gpa, fixture, "radius", "auto", null, null);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("Hello", response.content);
    try std.testing.expectEqualStrings("plan", response.thinking);
    try std.testing.expectEqualStrings("sig-1", response.thinking_signature);
    try std.testing.expectEqualStrings("toolUse", response.stop_reason);
    try std.testing.expectEqualStrings("toolUse", response.raw_stop_reason);
    try std.testing.expectEqualStrings("resp_1", response.response_id);
    try std.testing.expectEqual(@as(usize, 1), response.tool_calls.len);
    try std.testing.expectEqualStrings("call_1", response.tool_calls[0].id);
    try std.testing.expectEqualStrings("read", response.tool_calls[0].name);
    try std.testing.expectEqualStrings("{\"path\":\"a.txt\"}", response.tool_calls[0].arguments);
    try std.testing.expectEqual(@as(u64, 10), response.usage.input);
    try std.testing.expectEqual(@as(u64, 18), response.usage.total());
    try std.testing.expectApproxEqAbs(@as(f64, 0.33), response.usage.cost.total, 1e-12);
}

test "pi-messages stream terminal error becomes ModelResponse error" {
    const gpa = std.testing.allocator;
    const fixture = "data: {\"type\":\"error\",\"reason\":\"error\",\"usage\":{\"input\":1,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":1,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"total\":0}},\"errorMessage\":\"Upstream failed\"}\n\n";
    var response = try consumePiMessagesStreamBody(gpa, fixture, "radius", "auto", null, null);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expectEqualStrings("Upstream failed", response.content);
    try std.testing.expectEqual(@as(u64, 1), response.usage.total());
}

test "pi-messages stream detects missing terminal event" {
    const gpa = std.testing.allocator;
    const fixture = "data: {\"type\":\"text_delta\",\"contentIndex\":0,\"delta\":\"partial\"}\n\n";
    var response = try consumePiMessagesStreamBody(gpa, fixture, "radius", "auto", null, null);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("error", response.stop_reason);
    try std.testing.expect(std.mem.indexOf(u8, response.content, "stream ended without a terminal event") != null);
}

test "pi-messages refresh hook runs only after OAuth expiry" {
    const gpa = std.testing.allocator;
    const Ctx = struct { calls: usize = 0, key: []const u8 = "old" };
    const Hooks = struct {
        fn refresh(ctx_raw: *anyopaque, client: *PiMessagesClient, now_ms: i64) anyerror!void {
            const ctx: *Ctx = @ptrCast(@alignCast(ctx_raw));
            ctx.calls += 1;
            ctx.key = "fresh";
            client.api_key = ctx.key;
            client.token_expiration_ms = now_ms + 60_000;
        }
    };
    var ctx = Ctx{};
    var client = PiMessagesClient{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "old",
        .base_url = "https://radius.example/v1",
        .model = "auto",
        .token_expiration_ms = 0,
        .token_refresh_ctx = &ctx,
        .token_refresh_fn = Hooks.refresh,
    };
    try client.ensureTokenFresh();
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqualStrings("fresh", client.api_key);
    try client.ensureTokenFresh();
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
}
