//! JSONL tree session: header + messages, fork, branch tip, auto-save dir.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const session_migration = @import("session_migration.zig");
const ai = @import("../ai/root.zig");

/// Optional assistant metadata (upstream AgentMessage fields).
pub const AssistantMeta = struct {
    /// Provider-returned thinking/reasoning text retained for later replay.
    thinking: []const u8 = "",
    thinking_signature: []const u8 = "",
    thinking_redacted: bool = false,
    provider: []const u8 = "",
    api: []const u8 = "",
    model: []const u8 = "",
    response_id: []const u8 = "",
    response_model: []const u8 = "",
    /// Raw upstream AssistantMessage diagnostics array. Kept out of ChatMessage.
    diagnostics_json: []const u8 = "",
    error_message: []const u8 = "",
    raw_stop_reason: []const u8 = "",
    end_turn: ?bool = null,
    stop_reason: []const u8 = "",
    usage_input: u64 = 0,
    usage_output: u64 = 0,
    usage_cache_read: u64 = 0,
    usage_cache_write: u64 = 0,
    usage_cache_write_1h: ?u64 = null,
    usage_reasoning: ?u64 = null,
    usage_total: u64 = 0,
    cost_input: f64 = 0,
    cost_output: f64 = 0,
    cost_cache_read: f64 = 0,
    cost_cache_write: f64 = 0,
    cost_total: f64 = 0,

    pub fn deinit(self: *AssistantMeta, gpa: std.mem.Allocator) void {
        if (self.thinking.len > 0) gpa.free(self.thinking);
        if (self.thinking_signature.len > 0) gpa.free(self.thinking_signature);
        if (self.provider.len > 0) gpa.free(self.provider);
        if (self.api.len > 0) gpa.free(self.api);
        if (self.model.len > 0) gpa.free(self.model);
        if (self.response_id.len > 0) gpa.free(self.response_id);
        if (self.response_model.len > 0) gpa.free(self.response_model);
        if (self.diagnostics_json.len > 0) gpa.free(self.diagnostics_json);
        if (self.error_message.len > 0) gpa.free(self.error_message);
        if (self.raw_stop_reason.len > 0) gpa.free(self.raw_stop_reason);
        if (self.stop_reason.len > 0) gpa.free(self.stop_reason);
        self.* = .{};
    }

    pub fn dupe(self: AssistantMeta, gpa: std.mem.Allocator) !AssistantMeta {
        return .{
            .thinking = if (self.thinking.len > 0) try gpa.dupe(u8, self.thinking) else "",
            .thinking_signature = if (self.thinking_signature.len > 0) try gpa.dupe(u8, self.thinking_signature) else "",
            .thinking_redacted = self.thinking_redacted,
            .provider = if (self.provider.len > 0) try gpa.dupe(u8, self.provider) else "",
            .api = if (self.api.len > 0) try gpa.dupe(u8, self.api) else "",
            .model = if (self.model.len > 0) try gpa.dupe(u8, self.model) else "",
            .response_id = if (self.response_id.len > 0) try gpa.dupe(u8, self.response_id) else "",
            .response_model = if (self.response_model.len > 0) try gpa.dupe(u8, self.response_model) else "",
            .diagnostics_json = if (self.diagnostics_json.len > 0) try gpa.dupe(u8, self.diagnostics_json) else "",
            .error_message = if (self.error_message.len > 0) try gpa.dupe(u8, self.error_message) else "",
            .raw_stop_reason = if (self.raw_stop_reason.len > 0) try gpa.dupe(u8, self.raw_stop_reason) else "",
            .end_turn = self.end_turn,
            .stop_reason = if (self.stop_reason.len > 0) try gpa.dupe(u8, self.stop_reason) else "",
            .usage_input = self.usage_input,
            .usage_output = self.usage_output,
            .usage_cache_read = self.usage_cache_read,
            .usage_cache_write = self.usage_cache_write,
            .usage_cache_write_1h = self.usage_cache_write_1h,
            .usage_reasoning = self.usage_reasoning,
            .usage_total = self.usage_total,
            .cost_input = self.cost_input,
            .cost_output = self.cost_output,
            .cost_cache_read = self.cost_cache_read,
            .cost_cache_write = self.cost_cache_write,
            .cost_total = self.cost_total,
        };
    }
};

pub const EntryType = enum {
    message,
    compaction,
    branch_summary,
    session_info,
    label,
    custom,
    custom_message,
    model_change,
    thinking_level_change,
};

pub const SessionImage = ai.ChatImage;

fn cloneSessionImages(gpa: std.mem.Allocator, images: anytype) ![]SessionImage {
    if (images.len == 0) return &.{};
    const out = try gpa.alloc(SessionImage, images.len);
    errdefer gpa.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |image| {
        gpa.free(image.data_b64);
        gpa.free(image.mime_type);
    };
    for (images, 0..) |image, index| {
        out[index] = .{
            .data_b64 = try gpa.dupe(u8, image.data_b64),
            .mime_type = try gpa.dupe(u8, image.mime_type),
        };
        initialized += 1;
    }
    return out;
}

fn deinitSessionImages(gpa: std.mem.Allocator, images: []SessionImage) void {
    for (images) |image| {
        gpa.free(image.data_b64);
        gpa.free(image.mime_type);
    }
    if (images.len > 0) gpa.free(images);
}

pub const SessionEntry = struct {
    entry_type: EntryType = .message,
    id: []const u8,
    parent_id: ?[]const u8,
    role: []const u8,
    content: []const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,
    /// Tool name for toolResult entries (needed for Google functionResponse replay).
    tool_name: ?[]const u8 = null,
    /// Whether a tool-result entry represents a failed/aborted invocation.
    tool_is_error: bool = false,
    /// Optional single image carried by a tool result. Stored as raw base64 + MIME
    /// so provider adapters can replay it without lossy text conversion.
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
    /// Ordered images after the legacy first image. Keeping the first image in
    /// the historical fields allows old checkpoints to load unchanged while
    /// preserving every subsequent image block.
    images: []SessionImage = &.{},
    /// Native coding-agent shell message metadata. `content` stores the exact
    /// user-text projection consumed by model adapters; `bash_output` preserves
    /// the unmodified RPC/session payload for lossless round trips.
    bash_command: ?[]const u8 = null,
    bash_output: ?[]const u8 = null,
    bash_exit_code: ?i32 = null,
    bash_cancelled: bool = false,
    bash_truncated: bool = false,
    bash_full_output_path: ?[]const u8 = null,
    bash_exclude_from_context: bool = false,
    bash_timestamp_ms: i64 = 0,
    /// Tool definitions activated after this result (upstream addedToolNames).
    added_tool_names: []const []const u8 = &.{},
    /// Auxiliary/session-tree metadata. `raw_json` preserves upstream entries
    /// we do not otherwise need to interpret, without leaking them into context.
    raw_json: ?[]const u8 = null,
    target_id: ?[]const u8 = null,
    label: ?[]const u8 = null,
    custom_type: ?[]const u8 = null,
    data_json: ?[]const u8 = null,
    /// Compaction boundary metadata. `first_kept_entry_id` points to the first
    /// pre-compaction entry retained after the summary; `tokens_before` is the
    /// estimated context size before compaction. These fields are ignored for
    /// other entry types.
    first_kept_entry_id: ?[]const u8 = null,
    tokens_before: u64 = 0,
    from_hook: bool = false,
    display: bool = false,
    /// ISO-8601 timestamp owned string (persisted on save/load).
    timestamp: []const u8 = "",
    meta: AssistantMeta = .{},

    pub fn deinit(self: *SessionEntry, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        if (self.parent_id) |p| gpa.free(p);
        gpa.free(self.role);
        gpa.free(self.content);
        if (self.tool_call_id) |t| gpa.free(t);
        if (self.tool_calls_json) |t| gpa.free(t);
        if (self.tool_name) |t| gpa.free(t);
        if (self.image_b64) |data| gpa.free(data);
        if (self.image_mime) |mime| gpa.free(mime);
        deinitSessionImages(gpa, self.images);
        if (self.bash_command) |value| gpa.free(value);
        if (self.bash_output) |value| gpa.free(value);
        if (self.bash_full_output_path) |value| gpa.free(value);
        if (self.added_tool_names.len > 0) {
            for (self.added_tool_names) |name| gpa.free(name);
            gpa.free(self.added_tool_names);
        }
        if (self.raw_json) |v| gpa.free(v);
        if (self.target_id) |v| gpa.free(v);
        if (self.label) |v| gpa.free(v);
        if (self.custom_type) |v| gpa.free(v);
        if (self.data_json) |v| gpa.free(v);
        if (self.first_kept_entry_id) |v| gpa.free(v);
        if (self.timestamp.len > 0) gpa.free(self.timestamp);
        self.meta.deinit(gpa);
        self.* = undefined;
    }

    /// Deep-copy a durable entry into `gpa`. Compaction and session-tree
    /// reconstruction use this instead of field-by-field projections so new
    /// metadata cannot be silently lost when the session is rewritten.
    pub fn dupe(self: SessionEntry, gpa: std.mem.Allocator) !SessionEntry {
        var out: SessionEntry = undefined;
        {
            const id = try gpa.dupe(u8, self.id);
            errdefer gpa.free(id);
            const role = try gpa.dupe(u8, self.role);
            errdefer gpa.free(role);
            const content = try gpa.dupe(u8, self.content);
            errdefer gpa.free(content);
            out = .{
                .entry_type = self.entry_type,
                .id = id,
                .parent_id = null,
                .role = role,
                .content = content,
                .tool_is_error = self.tool_is_error,
                .bash_exit_code = self.bash_exit_code,
                .bash_cancelled = self.bash_cancelled,
                .bash_truncated = self.bash_truncated,
                .bash_exclude_from_context = self.bash_exclude_from_context,
                .bash_timestamp_ms = self.bash_timestamp_ms,
                .tokens_before = self.tokens_before,
                .from_hook = self.from_hook,
                .display = self.display,
            };
        }
        errdefer out.deinit(gpa);

        out.parent_id = if (self.parent_id) |value| try gpa.dupe(u8, value) else null;
        out.tool_call_id = if (self.tool_call_id) |value| try gpa.dupe(u8, value) else null;
        out.tool_calls_json = if (self.tool_calls_json) |value| try gpa.dupe(u8, value) else null;
        out.tool_name = if (self.tool_name) |value| try gpa.dupe(u8, value) else null;
        out.image_b64 = if (self.image_b64) |value| try gpa.dupe(u8, value) else null;
        out.image_mime = if (self.image_mime) |value| try gpa.dupe(u8, value) else null;
        out.images = try cloneSessionImages(gpa, self.images);
        out.bash_command = if (self.bash_command) |value| try gpa.dupe(u8, value) else null;
        out.bash_output = if (self.bash_output) |value| try gpa.dupe(u8, value) else null;
        out.bash_full_output_path = if (self.bash_full_output_path) |value| try gpa.dupe(u8, value) else null;
        if (self.added_tool_names.len > 0) {
            var added_tool_names = try gpa.alloc([]const u8, self.added_tool_names.len);
            var initialized: usize = 0;
            errdefer {
                for (added_tool_names[0..initialized]) |name| gpa.free(name);
                gpa.free(added_tool_names);
            }
            for (self.added_tool_names, 0..) |name, index| {
                added_tool_names[index] = try gpa.dupe(u8, name);
                initialized += 1;
            }
            out.added_tool_names = added_tool_names;
        }
        out.raw_json = if (self.raw_json) |value| try gpa.dupe(u8, value) else null;
        out.target_id = if (self.target_id) |value| try gpa.dupe(u8, value) else null;
        out.label = if (self.label) |value| try gpa.dupe(u8, value) else null;
        out.custom_type = if (self.custom_type) |value| try gpa.dupe(u8, value) else null;
        out.data_json = if (self.data_json) |value| try gpa.dupe(u8, value) else null;
        out.first_kept_entry_id = if (self.first_kept_entry_id) |value| try gpa.dupe(u8, value) else null;
        out.timestamp = if (self.timestamp.len > 0) try gpa.dupe(u8, self.timestamp) else "";
        out.meta = try self.meta.dupe(gpa);
        return out;
    }
};

pub const SessionInfo = struct {
    path: []const u8,
    id: []const u8,
    cwd: []const u8,
    name: []const u8,
    parent_session_path: ?[]const u8 = null,
    created_at: []const u8,
    message_count: usize = 0,
    first_message: []const u8,
    all_messages_text: []const u8,
    valid: bool = true,
    mtime_hint: []const u8 = "",
    /// Filesystem modification timestamp used for deterministic resume ordering.
    mtime_ns: i96 = 0,

    pub fn deinit(self: *SessionInfo, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        gpa.free(self.id);
        gpa.free(self.cwd);
        gpa.free(self.name);
        if (self.parent_session_path) |parent| gpa.free(parent);
        gpa.free(self.created_at);
        gpa.free(self.first_message);
        gpa.free(self.all_messages_text);
        if (self.mtime_hint.len > 0) gpa.free(self.mtime_hint);
        self.* = undefined;
    }
};

pub const SessionStats = struct {
    user_messages: usize = 0,
    assistant_messages: usize = 0,
    tool_calls: usize = 0,
    tool_results: usize = 0,
    total_messages: usize = 0,
    tokens: Tokens = .{},
    cost: f64 = 0,

    pub const Tokens = struct {
        input: u64 = 0,
        output: u64 = 0,
        cache_read: u64 = 0,
        cache_write: u64 = 0,
        total: u64 = 0,
    };
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    id: []const u8,
    cwd: []const u8,
    name: []const u8,
    /// Stable session-header creation time. Saving must not rewrite history.
    created_at: []const u8,
    /// Physical parent session path used by upstream fork/thread discovery.
    parent_session: ?[]const u8 = null,
    /// Active leaf tip for tree navigation (entry id).
    tip_id: ?[]const u8 = null,
    entries: std.ArrayList(SessionEntry),
    /// In-memory-only assistant attempts removed from the active Agent state by
    /// automatic retry. They remain in JSONL for forensics, but subsequent
    /// prompts in the same live session omit them from provider context. A
    /// save/load cycle intentionally clears this list, matching upstream's
    /// reconstruction from durable session entries.
    retry_excluded_entry_ids: std.ArrayList([]u8) = .empty,
    next_seq: u64 = 1,

    pub fn init(gpa: std.mem.Allocator, id: []const u8, cwd: []const u8) !Session {
        const id_owned = try gpa.dupe(u8, id);
        errdefer gpa.free(id_owned);
        const cwd_owned = try gpa.dupe(u8, cwd);
        errdefer gpa.free(cwd_owned);
        const name_owned = try gpa.dupe(u8, "");
        errdefer gpa.free(name_owned);
        var timestamp_buf: [32]u8 = undefined;
        const created_at = try gpa.dupe(u8, formatIsoTimestamp(&timestamp_buf));
        errdefer gpa.free(created_at);
        return .{
            .gpa = gpa,
            .id = id_owned,
            .cwd = cwd_owned,
            .name = name_owned,
            .created_at = created_at,
            .parent_session = null,
            .tip_id = null,
            .entries = .empty,
            .retry_excluded_entry_ids = .empty,
            .next_seq = 1,
        };
    }

    pub fn deinit(self: *Session) void {
        for (self.entries.items) |*e| e.deinit(self.gpa);
        self.entries.deinit(self.gpa);
        for (self.retry_excluded_entry_ids.items) |id| self.gpa.free(id);
        self.retry_excluded_entry_ids.deinit(self.gpa);
        self.gpa.free(self.id);
        self.gpa.free(self.cwd);
        self.gpa.free(self.name);
        self.gpa.free(self.created_at);
        if (self.parent_session) |path| self.gpa.free(path);
        if (self.tip_id) |t| self.gpa.free(t);
        self.* = undefined;
    }

    pub fn excludeEntryFromActiveContext(self: *Session, entry_id: []const u8) !void {
        if (self.getEntry(entry_id) == null) return error.UnknownEntry;
        if (self.isEntryExcludedFromActiveContext(entry_id)) return;
        const owned_id = try self.gpa.dupe(u8, entry_id);
        errdefer self.gpa.free(owned_id);
        try self.retry_excluded_entry_ids.append(self.gpa, owned_id);
    }

    pub fn isEntryExcludedFromActiveContext(self: *const Session, entry_id: []const u8) bool {
        for (self.retry_excluded_entry_ids.items) |candidate| {
            if (std.mem.eql(u8, candidate, entry_id)) return true;
        }
        return false;
    }

    /// Drop transient exclusions whose durable entries were removed by a tree
    /// rewrite such as compaction.
    pub fn pruneActiveContextExclusions(self: *Session) void {
        var write_index: usize = 0;
        for (self.retry_excluded_entry_ids.items) |id| {
            if (self.getEntry(id) != null) {
                self.retry_excluded_entry_ids.items[write_index] = id;
                write_index += 1;
            } else {
                self.gpa.free(id);
            }
        }
        self.retry_excluded_entry_ids.shrinkRetainingCapacity(write_index);
    }

    pub fn setName(self: *Session, name: []const u8) !void {
        const replacement = try self.gpa.dupe(u8, name);
        self.gpa.free(self.name);
        self.name = replacement;
    }

    pub fn setParentSession(self: *Session, path: ?[]const u8) !void {
        const replacement = if (path) |value| try self.gpa.dupe(u8, value) else null;
        if (self.parent_session) |old| self.gpa.free(old);
        self.parent_session = replacement;
    }

    pub fn setTip(self: *Session, entry_id: []const u8) !void {
        // Verify entry exists
        var found = false;
        for (self.entries.items) |e| {
            if (std.mem.eql(u8, e.id, entry_id)) {
                found = true;
                break;
            }
        }
        if (!found) return error.UnknownEntry;
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, entry_id);
    }

    pub fn getEntry(self: *const Session, id: []const u8) ?*const SessionEntry {
        for (self.entries.items) |*entry| if (std.mem.eql(u8, entry.id, id)) return entry;
        return null;
    }

    pub fn getChildren(self: *const Session, gpa: std.mem.Allocator, parent_id: []const u8) ![]const *const SessionEntry {
        var out: std.ArrayList(*const SessionEntry) = .empty;
        errdefer out.deinit(gpa);
        for (self.entries.items) |*entry| {
            if (entry.parent_id) |parent| if (std.mem.eql(u8, parent, parent_id)) try out.append(gpa, entry);
        }
        return try out.toOwnedSlice(gpa);
    }

    pub fn resetTip(self: *Session) void {
        if (self.tip_id) |tip| self.gpa.free(tip);
        self.tip_id = null;
    }

    pub fn getLabel(self: *const Session, target_id: []const u8) ?[]const u8 {
        var resolved: ?[]const u8 = null;
        for (self.entries.items) |entry| {
            if (entry.entry_type != .label) continue;
            const target = entry.target_id orelse continue;
            if (!std.mem.eql(u8, target, target_id)) continue;
            resolved = if (entry.label) |label| if (label.len > 0) label else null else null;
        }
        return resolved;
    }

    pub fn appendLabelChange(self: *Session, target_id: []const u8, label: ?[]const u8) ![]const u8 {
        if (self.getEntry(target_id) == null) return error.UnknownEntry;
        return try self.appendAux(.label, .{
            .target_id = target_id,
            .label = if (label) |value| std.mem.trim(u8, value, " \t\r\n") else null,
        });
    }

    pub fn appendCustomEntry(self: *Session, custom_type: []const u8, data_json: ?[]const u8) ![]const u8 {
        if (custom_type.len == 0) return error.InvalidCustomEntry;
        if (data_json) |raw| try validateJsonValue(self.gpa, raw);
        return try self.appendAux(.custom, .{ .custom_type = custom_type, .data_json = data_json });
    }

    /// Append an extension-provided context message. It is durable in the
    /// session tree and projects to a user-context message for provider calls,
    /// matching the original custom-message ingestion behavior.
    pub fn appendCustomMessage(self: *Session, custom_type: []const u8, content: []const u8, display: bool) ![]const u8 {
        if (custom_type.len == 0) return error.InvalidCustomEntry;
        return try self.appendAux(.custom_message, .{
            .custom_type = custom_type,
            .content = content,
            .display = display,
        });
    }

    pub fn appendSessionInfo(self: *Session, name: []const u8) ![]const u8 {
        const sanitized = try sanitizeSingleLine(self.gpa, name);
        defer self.gpa.free(sanitized);
        try self.setName(sanitized);
        return try self.appendAux(.session_info, .{ .content = sanitized });
    }

    /// Record the active model identity as a native session-tree entry.
    pub fn appendModelChange(self: *Session, provider: []const u8, model_id: []const u8) ![]const u8 {
        if (provider.len == 0 or model_id.len == 0) return error.InvalidModelChange;
        return try self.appendAux(.model_change, .{ .content = model_id, .custom_type = provider });
    }

    /// Record the active reasoning effort as a native session-tree entry.
    pub fn appendThinkingLevelChange(self: *Session, level: []const u8) ![]const u8 {
        if (level.len == 0) return error.InvalidThinkingLevelChange;
        return try self.appendAux(.thinking_level_change, .{ .content = level });
    }

    const AuxOptions = struct {
        content: []const u8 = "",
        target_id: ?[]const u8 = null,
        label: ?[]const u8 = null,
        custom_type: ?[]const u8 = null,
        data_json: ?[]const u8 = null,
        display: bool = false,
    };

    fn nextEntryId(self: *Session) ![]u8 {
        while (true) {
            const id = try std.fmt.allocPrint(self.gpa, "m{d}", .{self.next_seq});
            self.next_seq += 1;
            if (self.getEntry(id) == null) return id;
            self.gpa.free(id);
        }
    }

    fn observeEntryId(self: *Session, id: []const u8) void {
        if (id.len < 2 or id[0] != 'm') return;
        const value = std.fmt.parseUnsigned(u64, id[1..], 10) catch return;
        if (value >= self.next_seq and value < std.math.maxInt(u64)) self.next_seq = value + 1;
    }

    fn appendAux(self: *Session, entry_type: EntryType, opts: AuxOptions) ![]const u8 {
        const id = try self.nextEntryId();
        errdefer self.gpa.free(id);
        var ts_buf: [32]u8 = undefined;
        const timestamp = try self.gpa.dupe(u8, formatIsoTimestamp(&ts_buf));
        errdefer self.gpa.free(timestamp);
        const parent = self.lastEntryId();
        try self.entries.append(self.gpa, .{
            .entry_type = entry_type,
            .id = id,
            .parent_id = if (parent) |value| try self.gpa.dupe(u8, value) else null,
            .role = try self.gpa.dupe(u8, if (entry_type == .custom_message) "user" else "aux"),
            .content = try self.gpa.dupe(u8, opts.content),
            .target_id = if (opts.target_id) |value| try self.gpa.dupe(u8, value) else null,
            .label = if (opts.label) |value| try self.gpa.dupe(u8, value) else null,
            .custom_type = if (opts.custom_type) |value| try self.gpa.dupe(u8, value) else null,
            .data_json = if (opts.data_json) |value| try self.gpa.dupe(u8, value) else null,
            .display = opts.display,
            .timestamp = timestamp,
        });
        if (self.tip_id) |tip| self.gpa.free(tip);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    /// Append an upstream-compatible compaction boundary without rewriting or
    /// deleting prior session history. The entry becomes the active tip; context
    /// reconstruction later projects the summary plus the retained pre-boundary
    /// tail beginning at `first_kept_entry_id`.
    pub fn appendCompaction(
        self: *Session,
        summary: []const u8,
        first_kept_entry_id: []const u8,
        tokens_before: u64,
        details_json: ?[]const u8,
        from_hook: bool,
        meta: AssistantMeta,
    ) ![]const u8 {
        if (self.getEntry(first_kept_entry_id) == null) return error.UnknownEntry;
        if (details_json) |raw| try validateJsonValue(self.gpa, raw);

        const id = try self.nextEntryId();
        errdefer self.gpa.free(id);
        var ts_buf: [32]u8 = undefined;
        const timestamp = try self.gpa.dupe(u8, formatIsoTimestamp(&ts_buf));
        errdefer self.gpa.free(timestamp);
        const role = try self.gpa.dupe(u8, "system");
        errdefer self.gpa.free(role);
        const content = try self.gpa.dupe(u8, summary);
        errdefer self.gpa.free(content);
        const parent_owned = if (self.lastEntryId()) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (parent_owned) |value| self.gpa.free(value);
        const first_kept_owned = try self.gpa.dupe(u8, first_kept_entry_id);
        errdefer self.gpa.free(first_kept_owned);
        const details_owned = if (details_json) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (details_owned) |value| self.gpa.free(value);
        var meta_owned = try meta.dupe(self.gpa);
        errdefer meta_owned.deinit(self.gpa);

        try self.entries.append(self.gpa, .{
            .entry_type = .compaction,
            .id = id,
            .parent_id = parent_owned,
            .role = role,
            .content = content,
            .data_json = details_owned,
            .first_kept_entry_id = first_kept_owned,
            .tokens_before = tokens_before,
            .from_hook = from_hook,
            .timestamp = timestamp,
            .meta = meta_owned,
        });
        if (self.tip_id) |tip| self.gpa.free(tip);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    /// Attach a durable branch summary at an arbitrary tree position and make
    /// it the active tip. `from_id` follows the upstream branch-summary entry
    /// contract (the target branch position, or `"root"`).
    pub fn appendBranchSummary(
        self: *Session,
        parent_id: ?[]const u8,
        from_id: []const u8,
        summary: []const u8,
        details_json: ?[]const u8,
        meta: AssistantMeta,
    ) ![]const u8 {
        return self.appendBranchSummaryWithHook(parent_id, from_id, summary, details_json, false, meta);
    }

    pub fn appendBranchSummaryWithHook(
        self: *Session,
        parent_id: ?[]const u8,
        from_id: []const u8,
        summary: []const u8,
        details_json: ?[]const u8,
        from_hook: bool,
        meta: AssistantMeta,
    ) ![]const u8 {
        if (parent_id) |parent| if (self.getEntry(parent) == null) return error.UnknownEntry;
        if (details_json) |raw| try validateJsonValue(self.gpa, raw);

        const id = try self.nextEntryId();
        errdefer self.gpa.free(id);
        var ts_buf: [32]u8 = undefined;
        const timestamp = try self.gpa.dupe(u8, formatIsoTimestamp(&ts_buf));
        errdefer self.gpa.free(timestamp);
        const role = try self.gpa.dupe(u8, "system");
        errdefer self.gpa.free(role);
        const content = try self.gpa.dupe(u8, summary);
        errdefer self.gpa.free(content);
        const parent_owned = if (parent_id) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (parent_owned) |value| self.gpa.free(value);
        const from_owned = try self.gpa.dupe(u8, from_id);
        errdefer self.gpa.free(from_owned);
        const details_owned = if (details_json) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (details_owned) |value| self.gpa.free(value);
        var meta_owned = try meta.dupe(self.gpa);
        errdefer meta_owned.deinit(self.gpa);

        try self.entries.append(self.gpa, .{
            .entry_type = .branch_summary,
            .id = id,
            .parent_id = parent_owned,
            .role = role,
            .content = content,
            .target_id = from_owned,
            .data_json = details_owned,
            .from_hook = from_hook,
            .timestamp = timestamp,
            .meta = meta_owned,
        });
        if (self.tip_id) |tip| self.gpa.free(tip);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    pub fn appendMessage(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
        tool_calls_json: ?[]const u8,
    ) ![]const u8 {
        return self.appendMessageMeta(parent_id, role, content, tool_call_id, tool_calls_json, null, .{});
    }

    /// Append a user/system message with one inline image. Multiple images are
    /// represented as adjacent message entries so each attachment remains
    /// durable in the v3 JSONL tree and provider adapters can replay it.
    pub fn appendMessageWithMedia(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        image_b64: []const u8,
        image_mime: []const u8,
    ) ![]const u8 {
        const id = try self.appendMessageMeta(parent_id, role, content, null, null, null, .{});
        const entry = &self.entries.items[self.entries.items.len - 1];
        entry.image_b64 = try self.gpa.dupe(u8, image_b64);
        entry.image_mime = try self.gpa.dupe(u8, image_mime);
        return id;
    }

    /// Append one user/system message with an arbitrary image array. The first
    /// image occupies the legacy fields and remaining images retain order in
    /// `images`, yielding one canonical upstream message instead of adjacent
    /// synthetic messages.
    pub fn appendMessageWithImages(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        images: anytype,
    ) ![]const u8 {
        const id = try self.appendMessageMeta(parent_id, role, content, null, null, null, .{});
        if (images.len == 0) return id;
        const entry = &self.entries.items[self.entries.items.len - 1];
        entry.image_b64 = try self.gpa.dupe(u8, images[0].data_b64);
        entry.image_mime = try self.gpa.dupe(u8, images[0].mime_type);
        entry.images = try cloneSessionImages(self.gpa, images[1..]);
        return id;
    }

    pub fn appendToolResult(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
    ) ![]const u8 {
        return self.appendToolResultStatus(parent_id, content, tool_call_id, tool_name, false);
    }

    pub fn appendToolResultStatus(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
        is_error: bool,
    ) ![]const u8 {
        return self.appendToolResultStatusWithAdded(parent_id, content, tool_call_id, tool_name, is_error, &.{});
    }

    pub fn appendToolResultStatusWithAdded(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
        is_error: bool,
        added_tool_names: []const []const u8,
    ) ![]const u8 {
        return self.appendToolResultStatusWithMedia(parent_id, content, tool_call_id, tool_name, is_error, added_tool_names, null, null);
    }

    pub fn appendToolResultStatusWithMedia(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
        is_error: bool,
        added_tool_names: []const []const u8,
        image_b64: ?[]const u8,
        image_mime: ?[]const u8,
    ) ![]const u8 {
        return self.appendToolResultStatusWithImages(parent_id, content, tool_call_id, tool_name, is_error, added_tool_names, image_b64, image_mime, &.{});
    }

    pub fn appendToolResultStatusWithImages(
        self: *Session,
        parent_id: ?[]const u8,
        content: []const u8,
        tool_call_id: []const u8,
        tool_name: []const u8,
        is_error: bool,
        added_tool_names: []const []const u8,
        image_b64: ?[]const u8,
        image_mime: ?[]const u8,
        images: anytype,
    ) ![]const u8 {
        const id = try self.appendMessageMeta(parent_id, "tool", content, tool_call_id, null, tool_name, .{});
        const entry = &self.entries.items[self.entries.items.len - 1];
        entry.tool_is_error = is_error;
        if (image_b64) |data| entry.image_b64 = try self.gpa.dupe(u8, data);
        if (image_mime) |mime| entry.image_mime = try self.gpa.dupe(u8, mime);
        entry.images = try cloneSessionImages(self.gpa, images);
        if (added_tool_names.len > 0) {
            var owned = try self.gpa.alloc([]const u8, added_tool_names.len);
            errdefer self.gpa.free(owned);
            var count: usize = 0;
            errdefer for (owned[0..count]) |name| self.gpa.free(name);
            for (added_tool_names, 0..) |name, i| {
                owned[i] = try self.gpa.dupe(u8, name);
                count += 1;
            }
            entry.added_tool_names = owned;
        }
        return id;
    }

    pub fn appendBashExecution(
        self: *Session,
        parent_id: ?[]const u8,
        command: []const u8,
        output: []const u8,
        exit_code: ?i32,
        cancelled: bool,
        truncated: bool,
        full_output_path: ?[]const u8,
        exclude_from_context: bool,
    ) ![]const u8 {
        const projected = try formatBashExecutionText(self.gpa, command, output, exit_code, cancelled, truncated, full_output_path);
        defer self.gpa.free(projected);
        const id = try self.appendMessageMeta(parent_id, "bashExecution", projected, null, null, null, .{});
        const entry = &self.entries.items[self.entries.items.len - 1];
        entry.bash_command = try self.gpa.dupe(u8, command);
        entry.bash_output = try self.gpa.dupe(u8, output);
        entry.bash_exit_code = exit_code;
        entry.bash_cancelled = cancelled;
        entry.bash_truncated = truncated;
        entry.bash_full_output_path = if (full_output_path) |path| try self.gpa.dupe(u8, path) else null;
        entry.bash_exclude_from_context = exclude_from_context;
        entry.bash_timestamp_ms = wallishSeconds() * 1000;
        return id;
    }

    pub fn appendMessageMeta(
        self: *Session,
        parent_id: ?[]const u8,
        role: []const u8,
        content: []const u8,
        tool_call_id: ?[]const u8,
        tool_calls_json: ?[]const u8,
        tool_name: ?[]const u8,
        meta: AssistantMeta,
    ) ![]const u8 {
        const id = try self.nextEntryId();
        errdefer self.gpa.free(id);

        var ts_buf: [32]u8 = undefined;
        const ts_now = formatIsoTimestamp(&ts_buf);
        try self.entries.append(self.gpa, .{
            .id = id,
            .parent_id = if (parent_id) |p| try self.gpa.dupe(u8, p) else null,
            .role = try self.gpa.dupe(u8, role),
            .content = try self.gpa.dupe(u8, content),
            .tool_call_id = if (tool_call_id) |t| try self.gpa.dupe(u8, t) else null,
            .tool_calls_json = if (tool_calls_json) |t| try self.gpa.dupe(u8, t) else null,
            .tool_name = if (tool_name) |t| try self.gpa.dupe(u8, t) else null,
            .timestamp = try self.gpa.dupe(u8, ts_now),
            .meta = try meta.dupe(self.gpa),
        });
        if (self.tip_id) |t| self.gpa.free(t);
        self.tip_id = try self.gpa.dupe(u8, id);
        return id;
    }

    pub fn lastEntryId(self: *const Session) ?[]const u8 {
        if (self.tip_id) |t| return t;
        if (self.entries.items.len == 0) return null;
        return self.entries.items[self.entries.items.len - 1].id;
    }

    /// Entries on the path from root to `tip_id`. A null tip represents the
    /// position before the first session entry. Unknown or cyclic parents are
    /// rejected instead of returning a silently truncated branch.
    pub fn branchEntriesAt(self: *const Session, gpa: std.mem.Allocator, tip_id: ?[]const u8) ![]const *const SessionEntry {
        const tip = tip_id orelse return try gpa.alloc(*const SessionEntry, 0);
        var chain: std.ArrayList(*const SessionEntry) = .empty;
        errdefer chain.deinit(gpa);
        var seen = std.StringHashMap(void).init(gpa);
        defer seen.deinit();

        var current: ?[]const u8 = tip;
        while (current) |cid| {
            if (seen.contains(cid)) return error.ParentCycle;
            try seen.put(cid, {});
            const entry = self.getEntry(cid) orelse return error.UnknownEntry;
            try chain.append(gpa, entry);
            current = entry.parent_id;
        }
        std.mem.reverse(*const SessionEntry, chain.items);
        return try chain.toOwnedSlice(gpa);
    }

    /// Entries on the active branch (from root to tip).
    pub fn branchEntries(self: *const Session, gpa: std.mem.Allocator) ![]const *const SessionEntry {
        return self.branchEntriesAt(gpa, self.lastEntryId());
    }

    /// Build the compaction-aware active context entry list. The complete
    /// root-to-tip branch remains durable; only the provider-facing projection
    /// is shortened. With a latest compaction boundary, context is:
    ///   summary entry, retained pre-boundary tail, post-boundary entries.
    pub fn contextEntries(self: *const Session, gpa: std.mem.Allocator) ![]const *const SessionEntry {
        const path = try self.branchEntries(gpa);
        var retain_path = false;
        defer if (!retain_path) gpa.free(path);

        var latest_index: ?usize = null;
        for (path, 0..) |entry, index| {
            if (entry.entry_type == .compaction) latest_index = index;
        }
        const compaction_index = latest_index orelse {
            retain_path = true;
            return path;
        };
        const boundary = path[compaction_index];
        const first_kept_id = boundary.first_kept_entry_id orelse {
            retain_path = true;
            return path;
        };

        var out: std.ArrayList(*const SessionEntry) = .empty;
        errdefer out.deinit(gpa);
        try out.append(gpa, boundary);

        var found_first = false;
        for (path[0..compaction_index]) |entry| {
            if (std.mem.eql(u8, entry.id, first_kept_id)) found_first = true;
            if (found_first) try out.append(gpa, entry);
        }
        // A malformed or hand-edited boundary must not silently erase context.
        if (!found_first) {
            out.deinit(gpa);
            retain_path = true;
            return path;
        }
        for (path[compaction_index + 1 ..]) |entry| try out.append(gpa, entry);
        return try out.toOwnedSlice(gpa);
    }

    pub const ActiveSettings = struct {
        has_messages: bool = false,
        provider: ?[]const u8 = null,
        model_id: ?[]const u8 = null,
        thinking_level: ?[]const u8 = null,
        has_thinking_entry: bool = false,
    };

    /// Derive runtime settings from the active root-to-tip branch. Explicit
    /// model/thinking entries win in branch order, while assistant metadata
    /// restores the model used by older sessions without model-change entries.
    /// Returned slices borrow from this Session.
    pub fn activeSettings(self: *const Session, gpa: std.mem.Allocator) !ActiveSettings {
        const branch = try self.branchEntries(gpa);
        defer gpa.free(branch);
        var result: ActiveSettings = .{};
        for (branch) |entry| {
            if (entry.entry_type == .message) {
                result.has_messages = true;
                if (std.mem.eql(u8, entry.role, "assistant") and entry.meta.provider.len > 0 and entry.meta.model.len > 0) {
                    result.provider = entry.meta.provider;
                    result.model_id = entry.meta.model;
                }
                continue;
            }
            switch (entry.entry_type) {
                .model_change => {
                    if (entry.custom_type) |provider| {
                        if (provider.len > 0 and entry.content.len > 0) {
                            result.provider = provider;
                            result.model_id = entry.content;
                        }
                    }
                },
                .thinking_level_change => {
                    if (entry.content.len > 0) {
                        result.thinking_level = entry.content;
                        result.has_thinking_entry = true;
                    }
                },
                else => {},
            }
        }
        return result;
    }

    /// Serialize as upstream pi session-format v3 JSONL (type:session header + nested message).
    pub fn toJsonl(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);

        {
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            // Upstream SessionHeader: {"type":"session","version":3,"id":"...","timestamp":"...","cwd":"..."}
            try line.writer.writeAll("{\"type\":\"session\",\"version\":3,\"id\":");
            try std.json.Stringify.value(self.id, .{}, &line.writer);
            try line.writer.writeAll(",\"timestamp\":");
            try std.json.Stringify.value(self.created_at, .{}, &line.writer);
            try line.writer.writeAll(",\"cwd\":");
            try std.json.Stringify.value(self.cwd, .{}, &line.writer);
            if (self.parent_session) |parent| {
                try line.writer.writeAll(",\"parentSession\":");
                try std.json.Stringify.value(parent, .{}, &line.writer);
            }
            if (self.name.len > 0) {
                try line.writer.writeAll(",\"name\":");
                try std.json.Stringify.value(self.name, .{}, &line.writer);
            }
            // Tip is an extension field for pi-zig (ignored by upstream)
            if (self.tip_id) |t| {
                try line.writer.writeAll(",\"tipId\":");
                try std.json.Stringify.value(t, .{}, &line.writer);
            }
            try line.writer.writeAll(",\"next_seq\":");
            try line.writer.print("{d}", .{self.next_seq});
            try line.writer.writeAll("}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        for (self.entries.items) |e| {
            if (e.entry_type != .message) {
                if (e.raw_json) |raw| {
                    try out.appendSlice(gpa, raw);
                    try out.append(gpa, '\n');
                    continue;
                }
                const aux = try serializeAuxEntry(gpa, e);
                defer gpa.free(aux);
                try out.appendSlice(gpa, aux);
                try out.append(gpa, '\n');
                continue;
            }
            var line: std.Io.Writer.Allocating = .init(gpa);
            defer line.deinit();
            try line.writer.writeAll("{\"type\":\"message\",\"id\":");
            try std.json.Stringify.value(e.id, .{}, &line.writer);
            try line.writer.writeAll(",\"parentId\":");
            if (e.parent_id) |p| {
                try std.json.Stringify.value(p, .{}, &line.writer);
            } else {
                try line.writer.writeAll("null");
            }
            try line.writer.writeAll(",\"timestamp\":");
            if (e.timestamp.len > 0) {
                try std.json.Stringify.value(e.timestamp, .{}, &line.writer);
            } else {
                var ts_buf: [32]u8 = undefined;
                try std.json.Stringify.value(formatIsoTimestamp(&ts_buf), .{}, &line.writer);
            }
            try line.writer.writeAll(",\"message\":{");
            // Map internal "tool" role → upstream "toolResult"
            const out_role: []const u8 = if (std.mem.eql(u8, e.role, "tool")) "toolResult" else e.role;
            try line.writer.writeAll("\"role\":");
            try std.json.Stringify.value(out_role, .{}, &line.writer);
            if (std.mem.eql(u8, out_role, "bashExecution")) {
                try line.writer.writeAll(",\"command\":");
                try std.json.Stringify.value(e.bash_command orelse "", .{}, &line.writer);
                try line.writer.writeAll(",\"output\":");
                try std.json.Stringify.value(e.bash_output orelse "", .{}, &line.writer);
                if (e.bash_exit_code) |code| {
                    try line.writer.writeAll(",\"exitCode\":");
                    try line.writer.print("{d}", .{code});
                }
                try line.writer.writeAll(",\"cancelled\":");
                try line.writer.writeAll(if (e.bash_cancelled) "true" else "false");
                try line.writer.writeAll(",\"truncated\":");
                try line.writer.writeAll(if (e.bash_truncated) "true" else "false");
                if (e.bash_full_output_path) |path| {
                    try line.writer.writeAll(",\"fullOutputPath\":");
                    try std.json.Stringify.value(path, .{}, &line.writer);
                }
                if (e.bash_exclude_from_context) try line.writer.writeAll(",\"excludeFromContext\":true");
                try line.writer.writeAll(",\"timestamp\":");
                try line.writer.print("{d}", .{e.bash_timestamp_ms});
            } else if (std.mem.eql(u8, out_role, "assistant")) {
                try line.writer.writeAll(",\"content\":[");
                var first_content = true;
                if (e.meta.thinking.len > 0) {
                    try line.writer.writeAll("{\"type\":\"thinking\",\"thinking\":");
                    try std.json.Stringify.value(e.meta.thinking, .{}, &line.writer);
                    if (e.meta.thinking_signature.len > 0) {
                        try line.writer.writeAll(",\"thinkingSignature\":");
                        try std.json.Stringify.value(e.meta.thinking_signature, .{}, &line.writer);
                    }
                    if (e.meta.thinking_redacted) try line.writer.writeAll(",\"redacted\":true");
                    try line.writer.writeAll("}");
                    first_content = false;
                }
                if (e.content.len > 0 or first_content) {
                    if (!first_content) try line.writer.writeAll(",");
                    try line.writer.writeAll("{\"type\":\"text\",\"text\":");
                    try std.json.Stringify.value(e.content, .{}, &line.writer);
                    try line.writer.writeAll("}");
                }
                try line.writer.writeAll("]");
                if (e.tool_calls_json) |tcj| {
                    try line.writer.writeAll(",\"toolCalls\":");
                    try line.writer.writeAll(tcj);
                }
                // Upstream AssistantMessage metadata
                if (e.meta.provider.len > 0) {
                    try line.writer.writeAll(",\"provider\":");
                    try std.json.Stringify.value(e.meta.provider, .{}, &line.writer);
                }
                if (e.meta.api.len > 0) {
                    try line.writer.writeAll(",\"api\":");
                    try std.json.Stringify.value(e.meta.api, .{}, &line.writer);
                }
                if (e.meta.model.len > 0) {
                    try line.writer.writeAll(",\"model\":");
                    try std.json.Stringify.value(e.meta.model, .{}, &line.writer);
                }
                if (e.meta.response_id.len > 0) {
                    try line.writer.writeAll(",\"responseId\":");
                    try std.json.Stringify.value(e.meta.response_id, .{}, &line.writer);
                }
                if (e.meta.response_model.len > 0) {
                    try line.writer.writeAll(",\"responseModel\":");
                    try std.json.Stringify.value(e.meta.response_model, .{}, &line.writer);
                }
                if (e.meta.diagnostics_json.len > 0) {
                    try line.writer.writeAll(",\"diagnostics\":");
                    try line.writer.writeAll(e.meta.diagnostics_json);
                }
                if (e.meta.error_message.len > 0) {
                    try line.writer.writeAll(",\"errorMessage\":");
                    try std.json.Stringify.value(e.meta.error_message, .{}, &line.writer);
                }
                if (e.meta.raw_stop_reason.len > 0) {
                    try line.writer.writeAll(",\"rawStopReason\":");
                    try std.json.Stringify.value(e.meta.raw_stop_reason, .{}, &line.writer);
                }
                if (e.meta.end_turn) |value| {
                    try line.writer.writeAll(",\"endTurn\":");
                    try line.writer.writeAll(if (value) "true" else "false");
                }
                const sr: []const u8 = if (e.meta.stop_reason.len > 0)
                    e.meta.stop_reason
                else if (e.tool_calls_json != null)
                    "toolUse"
                else
                    "stop";
                try line.writer.writeAll(",\"stopReason\":");
                try std.json.Stringify.value(sr, .{}, &line.writer);
                if (e.meta.usage_total > 0 or e.meta.usage_input > 0 or e.meta.usage_output > 0 or e.meta.usage_cache_read > 0 or e.meta.usage_cache_write > 0) {
                    try line.writer.writeAll(",\"usage\":{\"input\":");
                    try line.writer.print("{d}", .{e.meta.usage_input});
                    try line.writer.writeAll(",\"output\":");
                    try line.writer.print("{d}", .{e.meta.usage_output});
                    try line.writer.writeAll(",\"cacheRead\":");
                    try line.writer.print("{d}", .{e.meta.usage_cache_read});
                    try line.writer.writeAll(",\"cacheWrite\":");
                    try line.writer.print("{d}", .{e.meta.usage_cache_write});
                    if (e.meta.usage_cache_write_1h) |v| {
                        try line.writer.writeAll(",\"cacheWrite1h\":");
                        try line.writer.print("{d}", .{v});
                    }
                    if (e.meta.usage_reasoning) |v| {
                        try line.writer.writeAll(",\"reasoning\":");
                        try line.writer.print("{d}", .{v});
                    }
                    try line.writer.writeAll(",\"totalTokens\":");
                    try line.writer.print("{d}", .{e.meta.usage_total});
                    try line.writer.writeAll(",\"cost\":{\"input\":");
                    try line.writer.print("{d}", .{e.meta.cost_input});
                    try line.writer.writeAll(",\"output\":");
                    try line.writer.print("{d}", .{e.meta.cost_output});
                    try line.writer.writeAll(",\"cacheRead\":");
                    try line.writer.print("{d}", .{e.meta.cost_cache_read});
                    try line.writer.writeAll(",\"cacheWrite\":");
                    try line.writer.print("{d}", .{e.meta.cost_cache_write});
                    try line.writer.writeAll(",\"total\":");
                    try line.writer.print("{d}", .{e.meta.cost_total});
                    try line.writer.writeAll("}}");
                }
            } else if (std.mem.eql(u8, out_role, "toolResult")) {
                try line.writer.writeAll(",\"toolCallId\":");
                try std.json.Stringify.value(e.tool_call_id orelse "", .{}, &line.writer);
                try line.writer.writeAll(",\"toolName\":");
                try std.json.Stringify.value(e.tool_name orelse "tool", .{}, &line.writer);
                try line.writer.writeAll(",\"content\":[");
                var first_tool_content = true;
                if (e.content.len > 0 or (e.image_b64 == null and e.images.len == 0)) {
                    try line.writer.writeAll("{\"type\":\"text\",\"text\":");
                    try std.json.Stringify.value(e.content, .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_tool_content = false;
                }
                if (e.image_b64) |data| {
                    if (!first_tool_content) try line.writer.writeAll(",");
                    try line.writer.writeAll("{\"type\":\"image\",\"data\":");
                    try std.json.Stringify.value(data, .{}, &line.writer);
                    try line.writer.writeAll(",\"mimeType\":");
                    try std.json.Stringify.value(e.image_mime orelse "image/png", .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_tool_content = false;
                }
                for (e.images) |image| {
                    if (!first_tool_content) try line.writer.writeAll(",");
                    try line.writer.writeAll("{\"type\":\"image\",\"data\":");
                    try std.json.Stringify.value(image.data_b64, .{}, &line.writer);
                    try line.writer.writeAll(",\"mimeType\":");
                    try std.json.Stringify.value(image.mime_type, .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_tool_content = false;
                }
                try line.writer.writeAll("],\"isError\":");
                try line.writer.writeAll(if (e.tool_is_error) "true" else "false");
                if (e.added_tool_names.len > 0) {
                    try line.writer.writeAll(",\"addedToolNames\":[");
                    for (e.added_tool_names, 0..) |name, i| {
                        if (i > 0) try line.writer.writeAll(",");
                        try std.json.Stringify.value(name, .{}, &line.writer);
                    }
                    try line.writer.writeAll("]");
                }
                if (e.meta.usage_total > 0 or e.meta.usage_input > 0 or e.meta.usage_output > 0 or e.meta.usage_cache_read > 0 or e.meta.usage_cache_write > 0) {
                    try line.writer.writeAll(",\"usage\":{\"input\":");
                    try line.writer.print("{d}", .{e.meta.usage_input});
                    try line.writer.writeAll(",\"output\":");
                    try line.writer.print("{d}", .{e.meta.usage_output});
                    try line.writer.writeAll(",\"cacheRead\":");
                    try line.writer.print("{d}", .{e.meta.usage_cache_read});
                    try line.writer.writeAll(",\"cacheWrite\":");
                    try line.writer.print("{d}", .{e.meta.usage_cache_write});
                    if (e.meta.usage_cache_write_1h) |v| {
                        try line.writer.writeAll(",\"cacheWrite1h\":");
                        try line.writer.print("{d}", .{v});
                    }
                    if (e.meta.usage_reasoning) |v| {
                        try line.writer.writeAll(",\"reasoning\":");
                        try line.writer.print("{d}", .{v});
                    }
                    try line.writer.writeAll(",\"totalTokens\":");
                    try line.writer.print("{d}", .{e.meta.usage_total});
                    try line.writer.writeAll(",\"cost\":{\"input\":");
                    try line.writer.print("{d}", .{e.meta.cost_input});
                    try line.writer.writeAll(",\"output\":");
                    try line.writer.print("{d}", .{e.meta.cost_output});
                    try line.writer.writeAll(",\"cacheRead\":");
                    try line.writer.print("{d}", .{e.meta.cost_cache_read});
                    try line.writer.writeAll(",\"cacheWrite\":");
                    try line.writer.print("{d}", .{e.meta.cost_cache_write});
                    try line.writer.writeAll(",\"total\":");
                    try line.writer.print("{d}", .{e.meta.cost_total});
                    try line.writer.writeAll("}}");
                }
            } else if (std.mem.eql(u8, out_role, "user") and (e.image_b64 != null or e.images.len > 0)) {
                try line.writer.writeAll(",\"content\":[");
                var first_user_content = true;
                if (e.content.len > 0) {
                    try line.writer.writeAll("{\"type\":\"text\",\"text\":");
                    try std.json.Stringify.value(e.content, .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_user_content = false;
                }
                if (e.image_b64) |data| {
                    if (!first_user_content) try line.writer.writeAll(",");
                    try line.writer.writeAll("{\"type\":\"image\",\"data\":");
                    try std.json.Stringify.value(data, .{}, &line.writer);
                    try line.writer.writeAll(",\"mimeType\":");
                    try std.json.Stringify.value(e.image_mime orelse "image/png", .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_user_content = false;
                }
                for (e.images) |image| {
                    if (!first_user_content) try line.writer.writeAll(",");
                    try line.writer.writeAll("{\"type\":\"image\",\"data\":");
                    try std.json.Stringify.value(image.data_b64, .{}, &line.writer);
                    try line.writer.writeAll(",\"mimeType\":");
                    try std.json.Stringify.value(image.mime_type, .{}, &line.writer);
                    try line.writer.writeAll("}");
                    first_user_content = false;
                }
                try line.writer.writeAll("]");
            } else {
                try line.writer.writeAll(",\"content\":");
                try std.json.Stringify.value(e.content, .{}, &line.writer);
            }
            try line.writer.writeAll("}}");
            try out.appendSlice(gpa, line.written());
            try out.append(gpa, '\n');
        }

        return try out.toOwnedSlice(gpa);
    }

    pub fn save(self: *const Session, io: Io, path: []const u8) !void {
        const data = try self.toJsonl(self.gpa);
        defer self.gpa.free(data);
        var atomic = try std.Io.Dir.cwd().createFileAtomic(io, path, .{
            .make_path = true,
            .replace = true,
        });
        defer atomic.deinit(io);
        try atomic.file.writePositionalAll(io, data, 0);
        try atomic.replace(io);
    }

    pub fn load(gpa: std.mem.Allocator, io: Io, path: []const u8) !Session {
        const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(32 * 1024 * 1024));
        defer gpa.free(raw);

        if (raw.len > 0 and raw[raw.len - 1] != '\n') {
            // Match upstream append safety: only repair a file whose parsed
            // entries establish a real session header. The final fragment may
            // itself be malformed; separating it prevents the next record from
            // being concatenated into the same physical line.
            var probe = parseJsonl(gpa, raw) catch null;
            if (probe) |*valid_session| {
                defer valid_session.deinit();
                var file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
                defer file.close(io);
                try file.writePositionalAll(io, "\n", raw.len);
            }
        }

        var migrated = session_migration.migrateJsonl(gpa, raw) catch |err| switch (err) {
            // Preserve support for the pre-upstream Pi-Zig flat `header` format.
            session_migration.Error.InvalidSession => return try parseJsonl(gpa, raw),
            else => return err,
        };
        defer migrated.deinit(gpa);
        var result = try parseJsonl(gpa, migrated.jsonl);
        errdefer result.deinit();
        if (migrated.changed) try result.save(io, path);
        return result;
    }

    /// Parse JSONL: accepts upstream v3 (`type:session` + nested `message`) and legacy pi-zig
    /// flat `type:header` / top-level role+content lines.
    fn jsonNumber(value: ?std.json.Value) ?f64 {
        const v = value orelse return null;
        return switch (v) {
            .integer => |n| @floatFromInt(n),
            .float => |n| n,
            else => null,
        };
    }

    fn applyUsage(meta: *AssistantMeta, usage: std.json.Value) void {
        if (usage != .object) return;
        if (usage.object.get("input")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_input = @intCast(v.integer);
        };
        if (usage.object.get("output")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_output = @intCast(v.integer);
        };
        if (usage.object.get("cacheRead") orelse usage.object.get("cache_read")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_cache_read = @intCast(v.integer);
        };
        if (usage.object.get("cacheWrite") orelse usage.object.get("cache_write")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_cache_write = @intCast(v.integer);
        };
        if (usage.object.get("cacheWrite1h") orelse usage.object.get("cache_write_1h")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_cache_write_1h = @intCast(v.integer);
        };
        if (usage.object.get("reasoning")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_reasoning = @intCast(v.integer);
        };
        if (usage.object.get("totalTokens") orelse usage.object.get("total_tokens")) |v| if (v == .integer and v.integer >= 0) {
            meta.usage_total = @intCast(v.integer);
        };
        if (usage.object.get("cost")) |cost| if (cost == .object) {
            meta.cost_input = jsonNumber(cost.object.get("input")) orelse 0;
            meta.cost_output = jsonNumber(cost.object.get("output")) orelse 0;
            meta.cost_cache_read = jsonNumber(cost.object.get("cacheRead") orelse cost.object.get("cache_read")) orelse 0;
            meta.cost_cache_write = jsonNumber(cost.object.get("cacheWrite") orelse cost.object.get("cache_write")) orelse 0;
            meta.cost_total = jsonNumber(cost.object.get("total")) orelse 0;
        };
    }

    pub fn parseJsonl(gpa: std.mem.Allocator, raw: []const u8) !Session {
        var session: ?Session = null;
        var explicit_tip = false;
        errdefer if (session) |*s| s.deinit();

        var it = std.mem.splitScalar(u8, raw, '\n');
        while (it.next()) |line_raw| {
            const line = std.mem.trim(u8, line_raw, " \t\r");
            if (line.len == 0) continue;
            var parsed = std.json.parseFromSlice(std.json.Value, gpa, line, .{}) catch continue;
            defer parsed.deinit();
            if (parsed.value != .object) return error.InvalidSession;

            const typ = parsed.value.object.get("type") orelse return error.InvalidSession;
            if (typ != .string) return error.InvalidSession;

            // Header: upstream "session" or legacy "header"
            if (std.mem.eql(u8, typ.string, "session") or std.mem.eql(u8, typ.string, "header")) {
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                const cwd = parsed.value.object.get("cwd") orelse return error.InvalidSession;
                if (id != .string or cwd != .string) return error.InvalidSession;
                var s = try Session.init(gpa, id.string, cwd.string);
                if (parsed.value.object.get("timestamp")) |timestamp| {
                    if (timestamp == .string and timestamp.string.len > 0) {
                        const replacement = try gpa.dupe(u8, timestamp.string);
                        gpa.free(s.created_at);
                        s.created_at = replacement;
                    }
                }
                if (parsed.value.object.get("parentSession")) |parent| {
                    if (parent == .string and parent.string.len > 0) s.parent_session = try gpa.dupe(u8, parent.string);
                }
                if (parsed.value.object.get("name")) |nm| {
                    if (nm == .string) {
                        gpa.free(s.name);
                        s.name = try gpa.dupe(u8, nm.string);
                    }
                }
                if (parsed.value.object.get("next_seq")) |ns| {
                    if (ns == .integer) s.next_seq = @intCast(ns.integer);
                }
                if (parsed.value.object.get("tipId")) |tip| {
                    if (tip == .string) {
                        s.tip_id = try gpa.dupe(u8, tip.string);
                        explicit_tip = true;
                    }
                }
                session = s;
                continue;
            }

            // Preserve auxiliary/session-tree entries as first-class nodes.
            // Only compaction/branch-summary/custom-message entries participate
            // in model context; labels/custom metadata never become system text.
            if (entryTypeFromName(typ.string)) |entry_type| {
                const s = &(session orelse return error.InvalidSession);
                const id = parsed.value.object.get("id") orelse continue;
                if (id != .string) continue;
                var parent_id: ?[]const u8 = null;
                if (parsed.value.object.get("parentId")) |value| {
                    if (value == .string) parent_id = value.string;
                }
                const timestamp = if (parsed.value.object.get("timestamp")) |value|
                    (if (value == .string) value.string else "")
                else
                    "";

                var role: []const u8 = "aux";
                var content_owned = try gpa.dupe(u8, "");
                errdefer gpa.free(content_owned);
                var target_owned: ?[]const u8 = null;
                errdefer if (target_owned) |value| gpa.free(value);
                var label_owned: ?[]const u8 = null;
                errdefer if (label_owned) |value| gpa.free(value);
                var custom_type_owned: ?[]const u8 = null;
                errdefer if (custom_type_owned) |value| gpa.free(value);
                var data_json_owned: ?[]const u8 = null;
                errdefer if (data_json_owned) |value| gpa.free(value);
                var first_kept_owned: ?[]const u8 = null;
                errdefer if (first_kept_owned) |value| gpa.free(value);
                var tokens_before: u64 = 0;
                var from_hook = false;
                var display = false;
                var aux_meta: AssistantMeta = .{};
                if (parsed.value.object.get("usage")) |usage| applyUsage(&aux_meta, usage);

                switch (entry_type) {
                    .compaction => {
                        role = "system";
                        const summary = if (parsed.value.object.get("summary")) |value| (if (value == .string) value.string else "") else "";
                        gpa.free(content_owned);
                        content_owned = try gpa.dupe(u8, summary);
                        if (parsed.value.object.get("firstKeptEntryId")) |value| {
                            if (value == .string) first_kept_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("tokensBefore")) |value| {
                            if (value == .integer and value.integer >= 0) tokens_before = @intCast(value.integer);
                        }
                        if (parsed.value.object.get("details")) |value| data_json_owned = try stringifyJsonValue(gpa, value);
                        if (parsed.value.object.get("fromHook")) |value| {
                            if (value == .bool) from_hook = value.bool;
                        }
                    },
                    .branch_summary => {
                        role = "system";
                        const summary = if (parsed.value.object.get("summary")) |value| (if (value == .string) value.string else "") else "";
                        gpa.free(content_owned);
                        content_owned = try gpa.dupe(u8, summary);
                        if (parsed.value.object.get("fromId")) |value| {
                            if (value == .string) target_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("details")) |value| data_json_owned = try stringifyJsonValue(gpa, value);
                        if (parsed.value.object.get("fromHook")) |value| {
                            if (value == .bool) from_hook = value.bool;
                        }
                    },
                    .session_info => {
                        if (parsed.value.object.get("name")) |value| {
                            if (value == .string) {
                                gpa.free(s.name);
                                s.name = try gpa.dupe(u8, value.string);
                                gpa.free(content_owned);
                                content_owned = try gpa.dupe(u8, value.string);
                            }
                        }
                    },
                    .label => {
                        if (parsed.value.object.get("targetId")) |value| {
                            if (value == .string) target_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("label")) |value| {
                            if (value == .string) label_owned = try gpa.dupe(u8, value.string);
                        }
                    },
                    .custom => {
                        if (parsed.value.object.get("customType")) |value| {
                            if (value == .string) custom_type_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("data")) |value| data_json_owned = try stringifyJsonValue(gpa, value);
                    },
                    .custom_message => {
                        role = "user";
                        if (parsed.value.object.get("customType")) |value| {
                            if (value == .string) custom_type_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("display")) |value| {
                            if (value == .bool) display = value.bool;
                        }
                        if (parsed.value.object.get("content")) |value| {
                            gpa.free(content_owned);
                            content_owned = try extractLooseContentText(gpa, value);
                        }
                    },
                    .model_change => {
                        if (parsed.value.object.get("provider")) |value| {
                            if (value == .string) custom_type_owned = try gpa.dupe(u8, value.string);
                        }
                        if (parsed.value.object.get("modelId")) |value| {
                            if (value == .string) {
                                gpa.free(content_owned);
                                content_owned = try gpa.dupe(u8, value.string);
                            }
                        }
                    },
                    .thinking_level_change => {
                        if (parsed.value.object.get("thinkingLevel")) |value| {
                            if (value == .string) {
                                gpa.free(content_owned);
                                content_owned = try gpa.dupe(u8, value.string);
                            }
                        }
                    },
                    .message => unreachable,
                }

                try s.entries.append(gpa, .{
                    .entry_type = entry_type,
                    .id = try gpa.dupe(u8, id.string),
                    .parent_id = if (parent_id) |value| try gpa.dupe(u8, value) else null,
                    .role = try gpa.dupe(u8, role),
                    .content = content_owned,
                    .raw_json = try gpa.dupe(u8, line),
                    .target_id = target_owned,
                    .label = label_owned,
                    .custom_type = custom_type_owned,
                    .data_json = data_json_owned,
                    .first_kept_entry_id = first_kept_owned,
                    .tokens_before = tokens_before,
                    .from_hook = from_hook,
                    .display = display,
                    .timestamp = if (timestamp.len > 0) try gpa.dupe(u8, timestamp) else "",
                    .meta = aux_meta,
                });
                s.observeEntryId(id.string);
                if (!explicit_tip) {
                    if (s.tip_id) |tip| gpa.free(tip);
                    s.tip_id = try gpa.dupe(u8, id.string);
                }
                continue;
            }

            if (std.mem.eql(u8, typ.string, "message")) {
                const s = &(session orelse return error.InvalidSession);
                const id = parsed.value.object.get("id") orelse return error.InvalidSession;
                if (id != .string) return error.InvalidSession;

                var parent_id: ?[]const u8 = null;
                if (parsed.value.object.get("parentId")) |p| {
                    if (p == .string) parent_id = p.string;
                }

                // Nested upstream message object OR flat legacy fields
                var role_str: []const u8 = undefined;
                var content_owned: []u8 = undefined;
                var tool_call_id: ?[]const u8 = null;
                var tool_calls_json: ?[]u8 = null;
                var meta_thinking: ?[]u8 = null;
                var meta_thinking_signature: ?[]u8 = null;
                var meta_thinking_redacted = false;
                var image_b64_owned: ?[]u8 = null;
                var image_mime_owned: ?[]u8 = null;
                var extra_images_owned: []SessionImage = &.{};
                var bash_command_owned: ?[]u8 = null;
                var bash_output_owned: ?[]u8 = null;
                var bash_exit_code: ?i32 = null;
                var bash_cancelled = false;
                var bash_truncated = false;
                var bash_full_output_path_owned: ?[]u8 = null;
                var bash_exclude_from_context = false;
                var bash_timestamp_ms: i64 = 0;

                if (parsed.value.object.get("message")) |msg| {
                    if (msg != .object) return error.InvalidSession;
                    const role = msg.object.get("role") orelse return error.InvalidSession;
                    if (role != .string) return error.InvalidSession;
                    // Map toolResult → tool for internal loop. Bash execution remains
                    // a first-class role and receives a deterministic user-text projection.
                    role_str = if (std.mem.eql(u8, role.string, "toolResult")) "tool" else role.string;

                    if (std.mem.eql(u8, role_str, "bashExecution")) {
                        const command_value = msg.object.get("command") orelse return error.InvalidSession;
                        const output_value = msg.object.get("output") orelse return error.InvalidSession;
                        if (command_value != .string or output_value != .string) return error.InvalidSession;
                        bash_command_owned = try gpa.dupe(u8, command_value.string);
                        bash_output_owned = try gpa.dupe(u8, output_value.string);
                        if (msg.object.get("exitCode")) |value| {
                            if (value == .integer and value.integer >= std.math.minInt(i32) and value.integer <= std.math.maxInt(i32)) bash_exit_code = @intCast(value.integer);
                        }
                        if (msg.object.get("cancelled")) |value| if (value == .bool) {
                            bash_cancelled = value.bool;
                        };
                        if (msg.object.get("truncated")) |value| if (value == .bool) {
                            bash_truncated = value.bool;
                        };
                        if (msg.object.get("fullOutputPath")) |value| if (value == .string) {
                            bash_full_output_path_owned = try gpa.dupe(u8, value.string);
                        };
                        if (msg.object.get("excludeFromContext")) |value| if (value == .bool) {
                            bash_exclude_from_context = value.bool;
                        };
                        if (msg.object.get("timestamp")) |value| if (value == .integer) {
                            bash_timestamp_ms = value.integer;
                        };
                        content_owned = try formatBashExecutionText(gpa, command_value.string, output_value.string, bash_exit_code, bash_cancelled, bash_truncated, if (bash_full_output_path_owned) |path| path else null);
                    } else {
                        content_owned = try extractMessageText(gpa, msg);
                        if (try extractMessageImage(gpa, msg)) |image| {
                            image_b64_owned = image.data;
                            image_mime_owned = image.mime;
                        }
                        extra_images_owned = try extractMessageExtraImages(gpa, msg);
                    }
                    if (std.mem.eql(u8, role_str, "assistant")) {
                        meta_thinking = try extractMessageThinking(gpa, msg);
                        meta_thinking_signature = try extractMessageThinkingSignature(gpa, msg);
                        meta_thinking_redacted = extractMessageThinkingRedacted(msg);
                    }
                    if (msg.object.get("toolCallId")) |t| {
                        if (t == .string) tool_call_id = t.string;
                    }
                    if (msg.object.get("toolCalls")) |tc| {
                        var aw: std.Io.Writer.Allocating = .init(gpa);
                        defer aw.deinit();
                        try std.json.Stringify.value(tc, .{}, &aw.writer);
                        tool_calls_json = try aw.toOwnedSlice();
                    } else if (msg.object.get("content")) |c| {
                        // Extract toolCall blocks from content array
                        if (c == .array) {
                            var tcs: std.ArrayList(u8) = .empty;
                            defer tcs.deinit(gpa);
                            try tcs.appendSlice(gpa, "[");
                            var first = true;
                            for (c.array.items) |block| {
                                if (block != .object) continue;
                                const bt = block.object.get("type") orelse continue;
                                if (bt != .string) continue;
                                if (!std.mem.eql(u8, bt.string, "toolCall") and !std.mem.eql(u8, bt.string, "tool_use")) continue;
                                if (!first) try tcs.appendSlice(gpa, ",");
                                first = false;
                                const tid = if (block.object.get("id")) |v| (if (v == .string) v.string else "") else "";
                                const nm = if (block.object.get("name")) |v| (if (v == .string) v.string else "") else "";
                                // arguments may be object or string
                                var args_aw: std.Io.Writer.Allocating = .init(gpa);
                                defer args_aw.deinit();
                                if (block.object.get("arguments")) |a| {
                                    if (a == .string) {
                                        try args_aw.writer.writeAll(a.string);
                                    } else {
                                        try std.json.Stringify.value(a, .{}, &args_aw.writer);
                                    }
                                } else if (block.object.get("input")) |inp| {
                                    try std.json.Stringify.value(inp, .{}, &args_aw.writer);
                                } else {
                                    try args_aw.writer.writeAll("{}");
                                }
                                try tcs.appendSlice(gpa, "{\"id\":");
                                var tmp: std.Io.Writer.Allocating = .init(gpa);
                                defer tmp.deinit();
                                try std.json.Stringify.value(tid, .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, ",\"type\":\"function\",\"function\":{\"name\":");
                                tmp.deinit();
                                tmp = .init(gpa);
                                try std.json.Stringify.value(nm, .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, ",\"arguments\":");
                                tmp.deinit();
                                tmp = .init(gpa);
                                try std.json.Stringify.value(args_aw.written(), .{}, &tmp.writer);
                                try tcs.appendSlice(gpa, tmp.written());
                                try tcs.appendSlice(gpa, "}}");
                            }
                            try tcs.appendSlice(gpa, "]");
                            if (!first) {
                                tool_calls_json = try tcs.toOwnedSlice(gpa);
                            }
                        }
                    }
                } else {
                    // Legacy flat format
                    const role = parsed.value.object.get("role") orelse return error.InvalidSession;
                    const content = parsed.value.object.get("content") orelse return error.InvalidSession;
                    if (role != .string or content != .string) return error.InvalidSession;
                    role_str = role.string;
                    content_owned = try gpa.dupe(u8, content.string);
                    if (parsed.value.object.get("toolCallId")) |t| {
                        if (t == .string) tool_call_id = t.string;
                    }
                    if (parsed.value.object.get("toolCalls")) |tc| {
                        var aw: std.Io.Writer.Allocating = .init(gpa);
                        defer aw.deinit();
                        try std.json.Stringify.value(tc, .{}, &aw.writer);
                        tool_calls_json = try aw.toOwnedSlice();
                    }
                }
                defer gpa.free(content_owned);
                defer if (tool_calls_json) |t| gpa.free(t);
                defer if (meta_thinking) |t| gpa.free(t);
                defer if (meta_thinking_signature) |t| gpa.free(t);
                defer if (image_b64_owned) |data| gpa.free(data);
                defer if (image_mime_owned) |mime| gpa.free(mime);
                defer deinitSessionImages(gpa, extra_images_owned);
                defer if (bash_command_owned) |value| gpa.free(value);
                defer if (bash_output_owned) |value| gpa.free(value);
                defer if (bash_full_output_path_owned) |value| gpa.free(value);

                var meta: AssistantMeta = .{};
                if (meta_thinking) |t| meta.thinking = try gpa.dupe(u8, t);
                if (meta_thinking_signature) |t| meta.thinking_signature = try gpa.dupe(u8, t);
                meta.thinking_redacted = meta_thinking_redacted;
                // Nested message object carries assistant metadata
                if (parsed.value.object.get("message")) |msg| {
                    if (msg == .object) {
                        if (msg.object.get("provider")) |pv| {
                            if (pv == .string) meta.provider = try gpa.dupe(u8, pv.string);
                        }
                        if (msg.object.get("api")) |av| {
                            if (av == .string) meta.api = try gpa.dupe(u8, av.string);
                        }
                        if (msg.object.get("model")) |mv| {
                            if (mv == .string) meta.model = try gpa.dupe(u8, mv.string);
                        }
                        if (msg.object.get("responseId")) |rv| {
                            if (rv == .string) meta.response_id = try gpa.dupe(u8, rv.string);
                        }
                        if (msg.object.get("responseModel")) |rv| {
                            if (rv == .string) meta.response_model = try gpa.dupe(u8, rv.string);
                        }
                        if (msg.object.get("diagnostics")) |dv| {
                            if (dv == .array) {
                                var diagnostics_out: std.Io.Writer.Allocating = .init(gpa);
                                errdefer diagnostics_out.deinit();
                                try std.json.Stringify.value(dv, .{}, &diagnostics_out.writer);
                                meta.diagnostics_json = try diagnostics_out.toOwnedSlice();
                            }
                        }
                        if (msg.object.get("errorMessage")) |ev| {
                            if (ev == .string) meta.error_message = try gpa.dupe(u8, ev.string);
                        }
                        if (msg.object.get("rawStopReason")) |rv| {
                            if (rv == .string) meta.raw_stop_reason = try gpa.dupe(u8, rv.string);
                        }
                        if (msg.object.get("endTurn") orelse msg.object.get("end_turn")) |value| {
                            if (value == .bool) meta.end_turn = value.bool;
                        }
                        if (msg.object.get("stopReason")) |sr| {
                            if (sr == .string) meta.stop_reason = try gpa.dupe(u8, sr.string);
                        }
                        if (msg.object.get("usage")) |usage| applyUsage(&meta, usage);
                    }
                }

                var tool_name_owned: ?[]const u8 = null;
                if (parsed.value.object.get("message")) |msg2| {
                    if (msg2 == .object) {
                        if (msg2.object.get("toolName")) |tn| {
                            if (tn == .string) tool_name_owned = try gpa.dupe(u8, tn.string);
                        }
                    }
                }
                var tool_is_error = false;
                if (parsed.value.object.get("message")) |msg2| {
                    if (msg2 == .object) {
                        if (msg2.object.get("isError")) |ie| {
                            if (ie == .bool) tool_is_error = ie.bool;
                        }
                    }
                }
                var added_tool_names_owned: []const []const u8 = &.{};
                if (parsed.value.object.get("message")) |msg2| {
                    if (msg2 == .object) {
                        if (msg2.object.get("addedToolNames")) |names| {
                            if (names == .array and names.array.items.len > 0) {
                                var list: std.ArrayList([]const u8) = .empty;
                                errdefer {
                                    for (list.items) |name| gpa.free(name);
                                    list.deinit(gpa);
                                }
                                for (names.array.items) |name| if (name == .string) try list.append(gpa, try gpa.dupe(u8, name.string));
                                added_tool_names_owned = try list.toOwnedSlice(gpa);
                            }
                        }
                    }
                }
                var ts_owned: []const u8 = "";
                if (parsed.value.object.get("timestamp")) |tsv| {
                    if (tsv == .string) ts_owned = try gpa.dupe(u8, tsv.string);
                }
                try s.entries.append(gpa, .{
                    .id = try gpa.dupe(u8, id.string),
                    .parent_id = if (parent_id) |p| try gpa.dupe(u8, p) else null,
                    .role = try gpa.dupe(u8, role_str),
                    .content = try gpa.dupe(u8, content_owned),
                    .tool_call_id = if (tool_call_id) |t| try gpa.dupe(u8, t) else null,
                    .tool_calls_json = if (tool_calls_json) |t| try gpa.dupe(u8, t) else null,
                    .tool_name = tool_name_owned,
                    .tool_is_error = tool_is_error,
                    .image_b64 = if (image_b64_owned) |data| try gpa.dupe(u8, data) else null,
                    .image_mime = if (image_mime_owned) |mime| try gpa.dupe(u8, mime) else null,
                    .images = try cloneSessionImages(gpa, extra_images_owned),
                    .bash_command = if (bash_command_owned) |value| try gpa.dupe(u8, value) else null,
                    .bash_output = if (bash_output_owned) |value| try gpa.dupe(u8, value) else null,
                    .bash_exit_code = bash_exit_code,
                    .bash_cancelled = bash_cancelled,
                    .bash_truncated = bash_truncated,
                    .bash_full_output_path = if (bash_full_output_path_owned) |value| try gpa.dupe(u8, value) else null,
                    .bash_exclude_from_context = bash_exclude_from_context,
                    .bash_timestamp_ms = bash_timestamp_ms,
                    .added_tool_names = added_tool_names_owned,
                    .timestamp = ts_owned,
                    .meta = meta,
                });
                s.observeEntryId(id.string);
                if (!explicit_tip) {
                    if (s.tip_id) |t| gpa.free(t);
                    s.tip_id = try gpa.dupe(u8, id.string);
                }
            }
        }

        var result = session orelse return error.InvalidSession;
        if (explicit_tip) {
            if (result.tip_id) |tip| {
                if (result.getEntry(tip) == null) {
                    gpa.free(tip);
                    result.tip_id = if (result.entries.items.len > 0)
                        try gpa.dupe(u8, result.entries.items[result.entries.items.len - 1].id)
                    else
                        null;
                }
            }
        }
        return result;
    }

    /// Deep-copy session as a new fork with new id.
    pub fn fork(self: *const Session, gpa: std.mem.Allocator, new_id: []const u8) !Session {
        var s = try Session.init(gpa, new_id, self.cwd);
        errdefer s.deinit();
        try s.setName(self.name);
        s.next_seq = self.next_seq;
        for (self.entries.items) |e| {
            try s.entries.append(gpa, .{
                .entry_type = e.entry_type,
                .id = try gpa.dupe(u8, e.id),
                .parent_id = if (e.parent_id) |p| try gpa.dupe(u8, p) else null,
                .role = try gpa.dupe(u8, e.role),
                .content = try gpa.dupe(u8, e.content),
                .tool_call_id = if (e.tool_call_id) |t| try gpa.dupe(u8, t) else null,
                .tool_calls_json = if (e.tool_calls_json) |t| try gpa.dupe(u8, t) else null,
                .tool_name = if (e.tool_name) |t| try gpa.dupe(u8, t) else null,
                .tool_is_error = e.tool_is_error,
                .image_b64 = if (e.image_b64) |data| try gpa.dupe(u8, data) else null,
                .image_mime = if (e.image_mime) |mime| try gpa.dupe(u8, mime) else null,
                .images = try cloneSessionImages(gpa, e.images),
                .bash_command = if (e.bash_command) |value| try gpa.dupe(u8, value) else null,
                .bash_output = if (e.bash_output) |value| try gpa.dupe(u8, value) else null,
                .bash_exit_code = e.bash_exit_code,
                .bash_cancelled = e.bash_cancelled,
                .bash_truncated = e.bash_truncated,
                .bash_full_output_path = if (e.bash_full_output_path) |value| try gpa.dupe(u8, value) else null,
                .bash_exclude_from_context = e.bash_exclude_from_context,
                .bash_timestamp_ms = e.bash_timestamp_ms,
                .added_tool_names = if (e.added_tool_names.len > 0) blk: {
                    const names = try gpa.alloc([]const u8, e.added_tool_names.len);
                    for (e.added_tool_names, 0..) |name, i| names[i] = try gpa.dupe(u8, name);
                    break :blk names;
                } else &.{},
                .raw_json = if (e.raw_json) |value| try gpa.dupe(u8, value) else null,
                .target_id = if (e.target_id) |value| try gpa.dupe(u8, value) else null,
                .label = if (e.label) |value| try gpa.dupe(u8, value) else null,
                .custom_type = if (e.custom_type) |value| try gpa.dupe(u8, value) else null,
                .data_json = if (e.data_json) |value| try gpa.dupe(u8, value) else null,
                .first_kept_entry_id = if (e.first_kept_entry_id) |value| try gpa.dupe(u8, value) else null,
                .tokens_before = e.tokens_before,
                .from_hook = e.from_hook,
                .display = e.display,
                .timestamp = if (e.timestamp.len > 0) try gpa.dupe(u8, e.timestamp) else "",
                .meta = try e.meta.dupe(gpa),
            });
        }
        if (self.tip_id) |t| s.tip_id = try gpa.dupe(u8, t);
        return s;
    }

    /// Aggregate billing and message activity over every durable entry, not
    /// merely the active branch. This mirrors upstream `/session` semantics:
    /// compacted history remains part of the amount actually billed.
    pub fn stats(self: *const Session) SessionStats {
        var result: SessionStats = .{};
        for (self.entries.items) |entry| {
            if (entry.entry_type == .compaction or entry.entry_type == .branch_summary) {
                addUsageToStats(&result, entry.meta);
            }
            if (entry.entry_type != .message) continue;
            result.total_messages += 1;
            if (std.mem.eql(u8, entry.role, "user")) {
                result.user_messages += 1;
            } else if (std.mem.eql(u8, entry.role, "assistant")) {
                result.assistant_messages += 1;
                result.tool_calls += countToolCalls(self.gpa, entry.tool_calls_json);
                addUsageToStats(&result, entry.meta);
            } else if (std.mem.eql(u8, entry.role, "tool")) {
                result.tool_results += 1;
                addUsageToStats(&result, entry.meta);
            }
        }
        result.tokens.total = result.tokens.input + result.tokens.output + result.tokens.cache_read + result.tokens.cache_write;
        return result;
    }

    pub fn lastAssistantText(self: *const Session) ?[]const u8 {
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const e = self.entries.items[i];
            if (std.mem.eql(u8, e.role, "assistant") and e.content.len > 0) return e.content;
        }
        return null;
    }

    /// Tree summary for /tree (caller frees).
    pub fn treeSummary(self: *const Session, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        const tip = self.lastEntryId();
        for (self.entries.items) |e| {
            const mark: []const u8 = if (tip != null and std.mem.eql(u8, e.id, tip.?)) " *" else "";
            const line = try std.fmt.allocPrint(gpa, "{s} <- {s} [{s}] {s}{s}\n", .{
                e.id,
                e.parent_id orelse "null",
                e.role,
                truncate(e.content, 40),
                mark,
            });
            defer gpa.free(line);
            try out.appendSlice(gpa, line);
        }
        return try out.toOwnedSlice(gpa);
    }
};

fn addUsageToStats(result: *SessionStats, meta: AssistantMeta) void {
    result.tokens.input +|= meta.usage_input;
    result.tokens.output +|= meta.usage_output;
    result.tokens.cache_read +|= meta.usage_cache_read;
    result.tokens.cache_write +|= meta.usage_cache_write;
    result.cost += meta.cost_total;
}

fn countToolCalls(gpa: std.mem.Allocator, raw: ?[]const u8) usize {
    const value = raw orelse return 0;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, value, .{}) catch return 0;
    defer parsed.deinit();
    return if (parsed.value == .array) parsed.value.array.items.len else 0;
}

pub fn formatBashExecutionText(
    gpa: std.mem.Allocator,
    command: []const u8,
    output: []const u8,
    exit_code: ?i32,
    cancelled: bool,
    truncated: bool,
    full_output_path: ?[]const u8,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.print("Ran `{s}`\n", .{command});
    if (output.len > 0) {
        try out.writer.writeAll("```\n");
        try out.writer.writeAll(output);
        try out.writer.writeAll("\n```");
    } else {
        try out.writer.writeAll("(no output)");
    }
    if (cancelled) {
        try out.writer.writeAll("\n\n(command cancelled)");
    } else if (exit_code) |code| {
        if (code != 0) try out.writer.print("\n\nCommand exited with code {d}", .{code});
    }
    if (truncated) if (full_output_path) |path| {
        try out.writer.print("\n\n[Output truncated. Full output: {s}]", .{path});
    };
    return try out.toOwnedSlice();
}

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

/// Wall-clock Unix seconds when available; else monotonic fallback.
var timestamp_tick: i64 = 0;
const timestamp_anchor: i64 = 1_704_067_200; // 2024-01-01T00:00:00Z

fn wallishSeconds() i64 {
    if (builtin.os.tag == .windows) {
        // 100-ns intervals since 1601-01-01 UTC
        const ticks: i64 = std.os.windows.ntdll.RtlGetSystemTimePrecise();
        // Windows epoch → Unix epoch
        return @divTrunc(ticks - 11_644_473_600_000_0000, 10_000_000);
    }
    // POSIX: clock_gettime(CLOCK_REALTIME) via libc when linked
    if (builtin.link_libc) {
        const c = @cImport({
            @cInclude("time.h");
        });
        var ts: c.timespec = undefined;
        if (c.clock_gettime(c.CLOCK_REALTIME, &ts) == 0) {
            return @intCast(ts.tv_sec);
        }
    }
    // Fallback: process-local monotonic from 2024 anchor
    timestamp_tick += 1;
    return timestamp_anchor + timestamp_tick;
}

/// Public helper for protocol headers (JSON/RPC session line).
pub fn formatIsoNow(buf: *[32]u8) []const u8 {
    return formatIsoTimestamp(buf);
}

fn formatIsoTimestamp(buf: *[32]u8) []const u8 {
    const secs: i64 = wallishSeconds();
    const days = @divFloor(secs, 86400);
    var rem = @mod(secs, 86400);
    if (rem < 0) rem += 86400;
    const hour: u32 = @intCast(@divFloor(rem, 3600));
    const minute: u32 = @intCast(@divFloor(@mod(rem, 3600), 60));
    const second: u32 = @intCast(@mod(rem, 60));
    // Civil from days (Howard Hinnant algorithm)
    const z = days + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i64 = mp + (if (mp < 10) @as(i64, 3) else -9);
    y += @intFromBool(m <= 2);
    // Zig's signed decimal formatter includes an explicit sign when zero-filled;
    // civil dates are non-negative here, so format unsigned components.
    const year: u32 = @intCast(@max(y, 0));
    const month: u32 = @intCast(@max(m, 0));
    const day: u32 = @intCast(@max(d, 0));
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.000Z", .{
        year, month, day, hour, minute, second,
    }) catch "2024-01-01T00:00:00.000Z";
}

/// Extract plain text from upstream message.content (string or content-block array).
fn extractMessageThinking(gpa: std.mem.Allocator, msg: std.json.Value) !?[]u8 {
    const content = msg.object.get("content") orelse return null;
    if (content != .array) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (content.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "thinking")) continue;
        const value = block.object.get("thinking") orelse block.object.get("text");
        const redacted = if (block.object.get("redacted")) |item| item == .bool and item.bool else false;
        const text = if (value) |item| if (item == .string) item.string else "" else "";
        if (text.len == 0 and !redacted) continue;
        if (out.items.len > 0) try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, if (redacted and text.len == 0) "[Reasoning redacted]" else text);
    }
    if (out.items.len == 0) {
        out.deinit(gpa);
        return null;
    }
    return try out.toOwnedSlice(gpa);
}

fn extractMessageThinkingRedacted(msg: std.json.Value) bool {
    const content = msg.object.get("content") orelse return false;
    if (content != .array) return false;
    for (content.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "thinking")) continue;
        if (block.object.get("redacted")) |value| if (value == .bool and value.bool) return true;
    }
    return false;
}

fn extractMessageThinkingSignature(gpa: std.mem.Allocator, msg: std.json.Value) !?[]u8 {
    const content = msg.object.get("content") orelse return null;
    if (content != .array) return null;
    for (content.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "thinking")) continue;
        const value = block.object.get("thinkingSignature") orelse block.object.get("signature") orelse continue;
        if (value == .string) return try gpa.dupe(u8, value.string);
    }
    return null;
}

const MessageImage = struct {
    data: []u8,
    mime: []u8,
};

fn extractMessageImage(gpa: std.mem.Allocator, msg: std.json.Value) !?MessageImage {
    const content = msg.object.get("content") orelse return null;
    if (content != .array) return null;
    for (content.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "image")) continue;
        const data = block.object.get("data") orelse continue;
        if (data != .string) continue;
        const mime_value = block.object.get("mimeType") orelse block.object.get("mime_type") orelse block.object.get("mime");
        const mime = if (mime_value) |value| if (value == .string) value.string else "image/png" else "image/png";
        return .{ .data = try gpa.dupe(u8, data.string), .mime = try gpa.dupe(u8, mime) };
    }
    return null;
}

fn extractMessageExtraImages(gpa: std.mem.Allocator, msg: std.json.Value) ![]SessionImage {
    const content = msg.object.get("content") orelse return &.{};
    if (content != .array) return &.{};
    var images: std.ArrayList(SessionImage) = .empty;
    errdefer {
        for (images.items) |image| {
            gpa.free(image.data_b64);
            gpa.free(image.mime_type);
        }
        images.deinit(gpa);
    }
    var seen_first = false;
    for (content.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "image")) continue;
        const data = block.object.get("data") orelse continue;
        if (data != .string) continue;
        if (!seen_first) {
            seen_first = true;
            continue;
        }
        const mime_value = block.object.get("mimeType") orelse block.object.get("mime_type") orelse block.object.get("mime");
        const mime = if (mime_value) |value| if (value == .string) value.string else "image/png" else "image/png";
        try images.append(gpa, .{
            .data_b64 = try gpa.dupe(u8, data.string),
            .mime_type = try gpa.dupe(u8, mime),
        });
    }
    return try images.toOwnedSlice(gpa);
}

fn extractMessageText(gpa: std.mem.Allocator, msg: std.json.Value) ![]u8 {
    const content = msg.object.get("content") orelse return try gpa.dupe(u8, "");
    if (content == .string) return try gpa.dupe(u8, content.string);
    if (content == .array) {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        for (content.array.items) |block| {
            if (block != .object) continue;
            const bt = block.object.get("type") orelse continue;
            if (bt != .string) continue;
            if (std.mem.eql(u8, bt.string, "text")) {
                if (block.object.get("text")) |tx| {
                    if (tx == .string) {
                        if (out.items.len > 0) try out.append(gpa, '\n');
                        try out.appendSlice(gpa, tx.string);
                    }
                }
            }
        }
        return try out.toOwnedSlice(gpa);
    }
    return try gpa.dupe(u8, "");
}

fn entryTypeFromName(name: []const u8) ?EntryType {
    if (std.mem.eql(u8, name, "model_change")) return .model_change;
    if (std.mem.eql(u8, name, "thinking_level_change")) return .thinking_level_change;
    if (std.mem.eql(u8, name, "compaction")) return .compaction;
    if (std.mem.eql(u8, name, "branch_summary")) return .branch_summary;
    if (std.mem.eql(u8, name, "session_info")) return .session_info;
    if (std.mem.eql(u8, name, "label")) return .label;
    if (std.mem.eql(u8, name, "custom")) return .custom;
    if (std.mem.eql(u8, name, "custom_message")) return .custom_message;
    return null;
}

fn entryTypeName(entry_type: EntryType) []const u8 {
    return switch (entry_type) {
        .message => "message",
        .compaction => "compaction",
        .branch_summary => "branch_summary",
        .session_info => "session_info",
        .label => "label",
        .custom => "custom",
        .custom_message => "custom_message",
        .model_change => "model_change",
        .thinking_level_change => "thinking_level_change",
    };
}

fn serializeAuxEntry(gpa: std.mem.Allocator, entry: SessionEntry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"type\":");
    try std.json.Stringify.value(entryTypeName(entry.entry_type), .{}, &out.writer);
    try out.writer.writeAll(",\"id\":");
    try std.json.Stringify.value(entry.id, .{}, &out.writer);
    try out.writer.writeAll(",\"parentId\":");
    if (entry.parent_id) |parent| try std.json.Stringify.value(parent, .{}, &out.writer) else try out.writer.writeAll("null");
    try out.writer.writeAll(",\"timestamp\":");
    if (entry.timestamp.len > 0) {
        try std.json.Stringify.value(entry.timestamp, .{}, &out.writer);
    } else {
        var ts_buf: [32]u8 = undefined;
        try std.json.Stringify.value(formatIsoTimestamp(&ts_buf), .{}, &out.writer);
    }
    switch (entry.entry_type) {
        .session_info => {
            try out.writer.writeAll(",\"name\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
        },
        .label => {
            try out.writer.writeAll(",\"targetId\":");
            try std.json.Stringify.value(entry.target_id orelse "", .{}, &out.writer);
            try out.writer.writeAll(",\"label\":");
            if (entry.label) |label| try std.json.Stringify.value(label, .{}, &out.writer) else try out.writer.writeAll("null");
        },
        .custom => {
            try out.writer.writeAll(",\"customType\":");
            try std.json.Stringify.value(entry.custom_type orelse "", .{}, &out.writer);
            try out.writer.writeAll(",\"data\":");
            if (entry.data_json) |raw| try out.writer.writeAll(raw) else try out.writer.writeAll("null");
        },
        .custom_message => {
            try out.writer.writeAll(",\"customType\":");
            try std.json.Stringify.value(entry.custom_type orelse "", .{}, &out.writer);
            try out.writer.writeAll(",\"content\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
            try out.writer.writeAll(",\"display\":");
            try out.writer.writeAll(if (entry.display) "true" else "false");
        },
        .compaction => {
            try out.writer.writeAll(",\"summary\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
            try out.writer.writeAll(",\"firstKeptEntryId\":");
            try std.json.Stringify.value(entry.first_kept_entry_id orelse "", .{}, &out.writer);
            try out.writer.print(",\"tokensBefore\":{d}", .{entry.tokens_before});
            if (entry.data_json) |raw| {
                try out.writer.writeAll(",\"details\":");
                try out.writer.writeAll(raw);
            }
            if (entry.from_hook) try out.writer.writeAll(",\"fromHook\":true");
            try writeUsageObject(&out.writer, entry.meta);
        },
        .branch_summary => {
            try out.writer.writeAll(",\"fromId\":");
            try std.json.Stringify.value(entry.target_id orelse entry.parent_id orelse "root", .{}, &out.writer);
            try out.writer.writeAll(",\"summary\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
            if (entry.data_json) |raw| {
                try out.writer.writeAll(",\"details\":");
                try out.writer.writeAll(raw);
            }
            if (entry.from_hook) try out.writer.writeAll(",\"fromHook\":true");
            try writeUsageObject(&out.writer, entry.meta);
        },
        .model_change => {
            try out.writer.writeAll(",\"provider\":");
            try std.json.Stringify.value(entry.custom_type orelse "", .{}, &out.writer);
            try out.writer.writeAll(",\"modelId\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
        },
        .thinking_level_change => {
            try out.writer.writeAll(",\"thinkingLevel\":");
            try std.json.Stringify.value(entry.content, .{}, &out.writer);
        },
        .message => return error.NotAuxiliaryEntry,
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn writeUsageObject(writer: *std.Io.Writer, meta: AssistantMeta) !void {
    if (meta.usage_total == 0 and meta.usage_input == 0 and meta.usage_output == 0 and
        meta.usage_cache_read == 0 and meta.usage_cache_write == 0 and
        meta.usage_cache_write_1h == null and meta.usage_reasoning == null and
        meta.cost_input == 0 and meta.cost_output == 0 and meta.cost_cache_read == 0 and
        meta.cost_cache_write == 0 and meta.cost_total == 0) return;

    try writer.writeAll(",\"usage\":{\"input\":");
    try writer.print("{d}", .{meta.usage_input});
    try writer.writeAll(",\"output\":");
    try writer.print("{d}", .{meta.usage_output});
    try writer.writeAll(",\"cacheRead\":");
    try writer.print("{d}", .{meta.usage_cache_read});
    try writer.writeAll(",\"cacheWrite\":");
    try writer.print("{d}", .{meta.usage_cache_write});
    if (meta.usage_cache_write_1h) |value| {
        try writer.writeAll(",\"cacheWrite1h\":");
        try writer.print("{d}", .{value});
    }
    if (meta.usage_reasoning) |value| {
        try writer.writeAll(",\"reasoning\":");
        try writer.print("{d}", .{value});
    }
    try writer.writeAll(",\"totalTokens\":");
    try writer.print("{d}", .{meta.usage_total});
    try writer.writeAll(",\"cost\":{\"input\":");
    try writer.print("{d}", .{meta.cost_input});
    try writer.writeAll(",\"output\":");
    try writer.print("{d}", .{meta.cost_output});
    try writer.writeAll(",\"cacheRead\":");
    try writer.print("{d}", .{meta.cost_cache_read});
    try writer.writeAll(",\"cacheWrite\":");
    try writer.print("{d}", .{meta.cost_cache_write});
    try writer.writeAll(",\"total\":");
    try writer.print("{d}", .{meta.cost_total});
    try writer.writeAll("}}");
}

fn stringifyJsonValue(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return try out.toOwnedSlice();
}

fn validateJsonValue(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return error.InvalidCustomEntry;
    defer parsed.deinit();
}

fn sanitizeSingleLine(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var pending_space = false;
    for (raw) |c| {
        if (c == '\r' or c == '\n') {
            pending_space = out.items.len > 0;
            continue;
        }
        if (pending_space) {
            if (c != ' ' and c != '\t') try out.append(gpa, ' ');
            pending_space = false;
        }
        try out.append(gpa, c);
    }
    const trimmed = std.mem.trim(u8, out.items, " \t\r\n");
    const result = try gpa.dupe(u8, trimmed);
    out.deinit(gpa);
    return result;
}

fn extractLooseContentText(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    if (value == .string) return try gpa.dupe(u8, value.string);
    if (value != .array) return try gpa.dupe(u8, "");
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (value.array.items) |block| {
        if (block != .object) continue;
        const typ = block.object.get("type") orelse continue;
        if (typ != .string or !std.mem.eql(u8, typ.string, "text")) continue;
        const text = block.object.get("text") orelse continue;
        if (text != .string) continue;
        if (out.items.len > 0) try out.append(gpa, '\n');
        try out.appendSlice(gpa, text.string);
    }
    return try out.toOwnedSlice(gpa);
}

fn fallbackSessionInfo(
    gpa: std.mem.Allocator,
    path: []const u8,
    file_name: []const u8,
    mtime_ns: i96,
) !SessionInfo {
    const stem = if (std.mem.endsWith(u8, file_name, ".jsonl")) file_name[0 .. file_name.len - ".jsonl".len] else file_name;
    const path_owned = try gpa.dupe(u8, path);
    errdefer gpa.free(path_owned);
    const id_owned = try gpa.dupe(u8, stem);
    errdefer gpa.free(id_owned);
    const cwd_owned = try gpa.dupe(u8, "");
    errdefer gpa.free(cwd_owned);
    const name_owned = try gpa.dupe(u8, "");
    errdefer gpa.free(name_owned);
    const created_owned = try gpa.dupe(u8, "");
    errdefer gpa.free(created_owned);
    const first_owned = try gpa.dupe(u8, "(no messages)");
    errdefer gpa.free(first_owned);
    const all_owned = try gpa.dupe(u8, "");
    errdefer gpa.free(all_owned);
    return .{
        .path = path_owned,
        .id = id_owned,
        .cwd = cwd_owned,
        .name = name_owned,
        .created_at = created_owned,
        .first_message = first_owned,
        .all_messages_text = all_owned,
        .valid = false,
        .mtime_ns = mtime_ns,
    };
}

fn buildSessionInfo(
    gpa: std.mem.Allocator,
    path: []const u8,
    file_name: []const u8,
    mtime_ns: i96,
    raw: []const u8,
) !SessionInfo {
    var normalized: ?session_migration.Result = null;
    defer if (normalized) |*value| value.deinit(gpa);
    var unsupported = false;
    if (session_migration.migrateJsonl(gpa, raw)) |result| {
        normalized = result;
    } else |err| switch (err) {
        session_migration.Error.InvalidSession => {},
        else => unsupported = true,
    }
    if (unsupported) return fallbackSessionInfo(gpa, path, file_name, mtime_ns);

    const payload = if (normalized) |value| value.jsonl else raw;
    var session = Session.parseJsonl(gpa, payload) catch return fallbackSessionInfo(gpa, path, file_name, mtime_ns);
    defer session.deinit();

    var message_count: usize = 0;
    var first_message: ?[]const u8 = null;
    var all_messages: std.ArrayList(u8) = .empty;
    defer all_messages.deinit(gpa);
    for (session.entries.items) |entry| {
        if (entry.entry_type != .message) continue;
        message_count += 1;
        const searchable = std.mem.eql(u8, entry.role, "user") or std.mem.eql(u8, entry.role, "assistant");
        if (!searchable or entry.content.len == 0) continue;
        if (all_messages.items.len > 0) try all_messages.append(gpa, ' ');
        try all_messages.appendSlice(gpa, entry.content);
        if (first_message == null and std.mem.eql(u8, entry.role, "user")) first_message = entry.content;
    }

    const path_owned = try gpa.dupe(u8, path);
    errdefer gpa.free(path_owned);
    const id_owned = try gpa.dupe(u8, session.id);
    errdefer gpa.free(id_owned);
    const cwd_owned = try gpa.dupe(u8, session.cwd);
    errdefer gpa.free(cwd_owned);
    const name_owned = try gpa.dupe(u8, session.name);
    errdefer gpa.free(name_owned);
    const parent_owned = if (session.parent_session) |parent| try gpa.dupe(u8, parent) else null;
    errdefer if (parent_owned) |parent| gpa.free(parent);
    const created_owned = try gpa.dupe(u8, session.created_at);
    errdefer gpa.free(created_owned);
    const first_owned = try gpa.dupe(u8, first_message orelse "(no messages)");
    errdefer gpa.free(first_owned);
    const all_owned = try gpa.dupe(u8, all_messages.items);
    errdefer gpa.free(all_owned);

    return .{
        .path = path_owned,
        .id = id_owned,
        .cwd = cwd_owned,
        .name = name_owned,
        .parent_session_path = parent_owned,
        .created_at = created_owned,
        .message_count = message_count,
        .first_message = first_owned,
        .all_messages_text = all_owned,
        .valid = true,
        .mtime_ns = mtime_ns,
    };
}

/// List session JSONL files in a directory. Discovery is best-effort: corrupt
/// files remain visible (with `valid=false`) so `sessions doctor` can report
/// them, while valid files receive the full upstream SessionInfo projection.
pub fn listSessions(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) ![]SessionInfo {
    var list: std.ArrayList(SessionInfo) = .empty;
    errdefer {
        for (list.items) |*item| item.deinit(gpa);
        list.deinit(gpa);
    }

    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch {
        return try list.toOwnedSlice(gpa);
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".jsonl")) continue;
        const full = try std.fs.path.join(gpa, &.{ dir_path, entry.name });
        defer gpa.free(full);
        const file_stat = std.Io.Dir.cwd().statFile(io, full, .{}) catch continue;
        const raw = std.Io.Dir.cwd().readFileAlloc(io, full, gpa, .limited(32 * 1024 * 1024)) catch {
            try list.append(gpa, try fallbackSessionInfo(gpa, full, entry.name, file_stat.mtime.nanoseconds));
            continue;
        };
        defer gpa.free(raw);
        try list.append(gpa, try buildSessionInfo(gpa, full, entry.name, file_stat.mtime.nanoseconds, raw));
    }
    std.mem.sort(SessionInfo, list.items, {}, struct {
        fn lessThan(_: void, lhs: SessionInfo, rhs: SessionInfo) bool {
            if (lhs.mtime_ns != rhs.mtime_ns) return lhs.mtime_ns > rhs.mtime_ns;
            return std.mem.lessThan(u8, lhs.path, rhs.path);
        }
    }.lessThan);
    return try list.toOwnedSlice(gpa);
}

/// Return the truly most recently modified session path.
fn sessionInfoNewestFirst(_: void, lhs: SessionInfo, rhs: SessionInfo) bool {
    if (lhs.mtime_ns != rhs.mtime_ns) return lhs.mtime_ns > rhs.mtime_ns;
    return std.mem.lessThan(u8, lhs.path, rhs.path);
}

fn skipRecursiveSessionDir(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, "node_modules") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "__pycache__") or
        std.mem.startsWith(u8, name, ".zig-cache") or
        std.mem.startsWith(u8, name, ".zig-global-cache");
}

fn appendSessionsRecursive(
    gpa: std.mem.Allocator,
    io: Io,
    root: []const u8,
    depth: usize,
    out: *std.ArrayList(SessionInfo),
) !void {
    if (depth > 12) return;

    const local = try listSessions(gpa, io, root);
    defer gpa.free(local);
    try out.ensureUnusedCapacity(gpa, local.len);
    for (local) |item| out.appendAssumeCapacity(item);

    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .directory or skipRecursiveSessionDir(entry.name)) continue;
        const child = try std.fs.path.join(gpa, &.{ root, entry.name });
        defer gpa.free(child);
        try appendSessionsRecursive(gpa, io, child, depth + 1, out);
    }
}

/// Discover sessions below a root containing multiple encoded working-directory
/// stores. The traversal is deliberately bounded and ignores build/dependency
/// trees so `--resume` can offer "all sessions" without turning into a general
/// filesystem crawler. Corrupt JSONL files remain visible exactly as they do in
/// `listSessions`.
pub fn listSessionsRecursive(gpa: std.mem.Allocator, io: Io, root: []const u8) ![]SessionInfo {
    var out: std.ArrayList(SessionInfo) = .empty;
    errdefer {
        for (out.items) |*item| item.deinit(gpa);
        out.deinit(gpa);
    }
    try appendSessionsRecursive(gpa, io, root, 0, &out);
    std.mem.sort(SessionInfo, out.items, {}, sessionInfoNewestFirst);
    return try out.toOwnedSlice(gpa);
}

pub fn mostRecentSessionPath(gpa: std.mem.Allocator, io: Io, dir_path: []const u8) !?[]u8 {
    const sessions = try listSessions(gpa, io, dir_path);
    defer {
        for (sessions) |*s| {
            var mut = s.*;
            mut.deinit(gpa);
        }
        gpa.free(sessions);
    }
    if (sessions.len == 0) return null;
    return try gpa.dupe(u8, sessions[0].path);
}

/// Validate an upstream-compatible explicit session id. IDs are portable file
/// components: ASCII alphanumeric at both ends, with `.`, `_`, and `-` allowed
/// only in the interior.
pub fn validateSessionId(id: []const u8) !void {
    if (id.len == 0 or !std.ascii.isAlphanumeric(id[0]) or !std.ascii.isAlphanumeric(id[id.len - 1])) {
        return error.InvalidSessionId;
    }
    for (id) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '.' and c != '_' and c != '-') return error.InvalidSessionId;
    }
}

/// Find an exact session id in the project session directory. The returned
/// path is independently owned and survives cleanup of the listing metadata.
pub fn findExactSessionPath(gpa: std.mem.Allocator, io: Io, session_dir: []const u8, id: []const u8) !?[]u8 {
    const sessions = try listSessions(gpa, io, session_dir);
    defer {
        for (sessions) |*info| info.deinit(gpa);
        gpa.free(sessions);
    }
    for (sessions) |info| {
        if (std.mem.eql(u8, info.id, id)) return try gpa.dupe(u8, info.path);
    }
    return null;
}

pub fn newSessionPath(gpa: std.mem.Allocator, session_dir: []const u8, id: []const u8) ![]u8 {
    const file = try std.fmt.allocPrint(gpa, "{s}.jsonl", .{id});
    defer gpa.free(file);
    return try std.fs.path.join(gpa, &.{ session_dir, file });
}

var session_id_counter: u64 = 1;

pub fn generateSessionId(gpa: std.mem.Allocator) ![]u8 {
    // Unique-enough id without depending on wall clock API.
    const n = session_id_counter;
    session_id_counter +%= 1;
    const mix: u64 = n *% 0x9e3779b97f4a7c15;
    return try std.fmt.allocPrint(gpa, "s{d}-{x}", .{ n, mix });
}

test "ISO timestamps use unsigned zero-padded civil fields" {
    var buf: [32]u8 = undefined;
    const timestamp = formatIsoNow(&buf);
    try std.testing.expectEqual(@as(usize, 24), timestamp.len);
    try std.testing.expect(timestamp[4] == '-' and timestamp[7] == '-' and timestamp[10] == 'T');
    try std.testing.expect(timestamp[0] >= '0' and timestamp[0] <= '9');
    try std.testing.expect(std.mem.indexOfScalar(u8, timestamp, '+') == null);
}

test "session save then load roundtrip" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "session.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "sess-1", tmp_path);
    defer s.deinit();
    try s.setName("test");

    const user_id = try s.appendMessage(null, "user", "hello", null, null);
    _ = try s.appendMessage(user_id, "assistant", "hi there", null, null);

    try s.save(io, session_path);

    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();

    try std.testing.expectEqualStrings("sess-1", loaded.id);
    try std.testing.expectEqualStrings("test", loaded.name);
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expectEqualStrings("user", loaded.entries.items[0].role);
    try std.testing.expectEqualStrings("hello", loaded.entries.items[0].content);
    try std.testing.expectEqualStrings("assistant", loaded.entries.items[1].role);
    try std.testing.expectEqualStrings(user_id, loaded.entries.items[1].parent_id.?);
}

test "per-entry timestamps persist across save/load" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "ts.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "ts-1", tmp_path);
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "with-ts", null, null);
    try std.testing.expect(s.entries.items[0].timestamp.len > 0);
    const ts_before = try gpa.dupe(u8, s.entries.items[0].timestamp);
    defer gpa.free(ts_before);

    try s.save(io, session_path);
    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.items.len);
    try std.testing.expect(loaded.entries.items[0].timestamp.len > 0);
    try std.testing.expectEqualStrings(ts_before, loaded.entries.items[0].timestamp);
}

test "session fork copies branch" {
    const gpa = std.testing.allocator;
    var s = try Session.init(gpa, "orig", "/tmp");
    defer s.deinit();
    const u = try s.appendMessage(null, "user", "hi", null, null);
    _ = try s.appendMessage(u, "assistant", "yo", null, null);

    var f = try s.fork(gpa, "forked");
    defer f.deinit();
    try std.testing.expectEqualStrings("forked", f.id);
    try std.testing.expectEqual(@as(usize, 2), f.entries.items.len);
    try std.testing.expectEqualStrings("hi", f.entries.items[0].content);
}

test "assistant metadata round-trip provider model stopReason usage" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const tmp_path = path_buf[0..n];
    const session_path = try std.fs.path.join(gpa, &.{ tmp_path, "meta.jsonl" });
    defer gpa.free(session_path);

    var s = try Session.init(gpa, "meta-sess", tmp_path);
    defer s.deinit();
    const uid = try s.appendMessage(null, "user", "go", null, null);
    _ = try s.appendMessageMeta(uid, "assistant", "calling tool", null,
        \\[{"id":"c1","type":"function","function":{"name":"ls","arguments":"{}"}}]
    , null, .{
        .provider = "openai",
        .api = "openai-responses",
        .model = "gpt-4o-mini",
        .response_id = "resp_tool_1",
        .response_model = "routed/model",
        .raw_stop_reason = "tool_calls",
        .end_turn = true,
        .stop_reason = "toolUse",
        .usage_input = 12,
        .usage_output = 4,
        .usage_total = 16,
    });
    const tip = s.lastEntryId().?;
    _ = try s.appendMessageMeta(tip, "assistant", "all done", null, null, null, .{
        .provider = "openai",
        .model = "gpt-4o-mini",
        .stop_reason = "stop",
        .usage_input = 20,
        .usage_output = 8,
        .usage_total = 28,
    });

    try s.save(io, session_path);
    var loaded = try Session.load(gpa, io, session_path);
    defer loaded.deinit();

    try std.testing.expectEqual(@as(usize, 3), loaded.entries.items.len);
    const a1 = loaded.entries.items[1];
    try std.testing.expectEqualStrings("assistant", a1.role);
    try std.testing.expectEqualStrings("openai", a1.meta.provider);
    try std.testing.expectEqualStrings("openai-responses", a1.meta.api);
    try std.testing.expectEqualStrings("gpt-4o-mini", a1.meta.model);
    try std.testing.expectEqualStrings("toolUse", a1.meta.stop_reason);
    try std.testing.expectEqualStrings("resp_tool_1", a1.meta.response_id);
    try std.testing.expectEqualStrings("routed/model", a1.meta.response_model);
    try std.testing.expectEqualStrings("tool_calls", a1.meta.raw_stop_reason);
    try std.testing.expectEqual(true, a1.meta.end_turn.?);
    try std.testing.expectEqual(@as(u64, 12), a1.meta.usage_input);
    try std.testing.expectEqual(@as(u64, 16), a1.meta.usage_total);
    const a2 = loaded.entries.items[2];
    try std.testing.expectEqualStrings("stop", a2.meta.stop_reason);
    try std.testing.expectEqual(@as(u64, 28), a2.meta.usage_total);

    // Also assert serialized JSON contains fields
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, session_path, gpa, .limited(1024 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"provider\":\"openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"api\":\"openai-responses\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"stopReason\":\"toolUse\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"responseId\":\"resp_tool_1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"responseModel\":\"routed/model\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"rawStopReason\":\"tool_calls\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"endTurn\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"totalTokens\":16") != null);
}

test "upstream v3 session fixture loads branch tip and roles" {
    const gpa = std.testing.allocator;
    // Shaped from packages/coding-agent/docs/session-format.md (version 3 nested message)
    const fixture =
        \\{"type":"session","version":3,"id":"uuid-upstream-1","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/path/to/project"}
        \\{"type":"message","id":"a1b2c3d4","parentId":null,"timestamp":"2024-12-03T14:00:01.000Z","message":{"role":"user","content":"Hello"}}
        \\{"type":"message","id":"b2c3d4e5","parentId":"a1b2c3d4","timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}],"provider":"anthropic","model":"claude","stopReason":"stop"}}
        \\{"type":"message","id":"c3d4e5f6","parentId":"b2c3d4e5","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"toolResult","toolCallId":"call_123","toolName":"bash","content":[{"type":"text","text":"output"}],"isError":false}}
        \\{"type":"model_change","id":"d4e5f6g7","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:05:00.000Z","provider":"openai","modelId":"gpt-4o"}
        \\{"type":"session_info","id":"e5f6g7h8","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:06:00.000Z","name":"Refactor auth"}
        \\{"type":"compaction","id":"f6g7h8i9","parentId":"c3d4e5f6","timestamp":"2024-12-03T14:10:00.000Z","summary":"User discussed Hello/Hi","tokensBefore":50000}
        \\
    ;
    var s = try Session.parseJsonl(gpa, fixture);
    defer s.deinit();

    try std.testing.expectEqualStrings("uuid-upstream-1", s.id);
    try std.testing.expectEqualStrings("/path/to/project", s.cwd);
    try std.testing.expectEqualStrings("Refactor auth", s.name);
    // messages + compaction synthetic entry
    try std.testing.expect(s.entries.items.len >= 3);
    try std.testing.expectEqualStrings("user", s.entries.items[0].role);
    try std.testing.expectEqualStrings("Hello", s.entries.items[0].content);
    try std.testing.expectEqualStrings("assistant", s.entries.items[1].role);
    try std.testing.expectEqualStrings("Hi!", s.entries.items[1].content);
    try std.testing.expectEqualStrings("a1b2c3d4", s.entries.items[1].parent_id.?);
    try std.testing.expectEqualStrings("tool", s.entries.items[2].role);
    try std.testing.expectEqualStrings("call_123", s.entries.items[2].tool_call_id.?);
    try std.testing.expectEqualStrings("output", s.entries.items[2].content);

    // Active tip after compaction
    try std.testing.expect(s.tip_id != null);
    try std.testing.expectEqualStrings("f6g7h8i9", s.tip_id.?);

    const branch = try s.branchEntries(gpa);
    defer gpa.free(branch);
    try std.testing.expect(branch.len >= 3);
    try std.testing.expectEqualStrings("user", branch[0].role);

    // Round-trip save→reload preserves topology
    const jsonl = try s.toJsonl(gpa);
    defer gpa.free(jsonl);
    var again = try Session.parseJsonl(gpa, jsonl);
    defer again.deinit();
    try std.testing.expectEqualStrings(s.id, again.id);
    try std.testing.expectEqual(@as(usize, s.entries.items.len), again.entries.items.len);
    try std.testing.expectEqualStrings(s.entries.items[0].id, again.entries.items[0].id);
    try std.testing.expectEqualStrings(s.entries.items[1].parent_id.?, again.entries.items[1].parent_id.?);
}

test "listSessions and mostRecentSessionPath" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir = path_buf[0..n];

    var s = try Session.init(gpa, "list-me", dir);
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "x", null, null);
    const path = try newSessionPath(gpa, dir, "list-me");
    defer gpa.free(path);
    try s.save(io, path);

    const listed = try listSessions(gpa, io, dir);
    defer {
        for (listed) |*info| {
            var mut = info.*;
            mut.deinit(gpa);
        }
        gpa.free(listed);
    }
    try std.testing.expect(listed.len >= 1);
    try std.testing.expectEqualStrings("list-me", listed[0].id);

    const recent = try mostRecentSessionPath(gpa, io, dir);
    defer if (recent) |r| gpa.free(r);
    try std.testing.expect(recent != null);
    try std.testing.expect(std.mem.indexOf(u8, recent.?, "list-me") != null);
}

test "session load repairs unterminated valid and malformed tails only after a valid header" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root = root_buf[0..try tmp.dir.realPath(io, &root_buf)];
    const header = "{\"type\":\"session\",\"version\":3,\"id\":\"tail\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"cwd\":\"/tmp\"}";
    const message = "{\"type\":\"message\",\"id\":\"m1\",\"parentId\":null,\"timestamp\":\"2026-01-01T00:00:01Z\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}";
    const cases = [_]struct { name: []const u8, tail: []const u8, entries: usize }{
        .{ .name = "valid.jsonl", .tail = message, .entries = 1 },
        .{ .name = "malformed.jsonl", .tail = "{\"type\":\"message\"", .entries = 0 },
    };
    for (cases) |case| {
        const path = try std.fs.path.join(gpa, &.{ root, case.name });
        defer gpa.free(path);
        const content = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ header, case.tail });
        defer gpa.free(content);
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = content });
        var loaded = try Session.load(gpa, io, path);
        defer loaded.deinit();
        try std.testing.expectEqual(case.entries, loaded.entries.items.len);
        const repaired = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(4096));
        defer gpa.free(repaired);
        try std.testing.expect(repaired.len > 0 and repaired[repaired.len - 1] == '\n');
    }

    const invalid_path = try std.fs.path.join(gpa, &.{ root, "not-session.jsonl" });
    defer gpa.free(invalid_path);
    const invalid = "{\"type\":\"message\",\"id\":\"m1\"}";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = invalid_path, .data = invalid });
    try std.testing.expectError(error.InvalidSession, Session.load(gpa, io, invalid_path));
    const unchanged = try std.Io.Dir.cwd().readFileAlloc(io, invalid_path, gpa, .limited(4096));
    defer gpa.free(unchanged);
    try std.testing.expectEqualStrings(invalid, unchanged);
}

test "assistant thinking survives JSONL round trip" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "thinking-session", "/tmp");
    defer session.deinit();
    _ = try session.appendMessageMeta(null, "assistant", "answer", null, null, null, .{
        .thinking = "private reasoning summary",
        .thinking_signature = "opaque-signature-123",
        .provider = "corp",
        .model = "m",
        .stop_reason = "stop",
    });
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"thinking\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "opaque-signature-123") != null);
    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("private reasoning summary", loaded.entries.items[0].meta.thinking);
    try std.testing.expectEqualStrings("opaque-signature-123", loaded.entries.items[0].meta.thinking_signature);
}

test "redacted reasoning marker survives upstream content-block JSONL" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "redacted-session", "/tmp");
    defer session.deinit();
    _ = try session.appendMessageMeta(null, "assistant", "answer", null, null, null, .{
        .thinking = "[Reasoning redacted]",
        .thinking_signature = "aGVsbG8=",
        .thinking_redacted = true,
        .provider = "amazon-bedrock",
        .api = "bedrock-converse-stream",
        .model = "global.openai.gpt-5.6-terra",
        .stop_reason = "stop",
    });
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"redacted\":true") != null);
    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expect(loaded.entries.items[0].meta.thinking_redacted);
    try std.testing.expectEqualStrings("aGVsbG8=", loaded.entries.items[0].meta.thinking_signature);
}

test "tool result addedToolNames survive JSONL and fork" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "deferred", "/tmp");
    defer session.deinit();
    const names = [_][]const u8{ "late_tool", "other_tool" };
    _ = try session.appendToolResultStatusWithAdded(null, "ok", "call-1", "loader", false, &names);
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"addedToolNames\":[\"late_tool\",\"other_tool\"]") != null);
    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items[0].added_tool_names.len);
    try std.testing.expectEqualStrings("late_tool", loaded.entries.items[0].added_tool_names[0]);
    var forked = try loaded.fork(gpa, "forked");
    defer forked.deinit();
    try std.testing.expectEqualStrings("other_tool", forked.entries.items[0].added_tool_names[1]);
}

test "tool result usage survives JSONL reload fork and stats" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "tool-usage", "/tmp");
    defer session.deinit();
    _ = try session.appendToolResultStatusWithAdded(null, "nested result", "call-usage", "subagent", false, &.{"late_nested"});
    const entry = &session.entries.items[0];
    entry.meta.usage_input = 11;
    entry.meta.usage_output = 7;
    entry.meta.usage_cache_read = 5;
    entry.meta.usage_cache_write = 3;
    entry.meta.usage_cache_write_1h = 2;
    entry.meta.usage_reasoning = 4;
    entry.meta.usage_total = 26;
    entry.meta.cost_input = 0.11;
    entry.meta.cost_output = 0.22;
    entry.meta.cost_cache_read = 0.03;
    entry.meta.cost_cache_write = 0.04;
    entry.meta.cost_total = 0.40;

    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"usage\":{\"input\":11") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"cacheWrite1h\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"reasoning\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"totalTokens\":26") != null);

    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    const restored = loaded.entries.items[0];
    try std.testing.expectEqual(@as(u64, 11), restored.meta.usage_input);
    try std.testing.expectEqual(@as(u64, 26), restored.meta.usage_total);
    try std.testing.expectEqual(@as(?u64, 2), restored.meta.usage_cache_write_1h);
    try std.testing.expectEqual(@as(?u64, 4), restored.meta.usage_reasoning);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), restored.meta.cost_total, 1e-12);

    const totals = loaded.stats();
    try std.testing.expectEqual(@as(u64, 11), totals.tokens.input);
    try std.testing.expectEqual(@as(u64, 7), totals.tokens.output);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), totals.cost, 1e-12);

    var forked = try loaded.fork(gpa, "tool-usage-fork");
    defer forked.deinit();
    try std.testing.expectEqual(@as(u64, 26), forked.entries.items[0].meta.usage_total);
    try std.testing.expectEqualStrings("late_nested", forked.entries.items[0].added_tool_names[0]);
}

test "tool result image survives JSONL load and fork" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "img-session", "/tmp");
    defer session.deinit();
    _ = try session.appendToolResultStatusWithMedia(null, "capture", "call-img", "screenshot", false, &.{}, "AQIDBA==", "image/png");
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"image\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "AQIDBA==") != null);

    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.items.len);
    try std.testing.expectEqualStrings("AQIDBA==", loaded.entries.items[0].image_b64.?);
    try std.testing.expectEqualStrings("image/png", loaded.entries.items[0].image_mime.?);

    var forked = try loaded.fork(gpa, "img-fork");
    defer forked.deinit();
    try std.testing.expectEqualStrings("AQIDBA==", forked.entries.items[0].image_b64.?);
    try std.testing.expectEqualStrings("image/png", forked.entries.items[0].image_mime.?);
}

test "session auxiliary label custom and info entries stay out of model roles" {
    const gpa = std.testing.allocator;
    const fixture =
        \\{"type":"session","version":3,"id":"aux-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","id":"m7","parentId":null,"timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":"hello"}}
        \\{"type":"label","id":"lab1","parentId":"m7","timestamp":"2026-01-01T00:00:02.000Z","targetId":"m7","label":"bookmark"}
        \\{"type":"custom","id":"custom1","parentId":"lab1","timestamp":"2026-01-01T00:00:03.000Z","customType":"demo","data":{"k":1}}
        \\{"type":"session_info","id":"info1","parentId":"custom1","timestamp":"2026-01-01T00:00:04.000Z","name":"Named session"}
        \\{"type":"message","id":"m9","parentId":"info1","timestamp":"2026-01-01T00:00:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"world"}],"stopReason":"stop"}}
        \\
    ;
    var session = try Session.parseJsonl(gpa, fixture);
    defer session.deinit();

    try std.testing.expectEqual(@as(usize, 5), session.entries.items.len);
    try std.testing.expectEqual(EntryType.message, session.entries.items[0].entry_type);
    try std.testing.expectEqual(EntryType.label, session.entries.items[1].entry_type);
    try std.testing.expectEqualStrings("aux", session.entries.items[1].role);
    try std.testing.expectEqualStrings("", session.entries.items[1].content);
    try std.testing.expectEqual(EntryType.custom, session.entries.items[2].entry_type);
    try std.testing.expectEqualStrings("aux", session.entries.items[2].role);
    try std.testing.expectEqualStrings("demo", session.entries.items[2].custom_type.?);
    try std.testing.expectEqualStrings("{\"k\":1}", session.entries.items[2].data_json.?);
    try std.testing.expectEqual(EntryType.session_info, session.entries.items[3].entry_type);
    try std.testing.expectEqualStrings("Named session", session.name);
    try std.testing.expectEqualStrings("bookmark", session.getLabel("m7").?);
    try std.testing.expectEqualStrings("m9", session.tip_id.?);

    const children = try session.getChildren(gpa, "m7");
    defer gpa.free(children);
    try std.testing.expectEqual(@as(usize, 1), children.len);
    try std.testing.expectEqualStrings("lab1", children[0].id);

    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"label\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"custom\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "[label]") == null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "[custom]") == null);

    // Imported m7/m9 IDs advance the generator, so appending cannot collide.
    const id = try session.appendCustomEntry("after-import", "{\"ok\":true}");
    try std.testing.expectEqualStrings("m10", id);
}

test "session label clearing and session info are append-only tree entries" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "aux-2", "/tmp");
    defer session.deinit();
    const root = try session.appendMessage(null, "user", "hello", null, null);
    _ = try session.appendLabelChange(root, "  keep me  ");
    try std.testing.expectEqualStrings("keep me", session.getLabel(root).?);
    _ = try session.appendLabelChange(root, null);
    try std.testing.expect(session.getLabel(root) == null);
    _ = try session.appendSessionInfo("  first\nname\r\n ");
    try std.testing.expectEqualStrings("first name", session.name);
    try std.testing.expectEqual(EntryType.session_info, session.entries.items[session.entries.items.len - 1].entry_type);

    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("first name", loaded.name);
    try std.testing.expect(loaded.getLabel(root) == null);
    try std.testing.expectEqual(session.entries.items.len, loaded.entries.items.len);
}

test "session explicit tip survives later physical JSONL entries" {
    const gpa = std.testing.allocator;
    const fixture =
        \\{"type":"session","version":3,"id":"tip-1","timestamp":"2026-01-01T00:00:00.000Z","cwd":"/tmp","tipId":"m1"}
        \\{"type":"message","id":"m1","parentId":null,"timestamp":"2026-01-01T00:00:01.000Z","message":{"role":"user","content":"root"}}
        \\{"type":"message","id":"m2","parentId":"m1","timestamp":"2026-01-01T00:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"other branch"}],"stopReason":"stop"}}
        \\
    ;
    var session = try Session.parseJsonl(gpa, fixture);
    defer session.deinit();
    try std.testing.expectEqualStrings("m1", session.tip_id.?);
    const id = try session.appendMessage(session.lastEntryId(), "user", "continue root", null, null);
    try std.testing.expectEqualStrings("m3", id);
    try std.testing.expectEqualStrings("m1", session.entries.items[session.entries.items.len - 1].parent_id.?);
}

test "assistant diagnostics raw JSON survives session round trip" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..n], "diag.jsonl" });
    defer gpa.free(path);

    var sess = try Session.init(gpa, "diag-session", path_buf[0..n]);
    defer sess.deinit();
    _ = try sess.appendMessageMeta(null, "assistant", "ok", null, null, null, .{
        .provider = "openai-codex",
        .api = "openai-codex-responses",
        .model = "gpt-5",
        .diagnostics_json = "[{\"type\":\"provider_transport_failure\",\"timestamp\":123,\"details\":{\"fallbackTransport\":\"sse\"}}]",
        .stop_reason = "stop",
    });
    try sess.save(io, path);

    var loaded = try Session.load(gpa, io, path);
    defer loaded.deinit();
    const last = loaded.entries.items[loaded.entries.items.len - 1];
    try std.testing.expect(std.mem.indexOf(u8, last.meta.diagnostics_json, "provider_transport_failure") != null);
    try std.testing.expect(std.mem.indexOf(u8, last.meta.diagnostics_json, "fallbackTransport") != null);
}

test "bash execution message survives exact session round trip and fork" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "bash-session", "/tmp");
    defer session.deinit();
    _ = try session.appendBashExecution(
        null,
        "printf hi; exit 7",
        "hi",
        7,
        false,
        true,
        "/tmp/pi-bash-full.log",
        true,
    );

    const entry = session.entries.items[0];
    try std.testing.expectEqualStrings("bashExecution", entry.role);
    try std.testing.expectEqualStrings("printf hi; exit 7", entry.bash_command.?);
    try std.testing.expectEqualStrings("hi", entry.bash_output.?);
    try std.testing.expectEqual(@as(?i32, 7), entry.bash_exit_code);
    try std.testing.expect(entry.bash_truncated);
    try std.testing.expect(entry.bash_exclude_from_context);
    try std.testing.expect(std.mem.indexOf(u8, entry.content, "Command exited with code 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, entry.content, "Full output: /tmp/pi-bash-full.log") != null);

    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"role\":\"bashExecution\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"command\":\"printf hi; exit 7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"exitCode\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"excludeFromContext\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"fullOutputPath\":\"/tmp/pi-bash-full.log\"") != null);

    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    const restored = loaded.entries.items[0];
    try std.testing.expectEqualStrings("bashExecution", restored.role);
    try std.testing.expectEqualStrings("printf hi; exit 7", restored.bash_command.?);
    try std.testing.expectEqualStrings("hi", restored.bash_output.?);
    try std.testing.expectEqual(@as(?i32, 7), restored.bash_exit_code);
    try std.testing.expect(restored.bash_truncated);
    try std.testing.expect(restored.bash_exclude_from_context);
    try std.testing.expectEqualStrings("/tmp/pi-bash-full.log", restored.bash_full_output_path.?);

    var forked = try loaded.fork(gpa, "bash-fork");
    defer forked.deinit();
    try std.testing.expectEqualStrings("printf hi; exit 7", forked.entries.items[0].bash_command.?);
    try std.testing.expectEqualStrings("hi", forked.entries.items[0].bash_output.?);
}

test "bash execution text follows upstream projection rules" {
    const gpa = std.testing.allocator;
    const empty = try formatBashExecutionText(gpa, "true", "", 0, false, false, null);
    defer gpa.free(empty);
    try std.testing.expectEqualStrings("Ran `true`\n(no output)", empty);

    const cancelled = try formatBashExecutionText(gpa, "sleep 10", "partial", 1, true, false, null);
    defer gpa.free(cancelled);
    try std.testing.expect(std.mem.endsWith(u8, cancelled, "(command cancelled)"));
    try std.testing.expect(std.mem.indexOf(u8, cancelled, "Command exited with code") == null);
}

test "model and thinking changes serialize and round trip natively" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var session = try Session.init(gpa, "changes", "/tmp/work");
    defer session.deinit();
    _ = try session.appendModelChange("openai", "gpt-5");
    _ = try session.appendThinkingLevelChange("high");

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..n], "changes.jsonl" });
    defer gpa.free(path);
    try session.save(io, path);

    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"type\":\"model_change\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"provider\":\"openai\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"modelId\":\"gpt-5\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"thinkingLevel\":\"high\"") != null);

    var loaded = try Session.load(gpa, io, path);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expectEqual(EntryType.model_change, loaded.entries.items[0].entry_type);
    try std.testing.expectEqualStrings("openai", loaded.entries.items[0].custom_type.?);
    try std.testing.expectEqualStrings("gpt-5", loaded.entries.items[0].content);
    try std.testing.expectEqual(EntryType.thinking_level_change, loaded.entries.items[1].entry_type);
    try std.testing.expectEqualStrings("high", loaded.entries.items[1].content);
}

test "user image message persists through JSONL and fork" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var sess = try Session.init(gpa, "media-session", "/tmp");
    defer sess.deinit();
    _ = try sess.appendMessageWithMedia(null, "user", "look", "AQIDBA==", "image/png");
    const jsonl = try sess.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"image\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "AQIDBA==") != null);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "media.jsonl" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = jsonl });
    var loaded = try Session.load(gpa, io, path);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("AQIDBA==", loaded.entries.items[0].image_b64.?);
    try std.testing.expectEqualStrings("image/png", loaded.entries.items[0].image_mime.?);
    var forked = try loaded.fork(gpa, "forked-media");
    defer forked.deinit();
    try std.testing.expectEqualStrings("AQIDBA==", forked.entries.items[0].image_b64.?);
}

test "explicit session id validation matches portable upstream grammar" {
    try validateSessionId("build.42_alpha-beta");
    try validateSessionId("A");
    try std.testing.expectError(error.InvalidSessionId, validateSessionId(""));
    try std.testing.expectError(error.InvalidSessionId, validateSessionId("-bad"));
    try std.testing.expectError(error.InvalidSessionId, validateSessionId("bad_"));
    try std.testing.expectError(error.InvalidSessionId, validateSessionId("bad/path"));
    try std.testing.expectError(error.InvalidSessionId, validateSessionId("bad space"));
}

test "find exact session path does not accept prefixes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const dir = path_buf[0..n];
    var sess = try Session.init(gpa, "exact-session", dir);
    defer sess.deinit();
    _ = try sess.appendMessage(null, "user", "hello", null, null);
    const path = try newSessionPath(gpa, dir, "exact-session");
    defer gpa.free(path);
    try sess.save(io, path);
    const found = (try findExactSessionPath(gpa, io, dir, "exact-session")).?;
    defer gpa.free(found);
    try std.testing.expectEqualStrings(path, found);
    try std.testing.expect((try findExactSessionPath(gpa, io, dir, "exact")) == null);
}

test "active settings follow the selected branch" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "settings-branch", "/tmp");
    defer session.deinit();

    const root = try session.appendMessage(null, "user", "hello", null, null);
    _ = try session.appendModelChange("openai", "gpt-root");
    const root_thinking = try session.appendThinkingLevelChange("medium");
    _ = try session.appendModelChange("anthropic", "claude-main");
    _ = try session.appendThinkingLevelChange("high");

    var settings = try session.activeSettings(gpa);
    try std.testing.expect(settings.has_messages);
    try std.testing.expectEqualStrings("anthropic", settings.provider.?);
    try std.testing.expectEqualStrings("claude-main", settings.model_id.?);
    try std.testing.expectEqualStrings("high", settings.thinking_level.?);

    // Fork branch from the first thinking entry and choose another model.
    try session.setTip(root_thinking);
    _ = try session.appendModelChange("google", "gemini-branch");
    settings = try session.activeSettings(gpa);
    try std.testing.expectEqualStrings("google", settings.provider.?);
    try std.testing.expectEqualStrings("gemini-branch", settings.model_id.?);
    try std.testing.expectEqualStrings("medium", settings.thinking_level.?);
    try std.testing.expect(settings.has_thinking_entry);
    _ = root;
}

test "load migrates legacy upstream session and rewrites durable v3" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const path = try std.fs.path.join(gpa, &.{ root, "legacy-v1.jsonl" });
    defer gpa.free(path);
    const legacy =
        \\{"type":"session","id":"legacy-v1","timestamp":"2024-01-02T03:04:05.000Z","cwd":"/legacy"}
        \\{"type":"message","timestamp":"2024-01-02T03:04:06.000Z","message":{"role":"user","content":"hello"}}
        \\broken-json
        \\{"type":"compaction","timestamp":"2024-01-02T03:04:07.000Z","summary":"old","firstKeptEntryIndex":1,"tokensBefore":12}
        \\
    ;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = legacy });

    var loaded = try Session.load(gpa, io, path);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("legacy-v1", loaded.id);
    try std.testing.expectEqualStrings("2024-01-02T03:04:05.000Z", loaded.created_at);
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items.len);
    try std.testing.expect(loaded.entries.items[0].id.len == 8);
    try std.testing.expectEqualStrings(loaded.entries.items[0].id, loaded.entries.items[1].parent_id.?);

    const rewritten = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024));
    defer gpa.free(rewritten);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "\"version\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "broken-json") == null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "firstKeptEntryId") != null);
    try std.testing.expect(std.mem.indexOf(u8, rewritten, "firstKeptEntryIndex") == null);
}

test "session header creation time and parent path survive repeated saves" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "stable-header", "/work");
    defer session.deinit();
    const original_created = try gpa.dupe(u8, session.created_at);
    defer gpa.free(original_created);
    try session.setParentSession("/sessions/parent.jsonl");
    _ = try session.appendMessage(null, "user", "hello", null, null);

    const first = try session.toJsonl(gpa);
    defer gpa.free(first);
    const second = try session.toJsonl(gpa);
    defer gpa.free(second);
    try std.testing.expectEqualStrings(first, second);

    var loaded = try Session.parseJsonl(gpa, first);
    defer loaded.deinit();
    try std.testing.expectEqualStrings(original_created, loaded.created_at);
    try std.testing.expectEqualStrings("/sessions/parent.jsonl", loaded.parent_session.?);
}

test "session stats include all history and summary billing" {
    const fixture =
        \\{"type":"session","version":3,"id":"stats","timestamp":"2024-01-01T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","id":"u1","parentId":null,"timestamp":"2024-01-01T00:00:01.000Z","message":{"role":"user","content":"go"}}
        \\{"type":"message","id":"a1","parentId":"u1","timestamp":"2024-01-01T00:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"}],"toolCalls":[{"id":"t1"},{"id":"t2"}],"usage":{"input":10,"output":4,"cacheRead":2,"cacheWrite":1,"totalTokens":17,"cost":{"total":0.25}}}}
        \\{"type":"message","id":"t1","parentId":"a1","timestamp":"2024-01-01T00:00:03.000Z","message":{"role":"toolResult","toolCallId":"t1","toolName":"bash","content":"ok","usage":{"input":3,"output":1,"cacheRead":0,"cacheWrite":0,"cost":{"total":0.05}}}}
        \\{"type":"compaction","id":"c1","parentId":"t1","timestamp":"2024-01-01T00:00:04.000Z","summary":"summary","firstKeptEntryId":"u1","tokensBefore":17,"usage":{"input":5,"output":2,"cacheRead":1,"cacheWrite":1,"cost":{"total":0.10}}}
        \\
    ;
    var session = try Session.parseJsonl(std.testing.allocator, fixture);
    defer session.deinit();
    const value = session.stats();
    try std.testing.expectEqual(@as(usize, 1), value.user_messages);
    try std.testing.expectEqual(@as(usize, 1), value.assistant_messages);
    try std.testing.expectEqual(@as(usize, 2), value.tool_calls);
    try std.testing.expectEqual(@as(usize, 1), value.tool_results);
    try std.testing.expectEqual(@as(usize, 3), value.total_messages);
    try std.testing.expectEqual(@as(u64, 18), value.tokens.input);
    try std.testing.expectEqual(@as(u64, 7), value.tokens.output);
    try std.testing.expectEqual(@as(u64, 3), value.tokens.cache_read);
    try std.testing.expectEqual(@as(u64, 2), value.tokens.cache_write);
    try std.testing.expectEqual(@as(u64, 30), value.tokens.total);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), value.cost, 0.000001);
}

test "append-only compaction preserves history and rebuilds active context" {
    const gpa = std.testing.allocator;
    var sess = try Session.init(gpa, "append-only-compact", "/tmp");
    defer sess.deinit();

    var ids: [6][]const u8 = undefined;
    var parent: ?[]const u8 = null;
    for (0..5) |index| {
        const text = try std.fmt.allocPrint(gpa, "entry-{d}", .{index});
        defer gpa.free(text);
        ids[index] = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
        parent = ids[index];
    }
    ids[5] = try sess.appendCompaction("durable summary", ids[3], 1234, "{\"readFiles\":[\"a.zig\"]}", false, .{
        .provider = "summary-provider",
        .model = "summary-model",
        .usage_input = 9,
        .usage_output = 3,
    });
    _ = try sess.appendMessage(ids[5], "user", "after-boundary", null, null);

    try std.testing.expectEqual(@as(usize, 7), sess.entries.items.len);
    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);
    try std.testing.expectEqual(@as(usize, 7), branch.len);

    const context = try sess.contextEntries(gpa);
    defer gpa.free(context);
    try std.testing.expectEqual(@as(usize, 4), context.len);
    try std.testing.expectEqual(EntryType.compaction, context[0].entry_type);
    try std.testing.expectEqualStrings("durable summary", context[0].content);
    try std.testing.expectEqualStrings("entry-3", context[1].content);
    try std.testing.expectEqualStrings("entry-4", context[2].content);
    try std.testing.expectEqualStrings("after-boundary", context[3].content);

    const raw = try sess.toJsonl(gpa);
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"firstKeptEntryId\":\"m4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"tokensBefore\":1234") != null);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"details\":{\"readFiles\":[\"a.zig\"]}") != null);

    var restored = try Session.parseJsonl(gpa, raw);
    defer restored.deinit();
    try std.testing.expectEqual(@as(usize, 7), restored.entries.items.len);
    const restored_context = try restored.contextEntries(gpa);
    defer gpa.free(restored_context);
    try std.testing.expectEqual(@as(usize, 4), restored_context.len);
    try std.testing.expectEqualStrings("durable summary", restored_context[0].content);
    try std.testing.expectEqualStrings("m4", restored_context[0].first_kept_entry_id.?);
    try std.testing.expectEqual(@as(u64, 1234), restored_context[0].tokens_before);
    try std.testing.expectEqual(@as(u64, 9), restored_context[0].meta.usage_input);
    try std.testing.expectEqual(@as(u64, 3), restored_context[0].meta.usage_output);
}

test "malformed compaction boundary falls back to the complete active path" {
    const fixture =
        \\{"type":"session","version":3,"id":"broken-boundary","timestamp":"2026-08-18T00:00:00.000Z","cwd":"/tmp"}
        \\{"type":"message","id":"u1","parentId":null,"timestamp":"2026-08-18T00:00:01.000Z","message":{"role":"user","content":"preserve me"}}
        \\{"type":"message","id":"a1","parentId":"u1","timestamp":"2026-08-18T00:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"preserve answer"}]}}
        \\{"type":"compaction","id":"c1","parentId":"a1","timestamp":"2026-08-18T00:00:03.000Z","summary":"broken summary","firstKeptEntryId":"missing","tokensBefore":9}
        \\
    ;
    var sess = try Session.parseJsonl(std.testing.allocator, fixture);
    defer sess.deinit();
    const context = try sess.contextEntries(std.testing.allocator);
    defer std.testing.allocator.free(context);
    try std.testing.expectEqual(@as(usize, 3), context.len);
    try std.testing.expectEqualStrings("preserve me", context[0].content);
    try std.testing.expectEqualStrings("preserve answer", context[1].content);
    try std.testing.expectEqual(EntryType.compaction, context[2].entry_type);
}

test "retry context exclusions are live-only and survive later turns" {
    const gpa = std.testing.allocator;
    var sess = try Session.init(gpa, "retry-exclusion", "/tmp");
    defer sess.deinit();
    const user = try sess.appendMessage(null, "user", "prompt", null, null);
    const failed = try sess.appendMessageMeta(user, "assistant", "transient failure", null, null, null, .{
        .stop_reason = "error",
        .error_message = "HTTP 503",
    });
    _ = try sess.appendMessage(failed, "user", "follow-up", null, null);
    try sess.excludeEntryFromActiveContext(failed);
    try std.testing.expect(sess.isEntryExcludedFromActiveContext(failed));

    const raw = try sess.toJsonl(gpa);
    defer gpa.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "transient failure") != null);

    var restored = try Session.parseJsonl(gpa, raw);
    defer restored.deinit();
    try std.testing.expect(!restored.isEntryExcludedFromActiveContext(failed));
    try std.testing.expect(restored.getEntry(failed) != null);
}

test "session listing projects latest metadata and malformed files" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];

    var session = try Session.init(gpa, "info-session", "/project");
    defer session.deinit();
    try session.setParentSession("/sessions/parent.jsonl");
    _ = try session.appendMessage(null, "user", "first prompt", null, null);
    _ = try session.appendMessage(session.lastEntryId(), "assistant", "answer text", null, null);
    _ = try session.appendSessionInfo("Latest name");
    const good_path = try std.fs.path.join(gpa, &.{ root, "good.jsonl" });
    defer gpa.free(good_path);
    try session.save(io, good_path);
    const bad_path = try std.fs.path.join(gpa, &.{ root, "bad.jsonl" });
    defer gpa.free(bad_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = bad_path, .data = "not json\n" });

    const infos = try listSessions(gpa, io, root);
    defer {
        for (infos) |*info| info.deinit(gpa);
        gpa.free(infos);
    }
    try std.testing.expectEqual(@as(usize, 2), infos.len);
    var saw_good = false;
    var saw_bad = false;
    for (infos) |info| {
        if (std.mem.eql(u8, info.id, "info-session")) {
            saw_good = true;
            try std.testing.expect(info.valid);
            try std.testing.expectEqualStrings("/project", info.cwd);
            try std.testing.expectEqualStrings("Latest name", info.name);
            try std.testing.expectEqualStrings("/sessions/parent.jsonl", info.parent_session_path.?);
            try std.testing.expectEqual(@as(usize, 2), info.message_count);
            try std.testing.expectEqualStrings("first prompt", info.first_message);
            try std.testing.expectEqualStrings("first prompt answer text", info.all_messages_text);
        } else if (std.mem.eql(u8, info.id, "bad")) {
            saw_bad = true;
            try std.testing.expect(!info.valid);
        }
    }
    try std.testing.expect(saw_good and saw_bad);
}

test "multiple tool-result images survive JSONL load and fork" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "multi-image", "/tmp");
    defer session.deinit();
    const extras = [_]SessionImage{
        .{ .data_b64 = "AQ==", .mime_type = "image/jpeg" },
        .{ .data_b64 = "Ag==", .mime_type = "image/webp" },
    };
    _ = try session.appendToolResultStatusWithImages(null, "capture", "call-images", "shot", false, &.{}, "AA==", "image/png", &extras);
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, jsonl, "\"type\":\"image\""));

    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqualStrings("AA==", loaded.entries.items[0].image_b64.?);
    try std.testing.expectEqual(@as(usize, 2), loaded.entries.items[0].images.len);
    try std.testing.expectEqualStrings("Ag==", loaded.entries.items[0].images[1].data_b64);

    var forked = try loaded.fork(gpa, "multi-image-fork");
    defer forked.deinit();
    try std.testing.expectEqual(@as(usize, 2), forked.entries.items[0].images.len);
    try std.testing.expect(forked.entries.items[0].images[0].data_b64.ptr != loaded.entries.items[0].images[0].data_b64.ptr);
}

test "one user message persists multiple ordered images" {
    const gpa = std.testing.allocator;
    var session = try Session.init(gpa, "multi-user-image", "/tmp");
    defer session.deinit();
    const images = [_]SessionImage{
        .{ .data_b64 = "AA==", .mime_type = "image/png" },
        .{ .data_b64 = "AQ==", .mime_type = "image/jpeg" },
    };
    _ = try session.appendMessageWithImages(null, "user", "compare", &images);
    const jsonl = try session.toJsonl(gpa);
    defer gpa.free(jsonl);
    var loaded = try Session.parseJsonl(gpa, jsonl);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.items.len);
    try std.testing.expectEqualStrings("AA==", loaded.entries.items[0].image_b64.?);
    try std.testing.expectEqual(@as(usize, 1), loaded.entries.items[0].images.len);
    try std.testing.expectEqualStrings("AQ==", loaded.entries.items[0].images[0].data_b64);
}

test "session entry deep copy preserves every rich field" {
    const gpa = std.testing.allocator;
    var entry: SessionEntry = .{
        .entry_type = .custom_message,
        .id = try gpa.dupe(u8, "entry-rich"),
        .parent_id = try gpa.dupe(u8, "parent-rich"),
        .role = try gpa.dupe(u8, "assistant"),
        .content = try gpa.dupe(u8, "rich content"),
        .tool_call_id = try gpa.dupe(u8, "call-rich"),
        .tool_calls_json = try gpa.dupe(u8, "[]"),
        .tool_name = try gpa.dupe(u8, "read"),
        .tool_is_error = true,
        .image_b64 = try gpa.dupe(u8, "AA=="),
        .image_mime = try gpa.dupe(u8, "image/png"),
        .images = try cloneSessionImages(gpa, &[_]SessionImage{
            .{ .data_b64 = "AQ==", .mime_type = "image/jpeg" },
            .{ .data_b64 = "Ag==", .mime_type = "image/webp" },
        }),
        .bash_command = try gpa.dupe(u8, "printf rich"),
        .bash_output = try gpa.dupe(u8, "rich"),
        .bash_exit_code = 7,
        .bash_cancelled = true,
        .bash_truncated = true,
        .bash_full_output_path = try gpa.dupe(u8, "/tmp/rich.log"),
        .bash_exclude_from_context = true,
        .bash_timestamp_ms = 1234,
        .added_tool_names = blk: {
            var names = try gpa.alloc([]const u8, 2);
            names[0] = try gpa.dupe(u8, "alpha");
            names[1] = try gpa.dupe(u8, "beta");
            break :blk names;
        },
        .raw_json = try gpa.dupe(u8, "{\"raw\":true}"),
        .target_id = try gpa.dupe(u8, "target"),
        .label = try gpa.dupe(u8, "label"),
        .custom_type = try gpa.dupe(u8, "card"),
        .data_json = try gpa.dupe(u8, "{\"value\":1}"),
        .first_kept_entry_id = try gpa.dupe(u8, "first-kept"),
        .tokens_before = 4321,
        .from_hook = true,
        .display = true,
        .timestamp = try gpa.dupe(u8, "2026-08-18T12:34:56.000Z"),
        .meta = .{
            .thinking = try gpa.dupe(u8, "thought"),
            .provider = try gpa.dupe(u8, "provider"),
            .model = try gpa.dupe(u8, "model"),
            .stop_reason = try gpa.dupe(u8, "error"),
            .usage_input = 11,
            .cost_total = 1.25,
        },
    };
    defer entry.deinit(gpa);

    var copy = try entry.dupe(gpa);
    defer copy.deinit(gpa);
    try std.testing.expectEqual(entry.entry_type, copy.entry_type);
    try std.testing.expectEqualStrings(entry.id, copy.id);
    try std.testing.expect(entry.id.ptr != copy.id.ptr);
    try std.testing.expectEqualStrings(entry.parent_id.?, copy.parent_id.?);
    try std.testing.expectEqualStrings(entry.image_b64.?, copy.image_b64.?);
    try std.testing.expectEqual(@as(usize, 2), copy.images.len);
    try std.testing.expectEqualStrings("image/webp", copy.images[1].mime_type);
    try std.testing.expectEqualStrings("beta", copy.added_tool_names[1]);
    try std.testing.expectEqualStrings("/tmp/rich.log", copy.bash_full_output_path.?);
    try std.testing.expectEqualStrings("card", copy.custom_type.?);
    try std.testing.expectEqualStrings("first-kept", copy.first_kept_entry_id.?);
    try std.testing.expectEqual(@as(u64, 4321), copy.tokens_before);
    try std.testing.expect(copy.from_hook);
    try std.testing.expectEqualStrings("thought", copy.meta.thinking);
    try std.testing.expectEqual(@as(u64, 11), copy.meta.usage_input);
    try std.testing.expectEqual(@as(f64, 1.25), copy.meta.cost_total);
}
