//! Byte-only owned executable transport for core/exec.ts (no shell expansion).
//! The process handle remains owned through post-exit pipe draining. Neither a
//! requested SIGTERM nor quiet inherited stdio permits killing a descendant.
const std = @import("std");
const builtin = @import("builtin");
pub const Stream = enum { stdout, stderr };
pub const Control = struct {
    terminate: std.atomic.Value(bool) = .init(false),
    force: std.atomic.Value(bool) = .init(false),
    shutdown: std.atomic.Value(bool) = .init(false),
    signal_sent: std.atomic.Value(bool) = .init(false),
};
pub const Sink = struct {
    context: *anyopaque,
    write: *const fn (*anyopaque, Stream, []const u8) anyerror!void,
};
pub const Result = struct { code: i32 = 0, signal: ?u32 = null };
pub const Identity = struct {
    pid: u32,
    // Windows creation FILETIME is queried from the exact retained hProcess.
    // POSIX ownership is the unreaped direct child, never a process-name match.
    creation_filetime: ?u64 = null,
};
pub const Process = struct {
    child: std.process.Child,
    identity: Identity,
    exited: bool = false,
    result: Result = .{},
    stdout_ended: bool = false,
    stderr_ended: bool = false,

    pub fn spawn(io: std.Io, argv: []const []const u8, cwd: ?[]const u8, env: *const std.process.Environ.Map) !Process {
        var child = try std.process.spawn(io, .{
            .argv = argv,
            .cwd = if (cwd) |path| .{ .path = path } else .inherit,
            .environ_map = env,
            .stdin = .ignore,
            .stdout = .pipe,
            .stderr = .pipe,
            .create_no_window = false,
        });
        errdefer child.kill(io);
        const identity: Identity = if (builtin.os.tag == .windows) windows: {
            const handle = child.id.?;
            var created: u64 = 0;
            var ended: u64 = 0;
            var kernel: u64 = 0;
            var user: u64 = 0;
            const has_time = win.GetProcessTimes(handle, &created, &ended, &kernel, &user) != 0;
            break :windows .{ .pid = win.GetProcessId(handle), .creation_filetime = if (has_time) created else null };
        } else .{ .pid = @intCast(child.id.?) };
        return .{ .child = child, .identity = identity };
    }

    /// Node ChildProcess.kill acts on this direct child. On Windows libuv maps
    /// both SIGTERM and SIGKILL to TerminateProcess(handle, 1). On POSIX success
    /// means the signal was sent, including a signal that the child ignores.
    fn signal(self: *Process, force: bool) bool {
        if (self.exited) return false;
        if (builtin.os.tag == .windows) return win.TerminateProcess(self.child.id.?, 1) != 0;
        std.posix.kill(self.child.id.?, if (force) .KILL else .TERM) catch return false;
        return true;
    }

    fn observeExit(self: *Process) !void {
        if (self.exited) return;
        if (builtin.os.tag == .windows) {
            const zero: std.os.windows.LARGE_INTEGER = 0;
            switch (std.os.windows.ntdll.NtWaitForSingleObject(self.child.id.?, .FALSE, &zero)) {
                .TIMEOUT => return,
                std.os.windows.NTSTATUS.WAIT_0 => {},
                else => return error.NativeExecProcessWaitFailed,
            }
            var code: u32 = 0;
            if (win.GetExitCodeProcess(self.child.id.?, &code) == 0) return error.NativeExecProcessWaitFailed;
            self.result.code = @bitCast(code);
            self.exited = true;
        } else {
            var status: if (builtin.link_libc) c_int else u32 = 0;
            const found = std.posix.system.waitpid(self.child.id.?, &status, std.posix.W.NOHANG);
            switch (std.posix.errno(found)) {
                .SUCCESS => {},
                .INTR => return,
                else => return error.NativeExecProcessWaitFailed,
            }
            if (found == 0) return;
            const bits: u32 = @bitCast(status);
            self.result = if (std.posix.W.IFEXITED(bits)) .{ .code = @intCast(std.posix.W.EXITSTATUS(bits)) } else if (std.posix.W.IFSIGNALED(bits)) .{ .signal = @intCast(std.posix.W.TERMSIG(bits)) } else .{};
            self.exited = true;
            // Reaped identity is retired before any later abort/timeout.
            self.child.id = null;
        }
    }

    fn read(self: *Process, io: std.Io, stream: Stream, sink: Sink) !bool {
        const ended = if (stream == .stdout) &self.stdout_ended else &self.stderr_ended;
        if (ended.*) return false;
        const file = (if (stream == .stdout) self.child.stdout else self.child.stderr) orelse {
            ended.* = true;
            return false;
        };
        var bytes: [64 * 1024]u8 = undefined;
        const count: usize = if (builtin.os.tag == .windows) windows: {
            var available: u32 = 0;
            if (win.PeekNamedPipe(file.handle, null, 0, null, &available, null) == 0) {
                ended.* = true;
                return false;
            }
            if (available == 0) return false;
            var received: u32 = 0;
            if (win.ReadFile(file.handle, &bytes, @intCast(@min(available, bytes.len)), &received, null) == 0) {
                ended.* = true;
                return false;
            }
            break :windows received;
        } else posix: {
            var descriptors = [_]std.posix.pollfd{.{ .fd = file.handle, .events = std.posix.POLL.IN, .revents = 0 }};
            if (try std.posix.poll(&descriptors, 0) == 0) return false;
            if (descriptors[0].revents & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR) == 0) return false;
            break :posix try file.readStreaming(io, &.{&bytes});
        };
        if (count == 0) {
            ended.* = true;
            return false;
        }
        try sink.write(sink.context, stream, bytes[0..count]);
        return true;
    }

    /// Source waitForChildProcess resolves when both pipes end, or after a
    /// post-exit 100ms IDLE period rearmed by every stdout/stderr data chunk.
    pub fn run(self: *Process, io: std.Io, control: *Control, sink: Sink) !Result {
        defer self.deinit(io);
        var idle_since: ?std.Io.Timestamp = null;
        var requested = false;
        var forced = false;
        while (true) {
            if (control.shutdown.load(.acquire)) {
                _ = self.signal(true);
                return error.Canceled;
            }
            if (!requested and control.terminate.load(.acquire)) {
                requested = true;
                control.signal_sent.store(self.signal(false), .release);
            }
            if (!forced and control.force.load(.acquire)) {
                forced = true;
                if (self.signal(true)) control.signal_sent.store(true, .release);
            }
            const was_exited = self.exited;
            try self.observeExit();
            const out = try self.read(io, .stdout, sink);
            const err = try self.read(io, .stderr, sink);
            if (self.exited) {
                if (self.stdout_ended and self.stderr_ended) return self.result;
                if (!was_exited or out or err) idle_since = std.Io.Clock.awake.now(io);
                if (idle_since.?.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds() >= 100) return self.result;
            }
            try io.sleep(.fromMilliseconds(5), .awake);
        }
    }

    /// Only the exact direct child can be stopped during engine shutdown.
    /// Draining completes before closing read handles; no descendant PID walk.
    pub fn deinit(self: *Process, io: std.Io) void {
        if (self.child.id != null) {
            if (!self.exited) _ = self.signal(true);
            _ = self.child.wait(io) catch {};
        }
        if (self.child.stdout) |file| file.close(io);
        if (self.child.stderr) |file| file.close(io);
        if (self.child.stdin) |file| file.close(io);
        self.child.stdout = null;
        self.child.stderr = null;
        self.child.stdin = null;
    }
};
const win = struct {
    const HANDLE = std.os.windows.HANDLE;
    extern "kernel32" fn GetProcessId(HANDLE) callconv(.winapi) u32;
    extern "kernel32" fn GetProcessTimes(HANDLE, *u64, *u64, *u64, *u64) callconv(.winapi) i32;
    extern "kernel32" fn GetExitCodeProcess(HANDLE, *u32) callconv(.winapi) i32;
    extern "kernel32" fn TerminateProcess(HANDLE, u32) callconv(.winapi) i32;
    extern "kernel32" fn PeekNamedPipe(HANDLE, ?*anyopaque, u32, ?*u32, ?*u32, ?*u32) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(HANDLE, *anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) i32;
};
