//! Raw launch ownership is retained before metadata/probe/persistence work.
const std = @import("std");
const w = @import("win32.zig");
const job_module = @import("job.zig");
const Deadline = @import("deadline.zig").Deadline;

pub const KernelIdentity = struct {
    pid: u32,
    creation_filetime_utc: u64,
    image: [32768]u16,
    image_units: u32,
    pub fn path(self: *const KernelIdentity) []const u16 {
        return self.image[0..self.image_units];
    }
};
pub const ExitRecord = struct { pid: u32, creation_filetime_utc: u64, exit_code: u32 };

pub const Launch = struct {
    info: w.ProcessInfo = std.mem.zeroes(w.ProcessInfo),
    created_by_this_call: bool = false,
    assigned: bool = false,
    resumed: bool = false,
    full_identity_bound: bool = false,
    kernel: ?KernelIdentity = null,

    /// Caller must open/flush intent and arm cleanup before this function.
    /// On success returned handles are already in self, even if later work fails.
    pub fn createSuspended(self: *Launch, allocator: std.mem.Allocator, exe: [:0]const u16,
        mutable_command: [:0]u16, cwd: [:0]const u16, env_block: []const u16,
        inherited: []const w.H, stdin: w.H, stdout: w.H, stderr: w.H) !void
    {
        if (self.created_by_this_call or self.info.process != null or inherited.len < 3 or inherited.len > 8)
            return error.InvalidLaunchState;
        if (env_block.len < 2 or env_block[env_block.len - 1] != 0 or env_block[env_block.len - 2] != 0)
            return error.InvalidExplicitEnvironment;
        for ([_]w.H{ stdin, stdout, stderr }) |needed| {
            if (std.mem.indexOfScalar(w.H, inherited, needed) == null) return error.StdioNotAllowlisted;
        }
        for (inherited, 0..) |handle, index| {
            if (std.mem.indexOfScalar(w.H, inherited[0..index], handle) != null) return error.DuplicateInheritedHandle;
            var flags: u32 = 0;
            if (w.GetHandleInformation(handle, &flags) == 0 or flags & w.handle_flag_inherit == 0)
                return error.AllowlistedHandleNotInheritable;
        }
        var size: usize = 0;
        _ = w.InitializeProcThreadAttributeList(null, 1, 0, &size);
        if (size == 0 or size > 65536) return error.AttributeStorageUnverifiable;
        const storage = try allocator.alloc(usize, (size + @sizeOf(usize) - 1) / @sizeOf(usize));
        defer allocator.free(storage);
        const attributes: *anyopaque = @ptrCast(storage.ptr);
        if (w.InitializeProcThreadAttributeList(attributes, 1, 0, &size) == 0) return error.AttributeInitFailed;
        defer w.DeleteProcThreadAttributeList(attributes);
        if (w.UpdateProcThreadAttribute(attributes, 0, w.attribute_handle_list,
            @ptrCast(@constCast(inherited.ptr)), inherited.len * @sizeOf(w.H), null, null) == 0)
            return error.HandleAllowlistFailed;
        var startup: w.StartupEx = std.mem.zeroes(w.StartupEx);
        startup.info.size = @sizeOf(w.StartupEx);
        startup.info.flags = w.startf_use_std_handles;
        startup.info.stdin = stdin;
        startup.info.stdout = stdout;
        startup.info.stderr = stderr;
        startup.attributes = attributes;
        // No operation occurs between successful CreateProcessW and retention:
        // the API writes directly into this cleanup-owned state, then we arm it.
        if (w.CreateProcessW(exe.ptr, mutable_command.ptr, null, null, 1,
            w.create_suspended | w.create_unicode_environment | w.extended_startupinfo_present | w.create_no_window,
            env_block.ptr, cwd.ptr, &startup.info, &self.info) == 0) return error.CreateSuspendedFailed;
        self.created_by_this_call = true;
    }

    pub fn assignWorker(self: *Launch, job: *job_module.Job) !void {
        if (!self.created_by_this_call or self.resumed or self.assigned) return error.InvalidAssignmentState;
        if (!job.queried_limits or job.termination_requested) return error.JobNotAdmitting;
        // Assignment may succeed even if its following verification fails:
        // record that association before any subsequent query can throw.
        const handle = self.info.process orelse return error.NoCreatedHandle;
        const job_handle = job.handle orelse return error.JobClosed;
        if (w.AssignProcessToJobObject(job_handle, handle) == 0) return error.NestedJobAssignmentFailed;
        self.assigned = true;
        try job.requireMember(handle);
    }

    /// Worker receives this acknowledgement only over the nonce/sequence-bound
    /// control channel after supervisor independently pulled and verified Node.
    /// The worker is never passed a job/supervisor handle to perform the query.
    pub fn acknowledgeInheritedNode(self: *Launch, pid: u32, creation: u64) !void {
        if (!self.created_by_this_call or self.resumed or self.kernel == null)
            return error.InvalidNodeBindingState;
        if (self.info.pid != pid or self.kernel.?.creation_filetime_utc != creation)
            return error.NodeAcknowledgementMismatch;
        self.assigned = true;
    }

    pub fn queryKernel(self: *Launch) !void {
        const handle = self.info.process orelse return error.NoCreatedHandle;
        self.kernel = try identity(handle);
        if (self.kernel.?.pid != self.info.pid) return error.CreatedPidMismatch;
    }

    /// Caller can set full_identity_bound only after image/hash/live WMI parent,
    /// command line and UTC comparison, flushed binding receipt and supervisor ACK.
    pub fn resume(self: *Launch) !void {
        if (!self.created_by_this_call or !self.assigned or !self.full_identity_bound or self.resumed)
            return error.UnboundResumeForbidden;
        const count = w.ResumeThread(self.info.thread orelse return error.NoCreatedThread);
        if (count != 1) return error.UnexpectedSuspendCount;
        self.resumed = true;
    }

    /// Only for a failed pre-assignment launch. Never used for an assigned tree.
    /// Retained CreateProcess handle is authority even if metadata capture failed.
    pub fn stopUnassigned(self: *Launch, retirement_end: u64) !void {
        if (!self.created_by_this_call or self.assigned or self.resumed) return error.UnassignedStopForbidden;
        const handle = self.info.process orelse return error.NoCreatedHandle;
        const wait = w.WaitForSingleObject(handle, 0);
        if (wait == w.wait_object) return;
        if (wait != w.wait_timeout) return error.SuspendedStateUnverifiable;
        if (w.TerminateProcess(handle, 125) == 0) return error.SuspendedTerminationFailed;
        if (w.WaitForSingleObject(handle, Deadline.remaining(retirement_end)) != w.wait_object)
            return error.SuspendedTerminationUnproven;
    }

    /// Must persist returned record before releaseExited; no endless Child.wait.
    pub fn exitRecord(self: *const Launch) !ExitRecord {
        const handle = self.info.process orelse return error.NoCreatedHandle;
        if (w.WaitForSingleObject(handle, 0) != w.wait_object) return error.ProcessNotRetired;
        var created: w.FileTime = undefined;
        var exited: w.FileTime = undefined;
        var kernel_time: w.FileTime = undefined;
        var user_time: w.FileTime = undefined;
        if (w.GetProcessTimes(handle, &created, &exited, &kernel_time, &user_time) == 0)
            return error.ExitIdentityUnverifiable;
        const pid = w.GetProcessId(handle);
        if (pid == 0 or pid != self.info.pid) return error.ExitIdentityUnverifiable;
        if (self.kernel) |bound| if (bound.creation_filetime_utc != created.ticks())
            return error.ExitIdentityChanged;
        var exit_code: u32 = 0;
        if (w.GetExitCodeProcess(handle, &exit_code) == 0) return error.ExitCodeUnverifiable;
        return .{ .pid = pid, .creation_filetime_utc = created.ticks(), .exit_code = exit_code };
    }

    pub fn releaseExited(self: *Launch) !void {
        if (self.info.process) |handle| {
            if (w.WaitForSingleObject(handle, 0) != w.wait_object) return error.LiveProcessReleaseForbidden;
        }
        var failed = false;
        if (self.info.thread) |handle| {
            if (w.CloseHandle(handle) == 0) failed = true else self.info.thread = null;
        }
        if (self.info.process) |handle| {
            if (w.CloseHandle(handle) == 0) failed = true else self.info.process = null;
        }
        if (failed) return error.ProcessReferenceReleaseFailed;
    }
};

pub fn identity(handle: w.H) !KernelIdentity {
    var result: KernelIdentity = undefined;
    result.pid = w.GetProcessId(handle);
    if (result.pid == 0) return error.ProcessIdUnverifiable;
    var created: w.FileTime = undefined;
    var exited: w.FileTime = undefined;
    var kernel: w.FileTime = undefined;
    var user: w.FileTime = undefined;
    if (w.GetProcessTimes(handle, &created, &exited, &kernel, &user) == 0) return error.CreationTimeUnverifiable;
    result.creation_filetime_utc = created.ticks();
    result.image_units = result.image.len;
    if (w.QueryFullProcessImageNameW(handle, 0, &result.image, &result.image_units) == 0 or
        result.image_units == 0 or result.image_units >= result.image.len) return error.ImagePathUnverifiable;
    return result;
}

pub fn pullNode(worker: w.H, worker_local_node: usize, expected_pid: u32, job: *const job_module.Job) !w.H {
    if (worker_local_node == 0 or worker_local_node == std.math.maxInt(usize)) return error.InvalidSourceNodeHandle;
    var duplicate: w.H = undefined;
    if (w.DuplicateHandle(worker, @ptrFromInt(worker_local_node), w.GetCurrentProcess(), &duplicate,
        0, 0, w.duplicate_same_access) == 0) return error.NodeHandlePullFailed;
    errdefer _ = w.CloseHandle(duplicate);
    if (w.GetProcessId(duplicate) != expected_pid) return error.PulledNodePidMismatch;
    try job.requireMember(duplicate);
    return duplicate;
}
