//! Linux PTY fixtures with bounded IO and exact, unreaped-child ownership.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const Io = std.Io;

/// Resolve relative fixture executables before a child changes to its scratch
/// cwd. std.fs.path.resolve normalizes paths but does not query the current dir.
pub fn executablePath(gpa: std.mem.Allocator, io: Io, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path)) return std.fs.path.resolve(gpa, &.{path});
    var buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const length = try std.process.currentPath(io, &buffer);
    return std.fs.path.resolve(gpa, &.{ buffer[0..length], path });
}

test "native fixture executable paths stay absolute across child cwd changes" {
    const gpa = std.testing.allocator;
    const path = try executablePath(gpa, std.testing.io, "zig-out/bin/pi");
    defer gpa.free(path);
    try std.testing.expect(std.fs.path.isAbsolute(path));
    try std.testing.expect(std.mem.endsWith(u8, path, if (builtin.os.tag == .windows) "zig-out\\bin\\pi" else "zig-out/bin/pi"));
}

fn executablePathAllocationCase(gpa: std.mem.Allocator) !void {
    const path = try executablePath(gpa, std.testing.io, "zig-out/bin/pi");
    defer gpa.free(path);
    try std.testing.expect(std.fs.path.isAbsolute(path));
    const absolute = try executablePath(gpa, std.testing.io, path);
    defer gpa.free(absolute);
    try std.testing.expectEqualStrings(path, absolute);
}

test "native executable path resolution releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, executablePathAllocationCase, .{});
}
pub const Scratch = struct {
    gpa: std.mem.Allocator,
    io: Io,
    parent: Io.Dir,
    dir: Io.Dir,
    name: []u8,
    path: []u8,

    pub fn init(gpa: std.mem.Allocator, io: Io, label: []const u8) !Scratch {
        if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
        const parent = try Io.Dir.openDirAbsolute(io, "/tmp", .{});
        errdefer parent.close(io);
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        const name = try std.fmt.allocPrint(gpa, "pi-native-{s}-{s}", .{ label, std.fmt.bytesToHex(random, .lower) });
        errdefer gpa.free(name);
        try parent.createDir(io, name, @enumFromInt(0o700));
        errdefer parent.deleteTree(io, name) catch {};
        const dir = try parent.openDir(io, name, .{});
        errdefer dir.close(io);
        const path = try std.fs.path.join(gpa, &.{ "/tmp", name });
        return .{ .gpa = gpa, .io = io, .parent = parent, .dir = dir, .name = name, .path = path };
    }

    pub fn deinit(self: *Scratch) void {
        self.dir.close(self.io);
        // Only this exclusively created relative name beneath the /tmp handle.
        self.parent.deleteTree(self.io, self.name) catch |err| std.debug.print("Owned PTY scratch cleanup: {s}\n", .{@errorName(err)});
        self.parent.close(self.io);
        self.gpa.free(self.path);
        self.gpa.free(self.name);
    }
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    io: Io,
    master: linux.fd_t,
    child: std.process.Child,
    output: std.ArrayList(u8) = .empty,
    term: ?std.process.Child.Term = null,
    eof: bool = false,
    operation_deadline_ms: i64,

    pub fn spawn(gpa: std.mem.Allocator, io: Io, options: std.process.SpawnOptions, timeout_ms: u32) !Session {
        if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
        const opened = linux.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true, .CLOEXEC = true, .NONBLOCK = true }, 0);
        if (linux.errno(opened) != .SUCCESS) return error.PtyOpenFailed;
        const master: linux.fd_t = @intCast(opened);
        errdefer _ = linux.close(master);
        var unlocked: c_int = 0;
        if (linux.errno(linux.ioctl(master, linux.T.IOCSPTLCK, @intFromPtr(&unlocked))) != .SUCCESS) return error.PtyUnlockFailed;
        const peer_result = linux.ioctl(master, linux.T.IOCGPTPEER, @as(u32, @bitCast(linux.O{ .ACCMODE = .RDWR, .NOCTTY = true, .CLOEXEC = true })));
        if (linux.errno(peer_result) != .SUCCESS) return error.PtyPeerOpenFailed;
        const peer: linux.fd_t = @intCast(peer_result);
        defer _ = linux.close(peer);
        var dimensions: std.posix.winsize = .{ .row = 40, .col = 100, .xpixel = 0, .ypixel = 0 };
        if (linux.errno(linux.ioctl(peer, linux.T.IOCSWINSZ, @intFromPtr(&dimensions))) != .SUCCESS) return error.PtyResizeFailed;
        var configured = options;
        const slave: Io.File = .{ .handle = peer, .flags = .{ .nonblocking = false } };
        configured.stdin = .{ .file = slave };
        configured.stdout = .{ .file = slave };
        const child = std.process.spawn(io, configured) catch |err| {
            std.debug.print("PTY spawn failure: {s}; program={s}; cwd={s}; master={d}; slave={d}\n", .{ @errorName(err), configured.argv[0], switch (configured.cwd) {
                .path => |path| path,
                else => "inherited/dir",
            }, master, peer });
            return err;
        };
        return .{ .gpa = gpa, .io = io, .master = master, .child = child, .operation_deadline_ms = now(io) + timeout_ms };
    }

    fn now(io: Io) i64 {
        return Io.Clock.awake.now(io).toMilliseconds();
    }

    fn deadline(self: *Session, timeout_ms: u32) i64 {
        return @min(self.operation_deadline_ms, now(self.io) + timeout_ms);
    }

    fn poll(self: *Session, events: i16, end: i64) !void {
        const remaining = end - now(self.io);
        if (remaining <= 0) return;
        var descriptor: linux.pollfd = .{ .fd = self.master, .events = events, .revents = 0 };
        switch (linux.errno(linux.poll(@ptrCast(&descriptor), 1, @intCast(@min(remaining, 50))))) {
            .SUCCESS, .INTR => {},
            else => return error.PtyPollFailed,
        }
        if (descriptor.revents & linux.POLL.NVAL != 0) return error.PtyInvalidDescriptor;
    }

    pub fn drain(self: *Session) !void {
        if (self.eof) return;
        var buffer: [65536]u8 = undefined;
        while (true) {
            const count = linux.read(self.master, &buffer, buffer.len);
            switch (linux.errno(count)) {
                .SUCCESS => {
                    if (count == 0) {
                        self.eof = true;
                        return;
                    }
                    if (self.output.items.len + count > 8 * 1024 * 1024) return error.PtyOutputLimit;
                    try self.output.appendSlice(self.gpa, buffer[0..count]);
                },
                .AGAIN => return,
                .INTR => continue,
                .IO => {
                    // Linux PTY masters report EIO once every slave is closed.
                    self.eof = true;
                    return;
                },
                else => return error.PtyReadFailed,
            }
        }
    }

    pub fn send(self: *Session, bytes: []const u8) !void {
        const end = self.deadline(5000);
        var written: usize = 0;
        while (written < bytes.len) {
            if (now(self.io) >= end) return error.PtyTimeout;
            const count = linux.write(self.master, bytes[written..].ptr, bytes.len - written);
            switch (linux.errno(count)) {
                .SUCCESS => {
                    if (count == 0) return error.PtyWriteFailed;
                    written += count;
                },
                .AGAIN => try self.poll(linux.POLL.OUT, end),
                .INTR => continue,
                else => return error.PtyWriteFailed,
            }
        }
    }

    /// Observe termination without reaping: this exact spawned PID cannot be
    /// reused before our own Child.wait, and no unrelated process is signalled.
    pub fn exited(self: *Session) !bool {
        if (self.term != null) return true;
        const pid = self.child.id orelse return error.PtyChildAlreadyReaped;
        var info = std.mem.zeroes(linux.siginfo_t);
        switch (linux.errno(linux.waitid(.PID, pid, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null))) {
            .SUCCESS => return @intFromEnum(info.signo) != 0,
            .INTR => return false,
            else => return error.PtyChildObserveFailed,
        }
    }

    pub fn waitFor(self: *Session, marker: []const u8, start: usize, timeout_ms: u32) !usize {
        const end = self.deadline(timeout_ms);
        while (true) {
            try self.drain();
            if (std.mem.indexOfPos(u8, self.output.items, @min(start, self.output.items.len), marker)) |found| return found + marker.len;
            if (self.eof or try self.exited()) break;
            if (now(self.io) >= end) break;
            try self.poll(linux.POLL.IN, end);
        }
        std.debug.print("PTY missing marker {s}; tail:\n{s}\n", .{ marker, self.output.items[self.output.items.len - @min(self.output.items.len, 8000) ..] });
        return error.PtyMarkerMissing;
    }

    fn waitUntilExited(self: *Session, end: i64, capture_output: bool) !std.process.Child.Term {
        while (!try self.exited()) {
            if (capture_output) try self.drain();
            if (now(self.io) >= end) return error.PtyChildTimeout;
            // A hung-up master is always poll-ready; use a bounded sleep to
            // avoid spinning while the owned child finishes its cleanup.
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        if (capture_output) try self.drain();
        // NOWAIT proved the child exited, so this wait cannot wait on live work.
        self.term = try self.child.wait(self.io);
        return self.term.?;
    }

    pub fn wait(self: *Session, timeout_ms: u32) !std.process.Child.Term {
        return self.waitUntilExited(self.deadline(timeout_ms), true);
    }

    pub fn stopOwned(self: *Session) !void {
        if (self.term != null) return;
        if (!try self.exited()) {
            const pid = self.child.id orelse return error.PtyChildAlreadyReaped;
            if (linux.errno(linux.kill(pid, .KILL)) != .SUCCESS) return error.PtyChildKillFailed;
        }
        // Reaping must remain possible after output allocation or limit failure.
        _ = try self.waitUntilExited(now(self.io) + 3000, false);
    }

    pub fn deinit(self: *Session) void {
        self.stopOwned() catch |err| std.debug.print("Owned PTY child cleanup failed: {s}\n", .{@errorName(err)});
        _ = linux.close(self.master);
        self.output.deinit(self.gpa);
    }
};

test "Linux PTY helper bounds missing output and reaps only its exact spawned child" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var session = try Session.spawn(std.testing.allocator, std.testing.io, .{ .argv = &.{ "/bin/sleep", "60" }, .stderr = .ignore }, 5000);
    defer session.deinit();
    try std.testing.expectError(error.PtyMarkerMissing, session.waitFor("never printed", 0, 20));
    try session.stopOwned();
    try std.testing.expect(session.child.id == null);
    try std.testing.expect(session.term.? == .signal and session.term.?.signal == .KILL);
}

test "Linux PTY helper can reap its owned child after output allocation failure" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var session = try Session.spawn(allocator.allocator(), std.testing.io, .{ .argv = &.{"/bin/cat"}, .stderr = .ignore }, 5000);
    defer session.deinit();
    try session.send("allocation-failure\n");
    try std.testing.expectError(error.OutOfMemory, session.waitFor("allocation-failure", 0, 1000));
    try session.stopOwned();
    try std.testing.expect(session.child.id == null);
    try std.testing.expect(session.term.? == .signal and session.term.?.signal == .KILL);
}
