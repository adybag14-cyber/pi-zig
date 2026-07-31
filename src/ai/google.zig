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
        const self: *GoogleClient = @ptrCast(@alignCast(ptr));
        return self.request(gpa, messages, tools_json);
    }

    fn request(self: *GoogleClient, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) !ai.ModelResponse {
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
            if (std.mem.eql(u8, msg.role, "tool")) {
                // functionResponse part — use real tool name when available
                try w.writeAll("{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"name\":");
                try std.json.Stringify.value(msg.tool_name orelse msg.tool_call_id orelse "tool", .{}, w);
                try w.writeAll(",\"response\":{\"content\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll("}}}]}");
            } else if (std.mem.eql(u8, msg.role, "assistant") and msg.tool_calls_json != null) {
                try w.writeAll("{\"role\":\"model\",\"parts\":[");
                if (msg.content.len > 0) {
                    try w.writeAll("{\"text\":");
                    try std.json.Stringify.value(msg.content, .{}, w);
                    try w.writeAll("},");
                }
                try appendGoogleFunctionCalls(gpa, w, msg.tool_calls_json.?);
                try w.writeAll("]}");
            } else {
                const role = if (std.mem.eql(u8, msg.role, "assistant")) "model" else "user";
                try w.writeAll("{\"role\":");
                try std.json.Stringify.value(role, .{}, w);
                try w.writeAll(",\"parts\":[{\"text\":");
                try std.json.Stringify.value(msg.content, .{}, w);
                try w.writeAll("}]}");
            }
        }
        try w.writeAll("]");
        // functionDeclarations from OpenAI-style tools_json
        if (tools_json.len > 2) {
            if (try convertToolsToGoogle(gpa, tools_json)) |decls| {
                defer gpa.free(decls);
                try w.writeAll(",\"tools\":[{\"functionDeclarations\":");
                try w.writeAll(decls);
                try w.writeAll("}]");
            }
        }
        try w.writeAll("}");

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

        var attempt: u32 = 0;
        var last_status: u16 = 0;
        while (attempt < 3) : (attempt += 1) {
            if (attempt > 0) {
                response_body.deinit();
                response_body = .init(gpa);
                const ms: i64 = 400 * (@as(i64, 1) << @intCast(attempt - 1));
                const backoff: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(ms), .clock = .real } };
                backoff.sleep(self.io) catch {};
            }
            const fetch_result = try http_client.fetch(.{
                .location = .{ .url = url },
                .method = .POST,
                .payload = payload,
                .keep_alive = false,
                .extra_headers = &headers,
                .response_writer = &response_body.writer,
            });
            last_status = @intCast(@intFromEnum(fetch_result.status));
            if (last_status >= 200 and last_status < 300) break;
            if ((last_status == 429 or last_status >= 500) and attempt + 1 < 3) continue;
            const response_json = try response_body.toOwnedSlice();
            defer gpa.free(response_json);
            const snippet = if (response_json.len > 800) response_json[0..800] else response_json;
            const content = try std.fmt.allocPrint(gpa, "HTTP {d} from google: {s}", .{ last_status, snippet });
            return .{
                .content = content,
                .tool_calls = try gpa.alloc(ai.ToolCall, 0),
                .provider = try gpa.dupe(u8, "google"),
                .model = try gpa.dupe(u8, self.model),
                .stop_reason = try gpa.dupe(u8, "error"),
            };
        }

        const response_json = try response_body.toOwnedSlice();
        defer gpa.free(response_json);

        var resp = try parseGoogleResponse(gpa, response_json);
        if (resp.provider.len == 0) resp.provider = try gpa.dupe(u8, "google");
        if (resp.model.len == 0) resp.model = try gpa.dupe(u8, self.model);
        try resp.ensureStopReason(gpa);
        return resp;
    }
};

fn appendGoogleFunctionCalls(gpa: std.mem.Allocator, w: anytype, tool_calls_json: []const u8) !void {
    _ = gpa;
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, tool_calls_json, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const id = item.object.get("id");
        const fn_obj = item.object.get("function");
        if (fn_obj == null or fn_obj.? != .object) continue;
        const name = fn_obj.?.object.get("name");
        const args = fn_obj.?.object.get("arguments");
        if (name == null or name.? != .string) continue;
        if (!first) try w.writeAll(",");
        first = false;
        try w.writeAll("{\"functionCall\":{\"name\":");
        try std.json.Stringify.value(name.?.string, .{}, w);
        try w.writeAll(",\"args\":");
        if (args != null and args.? == .string) {
            // arguments is JSON string — embed raw
            try w.writeAll(args.?.string);
        } else {
            try w.writeAll("{}");
        }
        try w.writeAll("}");
        _ = id;
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
                if (text.items.len > 0) try text.appendSlice(gpa, "\n");
                try text.appendSlice(gpa, t.string);
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
                const id = try std.fmt.allocPrint(gpa, "gcall_{d}", .{call_i});
                call_i += 1;
                try tcs.append(gpa, .{
                    .id = id,
                    .name = try gpa.dupe(u8, name),
                    .arguments = try args_aw.toOwnedSlice(),
                });
            }
        }
    }

    return .{
        .content = try text.toOwnedSlice(gpa),
        .tool_calls = try tcs.toOwnedSlice(gpa),
        .provider = try gpa.dupe(u8, "google"),
        .stop_reason = try gpa.dupe(u8, if (call_i > 0) "toolUse" else "stop"),
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
