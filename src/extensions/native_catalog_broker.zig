//! Catalog controls have their own acknowledgements so an async extension
//! invocation cannot block refreshes or receive a foreign command response.
const std = @import("std");
const identifier = @import("component_protocol.zig").identifier;
pub const Broker = struct {
    serial: std.Io.Mutex = .init,
    mutex: std.Io.Mutex = .init,
    wake: std.Io.Event = .unset,
    next_id: u64 = 1,
    pending: u64 = 0,
    accepted: ?bool = null,
    closed: bool = false,
    pub fn begin(self: *Broker, io: std.Io) !u64 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.closed) return error.NativeCatalogChannelClosed;
        if (self.pending != 0) return error.NativeCatalogControlBusy;
        const id = self.next_id;
        self.next_id = std.math.add(u64, id, 1) catch return error.NativeCatalogControlIdExhausted;
        self.pending = id;
        self.accepted = null;
        self.wake.reset();
        return id;
    }
    pub fn finish(self: *Broker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.pending = 0;
        self.accepted = null;
    }
    pub fn close(self: *Broker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        self.closed = true;
        self.wake.set(io);
        self.mutex.unlock(io);
    }
    pub fn accept(self: *Broker, io: std.Io, generation: u64, object: *const std.json.ObjectMap) !void {
        const owner = try identifier(object.get("ownerGeneration") orelse return error.InvalidNativeCatalogAck);
        const id = try identifier(object.get("id") orelse return error.InvalidNativeCatalogAck);
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.closed or owner != generation or self.pending == 0 or id != self.pending or self.accepted != null) return;
        const ok = object.get("ok") orelse return error.InvalidNativeCatalogAck;
        if (ok != .bool) return error.InvalidNativeCatalogAck;
        self.accepted = ok.bool;
        self.wake.set(io);
    }
    pub fn wait(self: *Broker, io: std.Io) !void {
        const deadline = std.Io.Clock.awake.now(io).toMilliseconds() + 5000;
        while (true) {
            self.mutex.lockUncancelable(io);
            const closed = self.closed;
            const accepted = self.accepted;
            self.mutex.unlock(io);
            if (closed) return error.NativeCatalogChannelClosed;
            if (accepted) |ok| return if (ok) {} else error.NativeCatalogRejected;
            const remaining = deadline - std.Io.Clock.awake.now(io).toMilliseconds();
            if (remaining <= 0) return error.NativeCatalogAckTimeout;
            self.wake.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(remaining), .clock = .awake } }) catch |err| if (err != error.Timeout) return err;
        }
    }
};

test "native catalog control rejects stale acknowledgements and releases rejected and closed waiters" {
    const io = std.testing.io;
    var broker: Broker = .{};
    const id = try broker.begin(io);
    defer broker.finish(io);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"ownerGeneration\":7,\"id\":1,\"ok\":false}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 1), id);
    try broker.accept(io, 8, &parsed.value.object);
    try std.testing.expect(broker.accepted == null);
    try broker.accept(io, 7, &parsed.value.object);
    try std.testing.expectError(error.NativeCatalogRejected, broker.wait(io));
    broker.finish(io);
    const next = try broker.begin(io);
    try std.testing.expectEqual(@as(u64, 2), next);
    try broker.accept(io, 7, &parsed.value.object);
    try std.testing.expect(broker.accepted == null);
    broker.close(io);
    try std.testing.expectError(error.NativeCatalogChannelClosed, broker.wait(io));
}
