//! Ordered, fork-aware detached reads over native durable snapshots.
const std = @import("std");
const memory = @import("memory.zig");
const json = memory.json;
const Value = json.Value;
pub const Query = struct {
    table: memory.Table,
    filters: Value = .{ .object = .empty },
    limit: u64 = 100,
    after: ?u64 = null,
    conversationId: ?u64 = null,
    minEntryId: ?u64 = null,
    maxEntryId: ?u64 = null,
    at: memory.Point = .current,
};
fn asc(_: void, a: u64, b: u64) bool {
    return a < b;
}
fn desc(_: void, a: u64, b: u64) bool {
    return a > b;
}
fn compare(record: Value, filters: Value, field: []const u8) !bool {
    const expected = json.get(filters, field) orelse return true;
    const actual = json.get(record, field) orelse return false;
    return json.equal(expected, actual);
}
fn matches(record: Value, query: Query) !bool {
    const filters = query.filters;
    switch (query.table) {
        .conversation => {
            const owner = json.get(record, "owner");
            for ([_]struct { filter: []const u8, field: []const u8 }{ .{ .filter = "ownerConversationId", .field = "conversationId" }, .{ .filter = "ownerTaskId", .field = "taskId" } }) |pair| {
                if (json.get(filters, pair.filter)) |expected| {
                    if (owner == null) return false;
                    const actual = json.get(owner.?, pair.field) orelse return false;
                    if (!json.equal(expected, actual)) return false;
                }
            }
        },
        .task => {
            for ([_][]const u8{ "conversationId", "kind", "abortRequested", "background" }) |field| if (!try compare(record, filters, field)) return false;
            if (json.get(filters, "status")) |status| {
                const state = try memory.field(record, "state");
                if (!json.equal(status, try memory.field(state, "status"))) return false;
            }
        },
        .submission => {
            for ([_][]const u8{ "conversationId", "status" }) |field| if (!try compare(record, filters, field)) return false;
        },
        .document => {
            if (!try memory.alive(record, query.at)) return false;
            if (!try compare(record, filters, "kind") or !try compare(record, filters, "scope")) return false;
        },
        .entry => {},
    }
    return true;
}
pub fn visibleIds(gpa: std.mem.Allocator, state: *const memory.State, conversation: u64, minimum: ?u64, maximum: ?u64) ![]u64 {
    var output: std.ArrayList(u64) = .empty;
    defer output.deinit(gpa);
    var current = conversation;
    var upper = maximum orelse memory.max_integer;
    var visited: std.AutoHashMap(u64, void) = .init(gpa);
    defer visited.deinit();
    while (true) {
        if (visited.contains(current)) return error.ConversationParentCycle;
        try visited.put(current, {});
        const row = state.rows.get(current) orelse return error.UnknownConversation;
        if (row.table != .conversation) return error.UnknownConversation;
        var ids: std.ArrayList(u64) = .empty;
        defer ids.deinit(gpa);
        var iterator = state.rows.iterator();
        while (iterator.next()) |item| {
            if (item.value_ptr.table != .entry or item.key_ptr.* > upper or item.key_ptr.* < (minimum orelse 0)) continue;
            if (try json.asInteger(try memory.field(item.value_ptr.record, "conversationId")) == current) try ids.append(gpa, item.key_ptr.*);
        }
        std.mem.sort(u64, ids.items, {}, desc);
        try output.appendSlice(gpa, ids.items);
        const parent = json.get(row.record, "parent") orelse break;
        upper = @min(upper, try json.asInteger(try memory.field(parent, "at")));
        if (upper < (minimum orelse 0)) break;
        current = try json.asInteger(try memory.field(parent, "conversationId"));
    }
    return output.toOwnedSlice(gpa);
}
pub fn scan(gpa: std.mem.Allocator, store: *const memory.Memory, query: Query) !json.Owned {
    try store.assertOpen();
    if (query.limit == 0 or query.limit > memory.max_integer) return error.InvalidPageLimit;
    var result = try json.Owned.empty(gpa);
    errdefer result.deinit();
    const allocator = result.arena.allocator();
    var selected: std.ArrayList(u64) = .empty;
    defer selected.deinit(gpa);
    if (query.table == .entry) {
        const conversation = query.conversationId orelse return error.MissingConversationId;
        if (query.after == null or query.after.? != 0) {
            const maximum = if (query.after) |after| @min(query.maxEntryId orelse memory.max_integer, after - 1) else query.maxEntryId;
            const ids = try visibleIds(gpa, store.state, conversation, query.minEntryId, maximum);
            defer gpa.free(ids);
            try selected.appendSlice(gpa, ids);
        }
    } else {
        var iterator = store.state.rows.iterator();
        while (iterator.next()) |item| {
            if (item.value_ptr.table != query.table or item.key_ptr.* <= (query.after orelse 0)) continue;
            if (try matches(item.value_ptr.record, query)) try selected.append(gpa, item.key_ptr.*);
        }
        std.mem.sort(u64, selected.items, {}, asc);
    }
    var page: Value = .{ .object = .empty };
    var items: std.array_list.Managed(Value) = .init(allocator);
    const count: usize = @intCast(@min(query.limit, selected.items.len));
    for (selected.items[0..count]) |id| try items.append(try json.clone(allocator, store.state.rows.get(id).?.record));
    try page.object.put(allocator, "items", .{ .array = items });
    if (selected.items.len > count) {
        var cursor: Value = .{ .object = .empty };
        try cursor.object.put(allocator, "after", .{ .integer = @intCast(selected.items[count - 1]) });
        try page.object.put(allocator, "next", cursor);
    }
    result.value = page;
    return result;
}
pub fn entry(gpa: std.mem.Allocator, store: *const memory.Memory, id: u64, conversation: ?u64) !?json.Owned {
    try store.assertOpen();
    const row = store.state.rows.get(id) orelse return null;
    if (row.table != .entry) return null;
    if (conversation) |scope| {
        const ids = try visibleIds(gpa, store.state, scope, id, id);
        defer gpa.free(ids);
        if (ids.len == 0) return null;
    }
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const allocator = owned.arena.allocator();
    var value: Value = .{ .object = .empty };
    try value.object.put(allocator, "entry", try json.clone(allocator, row.record));
    try value.object.put(allocator, "commitSeq", .{ .integer = @intCast(row.commitSeq) });
    owned.value = value;
    return owned;
}
pub fn findDocument(gpa: std.mem.Allocator, store: *const memory.Memory, address: Value, point: memory.Point) !?json.Owned {
    try store.assertOpen();
    var chosen: ?u64 = null;
    var iterator = store.state.documents.iterator();
    while (iterator.next()) |item| {
        if (try memory.sameAddress(item.value_ptr.record, address) and try memory.alive(item.value_ptr.record, point)) {
            if (chosen == null or item.key_ptr.* < chosen.?) chosen = item.key_ptr.*;
        }
    }
    return if (chosen) |id| store.readRecord(gpa, id) else null;
}
