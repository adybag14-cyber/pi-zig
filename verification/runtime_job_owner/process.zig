//! Raw launch ownership is retained before metadata/probe/persistence work.
const std = @import("std");
const w = @import("win32.zig");
const job_module = @import("job.zig");

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
pub const VerifiedWorkerContext = struct {
    worker_pid: u32,
    creation_filetime_utc: u64,
    supervisor_pid: u32,
    pub fn fromAuthenticatedBootstrap(bootstrap: *const @import("protocol.zig").WorkerBootstrap) !VerifiedWorkerContext {
        if (!bootstrap.authenticated) return error.AuthenticatedWorkerBootstrapRequired;
        const self: VerifiedWorkerContext = .{ .worker_pid = bootstrap.frame.pid,
            .creation_filetime_utc = bootstrap.frame.creation_filetime_utc, .supervisor_pid = bootstrap.frame.parent_pid };
        try self.requireCurrent();
        return self;
    }
    fn requireCurrent(self: VerifiedWorkerContext) !void {
        const current = try identity(w.GetCurrentProcess());
        if (self.supervisor_pid == 0 or current.pid != self.worker_pid or
            current.creation_filetime_utc != self.creation_filetime_utc) return error.WorkerRoleIdentityMismatch;
        var member: w.B = 0;
        if (w.IsProcessInJob(w.GetCurrentProcess(), null, &member) == 0 or member == 0)
            return error.WorkerInheritedJobUnverifiable;
        // Exact job is proved by supervisor; no job handle enters the worker.
    }
};

pub const Launch = struct {
    info: w.ProcessInfo = std.mem.zeroes(w.ProcessInfo),
    created_by_this_call: bool = false,
    assigned: bool = false,
    resumed: bool = false,
    full_identity_bound: bool = false,
    role: enum { unset, worker, node } = .unset,
    node_resume_acknowledged: bool = false,
    last_create_error: ?u32 = null,
    kernel: ?KernelIdentity = null,

    /// Mandatory atomic worker path. JOB_LIST association is part of creation;
    /// there is no successful worker outside the kill-on-close job.
    pub fn createWorkerInJob(self: *Launch, job: *job_module.Job, allocator: std.mem.Allocator, exe: [:0]const u16,
        mutable_command: [:0]u16, cwd: [:0]const u16, env_block: []const u16,
        inherited: []const w.H, stdin: w.H, stdout: w.H, stderr: w.H) !void
    {
        if (self.role != .unset) return error.LaunchRoleAlreadyAttempted;
        if (!job.queried_limits or job.termination_requested or job.worker_assigned) return error.JobNotAdmitting;
        const handle = job.handle orelse return error.JobClosed;
        if (std.mem.indexOfScalar(w.H, inherited, handle) != null) return error.JobHandleInheritanceForbidden;
        self.role = .worker;
        try self.createRaw(allocator, exe, mutable_command, cwd, env_block, inherited, stdin, stdout, stderr, handle);
        // No fallible probe/persistence operation before these local state bits.
        self.assigned = true;
        job.worker_assigned = true;
        try job.requireMember(self.info.process orelse return error.NoCreatedHandle);
    }

    /// Node inherits the job of the already creation-time-contained worker.
    /// Caller must authenticate its worker bootstrap before obtaining this role.
    /// Supervisor still pulls the exact Node handle and proves membership before ACK.
    pub fn createInheritedNode(self: *Launch, context: VerifiedWorkerContext, allocator: std.mem.Allocator,
        exe: [:0]const u16, mutable_command: [:0]u16, cwd: [:0]const u16, env_block: []const u16,
        inherited: []const w.H, stdin: w.H, stdout: w.H, stderr: w.H) !void
    {
        if (self.role != .unset) return error.LaunchRoleAlreadyAttempted;
        try context.requireCurrent();
        self.role = .node;
        try self.createRaw(allocator, exe, mutable_command, cwd, env_block, inherited, stdin, stdout, stderr, null);
        self.assigned = true;
    }

    /// Internal only; callers cannot choose the no-JOB_LIST worker path.
    /// Intent is flushed and cleanup state armed before entering this method.
    fn createRaw(self: *Launch, allocator: std.mem.Allocator, exe: [:0]const u16,
        mutable_command: [:0]u16, cwd: [:0]const u16, env_block: []const u16,
        inherited: []const w.H, stdin: w.H, stdout: w.H, stderr: w.H, creation_job: ?w.H) !void
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
        const attribute_count: u32 = if (creation_job != null) 2 else 1;
        _ = w.InitializeProcThreadAttributeList(null, attribute_count, 0, &size);
        if (size == 0 or size > 65536) return error.AttributeStorageUnverifiable;
        const storage = try allocator.alloc(usize, (size + @sizeOf(usize) - 1) / @sizeOf(usize));
        defer allocator.free(storage);
        const attributes: *anyopaque = @ptrCast(storage.ptr);
        if (w.InitializeProcThreadAttributeList(attributes, attribute_count, 0, &size) == 0) return error.AttributeInitFailed;
        defer w.DeleteProcThreadAttributeList(attributes);
        if (w.UpdateProcThreadAttribute(attributes, 0, w.attribute_handle_list,
            @ptrCast(@constCast(inherited.ptr)), inherited.len * @sizeOf(w.H), null, null) == 0)
            return error.HandleAllowlistFailed;
        // Value backing storage survives until after DeleteProcThreadAttributeList.
        // JOB_LIST associates the process but does not inherit its job handle.
        var creation_jobs: [1]w.H = undefined;
        if (creation_job) |job_handle| {
            creation_jobs[0] = job_handle;
            if (w.UpdateProcThreadAttribute(attributes, 0, w.attribute_job_list,
                &creation_jobs, @sizeOf(@TypeOf(creation_jobs)), null, null) == 0)
                return error.CreationTimeJobAttributeRequired;
        }
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
            env_block.ptr, cwd.ptr, &startup.info, &self.info) == 0) {
            self.last_create_error = w.GetLastError();
            // FALSE output is undefined, never process/thread ownership. Disarm
            // it before any defer/probe/cleanup can observe these fields.
            self.info = std.mem.zeroes(w.ProcessInfo);
            return error.CreateSuspendedFailed;
        }
        self.created_by_this_call = true;
        self.assigned = true; // JOB_LIST or verified worker inheritance, before defers
    }

    /// Worker receives this acknowledgement only over the nonce/sequence-bound
    /// control channel after supervisor independently pulled and verified Node.
    /// The worker is never passed a job/supervisor handle to perform the query.
    pub fn acknowledgeInheritedNode(self: *Launch, pid: u32, creation: u64) !void {
        if (!self.created_by_this_call or self.resumed or !self.assigned or self.kernel == null or
            self.role != .node or self.node_resume_acknowledged)
            return error.InvalidNodeBindingState;
        if (self.info.pid != pid or self.kernel.?.creation_filetime_utc != creation)
            return error.NodeAcknowledgementMismatch;
        self.node_resume_acknowledged = true;
    }

    pub fn queryKernel(self: *Launch) !void {
        if (!self.created_by_this_call) return error.NoSuccessfulCreationAuthority;
        const handle = self.info.process orelse return error.NoCreatedHandle;
        self.kernel = try identity(handle);
        if (self.kernel.?.pid != self.info.pid) return error.CreatedPidMismatch;
    }

    /// Caller can set full_identity_bound only after image/hash/live WMI parent,
    /// command line and UTC comparison, flushed binding receipt and supervisor ACK.
    pub fn resume(self: *Launch) !void {
        if (!self.created_by_this_call or !self.assigned or !self.full_identity_bound or self.resumed)
            return error.UnboundResumeForbidden;
        if (self.role == .unset or (self.role == .node and !self.node_resume_acknowledged))
            return error.UnacknowledgedResumeForbidden;
        const count = w.ResumeThread(self.info.thread orelse return error.NoCreatedThread);
        if (count != 1) return error.UnexpectedSuspendCount;
        self.resumed = true;
    }

    /// Must persist returned record before releaseExited; no endless Child.wait.
    pub fn exitRecord(self: *const Launch) !ExitRecord {
        if (!self.created_by_this_call) return error.NoSuccessfulCreationAuthority;
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
        if (!self.created_by_this_call) return error.NoSuccessfulCreationAuthority;
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
