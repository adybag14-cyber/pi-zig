//! Dedicated control acknowledgement independent of the invocation mutex.
const std = @import("std");
const identifiers = @import("component_protocol.zig");
pub const Result = union(enum) { count: usize, failure: []u8 };
pub const Broker = struct {
    serial: std.Io.Mutex = .init,
    mutex: std.Io.Mutex = .init,
    wake: std.Io.Event = .unset,
    next_id: u64 = 1,
    pending: u64 = 0,
    result: ?Result = null,
    closed: bool = false,
    pub fn begin(self: *Broker, io: std.Io) !u64 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.closed) return error.ContextInvalidationChannelClosed;
        const id = self.next_id;
        self.next_id = std.math.add(u64, id, 1) catch return error.ContextInvalidationTicketExhausted;
        self.pending = id;
        self.wake.reset();
        return id;
    }
    pub fn finish(self: *Broker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.pending = 0;
        if (self.result) |result| if (result == .failure) std.heap.page_allocator.free(result.failure);
        self.result = null;
    }
    pub fn close(self: *Broker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        self.closed = true;
        self.wake.set(io);
        self.mutex.unlock(io);
    }
    pub fn accept(self: *Broker, io: std.Io, generation: u64, object: *const std.json.ObjectMap) !void {
        const owner = try identifiers.identifier(object.get("ownerGeneration") orelse return error.InvalidContextInvalidationAck);
        const ticket = try identifiers.identifier(object.get("id") orelse return error.InvalidContextInvalidationAck);
        const ok = object.get("ok") orelse return error.InvalidContextInvalidationAck;
        if (ok != .bool) return error.InvalidContextInvalidationAck;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.closed or self.pending == 0 or owner != generation or ticket != self.pending or self.result != null) return;
        self.result = if (ok.bool) .{ .count = @intCast(try identifiers.identifier(object.get("invalidated") orelse return error.InvalidContextInvalidationAck)) } else blk: {
            const message = object.get("error") orelse return error.InvalidContextInvalidationAck;
            if (message != .string or message.string.len > 65536) return error.InvalidContextInvalidationAck;
            break :blk .{ .failure = try std.heap.page_allocator.dupe(u8, message.string) };
        };
        self.wake.set(io);
    }
    pub fn wait(self: *Broker, io: std.Io) !usize {
        const deadline = std.Io.Clock.awake.now(io).toMilliseconds() + 5000;
        while (true) {
            self.mutex.lockUncancelable(io);
            const closed = self.closed;
            const result = self.result;
            self.mutex.unlock(io);
            if (closed) return error.ContextInvalidationChannelClosed;
            if (result) |value| return if (value == .count) value.count else error.NativeContextInvalidationFailed;
            const remaining = deadline - std.Io.Clock.awake.now(io).toMilliseconds();
            if (remaining <= 0) return error.ContextInvalidationTimeout;
            self.wake.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(remaining), .clock = .awake } }) catch |err| if (err != error.Timeout) return err;
        }
    }
};

test "context invalidation acknowledgements fence owner generation pending tickets duplicates and closed channels" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    var broker: Broker = .{};
    const ticket = try broker.begin(io);
    defer broker.finish(io);
    const source = try std.fmt.allocPrint(gpa, "{{\"id\":\"{d}\",\"ownerGeneration\":\"7\",\"ok\":true,\"invalidated\":2}}", .{ticket});
    defer gpa.free(source);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{});
    defer parsed.deinit();
    try broker.accept(io, 8, &parsed.value.object);
    try std.testing.expect(!broker.wake.isSet());
    try broker.accept(io, 7, &parsed.value.object);
    try std.testing.expectEqual(@as(usize, 2), try broker.wait(io));
    try broker.accept(io, 7, &parsed.value.object);
    broker.finish(io);
    try broker.accept(io, 7, &parsed.value.object);
    try std.testing.expect(broker.result == null);
    broker.close(io);
    try std.testing.expectError(error.ContextInvalidationChannelClosed, broker.begin(io));
    try std.testing.expectError(error.ContextInvalidationChannelClosed, broker.wait(io));
}
