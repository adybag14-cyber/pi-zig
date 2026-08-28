//! Strict parser for protocol-v1 server messages.
//! The returned message and every nested slice/value are owned by one arena so
//! callers can retain complex snapshots/events and release them deterministically.
const std = @import("std");
const msg = @import("messages.zig");

pub const ParseError = error{
    InvalidMessage,
    UnsupportedVersion,
};

pub const ParsedServerMessage = struct {
    arena: std.heap.ArenaAllocator,
    message: msg.ServerMessage,

    pub fn deinit(self: *ParsedServerMessage) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn parseServerMessage(backing_allocator: std.mem.Allocator, input: []const u8) !ParsedServerMessage {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const gpa = arena.allocator();
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, input, .{}) catch return ParseError.InvalidMessage;
    // Arena free is intentionally a no-op; retain all parsed string/object data.
    defer parsed.deinit();
    const object = try expectObject(parsed.value);
    const typ = try requiredString(object, "type", true);
    const message: msg.ServerMessage = if (std.mem.eql(u8, typ, "hello"))
        .{ .hello = try parseHello(gpa, object) }
    else if (std.mem.eql(u8, typ, "hello_error"))
        .{ .hello_error = try parseError(object) }
    else if (std.mem.eql(u8, typ, "response"))
        .{ .response = try parseResponse(gpa, object) }
    else if (std.mem.eql(u8, typ, "event"))
        .{ .event = try parseEvent(gpa, object) }
    else
        return ParseError.InvalidMessage;
    return .{ .arena = arena, .message = message };
}

fn parseHello(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.ServerHello {
    if (!onlyKeys(object, &.{ "type", "version", "connectionId", "snapshot" })) return ParseError.InvalidMessage;
    const version = try requiredU32(object, "version");
    if (version != msg.PROTOCOL_VERSION) return ParseError.UnsupportedVersion;
    return .{
        .version = version,
        .connection_id = try requiredString(object, "connectionId", true),
        .snapshot = try parseServerSnapshot(gpa, try requiredValue(object, "snapshot")),
    };
}

fn parseResponse(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.ResponseEnvelope {
    const ok = try requiredBool(object, "ok");
    const id = try requiredString(object, "id", true);
    if (ok) {
        if (!onlyKeys(object, &.{ "type", "id", "ok", "result" })) return ParseError.InvalidMessage;
        return .{ .ok = .{ .id = id, .result = try parseCommandResult(gpa, try requiredValue(object, "result")) } };
    }
    if (!onlyKeys(object, &.{ "type", "id", "ok", "error" })) return ParseError.InvalidMessage;
    return .{ .err = .{ .id = id, .error_info = try parseError(try expectObject(try requiredValue(object, "error"))) } };
}

fn parseEvent(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.ServerEvent {
    if (!onlyKeys(object, &.{ "type", "event" })) return ParseError.InvalidMessage;
    const event = try expectObject(try requiredValue(object, "event"));
    const typ = try requiredString(event, "type", true);
    if (std.mem.eql(u8, typ, "server_snapshot")) {
        if (!onlyKeys(event, &.{ "type", "snapshot" })) return ParseError.InvalidMessage;
        return .{ .server_snapshot = try parseServerSnapshot(gpa, try requiredValue(event, "snapshot")) };
    }
    if (std.mem.eql(u8, typ, "session_snapshot")) {
        if (!onlyKeys(event, &.{ "type", "snapshot" })) return ParseError.InvalidMessage;
        return .{ .session_snapshot = try parseSessionSnapshot(gpa, try requiredValue(event, "snapshot")) };
    }
    if (std.mem.eql(u8, typ, "session_progress")) {
        if (!onlyKeys(event, &.{ "type", "sessionId", "progress" })) return ParseError.InvalidMessage;
        return .{ .session_progress = .{
            .session_id = try requiredString(event, "sessionId", true),
            .progress = try parseProgress(gpa, try requiredValue(event, "progress")),
        } };
    }
    if (std.mem.eql(u8, typ, "session_removed")) {
        if (!onlyKeys(event, &.{ "type", "sessionId" })) return ParseError.InvalidMessage;
        return .{ .session_removed = .{ .session_id = try requiredString(event, "sessionId", true) } };
    }
    return ParseError.InvalidMessage;
}

fn parseCommandResult(gpa: std.mem.Allocator, value: std.json.Value) !msg.CommandResult {
    const object = try expectObject(value);
    const command_text = try requiredString(object, "command", true);
    const command = msg.parseCommandName(command_text) orelse return ParseError.InvalidMessage;
    return switch (command) {
        .list => blk: {
            if (!onlyKeys(object, &.{ "command", "sessions" })) return ParseError.InvalidMessage;
            break :blk .{ .list = .{ .sessions = try parseSessionMetadataArray(gpa, try requiredValue(object, "sessions")) } };
        },
        .detach => blk: {
            if (!onlyKeys(object, &.{ "command", "sessionId" })) return ParseError.InvalidMessage;
            break :blk .{ .detach = .{ .session_id = try requiredString(object, "sessionId", true) } };
        },
        .create, .attach, .prompt, .steer, .abort, .set_model, .set_thinking => blk: {
            if (!onlyKeys(object, &.{ "command", "session" })) return ParseError.InvalidMessage;
            const session = try parseSessionSnapshot(gpa, try requiredValue(object, "session"));
            break :blk switch (command) {
                .create => .{ .create = session },
                .attach => .{ .attach = session },
                .prompt => .{ .prompt = session },
                .steer => .{ .steer = session },
                .abort => .{ .abort = session },
                .set_model => .{ .set_model = session },
                .set_thinking => .{ .set_thinking = session },
                else => unreachable,
            };
        },
    };
}

fn parseServerSnapshot(gpa: std.mem.Allocator, value: std.json.Value) !msg.ServerSnapshot {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{ "serverId", "protocolVersion", "revision", "sessions", "models" })) return ParseError.InvalidMessage;
    const version = try requiredU32(object, "protocolVersion");
    if (version != msg.PROTOCOL_VERSION) return ParseError.UnsupportedVersion;
    return .{
        .server_id = try requiredString(object, "serverId", true),
        .protocol_version = version,
        .revision = try requiredU64(object, "revision"),
        .sessions = try parseSessionMetadataArray(gpa, try requiredValue(object, "sessions")),
        .models = try parseModelArray(gpa, try requiredValue(object, "models")),
    };
}

fn parseSessionMetadataArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.SessionMetadata {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.SessionMetadata, array.items.len);
    for (array.items, 0..) |item, index| out[index] = try parseSessionMetadata(item);
    return out;
}

fn parseSessionMetadata(value: std.json.Value) !msg.SessionMetadata {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{ "id", "createdAt", "updatedAt", "parentSessionId", "sessionName", "cwd" })) return ParseError.InvalidMessage;
    return .{
        .id = try requiredString(object, "id", true),
        .created_at = try requiredU64(object, "createdAt"),
        .updated_at = try optionalU64(object, "updatedAt"),
        .parent_session_id = try optionalString(object, "parentSessionId", true),
        .session_name = try optionalString(object, "sessionName", false),
        .cwd = try optionalString(object, "cwd", true),
    };
}

fn parseSessionSnapshot(gpa: std.mem.Allocator, value: std.json.Value) !msg.SessionSnapshot {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{
        "id", "name", "cwd", "createdAt", "updatedAt", "phase", "model", "thinkingLevel", "attached", "locked", "revision", "transcript", "queuedSteer", "queuedSteerCount",
    })) return ParseError.InvalidMessage;
    const queued = try parseUserItemArray(gpa, try requiredValue(object, "queuedSteer"));
    const queued_count = try requiredU64(object, "queuedSteerCount");
    if (queued_count != queued.len) return ParseError.InvalidMessage;
    return .{
        .id = try requiredString(object, "id", true),
        .name = try optionalString(object, "name", false),
        .cwd = try requiredString(object, "cwd", true),
        .created_at = try requiredU64(object, "createdAt"),
        .updated_at = try requiredU64(object, "updatedAt"),
        .phase = try parseEnum(msg.SessionPhase, try requiredString(object, "phase", true)),
        .model = try parseModelRef(try requiredValue(object, "model")),
        .thinking_level = try parseEnum(msg.ThinkingLevel, try requiredString(object, "thinkingLevel", true)),
        .attached = try requiredBool(object, "attached"),
        .locked = try requiredBool(object, "locked"),
        .revision = try requiredU64(object, "revision"),
        .transcript = try parseTranscriptArray(gpa, try requiredValue(object, "transcript")),
        .queued_steer = queued,
        .queued_steer_count = queued_count,
    };
}

fn parseModelRef(value: std.json.Value) !msg.ModelRef {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{ "provider", "id" })) return ParseError.InvalidMessage;
    return .{
        .provider = try requiredString(object, "provider", true),
        .id = try requiredString(object, "id", true),
    };
}

fn parseModelArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.ModelMetadata {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.ModelMetadata, array.items.len);
    for (array.items, 0..) |item, index| out[index] = try parseModel(gpa, item);
    return out;
}

fn parseModel(gpa: std.mem.Allocator, value: std.json.Value) !msg.ModelMetadata {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{ "provider", "id", "name", "api", "reasoning", "input", "contextWindow", "maxTokens", "cost", "supportedThinkingLevels", "authenticated" })) return ParseError.InvalidMessage;
    const input = try expectArray(try requiredValue(object, "input"));
    var input_text = false;
    var input_image = false;
    for (input.items) |item| {
        const label = try expectString(item, true);
        if (std.mem.eql(u8, label, "text")) input_text = true else if (std.mem.eql(u8, label, "image")) input_image = true else return ParseError.InvalidMessage;
    }
    const levels_array = try expectArray(try requiredValue(object, "supportedThinkingLevels"));
    if (levels_array.items.len == 0) return ParseError.InvalidMessage;
    const levels = try gpa.alloc(msg.ThinkingLevel, levels_array.items.len);
    for (levels_array.items, 0..) |item, index| levels[index] = try parseEnum(msg.ThinkingLevel, try expectString(item, true));
    const cost = try expectObject(try requiredValue(object, "cost"));
    if (!onlyKeys(cost, &.{ "input", "output", "cacheRead", "cacheWrite" })) return ParseError.InvalidMessage;
    return .{
        .provider = try requiredString(object, "provider", true),
        .id = try requiredString(object, "id", true),
        .name = try requiredString(object, "name", true),
        .api = try requiredString(object, "api", true),
        .reasoning = try requiredBool(object, "reasoning"),
        .input_text = input_text,
        .input_image = input_image,
        .context_window = try requiredPositiveU64(object, "contextWindow"),
        .max_tokens = try requiredPositiveU64(object, "maxTokens"),
        .cost = .{
            .input = try requiredNonnegativeNumber(cost, "input"),
            .output = try requiredNonnegativeNumber(cost, "output"),
            .cache_read = try requiredNonnegativeNumber(cost, "cacheRead"),
            .cache_write = try requiredNonnegativeNumber(cost, "cacheWrite"),
        },
        .supported_thinking_levels = levels,
        .authenticated = try requiredBool(object, "authenticated"),
    };
}

fn parseUserItemArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.UserTranscriptItem {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.UserTranscriptItem, array.items.len);
    for (array.items, 0..) |item, index| out[index] = try parseUserItem(gpa, try expectObject(item));
    return out;
}

fn parseTranscriptArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.TranscriptItem {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.TranscriptItem, array.items.len);
    for (array.items, 0..) |item, index| out[index] = try parseTranscriptItem(gpa, item);
    return out;
}

fn parseTranscriptItem(gpa: std.mem.Allocator, value: std.json.Value) !msg.TranscriptItem {
    const object = try expectObject(value);
    const role = try requiredString(object, "role", true);
    if (std.mem.eql(u8, role, "user")) return .{ .user = try parseUserItem(gpa, object) };
    if (std.mem.eql(u8, role, "assistant")) return .{ .assistant = try parseAssistantItem(gpa, object) };
    if (std.mem.eql(u8, role, "tool")) return .{ .tool = try parseToolItem(gpa, object) };
    return ParseError.InvalidMessage;
}

fn parseUserItem(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.UserTranscriptItem {
    if (!onlyKeys(object, &.{ "id", "role", "content", "timestamp" })) return ParseError.InvalidMessage;
    if (!std.mem.eql(u8, try requiredString(object, "role", true), "user")) return ParseError.InvalidMessage;
    return .{
        .id = try requiredString(object, "id", true),
        .content = try parseUserContentArray(gpa, try requiredValue(object, "content")),
        .timestamp = try requiredU64(object, "timestamp"),
    };
}

fn parseAssistantItem(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.AssistantTranscriptItem {
    if (!onlyKeys(object, &.{ "id", "role", "content", "model", "responseModel", "usage", "timestamp", "status", "stopReason", "errorMessage" })) return ParseError.InvalidMessage;
    if (!std.mem.eql(u8, try requiredString(object, "role", true), "assistant")) return ParseError.InvalidMessage;
    const status = try parseEnum(msg.AssistantStatus, try requiredString(object, "status", true));
    const stop_reason: ?msg.AssistantStopReason = if (try optionalString(object, "stopReason", true)) |value|
        try parseEnum(msg.AssistantStopReason, value)
    else
        null;
    const error_message = try optionalString(object, "errorMessage", false);
    switch (status) {
        .streaming => if (stop_reason != null or error_message != null) return ParseError.InvalidMessage,
        .complete => {
            const reason = stop_reason orelse return ParseError.InvalidMessage;
            if (reason != .stop and reason != .length and reason != .toolUse) return ParseError.InvalidMessage;
            if (error_message != null) return ParseError.InvalidMessage;
        },
        .@"error" => {
            if (stop_reason != .@"error") return ParseError.InvalidMessage;
            if (error_message) |text| if (text.len == 0) return ParseError.InvalidMessage;
        },
        .aborted => if (stop_reason != .aborted) return ParseError.InvalidMessage,
    }
    return .{
        .id = try requiredString(object, "id", true),
        .content = try parseAssistantContentArray(gpa, try requiredValue(object, "content")),
        .model = try parseModelRef(try requiredValue(object, "model")),
        .response_model = try optionalString(object, "responseModel", true),
        .usage = if (object.get("usage")) |value| try parseUsage(value) else null,
        .timestamp = try requiredU64(object, "timestamp"),
        .status = status,
        .stop_reason = stop_reason,
        .error_message = error_message,
    };
}

fn parseToolItem(gpa: std.mem.Allocator, object: std.json.ObjectMap) !msg.ToolTranscriptItem {
    if (!onlyKeys(object, &.{ "id", "role", "toolCallId", "toolName", "input", "content", "details", "usage", "timestamp", "status", "isError" })) return ParseError.InvalidMessage;
    if (!std.mem.eql(u8, try requiredString(object, "role", true), "tool")) return ParseError.InvalidMessage;
    const status = try parseEnum(msg.ToolStatus, try requiredString(object, "status", true));
    const is_error = try requiredBool(object, "isError");
    if ((status == .@"error") != is_error) return ParseError.InvalidMessage;
    return .{
        .id = try requiredString(object, "id", true),
        .tool_call_id = try requiredString(object, "toolCallId", true),
        .tool_name = try requiredString(object, "toolName", true),
        .input = try requiredValue(object, "input"),
        .content = try parseToolContentArray(gpa, try requiredValue(object, "content")),
        .details = object.get("details"),
        .usage = if (object.get("usage")) |value| try parseUsage(value) else null,
        .timestamp = try requiredU64(object, "timestamp"),
        .status = status,
        .is_error = is_error,
    };
}

fn parseUserContentArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.UserContent {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.UserContent, array.items.len);
    for (array.items, 0..) |item, index| {
        const object = try expectObject(item);
        const typ = try requiredString(object, "type", true);
        if (std.mem.eql(u8, typ, "text")) out[index] = .{ .text = try parseTextContent(object) } else if (std.mem.eql(u8, typ, "image")) out[index] = .{ .image = try parseImageContent(object) } else return ParseError.InvalidMessage;
    }
    return out;
}

fn parseAssistantContentArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.AssistantContent {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.AssistantContent, array.items.len);
    for (array.items, 0..) |item, index| {
        const object = try expectObject(item);
        const typ = try requiredString(object, "type", true);
        if (std.mem.eql(u8, typ, "text")) out[index] = .{ .text = try parseTextContent(object) } else if (std.mem.eql(u8, typ, "thinking")) out[index] = .{ .thinking = try parseThinkingContent(object) } else if (std.mem.eql(u8, typ, "toolCall")) out[index] = .{ .toolCall = try parseToolCallContent(object) } else return ParseError.InvalidMessage;
    }
    return out;
}

fn parseToolContentArray(gpa: std.mem.Allocator, value: std.json.Value) ![]const msg.ToolContent {
    const array = try expectArray(value);
    const out = try gpa.alloc(msg.ToolContent, array.items.len);
    for (array.items, 0..) |item, index| {
        const object = try expectObject(item);
        const typ = try requiredString(object, "type", true);
        if (std.mem.eql(u8, typ, "text")) out[index] = .{ .text = try parseTextContent(object) } else if (std.mem.eql(u8, typ, "image")) out[index] = .{ .image = try parseImageContent(object) } else return ParseError.InvalidMessage;
    }
    return out;
}

fn parseTextContent(object: std.json.ObjectMap) !msg.TextContent {
    if (!onlyKeys(object, &.{ "type", "text" })) return ParseError.InvalidMessage;
    return .{ .text = try requiredString(object, "text", false) };
}

fn parseThinkingContent(object: std.json.ObjectMap) !msg.ThinkingContent {
    if (!onlyKeys(object, &.{ "type", "thinking", "redacted" })) return ParseError.InvalidMessage;
    return .{
        .thinking = try requiredString(object, "thinking", false),
        .redacted = if (object.get("redacted")) |value| try expectBool(value) else null,
    };
}

fn parseImageContent(object: std.json.ObjectMap) !msg.ImageContent {
    if (!onlyKeys(object, &.{ "type", "data", "mimeType" })) return ParseError.InvalidMessage;
    return .{
        .data = try requiredString(object, "data", false),
        .mime_type = try requiredString(object, "mimeType", true),
    };
}

fn parseToolCallContent(object: std.json.ObjectMap) !msg.ToolCallContent {
    if (!onlyKeys(object, &.{ "type", "toolCallId", "toolName", "input" })) return ParseError.InvalidMessage;
    return .{
        .tool_call_id = try requiredString(object, "toolCallId", true),
        .tool_name = try requiredString(object, "toolName", true),
        .input = try requiredValue(object, "input"),
    };
}

fn parseUsage(value: std.json.Value) !msg.Usage {
    const object = try expectObject(value);
    if (!onlyKeys(object, &.{ "input", "output", "cacheRead", "cacheWrite", "reasoning", "totalTokens", "cost" })) return ParseError.InvalidMessage;
    const cost = try expectObject(try requiredValue(object, "cost"));
    if (!onlyKeys(cost, &.{ "input", "output", "cacheRead", "cacheWrite", "total" })) return ParseError.InvalidMessage;
    return .{
        .input = try requiredU64(object, "input"),
        .output = try requiredU64(object, "output"),
        .cache_read = try requiredU64(object, "cacheRead"),
        .cache_write = try requiredU64(object, "cacheWrite"),
        .reasoning = try optionalU64(object, "reasoning"),
        .total_tokens = try requiredU64(object, "totalTokens"),
        .cost = .{
            .input = try requiredNonnegativeNumber(cost, "input"),
            .output = try requiredNonnegativeNumber(cost, "output"),
            .cache_read = try requiredNonnegativeNumber(cost, "cacheRead"),
            .cache_write = try requiredNonnegativeNumber(cost, "cacheWrite"),
            .total = try requiredNonnegativeNumber(cost, "total"),
        },
    };
}

fn parseProgress(gpa: std.mem.Allocator, value: std.json.Value) !msg.TranscriptProgress {
    const object = try expectObject(value);
    const typ = try requiredString(object, "type", true);
    if (std.mem.eql(u8, typ, "assistant_delta")) {
        if (!onlyKeys(object, &.{ "type", "messageId", "contentIndex", "kind", "delta" })) return ParseError.InvalidMessage;
        return .{ .assistant_delta = .{
            .message_id = try requiredString(object, "messageId", true),
            .content_index = try requiredU64(object, "contentIndex"),
            .kind = try parseEnum(msg.DeltaKind, try requiredString(object, "kind", true)),
            .delta = try requiredString(object, "delta", false),
        } };
    }
    if (std.mem.eql(u8, typ, "item_started") or std.mem.eql(u8, typ, "item_updated") or std.mem.eql(u8, typ, "item_finished")) {
        if (!onlyKeys(object, &.{ "type", "item" })) return ParseError.InvalidMessage;
        const item = try parseTranscriptItem(gpa, try requiredValue(object, "item"));
        if (std.mem.eql(u8, typ, "item_updated")) {
            if (item == .user) return ParseError.InvalidMessage;
            return .{ .item_updated = item };
        }
        if (std.mem.eql(u8, typ, "item_finished")) {
            switch (item) {
                .user => return ParseError.InvalidMessage,
                .assistant => |assistant| if (assistant.status == .streaming) return ParseError.InvalidMessage,
                .tool => |tool| if (tool.status == .running) return ParseError.InvalidMessage,
            }
            return .{ .item_finished = item };
        }
        return .{ .item_started = item };
    }
    return ParseError.InvalidMessage;
}

fn parseError(object: std.json.ObjectMap) !msg.ProtocolError {
    if (!onlyKeys(object, &.{ "code", "message", "details" })) return ParseError.InvalidMessage;
    return .{
        .code = try parseEnum(msg.ProtocolErrorCode, try requiredString(object, "code", true)),
        .message = try requiredString(object, "message", false),
        .details = object.get("details"),
    };
}

fn onlyKeys(object: std.json.ObjectMap, allowed: []const []const u8) bool {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var found = false;
        for (allowed) |key| if (std.mem.eql(u8, entry.key_ptr.*, key)) {
            found = true;
            break;
        };
        if (!found) return false;
    }
    return true;
}

fn requiredValue(object: std.json.ObjectMap, key: []const u8) ParseError!std.json.Value {
    return object.get(key) orelse ParseError.InvalidMessage;
}
fn expectObject(value: std.json.Value) ParseError!std.json.ObjectMap {
    if (value != .object) return ParseError.InvalidMessage;
    return value.object;
}
fn expectArray(value: std.json.Value) ParseError!std.json.Array {
    if (value != .array) return ParseError.InvalidMessage;
    return value.array;
}
fn expectString(value: std.json.Value, nonempty: bool) ParseError![]const u8 {
    if (value != .string or (nonempty and value.string.len == 0)) return ParseError.InvalidMessage;
    return value.string;
}
fn requiredString(object: std.json.ObjectMap, key: []const u8, nonempty: bool) ParseError![]const u8 {
    return expectString(try requiredValue(object, key), nonempty);
}
fn optionalString(object: std.json.ObjectMap, key: []const u8, nonempty: bool) ParseError!?[]const u8 {
    const value = object.get(key) orelse return null;
    return try expectString(value, nonempty);
}
fn expectBool(value: std.json.Value) ParseError!bool {
    if (value != .bool) return ParseError.InvalidMessage;
    return value.bool;
}
fn requiredBool(object: std.json.ObjectMap, key: []const u8) ParseError!bool {
    return expectBool(try requiredValue(object, key));
}
fn valueAsU64(value: std.json.Value) ParseError!u64 {
    if (value != .integer or value.integer < 0) return ParseError.InvalidMessage;
    return @intCast(value.integer);
}
fn requiredU64(object: std.json.ObjectMap, key: []const u8) ParseError!u64 {
    return valueAsU64(try requiredValue(object, key));
}
fn optionalU64(object: std.json.ObjectMap, key: []const u8) ParseError!?u64 {
    const value = object.get(key) orelse return null;
    return try valueAsU64(value);
}
fn requiredU32(object: std.json.ObjectMap, key: []const u8) ParseError!u32 {
    const value = try requiredU64(object, key);
    if (value > std.math.maxInt(u32)) return ParseError.InvalidMessage;
    return @intCast(value);
}
fn requiredPositiveU64(object: std.json.ObjectMap, key: []const u8) ParseError!u64 {
    const value = try requiredU64(object, key);
    if (value == 0) return ParseError.InvalidMessage;
    return value;
}
fn requiredNonnegativeNumber(object: std.json.ObjectMap, key: []const u8) ParseError!f64 {
    const value = try requiredValue(object, key);
    const number: f64 = switch (value) {
        .integer => |integer| @floatFromInt(integer),
        .float => |float| float,
        else => return ParseError.InvalidMessage,
    };
    if (!std.math.isFinite(number) or number < 0) return ParseError.InvalidMessage;
    return number;
}

fn parseEnum(comptime Enum: type, value: []const u8) ParseError!Enum {
    inline for (std.meta.fields(Enum)) |field| if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
    return ParseError.InvalidMessage;
}

const empty_snapshot =
    "{\"serverId\":\"server-1\",\"protocolVersion\":1,\"revision\":0,\"sessions\":[],\"models\":[]}";

test "parse strict server hello and metadata list" {
    const gpa = std.testing.allocator;
    const input = "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"connection-1\",\"snapshot\":" ++ empty_snapshot ++ "}";
    var parsed = try parseServerMessage(gpa, input);
    defer parsed.deinit();
    try std.testing.expect(parsed.message == .hello);
    try std.testing.expectEqualStrings("connection-1", parsed.message.hello.connection_id);

    const list = "{\"type\":\"response\",\"id\":\"r1\",\"ok\":true,\"result\":{\"command\":\"list\",\"sessions\":[{\"id\":\"s1\",\"createdAt\":1,\"updatedAt\":2,\"parentSessionId\":\"p1\",\"sessionName\":\"Named\",\"cwd\":\"/tmp\"}]}}";
    var listed = try parseServerMessage(gpa, list);
    defer listed.deinit();
    try std.testing.expect(listed.message.response == .ok);
    try std.testing.expectEqualStrings("Named", listed.message.response.ok.result.list.sessions[0].session_name.?);
}

test "server messages reject extra fields and inconsistent transcript status" {
    const gpa = std.testing.allocator;
    const extra = "{\"type\":\"hello\",\"version\":1,\"connectionId\":\"c\",\"snapshot\":" ++ empty_snapshot ++ ",\"extra\":true}";
    try std.testing.expectError(ParseError.InvalidMessage, parseServerMessage(gpa, extra));

    const invalid = "{\"type\":\"event\",\"event\":{\"type\":\"session_progress\",\"sessionId\":\"s\",\"progress\":{\"type\":\"item_finished\",\"item\":{\"id\":\"a\",\"role\":\"assistant\",\"content\":[],\"model\":{\"provider\":\"p\",\"id\":\"m\"},\"timestamp\":1,\"status\":\"streaming\"}}}}";
    try std.testing.expectError(ParseError.InvalidMessage, parseServerMessage(gpa, invalid));
}

test "server messages preserve recursive JSON tool details" {
    const gpa = std.testing.allocator;
    const input = "{\"type\":\"event\",\"event\":{\"type\":\"session_progress\",\"sessionId\":\"s\",\"progress\":{\"type\":\"item_finished\",\"item\":{\"id\":\"t\",\"role\":\"tool\",\"toolCallId\":\"c\",\"toolName\":\"read\",\"input\":{\"path\":\"/tmp\"},\"content\":[],\"details\":{\"lines\":[1,2,3],\"cached\":false},\"timestamp\":1,\"status\":\"complete\",\"isError\":false}}}}";
    var parsed = try parseServerMessage(gpa, input);
    defer parsed.deinit();
    const details = parsed.message.event.session_progress.progress.item_finished.tool.details.?;
    try std.testing.expect(details == .object);
    try std.testing.expectEqual(@as(usize, 3), details.object.get("lines").?.array.items.len);
}
