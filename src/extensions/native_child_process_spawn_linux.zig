//! Atomic Linux direct-child acquisition. Parent returns a genuine CLONE_PIDFD
//! identity and a nonblocking exec-status channel; no owner-thread exec wait.
//! Not selected: PATH lookup, epoll/wake and public child assembly remain separate.
const std = @import("std");
const builtin = @import("builtin");
const linux = std.os.linux;
const exit_watch = @import("native_child_process_exit_linux.zig");
const supported = builtin.os.tag == .linux and (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .aarch64);
pub const MaskRecovery = struct {
    original: ?linux.sigset_t = null,
    owner: std.Thread.Id = undefined,
    failure: ?linux.E = null,
    fn attempt(self: *MaskRecovery) linux.E {
        const mask = self.original orelse return .SUCCESS;
        const status = linux.errno(linux.sigprocmask(linux.SIG.SETMASK, &mask, null));
        self.failure = if (status == .SUCCESS) null else status;
        if (status == .SUCCESS) self.original = null;
        return status;
    }
    /// Failed clone plus failed restore returns no child, but this caller-owned
    /// native object retains exact owner-thread recovery state across the error.
    pub fn restore(self: *MaskRecovery) !void {
        if (self.original == null) return;
        if (self.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (self.attempt() != .SUCCESS) return error.NativeLinuxChildParentMaskRestoreFailed;
    }
};
pub const Inputs = struct {
    // Native normalization supplies validated NUL-free, sentinel-owned storage.
    // Child never allocates, invokes VM code or uses std.Io after cloning.
    absolute_file: [*:0]const u8,
    argv: [*:null]const ?[*:0]const u8,
    envp: [*:null]const ?[*:0]const u8,
    child_stdio: [3]linux.fd_t,
    cwd_fd: ?linux.fd_t = null,
    cwd_path: ?[*:0]const u8 = null,
    detached: bool = false,
    parent_mask_recovery: *MaskRecovery,
};
pub const Stage = enum(u32) { signals = 1, stdio, cwd, inherit, exec, session };
pub const Failure = extern struct { stage: u32, errno_number: u32 };
pub const Status = union(enum) { pending, channel_closed, failed: Failure };
/// Byte-only exclusive reap ownership after the VM owner withdraws all watches.
/// Static native retirement storage owns this value, never an Engine allocator.
pub const NativeReapTicket = struct {
    watch: exit_watch.Watch,
    exec_status_fd: ?linux.fd_t,
    charged: bool = true, claimed: bool = false,
    endpoints: [3]?linux.fd_t = .{null} ** 3,
    pub fn claimOnWorker(self: *NativeReapTicket) !void {
        if (self.claimed or !self.charged or self.watch.pidfd == null or self.watch.epoll != null) return error.NativeLinuxChildReapTransferInvalid;
        self.watch.owner = std.Thread.getCurrentId(); self.claimed = true;
        for (&self.endpoints) |*maybe_fd| if (maybe_fd.*) |fd| {
            maybe_fd.* = null;
            const status = linux.errno(linux.close(fd));
            if (status != .SUCCESS and status != .INTR) return error.NativeLinuxChildReapEndpointCloseFailed;
        };
    }
    /// Actual readiness is followed by exact waitid(P_PIDFD), never waitpid(pid)
    /// or a guessed process status. The native worker is the sole reaper.
    pub fn reapReady(self: *NativeReapTicket) !bool {
        if (!self.claimed) return error.NativeLinuxChildReapTransferInvalid;
        if (try self.watch.observe() == .pending) return false;
        _ = try self.watch.reap(); return true;
    }
    pub fn closeReaped(self: *NativeReapTicket) !void {
        if (!self.claimed or !self.charged) return error.NativeLinuxChildReapTransferInvalid;
        if (!self.watch.reaped or self.watch.epoll != null) return error.NativeChildPidfdRetirementAcknowledgementRequired;
        if (self.exec_status_fd) |fd| { self.exec_status_fd = null; closeOwned(fd); }
        try self.watch.closeReaped();
        self.charged = false; _ = admitted.fetchSub(1, .acq_rel);
    }
};
// Stable Linux UAPI struct clone_args. No CLONE_VM/FILES/THREAD/VFORK sharing.
const CloneArgs = extern struct {
    // Child-only atomic handler reset includes RT handlers before any child
    // instruction; ignored dispositions are preserved until ordinary reset.
    flags: u64 = linux.CLONE.PIDFD | linux.CLONE.CLEAR_SIGHAND, pidfd: u64, child_tid: u64 = 0,
    parent_tid: u64 = 0, exit_signal: u64 = @intFromEnum(linux.SIG.CHLD),
    stack: u64 = 0, stack_size: u64 = 0, tls: u64 = 0,
    set_tid: u64 = 0, set_tid_size: u64 = 0, cgroup: u64 = 0,
};
var admitted: std.atomic.Value(u32) = .init(0);
pub fn requireParentReaping() !void {
    var disposition: linux.Sigaction = undefined;
    if (linux.errno(linux.sigaction(.CHLD, null, &disposition)) != .SUCCESS) return error.NativeLinuxChildSigchldQueryFailed;
    if (disposition.handler.handler == linux.SIG.IGN or disposition.flags & linux.SA.NOCLDWAIT != 0) return error.NativeLinuxChildParentAutoReapUnsupported;
    // This query rejects known kernel auto-reap modes. The host must separately
    // guarantee no other reaper and no process-wide disposition mutation for the
    // ticket lifetime; an arbitrary callback cannot be proved safe by its address.
}
fn reserve() !void {
    var count = admitted.load(.acquire);
    while (count < 16) {
        if (admitted.cmpxchgWeak(count, count + 1, .acq_rel, .acquire)) |actual| count = actual else return;
    }
    return error.NativeLinuxChildTicketCapacity;
}
fn closeOwned(fd: linux.fd_t) void { _ = linux.close(fd); } // Never retry close.
fn duplicate(fd: linux.fd_t) !linux.fd_t {
    const value = linux.fcntl(fd, linux.F.DUPFD_CLOEXEC, 3);
    if (linux.errno(value) != .SUCCESS) return error.NativeLinuxChildDescriptorDuplicateFailed;
    return @intCast(value);
}
fn cloneAtomic(args: *CloneArgs) !usize {
    // Unsupported syscall enums (e.g. Sparc) must not be referenced/analyzed.
    if (comptime supported) return linux.syscall2(.clone3, @intFromPtr(args), @sizeOf(CloneArgs)) else return error.RequiredLinuxX64Arm64Clone3;
}
fn failChild(status_fd: linux.fd_t, stage: Stage, failure: linux.E) noreturn {
    const record: Failure = .{ .stage = @intFromEnum(stage), .errno_number = @intFromEnum(failure) };
    // One <=PIPE_BUF native record on a private, initially empty nonblocking
    // pipe. EINTR cannot transfer a partial record at this size. No allocation,
    // logging, Engine, allocator, Group cancellation or parent-runtime locks.
    const data = std.mem.asBytes(&record);
    while (linux.errno(linux.write(status_fd, data.ptr, data.len)) == .INTR) {}
    linux.exit_group(127);
}
fn child(inputs: Inputs, descriptors: [3]linux.fd_t, cwd: ?linux.fd_t, status_fd: linux.fd_t) noreturn {
    // Match the ordinary libuv child reset for non-RT signals, entirely in the
    // new process. Parent SIGPIPE/SIGCHLD dispositions and mask are untouched.
    const action: linux.Sigaction = .{ .handler = .{ .handler = null }, .mask = linux.sigemptyset(), .flags = 0 };
    for (1..32) |number| {
        const signal: linux.SIG = @enumFromInt(number);
        if (signal == .KILL or signal == .STOP) continue;
        const failure = linux.errno(linux.sigaction(signal, &action, null));
        if (failure != .SUCCESS) failChild(status_fd, .signals, failure);
    }
    if (inputs.detached) {
        const failure = linux.errno(linux.setsid());
        if (failure != .SUCCESS) failChild(status_fd, .session, failure);
    }
    inline for (0..3) |index| {
        const failure = linux.errno(linux.dup3(descriptors[index], index, 0));
        if (failure != .SUCCESS) failChild(status_fd, .stdio, failure);
        const current = linux.fcntl(index, linux.F.GETFL, 0);
        if (linux.errno(current) != .SUCCESS) failChild(status_fd, .stdio, linux.errno(current));
        const nonblocking = @as(usize, 1) << @bitOffsetOf(linux.O, "NONBLOCK");
        const changed = linux.errno(linux.fcntl(index, linux.F.SETFL, current & ~nonblocking));
        if (changed != .SUCCESS) failChild(status_fd, .stdio, changed);
    }
    if (inputs.cwd_path) |path| {
        const failure = linux.errno(linux.chdir(path));
        if (failure != .SUCCESS) failChild(status_fd, .cwd, failure);
    } else if (cwd) |fd| {
        const failure = linux.errno(linux.fchdir(fd));
        if (failure != .SUCCESS) failChild(status_fd, .cwd, failure);
    }
    // Linux UAPI CLOSE_RANGE_CLOEXEC is 1U<<2. Use its exact ABI value; the
    // pinned std packed CLOSE_RANGE layout must not silently change this flag.
    const inherited = linux.errno(linux.syscall3(.close_range, 3, std.math.maxInt(u32), 4));
    if (inherited != .SUCCESS) failChild(status_fd, .inherit, inherited);
    const empty = linux.sigemptyset();
    const mask_failure = linux.errno(linux.sigprocmask(linux.SIG.SETMASK, &empty, null));
    if (mask_failure != .SUCCESS) failChild(status_fd, .signals, mask_failure);
    failChild(status_fd, .exec, linux.errno(linux.execve(inputs.absolute_file, inputs.argv, inputs.envp)));
}
pub const Ticket = struct {
    watch: exit_watch.Watch,
    exec_status_fd: ?linux.fd_t,
    bytes: [@sizeOf(Failure)]u8 = undefined, received: usize = 0,
    status: Status = .pending,
    charged: bool = true,
    parent_mask_restore_errno: ?linux.E = null,
    parent_mask_before: linux.sigset_t,
    /// A failed parent restore is a fatal owner condition, but cannot discard
    /// the real child. Caller retains this ticket while repairing/retiring it.
    pub fn restoreParentMask(self: *Ticket) !void {
        if (self.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (self.parent_mask_restore_errno == null) return;
        const failure = linux.errno(linux.sigprocmask(linux.SIG.SETMASK, &self.parent_mask_before, null));
        if (failure != .SUCCESS) { self.parent_mask_restore_errno = failure; return error.NativeLinuxChildParentMaskRestoreFailed; }
        self.parent_mask_restore_errno = null;
    }
    /// Scheduler arms exec_status_fd for actual IN/HUP. One syscall, no poll
    /// timeout, busy retry or child.wait. EOF is channel closure, not output EOF
    /// and not evidence that a killed-before-exec child executed guest code.
    /// Caller first withdraws/acknowledges every borrowed exec-status wait arm;
    /// this operation can close its exact fd after completion.
    pub fn takeExecStatusAfterWithdraw(self: *Ticket) !Status {
        if (self.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        const fd = self.exec_status_fd orelse return self.status;
        const count = linux.read(fd, self.bytes[self.received..].ptr, self.bytes.len - self.received);
        switch (linux.errno(count)) {
            .SUCCESS => {}, .AGAIN, .INTR => return .pending,
            else => return error.NativeLinuxChildExecStatusReadFailed,
        }
        if (count == 0) {
            if (self.received != 0) return error.NativeLinuxChildTruncatedExecStatus;
            self.status = .channel_closed;
        } else {
            self.received += count;
            if (self.received != self.bytes.len) return .pending;
            const failure = std.mem.bytesToValue(Failure, &self.bytes);
            _ = std.meta.intToEnum(Stage, failure.stage) catch return error.NativeLinuxChildInvalidExecStatus;
            if (failure.errno_number == 0) return error.NativeLinuxChildInvalidExecStatus;
            self.status = .{ .failed = failure };
        }
        self.exec_status_fd = null; closeOwned(fd); return self.status;
    }
    /// Scheduler must withdraw both pidfd and exec-status fd snapshots first.
    /// A live/unreaped child cannot release its ticket capacity or pidfd.
    pub fn closeReapedAfterWithdraw(self: *Ticket) !void {
        if (self.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (self.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
        if (!self.charged) return error.NativeLinuxChildTicketAlreadyRetired;
        if (!self.watch.reaped or self.watch.epoll != null) return error.NativeChildPidfdRetirementAcknowledgementRequired;
        if (self.exec_status_fd) |fd| { self.exec_status_fd = null; closeOwned(fd); }
        try self.watch.closeReaped();
        self.charged = false; _ = admitted.fetchSub(1, .acq_rel);
    }
    /// Caller must first successfully withdraw every borrowed pidfd/status/pipe
    /// interest and restore its exact parent signal mask. Capacity stays charged
    /// to the returned sole native entitlement until an actual reap and close.
    pub fn moveToNativeReaperAfterWithdraw(self: *Ticket) !NativeReapTicket {
        if (self.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (self.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
        if (!self.charged or self.watch.pidfd == null or self.watch.epoll != null) return error.NativeLinuxChildReapTransferInvalid;
        const moved: NativeReapTicket = .{ .watch = self.watch, .exec_status_fd = self.exec_status_fd };
        self.charged = false; self.watch.pidfd = null; self.exec_status_fd = null;
        return moved;
    }
};
pub fn spawnAbsolute(inputs: Inputs) !Ticket {
    if (!supported) return error.RequiredLinuxX64Arm64Clone3;
    if (inputs.parent_mask_recovery.original != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
    if (inputs.absolute_file[0] != '/' or inputs.argv[0] == null) return error.NativeLinuxAbsoluteExecutableRequired;
    try reserve();
    var charged = true; errdefer if (charged) { _ = admitted.fetchSub(1, .acq_rel); };
    var descriptors: [3]?linux.fd_t = .{ null, null, null };
    defer for (descriptors) |fd| if (fd) |value| closeOwned(value);
    for (&descriptors, inputs.child_stdio) |*target, source| target.* = try duplicate(source);
    const cwd = if (inputs.cwd_fd) |fd| try duplicate(fd) else null;
    defer if (cwd) |fd| closeOwned(fd);
    var status_pipe: [2]linux.fd_t = undefined;
    if (linux.errno(linux.pipe2(&status_pipe, .{ .CLOEXEC = true, .NONBLOCK = true })) != .SUCCESS) return error.NativeLinuxChildExecPipeFailed;
    var raw_pipe_owned = true;
    defer if (raw_pipe_owned) { closeOwned(status_pipe[0]); closeOwned(status_pipe[1]); };
    // The host may have closed fd0/1/2. Move BOTH error endpoints above stdio
    // before cloning so child dup3 cannot overwrite its private status writer.
    const status_read = try duplicate(status_pipe[0]);
    errdefer closeOwned(status_read);
    const status_write = try duplicate(status_pipe[1]);
    defer closeOwned(status_write);
    closeOwned(status_pipe[0]); closeOwned(status_pipe[1]); raw_pipe_owned = false;
    var pidfd: linux.fd_t = -1;
    var args: CloneArgs = .{ .pidfd = @intFromPtr(&pidfd) };
    try requireParentReaping();
    var barrier = linux.sigfillset();
    inline for (.{ linux.SIG.KILL, linux.SIG.STOP, linux.SIG.TRAP, linux.SIG.SEGV, linux.SIG.BUS, linux.SIG.ILL, linux.SIG.SYS, linux.SIG.ABRT }) |signal| linux.sigdelset(&barrier, signal);
    var original_mask: linux.sigset_t = undefined;
    if (linux.errno(linux.sigprocmask(linux.SIG.BLOCK, &barrier, &original_mask)) != .SUCCESS) return error.NativeLinuxChildSignalBarrierFailed;
    inputs.parent_mask_recovery.* = .{ .original = original_mask, .owner = std.Thread.getCurrentId() };
    const spawned = cloneAtomic(&args) catch |err| {
        if (inputs.parent_mask_recovery.attempt() != .SUCCESS) return error.NativeLinuxChildParentMaskRestoreFailed;
        return err;
    };
    if (linux.errno(spawned) == .SUCCESS and spawned == 0) child(inputs, .{ descriptors[0].?, descriptors[1].?, descriptors[2].? }, cwd, status_write);
    // Only parent reaches here, on clone success OR failure. Restoration is
    // thread-local; no process disposition/SIGCHLD mutation occurs.
    const restored = inputs.parent_mask_recovery.attempt();
    if (restored != .SUCCESS and linux.errno(spawned) != .SUCCESS) return error.NativeLinuxChildParentMaskRestoreFailed;
    switch (linux.errno(spawned)) {
        .SUCCESS => {},
        .NOSYS, .INVAL => return error.RequiredKernelClone3Pidfd,
        else => return error.NativeLinuxAtomicChildSpawnFailed,
    }
    // No fallible parent operation after successful clone: the real direct-child
    // ticket is transferred intact, even if exec later reports an error.
    charged = false;
    // Successful clone transfers a failed-restore entitlement into the real
    // ticket. Leave no second stale recovery object able to replay an old mask.
    inputs.parent_mask_recovery.original = null; inputs.parent_mask_recovery.failure = null;
    return .{ .watch = .{ .pidfd = pidfd, .pid = @intCast(spawned), .owner = std.Thread.getCurrentId() }, .exec_status_fd = status_read, .parent_mask_restore_errno = if (restored == .SUCCESS) null else restored, .parent_mask_before = original_mask };
}
