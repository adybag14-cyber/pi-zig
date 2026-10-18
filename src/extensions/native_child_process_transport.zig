//! Byte-only direct-child transport. Native Node argument normalization occurs
//! on the VM owner; this module never reads a JS value or manufactures a child.
const std = @import("std");
const builtin = @import("builtin");
const stdin = @import("native_child_process_stdin.zig");
const windows_output = @import("native_child_process_output_windows.zig");
pub const Stream = enum { stdout, stderr };
pub const Stdio = enum { ignore, pipe, inherited };
pub const Options = struct {
    stdio: [3]Stdio = .{ .pipe, .pipe, .pipe },
    windows_hide: bool = false,
    detached: bool = false,
    windows_verbatim_arguments: bool = false,
    // Internal native owner mode; never inferred from a guest option/property.
    windows_overlapped_output: bool = false,
    // Native owner keeps this borrowed path alive in Config until process start.
    // It is separate from argv[0], which may be the user's genuine argv0 value.
    executable: ?[]const u8 = null,
    // Native-only prelaunch ownership. Never decoded from a guest property or
    // numeric fd; a real stdio preparer owns this until CreateProcess takes it.
    prepared_stdio: ?*@import("native_child_process_windows.zig").Prepared = null,
    // Actual authorized native leases, consumed by the Linux clone factory.
    // No guest descriptor number reaches that factory as an OS descriptor.
    linux_stdio: [3]?@import("native_child_process_stdio_linux.zig").Lease = .{null} ** 3,
    windows_stdio: [3]?@import("native_child_process_stdio_windows.zig").Lease = .{null} ** 3,
};
pub const Control = struct {
    terminate: std.atomic.Value(bool) = .init(false),
    force: std.atomic.Value(bool) = .init(false),
    shutdown: std.atomic.Value(bool) = .init(false),
    signal_sent: std.atomic.Value(bool) = .init(false),
    timeout_ms: ?u64 = null,
    timed_out: bool = false,
    kill_force: bool = false,
    close_pipes_on_kill: bool = false,
    stdin_retirement_pending: bool = false,
};
pub const Sink = struct {
    context: *anyopaque,
    write: *const fn (*anyopaque, Stream, []const u8) anyerror!void,
};
pub const Result = struct { code: i64 = 0, signal: ?u32 = null };
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
    io: std.Io,
    gate: std.Io.Mutex = .init,
    input: stdin.Pump = .{},
    windows_outputs: [2]?*windows_output.Slot = .{ null, null },
    output_retirement_pending: bool = false,

    /// Consumes an actual successful Windows CreateProcess result. This cannot
    /// construct a failed-launch Process and does not manufacture a PID/handle.
    pub fn adoptWindowsSpawned(io: std.Io, spawned: @import("native_child_process_windows.zig").Spawned) Process {
        const handle = spawned.child.id.?;
        var created: u64 = 0; var ended: u64 = 0; var kernel: u64 = 0; var user: u64 = 0;
        const has_time = win.GetProcessTimes(handle, &created, &ended, &kernel, &user) != 0;
        return .{ .child = spawned.child, .identity = .{ .pid = win.GetProcessId(handle), .creation_filetime = if (has_time) created else null }, .io = io, .input = .{ .windows_slot = spawned.input_slot }, .windows_outputs = spawned.output_slots };
    }

    pub fn spawn(io: std.Io, gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: Options) !Process {
        for (options.stdio) |mode| if (mode == .inherited) return error.RequiredActualOwnedStdioFactory;
        if (builtin.os.tag != .windows and options.detached) return error.NativeDetachedPosixSessionNotImplemented;
        var input: stdin.Pump = .{};
        errdefer input.retire(io);
        var output_slots: [2]?*windows_output.Slot = .{ null, null };
        errdefer if (builtin.os.tag == .windows) for (output_slots) |maybe_slot| if (maybe_slot) |slot| { _ = slot.retire(); };
        var child = if (builtin.os.tag == .windows) windows: {
            const spawned = try @import("native_child_process_windows.zig").spawn(gpa, argv, cwd, env, options);
            input.windows_slot = spawned.input_slot;
            output_slots = spawned.output_slots;
            break :windows spawned.child;
        } else try std.process.spawn(io, .{
            .argv = argv,
            .cwd = if (cwd) |path| .{ .path = path } else .inherit,
            .environ_map = try env.posixMap(),
            .stdin = if (options.stdio[0] == .pipe) .pipe else .ignore,
            .stdout = if (options.stdio[1] == .pipe) .pipe else .ignore,
            .stderr = if (options.stdio[2] == .pipe) .pipe else .ignore,
            .create_no_window = options.windows_hide,
        });
        errdefer child.kill(io);
        if (builtin.os.tag != .windows) if (child.stdin) |file| {
            try input.adoptPosix(file);
            child.stdin = null;
        };
        const identity: Identity = if (builtin.os.tag == .windows) windows: {
            const handle = child.id.?;
            var created: u64 = 0;
            var ended: u64 = 0;
            var kernel: u64 = 0;
            var user: u64 = 0;
            const has_time = win.GetProcessTimes(handle, &created, &ended, &kernel, &user) != 0;
            break :windows .{ .pid = win.GetProcessId(handle), .creation_filetime = if (has_time) created else null };
        } else .{ .pid = @intCast(child.id.?) };
        return .{ .child = child, .identity = identity, .io = io, .input = input, .windows_outputs = output_slots };
    }

    /// Node ChildProcess.kill acts on this direct child. On Windows libuv maps
    /// both SIGTERM and SIGKILL to TerminateProcess(handle, 1). On POSIX success
    /// means the signal was sent, including a signal that the child ignores.
    pub fn signal(self: *Process, force: bool) bool {
        self.gate.lockUncancelable(self.io);
        defer self.gate.unlock(self.io);
        return self.signalUnlocked(force);
    }
    fn signalUnlocked(self: *Process, force: bool) bool {
        return self.signalNumberUnlocked(if (force) 9 else 15) catch false;
    }
    pub fn signalNumber(self: *Process, number: i32) !bool {
        self.gate.lockUncancelable(self.io); defer self.gate.unlock(self.io);
        return self.signalNumberUnlocked(number);
    }
    fn signalNumberUnlocked(self: *Process, number: i32) !bool {
        if (self.exited or self.child.id == null) return false;
        if (number < 0 or number > 64) return error.UnsupportedNativeChildKillSignal;
        if (builtin.os.tag == .windows) {
            const handle = self.child.id.?;
            if (number == 0) {
                var status: u32 = 0; if (win.GetExitCodeProcess(handle, &status) == 0) return error.NativeExecProcessSignalFailed;
                if (status != 259) return false;
                const zero: std.os.windows.LARGE_INTEGER = 0;
                return switch (std.os.windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &zero)) { .TIMEOUT => true, std.os.windows.NTSTATUS.WAIT_0 => false, else => error.NativeExecProcessSignalFailed };
            }
            if (number != 2 and number != 3 and number != 9 and number != 15) return error.UnsupportedNativeChildKillSignal;
            if (win.TerminateProcess(handle, 1) != 0) return true;
            const failure = @intFromEnum(std.os.windows.GetLastError());
            if (failure == 5) {
                var status: u32 = 0; if (win.GetExitCodeProcess(handle, &status) != 0 and status != 259) return false;
                const zero: std.os.windows.LARGE_INTEGER = 0;
                if (std.os.windows.ntdll.NtWaitForSingleObject(handle, .FALSE, &zero) == .SUCCESS) return false;
                return error.PermissionDenied;
            }
            return error.NativeExecProcessSignalFailed;
        }
        std.posix.kill(self.child.id.?, @enumFromInt(number)) catch |err| switch (err) { error.ProcessNotFound => return false, else => return err };
        return true;
    }

    pub fn observeExit(self: *Process) !void {
        self.gate.lockUncancelable(self.io);
        defer self.gate.unlock(self.io);
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
            self.result.code = code;
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
            break :posix file.readStreaming(io, &.{&bytes}) catch |err| switch (err) { error.EndOfStream => 0, else => return err };
        };
        if (count == 0) {
            ended.* = true;
            return false;
        }
        try sink.write(sink.context, stream, bytes[0..count]);
        return true;
    }

    /// Public Node spawning keeps real inherited pipe handles until EOF. The
    /// separate actual Source waitForChildProcess consumer owns its idle grace.
    pub fn run(self: *Process, io: std.Io, control: *Control, sink: Sink, input_bytes: []const u8) !Result {
        defer {
            self.deinit(io);
            control.stdin_retirement_pending = self.input.retirement_pending;
        }
        if (self.windows_outputs[0] != null or self.windows_outputs[1] != null) return error.NativeOverlappedOutputRequiresOwnerTransport;
        const started = std.Io.Clock.awake.now(io);
        var requested = false;
        var forced = false;
        while (true) {
            if (control.timeout_ms) |timeout| if (!requested and @as(i128, started.durationTo(std.Io.Clock.awake.now(io)).toMilliseconds()) >= timeout) {
                control.timed_out = true;
                control.terminate.store(true, .release);
            };
            if (control.shutdown.load(.acquire)) {
                self.input.retire(io);
                _ = self.signal(true);
                return error.Canceled;
            }
            if (!requested and control.terminate.load(.acquire)) {
                requested = true;
                self.input.retire(io);
                control.signal_sent.store(self.signal(control.kill_force), .release);
                if (control.close_pipes_on_kill) {
                    if (self.child.stdout) |file| file.close(io);
                    if (self.child.stderr) |file| file.close(io);
                    self.child.stdout = null;
                    self.child.stderr = null;
                    self.stdout_ended = true;
                    self.stderr_ended = true;
                }
            }
            if (!forced and control.force.load(.acquire)) {
                forced = true;
                if (self.signal(true)) control.signal_sent.store(true, .release);
            }
            try self.observeExit();
            _ = try self.read(io, .stdout, sink);
            _ = try self.read(io, .stderr, sink);
            if (self.exited or requested or forced) self.input.retire(io) else try self.input.step(io, input_bytes);
            if (self.input.retirement_pending) return error.NativeStdinRetirementPending;
            if (self.exited) {
                if (self.stdout_ended and self.stderr_ended) return self.result;
            }
            try io.sleep(.fromMilliseconds(5), .awake);
        }
    }

    /// Only the exact direct child can be stopped during engine shutdown.
    /// Draining completes before closing read handles; no descendant PID walk.
    pub fn deinit(self: *Process, io: std.Io) void {
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        self.input.retire(io);
        if (builtin.os.tag == .windows) for (&self.windows_outputs) |*maybe_slot| if (maybe_slot.*) |slot| {
            maybe_slot.* = null;
            if (!slot.retire()) self.output_retirement_pending = true;
        };
        self.gate.lockUncancelable(io);
        defer self.gate.unlock(io);
        if (self.child.id != null) {
            if (!self.exited) _ = self.signalUnlocked(true);
            if (self.child.wait(io)) |_| {} else |_| self.child.kill(io);
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
