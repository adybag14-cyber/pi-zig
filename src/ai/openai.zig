//! OpenAI-compatible chat completions + tools (complete + stream:true SSE).
const std = @import("std");
const Io = std.Io;
const ai = @import("root.zig");
const stream_mod = @import("stream.zig");

pub const OpenAIClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    thinking: ai.ThinkingLevel = .off,
    /// Cooperative cancel checked during SSE drain.
    abort_flag: ?*bool = null,

    pub fn client(self: *OpenAIClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
            .streamFn = streamImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        const self: *OpenAIClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json, false, null, null);
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
        return self.request(gpa, messages, tools_json, true, on_delta, delta_ctx);
    }

    fn request(
        self: *OpenAIClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        const payload = try buildRequestBodyFull(gpa, self.model, messages, tools_json, streaming, self.thinking);
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/chat/completions", .{self.base_url});
        defer gpa.free(url);

        // Up to 3 attempts with exponential backoff on 429/5xx
        var attempt: u32 = 0;
        while (attempt < 3) : (attempt += 1) {
            if (attempt > 0) {
                const ms: i64 = 400 * (@as(i64, 1) << @intCast(attempt - 1));
                const backoff: std.Io.Timeout = .{ .duration = .{
                    .raw = .fromMilliseconds(ms),
                    .clock = .real,
                } };
                backoff.sleep(self.io) catch {};
            }
            const result = self.requestOnce(gpa, payload, url, streaming, on_delta, delta_ctx) catch |err| {
                if (attempt + 1 >= 3) return err;
                continue;
            };
            // requestOnce returns success responses; retry only on soft-fail via retryable flag
            if (result.stop_reason.len > 0 and std.mem.eql(u8, result.stop_reason, "error")) {
                if (isRetryableHttpErrorContent(result.content) and attempt + 1 < 3) {
                    // free and retry
                    var mut = result;
                    mut.deinit(gpa);
                    continue;
                }
            }
            return result;
        }
        return error.HttpError;
    }

    fn requestOnce(
        self: *OpenAIClient,
        gpa: std.mem.Allocator,
        payload: []const u8,
        url: []const u8,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        var http_client: std.http.Client = .{
            .allocator = gpa,
            .io = self.io,
        };
        defer http_client.deinit();

        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);
        const headers = [_]std.http.Header{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "authorization", .value = authorization },
            .{ .name = "accept", .value = if (streaming) "text/event-stream" else "application/json" },
        };

        // Live SSE writer: parse complete lines as HTTP body chunks drain into us
        var live = LiveSseWriter.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
        defer live.deinit();
        const fetch_result = http_client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .keep_alive = false,
            .extra_headers = &headers,
            .response_writer = &live.writer,
        }) catch |err| {
            if (self.abort_flag) |f| {
                if (f.*) {
                    return .{
                        .content = try gpa.dupe(u8, "aborted"),
                        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                        .provider = try gpa.dupe(u8, "openai"),
                        .model = try gpa.dupe(u8, self.model),
                        .stop_reason = try gpa.dupe(u8, "aborted"),
                    };
                }
            }
            return err;
        };
        const status: u16 = @intCast(@intFromEnum(fetch_result.status));
        try live.flushTrailing();
        if (live.aborted) {
            return .{
                .content = try gpa.dupe(u8, "aborted"),
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, "openai"),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "aborted"),
            };
        }
        if (status < 200 or status >= 300) {
            const response_json = try live.body.toOwnedSlice(gpa);
            defer gpa.free(response_json);
            return httpErrorResponse(gpa, "openai", status, response_json);
        }
        if (streaming) {
            var resp = try live.acc.finish();
            // Prevent double-free: finish() consumed acc contents; replace with empty
            live.acc = stream_mod.Accumulator.init(gpa);
            resp.provider = try gpa.dupe(u8, "openai");
            if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
            try resp.ensureStopReason(gpa);
            return resp;
        }
        const response_json = try live.body.toOwnedSlice(gpa);
        defer gpa.free(response_json);
        var resp = try parseOpenAIResponse(gpa, response_json);
        if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, "openai");
        try resp.ensureStopReason(gpa);
        return resp;
    }
};

fn isRetryableHttpErrorContent(content: []const u8) bool {
    if (std.mem.indexOf(u8, content, "HTTP 429") != null) return true;
    if (std.mem.indexOf(u8, content, "HTTP 500") != null) return true;
    if (std.mem.indexOf(u8, content, "HTTP 502") != null) return true;
    if (std.mem.indexOf(u8, content, "HTTP 503") != null) return true;
    if (std.mem.indexOf(u8, content, "HTTP 504") != null) return true;
    return false;
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

    fn deinit(self: *LiveSseWriter) void {
        self.line.deinit(self.gpa);
        self.body.deinit(self.gpa);
        self.acc.deinit();
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
            if (f.*) {
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
        if (try stream_mod.parseOpenAISseData(self.gpa, data)) |delta| {
            defer stream_mod.freeDelta(self.gpa, delta);
            try self.acc.onDelta(delta);
            if (self.on_delta) |h| h(self.delta_ctx, delta);
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

pub fn parseOpenAIResponse(gpa: std.mem.Allocator, response_json: []const u8) !ai.ModelResponse {
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
                const fn_obj = tc_item.object.get("function") orelse continue;
                if (fn_obj != .object) continue;
                const name = fn_obj.object.get("name") orelse continue;
                const args = fn_obj.object.get("arguments") orelse continue;
                if (id != .string or name != .string or args != .string) continue;
                try tcs.append(gpa, .{
                    .id = try gpa.dupe(u8, id.string),
                    .name = try gpa.dupe(u8, name.string),
                    .arguments = try gpa.dupe(u8, args.string),
                });
            }
        }
    }

    var usage: ai.Usage = .{};
    if (parsed.value.object.get("usage")) |u| {
        if (u == .object) {
            if (u.object.get("prompt_tokens")) |v| {
                if (v == .integer) usage.input = @intCast(v.integer);
            }
            if (u.object.get("completion_tokens")) |v| {
                if (v == .integer) usage.output = @intCast(v.integer);
            }
            if (u.object.get("total_tokens")) |v| {
                if (v == .integer) usage.total_tokens = @intCast(v.integer);
            }
        }
    }

    var model_out: []const u8 = "";
    if (parsed.value.object.get("model")) |m| {
        if (m == .string) model_out = try gpa.dupe(u8, m.string);
    }

    var stop_reason: []const u8 = "";
    if (first.object.get("finish_reason")) |fr| {
        if (fr == .string) {
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
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "openai"),
        .model = model_out,
        .stop_reason = stop_reason,
        .usage = usage,
    };
    try resp.ensureStopReason(gpa);
    return resp;
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
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    if (stream) try w.writeAll(",\"stream\":true");
    if (thinking.openaiEffort()) |effort| {
        try w.writeAll(",\"reasoning_effort\":");
        try std.json.Stringify.value(effort, .{}, w);
    }
    try w.writeAll(",\"messages\":[");
    for (messages, 0..) |msg, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"role\":");
        try std.json.Stringify.value(msg.role, .{}, w);
        if (msg.image_b64) |img| {
            try w.writeAll(",\"content\":[{\"type\":\"text\",\"text\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeAll("},{\"type\":\"image_url\",\"image_url\":{\"url\":");
            const data_url = try std.fmt.allocPrint(gpa, "data:{s};base64,{s}", .{ msg.image_mime orelse "image/png", img });
            defer gpa.free(data_url);
            try std.json.Stringify.value(data_url, .{}, w);
            try w.writeAll("}}]");
        } else {
            try w.writeAll(",\"content\":");
            try std.json.Stringify.value(msg.content, .{}, w);
        }
        if (msg.tool_call_id) |tid| {
            try w.writeAll(",\"tool_call_id\":");
            try std.json.Stringify.value(tid, .{}, w);
        }
        if (msg.tool_calls_json) |tcj| {
            try w.writeAll(",\"tool_calls\":");
            try w.writeAll(tcj);
        }
        try w.writeAll("}");
    }
    try w.writeAll("]");
    if (tools_json.len > 2) {
        try w.writeAll(",\"tools\":");
        try w.writeAll(tools_json);
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
        \\{"model":"gpt-4o-mini","choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":"hi","tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"path\":\"f\"}"}}]}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}
    ;
    var resp = try parseOpenAIResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hi", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expectEqualStrings("openai", resp.provider);
    try std.testing.expectEqualStrings("gpt-4o-mini", resp.model);
    try std.testing.expectEqualStrings("toolUse", resp.stop_reason);
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
