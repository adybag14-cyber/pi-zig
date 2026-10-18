//! Linux direct-child identity from an atomically acquired CLONE_PIDFD ticket.
//! This leaf never opens a pidfd from a numeric PID, changes SIGCHLD, polls a PID
//! or falls back to kill(pid). Atomic spawn + Linux owner wake remain unwired.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
pub const Result = @import("native_child_process_transport.zig").Result;
pub const Ready = enum { pending, exited };
pub const Watch = struct {
    // Native owner has exclusive lifetime/reap authority. A scheduler may wait
    // on this fd, but must withdraw/ack its snapshot before owner mutation.
    pidfd: ?linux.fd_t,
    pid: linux.pid_t,
    owner: std.Thread.Id,
    observed: ?Result = null,
    reaped: bool = false,
    epoll: ?linux.fd_t = null,
    arm_sequence: u64 = 0,

    /// Consumes the genuine parent-side clone3(CLONE_PIDFD) descriptor on both
    /// success and failure. Caller must transfer exclusive child wait ownership
    /// with it; another waitpid(-1)/SIGCHLD reaper is not permitted to consume it.
    /// The PID is diagnostic only and is never used for wait/signal authority.
    pub fn adoptAtomic(pidfd: linux.fd_t, pid: linux.pid_t) !Watch {
        if (builtin.os.tag != .linux) return error.RequiredLinuxPidfdPlatform;
        errdefer _ = linux.close(pidfd);
        if (pidfd < 0 or pid <= 0) return error.NativeChildInvalidAtomicPidfd;
        // pidfd from clone3 is already CLOEXEC. Require it rather than inheriting
        // a caller-supplied numeric fd into a future subprocess by accident.
        const flags = linux.fcntl(pidfd, linux.F.GETFD, 0);
        if (linux.errno(flags) != .SUCCESS or flags & linux.FD_CLOEXEC == 0) return error.NativeChildPidfdCloseOnExecRequired;
        return .{ .pidfd = pidfd, .pid = pid, .owner = std.Thread.getCurrentId() };
    }
    fn guard(self: *Watch) !linux.fd_t {
        if (std.Thread.getCurrentId() != self.owner) return error.NativeChildPidfdOwnerThreadRequired;
        return self.pidfd orelse error.NativeChildPidfdClosed;
    }
    fn result(info: linux.siginfo_t) !Result {
        const status = info.fields.common.second.sigchld.status;
        return switch (info.code) {
            @intFromEnum(linux.CLD.EXITED) => .{ .code = status },
            @intFromEnum(linux.CLD.KILLED), @intFromEnum(linux.CLD.DUMPED) => .{ .signal = @intCast(status) },
            else => error.NativeChildUnexpectedWaitStatus,
        };
    }
    /// Nonblocking kernel status observation. Real epoll readiness causes this
    /// call; WNOWAIT keeps the direct-child wait ownership until explicit reap.
    pub fn observe(self: *Watch) !Ready {
        const fd = try self.guard();
        if (self.observed != null) return .exited;
        var info: linux.siginfo_t = std.mem.zeroes(linux.siginfo_t);
        switch (linux.errno(linux.waitid(.PIDFD, fd, &info, linux.W.EXITED | linux.W.NOHANG | linux.W.NOWAIT, null))) {
            .SUCCESS => {},
            .INTR => return .pending,
            .CHILD => return error.NativeChildExclusiveWaitOwnershipLost,
            .INVAL => return error.RequiredKernelWaitidPidfd,
            else => return error.NativeChildPidfdWaitFailed,
        }
        if (info.fields.common.first.piduid.pid == 0) return .pending;
        if (info.fields.common.first.piduid.pid != self.pid) return error.NativeChildPidfdIdentityMismatch;
        self.observed = try result(info); return .exited;
    }
    /// Full caller token belongs to this arm; an outer registry must reject old
    /// tokens even if fd numbers or slots are later reused. Never close/rearm
    /// this descriptor while a native wait snapshot still owns it.
    pub fn arm(self: *Watch, epoll_fd: linux.fd_t, token: u64) !u64 {
        const fd = try self.guard();
        if (self.reaped or self.epoll != null) return error.NativeChildPidfdAlreadyArmed;
        if (self.arm_sequence == std.math.maxInt(u64)) return error.NativeChildPidfdArmExhausted;
        var event: linux.epoll_event = .{ .events = linux.EPOLL.IN | linux.EPOLL.ONESHOT, .data = .{ .u64 = token } };
        if (linux.errno(linux.epoll_ctl(epoll_fd, linux.EPOLL.CTL_ADD, fd, &event)) != .SUCCESS) return error.NativeChildPidfdEpollAddFailed;
        self.arm_sequence += 1; self.epoll = epoll_fd; return self.arm_sequence;
    }
    /// Owner calls only after its scheduler acknowledges withdrawal. Removing
    /// from epoll does not retract events already copied into worker storage.
    pub fn disarmAfterWithdraw(self: *Watch) !void {
        const fd = try self.guard();
        if (self.epoll) |epoll_fd| {
            if (linux.errno(linux.epoll_ctl(epoll_fd, linux.EPOLL.CTL_DEL, fd, null)) != .SUCCESS) return error.NativeChildPidfdEpollDeleteFailed;
            self.epoll = null;
        }
    }
    pub fn signal(self: *Watch, force: bool) !bool {
        const fd = try self.guard();
        if (self.reaped or self.observed != null) return false;
        return switch (linux.errno(linux.pidfd_send_signal(fd, if (force) .KILL else .TERM, null, 0))) {
            .SUCCESS => true,
            .SRCH => false,
            .PERM => error.NativeChildSignalPermissionDenied,
            else => error.NativeChildPidfdSignalFailed,
        };
    }
    pub fn reap(self: *Watch) !Result {
        const fd = try self.guard();
        if (self.reaped) return self.observed.?;
        var info: linux.siginfo_t = std.mem.zeroes(linux.siginfo_t);
        switch (linux.errno(linux.waitid(.PIDFD, fd, &info, linux.W.EXITED | linux.W.NOHANG, null))) {
            .SUCCESS => {},
            .INTR => return error.NativeChildPidfdReapInterrupted,
            .CHILD => return error.NativeChildExclusiveWaitOwnershipLost,
            else => return error.NativeChildPidfdReapFailed,
        }
        if (info.fields.common.first.piduid.pid == 0) return error.NativeChildStillRunning;
        if (info.fields.common.first.piduid.pid != self.pid) return error.NativeChildPidfdIdentityMismatch;
        self.observed = try result(info); self.reaped = true; return self.observed.?;
    }
    /// Closing a pidfd never reaps a live child. Owner/native reaper must retain
    /// this Watch until the real wait acknowledgement, including Engine shutdown.
    pub fn closeReaped(self: *Watch) !void {
        const fd = try self.guard();
        if (!self.reaped or self.epoll != null) return error.NativeChildPidfdRetirementAcknowledgementRequired;
        // Linux close(EINTR) still releases the descriptor. Never retry close on
        // its recycled numeric value; retire ownership before the syscall.
        self.pidfd = null;
        const status = linux.errno(linux.close(fd));
        if (status != .SUCCESS and status != .INTR) return error.NativeChildPidfdCloseFailed;
    }
};
