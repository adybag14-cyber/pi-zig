//! Per-command OS capabilities; never discover or kill processes by name.
const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
extern fn pi_durable_peek_child(pid: c_int, exit_code: *i64) callconv(.c) c_int;
const win = struct {
    extern "kernel32" fn CreateJobObjectW(attributes: ?*const anyopaque, name: ?[*:0]const u16) callconv(.winapi) ?windows.HANDLE;
    extern "kernel32" fn AssignProcessToJobObject(job: windows.HANDLE, process: windows.HANDLE) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn TerminateJobObject(job: windows.HANDLE, exit_code: windows.UINT) callconv(.winapi) windows.BOOL;
    extern "kernel32" fn GetExitCodeProcess(process: windows.HANDLE, exit_code: *windows.DWORD) callconv(.winapi) windows.BOOL;
};
pub const Control = struct {
    child: *std.process.Child,
    job: if (builtin.os.tag == .windows) windows.HANDLE else void,
    /// Windows children must be spawned suspended before assigning the job.
    pub fn init(child: *std.process.Child) !Control {
        if (builtin.os.tag == .windows) {
            const job = win.CreateJobObjectW(null, null) orelse return error.OwnedJobCreationFailed;
            errdefer windows.CloseHandle(job);
            if (win.AssignProcessToJobObject(job, child.id.?) == .FALSE) return error.OwnedJobAssignmentFailed;
            if (windows.ntdll.NtResumeThread(child.thread_handle, null) != .SUCCESS) return error.OwnedChildResumeFailed;
            return .{ .child = child, .job = job };
        }
        return .{ .child = child, .job = {} };
    }
    pub fn deinit(self: *Control) void {
        if (builtin.os.tag == .windows) windows.CloseHandle(self.job);
        self.* = undefined;
    }
    /// Until the final wait, the process handle or unreaped PID still refers
    /// to this exact child. Its process group/job contains only its descendants.
    pub fn kill(self: *const Control) void {
        const id = self.child.id orelse return;
        if (builtin.os.tag == .windows) {
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
            switch (windows.ntdll.NtWaitForSingleObject(id, .FALSE, &timeout)) {
                .TIMEOUT => return null,
                windows.NTSTATUS.WAIT_0 => {},
                else => return error.OwnedChildStatusFailed,
            }
            var exit_code: windows.DWORD = 0;
            if (win.GetExitCodeProcess(id, &exit_code) == .FALSE) return error.OwnedChildStatusFailed;
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
