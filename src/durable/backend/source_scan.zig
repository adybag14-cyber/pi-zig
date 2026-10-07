//! Latest source scan order and cursors over owned native storage snapshots.
const std = @import("std");
const memory = @import("memory.zig");
const legacy = @import("query.zig");
const json = memory.json;
const Value = json.Value;
pub const Order = enum { ascending, descending };
pub const Start = struct { order: Order, after: ?i64 };
fn order(value: Value) !Order {
    if (value != .string) return error.InvalidScanOrder;
    return std.meta.stringToEnum(Order, value.string) orelse error.InvalidScanOrder;
}
fn signed(value: Value) !i64 {
    const number = try json.asNumber(value);
    if (!std.math.isFinite(number) or number != @trunc(number) or @abs(number) > memory.max_integer) return error.InvalidStorageCursor;
    return @intFromFloat(number);
}
pub fn start(requested: ?Value, cursor: ?Value, fallback: Order) !Start {
    const preferred = if (requested) |value| try order(value) else null;
    const continuation = cursor orelse return .{ .order = preferred orelse fallback, .after = null };
    if (continuation != .object) return error.InvalidStorageCursor;
    const after = try signed(json.get(continuation, "after") orelse return error.InvalidStorageCursor);
    const stored = if (json.get(continuation, "order")) |value| order(value) catch return error.InvalidStorageCursor else fallback;
    if (preferred != null and preferred.? != stored) return error.ScanCursorOrderMismatch;
    return .{ .order = stored, .after = after };
}
fn matches(value: Value, filters: Value, name: []const u8) bool {
    const wanted = json.get(filters, name) orelse return true;
    const actual = json.get(value, name) orelse return false;
    return json.equal(wanted, actual);
}
fn asc(_: void, a: u64, b: u64) bool {
    return a < b;
}
fn desc(_: void, a: u64, b: u64) bool {
    return a > b;
}
pub fn scan(gpa: std.mem.Allocator, store: *const memory.Memory, table: memory.Table, filters: Value, limit: u64, cursor: ?Value) !json.Owned {
    try store.assertOpen();
    const position = if (table == .document) blk: {
        const after = if (cursor) |value| if (json.get(value, "after")) |number| try signed(number) else null else null;
        break :blk Start{ .order = .ascending, .after = after };
    } else try start(json.get(filters, "order"), cursor, if (table == .entry) .descending else .ascending);
    var ids: std.ArrayList(u64) = .empty;
    defer ids.deinit(gpa);
    if (table == .entry) {
        const conversation = try json.asInteger(try memory.field(filters, "conversationId"));
        const owner = store.state.rows.get(conversation) orelse return error.UnknownConversation;
        if (owner.table != .conversation) return error.UnknownConversation;
        const minimum = if (json.get(filters, "minEntryId")) |value| try signed(value) else 0;
        const maximum = if (json.get(filters, "maxEntryId")) |value| try signed(value) else memory.max_integer;
        if (maximum >= 0) {
            const visible = try legacy.visibleIds(gpa, store.state, conversation, @intCast(@max(minimum, 0)), @intCast(maximum));
            defer gpa.free(visible);
            try ids.appendSlice(gpa, visible);
        }
    } else {
        var iterator = store.state.rows.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.table != table) continue;
            const value = entry.value_ptr.record;
            const include = switch (table) {
                .conversation => blk: {
                    const owner = json.get(value, "owner") orelse .null;
                    if (json.get(filters, "ownerConversationId")) |wanted| {
                        const actual = json.get(owner, "conversationId") orelse break :blk false;
                        if (!json.equal(wanted, actual)) break :blk false;
                    }
                    if (json.get(filters, "ownerTaskId")) |wanted| {
                        const actual = json.get(owner, "taskId") orelse break :blk false;
                        if (!json.equal(wanted, actual)) break :blk false;
                    }
                    break :blk true;
                },
                .task => blk: {
                    for ([_][]const u8{ "conversationId", "kind", "abortRequested", "background" }) |name| if (!matches(value, filters, name)) break :blk false;
                    if (json.get(filters, "status")) |wanted| {
                        const state = json.get(value, "state") orelse break :blk false;
                        const actual = json.get(state, "status") orelse break :blk false;
                        if (!json.equal(wanted, actual)) break :blk false;
                    }
                    break :blk true;
                },
                .submission => matches(value, filters, "status") and matches(value, filters, "conversationId"),
                .document => blk: {
                    if (!matches(value, filters, "kind") or !matches(value, filters, "scope")) break :blk false;
                    const point = json.get(filters, "at") orelse Value{ .string = "current" };
                    const at: memory.Point = if (point == .string and std.mem.eql(u8, point.string, "current")) .current else .{ .seq = try json.asInteger(point) };
                    break :blk try memory.alive(value, at);
                },
                .entry => unreachable,
            };
            if (include) try ids.append(gpa, entry.key_ptr.*);
        }
    }
    if (table == .entry) {
        // Source traversal orders each fork segment, then follows its parent.
        // IDs supplied to storage need not increase across those segments.
        if (position.order == .ascending) std.mem.reverse(u64, ids.items);
    } else if (position.order == .ascending) std.mem.sort(u64, ids.items, {}, asc) else std.mem.sort(u64, ids.items, {}, desc);
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const allocator = owned.arena.allocator();
    var items: Value = .{ .array = std.array_list.Managed(Value).init(allocator) };
    var available: u64 = 0;
    for (ids.items) |id| {
        if (position.after) |after| if (if (position.order == .ascending) @as(i64, @intCast(id)) <= after else @as(i64, @intCast(id)) >= after) continue;
        available += 1;
        if (items.array.items.len < limit) try items.array.append(try json.clone(allocator, store.state.rows.get(id).?.record));
    }
    var page: Value = .{ .object = .empty };
    try page.object.put(allocator, "items", items);
    if (available > limit) {
        if (items.array.items.len == 0) return error.EmptyPageContinuation;
        var next: Value = .{ .object = .empty };
        try next.object.put(allocator, "after", try memory.field(items.array.items[items.array.items.len - 1], "id"));
        try next.object.put(allocator, "order", .{ .string = @tagName(position.order) });
        try page.object.put(allocator, "next", next);
    }
    owned.value = page;
    return owned;
}
pub fn latestHead(gpa: std.mem.Allocator, store: *const memory.Memory, conversation: u64, before: ?u64) !?json.Owned {
    try store.assertOpen();
    const ids = try legacy.visibleIds(gpa, store.state, conversation, null, before);
    defer gpa.free(ids);
    for (ids) |id| {
        const row = store.state.rows.get(id).?;
        if (json.get(row.record, "head") != null) return store.readRecord(gpa, id);
    }
    return null;
}
