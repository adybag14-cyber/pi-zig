//! One stdout writer, ordered command output, and priority control replies.
const std = @import("std");
const wire = @import("frame.zig");
const Io = std.Io;
const Item = struct { encoded: []u8, payload_bytes: usize };
pub const Output = struct {
    io: Io,
    allocator: std.mem.Allocator = std.heap.page_allocator,
    file: Io.File,
    mutex: Io.Mutex = .init,
    queued: Io.Event = .unset,
    drained: Io.Event = .unset,
    control: std.ArrayList(Item) = .empty,
    bulk: std.ArrayList(Item) = .empty,
    bulk_bytes: usize = 0,
    encoded_bytes: usize = 0,
    closed: bool = false,
    failure: ?anyerror = null,
    writer: ?Io.Future(anyerror!void) = null,
    pub fn start(self: *Output) !void {
        self.writer = try self.io.concurrent(run, .{self});
    }
    pub fn close(self: *Output) void {
        self.mutex.lockUncancelable(self.io);
        self.closed = true;
        self.mutex.unlock(self.io);
        self.queued.set(self.io);
        self.drained.set(self.io);
    }
    pub fn deinit(self: *Output) void {
        self.close();
        if (self.writer) |*future| _ = future.cancel(self.io) catch {};
        for (self.control.items) |item| self.allocator.free(item.encoded);
        for (self.bulk.items) |item| self.allocator.free(item.encoded);
        self.control.deinit(self.allocator);
        self.bulk.deinit(self.allocator);
    }
    fn queue(self: *Output, encoded: []u8, payload_bytes: usize, bulk: bool) !void {
        var transferred = false;
        defer if (!transferred) self.allocator.free(encoded);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return self.failure orelse error.DaemonOutputClosed;
        if (self.encoded_bytes + encoded.len > 64 * 1024 * 1024 or self.control.items.len + self.bulk.items.len >= 4096) return error.DaemonOutputBudgetExceeded;
        try (if (bulk) &self.bulk else &self.control).append(self.allocator, .{ .encoded = encoded, .payload_bytes = payload_bytes });
        self.encoded_bytes += encoded.len;
        if (bulk) self.bulk_bytes += payload_bytes;
        transferred = true;
        self.queued.set(self.io);
    }
    pub fn send(self: *Output, kind: wire.Kind, id: u32, value: anytype, payload: []const u8) !void {
        try self.queue(try wire.encode(self.allocator, kind, id, value, payload), payload.len, payload.len > 64 * 1024);
    }
    /// All records of one command, including its terminal result, share the
    /// bulk FIFO so priority replies cannot overtake that command's output.
    pub fn sendBulk(self: *Output, kind: wire.Kind, id: u32, value: anytype, payload: []const u8) !void {
        try self.queue(try wire.encode(self.allocator, kind, id, value, payload), payload.len, true);
    }
    pub fn sendJson(self: *Output, kind: wire.Kind, id: u32, json: []const u8, payload: []const u8) !void {
        try self.queue(try wire.encodeJson(self.allocator, kind, id, json, payload), payload.len, payload.len > 64 * 1024);
    }
    pub fn waitForRoom(self: *Output, abort: *const std.atomic.Value(bool), killed: *const std.atomic.Value(bool)) !void {
        while (true) {
            self.drained.reset();
            self.mutex.lockUncancelable(self.io);
            const closed = self.closed;
            const room = self.bulk_bytes <= 4 * 1024 * 1024;
            self.mutex.unlock(self.io);
            if (closed) return error.DaemonOutputClosed;
            if (room or abort.load(.acquire) or killed.load(.acquire)) return;
            self.drained.waitTimeout(self.io, .{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } }) catch |err| switch (err) {
                error.Timeout => {},
                else => return err,
            };
        }
    }
    fn take(self: *Output) !?Item {
        while (true) {
            self.queued.reset();
            self.mutex.lockUncancelable(self.io);
            const taking_bulk = self.control.items.len == 0;
            const item: ?Item = if (self.control.items.len != 0) self.control.orderedRemove(0) else if (self.bulk.items.len != 0) self.bulk.orderedRemove(0) else null;
            if (item) |value| {
                self.encoded_bytes -= value.encoded.len;
                if (taking_bulk) self.bulk_bytes -= value.payload_bytes;
                self.mutex.unlock(self.io);
                return value;
            }
            const closed = self.closed;
            self.mutex.unlock(self.io);
            if (closed) return null;
            try self.queued.wait(self.io);
        }
    }
    fn run(self: *Output) anyerror!void {
        self.writeFrames() catch |err| {
            self.mutex.lockUncancelable(self.io);
            self.failure = err;
            self.mutex.unlock(self.io);
            self.close();
            return err;
        };
    }
    fn writeFrames(self: *Output) !void {
        while (try self.take()) |item| {
            defer self.allocator.free(item.encoded);
            try self.file.writeStreamingAll(self.io, item.encoded);
            self.drained.set(self.io);
        }
    }
};
test "actual framed writer prioritizes controls while command results follow all command output" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file = try tmp.dir.createFile(io, "frames", .{});
    defer file.close(io);
    var output: Output = .{ .io = io, .file = file, .allocator = allocator };
    defer output.deinit();
    try output.sendBulk(.event, 4, .{ .kind = "output", .stream = "stdout" }, "first");
    try output.sendBulk(.event, 4, .{ .kind = "output", .stream = "stderr" }, "second");
    try output.sendBulk(.result, 4, .{ .exitCode = 37 }, "");
    try output.send(.ping, 0, std.json.Value{ .object = .empty }, "");
    try output.send(.result, 5, .{ .protocol = 1 }, "");
    try output.start();
    output.close();
    try output.writer.?.await(io);
    output.writer = null;
    const bytes = try tmp.dir.readFileAlloc(io, "frames", allocator, .limited(4096));
    defer allocator.free(bytes);
    var decoder = wire.Decoder.init(allocator);
    defer decoder.deinit();
    var offset: usize = 0;
    const kinds = [_]wire.Kind{ .ping, .result, .event, .event, .result };
    const ids = [_]u32{ 0, 5, 4, 4, 4 };
    var index: usize = 0;
    while (offset < bytes.len) {
        offset += try decoder.receive(bytes[offset..]);
        if (try decoder.next()) |received| {
            var record = received;
            defer record.deinit();
            try std.testing.expect(index < kinds.len);
            try std.testing.expectEqual(kinds[index], record.kind);
            try std.testing.expectEqual(ids[index], record.id);
            index += 1;
        }
    }
    try std.testing.expectEqual(kinds.len, index);
    try std.testing.expectEqual(@as(usize, 0), output.bulk_bytes);
    try std.testing.expectEqual(@as(usize, 0), output.encoded_bytes);
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var output: Output = .{ .io = std.testing.io, .file = std.Io.File.stdout(), .allocator = allocator };
    defer output.deinit();
    try output.sendBulk(.event, 4, .{ .kind = "output" }, "owned");
    try output.send(.result, 5, .{ .value = "control" }, "");
}
test "output queue allocation failures release encoder and accepted records" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
