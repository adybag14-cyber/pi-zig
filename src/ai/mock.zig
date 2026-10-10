//! Scripted mock model from JSON file.
const std = @import("std");
const ai = @import("root.zig");

pub const MockResponse = struct {
    response: ai.ModelResponse,
    /// Optional text chunks for streaming simulation (owned).
    stream_chunks: []const []const u8 = &.{},
    stream_chunk_delay_ms: u32 = 0,
};

pub const MockModel = struct {
    responses: []MockResponse,
    index: usize = 0,
    last_completion_options: ai.CompletionOptions = .{},
    io: ?std.Io = null,

    pub fn bindIo(self: *MockModel, io: std.Io) void {
        self.io = io;
    }

    pub fn client(self: *MockModel) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
            .completeOptionsFn = completeOptionsImpl,
            .streamFn = streamImpl,
        };
    }

    fn takeNext(self: *MockModel, gpa: std.mem.Allocator) !ai.ModelResponse {
        const exhausted = self.index >= self.responses.len;
        const src: ai.ModelResponse = if (exhausted) .{ .content = "(mock exhausted)", .tool_calls = &.{}, .provider = "mock", .model = "mock", .stop_reason = "stop" } else self.responses[self.index].response;
        if (!exhausted) self.index += 1;
        var tcs = try gpa.alloc(ai.ToolCall, src.tool_calls.len);
        var initialized: usize = 0;
        errdefer {
            for (tcs[0..initialized]) |*tc| tc.deinit(gpa);
            gpa.free(tcs);
        }
        for (src.tool_calls, 0..) |tc, i| {
            tcs[i] = try cloneToolCall(gpa, tc);
            initialized += 1;
        }
        const stop: []const u8 = if (src.stop_reason.len > 0)
            src.stop_reason
        else if (src.tool_calls.len > 0)
            "toolUse"
        else
            "stop";
        const content = try gpa.dupe(u8, src.content);
        errdefer gpa.free(content);
        const provider = try gpa.dupe(u8, if (src.provider.len > 0) src.provider else "mock");
        errdefer gpa.free(provider);
        const model = try gpa.dupe(u8, if (src.model.len > 0) src.model else "mock");
        errdefer gpa.free(model);
        const stop_reason = try gpa.dupe(u8, stop);
        return .{
            .content = content,
            .tool_calls = tcs,
            .provider = provider,
            .model = model,
            .stop_reason = stop_reason,
            .usage = src.usage,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        return completeOptionsImpl(ptr, gpa, messages, tools_json, .{});
    }

    fn completeOptionsImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8, options: ai.CompletionOptions) anyerror!ai.ModelResponse {
        _ = messages;
        _ = tools_json;
        const self: *MockModel = @ptrCast(@alignCast(ptr));
        self.last_completion_options = options;
        return self.takeNext(gpa);
    }

    fn streamImpl(
        ptr: *anyopaque,
        gpa: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        _ = messages;
        _ = tools_json;
        const self: *MockModel = @ptrCast(@alignCast(ptr));
        // Peek current scripted response for chunks before advancing
        const idx = self.index;
        const chunks: []const []const u8 = if (idx < self.responses.len) self.responses[idx].stream_chunks else &.{};
        var resp = try self.takeNext(gpa);
        errdefer resp.deinit(gpa);
        if (on_delta) |h| {
            if (chunks.len > 0) {
                const delay = self.responses[idx].stream_chunk_delay_ms;
                for (chunks, 0..) |ch, chunk_index| {
                    if (chunk_index > 0 and delay > 0) {
                        const io = self.io orelse return error.MockClockUnavailable;
                        try io.sleep(.fromMilliseconds(delay), .awake);
                    }
                    h(delta_ctx, .{ .kind = .text_delta, .text = ch });
                }
            } else if (resp.content.len > 0) {
                // Split into ~half for multi-chunk simulation when no explicit chunks
                const mid = resp.content.len / 2;
                if (mid > 0) {
                    h(delta_ctx, .{ .kind = .text_delta, .text = resp.content[0..mid] });
                    h(delta_ctx, .{ .kind = .text_delta, .text = resp.content[mid..] });
                } else {
                    h(delta_ctx, .{ .kind = .text_delta, .text = resp.content });
                }
            }
            for (resp.tool_calls) |tc| {
                h(delta_ctx, .{
                    .kind = .tool_call_delta,
                    .tool_call_id = tc.id,
                    .tool_name = tc.name,
                    .tool_arguments = tc.arguments,
                });
            }
            h(delta_ctx, .{ .kind = .done });
        }
        return resp;
    }

    pub fn deinit(self: *MockModel, gpa: std.mem.Allocator) void {
        for (self.responses) |*r| {
            r.response.deinit(gpa);
            for (r.stream_chunks) |c| gpa.free(c);
            if (r.stream_chunks.len > 0) gpa.free(r.stream_chunks);
        }
        gpa.free(self.responses);
        self.* = undefined;
    }

    /// Format: [{"content":"...","tool_calls":[...],"stream_chunks":["Hel","lo"]}]
    pub fn loadFromJson(gpa: std.mem.Allocator, json_text: []const u8) !MockModel {
        var parsed = try std.json.parseFromSlice(std.json.Value, gpa, json_text, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return error.InvalidMockScript;

        var list: std.ArrayList(MockResponse) = .empty;
        errdefer {
            for (list.items) |*r| {
                r.response.deinit(gpa);
                for (r.stream_chunks) |c| gpa.free(c);
                if (r.stream_chunks.len > 0) gpa.free(r.stream_chunks);
            }
            list.deinit(gpa);
        }

        for (parsed.value.array.items) |item| {
            if (item != .object) return error.InvalidMockScript;
            const content_v = item.object.get("content") orelse return error.InvalidMockScript;
            if (content_v != .string) return error.InvalidMockScript;
            const delay_ms: u32 = if (item.object.get("stream_chunk_delay_ms")) |delay| blk: {
                if (delay != .integer or delay.integer < 0 or delay.integer > 60_000) return error.InvalidMockScript;
                break :blk @intCast(delay.integer);
            } else 0;

            var tcs: std.ArrayList(ai.ToolCall) = .empty;
            errdefer {
                for (tcs.items) |*tc| tc.deinit(gpa);
                tcs.deinit(gpa);
            }

            if (item.object.get("tool_calls")) |tc_val| {
                if (tc_val == .array) {
                    for (tc_val.array.items) |tc_item| {
                        if (tc_item != .object) return error.InvalidMockScript;
                        const id = tc_item.object.get("id") orelse return error.InvalidMockScript;
                        const name = tc_item.object.get("name") orelse return error.InvalidMockScript;
                        const args = tc_item.object.get("arguments") orelse return error.InvalidMockScript;
                        if (id != .string or name != .string or args != .string) return error.InvalidMockScript;
                        var owned = try cloneToolCall(gpa, .{ .id = id.string, .name = name.string, .arguments = args.string });
                        errdefer owned.deinit(gpa);
                        try tcs.append(gpa, owned);
                    }
                }
            }

            var chunks: std.ArrayList([]const u8) = .empty;
            errdefer {
                for (chunks.items) |c| gpa.free(c);
                chunks.deinit(gpa);
            }
            if (item.object.get("stream_chunks")) |sc| {
                if (sc == .array) {
                    for (sc.array.items) |ch| {
                        if (ch == .string) {
                            const owned = try gpa.dupe(u8, ch.string);
                            errdefer gpa.free(owned);
                            try chunks.append(gpa, owned);
                        }
                    }
                }
            }

            const stop_reason: []const u8 = if (item.object.get("stop_reason")) |sr|
                if (sr == .string) sr.string else ""
            else
                "";

            const content = try gpa.dupe(u8, content_v.string);
            errdefer gpa.free(content);
            const owned_stop = if (stop_reason.len > 0) try gpa.dupe(u8, stop_reason) else "";
            errdefer if (owned_stop.len > 0) gpa.free(owned_stop);
            const owned_calls = try tcs.toOwnedSlice(gpa);
            errdefer {
                for (owned_calls) |*tc| tc.deinit(gpa);
                gpa.free(owned_calls);
            }
            const owned_chunks = try chunks.toOwnedSlice(gpa);
            errdefer {
                for (owned_chunks) |chunk| gpa.free(chunk);
                gpa.free(owned_chunks);
            }
            try list.append(gpa, .{ .response = .{ .content = content, .tool_calls = owned_calls, .stop_reason = owned_stop }, .stream_chunks = owned_chunks, .stream_chunk_delay_ms = delay_ms });
        }

        return .{
            .responses = try list.toOwnedSlice(gpa),
            .index = 0,
        };
    }
};

fn cloneToolCall(gpa: std.mem.Allocator, source: ai.ToolCall) !ai.ToolCall {
    const id = try gpa.dupe(u8, source.id);
    errdefer gpa.free(id);
    const name = try gpa.dupe(u8, source.name);
    errdefer gpa.free(name);
    const arguments = try gpa.dupe(u8, source.arguments);
    return .{ .id = id, .name = name, .arguments = arguments };
}

fn allocationCase(gpa: std.mem.Allocator) !void {
    var mock = try MockModel.loadFromJson(gpa, "[{\"content\":\"paced text\",\"stream_chunks\":[\"paced \",\"text\"],\"stream_chunk_delay_ms\":1,\"tool_calls\":[{\"id\":\"one\",\"name\":\"read\",\"arguments\":\"{}\"}]}]");
    defer mock.deinit(gpa);
    var response = try mock.takeNext(gpa);
    defer response.deinit(gpa);
    try std.testing.expectEqualStrings("paced text", response.content);
}
test "paced native mock parsing and response ownership release every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
    for ([_][]const u8{ "-1", "60001", "true", "\"1\"" }) |value| {
        const json = try std.fmt.allocPrint(std.testing.allocator, "[{{\"content\":\"x\",\"stream_chunk_delay_ms\":{s}}}]", .{value});
        defer std.testing.allocator.free(json);
        try std.testing.expectError(error.InvalidMockScript, MockModel.loadFromJson(std.testing.allocator, json));
    }
}

test "mock model returns scripted tool call then final" {
    const gpa = std.testing.allocator;
    const script =
        \\[
        \\  {"content":"calling write","tool_calls":[{"id":"c1","name":"write","arguments":"{\"path\":\"a.txt\",\"content\":\"x\"}"}]},
        \\  {"content":"all done","tool_calls":[]}
        \\]
    ;
    var m = try MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    const c = m.client();

    var r1 = try c.complete(gpa, &.{}, "[]");
    defer r1.deinit(gpa);
    try std.testing.expectEqualStrings("calling write", r1.content);
    try std.testing.expectEqual(@as(usize, 1), r1.tool_calls.len);
    try std.testing.expectEqualStrings("write", r1.tool_calls[0].name);

    var r2 = try c.complete(gpa, &.{}, "[]");
    defer r2.deinit(gpa);
    try std.testing.expectEqualStrings("all done", r2.content);
    try std.testing.expectEqual(@as(usize, 0), r2.tool_calls.len);
}

test "mock stream emits multi-chunk text then tool call" {
    const gpa = std.testing.allocator;
    const script =
        \\[
        \\  {"content":"Hello world","stream_chunks":["Hello ","world"],"tool_calls":[{"id":"c1","name":"ls","arguments":"{}"}]},
        \\  {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);

    var chunks: std.ArrayList([]const u8) = .empty;
    defer {
        for (chunks.items) |c| gpa.free(c);
        chunks.deinit(gpa);
    }
    const Ctx = struct {
        gpa: std.mem.Allocator,
        chunks: *std.ArrayList([]const u8),
        tools: usize = 0,
        fn onDelta(ptr: ?*anyopaque, d: ai.StreamDelta) void {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (d.kind == .text_delta and d.text.len > 0) {
                self.chunks.append(self.gpa, self.gpa.dupe(u8, d.text) catch return) catch {};
            }
            if (d.kind == .tool_call_delta) self.tools += 1;
        }
    };
    var ctx = Ctx{ .gpa = gpa, .chunks = &chunks };
    var r = try m.client().completeStreaming(gpa, &.{}, "[]", Ctx.onDelta, &ctx);
    defer r.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), chunks.items.len);
    try std.testing.expectEqualStrings("Hello ", chunks.items[0]);
    try std.testing.expectEqualStrings("world", chunks.items[1]);
    try std.testing.expect(ctx.tools >= 1);
    try std.testing.expectEqualStrings("Hello world", r.content);
}
