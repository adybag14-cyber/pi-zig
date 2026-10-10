//! Darwin libc PTY fixture with nonblocking capture and unreaped-PID ownership.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
extern "c" fn openpty(*c_int, *c_int, ?[*:0]u8, ?*const std.posix.termios, ?*const std.posix.winsize) c_int;
extern "c" fn waitid(c_int, u32, *std.c.siginfo_t, c_int) c_int;
pub const Session = struct {
    gpa: std.mem.Allocator,
    io: Io,
    master: c_int,
    child: std.process.Child,
    output: std.ArrayList(u8) = .empty,
    term: ?std.process.Child.Term = null,
    eof: bool = false,
    operation_deadline_ms: i64,
    pub fn spawn(gpa: std.mem.Allocator, io: Io, options: std.process.SpawnOptions, timeout_ms: u32) !Session {
        if (comptime builtin.os.tag != .macos) return error.SkipZigTest;
        var master: c_int = undefined;
        var slave: c_int = undefined;
        const size: std.posix.winsize = .{ .row = 40, .col = 100, .xpixel = 0, .ypixel = 0 };
        if (openpty(&master, &slave, null, null, &size) != 0) return error.PtyOpenFailed;
        errdefer _ = std.c.close(master);
        defer _ = std.c.close(slave);
        const current = std.c.fcntl(master, std.posix.F.GETFL);
        if (current < 0 or std.c.fcntl(master, std.posix.F.SETFL, current | @as(c_int, @bitCast(std.posix.O{ .NONBLOCK = true }))) < 0) return error.PtyNonblockingFailed;
        if (std.c.fcntl(master, std.posix.F.SETFD, @as(c_int, 1)) < 0 or std.c.fcntl(slave, std.posix.F.SETFD, @as(c_int, 1)) < 0) return error.PtyCloseOnExecFailed;
        var configured = options;
        const terminal: Io.File = .{ .handle = slave, .flags = .{ .nonblocking = false } };
        configured.stdin = .{ .file = terminal };
        configured.stdout = .{ .file = terminal };
        const child = try std.process.spawn(io, configured);
        return .{ .gpa = gpa, .io = io, .master = master, .child = child, .operation_deadline_ms = now(io) + timeout_ms };
    }
    fn now(io: Io) i64 {
        return Io.Clock.awake.now(io).toMilliseconds();
    }
    fn deadline(self: *Session, ms: u32) i64 {
        return @min(self.operation_deadline_ms, now(self.io) + ms);
    }
    fn poll(self: *Session, event: i16, end: i64) !void {
        const remaining = end - now(self.io);
        if (remaining <= 0) return error.PtyTimeout;
        var fd: std.posix.pollfd = .{ .fd = self.master, .events = event, .revents = 0 };
        _ = try std.posix.poll(@as(*[1]std.posix.pollfd, @ptrCast(&fd)), @intCast(@min(remaining, 50)));
    }
    pub fn drain(self: *Session) !void {
        if (self.eof) return;
        var buffer: [65536]u8 = undefined;
        while (true) {
            const count = std.c.read(self.master, &buffer, buffer.len);
            if (count > 0) {
                const length: usize = @intCast(count);
                if (length > 8 * 1024 * 1024 - self.output.items.len) return error.PtyOutputLimit;
                try self.output.appendSlice(self.gpa, buffer[0..length]);
            } else if (count == 0) {
                self.eof = true;
                return;
            } else switch (std.posix.errno(count)) {
                .AGAIN => return,
                .INTR => continue,
                .IO => {
                    self.eof = true;
                    return;
                },
                else => return error.PtyReadFailed,
            }
        }
    }
    pub fn send(self: *Session, bytes: []const u8) !void {
        const end = self.deadline(5000);
        var offset: usize = 0;
        while (offset < bytes.len) {
            if (now(self.io) >= end) return error.PtyTimeout;
            const count = std.c.write(self.master, bytes[offset..].ptr, bytes.len - offset);
            if (count > 0) offset += @intCast(count) else if (count == 0) return error.PtyWriteFailed else switch (std.posix.errno(count)) {
                .AGAIN => try self.poll(std.posix.POLL.OUT, end),
                .INTR => continue,
                else => return error.PtyWriteFailed,
            }
        }
    }
    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        var size: std.posix.winsize = .{ .row = rows, .col = columns, .xpixel = 0, .ypixel = 0 };
        // Darwin sys/ttycom.h: _IOW('t', 103, struct winsize).
        const tiocswinsz = 0x80000000 | (@sizeOf(std.posix.winsize) << 16) | ('t' << 8) | 103;
        if (std.posix.errno(std.posix.system.ioctl(self.master, @as(c_int, @bitCast(@as(u32, tiocswinsz))), @intFromPtr(&size))) != .SUCCESS) return error.PtyResizeFailed;
    }
    pub fn hangup(self: *Session) void {
        if (self.master >= 0) _ = std.c.close(self.master);
        self.master = -1;
        self.eof = true;
    }
    pub fn exited(self: *Session) !bool {
        if (self.term != null) return true;
        var info = std.mem.zeroes(std.c.siginfo_t);
        // Darwin sys/wait.h: P_PID=1, WEXITED=4, WNOHANG=1, WNOWAIT=32.
        const rc = waitid(1, @intCast(self.child.id orelse return error.PtyAlreadyReaped), &info, 4 | 1 | 32);
        return switch (std.posix.errno(rc)) {
            .SUCCESS => @intFromEnum(info.signo) != 0,
            .INTR => false,
            else => error.PtyChildObserveFailed,
        };
    }
    pub fn wait(self: *Session, timeout_ms: u32) !std.process.Child.Term {
        const end = self.deadline(timeout_ms);
        while (!try self.exited()) {
            try self.drain();
            if (now(self.io) >= end) return error.PtyChildTimeout;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        try self.drain();
        if (self.term == null) self.term = try self.child.wait(self.io);
        return self.term.?;
    }
    pub fn waitFor(self: *Session, marker: []const u8, start: usize, timeout_ms: u32) !usize {
        const end = self.deadline(timeout_ms);
        while (now(self.io) < end) {
            try self.drain();
            if (std.mem.indexOfPos(u8, self.output.items, @min(start, self.output.items.len), marker)) |position| return position + marker.len;
            if (try self.exited()) break;
            try self.poll(std.posix.POLL.IN, end);
        }
        return error.PtyMarkerMissing;
    }
    pub fn deinit(self: *Session) void {
        if (self.term == null) {
            if (!(self.exited() catch false)) std.posix.kill(self.child.id.?, .KILL) catch {};
            const end = now(self.io) + 3000;
            while (!(self.exited() catch true) and now(self.io) < end) self.io.sleep(.fromMilliseconds(10), .awake) catch break;
            if (self.exited() catch false) self.term = self.child.wait(self.io) catch null;
        }
        self.hangup();
        self.output.deinit(self.gpa);
    }
};
