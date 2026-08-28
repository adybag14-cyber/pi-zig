//! Mistral Conversations transport.
//!
//! This is intentionally separate from the generic OpenAI-compatible path:
//! Mistral constrains tool-call IDs to exactly nine alphanumeric characters,
//! carries thinking as typed content chunks, exposes prompt-cache usage, and
//! uses Mistral-specific reasoning controls.
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

const TOOL_ID_LEN = 9;

pub const TokenRefreshFn = *const fn (ctx: *anyopaque, client: *MistralClient, now_ms: i64) anyerror!void;

pub const MistralClient = struct {
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
    provider_id: []const u8 = "mistral",
    api_id: []const u8 = "mistral-conversations",
    thinking: ai.ThinkingLevel = .off,
    custom_headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    input_image: bool = false,
    model_cost: providers.ModelCost = .{},
    abort_flag: ?*bool = null,
    token_expiration_ms: ?i64 = null,
    token_refresh_ctx: ?*anyopaque = null,
    token_refresh_fn: ?TokenRefreshFn = null,

    pub fn client(self: *MistralClient) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl, .completeOptionsFn = completeOptionsImpl, .streamFn = streamImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        const self: *MistralClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, options, false, null, null);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn streamImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque) anyerror!ai.ModelResponse {
        const self: *MistralClient = @ptrCast(@alignCast(ptr));
        var response = try self.request(gpa, messages, tools_json, .{}, true, on_delta, delta_ctx);
        errdefer response.deinit(gpa);
        try response.normalizeToolArguments(gpa);
        try response.setApi(gpa, self.api_id);
        return response;
    }

    fn request(self: *MistralClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, request_options: ai.CompletionOptions, streaming: bool, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque) !ai.ModelResponse {
        if (self.token_refresh_fn) |refresh| {
            const now_ms = Io.Clock.real.now(self.io).toMilliseconds();
            const should_refresh = self.api_key.len == 0 or (if (self.token_expiration_ms) |expires| expires <= now_ms + 60_000 else true);
            if (should_refresh) try refresh(self.token_refresh_ctx orelse return error.InvalidTokenRefreshContext, self, now_ms);
        }
        var prepared = try transcript_repair.prepare(gpa, messages, .{ .supports_images = self.input_image, .target_provider = self.provider_id, .target_api = self.api_id, .target_model = self.model });
        defer prepared.deinit();
        const effective_messages = prepared.messages.items;
        const effective_max_tokens = context_estimate.clampMaxTokens(self.context_window, ai.resolveMaxTokens(self.max_tokens, request_options.max_tokens), effective_messages, tools_json);
        const payload = try buildRequestBody(gpa, self.model, effective_messages, tools_json, .{
            .stream = streaming,
            .thinking = self.thinking,
            .max_tokens = effective_max_tokens,
            .sampling_params = self.sampling_params,
        });
        defer gpa.free(payload);
        const url = try std.fmt.allocPrint(gpa, "{s}/chat/completions", .{self.base_url});
        defer gpa.free(url);

        var retry_index: usize = 0;
        while (true) {
            const response = self.requestOnce(gpa, payload, url, streaming, on_delta, delta_ctx) catch |err| {
                if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
                if (err == error.ProviderStreamInterruptedAfterOutput or retry_index >= self.provider_retry.max_retries) return err;
                const delay_ms = try retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, null);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            };
            if (std.mem.eql(u8, response.stop_reason, "error") and
                retry_index < self.provider_retry.max_retries and
                retry_mod.isRetryableProviderResponse(response.providerRetryMeta()))
            {
                var retry_response = response;
                const delay_ms = retry_mod.providerDelayMs(self.io, self.provider_retry, retry_index, retry_response.provider_retry_after_ms) catch |err| {
                    retry_response.deinit(gpa);
                    return err;
                };
                retry_response.deinit(gpa);
                retry_index += 1;
                if (!retry_mod.waitProvider(self.io, delay_ms, self.abort_flag)) return abortedResponse(gpa, self.provider_id, self.model);
                continue;
            }
            return response;
        }
    }

    fn requestOnce(self: *MistralClient, gpa: std.mem.Allocator, payload: []const u8, url: []const u8, streaming: bool, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque) !ai.ModelResponse {
        var proxy_arena = std.heap.ArenaAllocator.init(gpa);
        defer proxy_arena.deinit();
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        _ = try http_proxy.configureClient(&http_client, proxy_arena.allocator(), url, .{
            .environ = self.environ,
            .setting = self.proxy_url,
        });
        const auth = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(auth);
        var headers: std.ArrayList(std.http.Header) = .empty;
        defer headers.deinit(gpa);
        try putHeader(gpa, &headers, "content-type", "application/json");
        try putHeader(gpa, &headers, "authorization", auth);
        try putHeader(gpa, &headers, "accept", if (streaming) "text/event-stream" else "application/json");
        for (self.custom_headers) |header| try putHeader(gpa, &headers, header.name, header.value);

        var live = LiveWriter.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
        live.attachBuffer();
        defer live.deinit();
        const result = http_fetch.fetchControlled(&http_client, .{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .keep_alive = false,
            .extra_headers = headers.items,
            .response_writer = &live.writer,
        }, self.provider_retry.timeout_ms, self.abort_flag) catch |err| {
            if (self.abort_flag) |flag| if (@atomicLoad(bool, flag, .acquire)) return abortedResponse(gpa, self.provider_id, self.model);
            if (streaming and live.body.items.len > 0) return error.ProviderStreamInterruptedAfterOutput;
            return err;
        };
        try live.flushTrailing();
        if (live.aborted) return abortedResponse(gpa, self.provider_id, self.model);
        const status = result.status;
        if (status < 200 or status >= 300) {
            const raw = try live.body.toOwnedSlice(gpa);
            defer gpa.free(raw);
            var response = try errorResponse(gpa, self.provider_id, self.model, status, raw);
            response.provider_status = result.provider.status;
            response.provider_retry_after_ms = result.provider.retry_after_ms;
            response.provider_should_retry = result.provider.should_retry;
            return response;
        }
        if (streaming) {
            var response = try live.acc.finish();
            response.provider = try gpa.dupe(u8, self.provider_id);
            response.model = try gpa.dupe(u8, self.model);
            if (live.response_id.len > 0) response.response_id = try gpa.dupe(u8, live.response_id);
            if (live.response_model.len > 0 and !std.mem.eql(u8, live.response_model, self.model)) response.response_model = try gpa.dupe(u8, live.response_model);
            if (live.raw_stop_reason.len > 0) response.raw_stop_reason = try gpa.dupe(u8, live.raw_stop_reason);
            response.usage = live.usage;
            _ = cost_mod.calculate(self.model_cost, &response.usage);
            response.stop_reason = try gpa.dupe(u8, if (live.stop_reason.len > 0) live.stop_reason else if (response.tool_calls.len > 0) "toolUse" else "stop");
            return response;
        }
        const raw = try live.body.toOwnedSlice(gpa);
        defer gpa.free(raw);
        var response = try parseResponse(gpa, raw);
        if (response.provider.len > 0) gpa.free(response.provider);
        response.provider = try gpa.dupe(u8, self.provider_id);
        try normalizeRequestedModel(gpa, &response, self.model);
        _ = cost_mod.calculate(self.model_cost, &response.usage);
        return response;
    }
};

pub const RequestOptions = struct {
    stream: bool = false,
    thinking: ai.ThinkingLevel = .off,
    max_tokens: u64 = 0,
    sampling_params: []const metadata.SamplingParam = &.{},
};

const IdEntry = struct { raw: []u8, normalized: [TOOL_ID_LEN]u8 };
const IdNormalizer = struct {
    gpa: std.mem.Allocator,
    entries: std.ArrayList(IdEntry) = .empty,
    fn init(gpa: std.mem.Allocator) IdNormalizer {
        return .{ .gpa = gpa };
    }
    fn deinit(self: *IdNormalizer) void {
        for (self.entries.items) |entry| self.gpa.free(entry.raw);
        self.entries.deinit(self.gpa);
    }
    fn normalize(self: *IdNormalizer, raw: []const u8) ![]const u8 {
        for (self.entries.items) |*entry| if (std.mem.eql(u8, entry.raw, raw)) return &entry.normalized;
        var attempt: u32 = 0;
        while (true) : (attempt += 1) {
            const candidate = deriveToolId(raw, attempt);
            var collision = false;
            for (self.entries.items) |entry| if (std.mem.eql(u8, &entry.normalized, &candidate)) {
                collision = true;
                break;
            };
            if (!collision) {
                try self.entries.append(self.gpa, .{ .raw = try self.gpa.dupe(u8, raw), .normalized = candidate });
                return &self.entries.items[self.entries.items.len - 1].normalized;
            }
        }
    }
};

fn deriveToolId(raw: []const u8, attempt: u32) [TOOL_ID_LEN]u8 {
    var clean: [TOOL_ID_LEN]u8 = undefined;
    var clean_len: usize = 0;
    for (raw) |c| {
        if (!std.ascii.isAlphanumeric(c)) continue;
        if (clean_len < TOOL_ID_LEN) clean[clean_len] = c;
        clean_len += 1;
    }
    if (attempt == 0 and clean_len == TOOL_ID_LEN) return clean;

    // Port of upstream shortHash's two 32-bit Math.imul lanes, then base36.
    var h1: u32 = 0xdeadbeef;
    var h2: u32 = 0x41c6ce57;
    const seed_extra = if (attempt == 0) "" else ":";
    for (raw) |c| {
        h1 = (h1 ^ @as(u32, c)) *% 2654435761;
        h2 = (h2 ^ @as(u32, c)) *% 1597334677;
    }
    for (seed_extra) |c| {
        h1 = (h1 ^ @as(u32, c)) *% 2654435761;
        h2 = (h2 ^ @as(u32, c)) *% 1597334677;
    }
    if (attempt > 0) {
        var buf: [16]u8 = undefined;
        const digits = std.fmt.bufPrint(&buf, "{d}", .{attempt}) catch "";
        for (digits) |c| {
            h1 = (h1 ^ @as(u32, c)) *% 2654435761;
            h2 = (h2 ^ @as(u32, c)) *% 1597334677;
        }
    }
    h1 = ((h1 ^ (h1 >> 16)) *% 2246822507) ^ ((h2 ^ (h2 >> 13)) *% 3266489909);
    h2 = ((h2 ^ (h2 >> 16)) *% 2246822507) ^ ((h1 ^ (h1 >> 13)) *% 3266489909);
    var base36: [26]u8 = undefined;
    var pos: usize = 0;
    pos += writeBase36(base36[pos..], h2);
    pos += writeBase36(base36[pos..], h1);
    var out: [TOOL_ID_LEN]u8 = undefined;
    for (0..TOOL_ID_LEN) |i| out[i] = if (i < pos) base36[i] else '0';
    return out;
}

fn writeBase36(out: []u8, input: u32) usize {
    const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
    var value = input;
    var rev: [7]u8 = undefined;
    var n: usize = 0;
    if (value == 0) {
        out[0] = '0';
        return 1;
    }
    while (value > 0 and n < rev.len) : (n += 1) {
        rev[n] = alphabet[value % 36];
        value /= 36;
    }
    for (0..n) |i| out[i] = rev[n - 1 - i];
    return n;
}

pub fn buildRequestBody(gpa: std.mem.Allocator, model: []const u8, messages: []const ai.ChatMessage, tools_json: []const u8, options: RequestOptions) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;
    var repaired = try transcript_repair.repair(gpa, messages);
    defer repaired.deinit();
    const replay_messages = repaired.messages.items;
    var ids = IdNormalizer.init(gpa);
    defer ids.deinit();

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.print(",\"stream\":{s}", .{if (options.stream) "true" else "false"});
    if (options.max_tokens > 0) try w.print(",\"max_tokens\":{d}", .{options.max_tokens});
    if (options.thinking != .off) {
        if (usesReasoningEffort(model)) {
            try w.writeAll(",\"reasoning_effort\":\"high\"");
        } else {
            try w.writeAll(",\"prompt_mode\":\"reasoning\"");
        }
    }
    try w.writeAll(",\"messages\":[");
    for (replay_messages, 0..) |msg, index| {
        if (index > 0) try w.writeAll(",");
        try w.writeAll("{\"role\":");
        try std.json.Stringify.value(msg.role, .{}, w);
        if (std.mem.eql(u8, msg.role, "assistant")) {
            const has_parts = msg.content.len > 0 or (msg.thinking != null and msg.thinking.?.len > 0);
            if (has_parts) {
                try w.writeAll(",\"content\":[");
                var first = true;
                if (msg.thinking) |thinking| if (thinking.len > 0) {
                    try w.writeAll("{\"type\":\"thinking\",\"thinking\":[{\"type\":\"text\",\"text\":");
                    try std.json.Stringify.value(thinking, .{}, w);
                    try w.writeAll("}]}");
                    first = false;
                };
                if (msg.content.len > 0) {
                    if (!first) try w.writeAll(",");
                    try w.writeAll("{\"type\":\"text\",\"text\":");
                    try std.json.Stringify.value(msg.content, .{}, w);
                    try w.writeAll("}");
                }
                try w.writeAll("]");
            }
            if (msg.tool_calls_json) |raw| {
                try w.writeAll(",\"tool_calls\":");
                try writeToolCalls(gpa, w, raw, &ids);
            } else if (!has_parts) {
                try w.writeAll(",\"content\":\"\"");
            }
        } else if (std.mem.eql(u8, msg.role, "tool")) {
            try w.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeAll("}]");
            if (msg.tool_call_id) |raw_id| {
                try w.writeAll(",\"tool_call_id\":");
                try std.json.Stringify.value(try ids.normalize(raw_id), .{}, w);
            }
            if (msg.tool_name) |name| {
                try w.writeAll(",\"name\":");
                try std.json.Stringify.value(name, .{}, w);
            }
        } else if (msg.hasImages()) {
            try w.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeByte('}');
            var image_index: usize = 0;
            while (image_index < msg.imageCount()) : (image_index += 1) {
                const image = msg.imageAt(image_index).?;
                try w.writeAll(",{\"type\":\"image_url\",\"image_url\":");
                const data = try std.fmt.allocPrint(gpa, "data:{s};base64,{s}", .{ image.mime_type, image.data_b64 });
                defer gpa.free(data);
                try std.json.Stringify.value(data, .{}, w);
                try w.writeByte('}');
            }
            try w.writeByte(']');
        } else {
            try w.writeAll(",\"content\":");
            try std.json.Stringify.value(msg.content, .{}, w);
        }
        try w.writeAll("}");
    }
    try w.writeAll("]");
    if (tools_json.len > 2) {
        try w.writeAll(",\"tools\":");
        try w.writeAll(tools_json);
    }
    for (options.sampling_params) |param| {
        try w.writeAll(",");
        try std.json.Stringify.value(param.name, .{}, w);
        try w.writeAll(":");
        try w.writeAll(param.value_json);
    }
    try w.writeAll("}");
    return body.toOwnedSlice();
}

fn writeToolCalls(gpa: std.mem.Allocator, w: anytype, raw: []const u8, ids: *IdNormalizer) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidToolCalls;
    try w.writeAll("[");
    for (parsed.value.array.items, 0..) |item, index| {
        if (index > 0) try w.writeAll(",");
        if (item != .object) return error.InvalidToolCalls;
        const id_v = item.object.get("id") orelse return error.InvalidToolCalls;
        const fn_v = item.object.get("function") orelse return error.InvalidToolCalls;
        if (id_v != .string or fn_v != .object) return error.InvalidToolCalls;
        try w.writeAll("{\"id\":");
        try std.json.Stringify.value(try ids.normalize(id_v.string), .{}, w);
        try w.writeAll(",\"type\":\"function\",\"function\":");
        try std.json.Stringify.value(fn_v, .{}, w);
        try w.writeAll("}");
    }
    try w.writeAll("]");
}

fn usesReasoningEffort(model: []const u8) bool {
    return std.mem.eql(u8, model, "mistral-small-2603") or std.mem.eql(u8, model, "mistral-small-latest") or std.mem.eql(u8, model, "mistral-medium-3.5");
}

fn parseUsage(value: std.json.Value) ai.Usage {
    var usage: ai.Usage = .{};
    if (value != .object) return usage;
    const prompt = intAny(value.object, &.{ "prompt_tokens", "promptTokens" });
    const cached = cachedTokens(value.object, prompt);
    usage.input = prompt -| cached;
    usage.cache_read = cached;
    usage.output = intAny(value.object, &.{ "completion_tokens", "completionTokens" });
    usage.total_tokens = intAny(value.object, &.{ "total_tokens", "totalTokens" });
    usage.normalizeTotal();
    return usage;
}

fn cachedTokens(object: std.json.ObjectMap, prompt: u64) u64 {
    var raw: u64 = 0;
    const detail_names = [_][]const u8{ "prompt_tokens_details", "promptTokensDetails", "prompt_token_details", "promptTokenDetails" };
    for (detail_names) |name| if (object.get(name)) |v| if (v == .object) {
        raw = intAny(v.object, &.{ "cached_tokens", "cachedTokens" });
        if (raw > 0) break;
    };
    if (raw == 0) raw = intAny(object, &.{ "num_cached_tokens", "numCachedTokens" });
    return @min(raw, prompt);
}

fn intAny(object: std.json.ObjectMap, names: []const []const u8) u64 {
    for (names) |name| if (object.get(name)) |value| switch (value) {
        .integer => |v| if (v > 0) return @intCast(v),
        .float => |v| if (v > 0) return @intFromFloat(v),
        else => {},
    };
    return 0;
}

pub fn parseResponse(gpa: std.mem.Allocator, raw: []const u8) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;
    const choices = parsed.value.object.get("choices") orelse return error.InvalidResponse;
    if (choices != .array or choices.array.items.len == 0 or choices.array.items[0] != .object) return error.InvalidResponse;
    const first = choices.array.items[0].object;
    const message_v = first.get("message") orelse return error.InvalidResponse;
    if (message_v != .object) return error.InvalidResponse;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var thinking: std.ArrayList(u8) = .empty;
    defer thinking.deinit(gpa);
    try appendContent(gpa, message_v.object.get("content"), &text, &thinking);
    var calls: std.ArrayList(ai.ToolCall) = .empty;
    errdefer {
        for (calls.items) |*call| call.deinit(gpa);
        calls.deinit(gpa);
    }
    if (message_v.object.get("tool_calls") orelse message_v.object.get("toolCalls")) |tcv| if (tcv == .array) {
        for (tcv.array.items) |item| {
            if (item != .object) continue;
            const id_v = item.object.get("id") orelse continue;
            const fn_v = item.object.get("function") orelse continue;
            if (id_v != .string or fn_v != .object) continue;
            const name_v = fn_v.object.get("name") orelse continue;
            const args_v = fn_v.object.get("arguments") orelse continue;
            if (name_v != .string) continue;
            const args = if (args_v == .string) try gpa.dupe(u8, args_v.string) else try jsonValueOwned(gpa, args_v);
            try calls.append(gpa, .{ .id = try gpa.dupe(u8, id_v.string), .name = try gpa.dupe(u8, name_v.string), .arguments = args });
        }
    };
    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usage")) |value| usage = parseUsage(value);
    const raw_stop = if (first.get("finish_reason") orelse first.get("finishReason")) |v| if (v == .string) v.string else "" else "";
    const stop = mapStop(raw_stop);
    var response: ai.ModelResponse = .{
        .content = try gpa.dupe(u8, text.items),
        .thinking = if (thinking.items.len > 0) try gpa.dupe(u8, thinking.items) else "",
        .tool_calls = try calls.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "mistral"),
        .response_id = if (parsed.value.object.get("id")) |id| if (id == .string and id.string.len > 0) try gpa.dupe(u8, id.string) else "" else "",
        .raw_stop_reason = if (raw_stop.len > 0) try gpa.dupe(u8, raw_stop) else "",
        .stop_reason = try gpa.dupe(u8, stop),
        .usage = usage,
    };
    if (parsed.value.object.get("model")) |mv| {
        if (mv == .string) response.model = try gpa.dupe(u8, mv.string);
    }
    return response;
}

fn appendContent(gpa: std.mem.Allocator, optional: ?std.json.Value, text: *std.ArrayList(u8), thinking: *std.ArrayList(u8)) !void {
    const value = optional orelse return;
    switch (value) {
        .string => |s| try text.appendSlice(gpa, s),
        .array => |array| for (array.items) |item| {
            if (item == .string) {
                try text.appendSlice(gpa, item.string);
                continue;
            }
            if (item != .object) continue;
            const type_v = item.object.get("type") orelse continue;
            if (type_v != .string) continue;
            if (std.mem.eql(u8, type_v.string, "text")) {
                if (item.object.get("text")) |v| if (v == .string) try text.appendSlice(gpa, v.string);
            } else if (std.mem.eql(u8, type_v.string, "thinking")) {
                if (item.object.get("thinking")) |parts| switch (parts) {
                    .string => |s| try thinking.appendSlice(gpa, s),
                    .array => |a| for (a.items) |part| if (part == .object) if (part.object.get("text")) |v| if (v == .string) try thinking.appendSlice(gpa, v.string),
                    else => {},
                };
            }
        },
        else => {},
    }
}

fn mapStop(raw: []const u8) []const u8 {
    if (std.mem.eql(u8, raw, "tool_calls")) return "toolUse";
    if (std.mem.eql(u8, raw, "length") or std.mem.eql(u8, raw, "model_length")) return "length";
    if (raw.len == 0 or std.mem.eql(u8, raw, "stop")) return "stop";
    if (std.mem.eql(u8, raw, "error")) return "error";
    return "error";
}

const LiveWriter = struct {
    gpa: std.mem.Allocator,
    writer: std.Io.Writer,
    buf: [4096]u8 = undefined,
    line: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    acc: stream_mod.Accumulator,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
    streaming: bool,
    abort_flag: ?*bool,
    aborted: bool = false,
    usage: ai.Usage = .{},
    stop_reason: []const u8 = "",
    response_id: []u8 = &.{},
    response_model: []u8 = &.{},
    raw_stop_reason: []u8 = &.{},

    const vtable: std.Io.Writer.VTable = .{ .drain = drain, .flush = std.Io.Writer.noopFlush };
    fn init(gpa: std.mem.Allocator, on_delta: ?ai.StreamHandler, delta_ctx: ?*anyopaque, streaming: bool, abort_flag: ?*bool) LiveWriter {
        return .{ .gpa = gpa, .writer = .{ .vtable = &vtable, .buffer = &.{}, .end = 0 }, .acc = .init(gpa), .on_delta = on_delta, .delta_ctx = delta_ctx, .streaming = streaming, .abort_flag = abort_flag };
    }
    fn attachBuffer(self: *LiveWriter) void {
        self.writer.buffer = &self.buf;
        self.writer.end = 0;
    }
    fn deinit(self: *LiveWriter) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.acc.deinit();
        if (self.response_id.len > 0) self.gpa.free(self.response_id);
        if (self.response_model.len > 0) self.gpa.free(self.response_model);
        if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
    }
    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        _ = splat;
        const self: *LiveWriter = @fieldParentPtr("writer", w);
        var total: usize = 0;
        for (data) |chunk| {
            self.feed(chunk) catch return error.WriteFailed;
            total += chunk.len;
        }
        return total;
    }
    fn feed(self: *LiveWriter, chunk: []const u8) !void {
        if (self.abort_flag) |flag| {
            if (@atomicLoad(bool, flag, .acquire)) {
                self.aborted = true;
                return error.WriteFailed;
            }
        }
        try self.body.appendSlice(self.gpa, chunk);
        if (self.streaming) try self.consume(chunk);
    }
    fn consume(self: *LiveWriter, chunk: []const u8) !void {
        for (chunk) |c| {
            if (c == '\n') {
                try self.processLine(self.line.items);
                self.line.clearRetainingCapacity();
            } else if (c != '\r') try self.line.append(self.gpa, c);
        }
    }
    fn flushTrailing(self: *LiveWriter) !void {
        if (self.writer.end > 0) {
            try self.feed(self.writer.buffer[0..self.writer.end]);
            self.writer.end = 0;
        }
        if (self.streaming and self.line.items.len > 0) {
            try self.processLine(self.line.items);
            self.line.clearRetainingCapacity();
        }
    }
    fn processLine(self: *LiveWriter, line: []const u8) !void {
        if (!std.mem.startsWith(u8, line, "data:")) return;
        const data = std.mem.trim(u8, line[5..], " \t");
        if (data.len == 0 or std.mem.eql(u8, data, "[DONE]")) return;
        try self.processData(data);
    }
    fn processData(self: *LiveWriter, data: []const u8) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, data, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        if (self.response_id.len == 0) if (parsed.value.object.get("id")) |id| if (id == .string and id.string.len > 0) {
            self.response_id = try self.gpa.dupe(u8, id.string);
        };
        if (self.response_model.len == 0) if (parsed.value.object.get("model")) |model| if (model == .string and model.string.len > 0) {
            self.response_model = try self.gpa.dupe(u8, model.string);
        };
        if (parsed.value.object.get("usage")) |u| self.usage = parseUsage(u);
        const choices = parsed.value.object.get("choices") orelse return;
        if (choices != .array or choices.array.items.len == 0 or choices.array.items[0] != .object) return;
        const first = choices.array.items[0].object;
        if (first.get("finish_reason") orelse first.get("finishReason")) |fr| {
            if (fr == .string and fr.string.len > 0) {
                self.stop_reason = mapStop(fr.string);
                if (self.raw_stop_reason.len > 0) self.gpa.free(self.raw_stop_reason);
                self.raw_stop_reason = try self.gpa.dupe(u8, fr.string);
            }
        }
        const delta_v = first.get("delta") orelse return;
        if (delta_v != .object) return;
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(self.gpa);
        var thinking: std.ArrayList(u8) = .empty;
        defer thinking.deinit(self.gpa);
        try appendContent(self.gpa, delta_v.object.get("content"), &text, &thinking);
        if (text.items.len > 0) try self.emit(.{ .kind = .text_delta, .text = text.items });
        if (thinking.items.len > 0) try self.emit(.{ .kind = .thinking_delta, .thinking = thinking.items });
        if (delta_v.object.get("tool_calls") orelse delta_v.object.get("toolCalls")) |tcv| if (tcv == .array) {
            for (tcv.array.items, 0..) |item, index| {
                if (item != .object) continue;
                var id: []const u8 = "";
                if (item.object.get("id")) |v| {
                    if (v == .string and !std.mem.eql(u8, v.string, "null")) id = v.string;
                }
                var synthetic: [TOOL_ID_LEN]u8 = undefined;
                if (id.len == 0) {
                    synthetic = deriveToolId("toolcall", @intCast(index));
                    id = &synthetic;
                }
                const fnv = item.object.get("function") orelse continue;
                if (fnv != .object) continue;
                var name: []const u8 = "";
                if (fnv.object.get("name")) |v| {
                    if (v == .string) name = v.string;
                }
                var args_owned: ?[]u8 = null;
                defer if (args_owned) |owned| self.gpa.free(owned);
                var args: []const u8 = "";
                if (fnv.object.get("arguments")) |v| {
                    if (v == .string) args = v.string else {
                        args_owned = try jsonValueOwned(self.gpa, v);
                        args = args_owned.?;
                    }
                }
                try self.emit(.{ .kind = .tool_call_delta, .tool_call_id = id, .tool_name = name, .tool_arguments = args });
            }
        };
    }
    fn emit(self: *LiveWriter, delta: ai.StreamDelta) !void {
        try self.acc.onDelta(delta);
        if (self.on_delta) |handler| handler(self.delta_ctx, delta);
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

fn jsonValueOwned(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn putHeader(gpa: std.mem.Allocator, headers: *std.ArrayList(std.http.Header), name: []const u8, value: []const u8) !void {
    for (headers.items) |*header| if (std.ascii.eqlIgnoreCase(header.name, name)) {
        header.* = .{ .name = name, .value = value };
        return;
    };
    try headers.append(gpa, .{ .name = name, .value = value });
}
fn abortedResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8) !ai.ModelResponse {
    return .{ .content = try gpa.dupe(u8, "aborted"), .tool_calls = try gpa.alloc(ai.ToolCall, 0), .provider = try gpa.dupe(u8, provider), .model = try gpa.dupe(u8, model), .stop_reason = try gpa.dupe(u8, "aborted") };
}
fn errorResponse(gpa: std.mem.Allocator, provider: []const u8, model: []const u8, status: u16, raw: []const u8) !ai.ModelResponse {
    const capped = raw[0..@min(raw.len, 4000)];
    return .{ .content = try std.fmt.allocPrint(gpa, "Mistral API error ({d}): {s}", .{ status, capped }), .tool_calls = try gpa.alloc(ai.ToolCall, 0), .provider = try gpa.dupe(u8, provider), .model = try gpa.dupe(u8, model), .stop_reason = try gpa.dupe(u8, "error") };
}

test "Mistral serializes all ordered image URLs" {
    const gpa = std.testing.allocator;
    const messages = [_]ai.ChatMessage{.{
        .role = "user",
        .content = "compare",
        .image_b64 = "AA==",
        .image_mime = "image/png",
        .images = &.{.{ .data_b64 = "AQ==", .mime_type = "image/jpeg" }},
    }};
    const body = try buildRequestBody(gpa, "mistral-large-latest", &messages, "[]", .{});
    defer gpa.free(body);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, body, "\"type\":\"image_url\""));
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/png;base64,AA==") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "data:image/jpeg;base64,AQ==") != null);
}

test "Mistral tool IDs are exactly nine alphanumeric characters and stable" {
    const gpa = std.testing.allocator;
    var normalizer = IdNormalizer.init(gpa);
    defer normalizer.deinit();
    const a = try normalizer.normalize("call_very-long|item$id");
    const b = try normalizer.normalize("call_very-long|item$id");
    try std.testing.expectEqual(@as(usize, 9), a.len);
    try std.testing.expectEqualStrings(a, b);
    for (a) |c| try std.testing.expect(std.ascii.isAlphanumeric(c));
    try std.testing.expectEqualStrings("AbC123xyz", try normalizer.normalize("AbC123xyz"));
}

test "Mistral request replays thinking and pairs normalized tool IDs" {
    const gpa = std.testing.allocator;
    const calls = "[{\"id\":\"responses-call|item-123\",\"type\":\"function\",\"function\":{\"name\":\"bash\",\"arguments\":\"{\\\"cmd\\\":\\\"pwd\\\"}\"}}]";
    const messages = [_]ai.ChatMessage{
        .{ .role = "assistant", .content = "", .thinking = "plan", .tool_calls_json = calls },
        .{ .role = "tool", .content = "ok", .tool_call_id = "responses-call|item-123", .tool_name = "bash" },
    };
    const body = try buildRequestBody(gpa, "mistral-large-latest", &messages, "[]", .{ .stream = true, .thinking = .high, .max_tokens = 123 });
    defer gpa.free(body);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();
    const arr = parsed.value.object.get("messages").?.array.items;
    const call_id = arr[0].object.get("tool_calls").?.array.items[0].object.get("id").?.string;
    const result_id = arr[1].object.get("tool_call_id").?.string;
    try std.testing.expectEqual(@as(usize, 9), call_id.len);
    try std.testing.expectEqualStrings(call_id, result_id);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"prompt_mode\":\"reasoning\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":\"thinking\"") != null);
}

test "Mistral small uses reasoning_effort and cached usage is separated" {
    const gpa = std.testing.allocator;
    const body = try buildRequestBody(gpa, "mistral-small-latest", &.{.{ .role = "user", .content = "x" }}, "[]", .{ .thinking = .high });
    defer gpa.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"reasoning_effort\":\"high\"") != null);
    const response = "{\"id\":\"mresp_1\",\"model\":\"m\",\"choices\":[{\"message\":{\"content\":[{\"type\":\"thinking\",\"thinking\":[{\"type\":\"text\",\"text\":\"hmm\"}]},{\"type\":\"text\",\"text\":\"ok\"}]},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":100,\"prompt_tokens_details\":{\"cached_tokens\":40},\"completion_tokens\":20,\"total_tokens\":120}}";
    var parsed_resp = try parseResponse(gpa, response);
    defer parsed_resp.deinit(gpa);
    try std.testing.expectEqualStrings("ok", parsed_resp.content);
    try std.testing.expectEqualStrings("hmm", parsed_resp.thinking);
    try std.testing.expectEqual(@as(u64, 60), parsed_resp.usage.input);
    try std.testing.expectEqual(@as(u64, 40), parsed_resp.usage.cache_read);
    try std.testing.expectEqual(@as(u64, 20), parsed_resp.usage.output);
    try std.testing.expectEqualStrings("mresp_1", parsed_resp.response_id);
    try std.testing.expectEqualStrings("stop", parsed_resp.raw_stop_reason);
}
