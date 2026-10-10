const std = @import("std");
const builtin = @import("builtin");
const client = @import("connection.zig");
const frame = @import("frame.zig");
extern "c" fn mkfifo(path: [*:0]const u8, mode: c_uint) c_int;
test "sixteen native file workers bound blocking FIFO opens while free slots keep unrelated file requests live" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try client.Connection.start(gpa, io, &.{program}, 73);
    defer connection.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const root = root_buffer[0..root_len];
    const sentinel = try std.fs.path.join(gpa, &.{ root, "sentinel" });
    defer gpa.free(sentinel);
    try tmp.dir.writeFile(io, .{ .sub_path = "sentinel", .data = "worker-fairness" });
    var paths: [16][]u8 = undefined;
    var tickets: [16]client.Ticket = undefined;
    var count: usize = 0;
    defer for (0..count) |index| {
        tickets[index].deinit();
        gpa.free(paths[index]);
    };
    for (0..16) |index| {
        const path = try std.fmt.allocPrint(gpa, "{s}/fifo-{d}", .{ root, index });
        errdefer gpa.free(path);
        const terminated = try gpa.dupeZ(u8, path);
        defer gpa.free(terminated);
        try std.testing.expectEqual(@as(c_int, 0), mkfifo(terminated, 0o600));
        paths[index] = path;
        tickets[index] = try connection.begin(.{ .op = "open", .path = path, .mode = "read" }, "", null);
        count += 1;
        if (index == 14) {
            var live = try connection.begin(.{ .op = "lstat", .path = sentinel }, "", null);
            defer live.deinit();
            var reply = try live.next(2000);
            defer reply.deinit();
            try std.testing.expectEqual(frame.Kind.result, reply.kind);
            try std.testing.expectEqual(@as(i64, 15), reply.json.value.object.get("size").?.integer);
        }
    }
    for (tickets) |ticket| try std.testing.expectError(error.Timeout, ticket.next(5));
    var saturated = try connection.begin(.{ .op = "lstat", .path = sentinel }, "", null);
    defer saturated.deinit();
    try std.testing.expectError(error.Timeout, saturated.next(100));
    // Release exactly one FIFO worker. The seventeenth file request now runs.
    const writer = try std.Io.Dir.cwd().openFile(io, paths[0], .{ .mode = .write_only });
    try writer.writeStreamingAll(io, "FIFO-Ω🦊");
    writer.close(io);
    var first = try tickets[0].next(2000);
    defer first.deinit();
    try std.testing.expectEqual(frame.Kind.result, first.kind);
    var admitted = try saturated.next(2000);
    defer admitted.deinit();
    try std.testing.expectEqual(frame.Kind.result, admitted.kind);
    const id = first.json.value.object.get("handle").?;
    var read = try connection.begin(.{ .op = "pread", .handle = id, .length = 64 * 1024 }, "", 73);
    defer read.deinit();
    var data = try read.next(2000);
    defer data.deinit();
    try std.testing.expectEqual(frame.Kind.result, data.kind);
    try std.testing.expectEqualStrings("FIFO-Ω🦊", data.payload);
    var eof = try connection.begin(.{ .op = "pread", .handle = id, .length = 64 * 1024 }, "", 73);
    defer eof.deinit();
    var end = try eof.next(2000);
    defer end.deinit();
    try std.testing.expectEqual(@as(usize, 0), end.payload.len);
    for (1..16) |index| {
        const next_writer = try std.Io.Dir.cwd().openFile(io, paths[index], .{ .mode = .write_only });
        next_writer.close(io);
        var opened = try tickets[index].next(2000);
        defer opened.deinit();
        try std.testing.expectEqual(frame.Kind.result, opened.kind);
    }
}
test "native chunk arrival lanes preserve ordered bytes across parallel handle traffic and close every admitted ticket" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try client.Connection.start(gpa, io, &.{program}, 74);
    defer connection.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const path = try std.fs.path.join(gpa, &.{ root_buffer[0..root_len], "ordered" });
    defer gpa.free(path);
    var open = try connection.begin(.{ .op = "write", .path = path, .keep = true }, "first", null);
    defer open.deinit();
    var created = try open.next(2000);
    defer created.deinit();
    const id = created.json.value.object.get("handle").?;
    var queued: std.ArrayList(client.Ticket) = .empty;
    defer {
        for (queued.items) |*ticket| ticket.deinit();
        queued.deinit(gpa);
    }
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try bytes.appendSlice(gpa, "first");
    for (0..48) |index| {
        const chunk = try std.fmt.allocPrint(gpa, "/{d}:Ω🦊", .{index});
        defer gpa.free(chunk);
        try bytes.appendSlice(gpa, chunk);
        var ticket = try connection.begin(.{ .op = "writeChunk", .handle = id }, chunk, 74);
        errdefer ticket.deinit();
        try queued.append(gpa, ticket);
    }
    // Consume replies in reverse; completion order cannot change file order.
    var remaining = queued.items.len;
    while (remaining > 0) {
        remaining -= 1;
        var reply = try queued.items[remaining].next(2000);
        defer reply.deinit();
        try std.testing.expectEqual(frame.Kind.result, reply.kind);
    }
    var close = try connection.begin(.{ .op = "close", .handle = id }, "", 74);
    defer close.deinit();
    var closed = try close.next(2000);
    defer closed.deinit();
    const actual = try tmp.dir.readFileAlloc(io, "ordered", gpa, .limited(1024 * 1024));
    defer gpa.free(actual);
    try std.testing.expectEqualSlices(u8, bytes.items, actual);
}
test "a concurrent close cannot destroy a FIFO handle leased by an already blocked read" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try client.Connection.start(gpa, io, &.{program}, 75);
    defer connection.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const path = try std.fmt.allocPrintSentinel(gpa, "{s}/fifo", .{root_buffer[0..root_len]}, 0);
    defer gpa.free(path);
    try std.testing.expectEqual(@as(c_int, 0), mkfifo(path, 0o600));
    var opened = try connection.begin(.{ .op = "open", .path = @as([]const u8, path), .mode = "read" }, "", null);
    defer opened.deinit();
    const writer = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
    defer writer.close(io);
    var first = try opened.next(2000);
    defer first.deinit();
    const id = first.json.value.object.get("handle").?;
    var reading = try connection.begin(.{ .op = "pread", .handle = id, .length = 1024 }, "", 75);
    defer reading.deinit();
    try std.testing.expectError(error.Timeout, reading.next(100));
    var closing = try connection.begin(.{ .op = "close", .handle = id }, "", 75);
    defer closing.deinit();
    var closed = try closing.next(2000);
    defer closed.deinit();
    try std.testing.expectEqual(frame.Kind.result, closed.kind);
    try writer.writeStreamingAll(io, "leased-through-close-Ω🦊");
    var bytes = try reading.next(2000);
    defer bytes.deinit();
    try std.testing.expectEqual(frame.Kind.result, bytes.kind);
    try std.testing.expectEqualStrings("leased-through-close-Ω🦊", bytes.payload);
    var stale = try connection.begin(.{ .op = "pread", .handle = id, .length = 1 }, "", 75);
    defer stale.deinit();
    var rejected = try stale.next(2000);
    defer rejected.deinit();
    try std.testing.expectEqualStrings("EBADF", rejected.json.value.object.get("code").?.string);
}
test "polite transport EOF cancels and reaps native workers blocked in FIFO open without a writer" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var root_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buffer);
    const path = try std.fmt.allocPrintSentinel(gpa, "{s}/blocked", .{root_buffer[0..root_len]}, 0);
    defer gpa.free(path);
    try std.testing.expectEqual(@as(c_int, 0), mkfifo(path, 0o600));
    var child = try std.process.spawn(io, .{ .argv = &.{ program, "serve", "--token", "0123456789abcdef" }, .stdin = .pipe, .stdout = .pipe, .stderr = .inherit, .pgid = 0 });
    var control = try @import("../durable/process_ownership.zig").Control.initWithFlags(&child, 0x1c00);
    defer control.deinit();
    var reaped = false;
    defer if (!reaped) {
        control.kill();
        child.kill(io);
    };
    const Waiter = struct {
        child: *std.process.Child,
        done: std.atomic.Value(bool) = .init(false),
        term: ?std.process.Child.Term = null,
        fn wait(self: *@This(), inner: std.Io) !void {
            self.term = try self.child.wait(inner);
            self.done.store(true, .release);
        }
    };
    var sync_buffer: [128]u8 = undefined;
    var sync = child.stdout.?.readerStreaming(io, &sync_buffer);
    const line = try sync.interface.takeDelimiterExclusive('\n');
    try std.testing.expectEqualStrings("PI-ENV 0123456789abcdef", line);
    const encoded = try frame.encode(gpa, .request, 7, .{ .op = "open", .path = @as([]const u8, path), .mode = "read" }, "");
    defer gpa.free(encoded);
    try child.stdin.?.writeStreamingAll(io, encoded);
    // Let the actual worker enter the blocking open before ending the input.
    try io.sleep(.fromMilliseconds(100), .awake);
    child.stdin.?.close(io);
    child.stdin = null;
    var waiter: Waiter = .{ .child = &child };
    var waited = try io.concurrent(Waiter.wait, .{ &waiter, io });
    defer _ = waited.cancel(io) catch {};
    const until = std.Io.Clock.awake.now(io).toMilliseconds() + 2000;
    while (!waiter.done.load(.acquire) and std.Io.Clock.awake.now(io).toMilliseconds() < until) try io.sleep(.fromMilliseconds(10), .awake);
    try std.testing.expect(waiter.done.load(.acquire));
    try waited.await(io);
    reaped = true;
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, waiter.term.?);
}
