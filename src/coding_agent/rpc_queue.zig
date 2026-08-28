//! Thread-safe owned message queue used by RPC steering and follow-up delivery.
const std = @import("std");
const Io = std.Io;

pub const MessageQueue = struct {
    gpa: std.mem.Allocator,
    io: Io,
    mutex: std.Io.Mutex = .init,
    items: std.ArrayList([]u8) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: Io) MessageQueue {
        return .{ .gpa = gpa, .io = io };
    }

    pub fn deinit(self: *MessageQueue) void {
        self.mutex.lockUncancelable(self.io);
        for (self.items.items) |message| self.gpa.free(message);
        self.items.deinit(self.gpa);
        self.mutex.unlock(self.io);
        self.* = undefined;
    }

    pub fn push(self: *MessageQueue, message: []const u8) !void {
        const owned = try self.gpa.dupe(u8, message);
        errdefer self.gpa.free(owned);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.items.append(self.gpa, owned);
    }

    pub fn count(self: *MessageQueue) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.items.items.len;
    }

    pub fn clear(self: *MessageQueue) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.items.items) |message| self.gpa.free(message);
        self.items.clearRetainingCapacity();
    }

    /// AgentConfig callback. The returned slice is owned by the allocator that
    /// owns this queue and is transferred to the agent loop for eventual free.
    pub fn take(ctx: ?*anyopaque, _: std.mem.Allocator) anyerror!?[]u8 {
        const self: *MessageQueue = @ptrCast(@alignCast(ctx orelse return null));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.items.items.len == 0) return null;
        return self.items.orderedRemove(0);
    }
};

test "RPC message queue transfers owned messages in FIFO order" {
    const gpa = std.testing.allocator;
    var queue = MessageQueue.init(gpa, std.testing.io);
    defer queue.deinit();
    try queue.push("first");
    try queue.push("second");
    try std.testing.expectEqual(@as(usize, 2), queue.count());
    const first = (try MessageQueue.take(&queue, gpa)).?;
    defer gpa.free(first);
    try std.testing.expectEqualStrings("first", first);
    try std.testing.expectEqual(@as(usize, 1), queue.count());
    queue.clear();
    try std.testing.expectEqual(@as(usize, 0), queue.count());
}
