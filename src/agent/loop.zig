//! Agent loop with tool filter, turn limit, streaming events (pi-aligned kinds).
const std = @import("std");
const Io = std.Io;
const tools = @import("tools.zig");
const session_mod = @import("session.zig");
const compaction = @import("compaction.zig");
const branch_summary = @import("branch_summary.zig");
const summarization = @import("summarization.zig");
const ai = @import("../ai/root.zig");

pub const default_system_prompt =
    \\You are pi, a coding agent. Use the provided tools (read, write, edit, bash, grep, find, ls) to fulfill the user's request.
    \\Be concise. Prefer tools over inventing file contents.
;

pub const ToolResultOverride = struct {
    content: []u8,
    is_error: bool,
    image_b64: ?[]u8 = null,
    image_mime: ?[]u8 = null,
    images: []tools.ToolImage = &.{},
    details_json: ?[]u8 = null,
    usage: ?tools.ToolUsage = null,
    added_tool_names: ?[]const []const u8 = null,
    terminate: ?bool = null,

    pub fn deinit(self: *ToolResultOverride, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        if (self.image_b64) |value| gpa.free(value);
        if (self.image_mime) |value| gpa.free(value);
        tools.deinitImages(gpa, self.images);
        if (self.details_json) |value| gpa.free(value);
        if (self.added_tool_names) |values| deinitOwnedStringList(gpa, values);
        self.* = undefined;
    }
};

pub const BeforeToolResult = struct {
    /// Optional replacement JSON arguments. The replacement is intentionally
    /// not schema-revalidated, matching upstream beforeToolCall mutation semantics.
    arguments_json: ?[]u8 = null,
    block: bool = false,
    reason: ?[]u8 = null,

    pub fn deinit(self: *BeforeToolResult, gpa: std.mem.Allocator) void {
        if (self.arguments_json) |owned| gpa.free(owned);
        if (self.reason) |owned| gpa.free(owned);
        self.* = undefined;
    }
};

/// Extension/runtime bridge callbacks. The agent owns any returned allocation
/// and deliberately knows nothing about the extension implementation itself.
pub const BeforePromptFn = *const fn (?*anyopaque, std.mem.Allocator, []const u8) anyerror!?[]u8;

pub const ExtensionContextMessage = struct {
    custom_type: []u8,
    content: []u8,
    display: bool = false,

    pub fn deinit(self: *ExtensionContextMessage, gpa: std.mem.Allocator) void {
        gpa.free(self.custom_type);
        gpa.free(self.content);
        self.* = undefined;
    }
};

pub const BeforeAgentStartResult = struct {
    system_prompt: ?[]u8 = null,
    messages: []ExtensionContextMessage = &.{},

    pub fn deinit(self: *BeforeAgentStartResult, gpa: std.mem.Allocator) void {
        if (self.system_prompt) |owned| gpa.free(owned);
        for (self.messages) |*message| message.deinit(gpa);
        if (self.messages.len > 0) gpa.free(self.messages);
        self.* = undefined;
    }
};

/// Upstream `before_agent_start` bridge. The system prompt argument is the
/// fully assembled prompt for this turn (base + discovered context), and image
/// data remains binary-safe base64. Returned allocations are owned by `gpa`.
pub const BeforeAgentStartFn = *const fn (
    ?*anyopaque,
    std.mem.Allocator,
    []const u8,
    []const u8,
    []const u8,
    []const UserImage,
) anyerror!?BeforeAgentStartResult;
/// Per-provider-call context transform. The callback may return the original
/// slice or allocate a filtered/rewritten/injected view from `scratch`. The
/// arena is released after the provider request and session history is untouched.
pub const TransformContextFn = *const fn (?*anyopaque, std.mem.Allocator, []const ai.ChatMessage) anyerror![]const ai.ChatMessage;
pub const BeforeToolFn = *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8, []const u8) anyerror!?BeforeToolResult;
pub const AfterToolFn = *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8, []const u8, *const tools.ToolResult) anyerror!?ToolResultOverride;
pub const ExternalToolFn = *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror!?tools.ToolResult;

/// Borrowed partial result delivered while an external tool is still running.
/// The producer owns every slice and keeps it valid only for the callback.
pub const ExternalToolUpdate = struct {
    content: []const u8,
    is_error: bool = false,
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
    images: []const tools.ToolImage = &.{},
    details_json: ?[]const u8 = null,
    usage: ?tools.ToolUsage = null,
    added_tool_names: []const []const u8 = &.{},
    /// The source JavaScript runtime is still holding its invocation mutex.
    /// Deliver to the primary UI/client now and replay only to lifecycle
    /// observers after the tool response releases that mutex.
    defer_observer: bool = false,
};

pub const ExternalToolProgressFn = *const fn (?*anyopaque, ExternalToolUpdate) void;
pub const ExternalToolStreamingFn = *const fn (
    ?*anyopaque,
    std.mem.Allocator,
    []const u8,
    []const u8,
    ExternalToolProgressFn,
    ?*anyopaque,
) anyerror!?tools.ToolResult;
/// Full-fidelity external-tool callback. It is additive so existing native
/// integrations using ExternalToolStreamingFn remain source-compatible.
pub const ExternalToolCallStreamingFn = *const fn (
    ?*anyopaque,
    std.mem.Allocator,
    []const u8, // tool call ID
    []const u8, // tool name
    []const u8, // arguments JSON
    ExternalToolProgressFn,
    ?*anyopaque,
    ?*bool, // cooperative abort flag
) anyerror!?tools.ToolResult;
pub const ExternalToolExistsFn = *const fn (?*anyopaque, []const u8) bool;
pub const ExternalPrepareArgumentsFn = *const fn (?*anyopaque, std.mem.Allocator, []const u8, []const u8) anyerror!?[]u8;
pub const ToolExecutionMode = enum { parallel, sequential };
pub const ToolExecutionModeFn = *const fn (?*anyopaque, []const u8) ToolExecutionMode;

pub const TurnSummary = struct {
    assistant_text: []const u8,
    stop_reason: []const u8,
    tool_results: usize,
};

pub const PrepareNextTurnResult = struct {
    client: ?ai.ModelClient = null,
    /// Borrowed prompt replacements; the callback owner keeps them alive for run().
    system_prompt: ?[]const u8 = null,
    context_prompt: ?[]const u8 = null,
};

pub const PrepareNextTurnFn = *const fn (?*anyopaque, TurnSummary) ?PrepareNextTurnResult;
pub const ShouldStopAfterTurnFn = *const fn (?*anyopaque, TurnSummary) bool;
/// Drain extension/runtime side effects on the agent thread. The callback may
/// mutate the live run configuration and client, append owned steering/follow-up
/// text, persist session entries, or request a graceful stop.
pub const FlushRuntimeActionsFn = *const fn (
    ?*anyopaque,
    std.mem.Allocator,
    *session_mod.Session,
    *AgentConfig,
    *ai.ModelClient,
    *std.ArrayList([]u8),
    *std.ArrayList([]u8),
    *bool,
) anyerror!void;

pub const QueueMode = enum {
    all,
    one_at_a_time,

    pub fn parse(value: []const u8) ?QueueMode {
        if (std.ascii.eqlIgnoreCase(value, "all")) return .all;
        if (std.ascii.eqlIgnoreCase(value, "one-at-a-time") or std.ascii.eqlIgnoreCase(value, "one_at_a_time")) return .one_at_a_time;
        return null;
    }

    pub fn wireName(self: QueueMode) []const u8 {
        return switch (self) {
            .all => "all",
            .one_at_a_time => "one-at-a-time",
        };
    }
};

pub const AgentConfig = struct {
    max_turns: usize = 16,
    system_prompt: []const u8 = default_system_prompt,
    context_prompt: []const u8 = "",
    tool_filter: tools.ToolFilter = .{},
    experimental_strict_tools: bool = false,
    verbose: bool = false,
    /// Environment and live identity exposed only to built-in bash children.
    process_environ: ?*const std.process.Environ.Map = null,
    session_id: ?[]const u8 = null,
    session_file: ?[]const u8 = null,
    provider_name: ?[]const u8 = null,
    model_id: ?[]const u8 = null,
    reasoning_level: ?[]const u8 = null,
    /// Security/privacy boundary: images remain durable in session history but
    /// are removed from every provider request after extension transforms.
    block_images: bool = false,
    /// Normalize oversized, rotated and unsupported image results before they
    /// enter durable history/provider context. Safe images remain byte-for-byte.
    auto_resize_images: bool = true,
    /// Register and execute discovered `/skill:name` commands.
    enable_skill_commands: bool = true,
    /// Cooperative abort flag (RPC abort sets this). Checked between tools/turns.
    abort_flag: ?*bool = null,
    /// Steering messages delivered after current tool batch, before next LLM call.
    steer_queue: ?*std.ArrayList([]const u8) = null,
    steering_mode: QueueMode = .one_at_a_time,
    /// Thread-safe/server integrations can provide a message taker instead of
    /// exposing an ArrayList to concurrent writers. Returned text is owned by gpa.
    take_steer_fn: ?*const fn (?*anyopaque, std.mem.Allocator) anyerror!?[]u8 = null,
    take_steer_ctx: ?*anyopaque = null,
    /// Follow-up messages delivered only when the agent would otherwise stop (idle).
    follow_up_queue: ?*std.ArrayList([]const u8) = null,
    follow_up_mode: QueueMode = .one_at_a_time,
    /// Thread-safe equivalent of follow_up_queue. Returned text is owned by gpa.
    take_follow_up_fn: ?*const fn (?*anyopaque, std.mem.Allocator) anyerror!?[]u8 = null,
    take_follow_up_ctx: ?*anyopaque = null,
    /// Optional runtime/extension bridge. Returned prompt/tool content is owned
    /// by `gpa`; null means no mutation.
    hook_ctx: ?*anyopaque = null,
    before_prompt_fn: ?BeforePromptFn = null,
    before_agent_start_fn: ?BeforeAgentStartFn = null,
    transform_context_fn: ?TransformContextFn = null,
    before_tool_fn: ?BeforeToolFn = null,
    after_tool_fn: ?AfterToolFn = null,
    before_compact_fn: ?compaction.BeforeHookFn = null,
    after_compact_fn: ?compaction.AfterHookFn = null,
    before_tree_fn: ?branch_summary.BeforeHookFn = null,
    after_tree_fn: ?branch_summary.AfterHookFn = null,
    /// Optional observer for the complete native agent event stream. Unlike the
    /// primary renderer callback passed to run(), this is part of the runtime
    /// configuration and is therefore preserved across print/JSON/RPC modes.
    event_observer_fn: ?EventHandler = null,
    event_observer_ctx: ?*anyopaque = null,
    /// Additional tool schemas and dispatcher supplied by a trusted runtime.
    /// `extra_tools_json` must be an OpenAI-compatible JSON tool array.
    extra_tools_json: []const u8 = "[]",
    external_tool_fn: ?ExternalToolFn = null,
    /// Streaming dispatcher used when an external runtime can deliver tool
    /// progress before the final result. The legacy dispatcher remains as a
    /// compatibility fallback for native executable extensions and tests.
    external_tool_streaming_fn: ?ExternalToolStreamingFn = null,
    /// Preferred full-fidelity dispatcher. It receives the exact model tool-call
    /// ID and the shared abort flag even when no primary progress sink exists.
    external_tool_call_streaming_fn: ?ExternalToolCallStreamingFn = null,
    /// Identifies names owned by the external dispatcher, including native
    /// built-in names intentionally replaced by an extension.
    external_tool_exists_fn: ?ExternalToolExistsFn = null,
    /// Optional extension prepareArguments shim, applied before schema
    /// validation. Returned JSON is owned by the supplied allocator.
    external_prepare_arguments_fn: ?ExternalPrepareArgumentsFn = null,
    /// Default upstream behavior is parallel. A called tool marked sequential
    /// forces the entire assistant tool batch to execute sequentially.
    tool_execution: ToolExecutionMode = .parallel,
    external_tool_mode_fn: ?ToolExecutionModeFn = null,
    /// Graceful stop policy evaluated only after the current assistant turn and
    /// any tool batch have fully finalized. It runs before steering/follow-up
    /// queues are polled, matching upstream shouldStopAfterTurn ordering.
    should_stop_after_turn_fn: ?ShouldStopAfterTurnFn = null,
    /// Next-turn snapshot hook, applied after turn_end and before should-stop / queues.
    prepare_next_turn_fn: ?PrepareNextTurnFn = null,
    /// Ordered extension side effects are captured from arbitrary callbacks and
    /// applied only at safe agent-thread boundaries through this hook.
    flush_runtime_actions_fn: ?FlushRuntimeActionsFn = null,
    flush_runtime_actions_ctx: ?*anyopaque = null,
    /// Disable only native built-ins while leaving external tools available.
    disable_builtin_tools: bool = false,
    /// Token-budgeted compaction policy. A zero context window disables automatic
    /// threshold checks while retaining manual compaction support.
    auto_compaction_enabled: bool = true,
    compaction_context_window: u64 = 0,
    compaction_reserve_tokens: u64 = 16_384,
    compaction_keep_recent_tokens: u64 = 20_000,
    /// Branch-summary preparation uses the selected model context window and
    /// this independent reserve. skip_prompt controls the interactive tree
    /// confirmation; explicit `--summary` remains authoritative.
    branch_summary_reserve_tokens: u64 = 16_384,
    branch_summary_skip_prompt: bool = false,
    /// Settings-driven outer retry policy for transient assistant failures.
    retry_enabled: bool = true,
    /// Number of retries after the initial provider request.
    retry_max_retries: usize = 3,
    retry_base_delay_ms: u64 = 2_000,
    /// Cancels only a pending retry backoff without aborting the whole run.
    retry_abort_flag: ?*bool = null,
};

/// Event kinds aligned with packages/agent AgentEvent (+ legacy aliases).
pub const EventKind = enum {
    // Lifecycle (upstream)
    agent_start,
    agent_end,
    turn_start,
    turn_end,
    message_start,
    message_update,
    message_end,
    tool_execution_start,
    tool_execution_update,
    tool_execution_end,
    auto_retry_start,
    auto_retry_end,
    summarization_retry_scheduled,
    summarization_retry_attempt_start,
    summarization_retry_finished,
    session_compact_failed,
    // Legacy simplified names (still emitted for compatibility)
    user,
    assistant,
    tool_call,
    tool_result,
    done,
    turn_limit,
};

pub const EventDelivery = enum {
    all,
    primary_only,
    observer_only,
};

pub const AgentEvent = struct {
    kind: EventKind,
    text: []const u8 = "",
    name: []const u8 = "",
    id: []const u8 = "",
    /// JSON-ish args for tool_execution_start
    args_json: []const u8 = "",
    is_error: bool = false,
    details_json: ?[]const u8 = null,
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
    images: []const tools.ToolImage = &.{},
    usage: ?tools.ToolUsage = null,
    added_tool_names: []const []const u8 = &.{},
    is_partial: bool = false,
    /// Automatic retry metadata. Attempts are one-indexed retry attempts and do
    /// not include the initial provider request.
    attempt: usize = 0,
    max_attempts: usize = 0,
    delay_ms: u64 = 0,
    success: bool = false,
    error_message: ?[]const u8 = null,
    final_error: ?[]const u8 = null,
    /// Summarization retry context. `source` is `compaction` or
    /// `branchSummary`; compaction attempts also carry manual/threshold/overflow.
    source: []const u8 = "",
    reason: []const u8 = "",
    will_retry: bool = false,
    /// Internal fan-out control. Live script updates must reach the UI/client
    /// immediately but cannot recursively invoke hooks on the same locked
    /// JavaScript worker. Their observer copy is replayed after tool completion.
    delivery: EventDelivery = .all,
};

pub const EventHandler = *const fn (ctx: ?*anyopaque, event: AgentEvent) void;

pub const RunResult = struct {
    final_text: []u8,
    turns: usize,
    hit_turn_limit: bool,
    text_deltas: usize = 0,

    pub fn deinit(self: *RunResult, gpa: std.mem.Allocator) void {
        gpa.free(self.final_text);
        self.* = undefined;
    }
};

const DeltaCount = struct {
    n: usize = 0,
    fn onDelta(ptr: ?*anyopaque, d: ai.StreamDelta) void {
        const self: *DeltaCount = @ptrCast(@alignCast(ptr.?));
        if (d.kind == .text_delta and d.text.len > 0) self.n += 1;
    }
};

fn responseErrorText(response: ai.ModelResponse) []const u8 {
    if (response.error_message.len > 0) return response.error_message;
    return response.content;
}

fn responseIsError(response: ai.ModelResponse) bool {
    return response.stop_reason.len > 0 and std.mem.eql(u8, response.stop_reason, "error");
}

fn markResponseAborted(gpa: std.mem.Allocator, response: *ai.ModelResponse) !void {
    if (response.stop_reason.len > 0) gpa.free(response.stop_reason);
    response.stop_reason = try gpa.dupe(u8, "aborted");
    if (response.error_message.len > 0) {
        gpa.free(response.error_message);
        response.error_message = "";
    }
}

fn completeAssistant(
    gpa: std.mem.Allocator,
    client: ai.ModelClient,
    messages: []const ai.ChatMessage,
    tools_json: []const u8,
    on_delta: ?ai.StreamHandler,
    delta_ctx: ?*anyopaque,
) !ai.ModelResponse {
    return client.completeStreaming(gpa, messages, tools_json, on_delta, delta_ctx) catch |err| {
        const error_name = @errorName(err);
        // Preserve deterministic programmer/authentication failures as Zig
        // errors. Transient transport failures join the same settings-driven
        // retry path as provider-returned assistant error messages.
        if (!ai.retry.isRetryableError(error_name)) return err;
        const content = try gpa.dupe(u8, error_name);
        errdefer gpa.free(content);
        const error_message = try gpa.dupe(u8, error_name);
        errdefer gpa.free(error_message);
        const stop_reason = try gpa.dupe(u8, "error");
        errdefer gpa.free(stop_reason);
        return .{
            .content = content,
            .tool_calls = try gpa.alloc(ai.ToolCall, 0),
            .error_message = error_message,
            .stop_reason = stop_reason,
        };
    };
}

fn normalizedStopReason(response: ai.ModelResponse) []const u8 {
    if (response.stop_reason.len > 0) return response.stop_reason;
    if (response.tool_calls.len > 0) return "toolUse";
    return "stop";
}

/// Persist one assistant attempt exactly once. Retried failures remain durable
/// history, while retry request construction can omit them from active model
/// context just as the upstream AgentSession does.
fn appendAssistantAttempt(
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
    response: ai.ModelResponse,
) ![]const u8 {
    var tool_calls_json: ?[]u8 = null;
    defer if (tool_calls_json) |value| gpa.free(value);
    if (response.tool_calls.len > 0) {
        tool_calls_json = try serializeToolCallsOpenAI(gpa, response.tool_calls);
    }
    return try sess.appendMessageMeta(sess.lastEntryId(), "assistant", response.content, null, tool_calls_json, null, .{
        .thinking = response.thinking,
        .thinking_signature = response.thinking_signature,
        .thinking_redacted = response.thinking_redacted,
        .provider = response.provider,
        .api = response.api,
        .model = response.model,
        .response_id = response.response_id,
        .response_model = response.response_model,
        .diagnostics_json = response.diagnostics_json,
        .error_message = response.error_message,
        .raw_stop_reason = response.raw_stop_reason,
        .end_turn = response.end_turn,
        .stop_reason = normalizedStopReason(response),
        .usage_input = response.usage.input,
        .usage_output = response.usage.output,
        .usage_cache_read = response.usage.cache_read,
        .usage_cache_write = response.usage.cache_write,
        .usage_cache_write_1h = response.usage.cache_write_1h,
        .usage_reasoning = response.usage.reasoning,
        .usage_total = response.usage.total(),
        .cost_input = response.usage.cost.input,
        .cost_output = response.usage.cost.output,
        .cost_cache_read = response.usage.cost.cache_read,
        .cost_cache_write = response.usage.cost.cache_write,
        .cost_total = response.usage.cost.total,
    });
}

pub const UserImage = struct {
    data_b64: []const u8,
    mime_type: []const u8,
};

const EventMux = struct {
    primary_fn: ?EventHandler,
    primary_ctx: ?*anyopaque,
    observer_fn: ?EventHandler,
    observer_ctx: ?*anyopaque,

    fn onEvent(ctx: ?*anyopaque, event: AgentEvent) void {
        const self: *EventMux = @ptrCast(@alignCast(ctx.?));
        if (event.delivery != .observer_only) {
            if (self.primary_fn) |handler| handler(self.primary_ctx, event);
        }
        if (event.delivery != .primary_only) {
            if (self.observer_fn) |observer| observer(self.observer_ctx, event);
        }
    }
};

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *session_mod.Session,
    user_message: []const u8,
    initial_config: AgentConfig,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !RunResult {
    return runWithImages(gpa, io, cwd, client, sess, user_message, &.{}, initial_config, on_event, event_ctx);
}

/// Run one agent turn with zero or more binary-safe image attachments. Images
/// remain attached to one canonical user entry in their original order while
/// legacy single-image consumers continue to see the first attachment.
pub fn runWithImages(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    client: ai.ModelClient,
    sess: *session_mod.Session,
    user_message: []const u8,
    user_images: []const UserImage,
    initial_config: AgentConfig,
    downstream_on_event: ?EventHandler,
    downstream_event_ctx: ?*anyopaque,
) !RunResult {
    var config = initial_config;
    var event_mux = EventMux{
        .primary_fn = downstream_on_event,
        .primary_ctx = downstream_event_ctx,
        .observer_fn = config.event_observer_fn,
        .observer_ctx = config.event_observer_ctx,
    };
    const has_event_sink = downstream_on_event != null or config.event_observer_fn != null;
    const on_event: ?EventHandler = if (has_event_sink) EventMux.onEvent else null;
    const event_ctx: ?*anyopaque = if (has_event_sink) &event_mux else null;
    emit(on_event, event_ctx, .{ .kind = .agent_start });

    var active_client = client;
    var pending_messages: std.ArrayList([]u8) = .empty;
    defer {
        for (pending_messages.items) |msg| gpa.free(msg);
        pending_messages.deinit(gpa);
    }
    var extension_followups: std.ArrayList([]u8) = .empty;
    defer {
        for (extension_followups.items) |msg| gpa.free(msg);
        extension_followups.deinit(gpa);
    }
    var extension_stop_requested = false;
    var last_text: []u8 = try gpa.dupe(u8, "");
    errdefer gpa.free(last_text);

    var prompt_override: ?[]u8 = null;
    defer if (prompt_override) |owned| gpa.free(owned);
    if (config.before_prompt_fn) |transform| {
        prompt_override = try transform(config.hook_ctx, gpa, user_message);
    }
    const effective_user_message: []const u8 = prompt_override orelse user_message;
    try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
    if (extension_stop_requested) {
        _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
        return .{ .final_text = last_text, .turns = 0, .hit_turn_limit = false, .text_deltas = 0 };
    }

    var assembled_system_prompt: ?[]u8 = null;
    defer if (assembled_system_prompt) |owned| gpa.free(owned);
    var before_agent_start_result: ?BeforeAgentStartResult = null;
    defer if (before_agent_start_result) |*result| result.deinit(gpa);
    if (config.before_agent_start_fn) |before_agent_start| {
        assembled_system_prompt = if (config.context_prompt.len > 0)
            try std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ config.system_prompt, config.context_prompt })
        else
            try gpa.dupe(u8, config.system_prompt);
        before_agent_start_result = try before_agent_start(
            config.hook_ctx,
            gpa,
            cwd,
            effective_user_message,
            assembled_system_prompt.?,
            user_images,
        );
        if (before_agent_start_result) |result| {
            if (result.system_prompt) |replacement| {
                config.system_prompt = replacement;
                // The callback receives the already assembled prompt, so a
                // replacement supersedes rather than duplicates context_prompt.
                config.context_prompt = "";
            }
        }
    }
    try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
    if (extension_stop_requested) {
        _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
        return .{ .final_text = last_text, .turns = 0, .hit_turn_limit = false, .text_deltas = 0 };
    }

    const parent = sess.lastEntryId();
    if (user_images.len == 0) {
        _ = try sess.appendMessage(parent, "user", effective_user_message, null, null);
    } else {
        _ = try sess.appendMessageWithImages(parent, "user", effective_user_message, user_images);
    }
    emit(on_event, event_ctx, .{ .kind = .user, .text = effective_user_message });
    emit(on_event, event_ctx, .{
        .kind = .message_start,
        .text = effective_user_message,
        .name = "user",
    });
    emit(on_event, event_ctx, .{
        .kind = .message_end,
        .text = effective_user_message,
        .name = "user",
    });

    if (before_agent_start_result) |result| {
        for (result.messages) |message| {
            _ = try sess.appendCustomMessage(message.custom_type, message.content, message.display);
        }
    }

    try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
    try collectSteeringMessages(gpa, &config, &pending_messages);

    var turns: usize = 0;
    var total_deltas: usize = 0;

    while (turns < config.max_turns) : (turns += 1) {
        if (config.abort_flag) |f| {
            if (@atomicLoad(bool, f, .acquire)) {
                _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
                return .{
                    .final_text = last_text,
                    .turns = turns,
                    .hit_turn_limit = false,
                    .text_deltas = total_deltas,
                };
            }
        }
        emit(on_event, event_ctx, .{ .kind = .turn_start });
        try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
        if (extension_stop_requested) {
            _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
            return .{ .final_text = last_text, .turns = turns, .hit_turn_limit = false, .text_deltas = total_deltas };
        }

        // Pending steering/follow-up messages are injected only at turn boundaries.
        // This preserves arrivals that happen while the previous model/tool turn is running.
        try injectPendingMessages(gpa, sess, &pending_messages, on_event, event_ctx);

        // Auto-compact after queued user messages are part of the context.
        if (config.auto_compaction_enabled and config.compaction_context_window > 0) {
            const context_tokens = try compaction.estimateSessionContextTokens(gpa, sess);
            if (compaction.shouldCompact(context_tokens, config.compaction_context_window, .{
                .enabled = true,
                .reserve_tokens = config.compaction_reserve_tokens,
                .keep_recent_tokens = config.compaction_keep_recent_tokens,
            })) {
                try compactSession(io, sess, active_client, config, .threshold, on_event, event_ctx);
                try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
            }
        }

        const chat = try buildChatMessages(gpa, sess, config);
        defer freeChatMessages(gpa, chat);
        var transform_arena: std.heap.ArenaAllocator = .init(gpa);
        defer transform_arena.deinit();
        const request_chat = try transformChatContext(&config, transform_arena.allocator(), chat);
        try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
        if (extension_stop_requested) {
            _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
            return .{ .final_text = last_text, .turns = turns, .hit_turn_limit = false, .text_deltas = total_deltas };
        }

        // Runtime tool mutations are reflected in the very next provider call.
        // Rebuilding here avoids retaining stale schemas for the whole run.
        const builtin_schemas = if (config.disable_builtin_tools)
            try gpa.dupe(u8, "[]")
        else
            try tools.toolSchemasJsonWithOptions(gpa, config.tool_filter, .{ .experimental_strict = config.experimental_strict_tools });
        defer gpa.free(builtin_schemas);
        const schemas = try mergeToolSchemaArrays(gpa, builtin_schemas, config.extra_tools_json);
        defer gpa.free(schemas);

        var delta_count = DeltaCount{};
        const StreamCtx = struct {
            outer: ?EventHandler,
            outer_ctx: ?*anyopaque,
            counter: *DeltaCount,
            abort_flag: ?*bool,
            fn onDelta(ptr: ?*anyopaque, d: ai.StreamDelta) void {
                const self: *@This() = @ptrCast(@alignCast(ptr.?));
                if (self.abort_flag) |f| {
                    if (@atomicLoad(bool, f, .acquire)) return;
                }
                DeltaCount.onDelta(self.counter, d);
                if (self.outer) |h| {
                    if (d.kind == .text_delta and d.text.len > 0) {
                        h(self.outer_ctx, .{ .kind = .message_update, .text = d.text, .name = "assistant" });
                        h(self.outer_ctx, .{ .kind = .assistant, .text = d.text });
                    }
                }
            }
        };
        var sctx = StreamCtx{ .outer = on_event, .outer_ctx = event_ctx, .counter = &delta_count, .abort_flag = config.abort_flag };

        emit(on_event, event_ctx, .{ .kind = .message_start, .name = "assistant" });
        var response = try completeAssistant(gpa, active_client, request_chat, schemas, StreamCtx.onDelta, &sctx);
        var response_persisted = false;
        // Context overflow recovery remains separate from transient retry policy:
        // preserve the failed attempt, compact once, rebuild an active context
        // without failed assistants, and retry immediately.
        if (config.auto_compaction_enabled and responseIsError(response) and looksLikeContextOverflow(responseErrorText(response))) {
            const failed_id = try appendAssistantAttempt(gpa, sess, response);
            try sess.excludeEntryFromActiveContext(failed_id);
            response_persisted = true;
            emit(on_event, event_ctx, .{ .kind = .message_end, .text = response.content, .name = "assistant" });
            emit(on_event, event_ctx, .{ .kind = .assistant, .text = response.content });
            response.deinit(gpa);
            try compactSession(io, sess, active_client, config, .overflow, on_event, event_ctx);
            try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
            response = retry_call: {
                const chat2 = try buildChatMessages(gpa, sess, config);
                defer freeChatMessages(gpa, chat2);
                var retry_arena: std.heap.ArenaAllocator = .init(gpa);
                defer retry_arena.deinit();
                const request_chat2 = try transformChatContext(&config, retry_arena.allocator(), chat2);
                emit(on_event, event_ctx, .{ .kind = .message_start, .name = "assistant" });
                break :retry_call try completeAssistant(gpa, active_client, request_chat2, schemas, StreamCtx.onDelta, &sctx);
            };
            response_persisted = false;
        }

        var retry_attempt: usize = 0;
        var retry_started = false;
        var retry_cancelled = false;
        while (config.retry_enabled and retry_attempt < config.retry_max_retries and responseIsError(response) and ai.retry.isRetryableError(responseErrorText(response))) {
            retry_attempt += 1;
            retry_started = true;
            const retry_error = responseErrorText(response);
            const failed_id = try appendAssistantAttempt(gpa, sess, response);
            try sess.excludeEntryFromActiveContext(failed_id);
            response_persisted = true;
            emit(on_event, event_ctx, .{ .kind = .message_end, .text = response.content, .name = "assistant" });
            emit(on_event, event_ctx, .{ .kind = .assistant, .text = response.content });
            const delay_ms = ai.retry.delayMs(config.retry_base_delay_ms, retry_attempt);
            emit(on_event, event_ctx, .{
                .kind = .auto_retry_start,
                .attempt = retry_attempt,
                .max_attempts = config.retry_max_retries,
                .delay_ms = delay_ms,
                .error_message = retry_error,
                .text = retry_error,
            });

            if (!ai.retry.wait(io, delay_ms, config.abort_flag, config.retry_abort_flag)) {
                retry_cancelled = true;
                emit(on_event, event_ctx, .{
                    .kind = .auto_retry_end,
                    .success = false,
                    .attempt = retry_attempt,
                    .final_error = "Retry cancelled",
                    .text = "Retry cancelled",
                });
                break;
            }

            response.deinit(gpa);
            response = retry_call: {
                // Runtime hooks can mutate context between calls; rebuild rather
                // than retaining a request projection across the backoff. Failed
                // attempts stay durable but are excluded from the retry request.
                const retry_chat = try buildChatMessages(gpa, sess, config);
                defer freeChatMessages(gpa, retry_chat);
                var retry_arena: std.heap.ArenaAllocator = .init(gpa);
                defer retry_arena.deinit();
                const retry_request = try transformChatContext(&config, retry_arena.allocator(), retry_chat);
                emit(on_event, event_ctx, .{ .kind = .message_start, .name = "assistant" });
                break :retry_call try completeAssistant(gpa, active_client, retry_request, schemas, StreamCtx.onDelta, &sctx);
            };
            response_persisted = false;
        }
        if (retry_started and !retry_cancelled and !std.mem.eql(u8, response.stop_reason, "aborted")) {
            if (!responseIsError(response)) {
                emit(on_event, event_ctx, .{
                    .kind = .auto_retry_end,
                    .success = true,
                    .attempt = retry_attempt,
                });
            } else {
                const final_error = responseErrorText(response);
                emit(on_event, event_ctx, .{
                    .kind = .auto_retry_end,
                    .success = false,
                    .attempt = retry_attempt,
                    .final_error = final_error,
                    .text = final_error,
                });
            }
        }
        defer response.deinit(gpa);
        total_deltas += delta_count.n;

        if (config.abort_flag) |f| {
            if (@atomicLoad(bool, f, .acquire)) {
                gpa.free(last_text);
                last_text = try gpa.dupe(u8, response.content);
                _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
                return .{
                    .final_text = last_text,
                    .turns = turns + 1,
                    .hit_turn_limit = false,
                    .text_deltas = total_deltas,
                };
            }
        }

        const stop_reason = normalizedStopReason(response);
        if (!response_persisted) _ = try appendAssistantAttempt(gpa, sess, response);

        gpa.free(last_text);
        last_text = try gpa.dupe(u8, response.content);
        if (!response_persisted) {
            emit(on_event, event_ctx, .{ .kind = .message_end, .text = last_text, .name = "assistant" });
            emit(on_event, event_ctx, .{ .kind = .assistant, .text = last_text });
        }
        // Actions emitted while an assistant tool call is streaming must not be
        // persisted between that call and its tool result. Each terminal branch
        // below flushes after either confirming there is no tool batch or after
        // all tool-result entries have been appended.

        if (std.mem.eql(u8, stop_reason, "error") or std.mem.eql(u8, stop_reason, "aborted")) {
            emit(on_event, event_ctx, .{ .kind = .turn_end, .text = last_text });
            if (try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, true)) {
                applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, 0);
                continue;
            }
            return .{ .final_text = last_text, .turns = turns + 1, .hit_turn_limit = false, .text_deltas = total_deltas };
        }

        if (response.tool_calls.len == 0) {
            emit(on_event, event_ctx, .{ .kind = .turn_end, .text = last_text });
            try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
            if (shouldStopAfterTurn(config, last_text, stop_reason, 0)) {
                // A user stop policy is authoritative. Emit/flush agent_end so
                // extension cleanup remains durable, but do not consume queued
                // steering or follow-up messages after the stop decision.
                _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
                return .{
                    .final_text = last_text,
                    .turns = turns + 1,
                    .hit_turn_limit = false,
                    .text_deltas = total_deltas,
                };
            }
            try collectSteeringMessages(gpa, &config, &pending_messages);
            if (pending_messages.items.len > 0) {
                applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, 0);
                continue;
            }
            try collectExtensionFollowUps(gpa, &extension_followups, &pending_messages);
            try collectFollowUpMessages(gpa, &config, &pending_messages);
            if (pending_messages.items.len > 0) {
                applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, 0);
                continue;
            }
            emit(on_event, event_ctx, .{ .kind = .done, .text = last_text });
            if (try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, true)) {
                applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, 0);
                continue;
            }
            return .{
                .final_text = last_text,
                .turns = turns + 1,
                .hit_turn_limit = false,
                .text_deltas = total_deltas,
            };
        }

        if (std.mem.eql(u8, stop_reason, "length")) {
            for (response.tool_calls) |tc| {
                emit(on_event, event_ctx, .{
                    .kind = .tool_execution_start,
                    .id = tc.id,
                    .name = tc.name,
                    .args_json = tc.arguments,
                    .text = tc.arguments,
                });
                emit(on_event, event_ctx, .{ .kind = .tool_call, .name = tc.name, .id = tc.id, .text = tc.arguments });

                const result_content = try std.fmt.allocPrint(
                    gpa,
                    "Tool call \"{s}\" was not executed: the response hit the output token limit, so its arguments may be truncated. Re-issue the tool call with complete arguments.",
                    .{tc.name},
                );
                defer gpa.free(result_content);

                emit(on_event, event_ctx, .{
                    .kind = .tool_execution_end,
                    .id = tc.id,
                    .name = tc.name,
                    .args_json = tc.arguments,
                    .text = result_content,
                    .is_error = true,
                });
                emit(on_event, event_ctx, .{ .kind = .tool_result, .name = tc.name, .id = tc.id, .text = result_content, .is_error = true });

                const p = sess.lastEntryId();
                _ = try sess.appendToolResultStatusWithMedia(p, result_content, tc.id, tc.name, true, &.{}, null, null);
            }
            emit(on_event, event_ctx, .{ .kind = .turn_end, .text = last_text });
            try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
            if (shouldStopAfterTurn(config, last_text, stop_reason, response.tool_calls.len)) {
                _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
                return .{ .final_text = last_text, .turns = turns + 1, .hit_turn_limit = false, .text_deltas = total_deltas };
            }
            try collectSteeringMessages(gpa, &config, &pending_messages);
            applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, response.tool_calls.len);
            continue;
        }

        const force_sequential = batchRequiresSequential(config, response.tool_calls);
        const terminate_batch = if (force_sequential)
            try executeToolBatchSequential(gpa, io, cwd, &config, schemas, sess, response.tool_calls, on_event, event_ctx)
        else
            try executeToolBatchParallel(gpa, io, cwd, &config, schemas, sess, response.tool_calls, on_event, event_ctx);
        emit(on_event, event_ctx, .{ .kind = .turn_end, .text = last_text });
        try flushRuntimeActions(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested);
        if (shouldStopAfterTurn(config, last_text, stop_reason, response.tool_calls.len)) {
            _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
            return .{ .final_text = last_text, .turns = turns + 1, .hit_turn_limit = false, .text_deltas = total_deltas };
        }
        try collectSteeringMessages(gpa, &config, &pending_messages);
        if (!terminate_batch or pending_messages.items.len > 0) {
            applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, response.tool_calls.len);
            continue;
        }

        // A terminating tool batch stops only automatic tool continuation. Steering
        // still wins, and follow-ups are allowed once the agent would otherwise idle.
        try collectExtensionFollowUps(gpa, &extension_followups, &pending_messages);
        try collectFollowUpMessages(gpa, &config, &pending_messages);
        if (pending_messages.items.len > 0) {
            applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, response.tool_calls.len);
            continue;
        }
        emit(on_event, event_ctx, .{ .kind = .done, .text = last_text });
        if (try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, true)) {
            applyPrepareNextTurn(&config, &active_client, last_text, stop_reason, response.tool_calls.len);
            continue;
        }
        return .{
            .final_text = last_text,
            .turns = turns + 1,
            .hit_turn_limit = false,
            .text_deltas = total_deltas,
        };
    }

    emit(on_event, event_ctx, .{ .kind = .turn_limit, .text = last_text });
    _ = try finishAgentCycle(&config, gpa, sess, &active_client, &pending_messages, &extension_followups, &extension_stop_requested, on_event, event_ctx, last_text, false);
    return .{
        .final_text = last_text,
        .turns = turns,
        .hit_turn_limit = true,
        .text_deltas = total_deltas,
    };
}

/// Emit the canonical end event, then apply actions produced by its extension
/// handlers before deciding whether this native run is truly finished. Upstream
/// AgentSession performs the same post-agent check: messages queued by
/// `agent_end` handlers cause another continuation instead of being discarded.
fn finishAgentCycle(
    config: *AgentConfig,
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
    active_client: *ai.ModelClient,
    steering: *std.ArrayList([]u8),
    extension_followups: *std.ArrayList([]u8),
    stop_requested: *bool,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
    last_text: []const u8,
    allow_continuation: bool,
) !bool {
    emit(on_event, event_ctx, .{ .kind = .agent_end, .text = last_text });
    try flushRuntimeActions(config, gpa, sess, active_client, steering, extension_followups, stop_requested);
    if (!allow_continuation or stop_requested.*) return false;

    // Steering wins over follow-ups. Pull external queues again because an
    // agent_end observer may synchronously enqueue through either route.
    try collectSteeringMessages(gpa, config, steering);
    if (steering.items.len == 0) {
        try collectExtensionFollowUps(gpa, extension_followups, steering);
        try collectFollowUpMessages(gpa, config, steering);
    }
    if (steering.items.len == 0) return false;

    // A continuation is a new agent cycle over the same durable session. Flush
    // agent_start actions now so model/tool/session mutations affect its first
    // turn rather than landing one event late.
    emit(on_event, event_ctx, .{ .kind = .agent_start });
    try flushRuntimeActions(config, gpa, sess, active_client, steering, extension_followups, stop_requested);
    return !stop_requested.*;
}

fn flushRuntimeActions(
    config: *AgentConfig,
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
    active_client: *ai.ModelClient,
    steering: *std.ArrayList([]u8),
    followups: *std.ArrayList([]u8),
    stop_requested: *bool,
) !void {
    const callback = config.flush_runtime_actions_fn orelse return;
    try callback(config.flush_runtime_actions_ctx, gpa, sess, config, active_client, steering, followups, stop_requested);
}

fn collectExtensionFollowUps(
    gpa: std.mem.Allocator,
    followups: *std.ArrayList([]u8),
    pending: *std.ArrayList([]u8),
) !void {
    if (followups.items.len == 0) return;
    try pending.ensureUnusedCapacity(gpa, followups.items.len);
    for (followups.items) |message| pending.appendAssumeCapacity(message);
    followups.clearRetainingCapacity();
}

fn transformChatContext(config: *const AgentConfig, scratch: std.mem.Allocator, chat: []const ai.ChatMessage) ![]const ai.ChatMessage {
    const transformed = if (config.transform_context_fn) |transform|
        // Upstream contract says transformContext must provide a safe fallback
        // on extension failure. Preserve that contract before applying native
        // security policy.
        transform(config.hook_ctx, scratch, chat) catch chat
    else
        chat;

    if (!config.block_images) return transformed;
    var contains_images = false;
    for (transformed) |message| if (message.hasImages()) {
        contains_images = true;
        break;
    };
    if (!contains_images) return transformed;

    // Blocking images is a fail-closed provider boundary. Allocation failure is
    // propagated rather than falling back to the image-bearing request. The
    // shallow copy is safe because only image slices are replaced and scratch
    // outlives the provider call.
    const filtered = try scratch.alloc(ai.ChatMessage, transformed.len);
    @memcpy(filtered, transformed);
    const blocked_placeholder = "Image reading is disabled.";
    for (filtered) |*message| {
        if ((std.mem.eql(u8, message.role, "user") or std.mem.eql(u8, message.role, "tool")) and
            std.mem.indexOf(u8, message.content, blocked_placeholder) == null)
        {
            message.content = if (message.content.len == 0)
                try scratch.dupe(u8, blocked_placeholder)
            else
                try std.fmt.allocPrint(scratch, "{s}\n{s}", .{ message.content, blocked_placeholder });
            message.owned_content = true;
        }
        message.image_b64 = null;
        message.image_mime = null;
        message.images = &.{};
    }
    return filtered;
}

fn appendOwnedPending(gpa: std.mem.Allocator, pending: *std.ArrayList([]u8), msg: []u8) !void {
    errdefer gpa.free(msg);
    try pending.append(gpa, msg);
}

fn collectSteeringMessages(gpa: std.mem.Allocator, config: *const AgentConfig, pending: *std.ArrayList([]u8)) !void {
    if (config.take_steer_fn) |take| {
        if (config.steering_mode == .all) {
            while (try take(config.take_steer_ctx, gpa)) |msg| try appendOwnedPending(gpa, pending, msg);
        } else if (try take(config.take_steer_ctx, gpa)) |msg| {
            try appendOwnedPending(gpa, pending, msg);
        }
    }
    if (config.steer_queue) |queue| {
        const count = if (config.steering_mode == .all) queue.items.len else @min(queue.items.len, 1);
        for (0..count) |_| {
            const msg_const = queue.orderedRemove(0);
            const msg: []u8 = @constCast(msg_const);
            try appendOwnedPending(gpa, pending, msg);
        }
    }
}

fn collectFollowUpMessages(gpa: std.mem.Allocator, config: *const AgentConfig, pending: *std.ArrayList([]u8)) !void {
    if (config.take_follow_up_fn) |take| {
        if (config.follow_up_mode == .all) {
            while (try take(config.take_follow_up_ctx, gpa)) |msg| try appendOwnedPending(gpa, pending, msg);
        } else if (try take(config.take_follow_up_ctx, gpa)) |msg| {
            try appendOwnedPending(gpa, pending, msg);
        }
    }
    if (config.follow_up_queue) |queue| {
        const count = if (config.follow_up_mode == .all) queue.items.len else @min(queue.items.len, 1);
        for (0..count) |_| {
            const msg_const = queue.orderedRemove(0);
            const msg: []u8 = @constCast(msg_const);
            try appendOwnedPending(gpa, pending, msg);
        }
    }
}

fn injectPendingMessages(
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
    pending: *std.ArrayList([]u8),
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !void {
    for (pending.items) |msg| {
        const parent = sess.lastEntryId();
        _ = try sess.appendMessage(parent, "user", msg, null, null);
        emit(on_event, event_ctx, .{ .kind = .message_start, .text = msg, .name = "user" });
        emit(on_event, event_ctx, .{ .kind = .user, .text = msg });
        emit(on_event, event_ctx, .{ .kind = .message_end, .text = msg, .name = "user" });
        gpa.free(msg);
    }
    pending.clearRetainingCapacity();
}

fn applyPrepareNextTurn(
    config: *AgentConfig,
    active_client: *ai.ModelClient,
    assistant_text: []const u8,
    stop_reason: []const u8,
    tool_results: usize,
) void {
    const callback = config.prepare_next_turn_fn orelse return;
    const update = callback(config.hook_ctx, .{
        .assistant_text = assistant_text,
        .stop_reason = stop_reason,
        .tool_results = tool_results,
    }) orelse return;
    if (update.client) |next| active_client.* = next;
    if (update.system_prompt) |prompt| config.system_prompt = prompt;
    if (update.context_prompt) |prompt| config.context_prompt = prompt;
}

fn shouldStopAfterTurn(config: AgentConfig, assistant_text: []const u8, stop_reason: []const u8, tool_results: usize) bool {
    const callback = config.should_stop_after_turn_fn orelse return false;
    return callback(config.hook_ctx, .{
        .assistant_text = assistant_text,
        .stop_reason = stop_reason,
        .tool_results = tool_results,
    });
}

fn batchRequiresSequential(config: AgentConfig, calls: []const ai.ToolCall) bool {
    if (config.tool_execution == .sequential) return true;
    const mode_fn = config.external_tool_mode_fn orelse return false;
    for (calls) |tc| {
        if (mode_fn(config.hook_ctx, tc.name) == .sequential) return true;
    }
    return false;
}

fn executeRawTool(
    allocator: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    tc: *const ai.ToolCall,
    arguments_json: []const u8,
    progress_fn: ?ExternalToolProgressFn,
    progress_ctx: ?*anyopaque,
) !tools.ToolResult {
    var builtin_progress = BuiltinProgressAdapter{
        .io = io,
        .allocator = allocator,
        .callback = progress_fn,
        .context = progress_ctx,
    };
    defer builtin_progress.deinit();
    defer builtin_progress.finish();
    const tool_ctx = tools.ToolContext{
        .gpa = allocator,
        .io = io,
        .cwd = cwd,
        .environ = config.process_environ,
        .session_id = config.session_id,
        .session_file = config.session_file,
        .provider_name = config.provider_name,
        .model_id = config.model_id,
        .reasoning_level = config.reasoning_level,
        .auto_resize_images = config.auto_resize_images,
        .abort_flag = config.abort_flag,
        .progress_fn = if (progress_fn != null) BuiltinProgressAdapter.forward else null,
        .progress_ctx = if (progress_fn != null) &builtin_progress else null,
    };
    if (!config.tool_filter.isEnabled(tc.name) or (config.disable_builtin_tools and tools.isBuiltin(tc.name))) {
        return .{
            .content = try std.fmt.allocPrint(allocator, "tool disabled: {s}", .{tc.name}),
            .is_error = true,
        };
    }
    const external_claims = if (config.external_tool_exists_fn) |exists|
        exists(config.hook_ctx, tc.name)
    else
        !tools.isBuiltin(tc.name);
    if (external_claims) {
        if (try executeExternalTool(config, allocator, tc.id, tc.name, arguments_json, progress_fn, progress_ctx)) |result| return result;
    }
    if (tools.isBuiltin(tc.name)) return try tools.execute(tool_ctx, tc.name, arguments_json);
    if (!external_claims) {
        if (try executeExternalTool(config, allocator, tc.id, tc.name, arguments_json, progress_fn, progress_ctx)) |result| return result;
    }
    return try tools.execute(tool_ctx, tc.name, arguments_json);
}

/// Native tools expose byte deltas while external tools expose rich partial
/// results. Convert native deltas into bounded accumulated snapshots so TUI,
/// JSON, RPC, and extension renderers all observe the same replacement-style
/// progress semantics. Bash drains stdout and stderr on separate threads, so
/// the buffer and callback are serialized here.
const BuiltinProgressAdapter = struct {
    const max_snapshot_bytes = 128 * 1024;
    const update_interval_ns = std.Io.Duration.fromMilliseconds(100).nanoseconds;

    io: Io,
    allocator: std.mem.Allocator,
    callback: ?ExternalToolProgressFn,
    context: ?*anyopaque,
    mutex: std.Io.Mutex = .init,
    buffer: std.ArrayList(u8) = .empty,
    last_emit: ?std.Io.Timestamp = null,
    dirty: bool = false,

    fn deinit(self: *BuiltinProgressAdapter) void {
        self.buffer.deinit(self.allocator);
    }

    fn forward(raw_ctx: ?*anyopaque, delta: []const u8) void {
        const self: *BuiltinProgressAdapter = @ptrCast(@alignCast(raw_ctx.?));
        const callback = self.callback orelse return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.appendBounded(delta) catch return;
        self.dirty = true;
        const now = std.Io.Clock.awake.now(self.io);
        if (self.last_emit == null or self.last_emit.?.durationTo(now).nanoseconds >= update_interval_ns) {
            self.emitUnlocked(callback, now);
        }
    }

    fn finish(self: *BuiltinProgressAdapter) void {
        const callback = self.callback orelse return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.dirty) self.emitUnlocked(callback, std.Io.Clock.awake.now(self.io));
    }

    fn emitUnlocked(self: *BuiltinProgressAdapter, callback: ExternalToolProgressFn, now: std.Io.Timestamp) void {
        callback(self.context, .{
            .content = self.buffer.items,
            .details_json = "{\"kind\":\"output\",\"mode\":\"snapshot\"}",
        });
        self.last_emit = now;
        self.dirty = false;
    }

    fn appendBounded(self: *BuiltinProgressAdapter, delta: []const u8) !void {
        if (delta.len >= max_snapshot_bytes) {
            self.buffer.clearRetainingCapacity();
            try self.buffer.appendSlice(self.allocator, delta[delta.len - max_snapshot_bytes ..]);
            return;
        }
        if (self.buffer.items.len + delta.len > max_snapshot_bytes) {
            const discard = self.buffer.items.len + delta.len - max_snapshot_bytes;
            std.mem.copyForwards(u8, self.buffer.items[0 .. self.buffer.items.len - discard], self.buffer.items[discard..]);
            self.buffer.items.len -= discard;
        }
        try self.buffer.appendSlice(self.allocator, delta);
    }
};

fn discardExternalToolProgress(_: ?*anyopaque, _: ExternalToolUpdate) void {}

fn executeExternalTool(
    config: *const AgentConfig,
    allocator: std.mem.Allocator,
    tool_call_id: []const u8,
    name: []const u8,
    arguments_json: []const u8,
    progress_fn: ?ExternalToolProgressFn,
    progress_ctx: ?*anyopaque,
) !?tools.ToolResult {
    if (config.external_tool_call_streaming_fn) |execute_streaming| {
        const callback = progress_fn orelse discardExternalToolProgress;
        return try execute_streaming(config.hook_ctx, allocator, tool_call_id, name, arguments_json, callback, progress_ctx, config.abort_flag);
    }
    if (config.external_tool_streaming_fn) |execute_streaming| {
        if (progress_fn) |callback| {
            return try execute_streaming(config.hook_ctx, allocator, name, arguments_json, callback, progress_ctx);
        }
    }
    if (config.external_tool_fn) |execute_external| {
        return try execute_external(config.hook_ctx, allocator, name, arguments_json);
    }
    return null;
}

fn cloneToolResult(gpa: std.mem.Allocator, source: *const tools.ToolResult) !tools.ToolResult {
    const content = try gpa.dupe(u8, source.content);
    errdefer gpa.free(content);
    var image_b64: ?[]u8 = null;
    errdefer if (image_b64) |v| gpa.free(v);
    var image_mime: ?[]u8 = null;
    errdefer if (image_mime) |v| gpa.free(v);
    var details_json: ?[]u8 = null;
    errdefer if (details_json) |v| gpa.free(v);
    if (source.image_b64) |v| image_b64 = try gpa.dupe(u8, v);
    if (source.image_mime) |v| image_mime = try gpa.dupe(u8, v);
    const images = try tools.cloneImages(gpa, source.images);
    errdefer tools.deinitImages(gpa, images);
    if (source.details_json) |v| details_json = try gpa.dupe(u8, v);
    const added_tool_names = try cloneOwnedStringList(gpa, source.added_tool_names);
    errdefer deinitOwnedStringList(gpa, added_tool_names);
    const updates = try cloneToolUpdates(gpa, source.updates);
    errdefer deinitToolUpdates(gpa, updates);
    return .{
        .content = content,
        .is_error = source.is_error,
        .image_b64 = image_b64,
        .image_mime = image_mime,
        .images = images,
        .details_json = details_json,
        .usage = source.usage,
        .added_tool_names = added_tool_names,
        .updates = updates,
        .terminate = source.terminate,
    };
}

fn cloneToolUpdates(gpa: std.mem.Allocator, source: []const tools.ToolUpdate) ![]tools.ToolUpdate {
    if (source.len == 0) return &.{};
    const out = try gpa.alloc(tools.ToolUpdate, source.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |*update| update.deinit(gpa);
        gpa.free(out);
    }
    for (source, 0..) |update, index| {
        const content = try gpa.dupe(u8, update.content);
        errdefer gpa.free(content);
        const image_b64 = if (update.image_b64) |value| try gpa.dupe(u8, value) else null;
        errdefer if (image_b64) |value| gpa.free(value);
        const image_mime = if (update.image_mime) |value| try gpa.dupe(u8, value) else null;
        errdefer if (image_mime) |value| gpa.free(value);
        const images = try tools.cloneImages(gpa, update.images);
        errdefer tools.deinitImages(gpa, images);
        const details_json = if (update.details_json) |value| try gpa.dupe(u8, value) else null;
        errdefer if (details_json) |value| gpa.free(value);
        const added_tool_names = try cloneOwnedStringList(gpa, update.added_tool_names);
        errdefer deinitOwnedStringList(gpa, added_tool_names);
        out[index] = .{
            .content = content,
            .is_error = update.is_error,
            .image_b64 = image_b64,
            .image_mime = image_mime,
            .images = images,
            .details_json = details_json,
            .usage = update.usage,
            .added_tool_names = added_tool_names,
            .observer_deferred = update.observer_deferred,
        };
        initialized += 1;
    }
    return out;
}

fn cloneOwnedStringList(gpa: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    if (source.len == 0) return &.{};
    const out = try gpa.alloc([]const u8, source.len);
    var initialized: usize = 0;
    errdefer {
        for (out[0..initialized]) |value| gpa.free(value);
        gpa.free(out);
    }
    for (source, 0..) |value, index| {
        out[index] = try gpa.dupe(u8, value);
        initialized += 1;
    }
    return out;
}

fn deinitOwnedStringList(gpa: std.mem.Allocator, values: []const []const u8) void {
    if (values.len == 0) return;
    for (values) |value| gpa.free(value);
    gpa.free(values);
}

fn deinitToolUpdates(gpa: std.mem.Allocator, updates: []tools.ToolUpdate) void {
    for (updates) |*update| update.deinit(gpa);
    if (updates.len > 0) gpa.free(updates);
}

const max_normalized_tool_image_bytes: usize = 64 * 1024 * 1024;

fn appendToolImageHint(gpa: std.mem.Allocator, result: *tools.ToolResult, hint: []const u8) !void {
    if (hint.len == 0) return;
    const next = if (result.content.len == 0)
        try gpa.dupe(u8, hint)
    else
        try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ result.content, hint });
    gpa.free(result.content);
    result.content = next;
}

fn normalizeOneToolImage(
    gpa: std.mem.Allocator,
    io: Io,
    config: *const AgentConfig,
    data_b64: *[]u8,
    mime_type: *[]u8,
) !?[]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data_b64.*) catch return null;
    if (decoded_len == 0 or decoded_len > max_normalized_tool_image_bytes) return null;
    const decoded = try gpa.alloc(u8, decoded_len);
    defer gpa.free(decoded);
    std.base64.standard.Decoder.decode(decoded, data_b64.*) catch return null;

    var processed = (try ai.image_process.processBytes(gpa, io, decoded, .{
        .auto_resize = config.auto_resize_images,
        .environ = config.process_environ,
    })) orelse return null;
    defer processed.deinit(gpa);

    // Preserve exact extension bytes/base64 spelling when no pixel or format
    // transformation was required.
    if (!processed.was_resized and !processed.was_converted and !processed.orientation_normalized and
        std.ascii.eqlIgnoreCase(mime_type.*, processed.mime_type)) return null;

    const hints = try processed.formatHints(gpa);
    errdefer gpa.free(hints);
    const next_b64 = try gpa.dupe(u8, processed.data_b64);
    errdefer gpa.free(next_b64);
    const next_mime = try gpa.dupe(u8, processed.mime_type);
    errdefer gpa.free(next_mime);
    gpa.free(data_b64.*);
    gpa.free(mime_type.*);
    data_b64.* = next_b64;
    mime_type.* = next_mime;
    return hints;
}

fn normalizeToolResultImages(
    gpa: std.mem.Allocator,
    io: Io,
    config: *const AgentConfig,
    result: *tools.ToolResult,
) !void {
    if (result.image_b64) |*data| {
        if (result.image_mime) |*mime| {
            if (try normalizeOneToolImage(gpa, io, config, data, mime)) |hint| {
                defer gpa.free(hint);
                try appendToolImageHint(gpa, result, hint);
            }
        }
    }
    for (result.images) |*image| {
        if (try normalizeOneToolImage(gpa, io, config, &image.data_b64, &image.mime_type)) |hint| {
            defer gpa.free(hint);
            try appendToolImageHint(gpa, result, hint);
        }
    }
}

fn finalizeToolResult(
    gpa: std.mem.Allocator,
    io: Io,
    config: *const AgentConfig,
    tc: *const ai.ToolCall,
    execution_args: []const u8,
    raw: *const tools.ToolResult,
) !tools.ToolResult {
    var result = try cloneToolResult(gpa, raw);
    errdefer result.deinit(gpa);
    if (config.after_tool_fn) |transform| {
        var tool_override = transform(config.hook_ctx, gpa, tc.name, tc.id, execution_args, raw) catch |err| {
            gpa.free(result.content);
            result.content = try std.fmt.allocPrint(gpa, "afterToolCall failed: {s}", .{@errorName(err)});
            result.is_error = true;
            return result;
        };
        defer if (tool_override) |*owned| owned.deinit(gpa);
        if (tool_override) |owned| {
            gpa.free(result.content);
            result.content = try gpa.dupe(u8, owned.content);
            if (result.image_b64) |value| gpa.free(value);
            result.image_b64 = if (owned.image_b64) |value| try gpa.dupe(u8, value) else null;
            if (result.image_mime) |value| gpa.free(value);
            result.image_mime = if (owned.image_mime) |value| try gpa.dupe(u8, value) else null;
            tools.deinitImages(gpa, result.images);
            result.images = try tools.cloneImages(gpa, owned.images);
            if (result.details_json) |value| gpa.free(value);
            result.details_json = if (owned.details_json) |value| try gpa.dupe(u8, value) else null;
            if (owned.usage) |usage| result.usage = usage;
            if (owned.added_tool_names) |names| {
                deinitOwnedStringList(gpa, result.added_tool_names);
                result.added_tool_names = try cloneOwnedStringList(gpa, names);
            }
            result.is_error = owned.is_error;
            if (owned.terminate) |terminate| result.terminate = terminate;
        }
    }
    // Upstream normalizes extension/tool images after `tool_result` hooks so a
    // hook cannot reintroduce oversized, rotated or unsupported payloads.
    try normalizeToolResultImages(gpa, io, config, &result);
    return result;
}

fn emitToolStart(on_event: ?EventHandler, event_ctx: ?*anyopaque, tc: *const ai.ToolCall) void {
    emit(on_event, event_ctx, .{
        .kind = .tool_execution_start,
        .id = tc.id,
        .name = tc.name,
        .args_json = tc.arguments,
        .text = tc.arguments,
    });
    emit(on_event, event_ctx, .{ .kind = .tool_call, .name = tc.name, .id = tc.id, .text = tc.arguments });
}

fn emitToolEnd(on_event: ?EventHandler, event_ctx: ?*anyopaque, tc: *const ai.ToolCall, result: *const tools.ToolResult) void {
    emit(on_event, event_ctx, .{
        .kind = .tool_execution_end,
        .id = tc.id,
        .name = tc.name,
        .args_json = tc.arguments,
        .text = result.content,
        .is_error = result.is_error,
        .details_json = result.details_json,
        .image_b64 = result.image_b64,
        .image_mime = result.image_mime,
        .images = result.images,
        .usage = result.usage,
        .added_tool_names = result.added_tool_names,
    });
}

fn emitToolUpdates(on_event: ?EventHandler, event_ctx: ?*anyopaque, tc: *const ai.ToolCall, result: *const tools.ToolResult) void {
    for (result.updates) |update| {
        emit(on_event, event_ctx, .{
            .kind = .tool_execution_update,
            .id = tc.id,
            .name = tc.name,
            .args_json = tc.arguments,
            .text = update.content,
            .is_error = update.is_error,
            .details_json = update.details_json,
            .image_b64 = update.image_b64,
            .image_mime = update.image_mime,
            .images = update.images,
            .usage = update.usage,
            .added_tool_names = update.added_tool_names,
            .is_partial = true,
            .delivery = if (update.observer_deferred) .observer_only else .all,
        });
    }
}

const SequentialProgressContext = struct {
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
    tc: *const ai.ToolCall,
};

fn emitExternalToolProgress(raw_ctx: ?*anyopaque, update: ExternalToolUpdate) void {
    const ctx: *SequentialProgressContext = @ptrCast(@alignCast(raw_ctx.?));
    emit(ctx.on_event, ctx.event_ctx, .{
        .kind = .tool_execution_update,
        .id = ctx.tc.id,
        .name = ctx.tc.name,
        .args_json = ctx.tc.arguments,
        .text = update.content,
        .is_error = update.is_error,
        .details_json = update.details_json,
        .image_b64 = update.image_b64,
        .image_mime = update.image_mime,
        .images = update.images,
        .usage = update.usage,
        .added_tool_names = update.added_tool_names,
        .is_partial = true,
        .delivery = if (update.defer_observer) .primary_only else .all,
    });
}

const SequentialRawToolState = struct {
    arena: std.heap.ArenaAllocator,
    result: ?tools.ToolResult = null,
    error_name: ?[]const u8 = null,
};

const SequentialRawToolEvent = union(enum) {
    update: *const tools.ToolUpdate,
    complete,
};

const SequentialRawProgressContext = struct {
    state: *SequentialRawToolState,
    io: Io,
    events: *Io.Queue(SequentialRawToolEvent),
};

fn queueSequentialRawProgress(raw_ctx: ?*anyopaque, update: ExternalToolUpdate) void {
    const ctx: *SequentialRawProgressContext = @ptrCast(@alignCast(raw_ctx.?));
    const owned = cloneParallelToolUpdate(ctx.state.arena.allocator(), update) catch return;
    ctx.events.putOne(ctx.io, .{ .update = owned }) catch {};
}

fn sequentialRawToolWorker(
    state: *SequentialRawToolState,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    tc: *const ai.ToolCall,
    arguments: []const u8,
    events: *Io.Queue(SequentialRawToolEvent),
) Io.Cancelable!void {
    var progress_context = SequentialRawProgressContext{
        .state = state,
        .io = io,
        .events = events,
    };
    state.result = executeRawTool(
        state.arena.allocator(),
        io,
        cwd,
        config,
        tc,
        arguments,
        queueSequentialRawProgress,
        &progress_context,
    ) catch |err| blk: {
        state.error_name = @errorName(err);
        break :blk null;
    };
    events.putOne(io, .complete) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.Closed => return,
    };
}

/// Bash output is drained by helper threads. Run the complete tool call in an
/// I/O task and consume its progress queue on the agent thread, keeping TUI,
/// lifecycle hooks, session state, and JSON writers single-threaded.
fn executeSequentialRawTool(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    tc: *const ai.ToolCall,
    arguments: []const u8,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !tools.ToolResult {
    if (!std.mem.eql(u8, tc.name, "bash") or on_event == null) {
        var progress_context = SequentialProgressContext{
            .on_event = on_event,
            .event_ctx = event_ctx,
            .tc = tc,
        };
        return executeRawTool(
            gpa,
            io,
            cwd,
            config,
            tc,
            arguments,
            emitExternalToolProgress,
            &progress_context,
        );
    }

    var state = SequentialRawToolState{ .arena = .init(std.heap.page_allocator) };
    defer state.arena.deinit();
    var queue_storage: [32]SequentialRawToolEvent = undefined;
    var events: Io.Queue(SequentialRawToolEvent) = .init(&queue_storage);
    defer events.close(io);
    var group: Io.Group = .init;
    group.async(io, sequentialRawToolWorker, .{ &state, io, cwd, config, tc, arguments, &events });

    while (true) {
        const event = events.getOne(io) catch |err| switch (err) {
            error.Canceled => {
                group.cancel(io);
                return error.Canceled;
            },
            error.Closed => break,
        };
        switch (event) {
            .update => |progress| emit(on_event, event_ctx, .{
                .kind = .tool_execution_update,
                .id = tc.id,
                .name = tc.name,
                .args_json = tc.arguments,
                .text = progress.content,
                .is_error = progress.is_error,
                .details_json = progress.details_json,
                .image_b64 = progress.image_b64,
                .image_mime = progress.image_mime,
                .images = progress.images,
                .is_partial = true,
                .delivery = if (progress.observer_deferred) .primary_only else .all,
            }),
            .complete => break,
        }
    }
    try group.await(io);

    if (state.result) |*result| return try cloneToolResult(gpa, result);
    return .{
        .content = try std.fmt.allocPrint(gpa, "tool execution failed: {s}", .{state.error_name orelse "unknown"}),
        .is_error = true,
    };
}

fn persistToolResult(
    sess: *session_mod.Session,
    tc: *const ai.ToolCall,
    result: *const tools.ToolResult,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !void {
    emit(on_event, event_ctx, .{
        .kind = .tool_result,
        .name = tc.name,
        .id = tc.id,
        .text = result.content,
        .is_error = result.is_error,
        .details_json = result.details_json,
        .image_b64 = result.image_b64,
        .image_mime = result.image_mime,
        .images = result.images,
        .usage = result.usage,
        .added_tool_names = result.added_tool_names,
    });
    const p = sess.lastEntryId();
    _ = try sess.appendToolResultStatusWithImages(p, result.content, tc.id, tc.name, result.is_error, result.added_tool_names, result.image_b64, result.image_mime, result.images);
    if (result.usage) |usage| {
        const entry = &sess.entries.items[sess.entries.items.len - 1];
        entry.meta.usage_input = usage.input;
        entry.meta.usage_output = usage.output;
        entry.meta.usage_cache_read = usage.cache_read;
        entry.meta.usage_cache_write = usage.cache_write;
        entry.meta.usage_cache_write_1h = usage.cache_write_1h;
        entry.meta.usage_reasoning = usage.reasoning;
        entry.meta.usage_total = usage.total();
        entry.meta.cost_input = usage.cost.input;
        entry.meta.cost_output = usage.cost.output;
        entry.meta.cost_cache_read = usage.cost.cache_read;
        entry.meta.cost_cache_write = usage.cost.cache_write;
        entry.meta.cost_total = usage.cost.total;
    }
}

const PreparedInvocation = struct {
    arguments: []const u8,
    owned_arguments: ?[]u8 = null,
    immediate: ?tools.ToolResult = null,

    fn deinit(self: *PreparedInvocation, gpa: std.mem.Allocator) void {
        if (self.owned_arguments) |owned| gpa.free(owned);
        if (self.immediate) |*result| result.deinit(gpa);
        self.* = undefined;
    }
};

fn prepareToolInvocation(gpa: std.mem.Allocator, config: *const AgentConfig, schemas_json: []const u8, tc: *const ai.ToolCall) !PreparedInvocation {
    var prepared = PreparedInvocation{ .arguments = tc.arguments };
    errdefer prepared.deinit(gpa);
    const external_claims = if (config.external_tool_exists_fn) |exists| exists(config.hook_ctx, tc.name) else false;
    if (external_claims) {
        if (config.external_prepare_arguments_fn) |prepare_external| {
            const transformed = prepare_external(config.hook_ctx, gpa, tc.name, tc.arguments) catch |err| {
                prepared.immediate = .{
                    .content = try std.fmt.allocPrint(gpa, "prepareArguments failed: {s}", .{@errorName(err)}),
                    .is_error = true,
                };
                return prepared;
            };
            if (transformed) |owned| {
                prepared.owned_arguments = owned;
                prepared.arguments = owned;
            }
        }
    } else if (try tools.prepareArguments(gpa, tc.name, tc.arguments)) |owned| {
        prepared.owned_arguments = owned;
        prepared.arguments = owned;
    }
    if (try tools.validateArgumentsAgainstToolSchemas(gpa, schemas_json, tc.name, prepared.arguments)) |validation_error| {
        prepared.immediate = .{ .content = validation_error, .is_error = true };
        return prepared;
    }
    if (config.before_tool_fn) |before| {
        var decision = before(config.hook_ctx, gpa, tc.name, tc.id, prepared.arguments) catch |err| {
            prepared.immediate = .{
                .content = try std.fmt.allocPrint(gpa, "beforeToolCall failed: {s}", .{@errorName(err)}),
                .is_error = true,
            };
            return prepared;
        };
        defer if (decision) |*owned| owned.deinit(gpa);
        if (decision) |owned| {
            if (owned.arguments_json) |replacement| {
                if (prepared.owned_arguments) |old| gpa.free(old);
                prepared.owned_arguments = try gpa.dupe(u8, replacement);
                prepared.arguments = prepared.owned_arguments.?;
            }
            if (owned.block) {
                prepared.immediate = .{
                    .content = if (owned.reason) |reason|
                        try gpa.dupe(u8, reason)
                    else
                        try gpa.dupe(u8, "Tool execution was blocked"),
                    .is_error = true,
                };
                return prepared;
            }
        }
    }
    if (config.abort_flag) |flag| {
        if (@atomicLoad(bool, flag, .acquire)) {
            prepared.immediate = .{ .content = try gpa.dupe(u8, "Operation aborted"), .is_error = true };
        }
    }
    return prepared;
}

fn executeToolBatchSequential(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    schemas_json: []const u8,
    sess: *session_mod.Session,
    calls: []const ai.ToolCall,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !bool {
    var all_terminate = calls.len > 0;
    for (calls) |*tc| {
        if (config.abort_flag) |f| if (@atomicLoad(bool, f, .acquire)) break;
        emitToolStart(on_event, event_ctx, tc);
        var prepared = try prepareToolInvocation(gpa, config, schemas_json, tc);
        defer prepared.deinit(gpa);

        if (prepared.immediate) |*immediate| {
            emitToolEnd(on_event, event_ctx, tc, immediate);
            try persistToolResult(sess, tc, immediate, on_event, event_ctx);
            all_terminate = all_terminate and immediate.terminate;
            continue;
        }

        var raw: tools.ToolResult = executeSequentialRawTool(
            gpa,
            io,
            cwd,
            config,
            tc,
            prepared.arguments,
            on_event,
            event_ctx,
        ) catch |err| .{
            .content = try std.fmt.allocPrint(gpa, "tool execution failed: {s}", .{@errorName(err)}),
            .is_error = true,
        };
        defer raw.deinit(gpa);
        emitToolUpdates(on_event, event_ctx, tc, &raw);
        var final = try finalizeToolResult(gpa, io, config, tc, prepared.arguments, &raw);
        defer final.deinit(gpa);
        emitToolEnd(on_event, event_ctx, tc, &final);
        try persistToolResult(sess, tc, &final, on_event, event_ctx);
        all_terminate = all_terminate and final.terminate;
    }
    return all_terminate;
}

const ParallelToolState = struct {
    index: usize,
    tc: *const ai.ToolCall,
    arena: std.heap.ArenaAllocator,
    arguments: []const u8,
    owned_arguments: ?[]u8 = null,
    result: ?tools.ToolResult = null,
    error_name: ?[]const u8 = null,
};

const ParallelToolEvent = union(enum) {
    update: struct {
        state_index: usize,
        value: *const tools.ToolUpdate,
    },
    complete: usize,
};

const ParallelProgressContext = struct {
    state: *ParallelToolState,
    io: Io,
    events: *Io.Queue(ParallelToolEvent),
};

fn cloneParallelToolUpdate(allocator: std.mem.Allocator, update: ExternalToolUpdate) !*tools.ToolUpdate {
    const owned = try allocator.create(tools.ToolUpdate);
    owned.* = .{
        .content = try allocator.dupe(u8, update.content),
        .is_error = update.is_error,
        .image_b64 = if (update.image_b64) |value| try allocator.dupe(u8, value) else null,
        .image_mime = if (update.image_mime) |value| try allocator.dupe(u8, value) else null,
        .images = try tools.cloneImages(allocator, update.images),
        .details_json = if (update.details_json) |value| try allocator.dupe(u8, value) else null,
        .usage = update.usage,
        .added_tool_names = try cloneOwnedStringList(allocator, update.added_tool_names),
        .observer_deferred = update.defer_observer,
    };
    return owned;
}

fn queueParallelToolProgress(raw_ctx: ?*anyopaque, update: ExternalToolUpdate) void {
    const ctx: *ParallelProgressContext = @ptrCast(@alignCast(raw_ctx.?));
    const owned = cloneParallelToolUpdate(ctx.state.arena.allocator(), update) catch return;
    ctx.events.putOne(ctx.io, .{ .update = .{
        .state_index = ctx.state.index,
        .value = owned,
    } }) catch {};
}

fn parallelToolWorker(
    state: *ParallelToolState,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    events: *Io.Queue(ParallelToolEvent),
) Io.Cancelable!void {
    const allocator = state.arena.allocator();
    var progress_context = ParallelProgressContext{
        .state = state,
        .io = io,
        .events = events,
    };
    state.result = executeRawTool(
        allocator,
        io,
        cwd,
        config,
        state.tc,
        state.arguments,
        queueParallelToolProgress,
        &progress_context,
    ) catch |err| blk: {
        state.error_name = @errorName(err);
        break :blk null;
    };
    events.putOne(io, .{ .complete = state.index }) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.Closed => return,
    };
}

fn executeToolBatchParallel(
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    config: *const AgentConfig,
    schemas_json: []const u8,
    sess: *session_mod.Session,
    calls: []const ai.ToolCall,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !bool {
    if (calls.len <= 1) return executeToolBatchSequential(gpa, io, cwd, config, schemas_json, sess, calls, on_event, event_ctx);

    const states = try gpa.alloc(ParallelToolState, calls.len);
    defer gpa.free(states);
    for (calls, 0..) |*tc, i| {
        states[i] = .{
            .index = i,
            .tc = tc,
            .arena = .init(std.heap.page_allocator),
            .arguments = tc.arguments,
        };
    }
    defer for (states) |*state| {
        if (state.owned_arguments) |owned| gpa.free(owned);
        state.arena.deinit();
    };

    const event_capacity = @max(calls.len * 4, @as(usize, 8));
    const queue_storage = try gpa.alloc(ParallelToolEvent, event_capacity);
    defer gpa.free(queue_storage);
    var events: Io.Queue(ParallelToolEvent) = .init(queue_storage);
    defer events.close(io);

    const finals = try gpa.alloc(?tools.ToolResult, calls.len);
    defer {
        for (finals) |*item| if (item.*) |*result| result.deinit(gpa);
        gpa.free(finals);
    }
    @memset(finals, null);

    var group: Io.Group = .init;
    var active_tasks: usize = 0;
    var considered: usize = 0;
    for (calls, 0..) |*tc, i| {
        if (config.abort_flag) |f| if (@atomicLoad(bool, f, .acquire)) break;
        considered += 1;
        emitToolStart(on_event, event_ctx, tc);
        var prepared = try prepareToolInvocation(gpa, config, schemas_json, tc);
        defer prepared.deinit(gpa);
        if (prepared.immediate) |*immediate| {
            finals[i] = try cloneToolResult(gpa, immediate);
            emitToolEnd(on_event, event_ctx, tc, &finals[i].?);
            continue;
        }
        states[i].arguments = prepared.arguments;
        if (prepared.owned_arguments) |owned| {
            states[i].owned_arguments = owned;
            states[i].arguments = owned;
            prepared.owned_arguments = null;
        }
        group.async(io, parallelToolWorker, .{ &states[i], io, cwd, config, &events });
        active_tasks += 1;
    }

    var completed: usize = 0;
    while (completed < active_tasks) {
        const event = events.getOne(io) catch |err| switch (err) {
            error.Canceled => {
                group.cancel(io);
                return error.Canceled;
            },
            error.Closed => break,
        };
        switch (event) {
            .update => |progress| {
                const state = &states[progress.state_index];
                emit(on_event, event_ctx, .{
                    .kind = .tool_execution_update,
                    .id = state.tc.id,
                    .name = state.tc.name,
                    .args_json = state.tc.arguments,
                    .text = progress.value.content,
                    .is_error = progress.value.is_error,
                    .details_json = progress.value.details_json,
                    .image_b64 = progress.value.image_b64,
                    .image_mime = progress.value.image_mime,
                    .images = progress.value.images,
                    .usage = progress.value.usage,
                    .added_tool_names = progress.value.added_tool_names,
                    .is_partial = true,
                    .delivery = if (progress.value.observer_deferred) .primary_only else .all,
                });
            },
            .complete => |idx| {
                completed += 1;
                const state = &states[idx];
                var raw_error: ?tools.ToolResult = null;
                defer if (raw_error) |*r| r.deinit(gpa);
                const raw: *const tools.ToolResult = if (state.result) |*result|
                    result
                else blk: {
                    raw_error = .{
                        .content = try std.fmt.allocPrint(gpa, "tool execution failed: {s}", .{state.error_name orelse "unknown"}),
                        .is_error = true,
                    };
                    break :blk &raw_error.?;
                };
                emitToolUpdates(on_event, event_ctx, state.tc, raw);
                var final = try finalizeToolResult(gpa, io, config, state.tc, state.arguments, raw);
                emitToolEnd(on_event, event_ctx, state.tc, &final);
                finals[idx] = final;
            },
        }
    }
    try group.await(io);

    var all_terminate = considered > 0;
    for (calls[0..considered], 0..) |*tc, i| {
        if (finals[i]) |*result| {
            try persistToolResult(sess, tc, result, on_event, event_ctx);
            all_terminate = all_terminate and result.terminate;
        } else all_terminate = false;
    }
    return all_terminate;
}

const SummaryRetryEventContext = struct {
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,

    fn onEvent(raw: ?*anyopaque, event: summarization.Event) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        switch (event.kind) {
            .retry_scheduled => emit(self.on_event, self.event_ctx, .{
                .kind = .summarization_retry_scheduled,
                .attempt = event.attempt,
                .max_attempts = event.max_attempts,
                .delay_ms = event.delay_ms,
                .error_message = event.error_message,
                .text = event.error_message,
                .source = event.source.wireName(),
                .reason = event.reason.wireName(),
            }),
            .retry_attempt_start => emit(self.on_event, self.event_ctx, .{
                .kind = .summarization_retry_attempt_start,
                .attempt = event.attempt,
                .max_attempts = event.max_attempts,
                .source = event.source.wireName(),
                .reason = event.reason.wireName(),
            }),
            .retry_finished => emit(self.on_event, self.event_ctx, .{
                .kind = .summarization_retry_finished,
                .attempt = event.attempt,
                .success = event.success,
                .final_error = event.final_error,
                .source = event.source.wireName(),
                .reason = event.reason.wireName(),
            }),
        }
    }
};

fn compactSession(
    io: Io,
    sess: *session_mod.Session,
    client: ai.ModelClient,
    config: AgentConfig,
    reason: summarization.Reason,
    on_event: ?EventHandler,
    event_ctx: ?*anyopaque,
) !void {
    var retry_events: SummaryRetryEventContext = .{ .on_event = on_event, .event_ctx = event_ctx };
    compaction.compact(sess, .{
        .io = io,
        .settings = .{
            .enabled = true,
            .reserve_tokens = config.compaction_reserve_tokens,
            .keep_recent_tokens = config.compaction_keep_recent_tokens,
        },
        .client = client,
        .reason = reason,
        .retry_enabled = config.retry_enabled,
        .retry_max_retries = config.retry_max_retries,
        .retry_base_delay_ms = config.retry_base_delay_ms,
        .abort_flag = config.abort_flag,
        .retry_abort_flag = config.retry_abort_flag,
        .on_retry_event = SummaryRetryEventContext.onEvent,
        .retry_event_ctx = &retry_events,
        .hook_ctx = config.hook_ctx,
        .before_hook_fn = config.before_compact_fn,
        .after_hook_fn = config.after_compact_fn,
        .will_retry = reason == .overflow,
    }) catch |err| {
        emit(on_event, event_ctx, .{
            .kind = .session_compact_failed,
            .source = "compaction",
            .reason = reason.wireName(),
            .will_retry = reason == .overflow,
            .error_message = @errorName(err),
            .text = @errorName(err),
            .is_error = true,
        });
        return err;
    };
}

fn emit(handler: ?EventHandler, ctx: ?*anyopaque, event: AgentEvent) void {
    if (handler) |h| h(ctx, event);
}

fn mergeToolSchemaArrays(gpa: std.mem.Allocator, builtins_json: []const u8, extras_json: []const u8) ![]u8 {
    var builtins = std.json.parseFromSlice(std.json.Value, gpa, builtins_json, .{}) catch return error.InvalidToolSchemaJson;
    defer builtins.deinit();
    var extras = std.json.parseFromSlice(std.json.Value, gpa, extras_json, .{}) catch return error.InvalidToolSchemaJson;
    defer extras.deinit();
    if (builtins.value != .array or extras.value != .array) return error.InvalidToolSchemaJson;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('[');
    var first = true;
    for (builtins.value.array.items) |item| {
        const name = toolSchemaName(item) orelse return error.InvalidToolSchemaJson;
        var overridden = false;
        for (extras.value.array.items) |extra| {
            const extra_name = toolSchemaName(extra) orelse return error.InvalidToolSchemaJson;
            if (std.mem.eql(u8, name, extra_name)) {
                overridden = true;
                break;
            }
        }
        if (overridden) continue;
        if (!first) try out.writer.writeByte(',');
        first = false;
        try std.json.Stringify.value(item, .{}, &out.writer);
    }
    for (extras.value.array.items) |item| {
        _ = toolSchemaName(item) orelse return error.InvalidToolSchemaJson;
        if (!first) try out.writer.writeByte(',');
        first = false;
        try std.json.Stringify.value(item, .{}, &out.writer);
    }
    try out.writer.writeByte(']');
    return try out.toOwnedSlice();
}

fn toolSchemaName(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;
    const function = value.object.get("function") orelse return null;
    if (function != .object) return null;
    const name = function.object.get("name") orelse return null;
    return if (name == .string and name.string.len > 0) name.string else null;
}

fn looksLikeContextOverflow(msg: []const u8) bool {
    const needles = [_][]const u8{
        "context_length",
        "maximum context",
        "context window",
        "too many tokens",
        "prompt is too long",
        "token limit",
        "max_tokens",
        "CONTEXT_LENGTH",
    };
    for (needles) |n| {
        if (std.mem.indexOf(u8, msg, n) != null) return true;
    }
    return false;
}

const COMPACTION_SUMMARY_PREFIX = "The conversation history before this point was compacted into the following summary:\n\n<summary>\n";
const COMPACTION_SUMMARY_SUFFIX = "\n</summary>";
const BRANCH_SUMMARY_PREFIX = "The following is a summary of a branch that this conversation came back from:\n\n<summary>\n";
const BRANCH_SUMMARY_SUFFIX = "</summary>";

fn projectedSummaryContent(gpa: std.mem.Allocator, entry: session_mod.SessionEntry) ![]u8 {
    return switch (entry.entry_type) {
        .compaction => try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ COMPACTION_SUMMARY_PREFIX, entry.content, COMPACTION_SUMMARY_SUFFIX }),
        .branch_summary => try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ BRANCH_SUMMARY_PREFIX, entry.content, BRANCH_SUMMARY_SUFFIX }),
        else => error.NotSummaryEntry,
    };
}

const ChatBuildOptions = struct {
    include_retry_failures: bool = false,
};

fn buildChatMessages(gpa: std.mem.Allocator, sess: *session_mod.Session, config: AgentConfig) ![]ai.ChatMessage {
    return buildChatMessagesWithOptions(gpa, sess, config, .{});
}

fn buildChatMessagesWithOptions(
    gpa: std.mem.Allocator,
    sess: *session_mod.Session,
    config: AgentConfig,
    options: ChatBuildOptions,
) ![]ai.ChatMessage {
    var list: std.ArrayList(ai.ChatMessage) = .empty;
    errdefer {
        for (list.items) |message| if (message.owned_content) gpa.free(message.content);
        list.deinit(gpa);
    }

    const system_body = if (config.context_prompt.len > 0)
        try std.fmt.allocPrint(gpa, "{s}\n\n{s}", .{ config.system_prompt, config.context_prompt })
    else
        try gpa.dupe(u8, config.system_prompt);
    try list.append(gpa, .{
        .role = "system",
        .content = system_body,
        .owned_content = true,
    });

    const branch = try sess.contextEntries(gpa);
    defer gpa.free(branch);
    if (branch.len > 0) {
        for (branch) |e| {
            if (!options.include_retry_failures and sess.isEntryExcludedFromActiveContext(e.id)) {
                continue;
            }
            if (e.entry_type == .compaction or e.entry_type == .branch_summary) {
                const content = try projectedSummaryContent(gpa, e.*);
                errdefer gpa.free(content);
                try list.append(gpa, .{
                    .role = "user",
                    .content = content,
                    .owned_content = true,
                    .timestamp = if (e.timestamp.len > 0) e.timestamp else null,
                });
                continue;
            }
            const is_bash = std.mem.eql(u8, e.role, "bashExecution");
            if (std.mem.eql(u8, e.role, "user") or
                std.mem.eql(u8, e.role, "assistant") or
                std.mem.eql(u8, e.role, "tool") or
                std.mem.eql(u8, e.role, "system") or
                (is_bash and !e.bash_exclude_from_context))
            {
                try list.append(gpa, .{
                    .role = if (is_bash) "user" else e.role,
                    .content = e.content,
                    .custom_type = e.custom_type,
                    .provider = if (e.meta.provider.len > 0) e.meta.provider else null,
                    .api = if (e.meta.api.len > 0) e.meta.api else null,
                    .model = if (e.meta.model.len > 0) e.meta.model else null,
                    .response_id = if (e.meta.response_id.len > 0) e.meta.response_id else null,
                    .response_model = if (e.meta.response_model.len > 0) e.meta.response_model else null,
                    .raw_stop_reason = if (e.meta.raw_stop_reason.len > 0) e.meta.raw_stop_reason else null,
                    .end_turn = e.meta.end_turn,
                    .thinking = if (e.meta.thinking.len > 0) e.meta.thinking else null,
                    .thinking_signature = if (e.meta.thinking_signature.len > 0) e.meta.thinking_signature else null,
                    .thinking_redacted = e.meta.thinking_redacted,
                    .tool_call_id = e.tool_call_id,
                    .tool_calls_json = e.tool_calls_json,
                    .tool_name = e.tool_name,
                    .added_tool_names = e.added_tool_names,
                    .tool_is_error = e.tool_is_error,
                    .image_b64 = e.image_b64,
                    .image_mime = e.image_mime,
                    .images = e.images,
                    .stop_reason = if (e.meta.stop_reason.len > 0) e.meta.stop_reason else null,
                    .timestamp = if (e.timestamp.len > 0) e.timestamp else null,
                    .usage = .{
                        .input = e.meta.usage_input,
                        .output = e.meta.usage_output,
                        .cache_read = e.meta.usage_cache_read,
                        .cache_write = e.meta.usage_cache_write,
                        .cache_write_1h = e.meta.usage_cache_write_1h,
                        .reasoning = e.meta.usage_reasoning,
                        .total_tokens = e.meta.usage_total,
                        .cost = .{
                            .input = e.meta.cost_input,
                            .output = e.meta.cost_output,
                            .cache_read = e.meta.cost_cache_read,
                            .cache_write = e.meta.cost_cache_write,
                            .total = e.meta.cost_total,
                        },
                    },
                });
            }
        }
    } else {
        for (sess.entries.items) |e| {
            if (!options.include_retry_failures and sess.isEntryExcludedFromActiveContext(e.id)) continue;
            if (e.entry_type == .compaction or e.entry_type == .branch_summary) {
                const content = try projectedSummaryContent(gpa, e);
                errdefer gpa.free(content);
                try list.append(gpa, .{
                    .role = "user",
                    .content = content,
                    .owned_content = true,
                    .timestamp = if (e.timestamp.len > 0) e.timestamp else null,
                });
                continue;
            }
            const is_bash = std.mem.eql(u8, e.role, "bashExecution");
            if (std.mem.eql(u8, e.role, "user") or
                std.mem.eql(u8, e.role, "assistant") or
                std.mem.eql(u8, e.role, "tool") or
                (is_bash and !e.bash_exclude_from_context))
            {
                try list.append(gpa, .{
                    .role = if (is_bash) "user" else e.role,
                    .content = e.content,
                    .custom_type = e.custom_type,
                    .provider = if (e.meta.provider.len > 0) e.meta.provider else null,
                    .api = if (e.meta.api.len > 0) e.meta.api else null,
                    .model = if (e.meta.model.len > 0) e.meta.model else null,
                    .response_id = if (e.meta.response_id.len > 0) e.meta.response_id else null,
                    .response_model = if (e.meta.response_model.len > 0) e.meta.response_model else null,
                    .raw_stop_reason = if (e.meta.raw_stop_reason.len > 0) e.meta.raw_stop_reason else null,
                    .end_turn = e.meta.end_turn,
                    .thinking = if (e.meta.thinking.len > 0) e.meta.thinking else null,
                    .thinking_signature = if (e.meta.thinking_signature.len > 0) e.meta.thinking_signature else null,
                    .thinking_redacted = e.meta.thinking_redacted,
                    .tool_call_id = e.tool_call_id,
                    .tool_calls_json = e.tool_calls_json,
                    .tool_name = e.tool_name,
                    .added_tool_names = e.added_tool_names,
                    .tool_is_error = e.tool_is_error,
                    .image_b64 = e.image_b64,
                    .image_mime = e.image_mime,
                    .images = e.images,
                    .stop_reason = if (e.meta.stop_reason.len > 0) e.meta.stop_reason else null,
                    .timestamp = if (e.timestamp.len > 0) e.timestamp else null,
                    .usage = .{
                        .input = e.meta.usage_input,
                        .output = e.meta.usage_output,
                        .cache_read = e.meta.usage_cache_read,
                        .cache_write = e.meta.usage_cache_write,
                        .cache_write_1h = e.meta.usage_cache_write_1h,
                        .reasoning = e.meta.usage_reasoning,
                        .total_tokens = e.meta.usage_total,
                        .cost = .{
                            .input = e.meta.cost_input,
                            .output = e.meta.cost_output,
                            .cache_read = e.meta.cost_cache_read,
                            .cache_write = e.meta.cost_cache_write,
                            .total = e.meta.cost_total,
                        },
                    },
                });
            }
        }
    }

    return try list.toOwnedSlice(gpa);
}

fn freeChatMessages(gpa: std.mem.Allocator, messages: []ai.ChatMessage) void {
    for (messages) |message| {
        if (message.owned_content) gpa.free(message.content);
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
        try aw.writer.writeAll("}");
        if (tc.thought_signature.len > 0) {
            try aw.writer.writeAll(",\"thoughtSignature\":");
            try std.json.Stringify.value(tc.thought_signature, .{}, &aw.writer);
        }
        try aw.writer.writeAll("}");
    }
    try aw.writer.writeAll("]");
    return try aw.toOwnedSlice();
}

test "tool call serialization preserves provider thought signature" {
    const gpa = std.testing.allocator;
    var calls = [_]ai.ToolCall{.{
        .id = try gpa.dupe(u8, "g1"),
        .name = try gpa.dupe(u8, "read"),
        .arguments = try gpa.dupe(u8, "{}"),
        .thought_signature = try gpa.dupe(u8, "opaque-google-tool-sig"),
    }};
    defer calls[0].deinit(gpa);
    const json = try serializeToolCallsOpenAI(gpa, &calls);
    defer gpa.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"thoughtSignature\":\"opaque-google-tool-sig\"") != null);
}

test "failed overflow compaction emits session_compact_failed with retry intent" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    var model = try mock.MockModel.loadFromJson(gpa,
        \\[{"content":"429 insufficient_quota billing exhausted","stop_reason":"error","tool_calls":[]}]
    );
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "compact-failed-event", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..6) |index| {
        const content = try std.fmt.allocPrint(gpa, "event-message-{d}", .{index});
        defer gpa.free(content);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", content, null, null);
    }

    const Probe = struct {
        count: usize = 0,
        source: []const u8 = "",
        reason: []const u8 = "",
        will_retry: bool = false,
        error_message: ?[]const u8 = null,
        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            if (event.kind != .session_compact_failed) return;
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count += 1;
            self.source = event.source;
            self.reason = event.reason;
            self.will_retry = event.will_retry;
            self.error_message = event.error_message;
        }
    };
    var probe = Probe{};
    try std.testing.expectError(error.SummarizationFailed, compactSession(std.testing.io, &sess, model.client(), .{
        .compaction_keep_recent_tokens = 4,
        .retry_enabled = false,
    }, .overflow, Probe.onEvent, &probe));
    try std.testing.expectEqual(@as(usize, 1), probe.count);
    try std.testing.expectEqualStrings("compaction", probe.source);
    try std.testing.expectEqualStrings("overflow", probe.reason);
    try std.testing.expect(probe.will_retry);
    try std.testing.expectEqualStrings("SummarizationFailed", probe.error_message.?);
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
        \\  {"content":"Writing marker.","stream_chunks":["Writing ","marker."],"tool_calls":[{"id":"c1","name":"write","arguments":"{\"path\":\"marker.txt\",\"content\":\"agent-loop-ok\"}"}]},
        \\  {"content":"Marker written successfully.","stream_chunks":["Marker ","written successfully."],"tool_calls":[]}
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
    try std.testing.expect(result.text_deltas >= 2);

    const marker_path = try std.fs.path.join(gpa, &.{ tmp_path, "marker.txt" });
    defer gpa.free(marker_path);
    const data = try std.Io.Dir.cwd().readFileAlloc(io, marker_path, gpa, .limited(1024));
    defer gpa.free(data);
    try std.testing.expectEqualStrings("agent-loop-ok", data);
}

const AgentEndContinuationProbe = struct {
    pending: bool = false,
    queued_once: bool = false,
    agent_starts: usize = 0,
    agent_ends: usize = 0,

    fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
        const self: *AgentEndContinuationProbe = @ptrCast(@alignCast(raw.?));
        switch (event.kind) {
            .agent_start => self.agent_starts += 1,
            .agent_end => {
                self.agent_ends += 1;
                if (!self.queued_once) self.pending = true;
            },
            else => {},
        }
    }

    fn flush(
        raw: ?*anyopaque,
        gpa: std.mem.Allocator,
        sess: *session_mod.Session,
        config: *AgentConfig,
        client: *ai.ModelClient,
        steering: *std.ArrayList([]u8),
        followups: *std.ArrayList([]u8),
        stop_requested: *bool,
    ) anyerror!void {
        _ = sess;
        _ = config;
        _ = client;
        _ = steering;
        _ = stop_requested;
        const self: *AgentEndContinuationProbe = @ptrCast(@alignCast(raw.?));
        if (!self.pending) return;
        self.pending = false;
        self.queued_once = true;
        const owned = try gpa.dupe(u8, "queued by agent_end");
        errdefer gpa.free(owned);
        try followups.append(gpa, owned);
    }
};

test "agent_end runtime actions can queue a durable continuation" {
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
        \\  {"content":"first","tool_calls":[]},
        \\  {"content":"second","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "agent-end-continuation", tmp_path);
    defer sess.deinit();
    var probe = AgentEndContinuationProbe{};

    var result = try run(gpa, io, tmp_path, model.client(), &sess, "initial", .{
        .event_observer_fn = AgentEndContinuationProbe.onEvent,
        .event_observer_ctx = &probe,
        .flush_runtime_actions_fn = AgentEndContinuationProbe.flush,
        .flush_runtime_actions_ctx = &probe,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqualStrings("second", result.final_text);
    try std.testing.expectEqual(@as(usize, 2), result.turns);
    try std.testing.expectEqual(@as(usize, 2), probe.agent_starts);
    try std.testing.expectEqual(@as(usize, 2), probe.agent_ends);
    var queued_user_seen = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "queued by agent_end")) {
            queued_user_seen = true;
            break;
        }
    }
    try std.testing.expect(queued_user_seen);
}

const DeferredCustomMessageProbe = struct {
    pending: bool = false,
    injected: bool = false,

    fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (event.kind == .message_end and std.mem.eql(u8, event.name, "assistant") and !self.injected) self.pending = true;
    }

    fn flush(
        raw: ?*anyopaque,
        _: std.mem.Allocator,
        session: *session_mod.Session,
        _: *AgentConfig,
        _: *ai.ModelClient,
        _: *std.ArrayList([]u8),
        _: *std.ArrayList([]u8),
        _: *bool,
    ) anyerror!void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (!self.pending) return;
        self.pending = false;
        self.injected = true;
        _ = try session.appendCustomMessage("notice", "runtime note", true);
    }

    fn tool(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
        if (!std.mem.eql(u8, name, "ordering_probe")) return null;
        return .{ .content = try allocator.dupe(u8, "tool complete"), .is_error = false };
    }
};

test "runtime custom messages append after an assistant tool-call result" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    var model = try mock.MockModel.loadFromJson(gpa,
        \\[
        \\ {"content":"calling","tool_calls":[{"id":"order-1","name":"ordering_probe","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    );
    defer model.deinit(gpa);
    var session = try session_mod.Session.init(gpa, "custom-order", path_buf[0..n]);
    defer session.deinit();
    var probe = DeferredCustomMessageProbe{};
    var result = try run(gpa, io, path_buf[0..n], model.client(), &session, "go", .{
        .extra_tools_json = "[{\"type\":\"function\",\"function\":{\"name\":\"ordering_probe\",\"parameters\":{\"type\":\"object\"}}}]",
        .external_tool_fn = DeferredCustomMessageProbe.tool,
        .event_observer_fn = DeferredCustomMessageProbe.onEvent,
        .event_observer_ctx = &probe,
        .flush_runtime_actions_fn = DeferredCustomMessageProbe.flush,
        .flush_runtime_actions_ctx = &probe,
    }, null, null);
    defer result.deinit(gpa);
    var tool_index: ?usize = null;
    var custom_index: ?usize = null;
    for (session.entries.items, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_call_id orelse "", "order-1")) tool_index = index;
        if (entry.entry_type == .custom_message and std.mem.eql(u8, entry.content, "runtime note")) custom_index = index;
    }
    try std.testing.expect(tool_index != null and custom_index != null);
    try std.testing.expect(tool_index.? < custom_index.?);
}

const ImageRecorder = struct {
    image_count: usize = 0,
    final_user_text_seen: bool = false,

    fn client(self: *ImageRecorder) ai.ModelClient {
        return .{ .ptr = self, .completeFn = completeImpl };
    }

    fn completeImpl(ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ai.ChatMessage, tools_json: []const u8) anyerror!ai.ModelResponse {
        _ = tools_json;
        const self: *ImageRecorder = @ptrCast(@alignCast(ptr));
        self.image_count = 0;
        self.final_user_text_seen = false;
        for (messages) |message| {
            self.image_count += message.imageCount();
            if (std.mem.eql(u8, message.role, "user") and std.mem.eql(u8, message.content, "describe both")) {
                self.final_user_text_seen = true;
            }
        }
        return .{
            .content = try gpa.dupe(u8, "ok"),
            .tool_calls = try gpa.alloc(ai.ToolCall, 0),
        };
    }
};

test "agent loop persists and sends multiple user images in order" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var sess = try session_mod.Session.init(gpa, "image-loop", tmp_path);
    defer sess.deinit();
    var recorder = ImageRecorder{};
    const input_images = [_]UserImage{
        .{ .data_b64 = "AQID", .mime_type = "image/png" },
        .{ .data_b64 = "BAUG", .mime_type = "image/jpeg" },
    };
    var result = try runWithImages(gpa, io, tmp_path, recorder.client(), &sess, "describe both", &input_images, .{}, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), recorder.image_count);
    try std.testing.expect(recorder.final_user_text_seen);
    try std.testing.expect(sess.entries.items.len >= 2);
    try std.testing.expectEqualStrings("describe both", sess.entries.items[0].content);
    try std.testing.expectEqualStrings("AQID", sess.entries.items[0].image_b64.?);
    try std.testing.expectEqual(@as(usize, 1), sess.entries.items[0].images.len);
    try std.testing.expectEqualStrings("BAUG", sess.entries.items[0].images[0].data_b64);
    try std.testing.expectEqualStrings("image/jpeg", sess.entries.items[0].images[0].mime_type);
}

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

const BeforeStartProbe = struct {
    called: bool = false,
    saw_cwd: bool = false,
    saw_prompt: bool = false,
    saw_system: bool = false,
    saw_image: bool = false,

    fn invoke(
        ctx: ?*anyopaque,
        gpa: std.mem.Allocator,
        cwd: []const u8,
        prompt: []const u8,
        system_prompt: []const u8,
        images: []const UserImage,
    ) anyerror!?BeforeAgentStartResult {
        const self: *@This() = @ptrCast(@alignCast(ctx.?));
        self.called = true;
        self.saw_cwd = cwd.len > 0;
        self.saw_prompt = std.mem.eql(u8, prompt, "hello start");
        self.saw_system = std.mem.eql(u8, system_prompt, "BASE\n\nDISCOVERED");
        self.saw_image = images.len == 1 and std.mem.eql(u8, images[0].mime_type, "image/png");

        const messages = try gpa.alloc(ExtensionContextMessage, 1);
        errdefer gpa.free(messages);
        messages[0] = .{
            .custom_type = try gpa.dupe(u8, "mode-context"),
            .content = try gpa.dupe(u8, "extension injected context"),
            .display = false,
        };
        return .{
            .system_prompt = try gpa.dupe(u8, "OVERRIDE"),
            .messages = messages,
        };
    }
};

test "before_agent_start can replace assembled system prompt and append durable custom context" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_len = try tmp.dir.realPath(io, &cwd_buf);
    const cwd = cwd_buf[0..cwd_len];

    var sess = try session_mod.Session.init(gpa, "before-start", cwd);
    defer sess.deinit();
    var recorder = SystemRecorder{ .gpa = gpa };
    defer recorder.deinit();
    var probe = BeforeStartProbe{};
    const images = [_]UserImage{.{ .data_b64 = "AQID", .mime_type = "image/png" }};
    var result = try runWithImages(gpa, io, cwd, recorder.client(), &sess, "hello start", &images, .{
        .system_prompt = "BASE",
        .context_prompt = "DISCOVERED",
        .hook_ctx = &probe,
        .before_agent_start_fn = BeforeStartProbe.invoke,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expect(probe.called and probe.saw_cwd and probe.saw_prompt and probe.saw_system and probe.saw_image);
    try std.testing.expectEqualStrings("OVERRIDE", recorder.last_system.?);
    var found = false;
    for (sess.entries.items) |entry| {
        if (entry.entry_type != .custom_message) continue;
        try std.testing.expectEqualStrings("mode-context", entry.custom_type.?);
        try std.testing.expectEqualStrings("extension injected context", entry.content);
        found = true;
    }
    try std.testing.expect(found);
}

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

    cfg.context_prompt = "CONTEXT-V2-RELOADED";
    var result2 = try run(gpa, io, tmp_path, recorder.client(), &sess, "again", cfg, null, null);
    defer result2.deinit(gpa);
    try std.testing.expect(std.mem.indexOf(u8, recorder.last_system.?, "CONTEXT-V2-RELOADED") != null);
}

test "loop emits agent_start and tool_execution events" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script =
        \\[{"content":"x","tool_calls":[{"id":"c1","name":"ls","arguments":"{}"}]},{"content":"done","tool_calls":[]}]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "ev", tmp_path);
    defer sess.deinit();

    const C = struct {
        saw_agent_start: bool = false,
        saw_tool_start: bool = false,
        saw_tool_end: bool = false,
        saw_agent_end: bool = false,
        fn onEvent(ptr: ?*anyopaque, e: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            switch (e.kind) {
                .agent_start => self.saw_agent_start = true,
                .tool_execution_start => self.saw_tool_start = true,
                .tool_execution_end => self.saw_tool_end = true,
                .agent_end => self.saw_agent_end = true,
                else => {},
            }
        }
    };
    var c = C{};
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "ls", .{}, C.onEvent, &c);
    defer result.deinit(gpa);
    try std.testing.expect(c.saw_agent_start);
    try std.testing.expect(c.saw_tool_start);
    try std.testing.expect(c.saw_tool_end);
    try std.testing.expect(c.saw_agent_end);
}

test "agent hook callbacks mutate prompt and persisted tool result" {
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
        \\ {"content":"run","tool_calls":[{"id":"c1","name":"ls","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "hooked", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        fn before(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8) anyerror!?[]u8 {
            return try allocator.dupe(u8, "rewritten prompt");
        }
        fn after(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, _: *const tools.ToolResult) anyerror!?ToolResultOverride {
            const names = try allocator.alloc([]const u8, 2);
            errdefer allocator.free(names);
            names[0] = try allocator.dupe(u8, "late_one");
            errdefer allocator.free(names[0]);
            names[1] = try allocator.dupe(u8, "late_two");
            return .{
                .content = try allocator.dupe(u8, "hooked result"),
                .is_error = true,
                .usage = .{
                    .input = 9,
                    .output = 8,
                    .cache_read = 7,
                    .cache_write = 6,
                    .cache_write_1h = 3,
                    .reasoning = 2,
                    .total_tokens = 30,
                    .cost = .{ .input = 0.1, .output = 0.2, .cache_read = 0.3, .cache_write = 0.4, .total = 1.0 },
                },
                .added_tool_names = names,
            };
        }
    };
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "original prompt", .{
        .before_prompt_fn = Hook.before,
        .after_tool_fn = Hook.after,
    }, null, null);
    defer result.deinit(gpa);

    var saw_user = false;
    var saw_tool = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "rewritten prompt")) saw_user = true;
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.content, "hooked result") and entry.tool_is_error) {
            try std.testing.expectEqual(@as(u64, 30), entry.meta.usage_total);
            try std.testing.expectEqual(@as(?u64, 3), entry.meta.usage_cache_write_1h);
            try std.testing.expectEqual(@as(usize, 2), entry.added_tool_names.len);
            try std.testing.expectEqualStrings("late_two", entry.added_tool_names[1]);
            saw_tool = true;
        }
    }
    try std.testing.expect(saw_user);
    try std.testing.expect(saw_tool);
}

test "agent dispatches external tool while builtins can be disabled" {
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
        \\ {"content":"call","tool_calls":[{"id":"x1","name":"external_ping","arguments":"{\"value\":1}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "external", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "external_ping")) return null;
            return .{ .content = try allocator.dupe(u8, "pong-ext"), .is_error = false };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"external_ping\",\"description\":\"ping\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "use ext", .{
        .disable_builtin_tools = true,
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
    }, null, null);
    defer result.deinit(gpa);

    var saw_external = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_name orelse "", "external_ping")) {
            try std.testing.expectEqualStrings("pong-ext", entry.content);
            try std.testing.expect(!entry.tool_is_error);
            saw_external = true;
        }
    }
    try std.testing.expect(saw_external);
}

test "extension dispatcher can replace a built-in tool and its schema" {
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
        \\ {"content":"call","tool_calls":[{"id":"r1","name":"read","arguments":"{\"virtualPath\":\"vault://one\"}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "override", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "read");
        }
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, arguments: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "read")) return null;
            try std.testing.expect(std.mem.indexOf(u8, arguments, "vault://one") != null);
            return .{ .content = try allocator.dupe(u8, "extension-read"), .is_error = false };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"read\",\"description\":\"virtual read\",\"parameters\":{\"type\":\"object\",\"properties\":{\"virtualPath\":{\"type\":\"string\"}},\"required\":[\"virtualPath\"]}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "read virtual", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
        .external_tool_exists_fn = External.owns,
    }, null, null);
    defer result.deinit(gpa);

    var saw_override = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_name orelse "", "read")) {
            try std.testing.expectEqualStrings("extension-read", entry.content);
            saw_override = true;
        }
    }
    try std.testing.expect(saw_override);
}

test "extension dispatcher can delegate an overridden built-in back to Zig" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "native.txt", .data = "native-fallback" });
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script =
        \\[
        \\ {"content":"call","tool_calls":[{"id":"r2","name":"read","arguments":"{\"path\":\"native.txt\"}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "delegate", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "read");
        }
        fn exec(_: ?*anyopaque, _: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "read")) return null;
            return null;
        }
    };
    const schema = try tools.toolSchemasJson(gpa, .{ .allow = &.{"read"} });
    defer gpa.free(schema);
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "read native", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
        .external_tool_exists_fn = External.owns,
    }, null, null);
    defer result.deinit(gpa);

    var saw_native = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_name orelse "", "read")) {
            try std.testing.expect(std.mem.indexOf(u8, entry.content, "native-fallback") != null);
            saw_native = true;
        }
    }
    try std.testing.expect(saw_native);
}

test "length-truncated assistant tool calls are failed without execution" {
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
        \\ {"content":"truncated","stop_reason":"length","tool_calls":[{"id":"x1","name":"external_ping","arguments":"{\\\"value\\\":1}"}]},
        \\ {"content":"recovered","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "length-tool", tmp_path);
    defer sess.deinit();

    const External = struct {
        var calls: usize = 0;
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "external_ping")) return null;
            calls += 1;
            return .{ .content = try allocator.dupe(u8, "should-not-run"), .is_error = false };
        }
    };
    External.calls = 0;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"external_ping\",\"description\":\"ping\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "use ext", .{
        .disable_builtin_tools = true,
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 0), External.calls);
    try std.testing.expectEqualStrings("recovered", result.final_text);
    var saw_failed = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and entry.tool_is_error and
            std.mem.indexOf(u8, entry.content, "output token limit") != null)
        {
            saw_failed = true;
        }
    }
    try std.testing.expect(saw_failed);
}

fn testSleepMs(io: Io, ms: u64) void {
    const timeout: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@intCast(ms)), .clock = .real } };
    timeout.sleep(io) catch {};
}

test "parallel tool end events follow completion order while persistence follows source order" {
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
        \\ {"content":"run","tool_calls":[{"id":"c1","name":"slow_probe","arguments":"{}"},{"id":"c2","name":"fast_probe","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "parallel-order", tmp_path);
    defer sess.deinit();

    const Ctx = struct {
        io: Io,
        end_order: [2]u8 = .{ 0, 0 },
        end_count: usize = 0,

        fn exec(ptr: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (std.mem.eql(u8, name, "slow_probe")) testSleepMs(self.io, 40);
            if (!std.mem.eql(u8, name, "slow_probe") and !std.mem.eql(u8, name, "fast_probe")) return null;
            return .{ .content = try allocator.dupe(u8, name), .is_error = false };
        }

        fn event(ptr: ?*anyopaque, e: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (e.kind != .tool_execution_end or self.end_count >= self.end_order.len) return;
            self.end_order[self.end_count] = if (std.mem.eql(u8, e.id, "c1")) 1 else if (std.mem.eql(u8, e.id, "c2")) 2 else 9;
            self.end_count += 1;
        }
    };
    var ctx = Ctx{ .io = io };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"slow_probe\",\"parameters\":{\"type\":\"object\"}}},{\"type\":\"function\",\"function\":{\"name\":\"fast_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Ctx.exec,
        .hook_ctx = &ctx,
    }, Ctx.event, &ctx);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), ctx.end_count);
    try std.testing.expectEqualSlices(u8, &.{ 2, 1 }, &ctx.end_order);

    var tool_ids: [2][]const u8 = undefined;
    var tool_count: usize = 0;
    for (sess.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.role, "tool")) continue;
        if (tool_count < tool_ids.len) tool_ids[tool_count] = entry.tool_call_id orelse "";
        tool_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), tool_count);
    try std.testing.expectEqualStrings("c1", tool_ids[0]);
    try std.testing.expectEqualStrings("c2", tool_ids[1]);
}

test "one sequential tool forces the full batch to execute sequentially" {
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
        \\ {"content":"run","tool_calls":[{"id":"c1","name":"slow_probe","arguments":"{}"},{"id":"c2","name":"fast_probe","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "sequential-mode", tmp_path);
    defer sess.deinit();

    const Ctx = struct {
        io: Io,
        first_done: bool = false,
        overlap_observed: bool = false,

        fn mode(_: ?*anyopaque, name: []const u8) ToolExecutionMode {
            return if (std.mem.eql(u8, name, "slow_probe")) .sequential else .parallel;
        }

        fn exec(ptr: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            const self: *@This() = @ptrCast(@alignCast(ptr.?));
            if (std.mem.eql(u8, name, "slow_probe")) {
                testSleepMs(self.io, 30);
                @atomicStore(bool, &self.first_done, true, .release);
            } else if (std.mem.eql(u8, name, "fast_probe")) {
                if (!@atomicLoad(bool, &self.first_done, .acquire)) @atomicStore(bool, &self.overlap_observed, true, .release);
            } else return null;
            return .{ .content = try allocator.dupe(u8, name), .is_error = false };
        }
    };
    var ctx = Ctx{ .io = io };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"slow_probe\",\"parameters\":{\"type\":\"object\"}}},{\"type\":\"function\",\"function\":{\"name\":\"fast_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Ctx.exec,
        .external_tool_mode_fn = Ctx.mode,
        .hook_ctx = &ctx,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expect(@atomicLoad(bool, &ctx.first_done, .acquire));
    try std.testing.expect(!@atomicLoad(bool, &ctx.overlap_observed, .acquire));
}

test "agent stops after a tool batch only when every result terminates" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script =
        \\[{"content":"terminate-now","tool_calls":[{"id":"c1","name":"term_a","arguments":"{}"},{"id":"c2","name":"term_b","arguments":"{}"}]}]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "terminate-all", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.startsWith(u8, name, "term_")) return null;
            return .{ .content = try allocator.dupe(u8, name), .is_error = false, .terminate = true };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"term_a\",\"parameters\":{\"type\":\"object\"}}},{\"type\":\"function\",\"function\":{\"name\":\"term_b\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), m.index);
    try std.testing.expectEqual(@as(usize, 1), result.turns);
    try std.testing.expectEqualStrings("terminate-now", result.final_text);
}

test "agent continues when only some parallel tool results terminate" {
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
        \\ {"content":"mixed","tool_calls":[{"id":"c1","name":"term_yes","arguments":"{}"},{"id":"c2","name":"term_no","arguments":"{}"}]},
        \\ {"content":"continued","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "terminate-mixed", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.startsWith(u8, name, "term_")) return null;
            return .{
                .content = try allocator.dupe(u8, name),
                .is_error = false,
                .terminate = std.mem.eql(u8, name, "term_yes"),
            };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"term_yes\",\"parameters\":{\"type\":\"object\"}}},{\"type\":\"function\",\"function\":{\"name\":\"term_no\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), m.index);
    try std.testing.expectEqualStrings("continued", result.final_text);
}

test "after tool override can mark a result terminating" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script =
        \\[{"content":"hook-stop","tool_calls":[{"id":"c1","name":"hook_term","arguments":"{}"}]}]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "terminate-hook", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "hook_term")) return null;
            return .{ .content = try allocator.dupe(u8, "ok"), .is_error = false };
        }
        fn after(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8, raw: *const tools.ToolResult) anyerror!?ToolResultOverride {
            return .{ .content = try allocator.dupe(u8, raw.content), .is_error = raw.is_error, .terminate = true };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"hook_term\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .after_tool_fn = Hook.after,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), m.index);
    try std.testing.expectEqualStrings("hook-stop", result.final_text);
}

test "before tool hook mutates execution arguments without revalidation" {
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
        \\ {"content":"call","tool_calls":[{"id":"x1","name":"mutate_probe","arguments":"{\"value\":\"hello\"}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "before-mutate", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        var saw_mutated = false;
        fn before(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8) anyerror!?BeforeToolResult {
            return .{ .arguments_json = try allocator.dupe(u8, "{\"value\":123}") };
        }
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, args: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "mutate_probe")) return null;
            saw_mutated = std.mem.indexOf(u8, args, "123") != null;
            return .{ .content = try allocator.dupe(u8, args), .is_error = false };
        }
    };
    Hook.saw_mutated = false;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"mutate_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .before_tool_fn = Hook.before,
    }, null, null);
    defer result.deinit(gpa);
    try std.testing.expect(Hook.saw_mutated);
    try std.testing.expectEqualStrings("done", result.final_text);
}

test "before tool hook blocks execution and persists the reason" {
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
        \\ {"content":"call","tool_calls":[{"id":"x1","name":"blocked_probe","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "before-block", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        var executions: usize = 0;
        fn before(_: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8) anyerror!?BeforeToolResult {
            return .{ .block = true, .reason = try allocator.dupe(u8, "policy blocked probe") };
        }
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "blocked_probe")) return null;
            executions += 1;
            return .{ .content = try allocator.dupe(u8, "unexpected"), .is_error = false };
        }
    };
    Hook.executions = 0;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"blocked_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .before_tool_fn = Hook.before,
    }, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), Hook.executions);
    var saw = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and entry.tool_is_error and std.mem.eql(u8, entry.content, "policy blocked probe")) saw = true;
    }
    try std.testing.expect(saw);
}

test "invalid tool arguments fail validation before before hook or execution" {
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
        \\ {"content":"call","tool_calls":[{"id":"bad1","name":"typed_probe","arguments":"{\"value\":123}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "schema-preflight", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        var before_calls: usize = 0;
        var executions: usize = 0;
        fn before(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8, _: []const u8) anyerror!?BeforeToolResult {
            before_calls += 1;
            return null;
        }
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "typed_probe")) return null;
            executions += 1;
            return .{ .content = try allocator.dupe(u8, "unexpected"), .is_error = false };
        }
    };
    Hook.before_calls = 0;
    Hook.executions = 0;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"typed_probe\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"],\"additionalProperties\":false}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .before_tool_fn = Hook.before,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 0), Hook.before_calls);
    try std.testing.expectEqual(@as(usize, 0), Hook.executions);
    var saw = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and entry.tool_is_error and std.mem.indexOf(u8, entry.content, "Validation failed for tool \"typed_probe\"") != null) {
            saw = true;
            try std.testing.expect(std.mem.indexOf(u8, entry.content, "value: expected string") != null);
        }
    }
    try std.testing.expect(saw);
    try std.testing.expectEqualStrings("done", result.final_text);
}

test "should stop after turn runs before queued follow-up" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var m = try mock.MockModel.loadFromJson(gpa, "[{\"content\":\"first\",\"tool_calls\":[]},{\"content\":\"should-not-run\",\"tool_calls\":[]}]");
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "stop-before-followup", tmp_path);
    defer sess.deinit();
    var followups: std.ArrayList([]const u8) = .empty;
    defer {
        for (followups.items) |msg| gpa.free(msg);
        followups.deinit(gpa);
    }
    try followups.append(gpa, try gpa.dupe(u8, "queued follow-up"));

    const Hook = struct {
        var calls: usize = 0;
        fn stop(_: ?*anyopaque, summary: TurnSummary) bool {
            calls += 1;
            std.testing.expectEqualStrings("first", summary.assistant_text) catch @panic("bad turn text");
            std.testing.expectEqual(@as(usize, 0), summary.tool_results) catch @panic("bad tool count");
            return true;
        }
    };
    Hook.calls = 0;
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .follow_up_queue = &followups,
        .should_stop_after_turn_fn = Hook.stop,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), Hook.calls);
    try std.testing.expectEqual(@as(usize, 1), m.index);
    try std.testing.expectEqual(@as(usize, 1), followups.items.len);
    try std.testing.expectEqualStrings("first", result.final_text);
}

test "should stop after turn waits for current tool batch to finish" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const script = "[{\"content\":\"call\",\"tool_calls\":[{\"id\":\"s1\",\"name\":\"stop_probe\",\"arguments\":\"{}\"}]},{\"content\":\"should-not-run\",\"tool_calls\":[]}]";
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "stop-after-tools", tmp_path);
    defer sess.deinit();

    const Hook = struct {
        var executions: usize = 0;
        var stops: usize = 0;
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "stop_probe")) return null;
            executions += 1;
            return .{ .content = try allocator.dupe(u8, "finished"), .is_error = false };
        }
        fn stop(_: ?*anyopaque, summary: TurnSummary) bool {
            stops += 1;
            std.testing.expectEqual(@as(usize, 1), summary.tool_results) catch @panic("bad tool count");
            return true;
        }
    };
    Hook.executions = 0;
    Hook.stops = 0;
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"stop_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .should_stop_after_turn_fn = Hook.stop,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), Hook.executions);
    try std.testing.expectEqual(@as(usize, 1), Hook.stops);
    try std.testing.expectEqual(@as(usize, 1), m.index);
    var saw_tool = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.content, "finished")) saw_tool = true;
    }
    try std.testing.expect(saw_tool);
}

test "steering queued during tool execution is injected before the next model turn" {
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
        \\ {"content":"call","tool_calls":[{"id":"q1","name":"queue_probe","arguments":"{}"}]},
        \\ {"content":"after steering","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "steering-mid-tool", tmp_path);
    defer sess.deinit();
    var steering: std.ArrayList([]const u8) = .empty;
    defer {
        for (steering.items) |msg| gpa.free(msg);
        steering.deinit(gpa);
    }

    const Hook = struct {
        const State = struct { queue: *std.ArrayList([]const u8) };
        fn exec(ctx: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "queue_probe")) return null;
            const state: *State = @ptrCast(@alignCast(ctx.?));
            try state.queue.append(allocator, try allocator.dupe(u8, "mid-turn steering"));
            return .{ .content = try allocator.dupe(u8, "queued"), .is_error = false };
        }
    };
    var state = Hook.State{ .queue = &steering };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"queue_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .steer_queue = &steering,
        .hook_ctx = &state,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), m.index);
    try std.testing.expectEqual(@as(usize, 0), steering.items.len);
    var saw_steering = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "mid-turn steering")) saw_steering = true;
    }
    try std.testing.expect(saw_steering);
    try std.testing.expectEqualStrings("after steering", result.final_text);
}

test "terminating tool batch still allows queued follow-up" {
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
        \\ {"content":"terminate batch","tool_calls":[{"id":"tq1","name":"term_probe","arguments":"{}"}]},
        \\ {"content":"follow-up handled","tool_calls":[]}
        \\]
    ;
    var m = try mock.MockModel.loadFromJson(gpa, script);
    defer m.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "terminate-followup", tmp_path);
    defer sess.deinit();
    var followups: std.ArrayList([]const u8) = .empty;
    defer {
        for (followups.items) |msg| gpa.free(msg);
        followups.deinit(gpa);
    }
    try followups.append(gpa, try gpa.dupe(u8, "continue after terminate"));

    const Hook = struct {
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "term_probe")) return null;
            return .{ .content = try allocator.dupe(u8, "done"), .is_error = false, .terminate = true };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"term_probe\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, m.client(), &sess, "go", .{
        .extra_tools_json = schema,
        .external_tool_fn = Hook.exec,
        .follow_up_queue = &followups,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), m.index);
    try std.testing.expectEqual(@as(usize, 0), followups.items.len);
    try std.testing.expectEqualStrings("follow-up handled", result.final_text);
    var saw_followup = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "continue after terminate")) saw_followup = true;
    }
    try std.testing.expect(saw_followup);
}

test "prepare next turn can replace client and system prompt before continuation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    var first = try mock.MockModel.loadFromJson(
        gpa,
        "[{\"content\":\"switch\",\"tool_calls\":[{\"id\":\"p1\",\"name\":\"swap_probe\",\"arguments\":\"{}\"}]}]",
    );
    defer first.deinit(gpa);

    const Capture = struct {
        saw_second_prompt: bool = false,
        calls: usize = 0,
        fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, messages: []const ai.ChatMessage, _: []const u8) anyerror!ai.ModelResponse {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.calls += 1;
            if (messages.len > 0 and std.mem.eql(u8, messages[0].role, "system") and std.mem.eql(u8, messages[0].content, "second prompt")) {
                self.saw_second_prompt = true;
            }
            return .{
                .content = try allocator.dupe(u8, "switched client"),
                .tool_calls = try allocator.alloc(ai.ToolCall, 0),
                .provider = try allocator.dupe(u8, "capture"),
                .model = try allocator.dupe(u8, "capture-model"),
                .stop_reason = try allocator.dupe(u8, "stop"),
            };
        }
        fn client(self: *@This()) ai.ModelClient {
            return .{ .ptr = self, .completeFn = complete };
        }
    };
    var capture = Capture{};
    const State = struct {
        next: ai.ModelClient,
        used: bool = false,
        fn prepare(ctx: ?*anyopaque, _: TurnSummary) ?PrepareNextTurnResult {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            if (self.used) return null;
            self.used = true;
            return .{ .client = self.next, .system_prompt = "second prompt" };
        }
        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "swap_probe")) return null;
            return .{ .content = try allocator.dupe(u8, "ok"), .is_error = false };
        }
    };
    var state = State{ .next = capture.client() };
    var sess = try session_mod.Session.init(gpa, "prepare-next-turn", tmp_path);
    defer sess.deinit();
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"swap_probe\",\"parameters\":{\"type\":\"object\"}}}]";

    var result = try run(gpa, io, tmp_path, first.client(), &sess, "go", .{
        .system_prompt = "first prompt",
        .extra_tools_json = schema,
        .external_tool_fn = State.exec,
        .prepare_next_turn_fn = State.prepare,
        .hook_ctx = &state,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), first.index);
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expect(capture.saw_second_prompt);
    try std.testing.expectEqualStrings("switched client", result.final_text);
}

test "prepare next turn is not called after a final assistant turn" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    var model = try mock.MockModel.loadFromJson(gpa, "[{\"content\":\"done\",\"tool_calls\":[]}]");
    defer model.deinit(gpa);
    var session = try session_mod.Session.init(gpa, "prepare-final", path_buf[0..n]);
    defer session.deinit();
    const State = struct {
        calls: usize = 0,
        fn prepare(ctx: ?*anyopaque, _: TurnSummary) ?PrepareNextTurnResult {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.calls += 1;
            return null;
        }
    };
    var state = State{};
    var result = try run(gpa, io, path_buf[0..n], model.client(), &session, "go", .{
        .prepare_next_turn_fn = State.prepare,
        .hook_ctx = &state,
    }, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), state.calls);
}

test "tool-result image normalization trusts bytes over extension MIME" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var png = [_]u8{0} ** 24;
    @memcpy(png[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a });
    png[11] = 13;
    @memcpy(png[12..16], "IHDR");
    png[19] = 2;
    png[23] = 3;
    var data_b64 = try ai.images.encodeBase64(gpa, &png);
    defer gpa.free(data_b64);
    var mime_type = try gpa.dupe(u8, "image/bmp");
    defer gpa.free(mime_type);

    const hint = (try normalizeOneToolImage(gpa, io, &.{}, &data_b64, &mime_type)).?;
    defer gpa.free(hint);
    try std.testing.expectEqual(@as(usize, 0), hint.len);
    try std.testing.expectEqualStrings("image/png", mime_type);
}

test "tool-result image normalization retains invalid extension payload" {
    const gpa = std.testing.allocator;
    var data_b64 = try gpa.dupe(u8, "bm90LWFuLWltYWdl");
    defer gpa.free(data_b64);
    var mime_type = try gpa.dupe(u8, "image/png");
    defer gpa.free(mime_type);
    try std.testing.expect((try normalizeOneToolImage(gpa, std.testing.io, &.{}, &data_b64, &mime_type)) == null);
    try std.testing.expectEqualStrings("image/png", mime_type);
    try std.testing.expectEqualStrings("bm90LWFuLWltYWdl", data_b64);
}

test "blockImages strips legacy and ordered images after extension transforms" {
    const gpa = std.testing.allocator;
    const Hook = struct {
        fn transform(_: ?*anyopaque, scratch: std.mem.Allocator, messages: []const ai.ChatMessage) ![]const ai.ChatMessage {
            const rewritten = try scratch.alloc(ai.ChatMessage, messages.len);
            @memcpy(rewritten, messages);
            rewritten[0].image_b64 = "legacy";
            rewritten[0].image_mime = "image/jpeg";
            rewritten[0].images = &.{
                .{ .data_b64 = "ordered-1", .mime_type = "image/png" },
                .{ .data_b64 = "ordered-2", .mime_type = "image/webp" },
            };
            return rewritten;
        }
    };
    const original = [_]ai.ChatMessage{.{
        .role = "user",
        .content = "keep durable text",
        .image_b64 = "original",
        .image_mime = "image/gif",
        .images = &.{.{ .data_b64 = "more", .mime_type = "image/png" }},
    }};
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const filtered = try transformChatContext(&.{
        .block_images = true,
        .transform_context_fn = Hook.transform,
    }, arena.allocator(), &original);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("keep durable text\nImage reading is disabled.", filtered[0].content);
    try std.testing.expect(!filtered[0].hasImages());
    try std.testing.expect(original[0].hasImages());
    try std.testing.expectEqual(@as(usize, 2), original[0].imageCount());
}

test "blockImages preserves image-free request slices without allocation" {
    const messages = [_]ai.ChatMessage{.{ .role = "user", .content = "text only" }};
    var fixed_buffer: [1]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&fixed_buffer);
    const filtered = try transformChatContext(&.{ .block_images = true }, fba.allocator(), &messages);
    try std.testing.expect(filtered.ptr == messages[0..].ptr);
}

test "transform context rewrites provider view without mutating durable session" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];

    const Capture = struct {
        saw_transformed: bool = false,
        fn complete(ptr: *anyopaque, allocator: std.mem.Allocator, messages: []const ai.ChatMessage, _: []const u8) anyerror!ai.ModelResponse {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            for (messages) |message| {
                if (std.mem.eql(u8, message.role, "user") and std.mem.eql(u8, message.content, "rewritten for provider")) self.saw_transformed = true;
            }
            return .{
                .content = try allocator.dupe(u8, "done"),
                .tool_calls = try allocator.alloc(ai.ToolCall, 0),
                .provider = try allocator.dupe(u8, "capture"),
                .model = try allocator.dupe(u8, "capture-model"),
                .stop_reason = try allocator.dupe(u8, "stop"),
            };
        }
        fn client(self: *@This()) ai.ModelClient {
            return .{ .ptr = self, .completeFn = complete };
        }
    };
    const Hook = struct {
        fn transform(_: ?*anyopaque, scratch: std.mem.Allocator, messages: []const ai.ChatMessage) anyerror![]const ai.ChatMessage {
            const out = try scratch.dupe(ai.ChatMessage, messages);
            for (out) |*message| {
                if (std.mem.eql(u8, message.role, "user") and std.mem.eql(u8, message.content, "original durable prompt")) {
                    message.content = try scratch.dupe(u8, "rewritten for provider");
                }
            }
            return out;
        }
    };
    var capture = Capture{};
    var sess = try session_mod.Session.init(gpa, "transform-context", tmp_path);
    defer sess.deinit();
    var result = try run(gpa, io, tmp_path, capture.client(), &sess, "original durable prompt", .{
        .transform_context_fn = Hook.transform,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expect(capture.saw_transformed);
    var durable_original = false;
    var durable_rewrite = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "original durable prompt")) durable_original = true;
        if (std.mem.eql(u8, entry.role, "user") and std.mem.eql(u8, entry.content, "rewritten for provider")) durable_rewrite = true;
    }
    try std.testing.expect(durable_original);
    try std.testing.expect(!durable_rewrite);
}

test "queue mode parsing uses upstream wire names" {
    try std.testing.expectEqual(QueueMode.all, QueueMode.parse("all").?);
    try std.testing.expectEqual(QueueMode.one_at_a_time, QueueMode.parse("one-at-a-time").?);
    try std.testing.expectEqualStrings("one-at-a-time", QueueMode.one_at_a_time.wireName());
    try std.testing.expect(QueueMode.parse("invalid") == null);
}

test "one-at-a-time queue mode drains one item while all drains every item" {
    const gpa = std.testing.allocator;
    var queue: std.ArrayList([]const u8) = .empty;
    defer {
        for (queue.items) |item| gpa.free(item);
        queue.deinit(gpa);
    }
    try queue.append(gpa, try gpa.dupe(u8, "first"));
    try queue.append(gpa, try gpa.dupe(u8, "second"));
    var pending: std.ArrayList([]u8) = .empty;
    defer {
        for (pending.items) |item| gpa.free(item);
        pending.deinit(gpa);
    }

    try collectSteeringMessages(gpa, &.{ .steer_queue = &queue }, &pending);
    try std.testing.expectEqual(@as(usize, 1), pending.items.len);
    try std.testing.expectEqual(@as(usize, 1), queue.items.len);
    for (pending.items) |item| gpa.free(item);
    pending.clearRetainingCapacity();

    try collectSteeringMessages(gpa, &.{ .steer_queue = &queue, .steering_mode = .all }, &pending);
    try std.testing.expectEqual(@as(usize, 1), pending.items.len);
    try std.testing.expectEqual(@as(usize, 0), queue.items.len);
}

test "external tool partial updates retain details images and canonical order" {
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
        \\ {"content":"call","tool_calls":[{"id":"rich-1","name":"rich_stream","arguments":"{\"value\":1}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "rich-updates", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "rich_stream");
        }

        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "rich_stream")) return null;
            const updates = try allocator.alloc(tools.ToolUpdate, 2);
            var initialized: usize = 0;
            errdefer {
                for (updates[0..initialized]) |*update| update.deinit(allocator);
                allocator.free(updates);
            }
            updates[0] = .{
                .content = try allocator.dupe(u8, "phase-one"),
                .details_json = try allocator.dupe(u8, "{\"phase\":1}"),
            };
            initialized += 1;
            updates[1] = .{
                .content = try allocator.dupe(u8, ""),
                .image_b64 = try allocator.dupe(u8, "aW1hZ2U="),
                .image_mime = try allocator.dupe(u8, "image/png"),
                .details_json = try allocator.dupe(u8, "{\"phase\":2}"),
            };
            initialized += 1;
            return .{
                .content = try allocator.dupe(u8, "complete-rich"),
                .is_error = false,
                .image_b64 = try allocator.dupe(u8, "ZmluYWw="),
                .image_mime = try allocator.dupe(u8, "image/jpeg"),
                .details_json = try allocator.dupe(u8, "{\"phase\":3}"),
                .updates = updates,
            };
        }
    };

    const Probe = struct {
        canonical: [4]EventKind = undefined,
        count: usize = 0,
        saw_first_details: bool = false,
        saw_second_image: bool = false,
        saw_final: bool = false,

        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (event.kind) {
                .tool_execution_start, .tool_execution_update, .tool_execution_end => {
                    if (self.count < self.canonical.len) {
                        self.canonical[self.count] = event.kind;
                        self.count += 1;
                    }
                    if (event.kind == .tool_execution_update and std.mem.eql(u8, event.text, "phase-one")) {
                        self.saw_first_details = event.is_partial and event.details_json != null and std.mem.eql(u8, event.details_json.?, "{\"phase\":1}");
                    }
                    if (event.kind == .tool_execution_update and event.image_b64 != null) {
                        self.saw_second_image = event.is_partial and std.mem.eql(u8, event.image_b64.?, "aW1hZ2U=") and std.mem.eql(u8, event.image_mime.?, "image/png");
                    }
                    if (event.kind == .tool_execution_end) {
                        self.saw_final = !event.is_partial and std.mem.eql(u8, event.text, "complete-rich") and
                            std.mem.eql(u8, event.details_json.?, "{\"phase\":3}") and
                            std.mem.eql(u8, event.image_b64.?, "ZmluYWw=") and
                            std.mem.eql(u8, event.image_mime.?, "image/jpeg");
                    }
                },
                else => {},
            }
        }
    };
    var probe = Probe{};
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"rich_stream\",\"description\":\"rich\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}}}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "stream", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
        .external_tool_exists_fn = External.owns,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 4), probe.count);
    try std.testing.expectEqual(EventKind.tool_execution_start, probe.canonical[0]);
    try std.testing.expectEqual(EventKind.tool_execution_update, probe.canonical[1]);
    try std.testing.expectEqual(EventKind.tool_execution_update, probe.canonical[2]);
    try std.testing.expectEqual(EventKind.tool_execution_end, probe.canonical[3]);
    try std.testing.expect(probe.saw_first_details);
    try std.testing.expect(probe.saw_second_image);
    try std.testing.expect(probe.saw_final);

    var saw_persisted = false;
    for (sess.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.role, "tool") or !std.mem.eql(u8, entry.tool_name orelse "", "rich_stream")) continue;
        try std.testing.expectEqualStrings("complete-rich", entry.content);
        try std.testing.expectEqualStrings("ZmluYWw=", entry.image_b64.?);
        try std.testing.expectEqualStrings("image/jpeg", entry.image_mime.?);
        saw_persisted = true;
    }
    try std.testing.expect(saw_persisted);
}

test "full-fidelity external dispatcher receives exact call ID and abort flag without event sink" {
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
        \\ {"content":"call","tool_calls":[{"id":"exact-call-152","name":"identity_tool","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "exact-call", tmp_path);
    defer sess.deinit();

    const State = struct {
        expected_abort: *bool,
        called: bool = false,
        exact_id: bool = false,
        same_abort: bool = false,
        progress_called: bool = false,

        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "identity_tool");
        }

        fn exec(
            raw: ?*anyopaque,
            allocator: std.mem.Allocator,
            tool_call_id: []const u8,
            name: []const u8,
            _: []const u8,
            progress_fn: ExternalToolProgressFn,
            progress_ctx: ?*anyopaque,
            abort_flag: ?*bool,
        ) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "identity_tool")) return null;
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.called = true;
            self.exact_id = std.mem.eql(u8, tool_call_id, "exact-call-152");
            self.same_abort = abort_flag == self.expected_abort;
            progress_fn(progress_ctx, .{ .content = "discarded-without-sink" });
            self.progress_called = true;
            return .{ .content = try allocator.dupe(u8, "identity-ok"), .is_error = false };
        }
    };

    var abort_flag = false;
    var state = State{ .expected_abort = &abort_flag };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"identity_tool\",\"description\":\"identity\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "identity", .{
        .hook_ctx = &state,
        .abort_flag = &abort_flag,
        .extra_tools_json = schema,
        .external_tool_call_streaming_fn = State.exec,
        .external_tool_exists_fn = State.owns,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expect(state.called);
    try std.testing.expect(state.exact_id);
    try std.testing.expect(state.same_abort);
    try std.testing.expect(state.progress_called);
    try std.testing.expectEqualStrings("done", result.final_text);
}

test "streaming external update is emitted before tool execution returns" {
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
        \\ {"content":"call","tool_calls":[{"id":"live-1","name":"live_external","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "live-stream", tmp_path);
    defer sess.deinit();

    const State = struct {
        update_events: usize = 0,
        update_seen_before_return: bool = false,
        order: [3]EventKind = undefined,
        order_len: usize = 0,

        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "live_external");
        }

        fn exec(
            raw: ?*anyopaque,
            allocator: std.mem.Allocator,
            name: []const u8,
            _: []const u8,
            progress_fn: ExternalToolProgressFn,
            progress_ctx: ?*anyopaque,
        ) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "live_external")) return null;
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            progress_fn(progress_ctx, .{
                .content = "live-now",
                .details_json = "{\"phase\":1}",
            });
            self.update_seen_before_return = self.update_events == 1;
            return .{
                .content = try allocator.dupe(u8, "live-complete"),
                .is_error = false,
            };
        }

        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (event.kind) {
                .tool_execution_start, .tool_execution_update, .tool_execution_end => {
                    if (self.order_len < self.order.len) {
                        self.order[self.order_len] = event.kind;
                        self.order_len += 1;
                    }
                    if (event.kind == .tool_execution_update and std.mem.eql(u8, event.text, "live-now")) {
                        self.update_events += 1;
                    }
                },
                else => {},
            }
        }
    };
    var state = State{};
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"live_external\",\"description\":\"live\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "stream", .{
        .hook_ctx = &state,
        .extra_tools_json = schema,
        .external_tool_streaming_fn = State.exec,
        .external_tool_exists_fn = State.owns,
    }, State.onEvent, &state);
    defer result.deinit(gpa);

    try std.testing.expect(state.update_seen_before_return);
    try std.testing.expectEqual(@as(usize, 1), state.update_events);
    try std.testing.expectEqual(@as(usize, 3), state.order_len);
    try std.testing.expectEqual(EventKind.tool_execution_start, state.order[0]);
    try std.testing.expectEqual(EventKind.tool_execution_update, state.order[1]);
    try std.testing.expectEqual(EventKind.tool_execution_end, state.order[2]);
}

test "parallel streaming tools deliver each update before its matching end event" {
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
        \\ {"content":"calls","tool_calls":[
        \\   {"id":"pa","name":"parallel_a","arguments":"{}"},
        \\   {"id":"pb","name":"parallel_b","arguments":"{}"}
        \\ ]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "parallel-live", tmp_path);
    defer sess.deinit();

    const State = struct {
        started: u2 = 0,
        updated: u2 = 0,
        ended: u2 = 0,
        images_valid: u2 = 0,
        ordering_valid: bool = true,

        fn bitForName(name: []const u8) u2 {
            if (std.mem.eql(u8, name, "parallel_a")) return 1;
            if (std.mem.eql(u8, name, "parallel_b")) return 2;
            return 0;
        }

        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return bitForName(name) != 0;
        }

        fn exec(
            _: ?*anyopaque,
            allocator: std.mem.Allocator,
            name: []const u8,
            _: []const u8,
            progress_fn: ExternalToolProgressFn,
            progress_ctx: ?*anyopaque,
        ) anyerror!?tools.ToolResult {
            if (bitForName(name) == 0) return null;
            const images = [_]tools.ToolImage{
                .{ .data_b64 = @constCast("cGFyYWxsZWwtMQ=="), .mime_type = @constCast("image/png") },
                .{ .data_b64 = @constCast("cGFyYWxsZWwtMg=="), .mime_type = @constCast("image/webp") },
            };
            progress_fn(progress_ctx, .{
                .content = name,
                .details_json = "{\"live\":true}",
                .images = &images,
                .usage = .{ .input = 3, .output = 4, .total_tokens = 7 },
                .added_tool_names = &.{"parallel-added"},
            });
            return .{
                .content = try std.fmt.allocPrint(allocator, "done:{s}", .{name}),
                .is_error = false,
            };
        }

        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const bit = bitForName(event.name);
            if (bit == 0) return;
            switch (event.kind) {
                .tool_execution_start => self.started |= bit,
                .tool_execution_update => {
                    if ((self.started & bit) == 0 or (self.ended & bit) != 0) self.ordering_valid = false;
                    self.updated |= bit;
                    if (event.images.len == 2 and
                        std.mem.eql(u8, event.images[0].data_b64, "cGFyYWxsZWwtMQ==") and
                        std.mem.eql(u8, event.images[0].mime_type, "image/png") and
                        std.mem.eql(u8, event.images[1].data_b64, "cGFyYWxsZWwtMg==") and
                        std.mem.eql(u8, event.images[1].mime_type, "image/webp") and
                        event.usage != null and event.usage.?.total_tokens == 7 and
                        event.added_tool_names.len == 1 and std.mem.eql(u8, event.added_tool_names[0], "parallel-added"))
                    {
                        self.images_valid |= bit;
                    }
                },
                .tool_execution_end => {
                    if ((self.updated & bit) == 0) self.ordering_valid = false;
                    self.ended |= bit;
                },
                else => {},
            }
        }
    };
    var state = State{};
    const schema =
        "[{\"type\":\"function\",\"function\":{\"name\":\"parallel_a\",\"description\":\"a\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}," ++
        "{\"type\":\"function\",\"function\":{\"name\":\"parallel_b\",\"description\":\"b\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "parallel", .{
        .hook_ctx = &state,
        .extra_tools_json = schema,
        .external_tool_streaming_fn = State.exec,
        .external_tool_exists_fn = State.owns,
    }, State.onEvent, &state);
    defer result.deinit(gpa);

    try std.testing.expect(state.ordering_valid);
    try std.testing.expectEqual(@as(u2, 3), state.started);
    try std.testing.expectEqual(@as(u2, 3), state.updated);
    try std.testing.expectEqual(@as(u2, 3), state.ended);
    try std.testing.expectEqual(@as(u2, 3), state.images_valid);
}

test "streamed extension updates reach primary live and lifecycle observer after worker release" {
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
        \\ {"content":"call","tool_calls":[{"id":"defer-1","name":"deferred_update","arguments":"{}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "deferred-observer", tmp_path);
    defer sess.deinit();

    const State = struct {
        primary_updates: usize = 0,
        observer_updates: usize = 0,
        primary_was_live: bool = false,
        observer_was_deferred: bool = false,

        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "deferred_update");
        }

        fn exec(
            raw: ?*anyopaque,
            allocator: std.mem.Allocator,
            name: []const u8,
            _: []const u8,
            progress_fn: ExternalToolProgressFn,
            progress_ctx: ?*anyopaque,
        ) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "deferred_update")) return null;
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            progress_fn(progress_ctx, .{
                .content = "worker-live",
                .defer_observer = true,
            });
            self.primary_was_live = self.primary_updates == 1;
            self.observer_was_deferred = self.observer_updates == 0;
            const updates = try allocator.alloc(tools.ToolUpdate, 1);
            updates[0] = .{
                .content = try allocator.dupe(u8, "worker-live"),
                .observer_deferred = true,
            };
            return .{
                .content = try allocator.dupe(u8, "worker-complete"),
                .is_error = false,
                .updates = updates,
            };
        }

        fn primary(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .tool_execution_update and std.mem.eql(u8, event.text, "worker-live")) {
                self.primary_updates += 1;
            }
        }

        fn observer(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .tool_execution_update and std.mem.eql(u8, event.text, "worker-live")) {
                self.observer_updates += 1;
            }
        }
    };
    var state = State{};
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"deferred_update\",\"description\":\"deferred\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "defer", .{
        .hook_ctx = &state,
        .extra_tools_json = schema,
        .external_tool_streaming_fn = State.exec,
        .external_tool_exists_fn = State.owns,
        .event_observer_fn = State.observer,
        .event_observer_ctx = &state,
    }, State.primary, &state);
    defer result.deinit(gpa);

    try std.testing.expect(state.primary_was_live);
    try std.testing.expect(state.observer_was_deferred);
    try std.testing.expectEqual(@as(usize, 1), state.primary_updates);
    try std.testing.expectEqual(@as(usize, 1), state.observer_updates);
}

test "native bash streams bounded snapshots before command completion" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
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
        \\ {"content":"call","tool_calls":[{"id":"bash-live","name":"bash","arguments":"{\"command\":\"printf first; sleep 0.20; : > live.marker; printf second\"}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "bash-live", tmp_path);
    defer sess.deinit();
    const marker_path = try std.fs.path.join(gpa, &.{ tmp_path, "live.marker" });
    defer gpa.free(marker_path);

    const State = struct {
        io: Io,
        marker: []const u8,
        updates: usize = 0,
        first_before_marker: bool = false,
        saw_accumulated: bool = false,
        details_valid: bool = true,
        update_before_end: bool = false,
        ended: bool = false,

        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .tool_execution_update and std.mem.eql(u8, event.name, "bash")) {
                self.updates += 1;
                self.update_before_end = !self.ended;
                if (std.mem.indexOf(u8, event.text, "first") != null and std.mem.indexOf(u8, event.text, "second") == null) {
                    var marker_exists = true;
                    std.Io.Dir.cwd().access(self.io, self.marker, .{}) catch {
                        marker_exists = false;
                    };
                    self.first_before_marker = !marker_exists;
                }
                if (std.mem.indexOf(u8, event.text, "firstsecond") != null) self.saw_accumulated = true;
                self.details_valid = self.details_valid and event.details_json != null and
                    std.mem.eql(u8, event.details_json.?, "{\"kind\":\"output\",\"mode\":\"snapshot\"}");
            }
            if (event.kind == .tool_execution_end and std.mem.eql(u8, event.name, "bash")) self.ended = true;
        }
    };
    var state = State{ .io = io, .marker = marker_path };
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "bash", .{}, State.onEvent, &state);
    defer result.deinit(gpa);

    try std.testing.expect(state.updates >= 2);
    try std.testing.expect(state.first_before_marker);
    try std.testing.expect(state.saw_accumulated);
    try std.testing.expect(state.details_valid);
    try std.testing.expect(state.update_before_end);
    try std.testing.expect(state.ended);
}

test "native progress snapshots are throttled and tail bounded" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const Probe = struct {
        calls: usize = 0,
        final_len: usize = 0,
        saw_details: bool = true,

        fn update(raw: ?*anyopaque, value: ExternalToolUpdate) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.final_len = value.content.len;
            self.saw_details = self.saw_details and value.details_json != null and
                std.mem.eql(u8, value.details_json.?, "{\"kind\":\"output\",\"mode\":\"snapshot\"}");
        }
    };
    var probe = Probe{};
    var adapter = BuiltinProgressAdapter{
        .io = io,
        .allocator = gpa,
        .callback = Probe.update,
        .context = &probe,
    };
    defer adapter.deinit();

    var chunk: [4096]u8 = undefined;
    @memset(&chunk, 'x');
    for (0..100) |_| BuiltinProgressAdapter.forward(&adapter, &chunk);
    adapter.finish();

    try std.testing.expect(probe.calls >= 1);
    try std.testing.expect(probe.calls <= 3);
    try std.testing.expectEqual(BuiltinProgressAdapter.max_snapshot_bytes, probe.final_len);
    try std.testing.expect(probe.saw_details);
}

test "extension prepareArguments runs before schema validation and execution" {
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
        \\ {"content":"call","tool_calls":[{"id":"prep-1","name":"prepared_external","arguments":"{\"legacy\":\"converted\"}"}]},
        \\ {"content":"done","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "prepare-external", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "prepared_external");
        }

        fn prepare(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, arguments: []const u8) anyerror!?[]u8 {
            if (!std.mem.eql(u8, name, "prepared_external")) return null;
            try std.testing.expect(std.mem.indexOf(u8, arguments, "legacy") != null);
            return try allocator.dupe(u8, "{\"value\":\"converted\"}");
        }

        fn exec(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8, arguments: []const u8) anyerror!?tools.ToolResult {
            if (!std.mem.eql(u8, name, "prepared_external")) return null;
            try std.testing.expectEqualStrings("{\"value\":\"converted\"}", arguments);
            return .{ .content = try allocator.dupe(u8, "prepared-ok"), .is_error = false };
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"prepared_external\",\"description\":\"prepared\",\"parameters\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\"}},\"required\":[\"value\"],\"additionalProperties\":false}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "prepare", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
        .external_tool_exists_fn = External.owns,
        .external_prepare_arguments_fn = External.prepare,
    }, null, null);
    defer result.deinit(gpa);

    var saw = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_name orelse "", "prepared_external")) {
            try std.testing.expectEqualStrings("prepared-ok", entry.content);
            try std.testing.expect(!entry.tool_is_error);
            saw = true;
        }
    }
    try std.testing.expect(saw);
}

test "extension prepareArguments failure becomes an isolated tool error" {
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
        \\ {"content":"call","tool_calls":[{"id":"prep-err","name":"prepared_error","arguments":"{}"}]},
        \\ {"content":"recovered","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "prepare-error", tmp_path);
    defer sess.deinit();

    const External = struct {
        fn owns(_: ?*anyopaque, name: []const u8) bool {
            return std.mem.eql(u8, name, "prepared_error");
        }
        fn prepare(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) anyerror!?[]u8 {
            return error.BadPreparedArguments;
        }
        fn exec(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: []const u8) anyerror!?tools.ToolResult {
            return error.ShouldNotExecute;
        }
    };
    const schema = "[{\"type\":\"function\",\"function\":{\"name\":\"prepared_error\",\"description\":\"prepared\",\"parameters\":{\"type\":\"object\"}}}]";
    var result = try run(gpa, io, tmp_path, model.client(), &sess, "prepare", .{
        .extra_tools_json = schema,
        .external_tool_fn = External.exec,
        .external_tool_exists_fn = External.owns,
        .external_prepare_arguments_fn = External.prepare,
    }, null, null);
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings("recovered", result.final_text);

    var saw = false;
    for (sess.entries.items) |entry| {
        if (std.mem.eql(u8, entry.role, "tool") and std.mem.eql(u8, entry.tool_name orelse "", "prepared_error")) {
            try std.testing.expect(entry.tool_is_error);
            try std.testing.expect(std.mem.indexOf(u8, entry.content, "BadPreparedArguments") != null);
            saw = true;
        }
    }
    try std.testing.expect(saw);
}

test "tool result cloning and event persistence retain additional images" {
    const gpa = std.testing.allocator;
    var source: tools.ToolResult = .{
        .content = try gpa.dupe(u8, "capture"),
        .is_error = false,
        .image_b64 = try gpa.dupe(u8, "AA=="),
        .image_mime = try gpa.dupe(u8, "image/png"),
        .images = try tools.cloneImages(gpa, &.{
            .{ .data_b64 = @constCast("AQ=="), .mime_type = @constCast("image/jpeg") },
            .{ .data_b64 = @constCast("Ag=="), .mime_type = @constCast("image/webp") },
        }),
    };
    defer source.deinit(gpa);
    var cloned = try cloneToolResult(gpa, &source);
    defer cloned.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 2), cloned.images.len);
    try std.testing.expectEqualStrings("Ag==", cloned.images[1].data_b64);
    try std.testing.expect(cloned.images[0].data_b64.ptr != source.images[0].data_b64.ptr);
}

test "compaction and branch summaries use canonical user context wrappers" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "summary-projection", "/tmp");
    defer sess.deinit();

    const user_one = try sess.appendMessage(null, "user", "old", null, null);
    const assistant_one = try sess.appendMessage(user_one, "assistant", "old answer", null, null);
    const user_two = try sess.appendMessage(assistant_one, "user", "kept", null, null);
    _ = try sess.appendCompaction("raw compact summary", user_two, 42, "{\"readFiles\":[],\"modifiedFiles\":[]}", false, .{});

    const compact_chat = try buildChatMessages(gpa, &sess, .{});
    defer freeChatMessages(gpa, compact_chat);
    try std.testing.expectEqual(@as(usize, 3), compact_chat.len);
    try std.testing.expectEqualStrings("user", compact_chat[1].role);
    try std.testing.expect(std.mem.startsWith(u8, compact_chat[1].content, COMPACTION_SUMMARY_PREFIX));
    try std.testing.expect(std.mem.indexOf(u8, compact_chat[1].content, "raw compact summary") != null);
    try std.testing.expect(std.mem.endsWith(u8, compact_chat[1].content, COMPACTION_SUMMARY_SUFFIX));
    try std.testing.expectEqualStrings("kept", compact_chat[2].content);

    try sess.setTip(assistant_one);
    _ = try sess.appendBranchSummary(assistant_one, assistant_one, "raw branch summary", "{\"readFiles\":[],\"modifiedFiles\":[]}", .{});
    const branch_chat = try buildChatMessages(gpa, &sess, .{});
    defer freeChatMessages(gpa, branch_chat);
    try std.testing.expectEqualStrings("user", branch_chat[branch_chat.len - 1].role);
    try std.testing.expect(std.mem.startsWith(u8, branch_chat[branch_chat.len - 1].content, BRANCH_SUMMARY_PREFIX));
    try std.testing.expect(std.mem.indexOf(u8, branch_chat[branch_chat.len - 1].content, "raw branch summary") != null);
    try std.testing.expect(std.mem.endsWith(u8, branch_chat[branch_chat.len - 1].content, BRANCH_SUMMARY_SUFFIX));
}

test "automatic retry recovers transient assistant errors and emits canonical events" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];

    const script =
        \\[
        \\ {"content":"503 Service Unavailable","stop_reason":"error","tool_calls":[]},
        \\ {"content":"retry recovered","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "retry-success", cwd);
    defer sess.deinit();

    const Probe = struct {
        starts: usize = 0,
        ends: usize = 0,
        attempt: usize = 0,
        max_attempts: usize = 0,
        delay_ms: u64 = 999,
        success: bool = false,
        saw_expected_error: bool = false,

        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            switch (event.kind) {
                .auto_retry_start => {
                    self.starts += 1;
                    self.attempt = event.attempt;
                    self.max_attempts = event.max_attempts;
                    self.delay_ms = event.delay_ms;
                    self.saw_expected_error = std.mem.eql(u8, event.error_message orelse event.text, "503 Service Unavailable");
                },
                .auto_retry_end => {
                    self.ends += 1;
                    self.success = event.success;
                },
                else => {},
            }
        }
    };
    var probe = Probe{};
    var result = try run(gpa, io, cwd, model.client(), &sess, "retry", .{
        .retry_enabled = true,
        .retry_max_retries = 3,
        .retry_base_delay_ms = 0,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqualStrings("retry recovered", result.final_text);
    try std.testing.expectEqual(@as(usize, 2), model.index);
    try std.testing.expectEqual(@as(usize, 1), probe.starts);
    try std.testing.expectEqual(@as(usize, 1), probe.ends);
    try std.testing.expectEqual(@as(usize, 1), probe.attempt);
    try std.testing.expectEqual(@as(usize, 3), probe.max_attempts);
    try std.testing.expectEqual(@as(u64, 0), probe.delay_ms);
    try std.testing.expect(probe.success);
    try std.testing.expect(probe.saw_expected_error);

    var assistant_entries: usize = 0;
    for (sess.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.role, "assistant")) continue;
        switch (assistant_entries) {
            0 => {
                try std.testing.expectEqualStrings("503 Service Unavailable", entry.content);
                try std.testing.expectEqualStrings("error", entry.meta.stop_reason);
            },
            1 => {
                try std.testing.expectEqualStrings("retry recovered", entry.content);
                try std.testing.expectEqualStrings("stop", entry.meta.stop_reason);
            },
            else => return error.UnexpectedAssistantAttempt,
        }
        assistant_entries += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), assistant_entries);
}

test "retry request excludes durable failed assistant attempts" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];
    var sess = try session_mod.Session.init(gpa, "retry-context", cwd);
    defer sess.deinit();

    const ProbeModel = struct {
        calls: usize = 0,
        retry_context_contains_failed_attempt: bool = false,
        retry_context_contains_user: bool = false,

        fn response(
            allocator: std.mem.Allocator,
            content: []const u8,
            stop_reason: []const u8,
            error_message: []const u8,
        ) !ai.ModelResponse {
            return .{
                .content = try allocator.dupe(u8, content),
                .tool_calls = try allocator.alloc(ai.ToolCall, 0),
                .error_message = if (error_message.len > 0) try allocator.dupe(u8, error_message) else "",
                .stop_reason = try allocator.dupe(u8, stop_reason),
            };
        }

        fn complete(
            raw: *anyopaque,
            allocator: std.mem.Allocator,
            messages: []const ai.ChatMessage,
            _: []const u8,
        ) anyerror!ai.ModelResponse {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            if (self.calls == 1) {
                return response(allocator, "HTTP 503 durable attempt", "error", "HTTP 503 durable attempt");
            }
            for (messages) |message| {
                if (std.mem.eql(u8, message.role, "user") and std.mem.eql(u8, message.content, "keep user context")) {
                    self.retry_context_contains_user = true;
                }
                if (std.mem.eql(u8, message.role, "assistant") and
                    (std.mem.eql(u8, message.content, "HTTP 503 durable attempt") or
                        std.mem.eql(u8, message.stop_reason orelse "", "error")))
                {
                    self.retry_context_contains_failed_attempt = true;
                }
            }
            return response(allocator, "context recovered", "stop", "");
        }

        fn client(self: *@This()) ai.ModelClient {
            return .{ .ptr = self, .completeFn = complete };
        }
    };

    var model = ProbeModel{};
    var result = try run(gpa, io, cwd, model.client(), &sess, "keep user context", .{
        .retry_enabled = true,
        .retry_max_retries = 1,
        .retry_base_delay_ms = 0,
    }, null, null);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), model.calls);
    try std.testing.expect(model.retry_context_contains_user);
    try std.testing.expect(!model.retry_context_contains_failed_attempt);
    try std.testing.expectEqualStrings("context recovered", result.final_text);

    var failed_attempts: usize = 0;
    var successful_attempts: usize = 0;
    for (sess.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.role, "assistant")) continue;
        if (std.mem.eql(u8, entry.meta.stop_reason, "error")) {
            failed_attempts += 1;
            try std.testing.expectEqualStrings("HTTP 503 durable attempt", entry.content);
        } else if (std.mem.eql(u8, entry.meta.stop_reason, "stop")) {
            successful_attempts += 1;
            try std.testing.expectEqualStrings("context recovered", entry.content);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), failed_attempts);
    try std.testing.expectEqual(@as(usize, 1), successful_attempts);
}

test "automatic retry fails fast for quota and billing errors" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];

    const script =
        \\[
        \\ {"content":"insufficient_quota: billing account exhausted","stop_reason":"error","tool_calls":[]},
        \\ {"content":"must not execute","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "retry-quota", cwd);
    defer sess.deinit();

    const Probe = struct {
        retries: usize = 0,
        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .auto_retry_start or event.kind == .auto_retry_end) self.retries += 1;
        }
    };
    var probe = Probe{};
    var result = try run(gpa, io, cwd, model.client(), &sess, "quota", .{
        .retry_enabled = true,
        .retry_max_retries = 3,
        .retry_base_delay_ms = 0,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqualStrings("insufficient_quota: billing account exhausted", result.final_text);
    try std.testing.expectEqual(@as(usize, 1), model.index);
    try std.testing.expectEqual(@as(usize, 0), probe.retries);
}

test "retry-only cancellation aborts backoff without consuming another response" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];

    const script =
        \\[
        \\ {"content":"network error: connection lost","stop_reason":"error","tool_calls":[]},
        \\ {"content":"must not execute","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "retry-abort", cwd);
    defer sess.deinit();
    var abort_retry = true;

    const Probe = struct {
        starts: usize = 0,
        ends: usize = 0,
        success: bool = true,
        saw_cancelled_error: bool = false,
        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .auto_retry_start) self.starts += 1;
            if (event.kind == .auto_retry_end) {
                self.ends += 1;
                self.success = event.success;
                self.saw_cancelled_error = std.mem.eql(u8, event.final_error orelse event.text, "Retry cancelled");
            }
        }
    };
    var probe = Probe{};
    var result = try run(gpa, io, cwd, model.client(), &sess, "cancel retry", .{
        .retry_enabled = true,
        .retry_max_retries = 3,
        .retry_base_delay_ms = 500,
        .retry_abort_flag = &abort_retry,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), model.index);
    try std.testing.expectEqual(@as(usize, 1), probe.starts);
    try std.testing.expectEqual(@as(usize, 1), probe.ends);
    try std.testing.expect(!probe.success);
    try std.testing.expect(probe.saw_cancelled_error);
    try std.testing.expectEqualStrings("network error: connection lost", result.final_text);
    const assistant = sess.entries.items[sess.entries.items.len - 1];
    try std.testing.expectEqualStrings("assistant", assistant.role);
    try std.testing.expectEqualStrings("error", assistant.meta.stop_reason);
}

test "automatic retry emits one final failure after exhausting the budget" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const mock = @import("../ai/mock.zig");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];

    const script =
        \\[
        \\ {"content":"HTTP 503 first","stop_reason":"error","tool_calls":[]},
        \\ {"content":"HTTP 503 second","stop_reason":"error","tool_calls":[]},
        \\ {"content":"HTTP 503 final","stop_reason":"error","tool_calls":[]},
        \\ {"content":"must not execute","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "retry-exhaust", cwd);
    defer sess.deinit();

    const Probe = struct {
        starts: usize = 0,
        ends: usize = 0,
        success: bool = true,
        attempt: usize = 0,
        saw_final_error: bool = false,
        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .auto_retry_start) self.starts += 1;
            if (event.kind == .auto_retry_end) {
                self.ends += 1;
                self.success = event.success;
                self.attempt = event.attempt;
                self.saw_final_error = std.mem.eql(u8, event.final_error orelse event.text, "HTTP 503 final");
            }
        }
    };
    var probe = Probe{};
    var result = try run(gpa, io, cwd, model.client(), &sess, "exhaust", .{
        .retry_enabled = true,
        .retry_max_retries = 2,
        .retry_base_delay_ms = 0,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 3), model.index);
    try std.testing.expectEqual(@as(usize, 2), probe.starts);
    try std.testing.expectEqual(@as(usize, 1), probe.ends);
    try std.testing.expect(!probe.success);
    try std.testing.expectEqual(@as(usize, 2), probe.attempt);
    try std.testing.expect(probe.saw_final_error);
    try std.testing.expectEqualStrings("HTTP 503 final", result.final_text);
}

test "automatic retry converts transient Zig transport errors into retryable assistant failures" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const cwd = path_buf[0..n];
    var sess = try session_mod.Session.init(gpa, "retry-transport", cwd);
    defer sess.deinit();

    const Transport = struct {
        calls: usize = 0,
        fn complete(raw: *anyopaque, allocator: std.mem.Allocator, _: []const ai.ChatMessage, _: []const u8) anyerror!ai.ModelResponse {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            if (self.calls == 1) return error.ConnectionResetByPeer;
            return .{
                .content = try allocator.dupe(u8, "transport recovered"),
                .tool_calls = try allocator.alloc(ai.ToolCall, 0),
                .stop_reason = try allocator.dupe(u8, "stop"),
            };
        }
        fn client(self: *@This()) ai.ModelClient {
            return .{ .ptr = self, .completeFn = complete };
        }
    };
    var transport = Transport{};
    const Probe = struct {
        saw_start: bool = false,
        saw_success: bool = false,
        fn onEvent(raw: ?*anyopaque, event: AgentEvent) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (event.kind == .auto_retry_start) {
                self.saw_start = std.mem.eql(u8, event.error_message orelse event.text, "ConnectionResetByPeer");
            }
            if (event.kind == .auto_retry_end) self.saw_success = event.success;
        }
    };
    var probe = Probe{};
    var result = try run(gpa, io, cwd, transport.client(), &sess, "transport", .{
        .retry_enabled = true,
        .retry_max_retries = 1,
        .retry_base_delay_ms = 0,
    }, Probe.onEvent, &probe);
    defer result.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), transport.calls);
    try std.testing.expectEqualStrings("transport recovered", result.final_text);
    try std.testing.expect(probe.saw_start);
    try std.testing.expect(probe.saw_success);
}
