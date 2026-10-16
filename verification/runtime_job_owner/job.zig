//! This type can create a fresh job but cannot adopt/open an external job.
const std = @import("std");
const w = @import("win32.zig");
pub const caps = struct {
    pub const job_memory: usize = 8 * 1024 * 1024 * 1024;
    pub const process_memory: usize = 4 * 1024 * 1024 * 1024;
    pub const active: u32 = 64;
    pub const flags: u32 = 0x2000 | 0x0200 | 0x0100 | 0x0008;
};
pub const Snapshot = struct {
    accounting: w.AccountingIo,
    members: w.ProcessList,
    limits: w.ExtendedLimits,
    pub fn zero(self: *const Snapshot) bool {
        return self.accounting.basic.active_processes == 0 and
            self.members.assigned == 0 and self.members.returned == 0;
    }
};
pub const Notice = struct { message: u32, raw_pid: usize };

pub const Job = struct {
    // Never serialize/reconstruct these capabilities or send them to a worker.
    handle: ?w.H,
    port: ?w.H,
    completion_key: usize,
    queried_limits: bool,
    termination_requested: bool = false,
    worker_assigned: bool = false,

    pub fn create(completion_key: usize) !Job {
        if (completion_key == 0) return error.InvalidCompletionKey;
        const job = w.CreateJobObjectW(null, null) orelse return error.JobCreateFailed;
        errdefer _ = w.CloseHandle(job);
        var inheritance: u32 = 0;
        if (w.GetHandleInformation(job, &inheritance) == 0 or inheritance & w.handle_flag_inherit != 0)
            return error.JobHandleInheritanceUnsafe;
        var limits: w.ExtendedLimits = std.mem.zeroes(w.ExtendedLimits);
        limits.basic.flags = caps.flags;
        limits.basic.active_processes = caps.active;
        limits.process_memory = caps.process_memory;
        limits.job_memory = caps.job_memory;
        if (w.SetInformationJobObject(job, 9, &limits, @sizeOf(w.ExtendedLimits)) == 0)
            return error.JobLimitsFailed;
        var queried: w.ExtendedLimits = undefined;
        if (w.QueryInformationJobObject(job, 9, &queried, @sizeOf(w.ExtendedLimits), null) == 0)
            return error.JobLimitsQueryFailed;
        try validateLimits(queried);
        const port = w.CreateIoCompletionPort(w.invalid, null, 0, 1) orelse return error.JobPortCreateFailed;
        errdefer _ = w.CloseHandle(port);
        var association: w.AssociatePort = .{ .key = @ptrFromInt(completion_key), .port = port };
        if (w.SetInformationJobObject(job, 7, &association, @sizeOf(w.AssociatePort)) == 0)
            return error.JobPortAssociationFailed;
        const self: Job = .{ .handle = job, .port = port, .completion_key = completion_key, .queried_limits = true };
        const empty = try self.snapshot();
        if (!empty.zero() or empty.accounting.basic.total_processes != 0) return error.NewJobNotEmpty;
        return self;
    }

    pub fn requireMember(self: *const Job, exact_process: w.H) !void {
        var member: w.B = 0;
        if (w.IsProcessInJob(exact_process, self.handle orelse return error.JobClosed, &member) == 0)
            return error.JobMembershipUnverifiable;
        if (member == 0) return error.ProcessOutsideOwnedJob;
    }

    pub fn snapshot(self: *const Job) !Snapshot {
        const job = self.handle orelse return error.JobClosed;
        var result: Snapshot = undefined;
        if (w.QueryInformationJobObject(job, 8, &result.accounting, @sizeOf(w.AccountingIo), null) == 0)
            return error.JobAccountingUnverifiable;
        result.members = std.mem.zeroes(w.ProcessList);
        if (w.QueryInformationJobObject(job, 3, &result.members, @sizeOf(w.ProcessList), null) == 0)
            return error.JobMemberListUnverifiable;
        if (result.members.assigned != result.members.returned or result.members.returned > caps.active)
            return error.JobMemberListTruncated;
        if (w.QueryInformationJobObject(job, 9, &result.limits, @sizeOf(w.ExtendedLimits), null) == 0)
            return error.JobLimitsQueryFailed;
        try validateLimits(result.limits);
        // The accounting/list queries are separate observations. During live
        // execution their counts need not agree atomically; final zero requires
        // both successful queries after the final owned worker has retired.
        return result;
    }

    pub fn notice(self: *const Job, timeout_ms: u32) !?Notice {
        var message: u32 = 0;
        var key: usize = 0;
        var raw: ?*w.Overlapped = null;
        if (w.GetQueuedCompletionStatus(self.port orelse return error.JobClosed, &message, &key, &raw, timeout_ms) == 0) {
            if (w.GetLastError() == w.wait_timeout) return null;
            return error.JobNotificationReadFailed;
        }
        if (key != self.completion_key) return error.UnexpectedCompletionKey;
        return .{ .message = message, .raw_pid = if (raw) |pointer| @intFromPtr(pointer) else 0 };
    }

    pub fn abort(self: *Job, code: u32) !void {
        const job = self.handle orelse return error.JobClosed;
        self.termination_requested = true;
        if (w.TerminateJobObject(job, code) == 0) return error.OwnedJobTerminationFailed;
    }

    /// Caller must preserve zero/unknown accounting before this crash fallback.
    /// There is no claim that closing the handle proves termination completed.
    pub fn close(self: *Job) !void {
        var failed = false;
        if (self.port) |port| {
            self.port = null;
            if (w.CloseHandle(port) == 0) failed = true;
        }
        if (self.handle) |job| {
            self.handle = null;
            if (w.CloseHandle(job) == 0) failed = true;
        }
        if (failed) return error.JobHandleCloseFailed;
    }
};

fn validateLimits(limits: w.ExtendedLimits) !void {
    if (limits.basic.flags != caps.flags or limits.basic.active_processes != caps.active or
        limits.process_memory != caps.process_memory or limits.job_memory != caps.job_memory)
        return error.JobLimitContractMismatch;
}
