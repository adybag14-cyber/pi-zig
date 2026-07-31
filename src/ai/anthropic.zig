//! Anthropic Messages API + tools (complete + stream SSE).
const std = @import("std");
const Io = std.Io;
const ai = @import("root.zig");
const stream_mod = @import("stream.zig");

pub const AnthropicClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,
    thinking: ai.ThinkingLevel = .off,
    abort_flag: ?*bool = null,

    pub fn client(self: *AnthropicClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
            .streamFn = streamImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        const self: *AnthropicClient = @ptrCast(@alignCast(ptr));
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
        const self: *AnthropicClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json, true, on_delta, delta_ctx);
    }

    fn request(
        self: *AnthropicClient,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        const payload = try buildRequestBodyFull(gpa, self.model, messages, tools_json, streaming, self.thinking);
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/v1/messages", .{self.base_url});
        defer gpa.free(url);

        // Up to 3 attempts with exponential backoff
        var attempt: u32 = 0;
        while (attempt < 3) : (attempt += 1) {
            if (attempt > 0) {
                const ms: i64 = 400 * (@as(i64, 1) << @intCast(attempt - 1));
                const backoff: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(ms), .clock = .real } };
                backoff.sleep(self.io) catch {};
            }
            const result = self.requestOnce(gpa, payload, url, streaming, on_delta, delta_ctx) catch {
                if (attempt + 1 >= 3) return error.HttpError;
                continue;
            };
            if (result.stop_reason.len > 0 and std.mem.eql(u8, result.stop_reason, "error")) {
                if ((std.mem.indexOf(u8, result.content, "HTTP 429") != null or
                    std.mem.indexOf(u8, result.content, "HTTP 5") != null) and attempt + 1 < 3)
                {
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
        self: *AnthropicClient,
        gpa: std.mem.Allocator,
        payload: []const u8,
        url: []const u8,
        streaming: bool,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        var http_client: std.http.Client = .{ .allocator = gpa, .io = self.io };
        defer http_client.deinit();
        const headers = [_]std.http.Header{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
            .{ .name = "accept", .value = if (streaming) "text/event-stream" else "application/json" },
        };

        var live = AnthropicLiveSse.init(gpa, on_delta, delta_ctx, streaming, self.abort_flag);
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
                        .provider = try gpa.dupe(u8, "anthropic"),
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
                .provider = try gpa.dupe(u8, "anthropic"),
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
                .provider = try gpa.dupe(u8, "anthropic"),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "error"),
            };
        }
        if (streaming) {
            var resp = try live.acc.finish();
            live.acc = stream_mod.Accumulator.init(gpa);
            resp.provider = try gpa.dupe(u8, "anthropic");
            if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
            try resp.ensureStopReason(gpa);
            return resp;
        }
        const response_json = try live.body.toOwnedSlice(gpa);
        defer gpa.free(response_json);
        var resp = try parseAnthropicResponse(gpa, response_json);
        if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, "anthropic");
        try resp.ensureStopReason(gpa);
        return resp;
    }
};

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
        if (try stream_mod.parseAnthropicEvent(self.gpa, ename, data)) |delta| {
            defer stream_mod.freeDelta(self.gpa, delta);
            try self.acc.onDelta(delta);
            if (self.on_delta) |h| h(self.delta_ctx, delta);
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

fn appendAnthropicToolUses(gpa: std.mem.Allocator, w: anytype, tool_calls_json: []const u8) !void {
    _ = gpa;
    // Expect OpenAI format: [{"id":"...","type":"function","function":{"name":"...","arguments":"..."}}]
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, tool_calls_json, .{}) catch {
        // Fallback: empty
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items, 0..) |item, i| {
        if (i > 0) try w.writeAll(",");
        if (item != .object) continue;
        const id = item.object.get("id");
        const fn_obj = item.object.get("function");
        if (id == null or fn_obj == null or id.? != .string or fn_obj.? != .object) continue;
        const name = fn_obj.?.object.get("name");
        const args = fn_obj.?.object.get("arguments");
        if (name == null or args == null or name.? != .string or args.? != .string) continue;
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

pub fn convertToolsToAnthropic(gpa: std.mem.Allocator, tools_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return try gpa.dupe(u8, "[]");

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
        try out.writer.writeAll(",\"input_schema\":");
        if (params) |p| {
            try std.json.Stringify.value(p, .{}, &out.writer);
        } else {
            try out.writer.writeAll("{\"type\":\"object\",\"properties\":{}}");
        }
        try out.writer.writeAll("}");
    }
    try out.writer.writeAll("]");
    return try out.toOwnedSlice();
}

pub fn parseAnthropicResponse(gpa: std.mem.Allocator, response_json: []const u8) !ai.ModelResponse {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidResponse;

    const content_arr = parsed.value.object.get("content") orelse return error.InvalidResponse;
    if (content_arr != .array) return error.InvalidResponse;

    var text_parts: std.ArrayList(u8) = .empty;
    errdefer text_parts.deinit(gpa);
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
    if (parsed.value.object.get("usage")) |u| {
        if (u == .object) {
            if (u.object.get("input_tokens")) |v| {
                if (v == .integer) usage.input = @intCast(v.integer);
            }
            if (u.object.get("output_tokens")) |v| {
                if (v == .integer) usage.output = @intCast(v.integer);
            }
            if (u.object.get("cache_read_input_tokens")) |v| {
                if (v == .integer) usage.cache_read = @intCast(v.integer);
            }
            if (u.object.get("cache_creation_input_tokens")) |v| {
                if (v == .integer) usage.cache_write = @intCast(v.integer);
            }
        }
    }

    var model_out: []const u8 = "";
    if (parsed.value.object.get("model")) |m| {
        if (m == .string) model_out = try gpa.dupe(u8, m.string);
    }

    var stop_reason: []const u8 = "";
    if (parsed.value.object.get("stop_reason")) |sr| {
        if (sr == .string) {
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
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "anthropic"),
        .model = model_out,
        .stop_reason = stop_reason,
        .usage = usage,
    };
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
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"max_tokens\":8192");
    if (stream) try w.writeAll(",\"stream\":true");
    if (thinking.anthropicBudget()) |budget| {
        try w.writeAll(",\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":");
        try w.print("{d}", .{budget});
        try w.writeAll("}");
    }

    var system_parts: std.ArrayList([]const u8) = .empty;
    defer system_parts.deinit(gpa);
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system")) {
            try system_parts.append(gpa, msg.content);
        }
    }
    if (system_parts.items.len > 0) {
        try w.writeAll(",\"system\":");
        if (system_parts.items.len == 1) {
            try std.json.Stringify.value(system_parts.items[0], .{}, w);
        } else {
            var joined: std.ArrayList(u8) = .empty;
            defer joined.deinit(gpa);
            for (system_parts.items, 0..) |p, i| {
                if (i > 0) try joined.appendSlice(gpa, "\n\n");
                try joined.appendSlice(gpa, p);
            }
            try std.json.Stringify.value(joined.items, .{}, w);
        }
    }

    try w.writeAll(",\"messages\":[");
    var first = true;
    for (messages) |msg| {
        if (std.mem.eql(u8, msg.role, "system")) continue;
        if (!first) try w.writeAll(",");
        first = false;

        if (std.mem.eql(u8, msg.role, "tool")) {
            try w.writeAll("{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":");
            try std.json.Stringify.value(msg.tool_call_id orelse "", .{}, w);
            try w.writeAll(",\"content\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeAll("}]}");
        } else if (std.mem.eql(u8, msg.role, "assistant") and msg.tool_calls_json != null) {
            try w.writeAll("{\"role\":\"assistant\",\"content\":[");
            if (msg.content.len > 0) {
                try w.writeAll("{\"type\":\"text\",\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll("},");
            }
            try appendAnthropicToolUses(gpa, w, msg.tool_calls_json.?);
            try w.writeAll("]}");
        } else {
            try w.writeAll("{\"role\":");
            try std.json.Stringify.value(msg.role, .{}, w);
            try w.writeAll(",\"content\":");
            try std.json.Stringify.value(msg.content, .{}, w);
            try w.writeAll("}");
        }
    }
    try w.writeAll("]");

    if (tools_json.len > 2) {
        const anthropic_tools = try convertToolsToAnthropic(gpa, tools_json);
        defer gpa.free(anthropic_tools);
        try w.writeAll(",\"tools\":");
        try w.writeAll(anthropic_tools);
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
        \\{"model":"claude-test","stop_reason":"tool_use","usage":{"input_tokens":3,"output_tokens":7},"content":[{"type":"text","text":"Working"},{"type":"tool_use","id":"tu1","name":"read","input":{"path":"a.txt"}}]}
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
