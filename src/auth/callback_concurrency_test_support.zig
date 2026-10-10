//! Portable, bounded loopback exercises for real OAuth callback listeners.
const std = @import("std");
const Io = std.Io;
pub const Request = struct { target: []const u8, status: u16 };

fn Task(comptime Adapter: type) type {
    const Result = @typeInfo(@typeInfo(@TypeOf(Adapter.wait)).@"fn".return_type.?).error_union.payload;
    return struct {
        adapter: *Adapter,
        aborted: bool = false,
        result: ?Result = null,
        failure: ?anyerror = null,
        done: Io.Event = .unset,
        fn run(self: *@This()) Io.Cancelable!void {
            defer self.done.set(std.testing.io);
            self.result = self.adapter.wait(&self.aborted) catch |err| {
                self.failure = err;
                return;
            };
        }
        fn cleanup(self: *@This(), group: *Io.Group) void {
            @atomicStore(bool, &self.aborted, true, .release);
            group.cancel(std.testing.io);
            group.await(std.testing.io) catch {};
            if (self.result) |*result| result.deinit(std.heap.page_allocator);
        }
    };
}

fn sleep(io: Io) bool {
    io.sleep(.fromMilliseconds(2000), .awake) catch return false;
    return true;
}
fn query(io: Io, address: Io.net.IpAddress, target: []const u8) !u16 {
    const stream = try address.connect(io, .{ .mode = .stream, .protocol = .tcp });
    defer stream.close(io);
    var write_buffer: [1024]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    try writer.interface.print("GET {s} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", .{target});
    try writer.interface.flush();
    var read_buffer: [4096]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    const line = try reader.interface.takeDelimiterInclusive('\n');
    var fields = std.mem.splitScalar(u8, line, ' ');
    _ = fields.next();
    return std.fmt.parseInt(u16, fields.next() orelse return error.InvalidCallbackResponse, 10);
}
fn queryBounded(address: Io.net.IpAddress, target: []const u8) !u16 {
    const Race = union(enum) { result: anyerror!u16, expired: bool };
    var storage: [2]Race = undefined;
    var select = Io.Select(Race).init(std.testing.io, &storage);
    defer while (select.cancel()) |_| {};
    try select.concurrent(.result, query, .{ std.testing.io, address, target });
    try select.concurrent(.expired, sleep, .{std.testing.io});
    return switch (try select.await()) {
        .result => |result| result,
        .expired => error.CallbackTestTimeout,
    };
}
pub fn success(comptime Adapter: type, adapter: *Adapter, address: Io.net.IpAddress, requests: []const Request) !void {
    var task: Task(Adapter) = .{ .adapter = adapter };
    var group: Io.Group = .init;
    defer task.cleanup(&group);
    try group.concurrent(std.testing.io, Task(Adapter).run, .{&task});
    for (requests) |request| try std.testing.expectEqual(request.status, try queryBounded(address, request.target));
    try task.done.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(2000), .clock = .awake } });
    if (task.failure) |err| return err;
    try std.testing.expectEqualStrings("concurrent-code", task.result.?.code);
}
pub fn cancellation(comptime Adapter: type, adapter: *Adapter) !void {
    var task: Task(Adapter) = .{ .adapter = adapter };
    var group: Io.Group = .init;
    defer task.cleanup(&group);
    try group.concurrent(std.testing.io, Task(Adapter).run, .{&task});
    try std.testing.io.sleep(.fromMilliseconds(30), .awake);
    @atomicStore(bool, &task.aborted, true, .release);
    try task.done.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    try std.testing.expectEqual(error.LoginCancelled, task.failure.?);
    try std.testing.expect(task.result == null);
}
pub fn unavailable(comptime Adapter: type, adapter: *Adapter) !void {
    return failure(Adapter, adapter, error.ConcurrencyUnavailable);
}
pub fn failure(comptime Adapter: type, adapter: *Adapter, expected: anyerror) !void {
    var task: Task(Adapter) = .{ .adapter = adapter };
    var group: Io.Group = .init;
    defer task.cleanup(&group);
    try group.concurrent(std.testing.io, Task(Adapter).run, .{&task});
    try task.done.waitTimeout(std.testing.io, .{ .duration = .{ .raw = .fromMilliseconds(1000), .clock = .awake } });
    try std.testing.expectEqual(expected, task.failure.?);
    try std.testing.expect(task.result == null);
}
