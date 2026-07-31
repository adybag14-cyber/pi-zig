//! Scripted mock model from JSON file.
const std = @import("std");
const ai = @import("root.zig");

pub const MockResponse = struct {
    response: ai.ModelResponse,
    /// Optional text chunks for streaming simulation (owned).
    stream_chunks: []const []const u8 = &.{},
};

pub const MockModel = struct {
    responses: []MockResponse,
    index: usize = 0,

    pub fn client(self: *MockModel) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
            .streamFn = streamImpl,
        };
    }

    fn takeNext(self: *MockModel, gpa: std.mem.Allocator) !ai.ModelResponse {
        if (self.index >= self.responses.len) {
            return .{
                .content = try gpa.dupe(u8, "(mock exhausted)"),
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, "mock"),
                .model = try gpa.dupe(u8, "mock"),
                .stop_reason = try gpa.dupe(u8, "stop"),
            };
        }
        const src = self.responses[self.index].response;
        self.index += 1;
        var tcs = try gpa.alloc(ai.ToolCall, src.tool_calls.len);
        errdefer {
            for (tcs[0..]) |*tc| tc.deinit(gpa);
            gpa.free(tcs);
        }
        for (src.tool_calls, 0..) |tc, i| {
            tcs[i] = .{
                .id = try gpa.dupe(u8, tc.id),
                .name = try gpa.dupe(u8, tc.name),
                .arguments = try gpa.dupe(u8, tc.arguments),
            };
        }
        const stop: []const u8 = if (src.stop_reason.len > 0)
            src.stop_reason
        else if (src.tool_calls.len > 0)
            "toolUse"
        else
            "stop";
        return .{
            .content = try gpa.dupe(u8, src.content),
            .tool_calls = tcs,
            .provider = try gpa.dupe(u8, if (src.provider.len > 0) src.provider else "mock"),
            .model = try gpa.dupe(u8, if (src.model.len > 0) src.model else "mock"),
            .stop_reason = try gpa.dupe(u8, stop),
            .usage = src.usage,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        _ = messages;
        _ = tools_json;
        const self: *MockModel = @ptrCast(@alignCast(ptr));
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
        if (on_delta) |h| {
            if (chunks.len > 0) {
                for (chunks) |ch| {
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
                        try tcs.append(gpa, .{
                            .id = try gpa.dupe(u8, id.string),
                            .name = try gpa.dupe(u8, name.string),
                            .arguments = try gpa.dupe(u8, args.string),
                        });
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
                        if (ch == .string) try chunks.append(gpa, try gpa.dupe(u8, ch.string));
                    }
                }
            }

            try list.append(gpa, .{
                .response = .{
                    .content = try gpa.dupe(u8, content_v.string),
                    .tool_calls = try tcs.toOwnedSlice(gpa),
                },
                .stream_chunks = try chunks.toOwnedSlice(gpa),
            });
        }

        return .{
            .responses = try list.toOwnedSlice(gpa),
            .index = 0,
        };
    }
};

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
