//! Actual Linux owner operations over clone3 pidfd + real stdio sockets. There
//! is no std.process PID fallback, blocking wait, VM value or synthetic process.
const std = @import("std");
const linux = std.os.linux;
const assembly = @import("native_child_process_linux.zig");
const spawn = @import("native_child_process_spawn_linux.zig");
const reaper = @import("native_child_process_reaper_linux.zig");
const readiness = @import("native_child_process_epoll_linux.zig");
const Result = @import("native_child_process_transport.zig").Result;
pub const Read = union(enum) { pending, bytes: []const u8, eof, failure: anyerror };
pub const Shutdown = enum { pending, completed };
pub const Owned = struct {
    ticket: spawn.Ticket,
    endpoints: [3]?linux.fd_t,
    generations: [3]u64 = .{1} ** 3,
    operations: [5]u64 = .{0} ** 5,
    output_ended: [2]bool = .{false} ** 2,
    output_failure: [2]?anyerror = .{null} ** 2,
    output: [2][64 * 1024]u8 = undefined,
    input_finished: bool = false,
    exited: ?Result = null,
    detached: bool = false,
    pub fn adopt(actual: assembly.Spawned) Owned { return .{ .ticket = actual.ticket, .endpoints = actual.parents }; }
    fn guard(self: *Owned) !void {
        if (self.detached or !self.ticket.charged) return error.NativeLinuxChildOwnerDetached;
        if (self.ticket.watch.owner != std.Thread.getCurrentId()) return error.NativeLinuxChildTicketOwnerThreadRequired;
        if (self.ticket.parent_mask_restore_errno != null) return error.NativeLinuxChildParentMaskRecoveryRequired;
    }
    fn operation(self: *Owned, index: usize) !void {
        if (self.operations[index] == std.math.maxInt(u64)) return error.NativeLinuxChildOperationExhausted;
        self.operations[index] += 1;
    }
    pub fn restoreParentMask(self: *Owned) !void { try self.ticket.restoreParentMask(); }
    /// Caller withdraws exec-status readiness first. Channel closure records only
    /// absence of a reported setup error, never that user code physically ran.
    pub fn takeLaunchAfterWithdraw(self: *Owned) !spawn.Status {
        try self.guard(); try self.operation(3);
        return self.ticket.takeExecStatusAfterWithdraw();
    }
    pub fn signalNumber(self: *Owned, number: i32) !bool {
        try self.guard();
        if (number < 0 or number > 64) return error.UnsupportedNativeChildKillSignal;
        if (self.exited != null or self.ticket.watch.reaped) return false;
        const fd = self.ticket.watch.pidfd orelse return error.NativeChildPidfdClosed;
        return switch (linux.errno(linux.pidfd_send_signal(fd, @enumFromInt(number), null, 0))) {
            .SUCCESS => true, .SRCH => false,
            .PERM => error.PermissionDenied,
            else => error.NativeChildPidfdSignalFailed,
        };
    }
    /// No numeric PID wait, no other reaper and no owner-thread blocking. Only
    /// kernel observation/reap supplies this actual direct-child status.
    pub fn observeExitAfterWithdraw(self: *Owned) !?Result {
        try self.guard();
        if (self.exited) |result| return result;
        try self.operation(4);
        if (try self.ticket.watch.observe() == .pending) return null;
        const result = self.ticket.watch.reap() catch |failure| {
            if (failure == error.NativeChildPidfdReapInterrupted) return null;
            return failure;
        };
        self.exited = result; return result;
    }
    /// Writes are one nonblocking MSG_NOSIGNAL send attempt. The adapter retains
    /// its copied chunk/token and schedules OUT readiness for a pending suffix.
    pub fn writeOnce(self: *Owned, bytes: []const u8) !assembly.Write {
        try self.guard();
        if (self.input_finished) return .{ .failure = error.BrokenPipe };
        const fd = self.endpoints[0] orelse return .{ .failure = error.BrokenPipe };
        try self.operation(0); return assembly.writeOnce(fd, bytes);
    }
    /// Real SHUT_WR after every actual write acknowledgement is consumed. This
    /// half-close is distinct from endpoint destruction and process exit.
    pub fn finishInputAfterWrites(self: *Owned) !Shutdown {
        try self.guard();
        if (self.input_finished or self.endpoints[0] == null) return .completed;
        try self.operation(0);
        return switch (linux.errno(linux.shutdown(self.endpoints[0].?, linux.SHUT.WR))) {
            .SUCCESS, .NOTCONN => completed: { self.input_finished = true; break :completed .completed; },
            .INTR, .AGAIN => .pending,
            .PIPE, .CONNRESET => error.BrokenPipe,
            else => error.NativeLinuxChildShutdownFailed,
        };
    }
    /// A returned span belongs to this owner until the next read on that channel.
    /// Caller copies it before live Socket.push and does not reenter owner step.
    pub fn readOnce(self: *Owned, index: usize) !Read {
        try self.guard(); if (index >= 2) return error.NativeLinuxChildOutputIndex;
        if (self.output_ended[index] or self.output_failure[index] != null) return .pending;
        const fd = self.endpoints[index + 1] orelse return .pending;
        try self.operation(index + 1);
        const count = linux.read(fd, &self.output[index], self.output[index].len);
        return switch (linux.errno(count)) {
            .SUCCESS => if (count == 0) eof: { self.output_ended[index] = true; break :eof .eof; } else .{ .bytes = self.output[index][0..count] },
            .INTR, .AGAIN => .pending,
            else => failed: { self.output_failure[index] = error.NativeLinuxChildOutputReadFailed; break :failed .{ .failure = error.NativeLinuxChildOutputReadFailed }; },
        };
    }
    /// Successful withdrawal must precede close, so an obsolete epoll snapshot
    /// can never register a reused numeric endpoint. Closing never reports EOF.
    pub fn closeEndpointAfterWithdraw(self: *Owned, index: usize) !void {
        try self.guard(); if (index >= 3) return error.NativeLinuxChildEndpointIndex;
        const fd = self.endpoints[index] orelse return;
        if (self.generations[index] == std.math.maxInt(u64)) return error.NativeLinuxChildEndpointGenerationExhausted;
        self.endpoints[index] = null; self.generations[index] += 1;
        const status = linux.errno(linux.close(fd));
        // Linux close(EINTR) releases the descriptor. Never retry its integer.
        if (status != .SUCCESS and status != .INTR) return error.NativeLinuxChildEndpointCloseFailed;
    }
    pub fn snapshot(self: *Owned, input_pending: bool, stdout_demand: bool, stderr_demand: bool, deadline_ms: ?u64) !readiness.Snapshot {
        try self.guard();
        var result: readiness.Snapshot = .{ .deadline_ms = deadline_ms };
        if (input_pending and !self.input_finished) if (self.endpoints[0]) |fd| { result.interests[0] = .{ .fd = fd, .writable = true, .endpoint_generation = self.generations[0], .operation_sequence = self.operations[0] }; };
        for ([_]bool{stdout_demand, stderr_demand}, 0..) |demand, index| if (demand and !self.output_ended[index] and self.output_failure[index] == null) if (self.endpoints[index + 1]) |fd| {
            result.interests[index + 1] = .{ .fd = fd, .endpoint_generation = self.generations[index + 1], .operation_sequence = self.operations[index + 1] };
        };
        if (self.ticket.exec_status_fd) |fd| { result.interests[3] = .{ .fd = fd, .endpoint_generation = 1, .operation_sequence = self.operations[3] }; }
        if (self.exited == null) if (self.ticket.watch.pidfd) |fd| { result.interests[4] = .{ .fd = fd, .endpoint_generation = 1, .operation_sequence = self.operations[4] }; };
        return result;
    }
    pub fn disposeExitedAfterWithdraw(self: *Owned) !void {
        try self.guard();
        if (self.exited == null or !self.ticket.watch.reaped) return error.NativeChildStillRunning;
        for (0..3) |index| try self.closeEndpointAfterWithdraw(index);
        try self.ticket.closeReapedAfterWithdraw(); self.detached = true;
    }
    /// Exact live child is optionally signalled through its retained pidfd by the
    /// caller before this handoff. Adoption, even retained_failure, moves the sole
    /// ticket into bounded native storage; an error leaves owner Ticket charged.
    pub fn moveToReaperAfterWithdraw(self: *Owned) !reaper.Admission {
        try self.guard();
        const result = try reaper.adoptWithEndpointsAfterWithdraw(&self.ticket, &self.endpoints);
        self.detached = true; return result;
    }
};
