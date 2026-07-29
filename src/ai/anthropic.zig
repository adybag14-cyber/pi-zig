//! Anthropic Messages API + tools.
const std = @import("std");
const Io = std.Io;
const ai = @import("root.zig");

pub const AnthropicClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,

    pub fn client(self: *AnthropicClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        const self: *AnthropicClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json);
    }

    fn request(self: *AnthropicClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) !ai.ModelResponse {
        const payload = try buildRequestBody(gpa, self.model, messages, tools_json);
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/v1/messages", .{self.base_url});
        defer gpa.free(url);

        var http_client: std.http.Client = .{
            .allocator = gpa,
            .io = self.io,
        };
        defer http_client.deinit();

        var response_body: std.Io.Writer.Allocating = .init(gpa);
        defer response_body.deinit();

        const headers = [_]std.http.Header{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
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

        return try parseAnthropicResponse(gpa, response_json);
    }
};

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

    return .{
        .content = try text_parts.toOwnedSlice(gpa),
        .tool_calls = try tcs.toOwnedSlice(gpa),
    };
}

/// Build Anthropic /v1/messages JSON body (caller frees).
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
    try w.writeAll(",\"max_tokens\":8192");

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
    try std.testing.expect(std.mem.indexOf(u8, body, "\"input_schema\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"read\"") != null);
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
        \\{"content":[{"type":"text","text":"Working"},{"type":"tool_use","id":"tu1","name":"read","input":{"path":"a.txt"}}]}
    ;
    var resp = try parseAnthropicResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("Working", resp.content);
    try std.testing.expectEqual(@as(usize, 1), resp.tool_calls.len);
    try std.testing.expectEqualStrings("read", resp.tool_calls[0].name);
    try std.testing.expect(std.mem.indexOf(u8, resp.tool_calls[0].arguments, "a.txt") != null);
}
