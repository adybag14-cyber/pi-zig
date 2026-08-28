//! Summarize the abandoned side of a session tree before navigating elsewhere.
const std = @import("std");
const session_mod = @import("session.zig");
const summarization = @import("summarization.zig");
const compaction = @import("compaction.zig");
const ai = @import("../ai/root.zig");

const Io = std.Io;

const SUMMARY_PREAMBLE =
    "The user explored a different conversation branch before returning here.\n" ++
    "Summary of that exploration:\n\n";

const SUMMARIZATION_SYSTEM_PROMPT =
    "You are a context summarization assistant. Your task is to read a conversation between a user and an AI assistant, then produce a structured summary following the exact format specified.\n\n" ++
    "Do NOT continue the conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary.";

const SUMMARY_PROMPT =
    \\Create a structured summary of this conversation branch for context when returning later.
    \\
    \\Use this EXACT format:
    \\
    \\## Goal
    \\[What was the user trying to accomplish in this branch?]
    \\
    \\## Constraints & Preferences
    \\- [Any constraints, preferences, or requirements mentioned]
    \\- [Or "(none)" if none were mentioned]
    \\
    \\## Progress
    \\### Done
    \\- [x] [Completed tasks/changes]
    \\
    \\### In Progress
    \\- [ ] [Work that was started but not finished]
    \\
    \\### Blocked
    \\- [Issues preventing progress, if any]
    \\
    \\## Key Decisions
    \\- **[Decision]**: [Brief rationale]
    \\
    \\## Next Steps
    \\1. [What should happen next to continue this work]
    \\
    \\Keep each section concise. Preserve exact file paths, function names, and error messages.
;

pub const Options = struct {
    io: Io,
    /// Required only when `summarize` is true and no extension supplies a
    /// complete summary replacement.
    client: ?ai.ModelClient = null,
    target_id: []const u8,
    summarize: bool = true,
    custom_instructions: ?[]const u8 = null,
    replace_instructions: bool = false,
    label: ?[]const u8 = null,
    /// Active model context window and reserved prompt/response capacity.
    /// A zero context window uses the original 128k fallback.
    context_window: u64 = 128_000,
    reserve_tokens: u64 = 16_384,
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
};

pub const Result = struct {
    summary_entry_id: ?[]const u8 = null,
    common_ancestor_id: ?[]const u8 = null,
    summarized_entries: usize = 0,
    /// When the selected target is a user/custom message, upstream navigation
    /// branches from its parent and returns the selected text to the editor.
    editor_text: ?[]const u8 = null,
    cancelled: bool = false,
    from_extension: bool = false,
};

/// Owned extension-supplied summary returned by `session_before_tree`.
pub const HookSummary = struct {
    summary: []u8,
    details_json: ?[]u8 = null,
    meta: session_mod.AssistantMeta = .{},

    pub fn deinit(self: *HookSummary, gpa: std.mem.Allocator) void {
        gpa.free(self.summary);
        if (self.details_json) |value| gpa.free(value);
        self.meta.deinit(gpa);
        self.* = undefined;
    }
};

pub const HookPreparation = struct {
    target_id: []const u8,
    old_leaf_id: ?[]const u8,
    common_ancestor_id: ?[]const u8,
    entries_to_summarize: []const *const session_mod.SessionEntry,
    user_wants_summary: bool,
    custom_instructions: ?[]const u8,
    replace_instructions: bool,
    label: ?[]const u8,
};

pub const BeforeHookResult = struct {
    cancel: bool = false,
    summary: ?HookSummary = null,
    custom_instructions: ?[]u8 = null,
    replace_instructions: ?bool = null,
    label: ?[]u8 = null,

    pub fn deinit(self: *BeforeHookResult, gpa: std.mem.Allocator) void {
        if (self.summary) |*value| value.deinit(gpa);
        if (self.custom_instructions) |value| gpa.free(value);
        if (self.label) |value| gpa.free(value);
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
    new_leaf_id: ?[]const u8,
    old_leaf_id: ?[]const u8,
    summary_entry: ?*const session_mod.SessionEntry,
    from_extension: bool,
) anyerror!void;

pub const Collected = struct {
    entries: []const *const session_mod.SessionEntry,
    common_ancestor_id: ?[]const u8,

    pub fn deinit(self: *Collected, gpa: std.mem.Allocator) void {
        gpa.free(self.entries);
        self.* = undefined;
    }
};

/// Collect entries on the current path after its deepest common ancestor with
/// `target_id`, preserving chronological order. Compaction and nested branch
/// summaries remain in the material so repeated navigation retains context.
pub fn collectEntries(
    gpa: std.mem.Allocator,
    sess: *const session_mod.Session,
    old_tip_id: ?[]const u8,
    target_id: []const u8,
) !Collected {
    if (sess.getEntry(target_id) == null) return error.UnknownEntry;
    const old_tip = old_tip_id orelse return .{
        .entries = try gpa.alloc(*const session_mod.SessionEntry, 0),
        .common_ancestor_id = null,
    };

    const old_path = try sess.branchEntriesAt(gpa, old_tip);
    defer gpa.free(old_path);
    const target_path = try sess.branchEntriesAt(gpa, target_id);
    defer gpa.free(target_path);

    var old_ids = std.StringHashMap(void).init(gpa);
    defer old_ids.deinit();
    for (old_path) |entry| try old_ids.put(entry.id, {});

    var common: ?[]const u8 = null;
    var index = target_path.len;
    while (index > 0) {
        index -= 1;
        if (old_ids.contains(target_path[index].id)) {
            common = target_path[index].id;
            break;
        }
    }

    var collected: std.ArrayList(*const session_mod.SessionEntry) = .empty;
    errdefer collected.deinit(gpa);
    var current: ?[]const u8 = old_tip;
    var seen = std.StringHashMap(void).init(gpa);
    defer seen.deinit();
    while (current) |id| {
        if (common) |ancestor| if (std.mem.eql(u8, id, ancestor)) break;
        if (seen.contains(id)) return error.ParentCycle;
        try seen.put(id, {});
        const entry = sess.getEntry(id) orelse return error.UnknownEntry;
        try collected.append(gpa, entry);
        current = entry.parent_id;
    }
    std.mem.reverse(*const session_mod.SessionEntry, collected.items);
    return .{
        .entries = try collected.toOwnedSlice(gpa),
        .common_ancestor_id = common,
    };
}

fn targetPosition(entry: *const session_mod.SessionEntry) struct { parent: ?[]const u8, editor_text: ?[]const u8 } {
    if ((entry.entry_type == .message and std.mem.eql(u8, entry.role, "user")) or entry.entry_type == .custom_message) {
        return .{ .parent = entry.parent_id, .editor_text = entry.content };
    }
    return .{ .parent = entry.id, .editor_text = null };
}

fn usefulEntry(entry: *const session_mod.SessionEntry) bool {
    return switch (entry.entry_type) {
        .message => !std.mem.eql(u8, entry.role, "tool"),
        .compaction, .branch_summary, .custom_message => true,
        else => false,
    };
}

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

    fn add(self: *FileOperations, map: *std.StringHashMap(void), path: []const u8) !void {
        if (path.len == 0 or map.contains(path)) return;
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        try map.put(owned, {});
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

pub const BranchPreparation = struct {
    gpa: std.mem.Allocator,
    entries: []const *const session_mod.SessionEntry,
    total_tokens: u64,
    token_budget: u64,
    file_ops: FileOperations,
    read_files: [][]const u8,
    modified_files: [][]const u8,

    pub fn deinit(self: *BranchPreparation) void {
        self.gpa.free(self.entries);
        self.gpa.free(self.read_files);
        self.gpa.free(self.modified_files);
        self.file_ops.deinit();
        self.* = undefined;
    }
};

fn addNestedSummaryFileOperations(gpa: std.mem.Allocator, entry: session_mod.SessionEntry, ops: *FileOperations) !void {
    if (entry.entry_type != .branch_summary or entry.from_hook) return;
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

fn addAssistantFileOperations(gpa: std.mem.Allocator, entry: session_mod.SessionEntry, ops: *FileOperations) !void {
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
        const arguments_value = function.object.get("arguments") orelse continue;
        if (name_value != .string) continue;

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

fn buildFileLists(gpa: std.mem.Allocator, ops: *const FileOperations) !struct { read: [][]const u8, modified: [][]const u8 } {
    var modified_map = std.StringHashMap(void).init(gpa);
    defer modified_map.deinit();
    var written = ops.written.keyIterator();
    while (written.next()) |key| try modified_map.put(key.*, {});
    var edited = ops.edited.keyIterator();
    while (edited.next()) |key| try modified_map.put(key.*, {});

    var read_list: std.ArrayList([]const u8) = .empty;
    errdefer read_list.deinit(gpa);
    var read = ops.read.keyIterator();
    while (read.next()) |key| if (!modified_map.contains(key.*)) try read_list.append(gpa, key.*);
    std.mem.sort([]const u8, read_list.items, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.less);
    return .{
        .read = try read_list.toOwnedSlice(gpa),
        .modified = try sortedMapKeys(gpa, &modified_map),
    };
}

/// Prepare abandoned branch entries using the original newest-first token
/// budget. Nested pi-generated summaries contribute cumulative file metadata
/// even when their text falls outside the request budget.
pub fn prepareBranchEntries(
    gpa: std.mem.Allocator,
    entries: []const *const session_mod.SessionEntry,
    context_window_value: u64,
    reserve_tokens: u64,
) !BranchPreparation {
    const context_window = if (context_window_value == 0) 128_000 else context_window_value;
    const token_budget = context_window -| reserve_tokens;
    var ops = FileOperations.init(gpa);
    errdefer ops.deinit();

    for (entries) |entry| try addNestedSummaryFileOperations(gpa, entry.*, &ops);

    var newest_first: std.ArrayList(*const session_mod.SessionEntry) = .empty;
    defer newest_first.deinit(gpa);
    var total_tokens: u64 = 0;
    var index = entries.len;
    while (index > 0) {
        index -= 1;
        const entry = entries[index];
        if (!usefulEntry(entry)) continue;
        // Match upstream: file operations are cumulative for every visited
        // assistant message, including the first message that exceeds the
        // newest-first token budget.
        try addAssistantFileOperations(gpa, entry.*, &ops);
        const tokens = compaction.estimateEntryTokens(entry.*);
        if (token_budget > 0 and total_tokens +| tokens > token_budget) {
            const important_summary = entry.entry_type == .compaction or entry.entry_type == .branch_summary;
            const ninety_percent = @divFloor(token_budget *| 9, 10);
            if (important_summary and total_tokens < ninety_percent) {
                try newest_first.append(gpa, entry);
                total_tokens +|= tokens;
            }
            break;
        }
        try newest_first.append(gpa, entry);
        total_tokens +|= tokens;
    }
    std.mem.reverse(*const session_mod.SessionEntry, newest_first.items);
    const lists = try buildFileLists(gpa, &ops);
    errdefer {
        gpa.free(lists.read);
        gpa.free(lists.modified);
    }
    return .{
        .gpa = gpa,
        .entries = try newest_first.toOwnedSlice(gpa),
        .total_tokens = total_tokens,
        .token_budget = token_budget,
        .file_ops = ops,
        .read_files = lists.read,
        .modified_files = lists.modified,
    };
}

fn appendToolCalls(gpa: std.mem.Allocator, writer: *std.Io.Writer, raw: []const u8) !void {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch {
        try writer.writeAll(raw);
        return;
    };
    defer parsed.deinit();
    if (parsed.value != .array) {
        try writer.writeAll(raw);
        return;
    }
    var first = true;
    for (parsed.value.array.items) |item| {
        if (item != .object) continue;
        const function = item.object.get("function") orelse continue;
        if (function != .object) continue;
        const name = function.object.get("name") orelse continue;
        const arguments = function.object.get("arguments") orelse continue;
        if (name != .string) continue;
        if (!first) try writer.writeAll("; ");
        first = false;
        try writer.print("{s}(", .{name.string});
        switch (arguments) {
            .string => try writer.writeAll(arguments.string),
            else => try std.json.Stringify.value(arguments, .{}, writer),
        }
        try writer.writeByte(')');
    }
    if (first) try writer.writeAll(raw);
}

fn serializeConversationMaterial(
    gpa: std.mem.Allocator,
    entries: []const *const session_mod.SessionEntry,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    var first = true;
    for (entries) |entry| {
        if (!first) try out.writer.writeAll("\n\n");
        first = false;
        if (entry.entry_type == .compaction) {
            try out.writer.print("[Compaction summary]: {s}", .{entry.content});
        } else if (entry.entry_type == .branch_summary) {
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
                try out.writer.writeAll("[Assistant tool calls]: ");
                try appendToolCalls(gpa, &out.writer, calls);
            }
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

fn responseMeta(gpa: std.mem.Allocator, response: ai.ModelResponse) !session_mod.AssistantMeta {
    return .{
        .thinking = if (response.thinking.len > 0) try gpa.dupe(u8, response.thinking) else "",
        .thinking_signature = if (response.thinking_signature.len > 0) try gpa.dupe(u8, response.thinking_signature) else "",
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

/// Summarize the abandoned branch, switch to the selected tree position, and
/// append one branch_summary child at the new position. Selecting a user/custom
/// message mirrors upstream behavior by branching from its parent and returning
/// its text for editor prefill.
pub fn summarizeAndSwitch(sess: *session_mod.Session, options: Options) !Result {
    const gpa = sess.gpa;
    const target = sess.getEntry(options.target_id) orelse return error.UnknownEntry;
    const old_tip_owned = if (sess.lastEntryId()) |value| try gpa.dupe(u8, value) else null;
    defer if (old_tip_owned) |value| gpa.free(value);
    if (old_tip_owned) |old| if (std.mem.eql(u8, old, options.target_id)) return .{};

    var collected = try collectEntries(gpa, sess, old_tip_owned, options.target_id);
    defer collected.deinit(gpa);
    const position = targetPosition(target);

    var hook_result: ?BeforeHookResult = null;
    defer if (hook_result) |*result| result.deinit(gpa);
    var custom_instructions = options.custom_instructions;
    var replace_instructions = options.replace_instructions;
    var label = options.label;
    var extension_summary: ?*const HookSummary = null;
    if (options.before_hook_fn) |before_hook| {
        hook_result = try before_hook(options.hook_ctx, gpa, sess, .{
            .target_id = options.target_id,
            .old_leaf_id = old_tip_owned,
            .common_ancestor_id = collected.common_ancestor_id,
            .entries_to_summarize = collected.entries,
            .user_wants_summary = options.summarize,
            .custom_instructions = custom_instructions,
            .replace_instructions = replace_instructions,
            .label = label,
        });
        if (hook_result) |*result| {
            if (result.cancel) return .{ .cancelled = true };
            if (result.custom_instructions) |value| custom_instructions = value;
            if (result.replace_instructions) |value| replace_instructions = value;
            if (result.label) |value| label = value;
            if (options.summarize) {
                if (result.summary) |*value| extension_summary = value;
            }
        }
    }

    var summary_text: ?[]u8 = null;
    defer if (summary_text) |value| gpa.free(value);
    var summary_details_owned: ?[]u8 = null;
    defer if (summary_details_owned) |value| gpa.free(value);
    var summary_details: ?[]const u8 = null;
    var summary_meta: session_mod.AssistantMeta = .{};
    defer summary_meta.deinit(gpa);
    var from_extension = false;

    if (options.summarize) {
        if (extension_summary) |provided| {
            if (std.mem.trim(u8, provided.summary, " \t\r\n").len == 0) return error.EmptySummarization;
            summary_text = try gpa.dupe(u8, provided.summary);
            summary_details = provided.details_json;
            summary_meta = try provided.meta.dupe(gpa);
            from_extension = true;
        } else if (collected.entries.len > 0) {
            var preparation = try prepareBranchEntries(
                gpa,
                collected.entries,
                options.context_window,
                options.reserve_tokens,
            );
            defer preparation.deinit();
            summary_details_owned = try detailsJson(gpa, preparation.read_files, preparation.modified_files);
            summary_details = summary_details_owned;

            if (preparation.entries.len == 0) {
                summary_text = try gpa.dupe(u8, "No content to summarize");
            } else {
                const material = try serializeConversationMaterial(gpa, preparation.entries);
                defer gpa.free(material);
                const client = options.client orelse return error.NoModelForBranchSummary;
                const instructions = if (replace_instructions and custom_instructions != null)
                    try gpa.dupe(u8, custom_instructions.?)
                else if (custom_instructions) |extra|
                    try std.fmt.allocPrint(gpa, "{s}\n\nAdditional focus: {s}", .{ SUMMARY_PROMPT, extra })
                else
                    try gpa.dupe(u8, SUMMARY_PROMPT);
                defer gpa.free(instructions);

                const prompt = try std.fmt.allocPrint(gpa,
                    \\<conversation>
                    \\{s}
                    \\</conversation>
                    \\
                    \\{s}
                , .{ material, instructions });
                defer gpa.free(prompt);
                const messages = [_]ai.ChatMessage{
                    .{ .role = "system", .content = SUMMARIZATION_SYSTEM_PROMPT },
                    .{ .role = "user", .content = prompt },
                };

                var response = summarization.complete(gpa, &messages, .{
                    .io = options.io,
                    .client = client,
                    .source = .branch_summary,
                    .reason = .navigation,
                    .retry_enabled = options.retry_enabled,
                    .retry_max_retries = options.retry_max_retries,
                    .retry_base_delay_ms = options.retry_base_delay_ms,
                    .max_output_tokens = 2_048,
                    .abort_flag = options.abort_flag,
                    .retry_abort_flag = options.retry_abort_flag,
                    .on_event = options.on_retry_event,
                    .event_ctx = options.retry_event_ctx,
                }) catch |err| switch (err) {
                    error.SummarizationCancelled => return error.BranchSummaryCancelled,
                    else => return err,
                };
                defer response.deinit(gpa);

                if (std.mem.eql(u8, response.stop_reason, "aborted")) return error.BranchSummaryCancelled;
                if (std.mem.eql(u8, response.stop_reason, "error")) return error.BranchSummaryFailed;
                const model_text = std.mem.trim(u8, response.content, " \t\r\n");
                if (model_text.len == 0) return error.EmptySummarization;

                const raw_summary = try std.fmt.allocPrint(gpa, "{s}{s}", .{ SUMMARY_PREAMBLE, model_text });
                defer gpa.free(raw_summary);
                summary_text = try appendFileLists(
                    gpa,
                    raw_summary,
                    preparation.read_files,
                    preparation.modified_files,
                );
                summary_meta = try responseMeta(gpa, response);
            }
        }
    }

    var summary_id: ?[]const u8 = null;
    var summary_entry: ?*const session_mod.SessionEntry = null;
    if (summary_text) |summary| {
        const from_id = position.parent orelse "root";
        summary_id = try sess.appendBranchSummaryWithHook(
            position.parent,
            from_id,
            summary,
            summary_details,
            from_extension,
            summary_meta,
        );
        summary_entry = sess.getEntry(summary_id.?);
        if (label) |value| _ = try sess.appendLabelChange(summary_id.?, value);
    } else {
        if (position.parent) |parent| try sess.setTip(parent) else sess.resetTip();
        if (label) |value| _ = try sess.appendLabelChange(options.target_id, value);
    }

    if (options.after_hook_fn) |after_hook| {
        after_hook(
            options.hook_ctx,
            gpa,
            sess.lastEntryId(),
            old_tip_owned,
            summary_entry,
            from_extension,
        ) catch {};
    }

    return .{
        .summary_entry_id = summary_id,
        .common_ancestor_id = collected.common_ancestor_id,
        .summarized_entries = collected.entries.len,
        .editor_text = position.editor_text,
        .from_extension = from_extension,
    };
}

const EventProbe = struct {
    scheduled: usize = 0,
    started: usize = 0,
    finished: usize = 0,

    fn onEvent(raw: ?*anyopaque, event: summarization.Event) void {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        switch (event.kind) {
            .retry_scheduled => self.scheduled += 1,
            .retry_attempt_start => self.started += 1,
            .retry_finished => self.finished += 1,
        }
    }
};

test "branch preparation keeps newest token budget and cumulative file operations" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "branch-budget-166", "/tmp");
    defer sess.deinit();

    const root = try sess.appendMessage(null, "user", "root", null, null);
    const nested = try sess.appendBranchSummary(
        root,
        root,
        "older nested summary",
        "{\"readFiles\":[\"/nested-read\"],\"modifiedFiles\":[\"/nested-mod\"]}",
        .{},
    );
    const huge = try gpa.alloc(u8, 4096);
    defer gpa.free(huge);
    @memset(huge, 'x');
    const calls =
        \\[
        \\  {"id":"read-1","type":"function","function":{"name":"read","arguments":"{\"path\":\"/over-read\"}"}},
        \\  {"id":"write-1","type":"function","function":{"name":"write","arguments":"{\"path\":\"/over-write\"}"}},
        \\  {"id":"edit-1","type":"function","function":{"name":"edit","arguments":"{\"path\":\"/nested-read\"}"}}
        \\]
    ;
    const oversized = try sess.appendMessage(nested, "assistant", huge, null, calls);
    const newest = try sess.appendMessage(oversized, "user", "latest request", null, null);

    const entries = [_]*const session_mod.SessionEntry{
        sess.getEntry(nested).?,
        sess.getEntry(oversized).?,
        sess.getEntry(newest).?,
    };
    var preparation = try prepareBranchEntries(gpa, &entries, 100, 50);
    defer preparation.deinit();

    try std.testing.expectEqual(@as(u64, 50), preparation.token_budget);
    try std.testing.expectEqual(@as(usize, 1), preparation.entries.len);
    try std.testing.expectEqualStrings(newest, preparation.entries[0].id);
    try std.testing.expectEqual(@as(usize, 1), preparation.read_files.len);
    try std.testing.expectEqualStrings("/over-read", preparation.read_files[0]);
    try std.testing.expectEqual(@as(usize, 3), preparation.modified_files.len);
    try std.testing.expectEqualStrings("/nested-mod", preparation.modified_files[0]);
    try std.testing.expectEqualStrings("/nested-read", preparation.modified_files[1]);
    try std.testing.expectEqualStrings("/over-write", preparation.modified_files[2]);
}

test "collect branch summary entries finds deepest common ancestor" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "branch-collect", "/tmp");
    defer sess.deinit();
    const user1 = try sess.appendMessage(null, "user", "root", null, null);
    const assistant1 = try sess.appendMessage(user1, "assistant", "shared", null, null);
    const user2 = try sess.appendMessage(assistant1, "user", "first path", null, null);
    const assistant2 = try sess.appendMessage(user2, "assistant", "first answer", null, null);
    try sess.setTip(assistant1);
    const user3 = try sess.appendMessage(assistant1, "user", "second path", null, null);
    const assistant3 = try sess.appendMessage(user3, "assistant", "second answer", null, null);

    var result = try collectEntries(gpa, &sess, assistant3, assistant2);
    defer result.deinit(gpa);
    try std.testing.expectEqualStrings(assistant1, result.common_ancestor_id.?);
    try std.testing.expectEqual(@as(usize, 2), result.entries.len);
    try std.testing.expectEqualStrings(user3, result.entries[0].id);
    try std.testing.expectEqualStrings(assistant3, result.entries[1].id);
}

test "branch summary retries and persists at navigation target" {
    const gpa = std.testing.allocator;
    const mock = @import("../ai/mock.zig");
    var sess = try session_mod.Session.init(gpa, "branch-summary", "/tmp");
    defer sess.deinit();
    const user1 = try sess.appendMessage(null, "user", "root", null, null);
    const assistant1 = try sess.appendMessage(user1, "assistant", "shared", null, null);
    const user2 = try sess.appendMessage(assistant1, "user", "first path", null, null);
    const assistant2 = try sess.appendMessage(user2, "assistant", "first answer", null, null);
    try sess.setTip(assistant1);
    const user3 = try sess.appendMessage(assistant1, "user", "second path", null, null);
    const tool_calls = "[{\"id\":\"read-166\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"/tmp/read-166\\\"}\"}},{\"id\":\"edit-166\",\"type\":\"function\",\"function\":{\"name\":\"edit\",\"arguments\":\"{\\\"path\\\":\\\"/tmp/edit-166\\\"}\"}}]";
    _ = try sess.appendMessage(user3, "assistant", "second answer", null, tool_calls);

    const script =
        \\[
        \\  {"content":"HTTP 503 Service Unavailable","stop_reason":"error","tool_calls":[]},
        \\  {"content":"## Goal\\nSummarize the second path","stop_reason":"stop","tool_calls":[]}
        \\]
    ;
    var model = try mock.MockModel.loadFromJson(gpa, script);
    defer model.deinit(gpa);
    var probe: EventProbe = .{};
    const result = try summarizeAndSwitch(&sess, .{
        .io = std.testing.io,
        .client = model.client(),
        .target_id = assistant2,
        .retry_base_delay_ms = 0,
        .on_retry_event = EventProbe.onEvent,
        .retry_event_ctx = &probe,
    });

    try std.testing.expect(result.summary_entry_id != null);
    try std.testing.expectEqual(@as(u64, 2_048), model.last_completion_options.max_tokens);
    try std.testing.expectEqual(@as(usize, 2), result.summarized_entries);
    try std.testing.expectEqual(@as(usize, 1), probe.scheduled);
    try std.testing.expectEqual(@as(usize, 1), probe.started);
    try std.testing.expectEqual(@as(usize, 1), probe.finished);
    const summary = sess.getEntry(result.summary_entry_id.?).?;
    try std.testing.expectEqual(session_mod.EntryType.branch_summary, summary.entry_type);
    try std.testing.expectEqualStrings(assistant2, summary.parent_id.?);
    try std.testing.expectEqualStrings(assistant2, summary.target_id.?);
    try std.testing.expect(std.mem.startsWith(u8, summary.content, SUMMARY_PREAMBLE));
    try std.testing.expect(std.mem.indexOf(u8, summary.content, "Summarize the second path") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary.content, "<read-files>\n/tmp/read-166\n</read-files>") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary.content, "<modified-files>\n/tmp/edit-166\n</modified-files>") != null);
    try std.testing.expectEqualStrings("{\"readFiles\":[\"/tmp/read-166\"],\"modifiedFiles\":[\"/tmp/edit-166\"]}", summary.data_json.?);
    try std.testing.expectEqualStrings(summary.id, sess.lastEntryId().?);

    const jsonl = try sess.toJsonl(gpa);
    defer gpa.free(jsonl);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"type\":\"branch_summary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"fromId\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, jsonl, "\"details\":") != null);

    var restored = try session_mod.Session.parseJsonl(gpa, jsonl);
    defer restored.deinit();
    const restored_summary = restored.getEntry(result.summary_entry_id.?).?;
    try std.testing.expectEqual(session_mod.EntryType.branch_summary, restored_summary.entry_type);
    try std.testing.expectEqualStrings(assistant2, restored_summary.parent_id.?);
    try std.testing.expectEqualStrings(assistant2, restored_summary.target_id.?);
    try std.testing.expectEqualStrings(summary.content, restored_summary.content);
    try std.testing.expectEqualStrings(summary.data_json.?, restored_summary.data_json.?);
    try std.testing.expectEqualStrings(restored_summary.id, restored.lastEntryId().?);
}

test "session tree hooks can provide a durable labeled summary without a model" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "tree-hook-164", "/tmp");
    defer sess.deinit();
    const root_user = try sess.appendMessage(null, "user", "root", null, null);
    const shared = try sess.appendMessage(root_user, "assistant", "shared", null, null);
    const target_user = try sess.appendMessage(shared, "user", "target branch", null, null);
    const target_answer = try sess.appendMessage(target_user, "assistant", "target answer", null, null);
    try sess.setTip(shared);
    const abandoned_user = try sess.appendMessage(shared, "user", "abandoned work", null, null);
    _ = try sess.appendMessage(abandoned_user, "assistant", "abandoned answer", null, null);
    const old_tip = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(old_tip);

    const Probe = struct {
        before_count: usize = 0,
        after_count: usize = 0,
        saw_from_extension: bool = false,
        old_leaf_matches: bool = false,

        fn before(raw: ?*anyopaque, allocator: std.mem.Allocator, _: *const session_mod.Session, preparation: HookPreparation) anyerror!?BeforeHookResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.before_count += 1;
            if (!preparation.user_wants_summary or preparation.entries_to_summarize.len != 2) return error.InvalidPreparation;
            return .{
                .summary = .{
                    .summary = try allocator.dupe(u8, "extension branch summary 164"),
                    .details_json = try allocator.dupe(u8, "{\"tree\":164}"),
                    .meta = .{ .usage_input = 4, .usage_output = 5, .usage_total = 9, .cost_total = 0.9 },
                },
                .label = try allocator.dupe(u8, "extension-label-164"),
            };
        }

        fn after(raw: ?*anyopaque, _: std.mem.Allocator, _: ?[]const u8, old_leaf_id: ?[]const u8, summary_entry: ?*const session_mod.SessionEntry, from_extension: bool) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.after_count += 1;
            self.saw_from_extension = from_extension;
            self.old_leaf_matches = old_leaf_id != null and std.mem.eql(u8, old_leaf_id.?, "m6");
            if (summary_entry == null or !summary_entry.?.from_hook) return error.MissingSummary;
        }
    };
    var probe = Probe{};
    const result = try summarizeAndSwitch(&sess, .{
        .io = std.testing.io,
        .target_id = target_answer,
        .summarize = true,
        .hook_ctx = &probe,
        .before_hook_fn = Probe.before,
        .after_hook_fn = Probe.after,
    });
    try std.testing.expect(!result.cancelled);
    try std.testing.expect(result.from_extension);
    try std.testing.expectEqual(@as(usize, 2), result.summarized_entries);
    try std.testing.expectEqual(@as(usize, 1), probe.before_count);
    try std.testing.expectEqual(@as(usize, 1), probe.after_count);
    try std.testing.expect(probe.saw_from_extension);
    try std.testing.expect(probe.old_leaf_matches);
    const summary = sess.getEntry(result.summary_entry_id.?).?;
    try std.testing.expectEqual(session_mod.EntryType.branch_summary, summary.entry_type);
    try std.testing.expect(summary.from_hook);
    try std.testing.expectEqualStrings("extension branch summary 164", summary.content);
    try std.testing.expectEqualStrings("{\"tree\":164}", summary.data_json.?);
    try std.testing.expectEqual(@as(u64, 9), summary.meta.usage_total);
    try std.testing.expectEqualStrings("extension-label-164", sess.getLabel(summary.id).?);
}

test "session_before_tree cancellation preserves the active leaf" {
    const gpa = std.testing.allocator;
    var sess = try session_mod.Session.init(gpa, "tree-cancel-164", "/tmp");
    defer sess.deinit();
    const first = try sess.appendMessage(null, "user", "first", null, null);
    const second = try sess.appendMessage(first, "assistant", "second", null, null);
    const third = try sess.appendMessage(second, "user", "third", null, null);
    const old_tip = try gpa.dupe(u8, sess.lastEntryId().?);
    defer gpa.free(old_tip);
    const Hook = struct {
        fn before(_: ?*anyopaque, _: std.mem.Allocator, _: *const session_mod.Session, _: HookPreparation) anyerror!?BeforeHookResult {
            return .{ .cancel = true };
        }
    };
    const result = try summarizeAndSwitch(&sess, .{
        .io = std.testing.io,
        .target_id = second,
        .summarize = false,
        .before_hook_fn = Hook.before,
    });
    try std.testing.expect(result.cancelled);
    try std.testing.expectEqualStrings(old_tip, sess.lastEntryId().?);
    try std.testing.expectEqual(@as(usize, 3), sess.entries.items.len);
    try std.testing.expectEqualStrings(third, old_tip);
}
