//! print / json event stream / rpc JSONL modes (aligned with pi-main docs for core path).
const std = @import("std");
const Io = std.Io;
const agent_loop = @import("../agent/loop.zig");
const session_mod = @import("../agent/session.zig");
const tui_render = @import("../tui/render.zig");

pub const JsonEmitter = struct {
    io: Io,
    session_id: []const u8 = "",
    cwd: []const u8 = "",
    emitted_header: bool = false,

    pub fn emitHeader(self: *JsonEmitter) void {
        if (self.emitted_header) return;
        self.emitted_header = true;
        var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer aw.deinit();
        aw.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":") catch return;
        std.json.Stringify.value(self.session_id, .{}, &aw.writer) catch return;
        // Non-1970 timestamp for protocol clients (monotonic wallish stamp)
        aw.writer.writeAll(",\"timestamp\":") catch return;
        {
            var ts_buf: [32]u8 = undefined;
            const ts = session_mod.formatIsoNow(&ts_buf);
            std.json.Stringify.value(ts, .{}, &aw.writer) catch return;
        }
        aw.writer.writeAll(",\"cwd\":") catch return;
        std.json.Stringify.value(self.cwd, .{}, &aw.writer) catch return;
        aw.writer.writeAll("}\n") catch return;
        tui_render.writeAll(self.io, aw.written()) catch {};
    }

    pub fn emitRaw(self: JsonEmitter, line: []const u8) void {
        tui_render.writeAll(self.io, line) catch {};
        tui_render.writeAll(self.io, "\n") catch {};
    }

    pub fn onEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *JsonEmitter = @ptrCast(@alignCast(ctx.?));
        self.emitHeader();

        var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer aw.deinit();

        switch (event.kind) {
            .agent_start => {
                aw.writer.writeAll("{\"type\":\"agent_start\"}\n") catch return;
            },
            .agent_end => {
                aw.writer.writeAll("{\"type\":\"agent_end\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":") catch return;
                std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}]}]}\n") catch return;
            },
            .turn_start => {
                aw.writer.writeAll("{\"type\":\"turn_start\"}\n") catch return;
            },
            .turn_end => {
                // Include final assistant text when present for protocol clients
                aw.writer.writeAll("{\"type\":\"turn_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":") catch return;
                std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}]},\"toolResults\":[]}\n") catch return;
            },
            .message_start => {
                aw.writer.writeAll("{\"type\":\"message_start\",\"message\":{\"role\":") catch return;
                std.json.Stringify.value(if (event.name.len > 0) event.name else "assistant", .{}, &aw.writer) catch return;
                if (event.text.len > 0) {
                    aw.writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":") catch return;
                    std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                    aw.writer.writeAll("}]}}\n") catch return;
                } else {
                    aw.writer.writeAll(",\"content\":[]}}\n") catch return;
                }
            },
            .message_update => {
                aw.writer.writeAll("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":") catch return;
                std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}}\n") catch return;
            },
            .message_end => {
                aw.writer.writeAll("{\"type\":\"message_end\",\"message\":{\"role\":") catch return;
                std.json.Stringify.value(if (event.name.len > 0) event.name else "assistant", .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"content\":[{\"type\":\"text\",\"text\":") catch return;
                std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}]}}\n") catch return;
            },
            .tool_execution_start => {
                aw.writer.writeAll("{\"type\":\"tool_execution_start\",\"toolCallId\":") catch return;
                std.json.Stringify.value(event.id, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"toolName\":") catch return;
                std.json.Stringify.value(event.name, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"args\":") catch return;
                // args may already be JSON object string
                if (event.args_json.len > 0 and event.args_json[0] == '{') {
                    aw.writer.writeAll(event.args_json) catch return;
                } else {
                    std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                }
                aw.writer.writeAll("}\n") catch return;
            },
            .tool_execution_end => {
                aw.writer.writeAll("{\"type\":\"tool_execution_end\",\"toolCallId\":") catch return;
                std.json.Stringify.value(event.id, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"toolName\":") catch return;
                std.json.Stringify.value(event.name, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"isError\":") catch return;
                aw.writer.writeAll(if (event.is_error) "true" else "false") catch return;
                aw.writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":") catch return;
                std.json.Stringify.value(event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}]}}\n") catch return;
            },
            // Legacy aliases: loop already emits agent_end; skip .done to avoid duplicate agent_end.
            .done, .user, .assistant, .tool_call, .tool_result, .turn_limit => return,
        }
        tui_render.writeAll(self.io, aw.written()) catch {};
    }
};

pub const PrintEmitter = struct {
    io: Io,
    verbose: bool = false,

    pub fn onEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *PrintEmitter = @ptrCast(@alignCast(ctx.?));
        switch (event.kind) {
            .message_update => {
                if (self.verbose) tui_render.writeAll(self.io, event.text) catch {};
            },
            .assistant => {
                if (self.verbose) tui_render.renderAssistant(self.io, event.text) catch {};
            },
            .tool_execution_start, .tool_call => {
                if (self.verbose) tui_render.renderToolCall(self.io, event.name, event.text) catch {};
            },
            .tool_execution_end, .tool_result => {
                if (self.verbose) tui_render.renderToolResult(self.io, event.name, event.text, event.is_error) catch {};
            },
            else => {},
        }
    }
};

pub const RpcRequest = struct {
    id: []const u8,
    /// Normalized command name: prompt, ping, quit, get_state, set_model, …
    method: []const u8,
    params_prompt: ?[]const u8 = null,
    /// set_model / cycle_model
    provider: ?[]const u8 = null,
    model_id: ?[]const u8 = null,
    /// set_thinking_level
    thinking_level: ?[]const u8 = null,
};

fn dupeOptString(gpa: std.mem.Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return try gpa.dupe(u8, v.string);
}

fn extractRpcExtras(gpa: std.mem.Allocator, obj: std.json.ObjectMap, req: *RpcRequest) !void {
    // Top-level fields (upstream rpc.md)
    if (try dupeOptString(gpa, obj, "message")) |m| {
        if (req.params_prompt == null) req.params_prompt = m else gpa.free(m);
    }
    if (try dupeOptString(gpa, obj, "provider")) |p| req.provider = p;
    if (try dupeOptString(gpa, obj, "modelId") orelse try dupeOptString(gpa, obj, "model")) |m| req.model_id = m;
    if (try dupeOptString(gpa, obj, "thinkingLevel") orelse try dupeOptString(gpa, obj, "level")) |t| req.thinking_level = t;

    // Nested params object (legacy + some clients)
    if (obj.get("params")) |params| {
        if (params == .object) {
            if (try dupeOptString(gpa, params.object, "prompt") orelse
                try dupeOptString(gpa, params.object, "text") orelse
                try dupeOptString(gpa, params.object, "message")) |p|
            {
                if (req.params_prompt == null) req.params_prompt = p else gpa.free(p);
            }
            if (req.provider == null) {
                if (try dupeOptString(gpa, params.object, "provider")) |p| req.provider = p;
            }
            if (req.model_id == null) {
                if (try dupeOptString(gpa, params.object, "modelId") orelse try dupeOptString(gpa, params.object, "model")) |m| req.model_id = m;
            }
            if (req.thinking_level == null) {
                if (try dupeOptString(gpa, params.object, "thinkingLevel") orelse try dupeOptString(gpa, params.object, "level")) |t| req.thinking_level = t;
            }
        } else if (params == .string and req.params_prompt == null) {
            req.params_prompt = try gpa.dupe(u8, params.string);
        }
    }
}

/// Parse one JSONL RPC line supporting:
/// - upstream: {"type":"prompt","message":"...","id":"..."}
/// - legacy:  {"id":"...","method":"prompt","params":{"prompt":"..."}}
pub fn parseRpcLine(gpa: std.mem.Allocator, line: []const u8) !RpcRequest {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, line, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidRpc;

    var id_owned: []u8 = undefined;
    if (parsed.value.object.get("id")) |id_v| {
        id_owned = switch (id_v) {
            .string => |s| try gpa.dupe(u8, s),
            .integer => |i| try std.fmt.allocPrint(gpa, "{d}", .{i}),
            else => try gpa.dupe(u8, ""),
        };
    } else {
        id_owned = try gpa.dupe(u8, "");
    }
    errdefer gpa.free(id_owned);

    var req: RpcRequest = .{
        .id = id_owned,
        .method = undefined,
    };

    // Upstream style: type field is the command
    if (parsed.value.object.get("type")) |tv| {
        if (tv == .string) {
            req.method = try gpa.dupe(u8, tv.string);
            try extractRpcExtras(gpa, parsed.value.object, &req);
            return req;
        }
    }

    // Legacy method style
    const method_v = parsed.value.object.get("method") orelse return error.InvalidRpc;
    if (method_v != .string) return error.InvalidRpc;
    req.method = try gpa.dupe(u8, method_v.string);
    try extractRpcExtras(gpa, parsed.value.object, &req);
    return req;
}

pub fn freeRpcRequest(gpa: std.mem.Allocator, req: *RpcRequest) void {
    gpa.free(req.id);
    gpa.free(req.method);
    if (req.params_prompt) |p| gpa.free(p);
    if (req.provider) |p| gpa.free(p);
    if (req.model_id) |m| gpa.free(m);
    if (req.thinking_level) |t| gpa.free(t);
    req.* = undefined;
}

/// Upstream-shaped response: {"type":"response","command":"...","success":true,"id":"..."}
pub fn writeRpcResponse(io: Io, id: []const u8, command: []const u8, success: bool, data_json: ?[]const u8) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"type\":\"response\",\"command\":");
    try std.json.Stringify.value(command, .{}, &aw.writer);
    try aw.writer.writeAll(",\"success\":");
    try aw.writer.writeAll(if (success) "true" else "false");
    if (id.len > 0) {
        try aw.writer.writeAll(",\"id\":");
        try std.json.Stringify.value(id, .{}, &aw.writer);
    }
    if (data_json) |d| {
        try aw.writer.writeAll(",\"data\":");
        try aw.writer.writeAll(d);
    }
    try aw.writer.writeAll("}\n");
    try tui_render.writeAll(io, aw.written());
}

pub fn writeRpcResult(io: Io, id: []const u8, result_text: []const u8) !void {
    // Legacy helper — map to typed response with result in data
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"result\":");
    try std.json.Stringify.value(result_text, .{}, &aw.writer);
    try aw.writer.writeAll("}");
    const data = aw.written();
    try writeRpcResponse(io, id, "prompt", true, data);
}

pub fn writeRpcError(io: Io, id: []const u8, message: []const u8) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"error\":");
    try std.json.Stringify.value(message, .{}, &aw.writer);
    try aw.writer.writeAll("}");
    try writeRpcResponse(io, id, "error", false, aw.written());
}

/// RPC event passthrough using JsonEmitter shapes.
pub const RpcEventEmitter = struct {
    io: Io,
    json: JsonEmitter,

    pub fn init(io: Io) RpcEventEmitter {
        return .{ .io = io, .json = .{ .io = io } };
    }

    pub fn onEvent(ctx: ?*anyopaque, event: agent_loop.AgentEvent) void {
        const self: *RpcEventEmitter = @ptrCast(@alignCast(ctx.?));
        JsonEmitter.onEvent(&self.json, event);
    }
};

test "parse rpc prompt upstream type field" {
    const gpa = std.testing.allocator;
    var req = try parseRpcLine(gpa,
        \\{"id":"req-1","type":"prompt","message":"Hello, world!"}
    );
    defer freeRpcRequest(gpa, &req);
    try std.testing.expectEqualStrings("req-1", req.id);
    try std.testing.expectEqualStrings("prompt", req.method);
    try std.testing.expectEqualStrings("Hello, world!", req.params_prompt.?);
}

test "parse rpc prompt legacy method" {
    const gpa = std.testing.allocator;
    var req = try parseRpcLine(gpa,
        \\{"id":"1","method":"prompt","params":{"prompt":"hi"}}
    );
    defer freeRpcRequest(gpa, &req);
    try std.testing.expectEqualStrings("1", req.id);
    try std.testing.expectEqualStrings("prompt", req.method);
    try std.testing.expectEqualStrings("hi", req.params_prompt.?);
}

test "parse rpc set_model and set_thinking_level fields" {
    const gpa = std.testing.allocator;
    var r1 = try parseRpcLine(gpa,
        \\{"id":"m1","type":"set_model","provider":"openai","modelId":"gpt-4o"}
    );
    defer freeRpcRequest(gpa, &r1);
    try std.testing.expectEqualStrings("set_model", r1.method);
    try std.testing.expectEqualStrings("openai", r1.provider.?);
    try std.testing.expectEqualStrings("gpt-4o", r1.model_id.?);

    var r2 = try parseRpcLine(gpa,
        \\{"id":"t1","type":"set_thinking_level","thinkingLevel":"high"}
    );
    defer freeRpcRequest(gpa, &r2);
    try std.testing.expectEqualStrings("set_thinking_level", r2.method);
    try std.testing.expectEqualStrings("high", r2.thinking_level.?);
}
