//! Deep-clone helpers for Pi protocol values.
//!
//! The wire decoder intentionally owns a whole message in one arena. Higher
//! level clients, transcript reducers and session controllers often need to
//! retain only one nested value after the decoder advances. These helpers copy
//! every string, slice, JSON array/object and optional field into a caller
//! supplied allocator so ownership is explicit and independent of the frame.
const std = @import("std");
const msg = @import("messages.zig");

pub fn jsonValue(allocator: std.mem.Allocator, value: msg.JsonValue) !msg.JsonValue {
    return switch (value) {
        .null => .null,
        .bool => |inner| .{ .bool = inner },
        .integer => |inner| .{ .integer = inner },
        .float => |inner| .{ .float = inner },
        .number_string => |inner| .{ .number_string = try allocator.dupe(u8, inner) },
        .string => |inner| .{ .string = try allocator.dupe(u8, inner) },
        .array => |inner| blk: {
            var out = std.json.Array.init(allocator);
            errdefer out.deinit();
            try out.ensureTotalCapacity(inner.items.len);
            for (inner.items) |item| try out.append(try jsonValue(allocator, item));
            break :blk .{ .array = out };
        },
        .object => |inner| blk: {
            var out: std.json.ObjectMap = .empty;
            errdefer out.deinit(allocator);
            var iterator = inner.iterator();
            while (iterator.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                errdefer allocator.free(key);
                try out.put(allocator, key, try jsonValue(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = out };
        },
    };
}

pub fn modelRef(allocator: std.mem.Allocator, value: msg.ModelRef) !msg.ModelRef {
    return .{
        .provider = try allocator.dupe(u8, value.provider),
        .id = try allocator.dupe(u8, value.id),
    };
}

pub fn modelMetadata(allocator: std.mem.Allocator, value: msg.ModelMetadata) !msg.ModelMetadata {
    return .{
        .provider = try allocator.dupe(u8, value.provider),
        .id = try allocator.dupe(u8, value.id),
        .name = try allocator.dupe(u8, value.name),
        .api = try allocator.dupe(u8, value.api),
        .reasoning = value.reasoning,
        .input_text = value.input_text,
        .input_image = value.input_image,
        .context_window = value.context_window,
        .max_tokens = value.max_tokens,
        .cost = value.cost,
        .supported_thinking_levels = try allocator.dupe(msg.ThinkingLevel, value.supported_thinking_levels),
        .authenticated = value.authenticated,
    };
}

fn textContent(allocator: std.mem.Allocator, value: msg.TextContent) !msg.TextContent {
    return .{ .text = try allocator.dupe(u8, value.text) };
}

fn thinkingContent(allocator: std.mem.Allocator, value: msg.ThinkingContent) !msg.ThinkingContent {
    return .{ .thinking = try allocator.dupe(u8, value.thinking), .redacted = value.redacted };
}

fn imageContent(allocator: std.mem.Allocator, value: msg.ImageContent) !msg.ImageContent {
    return .{
        .data = try allocator.dupe(u8, value.data),
        .mime_type = try allocator.dupe(u8, value.mime_type),
    };
}

fn toolCallContent(allocator: std.mem.Allocator, value: msg.ToolCallContent) !msg.ToolCallContent {
    return .{
        .tool_call_id = try allocator.dupe(u8, value.tool_call_id),
        .tool_name = try allocator.dupe(u8, value.tool_name),
        .input = try jsonValue(allocator, value.input),
    };
}

pub fn userContent(allocator: std.mem.Allocator, value: msg.UserContent) !msg.UserContent {
    return switch (value) {
        .text => |inner| .{ .text = try textContent(allocator, inner) },
        .image => |inner| .{ .image = try imageContent(allocator, inner) },
    };
}

pub fn assistantContent(allocator: std.mem.Allocator, value: msg.AssistantContent) !msg.AssistantContent {
    return switch (value) {
        .text => |inner| .{ .text = try textContent(allocator, inner) },
        .thinking => |inner| .{ .thinking = try thinkingContent(allocator, inner) },
        .toolCall => |inner| .{ .toolCall = try toolCallContent(allocator, inner) },
    };
}

pub fn toolContent(allocator: std.mem.Allocator, value: msg.ToolContent) !msg.ToolContent {
    return switch (value) {
        .text => |inner| .{ .text = try textContent(allocator, inner) },
        .image => |inner| .{ .image = try imageContent(allocator, inner) },
    };
}

pub fn userItem(allocator: std.mem.Allocator, value: msg.UserTranscriptItem) !msg.UserTranscriptItem {
    const content = try allocator.alloc(msg.UserContent, value.content.len);
    for (value.content, 0..) |part, index| content[index] = try userContent(allocator, part);
    return .{
        .id = try allocator.dupe(u8, value.id),
        .content = content,
        .timestamp = value.timestamp,
    };
}

pub fn assistantItem(allocator: std.mem.Allocator, value: msg.AssistantTranscriptItem) !msg.AssistantTranscriptItem {
    const content = try allocator.alloc(msg.AssistantContent, value.content.len);
    for (value.content, 0..) |part, index| content[index] = try assistantContent(allocator, part);
    return .{
        .id = try allocator.dupe(u8, value.id),
        .content = content,
        .model = try modelRef(allocator, value.model),
        .response_model = if (value.response_model) |inner| try allocator.dupe(u8, inner) else null,
        .usage = value.usage,
        .timestamp = value.timestamp,
        .status = value.status,
        .stop_reason = value.stop_reason,
        .error_message = if (value.error_message) |inner| try allocator.dupe(u8, inner) else null,
    };
}

pub fn toolItem(allocator: std.mem.Allocator, value: msg.ToolTranscriptItem) !msg.ToolTranscriptItem {
    const content = try allocator.alloc(msg.ToolContent, value.content.len);
    for (value.content, 0..) |part, index| content[index] = try toolContent(allocator, part);
    return .{
        .id = try allocator.dupe(u8, value.id),
        .tool_call_id = try allocator.dupe(u8, value.tool_call_id),
        .tool_name = try allocator.dupe(u8, value.tool_name),
        .input = try jsonValue(allocator, value.input),
        .content = content,
        .details = if (value.details) |inner| try jsonValue(allocator, inner) else null,
        .usage = value.usage,
        .timestamp = value.timestamp,
        .status = value.status,
        .is_error = value.is_error,
    };
}

pub fn transcriptItem(allocator: std.mem.Allocator, value: msg.TranscriptItem) !msg.TranscriptItem {
    return switch (value) {
        .user => |inner| .{ .user = try userItem(allocator, inner) },
        .assistant => |inner| .{ .assistant = try assistantItem(allocator, inner) },
        .tool => |inner| .{ .tool = try toolItem(allocator, inner) },
    };
}

pub fn transcriptProgress(allocator: std.mem.Allocator, value: msg.TranscriptProgress) !msg.TranscriptProgress {
    return switch (value) {
        .item_started => |inner| .{ .item_started = try transcriptItem(allocator, inner) },
        .item_updated => |inner| .{ .item_updated = try transcriptItem(allocator, inner) },
        .item_finished => |inner| .{ .item_finished = try transcriptItem(allocator, inner) },
        .assistant_delta => |inner| .{ .assistant_delta = .{
            .message_id = try allocator.dupe(u8, inner.message_id),
            .content_index = inner.content_index,
            .kind = inner.kind,
            .delta = try allocator.dupe(u8, inner.delta),
        } },
    };
}

pub fn sessionMetadata(allocator: std.mem.Allocator, value: msg.SessionMetadata) !msg.SessionMetadata {
    return .{
        .id = try allocator.dupe(u8, value.id),
        .created_at = value.created_at,
        .updated_at = value.updated_at,
        .parent_session_id = if (value.parent_session_id) |inner| try allocator.dupe(u8, inner) else null,
        .session_name = if (value.session_name) |inner| try allocator.dupe(u8, inner) else null,
        .cwd = if (value.cwd) |inner| try allocator.dupe(u8, inner) else null,
    };
}

pub fn sessionSnapshot(allocator: std.mem.Allocator, value: msg.SessionSnapshot) !msg.SessionSnapshot {
    const transcript = try allocator.alloc(msg.TranscriptItem, value.transcript.len);
    for (value.transcript, 0..) |item, index| transcript[index] = try transcriptItem(allocator, item);
    const queued = try allocator.alloc(msg.UserTranscriptItem, value.queued_steer.len);
    for (value.queued_steer, 0..) |item, index| queued[index] = try userItem(allocator, item);
    return .{
        .id = try allocator.dupe(u8, value.id),
        .name = if (value.name) |inner| try allocator.dupe(u8, inner) else null,
        .cwd = try allocator.dupe(u8, value.cwd),
        .created_at = value.created_at,
        .updated_at = value.updated_at,
        .phase = value.phase,
        .model = try modelRef(allocator, value.model),
        .thinking_level = value.thinking_level,
        .attached = value.attached,
        .locked = value.locked,
        .revision = value.revision,
        .transcript = transcript,
        .queued_steer = queued,
        .queued_steer_count = value.queued_steer_count,
    };
}

pub fn serverSnapshot(allocator: std.mem.Allocator, value: msg.ServerSnapshot) !msg.ServerSnapshot {
    const sessions = try allocator.alloc(msg.SessionMetadata, value.sessions.len);
    for (value.sessions, 0..) |session, index| sessions[index] = try sessionMetadata(allocator, session);
    const models = try allocator.alloc(msg.ModelMetadata, value.models.len);
    for (value.models, 0..) |model, index| models[index] = try modelMetadata(allocator, model);
    return .{
        .server_id = try allocator.dupe(u8, value.server_id),
        .protocol_version = value.protocol_version,
        .revision = value.revision,
        .sessions = sessions,
        .models = models,
    };
}

pub fn protocolError(allocator: std.mem.Allocator, value: msg.ProtocolError) !msg.ProtocolError {
    return .{
        .code = value.code,
        .message = try allocator.dupe(u8, value.message),
        .details = if (value.details) |inner| try jsonValue(allocator, inner) else null,
    };
}

pub fn commandResult(allocator: std.mem.Allocator, value: msg.CommandResult) !msg.CommandResult {
    return switch (value) {
        .list => |inner| blk: {
            const sessions = try allocator.alloc(msg.SessionMetadata, inner.sessions.len);
            for (inner.sessions, 0..) |session, index| sessions[index] = try sessionMetadata(allocator, session);
            break :blk .{ .list = .{ .sessions = sessions } };
        },
        .create => |inner| .{ .create = try sessionSnapshot(allocator, inner) },
        .attach => |inner| .{ .attach = try sessionSnapshot(allocator, inner) },
        .detach => |inner| .{ .detach = .{ .session_id = try allocator.dupe(u8, inner.session_id) } },
        .prompt => |inner| .{ .prompt = try sessionSnapshot(allocator, inner) },
        .steer => |inner| .{ .steer = try sessionSnapshot(allocator, inner) },
        .abort => |inner| .{ .abort = try sessionSnapshot(allocator, inner) },
        .set_model => |inner| .{ .set_model = try sessionSnapshot(allocator, inner) },
        .set_thinking => |inner| .{ .set_thinking = try sessionSnapshot(allocator, inner) },
    };
}

pub fn serverEvent(allocator: std.mem.Allocator, value: msg.ServerEvent) !msg.ServerEvent {
    return switch (value) {
        .server_snapshot => |inner| .{ .server_snapshot = try serverSnapshot(allocator, inner) },
        .session_snapshot => |inner| .{ .session_snapshot = try sessionSnapshot(allocator, inner) },
        .session_progress => |inner| .{ .session_progress = .{
            .session_id = try allocator.dupe(u8, inner.session_id),
            .progress = try transcriptProgress(allocator, inner.progress),
        } },
        .session_removed => |inner| .{ .session_removed = .{ .session_id = try allocator.dupe(u8, inner.session_id) } },
    };
}

fn sampleToolInput(allocator: std.mem.Allocator) !msg.JsonValue {
    var object: std.json.ObjectMap = .empty;
    const nested = std.json.Array.init(allocator);
    try object.put(allocator, try allocator.dupe(u8, "path"), .{ .string = try allocator.dupe(u8, "/tmp/a") });
    try object.put(allocator, try allocator.dupe(u8, "nested"), .{ .array = nested });
    return .{ .object = object };
}

test "protocol clone owns nested transcript strings and JSON" {
    const gpa = std.testing.allocator;
    var source_arena = std.heap.ArenaAllocator.init(gpa);
    defer source_arena.deinit();
    const source = source_arena.allocator();
    const input = try sampleToolInput(source);
    const item: msg.TranscriptItem = .{ .tool = .{
        .id = try source.dupe(u8, "tool-1"),
        .tool_call_id = try source.dupe(u8, "call-1"),
        .tool_name = try source.dupe(u8, "read"),
        .input = input,
        .content = &.{.{ .text = .{ .text = "done" } }},
        .timestamp = 7,
        .status = .complete,
        .is_error = false,
    } };

    var target_arena = std.heap.ArenaAllocator.init(gpa);
    defer target_arena.deinit();
    const cloned = try transcriptItem(target_arena.allocator(), item);
    try std.testing.expect(cloned == .tool);
    try std.testing.expectEqualStrings("tool-1", cloned.tool.id);
    try std.testing.expect(cloned.tool.id.ptr != item.tool.id.ptr);
    try std.testing.expectEqualStrings("/tmp/a", cloned.tool.input.object.get("path").?.string);
    try std.testing.expect(cloned.tool.input.object.get("path").?.string.ptr != item.tool.input.object.get("path").?.string.ptr);
}

test "protocol clone preserves complete snapshots and optional fields" {
    const gpa = std.testing.allocator;
    const assistant: msg.TranscriptItem = .{ .assistant = .{
        .id = "assistant-1",
        .content = &.{
            .{ .thinking = .{ .thinking = "reason", .redacted = false } },
            .{ .text = .{ .text = "answer" } },
        },
        .model = .{ .provider = "openai", .id = "gpt" },
        .response_model = "gpt-build",
        .timestamp = 9,
        .status = .complete,
        .stop_reason = .stop,
    } };
    const source: msg.SessionSnapshot = .{
        .id = "session-1",
        .name = "clone test",
        .cwd = "/work",
        .created_at = 1,
        .updated_at = 2,
        .phase = .idle,
        .model = .{ .provider = "openai", .id = "gpt" },
        .thinking_level = .high,
        .attached = true,
        .locked = false,
        .revision = 3,
        .transcript = &.{assistant},
        .queued_steer = &.{.{ .id = "queued", .content = &.{.{ .text = .{ .text = "next" } }}, .timestamp = 10 }},
        .queued_steer_count = 1,
    };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const cloned = try sessionSnapshot(arena.allocator(), source);
    try std.testing.expectEqualStrings("clone test", cloned.name.?);
    try std.testing.expectEqual(msg.ThinkingLevel.high, cloned.thinking_level);
    try std.testing.expectEqualStrings("answer", cloned.transcript[0].assistant.content[1].text.text);
    try std.testing.expectEqualStrings("next", cloned.queued_steer[0].content[0].text.text);
    try std.testing.expect(cloned.id.ptr != source.id.ptr);
}
