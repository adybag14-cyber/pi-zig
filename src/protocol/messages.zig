//! Pi protocol data model, rewritten from packages/protocol/src/schemas.ts.
//! JSON-shaped extension fields use std.json.Value so the Zig representation
//! preserves the protocol's recursive JsonValue type without synthetic types.
const std = @import("std");

pub const PROTOCOL_VERSION: u32 = 1;
pub const JsonValue = std.json.Value;

pub const ThinkingLevel = enum { off, minimal, low, medium, high, xhigh, max };
pub const SessionPhase = enum { idle, turn, compaction, branch_summary, retry };
pub const ProtocolErrorCode = enum { version, busy, session_locked, not_found, invalid_request, not_implemented, internal_error };
pub const CommandName = enum { list, create, attach, detach, prompt, steer, abort, set_model, set_thinking };
pub const AssistantStatus = enum { streaming, complete, @"error", aborted };
pub const AssistantStopReason = enum { stop, length, toolUse, @"error", aborted };
pub const ToolStatus = enum { running, complete, @"error" };
pub const DeltaKind = enum { text, thinking, toolCall };

pub const ModelRef = struct { provider: []const u8, id: []const u8 };
pub const ModelCost = struct {
    input: f64,
    output: f64,
    cache_read: f64,
    cache_write: f64,
};
pub const ModelMetadata = struct {
    provider: []const u8,
    id: []const u8,
    name: []const u8,
    api: []const u8,
    reasoning: bool,
    input_text: bool = true,
    input_image: bool = false,
    context_window: u64,
    max_tokens: u64,
    cost: ModelCost,
    supported_thinking_levels: []const ThinkingLevel = &.{.off},
    authenticated: bool,
};

pub const TextContent = struct { text: []const u8 };
pub const ThinkingContent = struct { thinking: []const u8, redacted: ?bool = null };
pub const ImageContent = struct { data: []const u8, mime_type: []const u8 };
pub const ToolCallContent = struct { tool_call_id: []const u8, tool_name: []const u8, input: JsonValue };
pub const UserContent = union(enum) { text: TextContent, image: ImageContent };
pub const AssistantContent = union(enum) { text: TextContent, thinking: ThinkingContent, toolCall: ToolCallContent };
pub const ToolContent = union(enum) { text: TextContent, image: ImageContent };

pub const UsageCost = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    total: f64 = 0,
};
pub const Usage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cache_read: u64 = 0,
    cache_write: u64 = 0,
    reasoning: ?u64 = null,
    total_tokens: u64 = 0,
    cost: UsageCost = .{},
};

pub const UserTranscriptItem = struct {
    id: []const u8,
    content: []const UserContent,
    timestamp: u64,
};
pub const AssistantTranscriptItem = struct {
    id: []const u8,
    content: []const AssistantContent,
    model: ModelRef,
    response_model: ?[]const u8 = null,
    usage: ?Usage = null,
    timestamp: u64,
    status: AssistantStatus,
    stop_reason: ?AssistantStopReason = null,
    error_message: ?[]const u8 = null,
};
pub const ToolTranscriptItem = struct {
    id: []const u8,
    tool_call_id: []const u8,
    tool_name: []const u8,
    input: JsonValue,
    content: []const ToolContent,
    details: ?JsonValue = null,
    usage: ?Usage = null,
    timestamp: u64,
    status: ToolStatus,
    is_error: bool,
};
pub const TranscriptItem = union(enum) {
    user: UserTranscriptItem,
    assistant: AssistantTranscriptItem,
    tool: ToolTranscriptItem,
};

pub const TranscriptProgress = union(enum) {
    item_started: TranscriptItem,
    assistant_delta: struct {
        message_id: []const u8,
        content_index: u64,
        kind: DeltaKind,
        delta: []const u8,
    },
    item_updated: TranscriptItem,
    item_finished: TranscriptItem,
};

/// Durable metadata returned by server snapshots and `list`. It deliberately
/// excludes live session phase/model/attachment state; those fields belong to
/// SessionSnapshot after an explicit attach/create, matching protocol v1.
pub const SessionMetadata = struct {
    id: []const u8,
    created_at: u64,
    updated_at: ?u64 = null,
    parent_session_id: ?[]const u8 = null,
    session_name: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
};
/// Compatibility name retained for older native callers.
pub const SessionSummary = SessionMetadata;
pub const SessionSnapshot = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    cwd: []const u8,
    created_at: u64,
    updated_at: u64,
    phase: SessionPhase,
    model: ModelRef,
    thinking_level: ThinkingLevel,
    attached: bool,
    locked: bool,
    revision: u64,
    transcript: []const TranscriptItem,
    queued_steer: []const UserTranscriptItem,
    queued_steer_count: u64,
};
pub const ServerSnapshot = struct {
    server_id: []const u8,
    protocol_version: u32 = PROTOCOL_VERSION,
    revision: u64,
    sessions: []const SessionMetadata,
    models: []const ModelMetadata,
};

pub const ProtocolError = struct {
    code: ProtocolErrorCode,
    message: []const u8,
    details: ?JsonValue = null,
};

pub const Command = union(CommandName) {
    list: void,
    create: struct {
        cwd: ?[]const u8 = null,
        name: ?[]const u8 = null,
        model: ?ModelRef = null,
        thinking_level: ?ThinkingLevel = null,
    },
    attach: struct { session_id: []const u8 },
    detach: struct { session_id: []const u8 },
    prompt: struct { session_id: []const u8, text: []const u8 },
    steer: struct { session_id: []const u8, text: []const u8 },
    abort: struct { session_id: []const u8 },
    set_model: struct { session_id: []const u8, model: ModelRef },
    set_thinking: struct { session_id: []const u8, thinking_level: ThinkingLevel },
};

pub const CommandResult = union(CommandName) {
    list: struct { sessions: []const SessionMetadata },
    create: SessionSnapshot,
    attach: SessionSnapshot,
    detach: struct { session_id: []const u8 },
    prompt: SessionSnapshot,
    steer: SessionSnapshot,
    abort: SessionSnapshot,
    set_model: SessionSnapshot,
    set_thinking: SessionSnapshot,
};

pub const ClientHello = struct { version: u32 };
pub const RequestEnvelope = struct { id: []const u8, request: Command };
pub const ClientMessage = union(enum) { hello: ClientHello, request: RequestEnvelope };

pub const ServerEvent = union(enum) {
    server_snapshot: ServerSnapshot,
    session_snapshot: SessionSnapshot,
    session_progress: struct { session_id: []const u8, progress: TranscriptProgress },
    session_removed: struct { session_id: []const u8 },
};
pub const ServerHello = struct {
    version: u32 = PROTOCOL_VERSION,
    connection_id: []const u8,
    snapshot: ServerSnapshot,
};
pub const ResponseEnvelope = union(enum) {
    ok: struct { id: []const u8, result: CommandResult },
    err: struct { id: []const u8, error_info: ProtocolError },
};
pub const ServerMessage = union(enum) {
    hello: ServerHello,
    hello_error: ProtocolError,
    response: ResponseEnvelope,
    event: ServerEvent,
};

pub fn commandName(command: Command) []const u8 {
    return @tagName(command);
}
pub fn isSupportedProtocolVersion(version: u32) bool {
    return version == PROTOCOL_VERSION;
}

pub fn parseThinkingLevel(s: []const u8) ?ThinkingLevel {
    inline for (std.meta.fields(ThinkingLevel)) |f| if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
    return null;
}

pub fn parseCommandName(s: []const u8) ?CommandName {
    inline for (std.meta.fields(CommandName)) |f| if (std.mem.eql(u8, s, f.name)) return @enumFromInt(f.value);
    return null;
}

test "protocol command vocabulary matches upstream" {
    try std.testing.expectEqual(@as(u32, 1), PROTOCOL_VERSION);
    try std.testing.expect(parseCommandName("set_thinking") == .set_thinking);
    try std.testing.expect(parseCommandName("ext_msg_1_1") == null);
    try std.testing.expect(parseThinkingLevel("xhigh") == .xhigh);
}
