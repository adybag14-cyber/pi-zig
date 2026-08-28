//! Client-side search adapter for protocol session snapshots.
//!
//! Protocol v1 intentionally keeps search out of the wire command vocabulary.
//! This adapter acquires ordinary snapshots and projects their transcript using
//! the same query matcher and snippet rules as the local JSONL backend.
const std = @import("std");
const msg = @import("../protocol/messages.zig");
const text_search = @import("../agent/search.zig");

pub const Role = enum { user, assistant, tool };

pub const Options = struct {
    limit: usize = 100,
    case_sensitive: bool = false,
    roles: []const Role = &.{},
    snippet_context: usize = 96,
    include_thinking: bool = true,
    include_tool_names: bool = true,
};

pub const Hit = struct {
    session_id: []u8,
    session_name: []u8,
    item_id: []u8,
    role: Role,
    timestamp: u64,
    snippet: []u8,
    score: i64,
    item_ordinal: usize,

    pub fn deinit(self: *Hit, gpa: std.mem.Allocator) void {
        gpa.free(self.session_id);
        gpa.free(self.session_name);
        gpa.free(self.item_id);
        gpa.free(self.snippet);
        self.* = undefined;
    }
};

pub fn searchSnapshot(
    gpa: std.mem.Allocator,
    snapshot: *const msg.SessionSnapshot,
    query_raw: []const u8,
    options: Options,
) ![]Hit {
    const query = std.mem.trim(u8, query_raw, " \t\r\n");
    if (query.len == 0 or options.limit == 0) return try gpa.alloc(Hit, 0);

    var hits: std.ArrayList(Hit) = .empty;
    errdefer {
        for (hits.items) |*hit| hit.deinit(gpa);
        hits.deinit(gpa);
    }
    for (snapshot.transcript, 0..) |item, ordinal| {
        const role = itemRole(item);
        if (!roleAllowed(role, options.roles)) continue;
        const item_id, const timestamp = switch (item) {
            .user => |value| .{ value.id, value.timestamp },
            .assistant => |value| .{ value.id, value.timestamp },
            .tool => |value| .{ value.id, value.timestamp },
        };
        const projected = try projectItem(gpa, item, options);
        defer gpa.free(projected);
        const matched = text_search.matchText(projected, query, options.case_sensitive) orelse continue;
        const snippet = try text_search.snippetForMatch(gpa, projected, matched, options.snippet_context);
        errdefer gpa.free(snippet);
        try hits.append(gpa, .{
            .session_id = try gpa.dupe(u8, snapshot.id),
            .session_name = try gpa.dupe(u8, snapshot.name orelse ""),
            .item_id = try gpa.dupe(u8, item_id),
            .role = role,
            .timestamp = timestamp,
            .snippet = snippet,
            .score = matched.score,
            .item_ordinal = ordinal,
        });
    }
    sortHits(hits.items);
    if (hits.items.len > options.limit) {
        for (hits.items[options.limit..]) |*hit| hit.deinit(gpa);
        hits.shrinkRetainingCapacity(options.limit);
    }
    return try hits.toOwnedSlice(gpa);
}

pub fn deinitHits(gpa: std.mem.Allocator, hits: []Hit) void {
    for (hits) |*hit| hit.deinit(gpa);
    gpa.free(hits);
}

pub fn roleName(role: Role) []const u8 {
    return @tagName(role);
}

pub fn parseRole(raw: []const u8) ?Role {
    inline for (std.meta.fields(Role)) |field| {
        if (std.ascii.eqlIgnoreCase(raw, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn itemRole(item: msg.TranscriptItem) Role {
    return switch (item) {
        .user => .user,
        .assistant => .assistant,
        .tool => .tool,
    };
}

fn roleAllowed(role: Role, allowed: []const Role) bool {
    if (allowed.len == 0) return true;
    for (allowed) |candidate| if (candidate == role) return true;
    return false;
}

fn projectItem(gpa: std.mem.Allocator, item: msg.TranscriptItem, options: Options) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    switch (item) {
        .user => |user| for (user.content) |content| switch (content) {
            .text => |text| try appendField(gpa, &out, text.text),
            .image => {},
        },
        .assistant => |assistant| {
            for (assistant.content) |content| switch (content) {
                .text => |text| try appendField(gpa, &out, text.text),
                .thinking => |thinking| if (options.include_thinking) try appendField(gpa, &out, thinking.thinking),
                .toolCall => |tool_call| if (options.include_tool_names) try appendField(gpa, &out, tool_call.tool_name),
            };
            if (assistant.error_message) |message| try appendField(gpa, &out, message);
        },
        .tool => |tool| {
            if (options.include_tool_names) try appendField(gpa, &out, tool.tool_name);
            for (tool.content) |content| switch (content) {
                .text => |text| try appendField(gpa, &out, text.text),
                .image => {},
            };
        },
    }
    return try out.toOwnedSlice(gpa);
}

fn appendField(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    if (value.len == 0) return;
    if (out.items.len > 0) try out.append(gpa, '\n');
    try out.appendSlice(gpa, value);
}

pub fn sortHits(hits: []Hit) void {
    std.mem.sort(Hit, hits, {}, struct {
        fn lessThan(_: void, lhs: Hit, rhs: Hit) bool {
            if (lhs.score != rhs.score) return lhs.score > rhs.score;
            if (lhs.timestamp != rhs.timestamp) return lhs.timestamp > rhs.timestamp;
            const session_order = std.mem.order(u8, lhs.session_id, rhs.session_id);
            if (session_order != .eq) return session_order == .lt;
            return lhs.item_ordinal < rhs.item_ordinal;
        }
    }.lessThan);
}

test "snapshot search projects every transcript role and filters" {
    const gpa = std.testing.allocator;
    const transcript = [_]msg.TranscriptItem{
        .{ .user = .{ .id = "u1", .content = &.{.{ .text = .{ .text = "deploy migration safely" } }}, .timestamp = 1 } },
        .{ .assistant = .{
            .id = "a1",
            .content = &.{
                .{ .thinking = .{ .thinking = "migration verification" } },
                .{ .text = .{ .text = "take a backup before deploy" } },
            },
            .model = .{ .provider = "test", .id = "model" },
            .timestamp = 2,
            .status = .complete,
        } },
        .{ .tool = .{
            .id = "t1",
            .tool_call_id = "call-1",
            .tool_name = "database_migrate",
            .input = .null,
            .content = &.{.{ .text = .{ .text = "migration complete" } }},
            .timestamp = 3,
            .status = .complete,
            .is_error = false,
        } },
    };
    const snapshot = msg.SessionSnapshot{
        .id = "s1",
        .name = "demo",
        .cwd = "/tmp",
        .created_at = 1,
        .updated_at = 3,
        .phase = .idle,
        .model = .{ .provider = "test", .id = "model" },
        .thinking_level = .off,
        .attached = true,
        .locked = false,
        .revision = 1,
        .transcript = &transcript,
        .queued_steer = &.{},
        .queued_steer_count = 0,
    };
    const all = try searchSnapshot(gpa, &snapshot, "migration", .{});
    defer deinitHits(gpa, all);
    try std.testing.expectEqual(@as(usize, 3), all.len);

    const assistant_only = try searchSnapshot(gpa, &snapshot, "migration", .{ .roles = &.{.assistant} });
    defer deinitHits(gpa, assistant_only);
    try std.testing.expectEqual(@as(usize, 1), assistant_only.len);
    try std.testing.expectEqual(Role.assistant, assistant_only[0].role);

    const no_thinking = try searchSnapshot(gpa, &snapshot, "verification", .{ .include_thinking = false });
    defer deinitHits(gpa, no_thinking);
    try std.testing.expectEqual(@as(usize, 0), no_thinking.len);
}

test "snapshot search empty query and limit semantics" {
    const gpa = std.testing.allocator;
    const snapshot = msg.SessionSnapshot{
        .id = "empty",
        .cwd = "/",
        .created_at = 0,
        .updated_at = 0,
        .phase = .idle,
        .model = .{ .provider = "test", .id = "model" },
        .thinking_level = .off,
        .attached = true,
        .locked = false,
        .revision = 0,
        .transcript = &.{},
        .queued_steer = &.{},
        .queued_steer_count = 0,
    };
    const empty = try searchSnapshot(gpa, &snapshot, "  ", .{});
    defer deinitHits(gpa, empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}
