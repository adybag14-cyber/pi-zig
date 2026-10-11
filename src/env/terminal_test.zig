//! Physical framed daemon tests; no JavaScript host or substitute terminal.
const std = @import("std");
const native = @import("connection.zig");
const wire = @import("frame.zig");
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
