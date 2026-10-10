//! Real native pipe process harness with bounded IO and exact child ownership.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const Io = std.Io;

pub const Process = struct {
    gpa: std.mem.Allocator,
    io: Io,
    child: std.process.Child,
    output: std.ArrayList(u8) = .empty,
    cursor: usize = 0,
    eof: bool = false,
    term: ?std.process.Child.Term = null,
    operation_deadline_ms: i64,

    fn now(io: Io) i64 {
        return Io.Clock.awake.now(io).toMilliseconds();
    }

    fn nonblocking(fd: linux.fd_t) !void {
        const flags = linux.fcntl(fd, linux.F.GETFL, 0);
        if (linux.errno(flags) != .SUCCESS) return error.NativePipeFlagsFailed;
        const nonblock: u32 = @bitCast(linux.O{ .NONBLOCK = true });
        if (linux.errno(linux.fcntl(fd, linux.F.SETFL, flags | nonblock)) != .SUCCESS) return error.NativePipeFlagsFailed;
    }

    pub fn spawn(gpa: std.mem.Allocator, io: Io, options: std.process.SpawnOptions, timeout_ms: u32) !Process {
        if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
        var configured = options;
        configured.stdout = .pipe;
        var self: Process = .{ .gpa = gpa, .io = io, .child = try std.process.spawn(io, configured), .operation_deadline_ms = now(io) + timeout_ms };
        errdefer self.deinit();
        try nonblocking(self.child.stdout.?.handle);
        if (self.child.stdin) |input| try nonblocking(input.handle);
        return self;
    }

    fn deadline(self: *Process, timeout_ms: u32) i64 {
        return @min(self.operation_deadline_ms, now(self.io) + timeout_ms);
    }

    fn poll(self: *Process, fd: linux.fd_t, events: i16, end: i64) !void {
        const remaining = end - now(self.io);
        if (remaining <= 0) return;
        var descriptor: linux.pollfd = .{ .fd = fd, .events = events, .revents = 0 };
        switch (linux.errno(linux.poll(@ptrCast(&descriptor), 1, @intCast(@min(remaining, 50))))) {
            .SUCCESS, .INTR => {},
            else => return error.NativePipePollFailed,
        }
        if (descriptor.revents & linux.POLL.NVAL != 0) return error.NativePipeInvalidDescriptor;
    }

    pub fn drain(self: *Process) !void {
        if (self.eof or self.child.stdout == null) return;
        var buffer: [65536]u8 = undefined;
        while (true) {
            const count = linux.read(self.child.stdout.?.handle, &buffer, buffer.len);
            switch (linux.errno(count)) {
                .SUCCESS => {
                    if (count == 0) {
                        self.eof = true;
                        return;
                    }
                    if (self.output.items.len + count > 8 * 1024 * 1024) return error.NativePipeOutputLimit;
                    try self.output.appendSlice(self.gpa, buffer[0..count]);
                },
                .INTR => continue,
                .AGAIN => return,
                else => return error.NativePipeReadFailed,
            }
        }
    }

    pub fn send(self: *Process, bytes: []const u8) !void {
        const input = self.child.stdin orelse return error.NativePipeInputClosed;
        const end = self.deadline(5000);
        var offset: usize = 0;
        while (offset < bytes.len) {
            if (now(self.io) >= end) return error.NativePipeTimeout;
            const count = linux.write(input.handle, bytes[offset..].ptr, bytes.len - offset);
            switch (linux.errno(count)) {
                .SUCCESS => {
                    if (count == 0) return error.NativePipeWriteFailed;
                    offset += count;
                },
                .INTR => continue,
                .AGAIN => try self.poll(input.handle, linux.POLL.OUT, end),
                else => return error.NativePipeWriteFailed,
            }
        }
    }

    pub fn closeInput(self: *Process) void {
        if (self.child.stdin) |input| input.close(self.io);
        self.child.stdin = null;
    }

    pub fn exited(self: *Process) !bool {
        if (self.term != null) return true;
        const pid = self.child.id orelse return error.NativePipeChildAlreadyReaped;
        var info = std.mem.zeroes(linux.siginfo_t);
        switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null))) {
            .SUCCESS => return @intFromEnum(info.signo) != 0,
            .INTR => return false,
            else => return error.NativePipeChildObserveFailed,
        }
    }

    /// Caller owns each returned line; accumulated raw output stays available.
    pub fn line(self: *Process, timeout_ms: u32) ![]u8 {
        const end = self.deadline(timeout_ms);
        while (true) {
            try self.drain();
            if (std.mem.indexOfScalarPos(u8, self.output.items, self.cursor, '\n')) |newline| {
                const result = try self.gpa.dupe(u8, self.output.items[self.cursor..newline]);
                self.cursor = newline + 1;
                return result;
            }
            if (self.eof or try self.exited()) return error.NativePipeEndOfStream;
            if (now(self.io) >= end) return error.NativePipeTimeout;
            try self.poll(self.child.stdout.?.handle, linux.POLL.IN, end);
        }
    }

    fn waitUntilExited(self: *Process, end: i64, capture_output: bool) !std.process.Child.Term {
        while (!try self.exited()) {
            if (capture_output) try self.drain();
            if (now(self.io) >= end) return error.NativePipeChildTimeout;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        if (capture_output) try self.drain();
        self.term = try self.child.wait(self.io);
        return self.term.?;
    }

    pub fn wait(self: *Process, timeout_ms: u32) !std.process.Child.Term {
        return self.waitUntilExited(self.deadline(timeout_ms), true);
    }

    pub fn stopOwned(self: *Process) !void {
        if (self.term != null) return;
        if (!try self.exited()) {
            const pid = self.child.id orelse return error.NativePipeChildAlreadyReaped;
            if (linux.errno(linux.kill(pid, .KILL)) != .SUCCESS) return error.NativePipeChildKillFailed;
        }
        _ = try self.waitUntilExited(now(self.io) + 3000, false);
    }

    pub fn deinit(self: *Process) void {
        self.stopOwned() catch |err| std.debug.print("Owned native pipe cleanup failed: {s}\n", .{@errorName(err)});
        self.output.deinit(self.gpa);
    }
};

test "native RPC pipes preserve JSON lines EOF and exact-child cleanup" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var child = try Process.spawn(std.testing.allocator, std.testing.io, .{ .argv = &.{"/bin/cat"}, .stdin = .pipe, .stderr = .ignore }, 5000);
    defer child.deinit();
    try child.send("{\"id\":\"native\"}\n{\"kind\":\"second\"}\n");
    const first = try child.line(1000);
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("{\"id\":\"native\"}", first);
    const second = try child.line(1000);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("{\"kind\":\"second\"}", second);
    try std.testing.expectError(error.NativePipeTimeout, child.line(20));
    child.closeInput();
    const term = try child.wait(1000);
    try std.testing.expect(term == .exited and term.exited == 0);
    try std.testing.expect(child.child.id == null);
}

test "native RPC pipe cleanup remains possible after captured output allocation fails" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var child = try Process.spawn(allocator.allocator(), std.testing.io, .{ .argv = &.{"/bin/cat"}, .stdin = .pipe, .stderr = .ignore }, 5000);
    defer child.deinit();
    try child.send("native\n");
    try std.testing.expectError(error.OutOfMemory, child.line(1000));
    try child.stopOwned();
    try std.testing.expect(child.child.id == null);
}
