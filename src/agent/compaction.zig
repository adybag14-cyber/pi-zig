//! Context compaction with token-budget cut points and append-only history.
const std = @import("std");
const session_mod = @import("session.zig");
const ai = @import("../ai/root.zig");
const context_estimate = @import("../ai/context_estimate.zig");
const summarization = @import("summarization.zig");

const Io = std.Io;
const ESTIMATED_IMAGE_CHARS: u64 = 4_800;
const TOOL_RESULT_MAX_CHARS: usize = 2_000;

pub const Settings = struct {
    enabled: bool = true,
    reserve_tokens: u64 = 16_384,
    keep_recent_tokens: u64 = 20_000,
};

pub const FileOperationView = struct {
    read: []const []const u8 = &.{},
    written: []const []const u8 = &.{},
    edited: []const []const u8 = &.{},
};

/// Extension-facing preparation state. All slices borrow from the live session
/// or the temporary preparation object and remain valid only for the callback.
pub const HookPreparation = struct {
    branch_entries: []const *const session_mod.SessionEntry,
    messages_to_summarize: []const *const session_mod.SessionEntry,
    turn_prefix_messages: []const *const session_mod.SessionEntry,
    is_split_turn: bool,
    first_kept_entry_id: []const u8,
    tokens_before: u64,
    previous_summary: ?[]const u8 = null,
    file_ops: FileOperationView = .{},
    settings: Settings = .{},
    custom_instructions: ?[]const u8 = null,
    reason: summarization.Reason,
    will_retry: bool,
};

/// Owned replacement returned by `session_before_compact`.
pub const HookCompaction = struct {
    summary: []u8,
    first_kept_entry_id: []u8,
    tokens_before: u64,
    details_json: ?[]u8 = null,
    meta: session_mod.AssistantMeta = .{},

    pub fn deinit(self: *HookCompaction, gpa: std.mem.Allocator) void {
        gpa.free(self.summary);
        gpa.free(self.first_kept_entry_id);
        if (self.details_json) |value| gpa.free(value);
        self.meta.deinit(gpa);
        self.* = undefined;
    }
};

pub const BeforeHookResult = struct {
    cancel: bool = false,
    compaction: ?HookCompaction = null,

    pub fn deinit(self: *BeforeHookResult, gpa: std.mem.Allocator) void {
        if (self.compaction) |*value| value.deinit(gpa);
        self.* = undefined;
    }
};

pub const BeforeHookFn = *const fn (
    ctx: ?*anyopaque,
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    preparation: HookPreparation,
) anyerror!?BeforeHookResult;

pub const AfterHookFn = *const fn (
    ctx: ?*anyopaque,
    gpa: std.mem.Allocator,
    compaction_entry: *const session_mod.SessionEntry,
    reason: summarization.Reason,
    will_retry: bool,
    from_extension: bool,
) anyerror!void;

pub const CompactOptions = struct {
    io: Io,
    settings: Settings = .{},
    /// Optional model client for LLM-written summaries. Extractive summaries are
    /// used only when no model client was requested.
    client: ?ai.ModelClient = null,
    custom_instructions: ?[]const u8 = null,
    reason: summarization.Reason = .manual,
    retry_enabled: bool = true,
    retry_max_retries: usize = 3,
    retry_base_delay_ms: u64 = 2_000,
    abort_flag: ?*bool = null,
    retry_abort_flag: ?*bool = null,
    on_retry_event: ?summarization.EventHandler = null,
    retry_event_ctx: ?*anyopaque = null,
    hook_ctx: ?*anyopaque = null,
    before_hook_fn: ?BeforeHookFn = null,
    after_hook_fn: ?AfterHookFn = null,
    /// Overflow recovery retries the aborted assistant turn after compaction.
    will_retry: bool = false,
};

pub const CutPoint = struct {
    first_kept_entry_index: usize,
    turn_start_index: ?usize = null,
    is_split_turn: bool = false,
};

const FileOperations = struct {
    gpa: std.mem.Allocator,
    read: std.StringHashMap(void),
    written: std.StringHashMap(void),
    edited: std.StringHashMap(void),

    fn init(gpa: std.mem.Allocator) FileOperations {
        return .{
            .gpa = gpa,
            .read = std.StringHashMap(void).init(gpa),
            .written = std.StringHashMap(void).init(gpa),
            .edited = std.StringHashMap(void).init(gpa),
        };
    }

    fn deinit(self: *FileOperations) void {
        freeMapKeys(self.gpa, &self.read);
        freeMapKeys(self.gpa, &self.written);
        freeMapKeys(self.gpa, &self.edited);
        self.read.deinit();
        self.written.deinit();
        self.edited.deinit();
        self.* = undefined;
    }

    fn add(self: *FileOperations, target: *std.StringHashMap(void), path: []const u8) !void {
        if (path.len == 0 or target.contains(path)) return;
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        try target.put(owned, {});
    }

    fn addRead(self: *FileOperations, path: []const u8) !void {
        try self.add(&self.read, path);
    }

    fn addWritten(self: *FileOperations, path: []const u8) !void {
        try self.add(&self.written, path);
    }

    fn addEdited(self: *FileOperations, path: []const u8) !void {
        try self.add(&self.edited, path);
    }
};

fn freeMapKeys(gpa: std.mem.Allocator, map: *std.StringHashMap(void)) void {
    var it = map.keyIterator();
    while (it.next()) |key| gpa.free(key.*);
}

fn sortedMapKeys(gpa: std.mem.Allocator, map: *const std.StringHashMap(void)) ![][]const u8 {
    var out = try gpa.alloc([]const u8, map.count());
    var index: usize = 0;
    var it = map.keyIterator();
    while (it.next()) |key| : (index += 1) out[index] = key.*;
    std.mem.sort([]const u8, out, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return out;
}

const Preparation = struct {
    gpa: std.mem.Allocator,
    branch_entries: []const *const session_mod.SessionEntry,
    messages_to_summarize: []const *const session_mod.SessionEntry,
    turn_prefix_messages: []const *const session_mod.SessionEntry,
    is_split_turn: bool,
    first_kept_entry_id: []const u8,
    tokens_before: u64,
    previous_summary: ?[]const u8,
    settings: Settings,
    file_ops: FileOperations,
    read_view: [][]const u8,
    written_view: [][]const u8,
    edited_view: [][]const u8,

    fn deinit(self: *Preparation) void {
        self.gpa.free(self.branch_entries);
        self.gpa.free(self.messages_to_summarize);
        self.gpa.free(self.turn_prefix_messages);
        self.gpa.free(self.read_view);
        self.gpa.free(self.written_view);
        self.gpa.free(self.edited_view);
        self.file_ops.deinit();
        self.* = undefined;
    }

    fn hookView(self: *const Preparation, opts: CompactOptions) HookPreparation {
        return .{
            .branch_entries = self.branch_entries,
            .messages_to_summarize = self.messages_to_summarize,
            .turn_prefix_messages = self.turn_prefix_messages,
            .is_split_turn = self.is_split_turn,
            .first_kept_entry_id = self.first_kept_entry_id,
            .tokens_before = self.tokens_before,
            .previous_summary = self.previous_summary,
            .file_ops = .{
                .read = self.read_view,
                .written = self.written_view,
                .edited = self.edited_view,
            },
            .settings = self.settings,
            .custom_instructions = opts.custom_instructions,
            .reason = opts.reason,
            .will_retry = opts.will_retry,
        };
    }
};

const GeneratedSummary = struct {
    text: []u8,
    meta: session_mod.AssistantMeta = .{},

    fn deinit(self: *GeneratedSummary, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.meta.deinit(gpa);
        self.* = undefined;
    }
};

pub fn shouldCompact(context_tokens: u64, context_window: u64, settings: Settings) bool {
    if (!settings.enabled or context_window == 0) return false;
    const threshold = context_window -| settings.reserve_tokens;
    return context_tokens > threshold;
}

/// Estimate the provider-facing active context. The latest successful assistant
/// usage is authoritative; only entries after it use the conservative chars/4
/// fallback. This mirrors the original Pi policy and avoids repeatedly charging
/// the complete catalog/system prompt after a trusted usage snapshot.
pub fn estimateSessionContextTokens(gpa: std.mem.Allocator, sess: *const session_mod.Session) !u64 {
    const entries = try sess.contextEntries(gpa);
    defer gpa.free(entries);
    return estimateContextTokens(sess, entries);
}

fn estimateContextTokens(sess: *const session_mod.Session, entries: []const *const session_mod.SessionEntry) u64 {
    // Compaction summaries are inserted ahead of an older retained tail. Their
    // newer timestamp invalidates usage snapshots from that tail; otherwise a
    // pre-compaction assistant total could make the freshly compacted context
    // appear larger than it really is. This mirrors ai/context_estimate.zig.
    var latest_prefix_timestamp: ?[]const u8 = null;
    var last_usage_index: ?usize = null;
    var last_usage_tokens: u64 = 0;
    var latest_compaction_sequence: ?usize = null;
    for (entries) |entry| {
        if (entry.entry_type != .compaction) continue;
        for (sess.entries.items, 0..) |durable, durable_index| {
            if (std.mem.eql(u8, durable.id, entry.id)) latest_compaction_sequence = durable_index;
        }
    }

    for (entries, 0..) |entry, index| {
        if (sess.isEntryExcludedFromActiveContext(entry.id) or entry.bash_exclude_from_context) continue;
        if (std.mem.eql(u8, entry.role, "assistant")) {
            const stop = entry.meta.stop_reason;
            const usage = assistantUsageTokens(entry.*);
            var before_latest_compaction = false;
            if (latest_compaction_sequence) |boundary_index| {
                for (sess.entries.items, 0..) |durable, durable_index| {
                    if (std.mem.eql(u8, durable.id, entry.id)) {
                        before_latest_compaction = durable_index < boundary_index;
                        break;
                    }
                }
            }
            const timestamp_is_current = if (latest_prefix_timestamp) |latest|
                entry.timestamp.len > 0 and std.mem.order(u8, entry.timestamp, latest) != .lt
            else
                true;
            if (!before_latest_compaction and timestamp_is_current and usage > 0 and
                !std.mem.eql(u8, stop, "aborted") and
                !std.mem.eql(u8, stop, "error"))
            {
                last_usage_index = index;
                last_usage_tokens = usage;
            }
        }
        if (entry.timestamp.len > 0 and
            (latest_prefix_timestamp == null or std.mem.order(u8, entry.timestamp, latest_prefix_timestamp.?) == .gt))
        {
            latest_prefix_timestamp = entry.timestamp;
        }
    }

    if (last_usage_index) |index| {
        var trailing: u64 = 0;
        for (entries[index + 1 ..]) |later| {
            if (sess.isEntryExcludedFromActiveContext(later.id) or later.bash_exclude_from_context) continue;
            trailing +|= estimateEntryTokens(later.*);
        }
        return last_usage_tokens +| trailing;
    }

    var total: u64 = 0;
    for (entries) |entry| {
        if (sess.isEntryExcludedFromActiveContext(entry.id) or entry.bash_exclude_from_context) continue;
        total +|= estimateEntryTokens(entry.*);
    }
    return total;
}

fn assistantUsageTokens(entry: session_mod.SessionEntry) u64 {
    if (entry.meta.usage_total > 0) return entry.meta.usage_total;
    return entry.meta.usage_input +| entry.meta.usage_output +| entry.meta.usage_cache_read +| entry.meta.usage_cache_write;
}

pub fn estimateEntryTokens(entry: session_mod.SessionEntry) u64 {
    if (!entryContributesToContext(entry)) return 0;
    var chars: u64 = 0;
    if (std.mem.eql(u8, entry.role, "bashExecution")) {
        chars +|= @intCast(if (entry.bash_command) |value| value.len else 0);
        chars +|= @intCast(if (entry.bash_output) |value| value.len else entry.content.len);
    } else {
        chars +|= @intCast(entry.content.len);
    }
    chars +|= @as(u64, @intCast(@as(usize, @intFromBool(entry.image_b64 != null)) + entry.images.len)) * ESTIMATED_IMAGE_CHARS;
    if (std.mem.eql(u8, entry.role, "assistant")) {
        chars +|= @intCast(entry.meta.thinking.len);
        if (entry.tool_calls_json) |calls| chars +|= context_estimate.estimateToolCallsChars(calls);
    }
    return @divFloor(chars + 3, 4);
}

fn entryContributesToContext(entry: session_mod.SessionEntry) bool {
    return switch (entry.entry_type) {
        .compaction, .branch_summary, .custom_message => true,
        .message => std.mem.eql(u8, entry.role, "user") or
            std.mem.eql(u8, entry.role, "assistant") or
            std.mem.eql(u8, entry.role, "tool") or
            std.mem.eql(u8, entry.role, "system") or
            (std.mem.eql(u8, entry.role, "bashExecution") and !entry.bash_exclude_from_context),
        else => false,
    };
}

fn isCutPointEntry(entry: session_mod.SessionEntry) bool {
    if (!entryContributesToContext(entry) or entry.entry_type == .compaction) return false;
    return !std.mem.eql(u8, entry.role, "tool");
}

fn isTurnStartEntry(entry: session_mod.SessionEntry) bool {
    if (!entryContributesToContext(entry) or entry.entry_type == .compaction) return false;
    if (entry.entry_type == .branch_summary or entry.entry_type == .custom_message) return true;
    return std.mem.eql(u8, entry.role, "user") or
        std.mem.eql(u8, entry.role, "bashExecution") or
        std.mem.eql(u8, entry.role, "system");
}

fn findTurnStartIndex(entries: []const *const session_mod.SessionEntry, entry_index: usize, start_index: usize) ?usize {
    var index = entry_index + 1;
    while (index > start_index) {
        index -= 1;
        if (isTurnStartEntry(entries[index].*)) return index;
    }
    return null;
}

pub fn findCutPoint(
    sess: *const session_mod.Session,
    entries: []const *const session_mod.SessionEntry,
    start_index: usize,
    end_index: usize,
    keep_recent_tokens: u64,
) CutPoint {
    if (start_index >= end_index) return .{ .first_kept_entry_index = start_index };

    var first_cut: ?usize = null;
    for (entries[start_index..end_index], start_index..) |entry, index| {
        if (sess.isEntryExcludedFromActiveContext(entry.id)) continue;
        if (isCutPointEntry(entry.*)) {
            first_cut = index;
            break;
        }
    }
    const default_cut = first_cut orelse return .{ .first_kept_entry_index = start_index };

    var accumulated: u64 = 0;
    var cut_index = default_cut;
    var cursor = end_index;
    while (cursor > start_index) {
        cursor -= 1;
        const entry = entries[cursor];
        if (!sess.isEntryExcludedFromActiveContext(entry.id) and !entry.bash_exclude_from_context)
            accumulated +|= estimateEntryTokens(entry.*);
        if (accumulated < keep_recent_tokens) continue;

        for (entries[cursor..end_index], cursor..) |candidate, index| {
            if (sess.isEntryExcludedFromActiveContext(candidate.id)) continue;
            if (isCutPointEntry(candidate.*)) {
                cut_index = index;
                break;
            }
        }
        break;
    }

    // Retain adjacent labels/session metadata immediately preceding the cut.
    while (cut_index > start_index) {
        const previous = entries[cut_index - 1];
        if (previous.entry_type == .compaction or entryContributesToContext(previous.*)) break;
        cut_index -= 1;
    }

    const starts_turn = isTurnStartEntry(entries[cut_index].*);
    const turn_start = if (starts_turn) null else findTurnStartIndex(entries, cut_index, start_index);
    return .{
        .first_kept_entry_index = cut_index,
        .turn_start_index = turn_start,
        .is_split_turn = !starts_turn and turn_start != null,
    };
}

fn collectContextEntries(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    entries: []const *const session_mod.SessionEntry,
    start: usize,
    end: usize,
) ![]const *const session_mod.SessionEntry {
    var list: std.ArrayList(*const session_mod.SessionEntry) = .empty;
    errdefer list.deinit(gpa);
    for (entries[start..end]) |entry| {
        if (sess.isEntryExcludedFromActiveContext(entry.id) or entry.entry_type == .compaction) continue;
        if (entryContributesToContext(entry.*)) try list.append(gpa, entry);
    }
    return try list.toOwnedSlice(gpa);
}

fn findEntryIndex(entries: []const *const session_mod.SessionEntry, id: []const u8) ?usize {
    for (entries, 0..) |entry, index| if (std.mem.eql(u8, entry.id, id)) return index;
    return null;
}

fn prepareCompaction(gpa: std.mem.Allocator, sess: *const session_mod.Session, settings: Settings) !?Preparation {
    if (settings.keep_recent_tokens == 0) return error.InvalidKeepRecentTokens;
    const branch = try sess.branchEntries(gpa);
    errdefer gpa.free(branch);
    if (branch.len == 0 or branch[branch.len - 1].entry_type == .compaction) {
        gpa.free(branch);
        return null;
    }

    var previous_index: ?usize = null;
    for (branch, 0..) |entry, index| {
        if (entry.entry_type == .compaction) previous_index = index;
    }

    var boundary_start: usize = 0;
    var previous_summary: ?[]const u8 = null;
    if (previous_index) |index| {
        const previous = branch[index];
        previous_summary = previous.content;
        if (previous.first_kept_entry_id) |id| {
            boundary_start = findEntryIndex(branch, id) orelse index + 1;
        } else {
            boundary_start = index + 1;
        }
    }

    const context = try sess.contextEntries(gpa);
    defer gpa.free(context);
    const tokens_before = estimateContextTokens(sess, context);
    const cut = findCutPoint(sess, branch, boundary_start, branch.len, settings.keep_recent_tokens);
    if (cut.first_kept_entry_index >= branch.len) {
        gpa.free(branch);
        return null;
    }

    const history_end = if (cut.is_split_turn) cut.turn_start_index.? else cut.first_kept_entry_index;
    const messages = try collectContextEntries(gpa, sess, branch, boundary_start, history_end);
    errdefer gpa.free(messages);
    const prefix = if (cut.is_split_turn)
        try collectContextEntries(gpa, sess, branch, cut.turn_start_index.?, cut.first_kept_entry_index)
    else
        try gpa.alloc(*const session_mod.SessionEntry, 0);
    errdefer gpa.free(prefix);

    if (messages.len == 0 and prefix.len == 0) {
        gpa.free(prefix);
        gpa.free(messages);
        gpa.free(branch);
        return null;
    }

    var file_ops = FileOperations.init(gpa);
    errdefer file_ops.deinit();
    if (previous_index) |index| try extractPreviousFileOperations(gpa, branch[index].*, &file_ops);
    for (messages) |entry| try extractEntryFileOperations(gpa, entry.*, &file_ops);
    for (prefix) |entry| try extractEntryFileOperations(gpa, entry.*, &file_ops);

    const read_view = try sortedMapKeys(gpa, &file_ops.read);
    errdefer gpa.free(read_view);
    const written_view = try sortedMapKeys(gpa, &file_ops.written);
    errdefer gpa.free(written_view);
    const edited_view = try sortedMapKeys(gpa, &file_ops.edited);
    errdefer gpa.free(edited_view);

    return .{
        .gpa = gpa,
        .branch_entries = branch,
        .messages_to_summarize = messages,
        .turn_prefix_messages = prefix,
        .is_split_turn = cut.is_split_turn,
        .first_kept_entry_id = branch[cut.first_kept_entry_index].id,
        .tokens_before = tokens_before,
        .previous_summary = previous_summary,
        .settings = settings,
        .file_ops = file_ops,
        .read_view = read_view,
        .written_view = written_view,
        .edited_view = edited_view,
    };
}

fn extractPreviousFileOperations(gpa: std.mem.Allocator, entry: session_mod.SessionEntry, ops: *FileOperations) !void {
    if (entry.from_hook) return;
    const raw = entry.data_json orelse return;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    if (parsed.value.object.get("readFiles")) |value| if (value == .array) {
        for (value.array.items) |item| if (item == .string) try ops.addRead(item.string);
    };
    if (parsed.value.object.get("modifiedFiles")) |value| if (value == .array) {
        for (value.array.items) |item| if (item == .string) try ops.addEdited(item.string);
    };
}

fn extractEntryFileOperations(gpa: std.mem.Allocator, entry: session_mod.SessionEntry, ops: *FileOperations) !void {
    if (!std.mem.eql(u8, entry.role, "assistant")) return;
    const raw = entry.tool_calls_json orelse return;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .array) return;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const function = item.object.get("function") orelse continue;
        if (function != .object) continue;
        const name_value = function.object.get("name") orelse continue;
        if (name_value != .string) continue;
        const arguments_value = function.object.get("arguments") orelse continue;
        var argument_parse: ?std.json.Parsed(std.json.Value) = null;
        defer if (argument_parse) |*value| value.deinit();
        const arguments = switch (arguments_value) {
            .object => arguments_value,
            .string => blk: {
                argument_parse = std.json.parseFromSlice(std.json.Value, gpa, arguments_value.string, .{}) catch continue;
                break :blk argument_parse.?.value;
            },
            else => continue,
        };
        if (arguments != .object) continue;
        const path_value = arguments.object.get("path") orelse continue;
        if (path_value != .string) continue;
        if (std.mem.eql(u8, name_value.string, "read")) {
            try ops.addRead(path_value.string);
        } else if (std.mem.eql(u8, name_value.string, "write")) {
            try ops.addWritten(path_value.string);
        } else if (std.mem.eql(u8, name_value.string, "edit")) {
            try ops.addEdited(path_value.string);
        }
    }
}

const SUMMARIZATION_SYSTEM_PROMPT = "You are a context summarization assistant. Read the supplied conversation and output only the requested structured checkpoint. Do not continue the conversation or answer its questions.";

const SUMMARIZATION_PROMPT =
    \\The messages above are a conversation to summarize. Create a structured context checkpoint summary that another LLM will use to continue the work.
    \\
    \\Use this exact format:
    \\
    \\## Goal
    \\[What the user is trying to accomplish]
    \\
    \\## Constraints & Preferences
    \\- [Requirements and preferences]
    \\
    \\## Progress
    \\### Done
    \\- [x] [Completed work]
    \\
    \\### In Progress
    \\- [ ] [Current work]
    \\
    \\### Blocked
    \\- [Current blockers, or (none)]
    \\
    \\## Key Decisions
    \\- **[Decision]**: [Rationale]
    \\
    \\## Next Steps
    \\1. [What should happen next]
    \\
    \\## Critical Context
    \\- [Exact paths, APIs, errors, or data needed to continue]
    \\
    \\Keep each section concise. Preserve exact file paths, function names, commands, and error messages.
;

const UPDATE_SUMMARIZATION_PROMPT =
    \\The messages above are NEW conversation messages to incorporate into the existing summary in <previous-summary> tags.
    \\
    \\Update the structured summary. Preserve still-relevant goals, constraints, completed work, decisions, exact paths, function names, commands, and errors. Move completed items out of In Progress and refresh Next Steps.
    \\
    \\Use the same exact Goal / Constraints & Preferences / Progress / Key Decisions / Next Steps / Critical Context structure.
;

const TURN_PREFIX_SUMMARIZATION_PROMPT =
    \\This is the PREFIX of a turn that was too large to keep. The SUFFIX (recent work) remains in context.
    \\
    \\Summarize only what is needed to understand that retained suffix, using:
    \\
    \\## Original Request
    \\[What the user asked in this turn]
    \\
    \\## Early Progress
    \\- [Decisions and work completed in the prefix]
    \\
    \\## Context for Suffix
    \\- [Information needed to understand the retained work]
;

fn utf8Prefix(text: []const u8, max_bytes: usize) []const u8 {
    if (text.len <= max_bytes) return text;
    var end = max_bytes;
    while (end > 0 and !std.unicode.utf8ValidateSlice(text[0..end])) end -= 1;
    return text[0..end];
}

fn serializeEntries(gpa: std.mem.Allocator, entries: []const *const session_mod.SessionEntry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    for (entries) |entry| {
        if (!first) try out.writer.writeAll("\n\n");
        first = false;
        if (entry.entry_type == .branch_summary) {
            try out.writer.print("[Branch summary]: {s}", .{entry.content});
        } else if (entry.entry_type == .custom_message or std.mem.eql(u8, entry.role, "user") or std.mem.eql(u8, entry.role, "system")) {
            try out.writer.print("[User]: {s}", .{entry.content});
        } else if (std.mem.eql(u8, entry.role, "assistant")) {
            var wrote = false;
            if (entry.meta.thinking.len > 0) {
                try out.writer.print("[Assistant thinking]: {s}", .{entry.meta.thinking});
                wrote = true;
            }
            if (entry.content.len > 0) {
                if (wrote) try out.writer.writeAll("\n\n");
                try out.writer.print("[Assistant]: {s}", .{entry.content});
                wrote = true;
            }
            if (entry.tool_calls_json) |calls| {
                if (wrote) try out.writer.writeAll("\n\n");
                try out.writer.print("[Assistant tool calls]: {s}", .{calls});
            }
        } else if (std.mem.eql(u8, entry.role, "tool")) {
            const prefix = utf8Prefix(entry.content, TOOL_RESULT_MAX_CHARS);
            try out.writer.print("[Tool result]: {s}", .{prefix});
            if (prefix.len < entry.content.len)
                try out.writer.print("\n\n[... {d} more bytes truncated]", .{entry.content.len - prefix.len});
        } else if (std.mem.eql(u8, entry.role, "bashExecution")) {
            try out.writer.writeAll("[Bash execution]: ");
            if (entry.bash_command) |command| try out.writer.print("$ {s}\n", .{command});
            if (entry.bash_output) |output| try out.writer.writeAll(output) else try out.writer.writeAll(entry.content);
        } else {
            try out.writer.print("[{s}]: {s}", .{ entry.role, entry.content });
        }
    }
    return try out.toOwnedSlice();
}

fn summarizationMaxOutputTokens(reserve_tokens: u64, turn_prefix: bool) u64 {
    if (turn_prefix) return reserve_tokens / 2;
    // floor(0.8 * reserve_tokens) without overflowing u64.
    return (reserve_tokens / 5) * 4 + ((reserve_tokens % 5) * 4) / 5;
}

fn generatedSummary(
    gpa: std.mem.Allocator,
    material: []const u8,
    previous_summary: ?[]const u8,
    custom_instructions: ?[]const u8,
    turn_prefix: bool,
    opts: CompactOptions,
) !GeneratedSummary {
    if (opts.client == null) {
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        if (!turn_prefix and previous_summary != null) {
            try out.writer.writeAll(previous_summary.?);
            if (material.len > 0) try out.writer.writeAll("\n\n---\n\n");
        }
        try out.writer.writeAll(material);
        return .{ .text = try out.toOwnedSlice() };
    }

    var prompt: std.Io.Writer.Allocating = .init(gpa);
    defer prompt.deinit();
    try prompt.writer.print("<conversation>\n{s}\n</conversation>\n\n", .{material});
    if (!turn_prefix) {
        if (previous_summary) |previous| {
            try prompt.writer.print("<previous-summary>\n{s}\n</previous-summary>\n\n", .{previous});
        }
    }
    try prompt.writer.writeAll(if (turn_prefix) TURN_PREFIX_SUMMARIZATION_PROMPT else if (previous_summary != null) UPDATE_SUMMARIZATION_PROMPT else SUMMARIZATION_PROMPT);
    if (custom_instructions) |instructions| try prompt.writer.print("\n\nAdditional focus: {s}", .{instructions});

    const messages = [_]ai.ChatMessage{
        .{ .role = "system", .content = SUMMARIZATION_SYSTEM_PROMPT },
        .{ .role = "user", .content = prompt.written() },
    };
    var response = summarization.complete(gpa, &messages, .{
        .io = opts.io,
        .client = opts.client.?,
        .source = .compaction,
        .reason = opts.reason,
        .retry_enabled = opts.retry_enabled,
        .retry_max_retries = opts.retry_max_retries,
        .retry_base_delay_ms = opts.retry_base_delay_ms,
        .max_output_tokens = summarizationMaxOutputTokens(opts.settings.reserve_tokens, turn_prefix),
        .abort_flag = opts.abort_flag,
        .retry_abort_flag = opts.retry_abort_flag,
        .on_event = opts.on_retry_event,
        .event_ctx = opts.retry_event_ctx,
    }) catch |err| switch (err) {
        error.SummarizationCancelled => return error.CompactionCancelled,
        else => return err,
    };
    defer response.deinit(gpa);
    if (std.mem.eql(u8, response.stop_reason, "aborted")) return error.CompactionCancelled;
    if (std.mem.eql(u8, response.stop_reason, "error")) return error.SummarizationFailed;
    if (std.mem.trim(u8, response.content, " \t\r\n").len == 0) return error.EmptySummarization;
    return .{
        .text = try gpa.dupe(u8, response.content),
        .meta = try responseMeta(gpa, response),
    };
}

fn addMetaUsage(target: *session_mod.AssistantMeta, source: session_mod.AssistantMeta) void {
    target.usage_input +|= source.usage_input;
    target.usage_output +|= source.usage_output;
    target.usage_cache_read +|= source.usage_cache_read;
    target.usage_cache_write +|= source.usage_cache_write;
    if (source.usage_cache_write_1h) |value| target.usage_cache_write_1h = (target.usage_cache_write_1h orelse 0) +| value;
    if (source.usage_reasoning) |value| target.usage_reasoning = (target.usage_reasoning orelse 0) +| value;
    target.usage_total +|= source.usage_total;
    target.cost_input += source.cost_input;
    target.cost_output += source.cost_output;
    target.cost_cache_read += source.cost_cache_read;
    target.cost_cache_write += source.cost_cache_write;
    target.cost_total += source.cost_total;
}

fn fileLists(gpa: std.mem.Allocator, ops: *const FileOperations) !struct { read: [][]const u8, modified: [][]const u8 } {
    var modified_map = std.StringHashMap(void).init(gpa);
    defer modified_map.deinit();
    var written_it = ops.written.keyIterator();
    while (written_it.next()) |key| try modified_map.put(key.*, {});
    var edited_it = ops.edited.keyIterator();
    while (edited_it.next()) |key| try modified_map.put(key.*, {});

    var read_list: std.ArrayList([]const u8) = .empty;
    errdefer read_list.deinit(gpa);
    var read_it = ops.read.keyIterator();
    while (read_it.next()) |key| if (!modified_map.contains(key.*)) try read_list.append(gpa, key.*);
    std.mem.sort([]const u8, read_list.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    const modified = try sortedMapKeys(gpa, &modified_map);
    return .{ .read = try read_list.toOwnedSlice(gpa), .modified = modified };
}

fn detailsJson(gpa: std.mem.Allocator, read_files: []const []const u8, modified_files: []const []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"readFiles\":[");
    for (read_files, 0..) |path, index| {
        if (index > 0) try out.writer.writeByte(',');
        try std.json.Stringify.value(path, .{}, &out.writer);
    }
    try out.writer.writeAll("],\"modifiedFiles\":[");
    for (modified_files, 0..) |path, index| {
        if (index > 0) try out.writer.writeByte(',');
        try std.json.Stringify.value(path, .{}, &out.writer);
    }
    try out.writer.writeAll("]}");
    return try out.toOwnedSlice();
}

fn appendFileLists(gpa: std.mem.Allocator, summary: []const u8, read_files: []const []const u8, modified_files: []const []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll(summary);
    if (read_files.len > 0) {
        try out.writer.writeAll("\n\n<read-files>\n");
        for (read_files) |path| try out.writer.print("{s}\n", .{path});
        try out.writer.writeAll("</read-files>");
    }
    if (modified_files.len > 0) {
        try out.writer.writeAll("\n\n<modified-files>\n");
        for (modified_files) |path| try out.writer.print("{s}\n", .{path});
        try out.writer.writeAll("</modified-files>");
    }
    return try out.toOwnedSlice();
}

/// Append an upstream-compatible compaction boundary without deleting prior
/// history. Cut selection is token-budgeted and may split a single oversized
/// turn at an assistant boundary while retaining all following tool results.
pub fn compact(sess: *session_mod.Session, opts: CompactOptions) !void {
    if (!opts.settings.enabled) return;
    var preparation = (try prepareCompaction(sess.gpa, sess, opts.settings)) orelse return;
    defer preparation.deinit();
    const gpa = sess.gpa;

    var hook_result: ?BeforeHookResult = null;
    defer if (hook_result) |*result| result.deinit(gpa);
    if (opts.before_hook_fn) |before_hook| {
        hook_result = try before_hook(opts.hook_ctx, gpa, sess, preparation.hookView(opts));
        if (hook_result) |*result| {
            if (result.cancel) return error.CompactionCancelled;
            if (result.compaction) |*replacement| {
                if (std.mem.trim(u8, replacement.summary, " \t\r\n").len == 0) return error.EmptySummarization;
                if (!entryIsOnBranch(preparation.branch_entries, replacement.first_kept_entry_id)) return error.InvalidFirstKeptEntry;
                const id = try sess.appendCompaction(
                    replacement.summary,
                    replacement.first_kept_entry_id,
                    replacement.tokens_before,
                    replacement.details_json,
                    true,
                    replacement.meta,
                );
                if (opts.after_hook_fn) |after_hook| {
                    const entry = sess.getEntry(id).?;
                    after_hook(opts.hook_ctx, gpa, entry, opts.reason, opts.will_retry, true) catch {};
                }
                return;
            }
        }
    }

    const history_material = try serializeEntries(gpa, preparation.messages_to_summarize);
    defer gpa.free(history_material);
    var history = if (preparation.messages_to_summarize.len > 0)
        try generatedSummary(gpa, history_material, preparation.previous_summary, opts.custom_instructions, false, opts)
    else
        GeneratedSummary{ .text = try gpa.dupe(u8, "No prior history.") };
    defer history.deinit(gpa);

    var merged_text: []u8 = undefined;
    var merged_meta: session_mod.AssistantMeta = .{};
    defer merged_meta.deinit(gpa);
    if (preparation.is_split_turn and preparation.turn_prefix_messages.len > 0) {
        const prefix_material = try serializeEntries(gpa, preparation.turn_prefix_messages);
        defer gpa.free(prefix_material);
        var prefix = try generatedSummary(gpa, prefix_material, null, null, true, opts);
        defer prefix.deinit(gpa);
        merged_text = try std.fmt.allocPrint(gpa, "{s}\n\n---\n\n**Turn Context (split turn):**\n\n{s}", .{ history.text, prefix.text });
        merged_meta = try prefix.meta.dupe(gpa);
        addMetaUsage(&merged_meta, history.meta);
    } else {
        merged_text = try gpa.dupe(u8, history.text);
        merged_meta = try history.meta.dupe(gpa);
    }
    defer gpa.free(merged_text);

    const lists = try fileLists(gpa, &preparation.file_ops);
    defer gpa.free(lists.read);
    defer gpa.free(lists.modified);
    const final_summary = try appendFileLists(gpa, merged_text, lists.read, lists.modified);
    defer gpa.free(final_summary);
    const details = try detailsJson(gpa, lists.read, lists.modified);
    defer gpa.free(details);

    const id = try sess.appendCompaction(
        final_summary,
        preparation.first_kept_entry_id,
        preparation.tokens_before,
        details,
        false,
        merged_meta,
    );
    if (opts.after_hook_fn) |after_hook| {
        const entry = sess.getEntry(id).?;
        after_hook(opts.hook_ctx, gpa, entry, opts.reason, opts.will_retry, false) catch {};
    }
}

fn entryIsOnBranch(branch: []const *const session_mod.SessionEntry, id: []const u8) bool {
    for (branch) |entry| if (std.mem.eql(u8, entry.id, id)) return true;
    return false;
}

fn responseMeta(gpa: std.mem.Allocator, response: ai.ModelResponse) !session_mod.AssistantMeta {
    return .{
        .thinking = if (response.thinking.len > 0) try gpa.dupe(u8, response.thinking) else "",
        .thinking_signature = if (response.thinking_signature.len > 0) try gpa.dupe(u8, response.thinking_signature) else "",
        .thinking_redacted = response.thinking_redacted,
        .provider = if (response.provider.len > 0) try gpa.dupe(u8, response.provider) else "",
        .api = if (response.api.len > 0) try gpa.dupe(u8, response.api) else "",
        .model = if (response.model.len > 0) try gpa.dupe(u8, response.model) else "",
        .response_id = if (response.response_id.len > 0) try gpa.dupe(u8, response.response_id) else "",
        .response_model = if (response.response_model.len > 0) try gpa.dupe(u8, response.response_model) else "",
        .diagnostics_json = if (response.diagnostics_json.len > 0) try gpa.dupe(u8, response.diagnostics_json) else "",
        .error_message = if (response.error_message.len > 0) try gpa.dupe(u8, response.error_message) else "",
        .raw_stop_reason = if (response.raw_stop_reason.len > 0) try gpa.dupe(u8, response.raw_stop_reason) else "",
        .stop_reason = if (response.stop_reason.len > 0) try gpa.dupe(u8, response.stop_reason) else "",
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
    };
}

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

test "summarization output budgets match upstream reserve fractions" {
    try std.testing.expectEqual(@as(u64, 13_107), summarizationMaxOutputTokens(16_384, false));
    try std.testing.expectEqual(@as(u64, 8_192), summarizationMaxOutputTokens(16_384, true));
    try std.testing.expectEqual(@as(u64, 3), summarizationMaxOutputTokens(4, false));
    try std.testing.expectEqual(@as(u64, 2), summarizationMaxOutputTokens(5, true));
}

test "compaction threshold uses reserve tokens without underflow" {
    try std.testing.expect(!shouldCompact(90, 100, .{ .reserve_tokens = 10 }));
    try std.testing.expect(shouldCompact(91, 100, .{ .reserve_tokens = 10 }));
    try std.testing.expect(!shouldCompact(90, 100, .{ .reserve_tokens = 9 }));
    try std.testing.expect(shouldCompact(1, 10, .{ .reserve_tokens = 20 }));
    try std.testing.expect(!shouldCompact(1000, 100, .{ .enabled = false, .reserve_tokens = 1 }));
    try std.testing.expect(!shouldCompact(1000, 0, .{}));
}

test "new compaction prefix invalidates stale retained assistant usage" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "stale-usage", "/tmp");
    defer sess.deinit();

    const user = try sess.appendMessage(null, "user", "old request", null, null);
    const assistant = try sess.appendMessageMeta(user, "assistant", "old answer", null, null, null, .{
        .stop_reason = "stop",
        .usage_total = 90_000,
    });
    const tail = try sess.appendMessage(assistant, "user", "tiny retained tail", null, null);
    _ = tail;
    _ = try sess.appendCompaction("fresh compact summary", assistant, 90_010, null, false, .{});

    const estimated = try estimateSessionContextTokens(gpa, &sess);
    try std.testing.expect(estimated < 100);
    try std.testing.expect(estimated != 90_000);
}

test "token cut never begins at a tool result and reports split-turn prefix" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "split-cut", "/tmp");
    defer sess.deinit();

    const user = try sess.appendMessage(null, "user", "request", null, null);
    const assistant = try sess.appendMessageMeta(user, "assistant", "call", null, "[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"src/main.zig\\\"}\"}}]", null, .{});
    const tool = try sess.appendToolResult(assistant, "tool output long enough", "c1", "read");
    _ = try sess.appendMessage(tool, "assistant", "continued answer", null, null);

    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);
    const cut = findCutPoint(&sess, branch, 0, branch.len, 8);
    try std.testing.expect(!std.mem.eql(u8, branch[cut.first_kept_entry_index].role, "tool"));
    if (cut.is_split_turn) {
        try std.testing.expect(cut.turn_start_index != null);
        try std.testing.expectEqualStrings("request", branch[cut.turn_start_index.?].content);
    }
}

test "compact keeps recent messages" {
    const gpa = std.testing.allocator;
    var s = try session_mod.Session.init(gpa, "c1", "/tmp");
    defer s.deinit();

    var parent: ?[]const u8 = null;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const role = if (i % 2 == 0) "user" else "assistant";
        const content = try std.fmt.allocPrint(gpa, "msg-{d}", .{i});
        defer gpa.free(content);
        parent = try s.appendMessage(parent, role, content, null, null);
    }
    try std.testing.expectEqual(@as(usize, 10), s.entries.items.len);

    try compact(&s, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 7 } });
    // Full history remains durable; provider context is summary + 4 recent.
    try std.testing.expectEqual(@as(usize, 11), s.entries.items.len);
    const boundary = s.entries.items[10];
    try std.testing.expectEqual(session_mod.EntryType.compaction, boundary.entry_type);
    try std.testing.expectEqualStrings("msg-6", s.getEntry(boundary.first_kept_entry_id.?).?.content);
    const context = try s.contextEntries(gpa);
    defer gpa.free(context);
    try std.testing.expectEqual(@as(usize, 5), context.len);
    try std.testing.expectEqualStrings(boundary.id, context[0].id);
    try std.testing.expect(std.mem.indexOf(u8, context[0].content, "msg-0") != null);
    try std.testing.expectEqualStrings("msg-6", context[1].content);
}

test "compact rejects an empty retained tail" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-zero", "/tmp");
    defer sess.deinit();
    _ = try sess.appendMessage(null, "user", "one", null, null);
    try std.testing.expectError(error.InvalidKeepRecentTokens, compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 0 } }));
    try std.testing.expectEqual(@as(usize, 1), sess.entries.items.len);
}

test "repeated compaction keeps the complete append-only branch" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-repeat", "/tmp");
    defer sess.deinit();

    var parent: ?[]const u8 = null;
    for (0..8) |index| {
        const text = try std.fmt.allocPrint(gpa, "turn-{d}", .{index});
        defer gpa.free(text);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
    }
    try compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 8 } });
    const first_boundary_id = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(first_boundary_id);
    _ = try sess.appendMessage(sess.lastEntryId(), "user", "after-first", null, null);
    _ = try sess.appendMessage(sess.lastEntryId(), "assistant", "after-first-answer", null, null);
    const before_second = sess.entries.items.len;
    try compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 10 } });

    try std.testing.expectEqual(before_second + 1, sess.entries.items.len);
    try std.testing.expect(sess.getEntry(first_boundary_id) != null);
    const latest = sess.entries.items[sess.entries.items.len - 1];
    try std.testing.expectEqual(session_mod.EntryType.compaction, latest.entry_type);
    try std.testing.expect(!std.mem.eql(u8, first_boundary_id, latest.id));
    const context = try sess.contextEntries(gpa);
    defer gpa.free(context);
    // The previous boundary remains durable, while the latest token-budgeted
    // projection keeps only the new turn after the replacement summary.
    try std.testing.expectEqual(@as(usize, 3), context.len);
    try std.testing.expectEqualStrings(latest.id, context[0].id);
    try std.testing.expectEqualStrings("after-first", context[1].content);
    try std.testing.expectEqualStrings("after-first-answer", context[2].content);
}

test "compaction is append-only and repeated unchanged compaction is a no-op" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-repeat", "/tmp");
    defer sess.deinit();

    var parent: ?[]const u8 = null;
    for (0..6) |index| {
        const text = try std.fmt.allocPrint(gpa, "repeat-{d}", .{index});
        defer gpa.free(text);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
    }
    try compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 4 } });
    const after_first = sess.entries.items.len;
    const first_tip = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(first_tip);
    try compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 4 } });
    try std.testing.expectEqual(after_first, sess.entries.items.len);
    try std.testing.expectEqualStrings(first_tip, sess.lastEntryId().?);
}

test "compaction preserves rich recent session entries" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-rich", "/tmp");
    defer sess.deinit();

    var parent: ?[]const u8 = null;
    parent = try sess.appendMessage(parent, "user", "old user", null, null);
    parent = try sess.appendMessage(parent, "assistant", "old assistant", null, null);
    parent = try sess.appendMessage(parent, "user", "old user two", null, null);
    parent = try sess.appendMessageMeta(parent, "assistant", "kept assistant", null, null, null, .{
        .thinking = "kept thought",
        .provider = "provider-rich",
        .model = "model-rich",
        .stop_reason = "stop",
        .usage_input = 42,
        .cost_total = 0.75,
    });
    const images = [_]ai.ChatImage{
        .{ .data_b64 = "AQ==", .mime_type = "image/jpeg" },
        .{ .data_b64 = "Ag==", .mime_type = "image/webp" },
    };
    parent = try sess.appendToolResultStatusWithImages(parent, "tool kept", "call-kept", "capture", false, &.{ "next-a", "next-b" }, "AA==", "image/png", &images);
    _ = try sess.appendBashExecution(parent, "printf kept", "kept output", 0, false, true, "/tmp/kept.log", true);

    try compact(&sess, .{ .io = std.testing.io, .settings = .{ .keep_recent_tokens = 3_605 } });
    try std.testing.expectEqual(@as(usize, 7), sess.entries.items.len);
    const context = try sess.contextEntries(gpa);
    defer gpa.free(context);
    try std.testing.expectEqual(@as(usize, 4), context.len);
    const assistant = context[1].*;
    try std.testing.expectEqualStrings("kept assistant", assistant.content);
    try std.testing.expectEqualStrings("kept thought", assistant.meta.thinking);
    try std.testing.expectEqualStrings("provider-rich", assistant.meta.provider);
    try std.testing.expectEqual(@as(u64, 42), assistant.meta.usage_input);
    try std.testing.expectEqual(@as(f64, 0.75), assistant.meta.cost_total);

    const tool = context[2].*;
    try std.testing.expectEqualStrings("call-kept", tool.tool_call_id.?);
    try std.testing.expectEqualStrings("capture", tool.tool_name.?);
    try std.testing.expectEqualStrings("AA==", tool.image_b64.?);
    try std.testing.expectEqual(@as(usize, 2), tool.images.len);
    try std.testing.expectEqualStrings("image/webp", tool.images[1].mime_type);
    try std.testing.expectEqual(@as(usize, 2), tool.added_tool_names.len);
    try std.testing.expectEqualStrings("next-b", tool.added_tool_names[1]);

    const bash = context[3].*;
    try std.testing.expectEqualStrings("printf kept", bash.bash_command.?);
    try std.testing.expectEqualStrings("kept output", bash.bash_output.?);
    try std.testing.expect(bash.bash_truncated);
    try std.testing.expect(bash.bash_exclude_from_context);
    try std.testing.expectEqualStrings("/tmp/kept.log", bash.bash_full_output_path.?);
    // Durable ancestry is unchanged; only the context projection is compacted.
    try std.testing.expectEqualStrings(sess.entries.items[2].id, assistant.parent_id.?);
    try std.testing.expectEqual(session_mod.EntryType.compaction, context[0].entry_type);
}

test "model compaction retries transient summarization and emits canonical sequence" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\ {"content":"terminated: upstream stream ended","stop_reason":"error","tool_calls":[]},
        \\ {"content":"model summary 162","stop_reason":"stop","tool_calls":[],"provider":"mock-provider","model":"mock-summary"}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "compact-retry", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..6) |index| {
        const content = try std.fmt.allocPrint(gpa, "message-{d}", .{index});
        defer gpa.free(content);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", content, null, null);
    }

    const Probe = struct {
        kinds: [3]summarization.EventKind = undefined,
        count: usize = 0,
        source: summarization.Source = .branch_summary,
        reason: summarization.Reason = .navigation,
        fn onEvent(raw: ?*anyopaque, event: summarization.Event) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (self.count < self.kinds.len) self.kinds[self.count] = event.kind;
            self.count += 1;
            self.source = event.source;
            self.reason = event.reason;
        }
    };
    var probe = Probe{};
    try compact(&sess, .{
        .io = std.testing.io,
        .settings = .{ .keep_recent_tokens = 4 },
        .client = model.client(),
        .reason = .threshold,
        .retry_base_delay_ms = 0,
        .on_retry_event = Probe.onEvent,
        .retry_event_ctx = &probe,
    });
    try std.testing.expectEqual(@as(usize, 2), model.index);
    try std.testing.expectEqual(@as(usize, 3), probe.count);
    try std.testing.expectEqual(summarization.EventKind.retry_scheduled, probe.kinds[0]);
    try std.testing.expectEqual(summarization.EventKind.retry_attempt_start, probe.kinds[1]);
    try std.testing.expectEqual(summarization.EventKind.retry_finished, probe.kinds[2]);
    try std.testing.expectEqual(summarization.Source.compaction, probe.source);
    try std.testing.expectEqual(summarization.Reason.threshold, probe.reason);
    const boundary = sess.entries.items[sess.entries.items.len - 1];
    try std.testing.expectEqual(session_mod.EntryType.compaction, boundary.entry_type);
    try std.testing.expect(std.mem.indexOf(u8, boundary.content, "model summary 162") != null);
    try std.testing.expectEqualStrings("mock", boundary.meta.provider);
    try std.testing.expectEqualStrings("mock", boundary.meta.model);
}

test "model compaction fails without mutating session on terminal summarization error" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    const script =
        \\[
        \\ {"content":"429 insufficient_quota billing exhausted","stop_reason":"error","tool_calls":[]},
        \\ {"content":"must not run","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var sess = try session_mod.Session.init(gpa, "compact-terminal", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..5) |index| {
        const content = try std.fmt.allocPrint(gpa, "original-{d}", .{index});
        defer gpa.free(content);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", content, null, null);
    }
    const before_tip = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(before_tip);
    try std.testing.expectError(error.SummarizationFailed, compact(&sess, .{
        .io = std.testing.io,
        .settings = .{ .keep_recent_tokens = 4 },
        .client = model.client(),
        .retry_base_delay_ms = 0,
    }));
    try std.testing.expectEqual(@as(usize, 1), model.index);
    try std.testing.expectEqual(@as(usize, 5), sess.entries.items.len);
    try std.testing.expectEqualStrings(before_tip, sess.lastEntryId().?);
    try std.testing.expectEqualStrings("original-0", sess.entries.items[0].content);
}

test "session compaction hooks can replace summary and receive the saved boundary" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-hook-164", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..6) |index| {
        const text = try std.fmt.allocPrint(gpa, "hook-message-{d}", .{index});
        defer gpa.free(text);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
    }

    const Probe = struct {
        before_count: usize = 0,
        after_count: usize = 0,
        saw_reason: summarization.Reason = .manual,
        saw_will_retry: bool = false,
        saw_from_extension: bool = false,
        saw_branch_len: usize = 0,

        fn before(raw: ?*anyopaque, allocator: std.mem.Allocator, _: *const session_mod.Session, preparation: HookPreparation) anyerror!?BeforeHookResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.before_count += 1;
            self.saw_reason = preparation.reason;
            self.saw_will_retry = preparation.will_retry;
            self.saw_branch_len = preparation.branch_entries.len;
            return .{ .compaction = .{
                .summary = try allocator.dupe(u8, "extension summary 164"),
                .first_kept_entry_id = try allocator.dupe(u8, preparation.first_kept_entry_id),
                .tokens_before = preparation.tokens_before + 7,
                .details_json = try allocator.dupe(u8, "{\"extension\":164}"),
                .meta = .{ .usage_input = 10, .usage_output = 20, .usage_total = 30, .cost_total = 1.25 },
            } };
        }

        fn after(raw: ?*anyopaque, _: std.mem.Allocator, entry: *const session_mod.SessionEntry, reason: summarization.Reason, will_retry: bool, from_extension: bool) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.after_count += 1;
            self.saw_reason = reason;
            self.saw_will_retry = will_retry;
            self.saw_from_extension = from_extension;
            if (!std.mem.eql(u8, entry.content, "extension summary 164")) return error.UnexpectedSummary;
        }
    };
    var probe = Probe{};
    try compact(&sess, .{
        .io = std.testing.io,
        .settings = .{ .keep_recent_tokens = 4 },
        .reason = .overflow,
        .hook_ctx = &probe,
        .before_hook_fn = Probe.before,
        .after_hook_fn = Probe.after,
        .will_retry = true,
    });

    try std.testing.expectEqual(@as(usize, 1), probe.before_count);
    try std.testing.expectEqual(@as(usize, 1), probe.after_count);
    try std.testing.expectEqual(@as(usize, 6), probe.saw_branch_len);
    try std.testing.expectEqual(summarization.Reason.overflow, probe.saw_reason);
    try std.testing.expect(probe.saw_will_retry);
    try std.testing.expect(probe.saw_from_extension);
    const boundary = sess.getEntry(sess.lastEntryId().?).?;
    try std.testing.expectEqual(session_mod.EntryType.compaction, boundary.entry_type);
    try std.testing.expect(boundary.from_hook);
    try std.testing.expectEqualStrings("extension summary 164", boundary.content);
    try std.testing.expectEqualStrings("{\"extension\":164}", boundary.data_json.?);
    try std.testing.expectEqual(@as(u64, 10), boundary.meta.usage_input);
    try std.testing.expectEqual(@as(u64, 30), boundary.meta.usage_total);
    try std.testing.expectEqual(@as(f64, 1.25), boundary.meta.cost_total);
}

test "session_before_compact cancellation leaves the append-only tree unchanged" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "compact-cancel-164", "/tmp");
    defer sess.deinit();
    var parent: ?[]const u8 = null;
    for (0..5) |index| {
        const text = try std.fmt.allocPrint(gpa, "cancel-{d}", .{index});
        defer gpa.free(text);
        parent = try sess.appendMessage(parent, if (index % 2 == 0) "user" else "assistant", text, null, null);
    }
    const tip = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(tip);
    const Hook = struct {
        fn before(_: ?*anyopaque, _: std.mem.Allocator, _: *const session_mod.Session, _: HookPreparation) anyerror!?BeforeHookResult {
            return .{ .cancel = true };
        }
    };
    try std.testing.expectError(error.CompactionCancelled, compact(&sess, .{
        .io = std.testing.io,
        .settings = .{ .keep_recent_tokens = 4 },
        .before_hook_fn = Hook.before,
    }));
    try std.testing.expectEqual(@as(usize, 5), sess.entries.items.len);
    try std.testing.expectEqualStrings(tip, sess.lastEntryId().?);
}
