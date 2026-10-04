//! Read-only session traversal over the host's immutable JSON snapshot.
const std = @import("std");

pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    entries: []const std.json.Value,
    by_id: std.StringHashMapUnmanaged(usize) = .empty,
    leaf: ?[]const u8,

    /// The caller provides a temporary arena; returned values borrow its data.
    pub fn init(allocator: std.mem.Allocator, value: std.json.Value) !Snapshot {
        if (value != .object) return error.InvalidSessionSnapshot;
        const entries_value = value.object.get("sessionEntries") orelse std.json.Value{ .array = .init(allocator) };
        if (entries_value != .array) return error.InvalidSessionSnapshot;
        const leaf_value = value.object.get("sessionLeafId") orelse std.json.Value.null;
        if (leaf_value != .string and leaf_value != .null) return error.InvalidSessionSnapshot;
        var result: Snapshot = .{ .allocator = allocator, .entries = entries_value.array.items, .leaf = if (leaf_value == .string) leaf_value.string else null };
        for (result.entries, 0..) |value_entry, index| {
            if (value_entry != .object) return error.InvalidSessionSnapshot;
            const id = text(value_entry, "id") orelse return error.InvalidSessionSnapshot;
            if (id.len == 0 or result.by_id.contains(id)) return error.InvalidSessionSnapshot;
            try result.by_id.put(allocator, id, index);
        }
        return result;
    }

    pub fn text(value: std.json.Value, key: []const u8) ?[]const u8 {
        if (value != .object) return null;
        const field = value.object.get(key) orelse return null;
        return if (field == .string) field.string else null;
    }

    pub fn entry(self: *const Snapshot, id: ?[]const u8) ?std.json.Value {
        const index = self.by_id.get(id orelse return null) orelse return null;
        return self.entries[index];
    }

    pub fn label(self: *const Snapshot, id: []const u8) ?[]const u8 {
        var result: ?[]const u8 = null;
        for (self.entries) |value| {
            const kind = text(value, "type") orelse continue;
            if (!std.mem.eql(u8, kind, "label")) continue;
            const target = text(value, "targetId") orelse continue;
            if (!std.mem.eql(u8, target, id)) continue;
            const candidate = text(value, "label");
            result = if (candidate != null and candidate.?.len > 0) candidate else null;
        }
        return result;
    }

    pub fn branch(self: *const Snapshot, id: ?[]const u8) !std.json.Value {
        var values: std.json.Array = .init(self.allocator);
        var current = id;
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        while (current) |name| {
            const value = self.entry(name) orelse break;
            if (seen.contains(name)) return error.SessionParentCycle;
            try seen.put(self.allocator, name, {});
            try values.append(value);
            const parent = value.object.get("parentId") orelse std.json.Value.null;
            if (parent != .string and parent != .null) return error.InvalidSessionSnapshot;
            current = if (parent == .string) parent.string else null;
        }
        std.mem.reverse(std.json.Value, values.items);
        return .{ .array = values };
    }

    pub fn contextEntries(self: *const Snapshot) !std.json.Value {
        const path = try self.branch(self.leaf);
        var latest: ?usize = null;
        for (path.array.items, 0..) |value, index| {
            const kind = text(value, "type") orelse continue;
            if (std.mem.eql(u8, kind, "compaction")) latest = index;
        }
        const boundary = latest orelse return path;
        const compaction = path.array.items[boundary];
        const kept = text(compaction, "firstKeptEntryId");
        var values: std.json.Array = .init(self.allocator);
        try values.append(compaction);
        var include = false;
        for (path.array.items[0..boundary]) |value| {
            const id = text(value, "id").?;
            if (kept != null and std.mem.eql(u8, id, kept.?)) include = true;
            if (!include) continue;
            const kind = text(value, "type") orelse "";
            if (std.mem.eql(u8, kind, "message")) {
                const message = value.object.get("message") orelse std.json.Value.null;
                const role = text(message, "role") orelse "";
                if (std.mem.eql(u8, role, "system")) continue;
            }
            try values.append(value);
        }
        for (path.array.items[boundary + 1 ..]) |value| try values.append(value);
        return .{ .array = values };
    }

    pub fn parents(self: *const Snapshot) ![]?usize {
        const result = try self.allocator.alloc(?usize, self.entries.len);
        for (self.entries, result, 0..) |value, *parent, index| {
            const id = text(value, "parentId");
            parent.* = if (id) |name| self.by_id.get(name) else null;
            // Upstream treats a self-parented entry as a root in tree views.
            if (parent.* == index) parent.* = null;
        }
        const colors = try self.allocator.alloc(u8, self.entries.len);
        @memset(colors, 0);
        var path: std.ArrayList(usize) = .empty;
        for (self.entries, 0..) |_, start| {
            if (colors[start] == 2) continue;
            path.clearRetainingCapacity();
            var current: ?usize = start;
            while (current) |index| {
                if (colors[index] == 2) break;
                if (colors[index] == 1) return error.SessionParentCycle;
                colors[index] = 1;
                try path.append(self.allocator, index);
                current = result[index];
            }
            for (path.items) |index| colors[index] = 2;
        }
        return result;
    }
};

test "native session snapshots traverse explicit branches resolve labels and exclude old system entries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const value = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        "{\"sessionLeafId\":\"tail\",\"sessionEntries\":[" ++
            "{\"id\":\"root\",\"parentId\":null,\"type\":\"message\",\"message\":{\"role\":\"user\"}}," ++
            "{\"id\":\"system\",\"parentId\":\"root\",\"type\":\"message\",\"message\":{\"role\":\"system\"}}," ++
            "{\"id\":\"kept\",\"parentId\":\"system\",\"type\":\"message\",\"message\":{\"role\":\"assistant\"}}," ++
            "{\"id\":\"summary\",\"parentId\":\"kept\",\"type\":\"compaction\",\"firstKeptEntryId\":\"root\"}," ++
            "{\"id\":\"tail\",\"parentId\":\"summary\",\"type\":\"message\"}," ++
            "{\"id\":\"label-one\",\"parentId\":\"root\",\"type\":\"label\",\"targetId\":\"root\",\"label\":\"old\"}," ++
            "{\"id\":\"label-two\",\"parentId\":\"label-one\",\"type\":\"label\",\"targetId\":\"root\",\"label\":null}]}",
        .{},
    );
    const snapshot = try Snapshot.init(allocator, value);
    try std.testing.expectEqualStrings("tail", Snapshot.text(snapshot.entry(snapshot.leaf).?, "id").?);
    try std.testing.expect(snapshot.label("root") == null);
    const branch = try snapshot.branch("kept");
    try std.testing.expectEqual(@as(usize, 3), branch.array.items.len);
    const context = try snapshot.contextEntries();
    try std.testing.expectEqual(@as(usize, 4), context.array.items.len);
    try std.testing.expectEqualStrings("summary", Snapshot.text(context.array.items[0], "id").?);
    try std.testing.expectEqualStrings("root", Snapshot.text(context.array.items[1], "id").?);
    try std.testing.expectEqualStrings("kept", Snapshot.text(context.array.items[2], "id").?);
}

test "native session snapshot parent cycles and duplicate identifiers fail explicitly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cycle = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"sessionEntries\":[{\"id\":\"a\",\"parentId\":\"b\"},{\"id\":\"b\",\"parentId\":\"a\"}]}", .{});
    const snapshot = try Snapshot.init(allocator, cycle);
    try std.testing.expectError(error.SessionParentCycle, snapshot.branch("a"));
    const repeated = try std.json.parseFromSliceLeaky(std.json.Value, allocator, "{\"sessionEntries\":[{\"id\":\"a\"},{\"id\":\"a\"}]}", .{});
    try std.testing.expectError(error.InvalidSessionSnapshot, Snapshot.init(allocator, repeated));
}
