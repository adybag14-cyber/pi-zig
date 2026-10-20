//! Actual native StreamResource listener lifetime controls.
//! The listeners are native records and callbacks; no JavaScript stand-in
//! implements their list, destruction, allocation or reentrant mutations.
const std = @import("std");
const em = @import("extensions/engine.zig");
const streams = @import("extensions/native_node_stream_resource.zig");
const ChargedAllocator = @import("extensions/native_env_charged_allocator.zig").ChargedAllocator;

const Action = enum { observe, remove_self, remove_other, push_other, free_self };
const Record = struct {
    allocator: std.mem.Allocator,
    trace: [16]u8 = undefined,
    length: usize = 0,
    freed: usize = 0,
    fn append(self: *Record, id: u8) void {
        std.debug.assert(self.length < self.trace.len);
        self.trace[self.length] = id;
        self.length += 1;
    }
};
const Node = struct {
    listener: streams.Listener = .{ .on_destroy = destroyed },
    record: *Record,
    id: u8,
    action: Action = .observe,
    other: ?*streams.Listener = null,

    fn destroyed(listener: *streams.Listener) void {
        const self: *Node = @alignCast(@fieldParentPtr("listener", listener));
        const record = self.record;
        record.append(self.id);
        const action = self.action;
        self.action = .observe;
        switch (action) {
            .observe => {},
            .remove_self => self.listener.deinit(),
            .remove_other => self.listener.stream.?.remove(self.other),
            .push_other => self.listener.stream.?.push(self.other),
            .free_self => {
                self.listener.deinit();
                record.freed += 1;
                // The actual native record is gone before Resource.deinit
                // resumes. Only the saved address may be compared afterward.
                record.allocator.destroy(self);
            },
        }
    }
};
const Fixture = struct {
    engine: *em.Engine,
    charged: ChargedAllocator,
    resource: streams.Resource,
    record: Record,
    nodes: [4]Node,

    fn init(self: *Fixture) !void {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        self.* = .{
            .engine = engine,
            .charged = ChargedAllocator.init(engine),
            .resource = streams.Resource.init(engine),
            .record = undefined,
            .nodes = undefined,
        };
        self.record = .{ .allocator = self.charged.allocator() };
        for (&self.nodes, 0..) |*node, index|
            node.* = .{ .record = &self.record, .id = @intCast(index) };
    }
    fn deinit(self: *Fixture) void {
        // Teardown also owns any still-linked heap listener after a failed
        // assertion. Callback records and the diagnostic Engine remain alive.
        self.resource.deinit();
        for (&self.nodes) |*node| node.listener.deinit();
        self.charged.deinit();
        self.engine.deinit();
    }
    fn push(self: *Fixture, index: usize) void {
        self.resource.push(&self.nodes[index].listener);
    }
    fn expectTrace(self: *Fixture, expected: []const u8) !void {
        try std.testing.expectEqualSlices(u8, expected, self.record.trace[0..self.record.length]);
    }
    fn expectUnlinked(self: *Fixture, index: usize) !void {
        try std.testing.expect(self.nodes[index].listener.stream == null);
        try std.testing.expect(self.nodes[index].listener.previous_listener == null);
    }
};

test "native Node stream resource initializes the actual counters and publishes the native listener chain" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    try std.testing.expectEqual(@as(u64, 0), f.resource.bytes_read);
    try std.testing.expectEqual(@as(u64, 0), f.resource.bytes_written);
    try std.testing.expect(f.resource.listener == null);
    f.push(0); f.push(1);
    try std.testing.expect(f.resource.listener == &f.nodes[1].listener);
    try std.testing.expect(f.nodes[1].listener.previous_listener == &f.nodes[0].listener);
    try std.testing.expect(f.nodes[0].listener.previous_listener == null);
    try std.testing.expect(f.nodes[0].listener.stream == &f.resource);
    try std.testing.expect(f.nodes[1].listener.stream == &f.resource);
    try f.expectTrace(&.{});
}
test "native Node stream resource removes a middle listener and clears both of its actual links" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0); f.push(1); f.push(2);
    f.resource.remove(&f.nodes[1].listener);
    try f.expectUnlinked(1);
    try std.testing.expect(f.resource.listener == &f.nodes[2].listener);
    try std.testing.expect(f.nodes[2].listener.previous_listener == &f.nodes[0].listener);
    try std.testing.expect(f.nodes[0].listener.stream == &f.resource);
    try f.expectTrace(&.{});
    f.resource.deinit();
    try f.expectTrace(&.{ 2, 0 });
}
test "native Node stream resource listener destruction unlinks once without invoking OnStreamDestroy" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0); f.push(1);
    f.nodes[1].listener.deinit();
    f.nodes[1].listener.deinit();
    try f.expectUnlinked(1);
    try std.testing.expect(f.resource.listener == &f.nodes[0].listener);
    try f.expectTrace(&.{});
    f.resource.deinit();
    try f.expectTrace(&.{0});
}
test "native Node stream resource destruction visits the original native head order and clears each link" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0); f.push(1); f.push(2);
    f.resource.deinit();
    try f.expectTrace(&.{ 2, 1, 0 });
    try std.testing.expect(f.resource.listener == null);
    for (0..3) |index| try f.expectUnlinked(index);
}
test "native Node stream resource callback can unlink and free its actual charged native record" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0);
    const self_deleting = try f.record.allocator.create(Node);
    self_deleting.* = .{ .record = &f.record, .id = 9, .action = .free_self };
    f.resource.push(&self_deleting.listener);
    // Resource now owns the actual callback route to this allocation's free.
    // Fixture.deinit reaches it even if a later assertion fails.
    f.resource.deinit();
    try f.expectTrace(&.{ 9, 0 });
    try std.testing.expectEqual(@as(usize, 1), f.record.freed);
    try std.testing.expect(f.resource.listener == null);
    try f.expectUnlinked(0);
}
test "native Node stream resource destruction observes actual removal of a later listener" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0); f.push(1); f.push(2);
    f.nodes[2].action = .remove_other;
    f.nodes[2].other = &f.nodes[1].listener;
    f.resource.deinit();
    try f.expectTrace(&.{ 2, 0 });
    for (0..3) |index| try f.expectUnlinked(index);
}
test "native Node stream resource destruction visits a newly pushed head before returning to its original listener" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0);
    f.nodes[0].action = .push_other;
    f.nodes[0].other = &f.nodes[1].listener;
    f.resource.deinit();
    // Original OnStreamDestroy has not unlinked itself. Once the new head is
    // removed, the real while loop visits that original listener a second time.
    try f.expectTrace(&.{ 0, 1, 0 });
    try f.expectUnlinked(0); try f.expectUnlinked(1);
}
test "native Node stream resource preserves the embedded default listener member-before-base destruction" {
    var f: Fixture = undefined; try f.init(); defer f.deinit();
    f.push(0); f.push(1);
    // Actual StreamBase::default_listener_ is destroyed before its
    // StreamResource base. Its StreamListener destructor only unlinks it.
    f.nodes[0].listener.deinit();
    try f.expectUnlinked(0);
    try std.testing.expect(f.nodes[1].listener.previous_listener == null);
    f.resource.deinit();
    try f.expectTrace(&.{1});
    try f.expectUnlinked(1);
}
