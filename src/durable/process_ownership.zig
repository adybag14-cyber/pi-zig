//! Per-command OS capabilities; never discover or kill processes by name.
const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
extern fn pi_durable_peek_child(pid: c_int, exit_code: *i64) callconv(.c) c_int;
const win = struct {
    const BasicLimits = extern struct { process_time: i64, job_time: i64, flags: u32, minimum_working_set: usize, maximum_working_set: usize, active_processes: u32, affinity: usize, priority: u32, scheduling: u32 };
    const Counters = extern struct { read_ops: u64, write_ops: u64, other_ops: u64, read_bytes: u64, write_bytes: u64, other_bytes: u64 };
    const Limits = extern struct { basic: BasicLimits, counters: Counters, process_memory: usize, job_memory: usize, peak_process_memory: usize, peak_job_memory: usize };
    extern "kernel32" fn CreateJobObjectW(attributes: ?*const anyopaque, name: ?[*:0]const u16) callconv(.winapi) ?windows.HANDLE;
    extern "kernel32" fn AssignProcessToJobObject(job: windows.HANDLE, process: windows.HANDLE) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn TerminateJobObject(job: windows.HANDLE, exit_code: windows.UINT) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn GetExitCodeProcess(process: windows.HANDLE, exit_code: *windows.DWORD) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn SetInformationJobObject(job: windows.HANDLE, class: u32, information: *const anyopaque, length: u32) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn GetSystemDirectoryW(buffer: [*]u16, length: windows.UINT) callconv(.winapi) windows.UINT;
    extern "kernel32" fn GetProcessId(process: windows.HANDLE) callconv(.winapi) windows.DWORD;
    extern "kernel32" fn DuplicateHandle(source_process: windows.HANDLE, source: windows.HANDLE, target_process: windows.HANDLE, target: *windows.HANDLE, access: windows.DWORD, inherit: windows.BOOL, options: windows.DWORD) callconv(.winapi) windows.BOOL;
};
pub const Control = struct {
    child: *std.process.Child,
    job: if (builtin.os.tag == .windows) windows.HANDLE else void,
    process_lease: if (builtin.os.tag == .windows) windows.HANDLE else void,
    daemon_io: ?std.Io = null,
    pub fn initForDaemon(child: *std.process.Child, io: std.Io) !Control {
        var control = try initWithFlags(child, 0x1c00);
        control.daemon_io = io;
        return control;
    }
    /// Windows children must be spawned suspended before assigning the job.
    pub fn init(child: *std.process.Child) !Control {
        return initWithFlags(child, 0);
    }
    pub fn initWithFlags(child: *std.process.Child, flags: u32) !Control {
        if (builtin.os.tag == .windows) {
            const job = win.CreateJobObjectW(null, null) orelse return error.OwnedJobCreationFailed;
            errdefer windows.CloseHandle(job);
            var process_lease: windows.HANDLE = undefined;
            if (win.DuplicateHandle(windows.GetCurrentProcess(), child.id.?, windows.GetCurrentProcess(), &process_lease, 0, .FALSE, 2) == .FALSE) return error.OwnedChildHandleCloneFailed;
            errdefer windows.CloseHandle(process_lease);
            if (flags != 0) {
                var limits = std.mem.zeroes(win.Limits);
                limits.basic.flags = flags;
                if (win.SetInformationJobObject(job, 9, &limits, @sizeOf(win.Limits)) == .FALSE) return error.OwnedJobLimitsFailed;
            }
            if (win.AssignProcessToJobObject(job, child.id.?) == .FALSE) return error.OwnedJobAssignmentFailed;
            if (windows.ntdll.NtResumeThread(child.thread_handle, null) != .SUCCESS) return error.OwnedChildResumeFailed;
            return .{ .child = child, .job = job, .process_lease = process_lease };
        }
        return .{ .child = child, .job = {}, .process_lease = {} };
    }
    pub fn deinit(self: *Control) void {
        if (builtin.os.tag == .windows) {
            windows.CloseHandle(self.job);
            windows.CloseHandle(self.process_lease);
        }
        self.* = undefined;
    }
    /// Until the final wait, the process handle or unreaped PID still refers
    /// to this exact child. Its process group/job contains only its descendants.
    pub fn kill(self: *const Control) void {
        const id = self.child.id orelse return;
        if (builtin.os.tag == .windows) {
            if (self.daemon_io) |io| {
                // Keep the root process handle leased while taskkill discovers
                // descendants. No process name, user supplied PID, or global
                // enumeration participates in selecting the owned root.
                const allocator = std.heap.page_allocator;
                var timeout: windows.LARGE_INTEGER = -1;
                // A duplicated handle cannot alias a newly allocated handle
                // while Child.wait closes its own process reference.
                if (windows.ntdll.NtWaitForSingleObject(self.process_lease, .FALSE, &timeout) != .TIMEOUT) return;
                var directory: [1024]u16 = undefined;
                const length = win.GetSystemDirectoryW(&directory, directory.len);
                if (length != 0 and length < directory.len) {
                    const path = std.unicode.wtf16LeToWtf8Alloc(allocator, directory[0..length]) catch null;
                    if (path) |system_directory| {
                        defer allocator.free(system_directory);
                        const program = std.fmt.allocPrint(allocator, "{s}\\taskkill.exe", .{system_directory}) catch null;
                        if (program) |owned_program| {
                            defer allocator.free(owned_program);
                            var pid_buffer: [20]u8 = undefined;
                            const owned_pid = win.GetProcessId(self.process_lease);
                            if (owned_pid == 0) return;
                            const pid = std.fmt.bufPrint(&pid_buffer, "{d}", .{owned_pid}) catch unreachable;
                            if (std.process.spawn(io, .{ .argv = &.{ owned_program, "/F", "/T", "/PID", pid }, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore, .create_no_window = true })) |spawned| {
                                var helper = spawned;
                                defer helper.kill(io);
                                _ = helper.wait(io) catch {};
                            } else |_| {}
                        }
                    }
                }
            }
            _ = win.TerminateJobObject(self.job, 1);
        } else {
            std.posix.kill(-id, .KILL) catch {
                std.posix.kill(id, .KILL) catch {};
            };
        }
    }
    /// Get the full exit status without reaping or closing pipe handles.
    pub fn peek(self: *const Control) !?i64 {
        const id = self.child.id orelse return error.OwnedChildAlreadyReaped;
        if (builtin.os.tag == .windows) {
            var timeout: windows.LARGE_INTEGER = -1;
            switch (windows.ntdll.NtWaitForSingleObject(self.process_lease, .FALSE, &timeout)) {
                .TIMEOUT => return null,
                windows.NTSTATUS.WAIT_0 => {},
                else => return error.OwnedChildStatusFailed,
            }
            var exit_code: windows.DWORD = 0;
            if (win.GetExitCodeProcess(self.process_lease, &exit_code) == .FALSE) return error.OwnedChildStatusFailed;
            return exit_code;
        }
        var exit_code: i64 = 0;
        return switch (pi_durable_peek_child(id, &exit_code)) {
            0 => null,
            1 => exit_code,
            else => error.OwnedChildStatusFailed,
        };
    }
};
/// A daemon lifecycle boundary, separate from each ordinary command lifetime.
/// Completed commands may leave descendants until this owner itself closes.
pub const ParentJob = struct {
    handle: if (builtin.os.tag == .windows) ?windows.HANDLE else void,
    pub fn init() !ParentJob {
        if (builtin.os.tag == .windows) {
            const job = win.CreateJobObjectW(null, null) orelse return error.OwnedJobCreationFailed;
            errdefer windows.CloseHandle(job);
            var limits = std.mem.zeroes(win.Limits);
            // libuv's daemon job permits detached descendants to break away.
            // Completed background commands must not become daemon-owned work.
            limits.basic.flags = 0x3c00;
            if (win.SetInformationJobObject(job, 9, &limits, @sizeOf(win.Limits)) == .FALSE) return error.OwnedJobLimitsFailed;
            return .{ .handle = job };
        }
        return .{ .handle = {} };
    }
    pub fn assign(self: *ParentJob, child: *std.process.Child) !void {
        if (builtin.os.tag == .windows) {
            if (win.AssignProcessToJobObject(self.handle.?, child.id.?) == .FALSE) return error.OwnedJobAssignmentFailed;
        }
    }
    pub fn deinit(self: *ParentJob) void {
        if (builtin.os.tag == .windows) if (self.handle) |handle| windows.CloseHandle(handle);
        self.* = undefined;
    }
};
