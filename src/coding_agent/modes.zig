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
            .tool_execution_update => {
                aw.writer.writeAll("{\"type\":\"tool_execution_update\",\"toolCallId\":") catch return;
                std.json.Stringify.value(event.id, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"toolName\":") catch return;
                std.json.Stringify.value(event.name, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"args\":") catch return;
                if (event.args_json.len > 0 and event.args_json[0] == '{')
                    aw.writer.writeAll(event.args_json) catch return
                else
                    aw.writer.writeAll("{}") catch return;
                aw.writer.writeAll(",\"partialResult\":") catch return;
                writeToolResultObject(&aw.writer, event) catch return;
                aw.writer.writeAll("}\n") catch return;
            },
            .tool_execution_end => {
                aw.writer.writeAll("{\"type\":\"tool_execution_end\",\"toolCallId\":") catch return;
                std.json.Stringify.value(event.id, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"toolName\":") catch return;
                std.json.Stringify.value(event.name, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"isError\":") catch return;
                aw.writer.writeAll(if (event.is_error) "true" else "false") catch return;
                aw.writer.writeAll(",\"result\":") catch return;
                writeToolResultObject(&aw.writer, event) catch return;
                aw.writer.writeAll("}\n") catch return;
            },
            .auto_retry_start => {
                aw.writer.print("{{\"type\":\"auto_retry_start\",\"attempt\":{d},\"maxAttempts\":{d},\"delayMs\":{d},\"errorMessage\":", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                }) catch return;
                std.json.Stringify.value(event.error_message orelse event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}\n") catch return;
            },
            .auto_retry_end => {
                aw.writer.print("{{\"type\":\"auto_retry_end\",\"success\":{s},\"attempt\":{d}", .{
                    if (event.success) "true" else "false",
                    event.attempt,
                }) catch return;
                if (event.final_error) |final_error| {
                    aw.writer.writeAll(",\"finalError\":") catch return;
                    std.json.Stringify.value(final_error, .{}, &aw.writer) catch return;
                }
                aw.writer.writeAll("}\n") catch return;
            },
            .summarization_retry_scheduled => {
                aw.writer.print("{{\"type\":\"summarization_retry_scheduled\",\"attempt\":{d},\"maxAttempts\":{d},\"delayMs\":{d},\"errorMessage\":", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                }) catch return;
                std.json.Stringify.value(event.error_message orelse event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}\n") catch return;
            },
            .summarization_retry_attempt_start => {
                aw.writer.writeAll("{\"type\":\"summarization_retry_attempt_start\",\"source\":") catch return;
                std.json.Stringify.value(event.source, .{}, &aw.writer) catch return;
                if (std.mem.eql(u8, event.source, "compaction")) {
                    aw.writer.writeAll(",\"reason\":") catch return;
                    std.json.Stringify.value(event.reason, .{}, &aw.writer) catch return;
                }
                aw.writer.writeAll("}\n") catch return;
            },
            .summarization_retry_finished => {
                aw.writer.writeAll("{\"type\":\"summarization_retry_finished\"}\n") catch return;
            },
            .session_compact_failed => {
                aw.writer.writeAll("{\"type\":\"session_compact_failed\",\"source\":") catch return;
                std.json.Stringify.value(event.source, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"reason\":") catch return;
                std.json.Stringify.value(event.reason, .{}, &aw.writer) catch return;
                aw.writer.writeAll(",\"willRetry\":") catch return;
                aw.writer.writeAll(if (event.will_retry) "true" else "false") catch return;
                aw.writer.writeAll(",\"error\":") catch return;
                std.json.Stringify.value(event.error_message orelse event.text, .{}, &aw.writer) catch return;
                aw.writer.writeAll("}\n") catch return;
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
            .tool_execution_update, .tool_execution_end, .tool_result => {
                if (self.verbose) tui_render.renderToolResult(self.io, event.name, event.text, event.is_error) catch {};
            },
            .auto_retry_start => if (self.verbose) {
                var buf: [256]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "retry {d}/{d} in {d}ms: {s}", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                    event.error_message orelse event.text,
                }) catch return;
                tui_render.printLine(self.io, line) catch {};
            },
            .auto_retry_end => if (self.verbose) {
                var buf: [192]u8 = undefined;
                const line = if (event.success)
                    std.fmt.bufPrint(&buf, "retry succeeded after attempt {d}", .{event.attempt}) catch return
                else
                    std.fmt.bufPrint(&buf, "retry ended after attempt {d}: {s}", .{ event.attempt, event.final_error orelse event.text }) catch return;
                tui_render.printLine(self.io, line) catch {};
            },
            .summarization_retry_scheduled => if (self.verbose) {
                var buf: [320]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "summary retry {d}/{d} in {d}ms: {s}", .{
                    event.attempt,
                    event.max_attempts,
                    event.delay_ms,
                    event.error_message orelse event.text,
                }) catch return;
                tui_render.printLine(self.io, line) catch {};
            },
            .summarization_retry_attempt_start => if (self.verbose) {
                var buf: [160]u8 = undefined;
                const line = if (std.mem.eql(u8, event.source, "branchSummary"))
                    std.fmt.bufPrint(&buf, "retrying branch summary", .{}) catch return
                else
                    std.fmt.bufPrint(&buf, "retrying {s} compaction", .{event.reason}) catch return;
                tui_render.printLine(self.io, line) catch {};
            },
            .summarization_retry_finished => {},
            .session_compact_failed => if (self.verbose) {
                var buf: [256]u8 = undefined;
                const line = std.fmt.bufPrint(&buf, "{s} compaction failed: {s}", .{ event.reason, event.error_message orelse event.text }) catch return;
                tui_render.printLine(self.io, line) catch {};
            },
            else => {},
        }
    }
};

fn writeToolResultObject(writer: *std.Io.Writer, event: agent_loop.AgentEvent) !void {
    try writer.writeAll("{\"content\":[");
    var wrote = false;
    if (event.text.len > 0 or (event.image_b64 == null and event.images.len == 0)) {
        try writer.writeAll("{\"type\":\"text\",\"text\":");
        try std.json.Stringify.value(event.text, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    if (event.image_b64) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(event.image_mime orelse "image/png", .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    for (event.images) |image| {
        if (wrote) try writer.writeByte(',');
        try writer.writeAll("{\"type\":\"image\",\"data\":");
        try std.json.Stringify.value(image.data_b64, .{}, writer);
        try writer.writeAll(",\"mimeType\":");
        try std.json.Stringify.value(image.mime_type, .{}, writer);
        try writer.writeByte('}');
        wrote = true;
    }
    try writer.writeAll("],\"details\":");
    if (event.details_json) |details|
        try writer.writeAll(details)
    else
        try writer.writeAll("null");
    try writer.writeAll(",\"isError\":");
    try writer.writeAll(if (event.is_error) "true" else "false");
    if (event.usage) |usage| {
        try writer.writeAll(",\"usage\":");
        try writeUsageObject(writer, usage, true);
    }
    if (event.added_tool_names.len > 0) {
        try writer.writeAll(",\"addedToolNames\":[");
        for (event.added_tool_names, 0..) |name, index| {
            if (index > 0) try writer.writeByte(',');
            try std.json.Stringify.value(name, .{}, writer);
        }
        try writer.writeByte(']');
    }
    try writer.writeByte('}');
}

fn writeUsageObject(writer: *std.Io.Writer, usage: anytype, include_cache_write_1h: bool) !void {
    try writer.print("{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
        usage.input,
        usage.output,
        usage.cache_read,
        usage.cache_write,
    });
    if (include_cache_write_1h) {
        if (usage.cache_write_1h) |tokens| try writer.print(",\"cacheWrite1h\":{d}", .{tokens});
    }
    if (usage.reasoning) |tokens| try writer.print(",\"reasoning\":{d}", .{tokens});
    try writer.print(",\"totalTokens\":{d},\"cost\":{{\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d},\"total\":{d}}}}}", .{
        usage.total(),
        usage.cost.input,
        usage.cost.output,
        usage.cost.cache_read,
        usage.cost.cache_write,
        usage.cost.total,
    });
}

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
    /// Queue-mode commands.
    mode: ?[]const u8 = null,
    /// Direct bash command.
    shell_command: ?[]const u8 = null,
    custom_instructions: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    session_path: ?[]const u8 = null,
    entry_id: ?[]const u8 = null,
    since: ?[]const u8 = null,
    name: ?[]const u8 = null,
    parent_session: ?[]const u8 = null,
    streaming_behavior: ?[]const u8 = null,
    enabled: ?bool = null,
    exclude_from_context: ?bool = null,
};

fn dupeOptString(gpa: std.mem.Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return try gpa.dupe(u8, v.string);
}

fn optBool(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    if (v != .bool) return null;
    return v.bool;
}

fn setStringIfMissing(
    gpa: std.mem.Allocator,
    field: *?[]const u8,
    value: ?[]const u8,
) void {
    if (value) |owned| {
        if (field.* == null) field.* = owned else gpa.free(owned);
    }
}

fn extractRpcObject(gpa: std.mem.Allocator, obj: std.json.ObjectMap, req: *RpcRequest) !void {
    setStringIfMissing(gpa, &req.params_prompt, try dupeOptString(gpa, obj, "message"));
    setStringIfMissing(gpa, &req.params_prompt, try dupeOptString(gpa, obj, "prompt"));
    setStringIfMissing(gpa, &req.params_prompt, try dupeOptString(gpa, obj, "text"));
    setStringIfMissing(gpa, &req.provider, try dupeOptString(gpa, obj, "provider"));
    setStringIfMissing(gpa, &req.model_id, try dupeOptString(gpa, obj, "modelId"));
    setStringIfMissing(gpa, &req.model_id, try dupeOptString(gpa, obj, "model"));
    setStringIfMissing(gpa, &req.thinking_level, try dupeOptString(gpa, obj, "thinkingLevel"));
    setStringIfMissing(gpa, &req.thinking_level, try dupeOptString(gpa, obj, "level"));
    setStringIfMissing(gpa, &req.mode, try dupeOptString(gpa, obj, "mode"));
    setStringIfMissing(gpa, &req.shell_command, try dupeOptString(gpa, obj, "command"));
    setStringIfMissing(gpa, &req.custom_instructions, try dupeOptString(gpa, obj, "customInstructions"));
    setStringIfMissing(gpa, &req.output_path, try dupeOptString(gpa, obj, "outputPath"));
    setStringIfMissing(gpa, &req.session_path, try dupeOptString(gpa, obj, "sessionPath"));
    setStringIfMissing(gpa, &req.entry_id, try dupeOptString(gpa, obj, "entryId"));
    setStringIfMissing(gpa, &req.since, try dupeOptString(gpa, obj, "since"));
    setStringIfMissing(gpa, &req.name, try dupeOptString(gpa, obj, "name"));
    setStringIfMissing(gpa, &req.parent_session, try dupeOptString(gpa, obj, "parentSession"));
    setStringIfMissing(gpa, &req.streaming_behavior, try dupeOptString(gpa, obj, "streamingBehavior"));
    if (req.enabled == null) req.enabled = optBool(obj, "enabled");
    if (req.exclude_from_context == null) req.exclude_from_context = optBool(obj, "excludeFromContext");
}

fn extractRpcExtras(gpa: std.mem.Allocator, obj: std.json.ObjectMap, req: *RpcRequest) !void {
    // Current upstream commands place parameters at the top level.
    try extractRpcObject(gpa, obj, req);

    // Legacy clients place the same fields under `params`.
    if (obj.get("params")) |params| {
        if (params == .object) {
            try extractRpcObject(gpa, params.object, req);
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

    var req: RpcRequest = blk: {
        const id_owned: []u8 = if (parsed.value.object.get("id")) |id_v|
            switch (id_v) {
                .string => |value| try gpa.dupe(u8, value),
                .integer => |value| try std.fmt.allocPrint(gpa, "{d}", .{value}),
                else => try gpa.dupe(u8, ""),
            }
        else
            try gpa.dupe(u8, "");
        errdefer gpa.free(id_owned);

        const method_value = parsed.value.object.get("type") orelse parsed.value.object.get("method") orelse return error.InvalidRpc;
        if (method_value != .string) return error.InvalidRpc;
        const method_owned = try gpa.dupe(u8, method_value.string);
        errdefer gpa.free(method_owned);
        break :blk .{ .id = id_owned, .method = method_owned };
    };
    errdefer freeRpcRequest(gpa, &req);
    try extractRpcExtras(gpa, parsed.value.object, &req);
    return req;
}

pub fn freeRpcRequest(gpa: std.mem.Allocator, req: *RpcRequest) void {
    gpa.free(req.id);
    gpa.free(req.method);
    if (req.params_prompt) |value| gpa.free(value);
    if (req.provider) |value| gpa.free(value);
    if (req.model_id) |value| gpa.free(value);
    if (req.thinking_level) |value| gpa.free(value);
    if (req.mode) |value| gpa.free(value);
    if (req.shell_command) |value| gpa.free(value);
    if (req.custom_instructions) |value| gpa.free(value);
    if (req.output_path) |value| gpa.free(value);
    if (req.session_path) |value| gpa.free(value);
    if (req.entry_id) |value| gpa.free(value);
    if (req.since) |value| gpa.free(value);
    if (req.name) |value| gpa.free(value);
    if (req.parent_session) |value| gpa.free(value);
    if (req.streaming_behavior) |value| gpa.free(value);
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

pub fn writeBashExecutionUpdate(io: Io, id: []const u8, delta: []const u8) !void {
    var aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer aw.deinit();
    try aw.writer.writeAll("{\"type\":\"bash_execution_update\"");
    if (id.len > 0) {
        try aw.writer.writeAll(",\"id\":");
        try std.json.Stringify.value(id, .{}, &aw.writer);
    }
    try aw.writer.writeAll(",\"delta\":");
    try std.json.Stringify.value(delta, .{}, &aw.writer);
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

test "tool result JSON preserves usage and added tool names" {
    const gpa = std.testing.allocator;
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try writeToolResultObject(&out.writer, .{
        .kind = .tool_execution_end,
        .text = "done",
        .image_b64 = "AA==",
        .image_mime = "image/png",
        .images = &.{.{ .data_b64 = @constCast("AQ=="), .mime_type = @constCast("image/jpeg") }},
        .usage = .{
            .input = 4,
            .output = 3,
            .cache_read = 2,
            .cache_write = 1,
            .cache_write_1h = 1,
            .reasoning = 2,
            .total_tokens = 10,
            .cost = .{ .input = 0.1, .output = 0.2, .cache_read = 0.3, .cache_write = 0.4, .total = 1.0 },
        },
        .added_tool_names = &.{ "alpha", "beta" },
    });
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, out.written(), .{});
    defer parsed.deinit();
    const content = parsed.value.object.get("content").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), content.len);
    try std.testing.expectEqualStrings("AA==", content[1].object.get("data").?.string);
    try std.testing.expectEqualStrings("AQ==", content[2].object.get("data").?.string);
    const usage = parsed.value.object.get("usage").?;
    try std.testing.expectEqual(@as(i64, 10), usage.object.get("totalTokens").?.integer);
    try std.testing.expectEqual(@as(i64, 1), usage.object.get("cacheWrite1h").?.integer);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.object.get("addedToolNames").?.array.items.len);
    try std.testing.expectEqualStrings("beta", parsed.value.object.get("addedToolNames").?.array.items[1].string);
}

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

test "parse rpc command-specific top-level and nested parameters" {
    const gpa = std.testing.allocator;
    var current = try parseRpcLine(gpa,
        \\{"id":9,"type":"bash","command":"pwd","excludeFromContext":true}
    );
    defer freeRpcRequest(gpa, &current);
    try std.testing.expectEqualStrings("9", current.id);
    try std.testing.expectEqualStrings("pwd", current.shell_command.?);
    try std.testing.expectEqual(true, current.exclude_from_context.?);

    var legacy = try parseRpcLine(gpa,
        \\{"method":"get_entries","params":{"since":"m4","enabled":false,"mode":"all"}}
    );
    defer freeRpcRequest(gpa, &legacy);
    try std.testing.expectEqualStrings("m4", legacy.since.?);
    try std.testing.expectEqual(false, legacy.enabled.?);
    try std.testing.expectEqualStrings("all", legacy.mode.?);
}
