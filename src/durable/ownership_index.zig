//! Native downward ownership index around live work, matching ea448 scheduler.
//! Callers serialize mutations on the Session line and run sweep after a full
//! publication, or in a later read job after a rejected/empty/read operation.
const std = @import("std");
const IdSet = std.AutoArrayHashMapUnmanaged(u64, void);
const NodeSet = std.AutoArrayHashMapUnmanaged(Node, void);
pub const Node = struct {
    kind: enum { task, conversation },
    id: u64,
    pub fn task(id: u64) Node {
        return .{ .kind = .task, .id = id };
    }
    pub fn conversation(id: u64) Node {
        return .{ .kind = .conversation, .id = id };
    }
};
pub const Status = enum { pending, running, waiting, completing, terminal };
pub const Link = struct {
    conversation: u64,
    owner: ?u64 = null,
    background: bool = false,
    pub fn parent(self: Link) Node {
        return if (self.owner) |id| Node.task(id) else Node.conversation(self.conversation);
    }
};
pub const Task = struct {
    id: u64,
    link: Link,
    status: Status,
    abort_requested: bool = false,
    failed_outcome: bool = false,
    wait_on: []const u64 = &.{},
    fn intent(self: Task) bool {
        return self.status != .terminal and (self.abort_requested or self.failed_outcome);
    }
};
pub const Edge = union(enum) { unknown, root, owned: u64 };
pub const Conversation = struct { id: u64, owner: ?u64 = null };
pub const Sizes = struct { live: usize, settled: usize, edges: usize, below: usize, roots: usize, unloaded: usize, dropQueue: usize };
pub const Index = struct {
    gpa: std.mem.Allocator,
    usable: bool = true,
    live: std.AutoHashMapUnmanaged(u64, Task) = .{},
    settled: std.AutoHashMapUnmanaged(u64, Link) = .{},
    edges: std.AutoHashMapUnmanaged(u64, ?u64) = .{},
    below: std.AutoHashMapUnmanaged(Node, NodeSet) = .{},
    roots: IdSet = .empty,
    unloaded: IdSet = .empty,
    intents: IdSet = .empty,
    runnable: IdSet = .empty,
    finalize_checks: IdSet = .empty,
    waiters: std.AutoHashMapUnmanaged(u64, IdSet) = .{},
    drop_queue: NodeSet = .empty,
    pub fn init(gpa: std.mem.Allocator) Index {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Index) void {
        var tasks = self.live.valueIterator();
        while (tasks.next()) |task| self.gpa.free(task.wait_on);
        var children = self.below.valueIterator();
        while (children.next()) |set| set.deinit(self.gpa);
        var waiters = self.waiters.valueIterator();
        while (waiters.next()) |set| set.deinit(self.gpa);
        self.live.deinit(self.gpa);
        self.settled.deinit(self.gpa);
        self.edges.deinit(self.gpa);
        self.below.deinit(self.gpa);
        self.roots.deinit(self.gpa);
        self.unloaded.deinit(self.gpa);
        self.intents.deinit(self.gpa);
        self.runnable.deinit(self.gpa);
        self.finalize_checks.deinit(self.gpa);
        self.waiters.deinit(self.gpa);
        self.drop_queue.deinit(self.gpa);
        self.* = undefined;
    }
    /// A transaction-local candidate index. Only live records and the minimal
    /// links around them are copied; no historical Storage snapshot is read.
    /// Child and worklist insertion order survives the copy.
    pub fn duplicate(self: *const Index, gpa: std.mem.Allocator) !Index {
        try self.check();
        var copied = Index.init(gpa);
        errdefer copied.deinit();
        try copied.live.ensureTotalCapacity(gpa, self.live.count());
        var records = self.live.iterator();
        while (records.next()) |entry| {
            var record = entry.value_ptr.*;
            record.wait_on = try gpa.dupe(u64, record.wait_on);
            copied.live.putAssumeCapacity(entry.key_ptr.*, record);
        }
        copied.settled = try self.settled.clone(gpa);
        copied.edges = try self.edges.clone(gpa);
        try copied.below.ensureTotalCapacity(gpa, self.below.count());
        var children = self.below.iterator();
        while (children.next()) |entry| copied.below.putAssumeCapacity(entry.key_ptr.*, try entry.value_ptr.clone(gpa));
        copied.roots = try self.roots.clone(gpa);
        copied.unloaded = try self.unloaded.clone(gpa);
        copied.intents = try self.intents.clone(gpa);
        copied.runnable = try self.runnable.clone(gpa);
        copied.finalize_checks = try self.finalize_checks.clone(gpa);
        try copied.waiters.ensureTotalCapacity(gpa, self.waiters.count());
        var waiters = self.waiters.iterator();
        while (waiters.next()) |entry| copied.waiters.putAssumeCapacity(entry.key_ptr.*, try entry.value_ptr.clone(gpa));
        copied.drop_queue = try self.drop_queue.clone(gpa);
        return copied;
    }
    fn check(self: *const Index) !void {
        if (!self.usable) return error.OwnershipIndexFailed;
    }
    pub fn sizes(self: *const Index) Sizes {
        var count: usize = 0;
        var children = self.below.valueIterator();
        while (children.next()) |set| count += set.count();
        return .{ .live = self.live.count(), .settled = self.settled.count(), .edges = self.edges.count(), .below = count, .roots = self.roots.count(), .unloaded = self.unloaded.count(), .dropQueue = self.drop_queue.count() };
    }
    pub fn needsSweep(self: *const Index) bool {
        return self.drop_queue.count() != 0;
    }
    /// Only committed publications belong here. Edges precede their task
    /// links, and a sweep runs after all writes from that publication.
    pub fn observe(self: *Index, conversations: []const Conversation, tasks: []const Task) !void {
        try self.check();
        for (conversations) |conversation| if (!self.edges.contains(conversation.id)) try self.setEdge(conversation.id, conversation.owner);
        for (tasks) |task| try self.track(task);
        try self.sweep();
    }
    pub fn edge(self: *const Index, id: u64) Edge {
        const found = self.edges.getEntry(id) orelse return .unknown;
        return if (found.value_ptr.*) |owner| .{ .owned = owner } else .root;
    }
    pub fn link(self: *const Index, id: u64) ?Link {
        return if (self.live.get(id)) |record| record.link else self.settled.get(id);
    }
    pub fn known(self: *const Index, node: Node) bool {
        if (node.kind == .task) return (self.live.contains(node.id) or self.settled.contains(node.id)) and !self.unloaded.contains(node.id);
        return switch (self.edge(node.id)) {
            .unknown => false,
            .root => true,
            .owned => |owner| self.known(Node.task(owner)),
        };
    }
    pub fn setEdge(self: *Index, id: u64, owner: ?u64) !void {
        try self.check();
        errdefer self.usable = false;
        try self.edges.put(self.gpa, id, owner);
        try self.relist(Node.conversation(id));
        try self.dropIfUnneeded(Node.conversation(id));
    }
    /// A terminal task actually read while loading an unknown owner chain.
    pub fn settleLoaded(self: *Index, id: u64, fields: Link) !void {
        try self.check();
        errdefer self.usable = false;
        try self.settled.put(self.gpa, id, fields);
        try self.unloaded.put(self.gpa, id, {});
        try self.relist(Node.task(id));
        try self.dropIfUnneeded(Node.task(id));
    }
    /// Only after the real Storage chain load reaches a known complete chain.
    pub fn markChainLoaded(self: *Index, ids: []const u64) !void {
        try self.check();
        for (ids) |id| _ = self.unloaded.orderedRemove(id);
    }
    fn removeWaiter(self: *Index, member: u64, id: u64) void {
        const set = self.waiters.getPtr(member) orelse return;
        _ = set.orderedRemove(id);
        if (set.count() == 0) {
            var removed = self.waiters.fetchRemove(member).?;
            removed.value.deinit(self.gpa);
        }
    }
    fn addWaiter(self: *Index, member: u64, id: u64) !void {
        const slot = try self.waiters.getOrPut(self.gpa, member);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.put(self.gpa, id, {});
    }
    pub fn track(self: *Index, incoming: Task) !void {
        try self.check();
        errdefer self.usable = false;
        if (incoming.status == .terminal) {
            try self.settled.put(self.gpa, incoming.id, incoming.link);
            if (self.live.fetchRemove(incoming.id)) |removed| {
                for (removed.value.wait_on) |member| self.removeWaiter(member, incoming.id);
                self.gpa.free(removed.value.wait_on);
            }
            _ = self.intents.orderedRemove(incoming.id);
            _ = self.runnable.orderedRemove(incoming.id);
            _ = self.finalize_checks.orderedRemove(incoming.id);
            if (try self.nearestLiveAbove(incoming.link)) |above| {
                const owner = self.live.get(above).?;
                if (owner.status == .completing) try self.finalize_checks.put(self.gpa, above, {}) else if (owner.abort_requested) try self.runnable.put(self.gpa, above, {});
            }
            if (self.waiters.getPtr(incoming.id)) |set| for (set.keys()) |waiter| {
                try self.runnable.put(self.gpa, waiter, {});
            };
            try self.relist(Node.task(incoming.id));
            try self.dropIfUnneeded(Node.task(incoming.id));
            return;
        }
        var record = incoming;
        record.wait_on = try self.gpa.dupe(u64, if (incoming.status == .waiting) incoming.wait_on else &.{});
        var adopted = false;
        errdefer if (!adopted) self.gpa.free(record.wait_on);
        const slot = try self.live.getOrPut(self.gpa, incoming.id);
        const previous: ?Task = if (slot.found_existing) slot.value_ptr.* else null;
        if (previous) |old| for (old.wait_on) |member| self.removeWaiter(member, incoming.id);
        slot.value_ptr.* = record;
        adopted = true;
        if (previous) |old| self.gpa.free(old.wait_on);
        if (previous == null) {
            if (!self.known(record.link.parent())) try self.unloaded.put(self.gpa, record.id, {});
            try self.relist(Node.task(record.id));
        }
        if (record.intent()) try self.intents.put(self.gpa, record.id, {}) else _ = self.intents.orderedRemove(record.id);
        if (record.status == .completing) {
            _ = self.runnable.orderedRemove(record.id);
            try self.finalize_checks.put(self.gpa, record.id, {});
        } else try self.runnable.put(self.gpa, record.id, {});
        for (record.wait_on) |member| try self.addWaiter(member, record.id);
    }
    fn dropIfUnneeded(self: *Index, node: Node) !void {
        if (node.kind == .task and self.live.contains(node.id)) return;
        if (self.below.contains(node)) return;
        try self.drop_queue.put(self.gpa, node, {});
    }
    /// Sweep is deliberately separate from track/load: a commit may create
    /// work below a chain its own callback just loaded, before publication.
    pub fn sweep(self: *Index) !void {
        try self.check();
        for (self.drop_queue.keys()) |node| {
            if (self.below.contains(node)) continue;
            if (node.kind == .conversation) {
                _ = self.edges.remove(node.id);
                _ = self.roots.orderedRemove(node.id);
            } else if (!self.live.contains(node.id)) {
                _ = self.settled.remove(node.id);
                _ = self.unloaded.orderedRemove(node.id);
            }
        }
        self.drop_queue.clearRetainingCapacity();
    }
    fn relist(self: *Index, start: Node) !void {
        var node = start;
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (remaining > 0) : (remaining -= 1) {
            const needed = (node.kind == .task and self.live.contains(node.id)) or self.below.contains(node);
            const parent: Node = if (node.kind == .task) (self.link(node.id) orelse return).parent() else switch (self.edge(node.id)) {
                .unknown => return,
                .root => {
                    if (needed) try self.roots.put(self.gpa, node.id, {}) else _ = self.roots.orderedRemove(node.id);
                    return;
                },
                .owned => |owner| Node.task(owner),
            };
            const present = if (self.below.getPtr(parent)) |set| set.contains(node) else false;
            if (present == needed) return;
            if (needed) {
                const slot = try self.below.getOrPut(self.gpa, parent);
                const first = !slot.found_existing;
                if (first) slot.value_ptr.* = .empty;
                try slot.value_ptr.put(self.gpa, node, {});
                if (!first) return;
            } else {
                const set = self.below.getPtr(parent).?;
                _ = set.orderedRemove(node);
                if (set.count() != 0) return;
                var removed = self.below.fetchRemove(parent).?;
                removed.value.deinit(self.gpa);
                try self.dropIfUnneeded(parent);
            }
            node = parent;
        }
        return error.TaskOwnershipCycle;
    }
    pub fn nearestLiveAbove(self: *const Index, start: Link) !?u64 {
        try self.check();
        var current = start;
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (remaining > 0) : (remaining -= 1) {
            if (current.background) return null;
            const owner = current.owner orelse switch (self.edge(current.conversation)) {
                .owned => |id| id,
                .root, .unknown => return null,
            };
            if (self.live.contains(owner)) return owner;
            current = self.settled.get(owner) orelse return null;
        }
        return error.TaskOwnershipCycle;
    }
    pub fn cancellingOwner(self: *const Index, start: Node) !?u64 {
        try self.check();
        if (self.intents.count() == 0) return null;
        var node = start;
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (remaining > 0) : (remaining -= 1) {
            if (node.kind == .conversation) {
                node = switch (self.edge(node.id)) {
                    .owned => |owner| Node.task(owner),
                    .root, .unknown => return null,
                };
            } else {
                const fields = self.link(node.id) orelse return null;
                if (self.live.get(node.id)) |record| if (record.intent()) return node.id;
                if (fields.background) return null;
                node = fields.parent();
            }
        }
        return error.TaskOwnershipCycle;
    }
    pub fn reaches(self: *const Index, start: Node, wanted: Node, cross_background: bool) !bool {
        try self.check();
        var node = start;
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (remaining > 0) : (remaining -= 1) {
            if (std.meta.eql(node, wanted)) return true;
            if (node.kind == .conversation) {
                node = switch (self.edge(node.id)) {
                    .owned => |owner| Node.task(owner),
                    .unknown, .root => return false,
                };
            } else {
                const fields = self.link(node.id) orelse return false;
                if (fields.background and !cross_background) return false;
                node = fields.parent();
            }
        }
        return error.TaskOwnershipCycle;
    }
    /// Null means an owner edge is not loaded yet. A background owner stops
    /// ordinary traversal before an outer scope, but a conversation reached
    /// earlier in the walk is already inside its own scope.
    pub fn inScope(self: *const Index, start: Node, wanted: ?u64, cross_background: bool) !?bool {
        try self.check();
        var node = start;
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (remaining > 0) : (remaining -= 1) {
            if (node.kind == .conversation) {
                if (wanted == node.id) return true;
                node = switch (self.edge(node.id)) {
                    .unknown => return null,
                    .root => return wanted == null,
                    .owned => |owner| Node.task(owner),
                };
            } else {
                const fields = self.link(node.id) orelse return null;
                if (fields.background and !cross_background) return false;
                node = fields.parent();
            }
        }
        return error.TaskOwnershipCycle;
    }
    pub fn hasOrdinaryBelow(self: *const Index, gpa: std.mem.Allocator, start: Node) !bool {
        try self.check();
        var pending: std.ArrayList(Node) = .empty;
        defer pending.deinit(gpa);
        try pending.append(gpa, start);
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (pending.pop()) |at| {
            if (remaining == 0) return error.TaskOwnershipCycle;
            remaining -= 1;
            const children = self.below.get(at) orelse continue;
            for (children.keys()) |node| {
                if (node.kind == .conversation) {
                    try pending.append(gpa, node);
                    continue;
                }
                const fields = self.link(node.id) orelse continue;
                if (fields.background) continue;
                if (self.live.contains(node.id)) return true;
                try pending.append(gpa, node);
            }
        }
        return false;
    }
    pub fn idle(self: *const Index, gpa: std.mem.Allocator, wanted: ?u64) !bool {
        try self.check();
        for (self.unloaded.keys()) |id| {
            const task = self.live.get(id) orelse continue;
            if (task.link.background) continue;
            const inside = try self.inScope(task.link.parent(), wanted, false);
            if (inside == null or inside.?) return false;
        }
        if (wanted) |id| return !try self.hasOrdinaryBelow(gpa, Node.conversation(id));
        for (self.roots.keys()) |id| if (try self.hasOrdinaryBelow(gpa, Node.conversation(id))) return false;
        return true;
    }
    pub fn directOwned(self: *const Index, gpa: std.mem.Allocator, owner: u64) ![]u64 {
        try self.check();
        var ids: std.ArrayList(u64) = .empty;
        errdefer ids.deinit(gpa);
        if (self.below.get(Node.task(owner))) |children| for (children.keys()) |node| {
            if (node.kind != .task) continue;
            const record = self.live.get(node.id) orelse continue;
            if (record.link.owner == owner) try ids.append(gpa, node.id);
        };
        std.mem.sort(u64, ids.items, {}, std.sort.asc(u64));
        return ids.toOwnedSlice(gpa);
    }
    pub fn ordinaryOwned(self: *const Index, gpa: std.mem.Allocator, owner: u64) ![]u64 {
        return self.walkOwned(gpa, owner, false);
    }
    /// Reach another live cancellation intent, but do not enter it: that
    /// owner's own cascade determines the nearest reason for work below it.
    pub fn cascadeOwned(self: *const Index, gpa: std.mem.Allocator, owner: u64) ![]u64 {
        return self.walkOwned(gpa, owner, true);
    }
    fn walkOwned(self: *const Index, gpa: std.mem.Allocator, owner: u64, stop_at_intent: bool) ![]u64 {
        return self.walkLive(gpa, Node.task(owner), false, stop_at_intent);
    }
    pub fn inConversation(self: *const Index, gpa: std.mem.Allocator, conversation: u64, cross_background: bool) ![]u64 {
        return self.walkLive(gpa, Node.conversation(conversation), cross_background, false);
    }
    fn walkLive(self: *const Index, gpa: std.mem.Allocator, start: Node, cross_background: bool, stop_at_intent: bool) ![]u64 {
        try self.check();
        var pending: std.ArrayList(Node) = .empty;
        defer pending.deinit(gpa);
        var ids: std.ArrayList(u64) = .empty;
        errdefer ids.deinit(gpa);
        try pending.append(gpa, start);
        var remaining = self.live.count() + self.settled.count() + self.edges.count() + 1;
        while (pending.pop()) |at| {
            if (remaining == 0) return error.TaskOwnershipCycle;
            remaining -= 1;
            const children = self.below.get(at) orelse continue;
            for (children.keys()) |node| {
                if (node.kind == .conversation) {
                    try pending.append(gpa, node);
                    continue;
                }
                const fields = self.link(node.id) orelse continue;
                if (self.live.contains(node.id) and (cross_background or !fields.background)) try ids.append(gpa, node.id);
                if ((cross_background or !fields.background) and !(stop_at_intent and self.intents.contains(node.id))) try pending.append(gpa, node);
            }
        }
        return ids.toOwnedSlice(gpa);
    }
};

fn expectSizes(index: *Index, expected: @import("backend/json.zig").Value) !void {
    const json = @import("backend/json.zig");
    const actual = index.sizes();
    inline for (std.meta.fields(Sizes)) |field| try std.testing.expectEqual(try json.asInteger(try json.required(expected, field.name)), @field(actual, field.name));
}
fn retentionExercise(gpa: std.mem.Allocator) !void {
    const json = @import("backend/json.zig");
    var source = try json.Owned.parse(gpa, @embedFile("fixtures/durable-ea-retention.json"));
    defer source.deinit();
    const rows = (try json.required(source.value, "rows")).array.items;
    var index = Index.init(gpa);
    defer index.deinit();
    try index.setEdge(1, null);
    try index.sweep();
    try expectSizes(&index, try json.required(rows[0], "sizes"));
    try index.setEdge(1, null);
    try index.track(.{ .id = 7, .link = .{ .conversation = 1 }, .status = .running });
    try index.track(.{ .id = 8, .link = .{ .conversation = 1, .owner = 7 }, .status = .running });
    try index.setEdge(9, 8);
    try index.markChainLoaded(&.{ 7, 8 });
    try index.sweep();
    try expectSizes(&index, try json.required(rows[1], "sizes"));
    try index.track(.{ .id = 8, .link = .{ .conversation = 1, .owner = 7 }, .status = .terminal });
    try index.sweep();
    try expectSizes(&index, try json.required(rows[2], "sizes"));
    try index.track(.{ .id = 15, .link = .{ .conversation = 9 }, .status = .running });
    try index.setEdge(9, 8);
    try index.settleLoaded(8, .{ .conversation = 1, .owner = 7 });
    try index.markChainLoaded(&.{ 15, 8 });
    try index.sweep();
    try expectSizes(&index, try json.required(rows[3], "sizes"));
    const owned = try index.ordinaryOwned(gpa, 7);
    defer gpa.free(owned);
    try std.testing.expectEqualSlices(u64, &.{15}, owned);
    try index.track(.{ .id = 15, .link = .{ .conversation = 9 }, .status = .terminal });
    try index.sweep();
    try expectSizes(&index, try json.required(rows[4], "sizes"));
    try index.track(.{ .id = 7, .link = .{ .conversation = 1 }, .status = .terminal });
    try index.sweep();
    try expectSizes(&index, try json.required(rows[5], "sizes"));
}
test "durable ownership index matches actual ea ended-chain sweep and reload sizes" {
    try retentionExercise(std.testing.allocator);
}
test "durable ownership index releases every native allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retentionExercise, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, boundaryExercise, .{});
}
fn boundaryExercise(gpa: std.mem.Allocator) !void {
    var index = Index.init(gpa);
    defer index.deinit();
    try index.observe(&.{.{ .id = 1 }}, &.{
        .{ .id = 7, .link = .{ .conversation = 1 }, .status = .running, .abort_requested = true },
        .{ .id = 10, .link = .{ .conversation = 1, .owner = 7 }, .status = .waiting, .wait_on = &.{11} },
        .{ .id = 11, .link = .{ .conversation = 1, .owner = 7 }, .status = .running },
    });
    try index.observe(&.{.{ .id = 9, .owner = 7 }}, &.{
        .{ .id = 13, .link = .{ .conversation = 9, .background = true }, .status = .running },
        .{ .id = 14, .link = .{ .conversation = 9, .owner = 13 }, .status = .running },
    });
    const direct = try index.directOwned(gpa, 7);
    defer gpa.free(direct);
    try std.testing.expectEqualSlices(u64, &.{ 10, 11 }, direct);
    const ordinary = try index.ordinaryOwned(gpa, 7);
    defer gpa.free(ordinary);
    try std.testing.expectEqualSlices(u64, &.{ 10, 11 }, ordinary);
    try std.testing.expectEqual(@as(?u64, 7), try index.cancellingOwner(Node.task(11)));
    try std.testing.expectEqual(@as(?u64, null), try index.cancellingOwner(Node.task(13)));
    try std.testing.expect(!try index.idle(gpa, null));
    try std.testing.expectEqual(@as(?bool, false), try index.inScope(Node.task(13), null, false));
    const scope = try index.inConversation(gpa, 1, false);
    defer gpa.free(scope);
    try std.testing.expectEqualSlices(u64, &.{ 7, 10, 11 }, scope);
    const all_scope = try index.inConversation(gpa, 1, true);
    defer gpa.free(all_scope);
    try std.testing.expectEqualSlices(u64, &.{ 7, 10, 11, 13, 14 }, all_scope);
    try std.testing.expect(!try index.reaches(Node.task(14), Node.conversation(1), false));
    try std.testing.expect(try index.reaches(Node.task(14), Node.conversation(1), true));
    {
        var overlay = try index.duplicate(gpa);
        defer overlay.deinit();
        const copied = overlay.live.get(10).?.wait_on;
        try std.testing.expect(copied.ptr != index.live.get(10).?.wait_on.ptr);
        try std.testing.expectEqualSlices(u64, &.{11}, copied);
        try overlay.track(.{ .id = 10, .link = .{ .conversation = 1, .owner = 7 }, .status = .running, .abort_requested = true });
        try overlay.track(.{ .id = 12, .link = .{ .conversation = 1, .owner = 10 }, .status = .running });
        const cascade = try overlay.cascadeOwned(gpa, 7);
        defer gpa.free(cascade);
        try std.testing.expectEqualSlices(u64, &.{ 10, 11 }, cascade);
        const ordinary_overlay = try overlay.ordinaryOwned(gpa, 7);
        defer gpa.free(ordinary_overlay);
        try std.testing.expectEqualSlices(u64, &.{ 10, 11, 12 }, ordinary_overlay);
        try std.testing.expect(!index.live.contains(12));
        try std.testing.expectEqualSlices(u64, &.{11}, index.live.get(10).?.wait_on);
    }
    // Reservation removes a waiter it finds still blocked. Ending a member
    // puts it back, without scanning unrelated live records.
    _ = index.runnable.orderedRemove(10);
    try index.track(.{ .id = 7, .link = .{ .conversation = 1 }, .status = .completing });
    _ = index.finalize_checks.orderedRemove(7);
    try index.track(.{ .id = 11, .link = .{ .conversation = 1, .owner = 7 }, .status = .terminal });
    try std.testing.expect(index.runnable.contains(10));
    try std.testing.expect(index.finalize_checks.contains(7));
    try index.sweep();
    try std.testing.expect(!index.settled.contains(11));
}
test "durable ownership index excludes background branches and wakes explicit waiters and held owners" {
    try boundaryExercise(std.testing.allocator);
}
test "durable ownership index unknown chains hold idle until loaded and background owners bound the scope" {
    const gpa = std.testing.allocator;
    var index = Index.init(gpa);
    defer index.deinit();
    try index.track(.{ .id = 20, .link = .{ .conversation = 9 }, .status = .running });
    try std.testing.expect(!try index.idle(gpa, null));
    try std.testing.expect(!try index.idle(gpa, 1));
    try index.setEdge(9, 13);
    try index.settleLoaded(13, .{ .conversation = 1, .background = true });
    try index.setEdge(1, null);
    try index.markChainLoaded(&.{ 20, 13 });
    try index.sweep();
    try std.testing.expect(try index.idle(gpa, null));
    try std.testing.expect(try index.idle(gpa, 1));
    try std.testing.expect(!try index.idle(gpa, 9));
}
