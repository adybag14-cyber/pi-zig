//! Agent loop with tool filter, turn limit, events.
const std = @import("std");
const Io = std.Io;
const tools = @import("tools.zig");
const session_mod = @import("session.zig");
const ai = @import("../ai/root.zig");

pub const default_system_prompt =
    \\You are pi, a coding agent. Use the provided tools (read, write, edit, bash, grep, find, ls) to fulfill the user's request.
    \\Be concise. Prefer tools over inventing file contents.
;

pub const AgentConfig = struct {
    max_turns: usize = 16,
    system_prompt: []const u8 = default_system_prompt,
    context_prompt: []const u8 = "",
    tool_filter: tools.ToolFilter = .{},
    verbose: bool = false,
};

pub const EventKind = enum {
    user,
    assistant,
    tool_call,
    tool_result,
    done,
    turn_limit,
};

pub const AgentEvent = struct {
    kind: EventKind,
    text: []const u8 = "",
    name: []const u8 = "",
    id: []const u8 = "",
};

pub const EventHandler = *const fn (ctx: ?*anyopaque, event: AgentEvent) void;

pub const RunResult = struct {
    final_text: []u8,
    turns: usize,
    hit_turn_limit: bool,

    pub fn deinit(self: *RunResult, gpa: std.mem.Allocator) void {
        gpa.free(self.final_text);
        self.* = undefined;
    }
};

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *session_mod.Session,
    user_message: []const u8,
    config: AgentConfig,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !RunResult {
    const parent = sess.lastEntryId();
    _ = try sess.appendMessage(parent, "user", user_message, null, null);
    emit(on_event, event_ctx, .{ .kind = .user, .text = user_message });

    const schemas = try tools.toolSchemasJson(gpa, config.tool_filter);
    defer gpa.free(schemas);

    var turns: usize = 0;
    var last_text: []u8 = try gpa.dupe(u8, "");
    errdefer gpa.free(last_text);

    while (turns < config.max_turns) : (turns += 1) {
        const chat = try buildChatMessages(gpa, sess, config);
        defer freeChatMessages(gpa, chat);

        var response = try client.complete(gpa, chat, schemas);
        defer response.deinit(gpa);

        var tool_calls_json: ?[]u8 = null;
        defer if (tool_calls_json) |t| gpa.free(t);
        if (response.tool_calls.len > 0) {
            tool_calls_json = try serializeToolCallsOpenAI(gpa, response.tool_calls);
        }

        const prev = sess.lastEntryId();
        _ = try sess.appendMessage(prev, "assistant", response.content, null, tool_calls_json);

        gpa.free(last_text);
        last_text = try gpa.dupe(u8, response.content);
        emit(on_event, event_ctx, .{ .kind = .assistant, .text = response.content });

        if (response.tool_calls.len == 0) {
            emit(on_event, event_ctx, .{ .kind = .done, .text = last_text });
            return .{
                .final_text = last_text,
                .turns = turns + 1,
                .hit_turn_limit = false,
            };
        }

        const tool_ctx = tools.ToolContext{ .gpa = gpa, .io = io, .cwd = cwd };
        for (response.tool_calls) |tc| {
            emit(on_event, event_ctx, .{ .kind = .tool_call, .name = tc.name, .id = tc.id, .text = tc.arguments });

            var result: tools.ToolResult = undefined;
            if (!config.tool_filter.isEnabled(tc.name)) {
                result = .{
                    .content = try std.fmt.allocPrint(gpa, "tool disabled: {s}", .{tc.name}),
                    .is_error = true,
                };
            } else {
                result = try tools.execute(tool_ctx, tc.name, tc.arguments);
            }
            defer result.deinit(gpa);

            emit(on_event, event_ctx, .{ .kind = .tool_result, .name = tc.name, .id = tc.id, .text = result.content });

            const p = sess.lastEntryId();
            _ = try sess.appendMessage(p, "tool", result.content, tc.id, null);
        }
    }

    emit(on_event, event_ctx, .{ .kind = .turn_limit, .text = last_text });
    return .{
        .final_text = last_text,
        .turns = turns,
        .hit_turn_limit = true,
    };
}

fn emit(handler: ?EventHandler, ctx: ?*anyopaque, event: AgentEvent) void {
    if (handler) |h| h(ctx, event);
}

fn buildChatMessages(gpa: std.mem.Allocator, sess: *session_mod.Session, config: AgentConfig) ![]ai.ChatMessage {
    var list: std.ArrayList(ai.ChatMessage) = .empty;
    errdefer list.deinit(gpa);

    const system_body = if (config.context_prompt.len > 0)
        try std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ config.system_prompt, config.context_prompt })
    else
        try gpa.dupe(u8, config.system_prompt);
    try list.append(gpa, .{
        .role = "system",
        .content = system_body,
    });

    // Prefer active branch if tree exists
    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);
    if (branch.len > 0) {
        for (branch) |e| {
            if (std.mem.eql(u8, e.role, "user") or
                std.mem.eql(u8, e.role, "assistant") or
                std.mem.eql(u8, e.role, "tool") or
                std.mem.eql(u8, e.role, "system"))
            {
                try list.append(gpa, .{
                    .role = e.role,
                    .content = e.content,
                    .tool_call_id = e.tool_call_id,
                    .tool_calls_json = e.tool_calls_json,
                });
            }
        }
    } else {
        for (sess.entries.items) |e| {
            if (std.mem.eql(u8, e.role, "user") or
                std.mem.eql(u8, e.role, "assistant") or
                std.mem.eql(u8, e.role, "tool"))
            {
                try list.append(gpa, .{
                    .role = e.role,
                    .content = e.content,
                    .tool_call_id = e.tool_call_id,
                    .tool_calls_json = e.tool_calls_json,
                });
            }
        }
    }

    return try list.toOwnedSlice(gpa);
}

fn freeChatMessages(gpa: std.mem.Allocator, messages: []ai.ChatMessage) void {
    if (messages.len > 0) {
        gpa.free(messages[0].content);
    }
    gpa.free(messages);
}

fn serializeToolCallsOpenAI(gpa: std.mem.Allocator, tcs: []const ai.ToolCall) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.writeAll("[");
    for (tcs, 0..) |tc, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"id\":");
        try std.json.Stringify.value(tc.id, .{}, &aw.writer);
        try aw.writer.writeAll(",\"type\":\"function\",\"function\":{\"name\":");
        try std.json.Stringify.value(tc.name, .{}, &aw.writer);
        try aw.writer.writeAll(",\"arguments\":");
        try std.json.Stringify.value(tc.arguments, .{}, &aw.writer);
        try aw.writer.writeAll("}}");
    }
    try aw.writer.writeAll("]");
    return try aw.toOwnedSlice();
}

test "agent loop executes tool then finishes with mock model" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script =
        \\[
        \\  {"content":"Writing marker.","tool_calls":[{"id":"c1","name":"write","arguments":"{\"path\":\"marker.txt\",\"content\":\"agent-loop-ok\"}"}]},
        \\  {"content":"Marker written successfully.","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);

    var sess = try session_mod.Session.init(gpa, "test-loop", tmp_path);
    defer sess.deinit();

    var result = try run(gpa, io, tmp_path, m.client(), &sess, "write a marker file", .{}, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqualStrings("Marker written successfully.", result.final_text);
    try std.testing.expect(!result.hit_turn_limit);
    try std.testing.expect(result.turns >= 2);

    const marker_path = try std.fs.path.join(gpa, &.{ tmp_path, "marker.txt" });
    defer gpa.free(marker_path);
    const data = try std.Io.Dir.cwd().readFileAlloc(io, marker_path, gpa, .limited(1024));
    defer gpa.free(data);
    try std.testing.expectEqualStrings("agent-loop-ok", data);
}

/// Records the system message content from the first complete() call.
const SystemRecorder = struct {
    last_system: ?[]u8 = null,
    gpa: std.mem.Allocator,

    fn deinit(self: *SystemRecorder) void {
        if (self.last_system) |s| self.gpa.free(s);
        self.* = undefined;
    }

    fn client(self: *SystemRecorder) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        _ = tools_json;
        const self: *SystemRecorder = @ptrCast(@alignCast(ptr));
        if (messages.len > 0 and std.mem.eql(u8, messages[0].role, "system")) {
            if (self.last_system) |old| self.gpa.free(old);
            self.last_system = try self.gpa.dupe(u8, messages[0].content);
        }
        return .{
            .content = try gpa.dupe(u8, "ok"),
            .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        };
    }
};

test "updated agent_cfg.context_prompt appears in next chat system message" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var sess = try session_mod.Session.init(gpa, "sys-rec", tmp_path);
    defer sess.deinit();

    var recorder = SystemRecorder{ .gpa = gpa };
    defer recorder.deinit();

    var cfg = AgentConfig{
        .system_prompt = "BASE",
        .context_prompt = "CONTEXT-V1",
    };
    var result1 = try run(gpa, io, tmp_path, recorder.client(), &sess, "hi", cfg, null, null);
    defer result1.deinit(gpa);
    try std.testing.expect(recorder.last_system != null);
    try std.testing.expect(std.mem.indexOf(u8, recorder.last_system.?, "CONTEXT-V1") != null);

    // Simulate /reload applying new context into agent_cfg
    cfg.context_prompt = "CONTEXT-V2-RELOADED";
    var result2 = try run(gpa, io, tmp_path, recorder.client(), &sess, "again", cfg, null, null);
    defer result2.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, recorder.last_system.?, "CONTEXT-V2-RELOADED") != null);
}
