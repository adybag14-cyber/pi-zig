//! Physical framed daemon tests; no JavaScript host or substitute terminal.
const std = @import("std");
const native = @import("connection.zig");
const wire = @import("frame.zig");
const client = @import("terminal.zig");
fn connect() !*native.Connection {
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    const program = environment.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    return native.Connection.start(std.testing.allocator, std.testing.io, &.{program}, 9719);
}
fn request(connection: *native.Connection, value: anytype, payload: []const u8) !wire.Frame {
    var ticket = try connection.begin(value, payload, 9719);
    defer ticket.deinit();
    return ticket.next(5000);
}
fn control(connection: *native.Connection, value: anytype, payload: []const u8) !void {
    var reply = try request(connection, value, payload);
    defer reply.deinit();
    try std.testing.expectEqual(wire.Kind.result, reply.kind);
    try std.testing.expectEqual(@as(usize, 0), reply.json.value.object.count());
    try std.testing.expectEqual(@as(usize, 0), reply.payload.len);
}
fn open(connection: *native.Connection) !native.Ticket {
    var ticket = try connection.begin(.{ .op = "pty", .cwd = "/tmp", .argv = &.{ "/bin/sh", "-i" }, .env = .{ .PS1 = "PTY-PROMPT>", .TERM = "xterm-256color" }, .cols = 80, .rows = 24 }, "", 9719);
    errdefer {
        ticket.cancel(false) catch {};
        ticket.deinit();
    }
    var started = try ticket.next(5000);
    defer started.deinit();
    try std.testing.expectEqual(wire.Kind.event, started.kind);
    try std.testing.expectEqualStrings("started", started.json.value.object.get("kind").?.string);
    try std.testing.expect(started.json.value.object.get("pid").?.integer > 0);
    return ticket;
}
fn cleanup(ticket: *native.Ticket) void {
    ticket.cancel(false) catch {};
    for (0..100) |_| {
        var reply = ticket.next(100) catch break;
        const terminal = reply.kind == .result or reply.kind == .remote_error;
        reply.deinit();
        if (terminal) break;
    }
    ticket.deinit();
}
fn output(ticket: native.Ticket, bytes: *std.ArrayList(u8), needle: []const u8) !void {
    const io = std.testing.io;
    const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
    while (std.mem.indexOf(u8, bytes.items, needle) == null) {
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalOutputTimeout;
        var reply = try ticket.next(5000);
        defer reply.deinit();
        try std.testing.expectEqual(wire.Kind.event, reply.kind);
        try std.testing.expectEqualStrings("output", reply.json.value.object.get("kind").?.string);
        try std.testing.expectEqual(@as(usize, 1), reply.json.value.object.count());
        try bytes.appendSlice(std.testing.allocator, reply.payload);
    }
}
test "POSIX terminal framed daemon preserves actual TTY raw output resizing and normal exit" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    var terminal = try open(connection);
    defer cleanup(&terminal);
    var foreground = try request(connection, .{ .op = "ptyForeground", .target = terminal.id }, "");
    defer foreground.deinit();
    try std.testing.expect(foreground.json.value.object.get("foreground").? == .null);
    try control(connection, .{ .op = "ptyWrite", .target = terminal.id }, "test -t 0 && printf 'TTY-OK\\n'; stty size\n");
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    try output(terminal, &bytes, "24 80\r\n");
    try std.testing.expect(std.mem.indexOf(u8, bytes.items, "TTY-OK\r\n") != null);
    try control(connection, .{ .op = "ptyResize", .target = terminal.id, .cols = 100, .rows = 30 }, "");
    try control(connection, .{ .op = "ptyWrite", .target = terminal.id }, "stty size; printf '\\377\\000RAW\\n'; exit 3\n");
    try output(terminal, &bytes, "\xff\x00RAW\r\n");
    try std.testing.expect(std.mem.indexOf(u8, bytes.items, "30 100\r\n") != null);
    while (true) {
        var reply = try terminal.next(5000);
        defer reply.deinit();
        if (reply.kind == .event) continue;
        try std.testing.expectEqual(wire.Kind.result, reply.kind);
        try std.testing.expectEqual(@as(i64, 3), reply.json.value.object.get("exitCode").?.integer);
        break;
    }
    var retired = try request(connection, .{ .op = "ptyResize", .target = terminal.id, .cols = 0, .rows = 0 }, "");
    defer retired.deinit();
    try std.testing.expectEqual(wire.Kind.remote_error, retired.kind);
    try std.testing.expectEqualStrings("EBADF", retired.json.value.object.get("code").?.string);
    try std.testing.expectEqualStrings("no running terminal with this id", retired.json.value.object.get("message").?.string);
}
test "POSIX terminal framed daemon reports the foreground job and retires before aborted outcome" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    var terminal = try open(connection);
    defer cleanup(&terminal);
    try control(connection, .{ .op = "ptyWrite", .target = terminal.id }, "sleep 30\n");
    const io = std.testing.io;
    const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
    while (true) {
        var foreground = try request(connection, .{ .op = "ptyForeground", .target = terminal.id }, "");
        defer foreground.deinit();
        try std.testing.expectEqual(wire.Kind.result, foreground.kind);
        const job = foreground.json.value.object.get("foreground").?;
        if (job == .object) {
            try std.testing.expect(job.object.get("pid").?.integer > 0);
            const name = job.object.get("name").?;
            if (name == .string and std.mem.eql(u8, name.string, "sleep")) break;
        }
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalForegroundTimeout;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    try terminal.cancel(false);
    while (true) {
        var reply = try terminal.next(5000);
        defer reply.deinit();
        if (reply.kind == .event) continue;
        try std.testing.expectEqual(wire.Kind.remote_error, reply.kind);
        try std.testing.expectEqualStrings("aborted", reply.json.value.object.get("code").?.string);
        try std.testing.expectEqualStrings("aborted", reply.json.value.object.get("message").?.string);
        break;
    }
    var retired = try request(connection, .{ .op = "ptyForeground", .target = terminal.id }, "");
    defer retired.deinit();
    try std.testing.expectEqualStrings("EBADF", retired.json.value.object.get("code").?.string);
    try std.testing.expectError(error.StaleDaemonSession, connection.begin(.{ .op = "ptyForeground", .target = terminal.id }, "", 9718));
}
test "native terminal client preserves upstream Windows unsupported error fields" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    const Ignore = struct {
        fn data(_: ?*anyopaque, _: []const u8) void {}
    };
    var result = try client.Terminal.open(std.testing.allocator, std.testing.io, .{ .native = connection }, .{ .cwd = ".", .cols = 80, .rows = 24, .onData = Ignore.data });
    try std.testing.expect(result == .failure);
    defer result.failure.deinit();
    try std.testing.expectEqualStrings("ENOTSUP", result.failure.code());
    try std.testing.expectEqualStrings("Terminals are not supported on this system yet", result.failure.message());
    try std.testing.expectEqual(@as(usize, 2), result.failure.fields.value.object.count());
}
test "native terminal client retains raw output normal exit and retired foreground failure" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    const Capture = struct {
        io: std.Io,
        mutex: std.Io.Mutex = .init,
        bytes: std.ArrayList(u8) = .empty,
        failure: bool = false,
        fn data(raw: ?*anyopaque, bytes: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            self.bytes.appendSlice(std.heap.page_allocator, bytes) catch {
                self.failure = true;
            };
        }
    };
    var capture: Capture = .{ .io = std.testing.io };
    defer capture.bytes.deinit(std.heap.page_allocator);
    const opened = try client.Terminal.open(std.testing.allocator, std.testing.io, .{ .native = connection }, .{ .cwd = "/tmp", .argv = &.{ "/bin/sh", "-c", "printf '\\377\\000CLIENT\\n'; exit 7" }, .cols = 80, .rows = 24, .onData = Capture.data, .context = &capture });
    try std.testing.expect(opened == .terminal);
    const terminal = opened.terminal;
    defer terminal.deinit();
    const outcome = try terminal.wait(std.testing.allocator);
    try std.testing.expect(outcome == .exit_code);
    try std.testing.expectEqual(@as(i64, 7), outcome.exit_code);
    const repeated = try terminal.wait(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 7), repeated.exit_code);
    capture.mutex.lockUncancelable(std.testing.io);
    const found = !capture.failure and std.mem.indexOf(u8, capture.bytes.items, "\xff\x00CLIENT\r\n") != null;
    capture.mutex.unlock(std.testing.io);
    try std.testing.expect(found);
    var foreground = try terminal.foreground(std.testing.allocator);
    try std.testing.expect(foreground == .failure);
    defer foreground.failure.deinit();
    try std.testing.expectEqualStrings("EBADF", foreground.failure.code());
}
test "native terminal client ordered input resize foreground and abort use the original daemon session" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    const Ignore = struct {
        fn data(_: ?*anyopaque, _: []const u8) void {}
    };
    const opened = try client.Terminal.open(std.testing.allocator, std.testing.io, .{ .native = connection }, .{ .cwd = "/tmp", .argv = &.{ "/bin/sh", "-i" }, .cols = 80, .rows = 24, .onData = Ignore.data });
    try std.testing.expect(opened == .terminal);
    const terminal = opened.terminal;
    defer terminal.deinit();
    terminal.resize(100, 30);
    terminal.write("sleep 30\n");
    const io = std.testing.io;
    const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(5));
    while (true) {
        var foreground = try terminal.foreground(std.testing.allocator);
        try std.testing.expect(foreground == .job);
        if (foreground.job) |*job| {
            const found = job.pid != terminal.pid and job.name != null and std.mem.eql(u8, job.name.?, "sleep");
            job.deinit(std.testing.allocator);
            if (found) break;
        }
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalForegroundTimeout;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    terminal.close();
    var outcome = try terminal.wait(std.testing.allocator);
    try std.testing.expect(outcome == .failure);
    defer outcome.failure.deinit();
    try std.testing.expectEqualStrings("aborted", outcome.failure.code());
    try std.testing.expectEqualStrings("aborted", outcome.failure.message());
}
test "native terminal client chunks input beyond the protocol frame limit without changing raw bytes" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const connection = try connect();
    defer connection.deinit();
    const Capture = struct {
        io: std.Io,
        mutex: std.Io.Mutex = .init,
        bytes: std.ArrayList(u8) = .empty,
        failed: bool = false,
        fn data(raw: ?*anyopaque, bytes: []const u8) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            self.bytes.appendSlice(std.heap.page_allocator, bytes) catch {
                self.failed = true;
            };
        }
        fn length(self: *@This()) !usize {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            if (self.failed) return error.TerminalCaptureAllocationFailed;
            return self.bytes.items.len;
        }
    };
    const io = std.testing.io;
    var capture: Capture = .{ .io = io };
    defer capture.bytes.deinit(std.heap.page_allocator);
    const opened = try client.Terminal.open(std.testing.allocator, io, .{ .native = connection }, .{ .cwd = "/tmp", .argv = &.{ "/bin/sh", "-c", "stty raw -echo; printf READY; exec cat" }, .cols = 80, .rows = 24, .onData = Capture.data, .context = &capture });
    try std.testing.expect(opened == .terminal);
    const terminal = opened.terminal;
    defer terminal.deinit();
    var deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(10));
    while (try capture.length() < 5) {
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalReadyTimeout;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    const payload = try std.testing.allocator.alloc(u8, wire.maximum_frame + 1024 * 1024 + 17);
    defer std.testing.allocator.free(payload);
    for (payload, 0..) |*byte, index| byte.* = @truncate(index * 17 + 33);
    terminal.write(payload);
    deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(10));
    while (try capture.length() < payload.len + 5) {
        if (std.Io.Clock.awake.now(io).nanoseconds >= deadline.nanoseconds) return error.TerminalPayloadTimeout;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    capture.mutex.lockUncancelable(io);
    const exact = std.mem.eql(u8, capture.bytes.items[0..5], "READY") and std.mem.eql(u8, capture.bytes.items[5..], payload);
    capture.mutex.unlock(io);
    try std.testing.expect(exact);
    terminal.close();
    var outcome = try terminal.wait(std.testing.allocator);
    try std.testing.expect(outcome == .failure);
    defer outcome.failure.deinit();
    try std.testing.expectEqualStrings("aborted", outcome.failure.code());
}
