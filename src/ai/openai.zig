//! OpenAI-compatible chat completions + tools.
const std = @import("std");
const Io = std.Io;
const ai = @import("root.zig");

pub const OpenAIClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,

    pub fn client(self: *OpenAIClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        const self: *OpenAIClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json);
    }

    fn request(self: *OpenAIClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) !ai.ModelResponse {
        const payload = try buildRequestBody(gpa, self.model, messages, tools_json);
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/chat/completions", .{self.base_url});
        defer gpa.free(url);

        var http_client: std.http.Client = .{
            .allocator = gpa,
            .io = self.io,
        };
        defer http_client.deinit();

        var response_body: std.Io.Writer.Allocating = .init(gpa);
        defer response_body.deinit();

        const authorization = try std.fmt.allocPrint(gpa, "Bearer {s}", .{self.api_key});
        defer gpa.free(authorization);

        const headers = [_]std.http.Header{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "authorization", .value = authorization },
        };

        const fetch_result = try http_client.fetch(.{
            .location = .{ .url = url },
            .method = .POST,
            .payload = payload,
            .keep_alive = false,
            .extra_headers = &headers,
            .response_writer = &response_body.writer,
        });

        const status: u16 = @intCast(@intFromEnum(fetch_result.status));
        const response_json = try response_body.toOwnedSlice();
        defer gpa.free(response_json);

        if (status < 200 or status >= 300) {
            return error.HttpError;
        }

        return try parseOpenAIResponse(gpa, response_json);
    }
};

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

    return .{
        .content = try gpa.dupe(u8, content),
        .tool_calls = try tcs.toOwnedSlice(gpa),
    };
}

/// Build OpenAI chat/completions JSON body (caller frees).
pub fn buildRequestBody(
    gpa: std.mem.Allocator,
    model: []const u8,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
) ![]u8 {
    var body: std.Io.Writer.Allocating = .init(gpa);
    errdefer body.deinit();
    const w = &body.writer;

    try w.writeAll("{\"model\":");
    try std.json.Stringify.value(model, .{}, w);
    try w.writeAll(",\"messages\":[");
    for (messages, 0..) |msg, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"role\":");
        try std.json.Stringify.value(msg.role, .{}, w);
        try w.writeAll(",\"content\":");
        try std.json.Stringify.value(msg.content, .{}, w);
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
        \\{"choices":[{"message":{"role":"assistant","content":"hi","tool_calls":[{"id":"call_1","type":"function","function":{"name":"read","arguments":"{\"path\":\"f\"}"}}]}}]}
    ;
    var resp = try parseOpenAIResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hi", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
}
