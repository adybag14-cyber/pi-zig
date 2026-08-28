//! Projection of authoritative remote-session snapshots plus transient stream
//! progress, ported from coding-agent/src/client/transcript.ts.
//!
//! A snapshot is never mutated by deltas. Progress items are retained in an
//! independent arena and overlaid by id when callers request the visible
//! transcript. Periodic arena compaction bounds memory retained by long streams
//! without changing item order or partial tool-call parsing.
const std = @import("std");
const protocol = @import("../protocol/root.zig");
const msg = protocol.messages;
const clone = protocol.clone;

pub const DEFAULT_COMPACT_MUTATIONS: usize = 4096;
pub const DEFAULT_COMPACT_BYTES: usize = 8 * 1024 * 1024;

pub const Options = struct {
    compact_mutations: usize = DEFAULT_COMPACT_MUTATIONS,
    compact_bytes: usize = DEFAULT_COMPACT_BYTES,
};

pub const State = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    snapshot: msg.SessionSnapshot,
    progress_items: std.StringHashMap(msg.TranscriptItem),
    progress_order: std.ArrayList([]const u8) = .empty,
    tool_call_buffers: std.StringHashMap([]const u8),
    mutation_count: usize = 0,
    retained_delta_bytes: usize = 0,
    options: Options,

    pub fn init(gpa: std.mem.Allocator, snapshot_value: msg.SessionSnapshot, options: Options) !State {
        var state: State = .{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
            .snapshot = undefined,
            .progress_items = std.StringHashMap(msg.TranscriptItem).init(gpa),
            .tool_call_buffers = std.StringHashMap([]const u8).init(gpa),
            .options = options,
        };
        errdefer {
            state.progress_items.deinit();
            state.tool_call_buffers.deinit();
            state.arena.deinit();
        }
        state.snapshot = try clone.sessionSnapshot(state.arena.allocator(), snapshot_value);
        return state;
    }

    pub fn deinit(self: *State) void {
        self.progress_order.deinit(self.gpa);
        self.progress_items.deinit();
        self.tool_call_buffers.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    /// Replaces state with a newly acquired authoritative runtime regardless of
    /// its revision. This is used after a detach/reacquire, where revision zero
    /// is valid even if an earlier runtime reached a much larger revision.
    pub fn reset(self: *State, snapshot_value: msg.SessionSnapshot) !void {
        var replacement = try State.init(self.gpa, snapshot_value, self.options);
        errdefer replacement.deinit();
        var previous = self.*;
        self.* = replacement;
        previous.deinit();
    }

    /// Applies an ordinary server snapshot. Older revisions from the same
    /// attached runtime are ignored; switching session ids accepts any revision.
    pub fn applySnapshot(self: *State, snapshot_value: msg.SessionSnapshot) !bool {
        if (std.mem.eql(u8, self.snapshot.id, snapshot_value.id) and snapshot_value.revision < self.snapshot.revision) return false;
        try self.reset(snapshot_value);
        return true;
    }

    pub fn applyProgress(self: *State, progress: msg.TranscriptProgress) !void {
        switch (progress) {
            .item_started => |item| try self.setProgressItem(item),
            .item_updated => |item| try self.setProgressItem(item),
            .item_finished => |item| {
                try self.removeToolBuffersForItem(itemId(item));
                try self.setProgressItem(item);
            },
            .assistant_delta => |delta| try self.applyAssistantDelta(delta),
        }
        self.mutation_count +|= 1;
        if ((self.options.compact_mutations > 0 and self.mutation_count >= self.options.compact_mutations) or
            (self.options.compact_bytes > 0 and self.retained_delta_bytes >= self.options.compact_bytes))
        {
            try self.compact();
        }
    }

    /// Returns a newly allocated slice whose nested values remain owned by this
    /// State. Callers free only the outer slice and must not retain it after the
    /// state is mutated or deinitialized.
    pub fn selectAlloc(self: *const State, allocator: std.mem.Allocator) ![]msg.TranscriptItem {
        var out: std.ArrayList(msg.TranscriptItem) = .empty;
        errdefer out.deinit(allocator);
        try out.ensureTotalCapacity(allocator, self.snapshot.transcript.len + self.progress_order.items.len + self.snapshot.queued_steer.len);
        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();

        for (self.snapshot.transcript) |item| {
            const id = itemId(item);
            const visible = self.progress_items.get(id) orelse item;
            try out.append(allocator, visible);
            try seen.put(id, {});
        }
        for (self.progress_order.items) |id| {
            if (seen.contains(id)) continue;
            const item = self.progress_items.get(id) orelse continue;
            try out.append(allocator, item);
            try seen.put(id, {});
        }
        for (self.snapshot.queued_steer) |item| {
            if (seen.contains(item.id)) continue;
            try out.append(allocator, .{ .user = item });
            try seen.put(item.id, {});
        }
        return out.toOwnedSlice(allocator);
    }

    pub fn progressItem(self: *const State, id: []const u8) ?msg.TranscriptItem {
        return self.progress_items.get(id);
    }

    pub fn compact(self: *State) !void {
        var replacement = try State.init(self.gpa, self.snapshot, self.options);
        errdefer replacement.deinit();
        for (self.progress_order.items) |id| {
            const item = self.progress_items.get(id) orelse continue;
            try replacement.setProgressItemWithoutAccounting(item);
        }
        var buffers = self.tool_call_buffers.iterator();
        while (buffers.next()) |entry| {
            const key = try replacement.arena.allocator().dupe(u8, entry.key_ptr.*);
            const value = try replacement.arena.allocator().dupe(u8, entry.value_ptr.*);
            try replacement.tool_call_buffers.put(key, value);
        }
        replacement.mutation_count = 0;
        replacement.retained_delta_bytes = 0;
        var previous = self.*;
        self.* = replacement;
        previous.deinit();
    }

    fn setProgressItem(self: *State, item: msg.TranscriptItem) !void {
        try self.setProgressItemWithoutAccounting(item);
    }

    fn setProgressItemWithoutAccounting(self: *State, item: msg.TranscriptItem) !void {
        const copied = try clone.transcriptItem(self.arena.allocator(), item);
        const id = itemId(copied);
        if (self.progress_items.getPtr(id)) |existing| {
            existing.* = copied;
        } else {
            try self.progress_items.put(id, copied);
            try self.progress_order.append(self.gpa, id);
        }
    }

    fn applyAssistantDelta(self: *State, delta: anytype) !void {
        const source = self.findItem(delta.message_id) orelse return;
        if (source != .assistant) return;
        const index = std.math.cast(usize, delta.content_index) orelse return;
        if (index >= source.assistant.content.len) return;

        const allocator = self.arena.allocator();
        const content = try allocator.alloc(msg.AssistantContent, source.assistant.content.len);
        for (source.assistant.content, 0..) |current, content_index| {
            if (content_index != index) {
                content[content_index] = try clone.assistantContent(allocator, current);
                continue;
            }
            content[content_index] = switch (delta.kind) {
                .text => if (current == .text)
                    .{ .text = .{ .text = try self.appendDelta(current.text.text, delta.delta) } }
                else
                    try clone.assistantContent(allocator, current),
                .thinking => if (current == .thinking)
                    .{ .thinking = .{
                        .thinking = try self.appendDelta(current.thinking.thinking, delta.delta),
                        .redacted = current.thinking.redacted,
                    } }
                else
                    try clone.assistantContent(allocator, current),
                .toolCall => if (current == .toolCall)
                    .{ .toolCall = try self.appendToolCallDelta(delta.message_id, index, current.toolCall, delta.delta) }
                else
                    try clone.assistantContent(allocator, current),
            };
        }
        const copied: msg.AssistantTranscriptItem = .{
            .id = try allocator.dupe(u8, source.assistant.id),
            .content = content,
            .model = try clone.modelRef(allocator, source.assistant.model),
            .response_model = if (source.assistant.response_model) |value| try allocator.dupe(u8, value) else null,
            .usage = source.assistant.usage,
            .timestamp = source.assistant.timestamp,
            .status = source.assistant.status,
            .stop_reason = source.assistant.stop_reason,
            .error_message = if (source.assistant.error_message) |value| try allocator.dupe(u8, value) else null,
        };
        try self.setProgressItemWithoutAccounting(.{ .assistant = copied });
    }

    fn appendDelta(self: *State, existing: []const u8, delta: []const u8) ![]const u8 {
        self.retained_delta_bytes +|= existing.len + delta.len;
        return std.mem.concat(self.arena.allocator(), u8, &.{ existing, delta });
    }

    fn appendToolCallDelta(
        self: *State,
        message_id: []const u8,
        content_index: usize,
        current: msg.ToolCallContent,
        delta: []const u8,
    ) !msg.ToolCallContent {
        const key_candidate = try std.fmt.allocPrint(self.arena.allocator(), "{s}:{d}", .{ message_id, content_index });
        const initial = self.tool_call_buffers.get(key_candidate) orelse switch (current.input) {
            .string => |text| text,
            else => "",
        };
        const buffer = try self.appendDelta(initial, delta);
        if (self.tool_call_buffers.getPtr(key_candidate)) |existing| {
            existing.* = buffer;
        } else {
            try self.tool_call_buffers.put(key_candidate, buffer);
        }
        return .{
            .tool_call_id = try self.arena.allocator().dupe(u8, current.tool_call_id),
            .tool_name = try self.arena.allocator().dupe(u8, current.tool_name),
            .input = try parsePartialToolInput(self.arena.allocator(), buffer),
        };
    }

    fn findItem(self: *const State, id: []const u8) ?msg.TranscriptItem {
        if (self.progress_items.get(id)) |item| return item;
        for (self.snapshot.transcript) |item| if (std.mem.eql(u8, itemId(item), id)) return item;
        return null;
    }

    fn removeToolBuffersForItem(self: *State, id: []const u8) !void {
        const prefix = try std.fmt.allocPrint(self.gpa, "{s}:", .{id});
        defer self.gpa.free(prefix);
        var removals: std.ArrayList([]const u8) = .empty;
        defer removals.deinit(self.gpa);
        var iterator = self.tool_call_buffers.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, prefix)) try removals.append(self.gpa, entry.key_ptr.*);
        }
        for (removals.items) |key| _ = self.tool_call_buffers.remove(key);
    }
};

pub fn itemId(item: msg.TranscriptItem) []const u8 {
    return switch (item) {
        .user => |inner| inner.id,
        .assistant => |inner| inner.id,
        .tool => |inner| inner.id,
    };
}

fn parsePartialToolInput(allocator: std.mem.Allocator, text: []const u8) !msg.JsonValue {
    return std.json.parseFromSliceLeaky(std.json.Value, allocator, text, .{}) catch .{ .string = text };
}

fn assistantSnapshot(comptime revision: u64, comptime text: []const u8) msg.SessionSnapshot {
    return .{
        .id = "session-1",
        .cwd = "/workspace",
        .created_at = 1,
        .updated_at = revision + 1,
        .phase = .turn,
        .model = .{ .provider = "faux", .id = "faux-1" },
        .thinking_level = .off,
        .attached = true,
        .locked = true,
        .revision = revision,
        .transcript = &.{.{ .assistant = .{
            .id = "assistant-1",
            .content = &.{.{ .text = .{ .text = text } }},
            .model = .{ .provider = "faux", .id = "faux-1" },
            .timestamp = 1,
            .status = .streaming,
        } }},
        .queued_steer = &.{},
        .queued_steer_count = 0,
    };
}

test "remote transcript projects deltas without mutating snapshot" {
    const gpa = std.testing.allocator;
    var state = try State.init(gpa, assistantSnapshot(1, "saved"), .{});
    defer state.deinit();
    try state.applyProgress(.{ .assistant_delta = .{
        .message_id = "assistant-1",
        .content_index = 0,
        .kind = .text,
        .delta = " response",
    } });
    try std.testing.expectEqualStrings("saved", state.snapshot.transcript[0].assistant.content[0].text.text);
    const visible = try state.selectAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqualStrings("saved response", visible[0].assistant.content[0].text.text);
}

test "remote transcript accumulates and parses streamed tool call input" {
    const gpa = std.testing.allocator;
    var snapshot = assistantSnapshot(1, "ignored");
    snapshot.transcript = &.{.{ .assistant = .{
        .id = "assistant-1",
        .content = &.{.{ .toolCall = .{ .tool_call_id = "call-1", .tool_name = "bash", .input = .null } }},
        .model = .{ .provider = "faux", .id = "faux-1" },
        .timestamp = 1,
        .status = .streaming,
    } }};
    var state = try State.init(gpa, snapshot, .{});
    defer state.deinit();
    try state.applyProgress(.{ .assistant_delta = .{
        .message_id = "assistant-1",
        .content_index = 0,
        .kind = .toolCall,
        .delta = "{\"command\":",
    } });
    var visible = try state.selectAlloc(gpa);
    try std.testing.expectEqualStrings("{\"command\":", visible[0].assistant.content[0].toolCall.input.string);
    gpa.free(visible);

    try state.applyProgress(.{ .item_updated = snapshot.transcript[0] });
    try state.applyProgress(.{ .assistant_delta = .{
        .message_id = "assistant-1",
        .content_index = 0,
        .kind = .toolCall,
        .delta = "\"pwd\"}",
    } });
    visible = try state.selectAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqualStrings("pwd", visible[0].assistant.content[0].toolCall.input.object.get("command").?.string);
}

test "remote transcript restores partial tool input from authoritative snapshot" {
    const gpa = std.testing.allocator;
    var snapshot = assistantSnapshot(1, "ignored");
    snapshot.transcript = &.{.{ .assistant = .{
        .id = "assistant-1",
        .content = &.{.{ .toolCall = .{
            .tool_call_id = "call-1",
            .tool_name = "bash",
            .input = .{ .string = "{\"command\":" },
        } }},
        .model = .{ .provider = "faux", .id = "faux-1" },
        .timestamp = 1,
        .status = .streaming,
    } }};
    var state = try State.init(gpa, snapshot, .{});
    defer state.deinit();
    try state.applyProgress(.{ .assistant_delta = .{
        .message_id = "assistant-1",
        .content_index = 0,
        .kind = .toolCall,
        .delta = "\"pwd\"}",
    } });
    const visible = try state.selectAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqualStrings("pwd", visible[0].assistant.content[0].toolCall.input.object.get("command").?.string);
}

test "remote transcript appends transient items replaces by id and queues steering" {
    const gpa = std.testing.allocator;
    var snapshot = assistantSnapshot(1, "saved");
    snapshot.queued_steer = &.{.{
        .id = "user-steer",
        .content = &.{.{ .text = .{ .text = "adjust" } }},
        .timestamp = 3,
    }};
    snapshot.queued_steer_count = 1;
    var state = try State.init(gpa, snapshot, .{});
    defer state.deinit();
    const started: msg.TranscriptItem = .{ .tool = .{
        .id = "tool-call-1",
        .tool_call_id = "call-1",
        .tool_name = "bash",
        .input = .{ .string = "printf hi" },
        .content = &.{},
        .timestamp = 2,
        .status = .running,
        .is_error = false,
    } };
    try state.applyProgress(.{ .item_started = started });
    var updated = started;
    updated.tool.content = &.{.{ .text = .{ .text = "hi" } }};
    try state.applyProgress(.{ .item_updated = updated });
    const visible = try state.selectAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqual(@as(usize, 3), visible.len);
    try std.testing.expectEqualStrings("hi", visible[1].tool.content[0].text.text);
    try std.testing.expectEqualStrings("adjust", visible[2].user.content[0].text.text);
}

test "remote transcript snapshot authority and runtime reset semantics" {
    const gpa = std.testing.allocator;
    var state = try State.init(gpa, assistantSnapshot(3, "new"), .{});
    defer state.deinit();
    try state.applyProgress(.{ .assistant_delta = .{ .message_id = "assistant-1", .content_index = 0, .kind = .text, .delta = " transient" } });
    try std.testing.expect(try state.applySnapshot(assistantSnapshot(4, "authoritative")));
    try std.testing.expect(!try state.applySnapshot(assistantSnapshot(2, "stale")));
    try std.testing.expectEqual(@as(u64, 4), state.snapshot.revision);
    var lower = assistantSnapshot(0, "other");
    lower.id = "session-2";
    try std.testing.expect(try state.applySnapshot(lower));
    try std.testing.expectEqualStrings("session-2", state.snapshot.id);
    try state.reset(assistantSnapshot(0, "reacquired"));
    try std.testing.expectEqual(@as(u64, 0), state.snapshot.revision);
}

test "remote transcript compaction preserves visible projection and buffers" {
    const gpa = std.testing.allocator;
    var state = try State.init(gpa, assistantSnapshot(1, "x"), .{ .compact_mutations = 2, .compact_bytes = 0 });
    defer state.deinit();
    try state.applyProgress(.{ .assistant_delta = .{ .message_id = "assistant-1", .content_index = 0, .kind = .text, .delta = "y" } });
    try state.applyProgress(.{ .assistant_delta = .{ .message_id = "assistant-1", .content_index = 0, .kind = .text, .delta = "z" } });
    try std.testing.expectEqual(@as(usize, 0), state.mutation_count);
    const visible = try state.selectAlloc(gpa);
    defer gpa.free(visible);
    try std.testing.expectEqualStrings("xyz", visible[0].assistant.content[0].text.text);
}
