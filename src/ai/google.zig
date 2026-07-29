//! Google Generative Language API (generateContent) — text responses.
const std = @import("std");
const Io = std.Io;
const ai = @import("root.zig");

pub const GoogleClient = struct {
    gpa: std.mem.Allocator,
    io: Io,
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,

    pub fn client(self: *GoogleClient) ai.ModelClient {
        return .{
            .ptr = self,
            .completeFn = completeImpl,
        };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        _ = tools_json; // basic text path; tools optional later
        const self: *GoogleClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages);
    }

    fn request(self: *GoogleClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage) !ai.ModelResponse {
        var body: std.Io.Writer.Allocating = .init(gpa);
        defer body.deinit();
        const w = &body.writer;

        // systemInstruction from system messages
        var system_text: ?[]const u8 = null;
        for (messages) |msg| {
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
        var first = true;
        for (messages) |msg| {
            if (std.mem.eql(u8, msg.role, "system")) continue;
            if (!first) try w.writeAll(",");
            first = false;
            const role = if (std.mem.eql(u8, msg.role, "assistant")) "model" else "user";
            // Fold tool results into user text
            try w.writeAll("{\"role\":");
            try std.json.Stringify.value(role, .{}, w);
            try w.writeAll(",\"parts\":[{\"text\":");
            if (std.mem.eql(u8, msg.role, "tool")) {
                const wrapped = try std.fmt.allocPrint(gpa, "[tool {s}] {s}", .{ msg.tool_call_id orelse "?", msg.content });
                defer gpa.free(wrapped);
                try std.json.Stringify.value(wrapped, .{}, w);
            } else {
                try std.json.Stringify.value(msg.content, .{}, w);
            }
            try w.writeAll("}]}");
        }
        try w.writeAll("]}");

        const payload = try body.toOwnedSlice();
        defer gpa.free(payload);

        const url = try std.fmt.allocPrint(gpa, "{s}/models/{s}:generateContent?key={s}", .{ self.base_url, self.model, self.api_key });
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

        return try parseGoogleResponse(gpa, response_json);
    }
};

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
    for (parts.array.items) |part| {
        if (part != .object) continue;
        if (part.object.get("text")) |t| {
            if (t == .string) {
                if (text.items.len > 0) try text.appendSlice(gpa, "\n");
                try text.appendSlice(gpa, t.string);
            }
        }
    }

    return .{
        .content = try text.toOwnedSlice(gpa),
        .tool_calls = try gpa.alloc(ai.ToolCall, 0),
    };
}

test "parseGoogleResponse extracts text" {
    const gpa = std.testing.allocator;
    const sample =
        \\{"candidates":[{"content":{"parts":[{"text":"hello gemini"}]}}]}
    ;
    var resp = try parseGoogleResponse(gpa, sample);
    defer resp.deinit(gpa);
    try std.testing.expectEqualStrings("hello gemini", resp.content);
    try std.testing.expectEqual(@as(usize, 0), resp.tool_calls.len);
}
