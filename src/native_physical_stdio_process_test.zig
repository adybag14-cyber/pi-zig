//! Real pipe checks for the physical owner shared by Main and native workers.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
extern fn pi_durable_peek_child(pid: c_int, exit_code: *i64) callconv(.c) c_int;

const Capture = struct {
    file: Io.File,
    bytes: std.ArrayList(u8) = .empty,
    ready: std.atomic.Value(bool) = .init(false),
    failure: ?anyerror = null,
    fn run(self: *Capture) void {
        var buffer: [4096]u8 = undefined;
        while (true) {
            var vectors = [_][]u8{&buffer};
            const count = self.file.readStreaming(std.testing.io, &vectors) catch |err| {
                if (err != error.EndOfStream and err != error.Canceled) self.failure = err;
                return;
            };
            if (count == 0) return;
            if (self.bytes.items.len + count > 65536) {
                self.failure = error.PhysicalOutputLimit;
                return;
            }
            self.bytes.appendSlice(std.testing.allocator, buffer[0..count]) catch |err| {
                self.failure = err;
                return;
            };
            if (std.mem.indexOf(u8, self.bytes.items, "PHYSICAL_READY\n") != null) self.ready.store(true, .release);
        }
    }
};

fn exited(child: *std.process.Child) !bool {
    if (comptime builtin.os.tag == .windows) {
        var timeout: std.os.windows.LARGE_INTEGER = -1;
        return switch (std.os.windows.ntdll.NtWaitForSingleObject(child.id.?, .FALSE, &timeout)) {
            .WAIT_0 => true,
            .TIMEOUT => false,
            else => error.PhysicalChildStatusFailed,
        };
    } else {
        var code: i64 = 0;
        return switch (pi_durable_peek_child(child.id.?, &code)) {
            0 => false,
            1 => true,
            else => error.PhysicalChildStatusFailed,
        };
    }
}

fn physicalPipe(cancel: bool) !void {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, allocator);
    defer environment.deinit();
    const binary = environment.get("PI_PHYSICAL_STDIO_TEST_BINARY") orelse return error.MissingPhysicalFixture;
    const arguments: []const []const u8 = if (cancel) &.{ binary, "cancel" } else &.{binary};
    var child = try std.process.spawn(io, .{ .argv = arguments, .environ_map = &environment, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe, .create_no_window = true });
    var waited = false;
    defer if (!waited) {
        child.kill(io);
        _ = child.wait(io) catch {};
    };
    const input = child.stdin.?;
    var input_open = true;
    defer if (input_open) input.close(io);
    const output = child.stdout.?;
    defer output.close(io);
    const errors = child.stderr.?;
    defer errors.close(io);
    var stdout: Capture = .{ .file = output };
    defer stdout.bytes.deinit(allocator);
    var stderr: Capture = .{ .file = errors };
    defer stderr.bytes.deinit(allocator);
    var readers: Io.Group = .init;
    defer {
        readers.cancel(io);
        readers.await(io) catch {};
    }
    try readers.concurrent(io, Capture.run, .{&stdout});
    try readers.concurrent(io, Capture.run, .{&stderr});
    const ready_deadline = Io.Clock.awake.now(io).toMilliseconds() + 10000;
    while (!stdout.ready.load(.acquire)) {
        if (try exited(&child)) return error.PhysicalChildExitedBeforeReady;
        if (Io.Clock.awake.now(io).toMilliseconds() >= ready_deadline) return error.PhysicalReadyTimeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
    const bytes = "aΩ🦊z\x00\xff";
    try input.writeStreamingAll(io, bytes);
    if (!cancel) {
        input.close(io);
        input_open = false;
    }
    const exit_deadline = Io.Clock.awake.now(io).toMilliseconds() + 10000;
    while (!try exited(&child)) {
        if (Io.Clock.awake.now(io).toMilliseconds() >= exit_deadline) return error.PhysicalChildExitTimeout;
        try io.sleep(.fromMilliseconds(5), .awake);
    }
    const termination = try child.wait(io);
    waited = true;
    try readers.await(io);
    if (termination != .exited or termination.exited != 0) std.debug.print("Physical child failed: {s}\n", .{stderr.bytes.items});
    try std.testing.expect(termination == .exited and termination.exited == 0);
    if (stdout.failure) |failure| return failure;
    if (stderr.failure) |failure| return failure;
    try std.testing.expectEqualStrings("", stderr.bytes.items);
    if (cancel) {
        // No EOF was sent: deinit must cancel and join its physical read.
        try std.testing.expect(input_open);
        try std.testing.expectEqualStrings("PHYSICAL_READY\nPHYSICAL_CANCEL\n", stdout.bytes.items);
    } else {
        const expected = try std.fmt.allocPrint(allocator, "PHYSICAL_READY\nPHYSICAL_MATCH {d}\n", .{bytes.len});
        defer allocator.free(expected);
        try std.testing.expectEqualStrings(expected, stdout.bytes.items);
    }
}

test "physical stdio process fans out actual binary Unicode input and EOF to Main and replacement sinks" {
    try physicalPipe(false);
}
test "physical stdio process joins its blocked physical reader while parent stdin remains open" {
    try physicalPipe(true);
}
