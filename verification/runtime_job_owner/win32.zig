//! Verification-only Windows ABI. No existing-job open or global kill API.
const std = @import("std");
pub const H = *anyopaque;
pub const B = i32;
pub const D = u32;
pub const invalid: H = @ptrFromInt(std.math.maxInt(usize));
pub const wait_object = 0;
pub const wait_timeout = 258;
pub const wait_failed = 0xffffffff;
pub const error_io_pending = 997;
pub const error_operation_aborted = 995;
pub const error_broken_pipe = 109;
pub const error_pipe_not_connected = 233;
pub const error_not_found = 1168;
pub const error_more_data = 234;
pub const duplicate_same_access = 2;
pub const handle_flag_inherit = 1;
pub const process_query_limited = 0x1000;
pub const process_synchronize = 0x00100000;
pub const create_suspended = 0x00000004;
pub const detached_process = 0x00000008;
pub const create_unicode_environment = 0x00000400;
pub const extended_startupinfo_present = 0x00080000;
pub const create_no_window = 0x08000000;
pub const attribute_handle_list = 0x00020002;
pub const attribute_job_list = 0x0002000d;
pub const startf_use_std_handles = 0x00000100;
pub const generic_read = 0x80000000;
pub const generic_write = 0x40000000;
pub const share_read = 1;
pub const open_existing = 3;
pub const create_new = 1;
pub const file_flag_overlapped = 0x40000000;
pub const file_flag_open_reparse_point = 0x00200000;
pub const file_flag_backup_semantics = 0x02000000;
pub const file_attribute_reparse_point = 0x400;
pub const file_attribute_directory = 0x10;

pub const FileTime = extern struct {
    low: u32,
    high: u32,
    pub fn ticks(self: FileTime) u64 {
        return @as(u64, self.high) << 32 | self.low;
    }
};
pub const Security = extern struct { length: u32, descriptor: ?*anyopaque, inherit: B };
pub const Startup = extern struct {
    size: u32,
    reserved: ?[*:0]u16,
    desktop: ?[*:0]u16,
    title: ?[*:0]u16,
    x: u32,
    y: u32,
    x_size: u32,
    y_size: u32,
    x_count_chars: u32,
    y_count_chars: u32,
    fill_attribute: u32,
    flags: u32,
    show_window: u16,
    reserved_size: u16,
    reserved_bytes: ?[*]u8,
    stdin: ?H,
    stdout: ?H,
    stderr: ?H,
};
pub const StartupEx = extern struct { info: Startup, attributes: ?*anyopaque };
pub const ProcessInfo = extern struct { process: ?H, thread: ?H, pid: u32, tid: u32 };
pub const Overlapped = extern struct { internal: usize, internal_high: usize, offset: u64, event: ?H };
pub const BasicLimits = extern struct {
    process_user_time: i64,
    job_user_time: i64,
    flags: u32,
    min_working_set: usize,
    max_working_set: usize,
    active_processes: u32,
    affinity: usize,
    priority: u32,
    scheduling: u32,
};
pub const IoCounters = extern struct {
    read_operations: u64,
    write_operations: u64,
    other_operations: u64,
    read_bytes: u64,
    write_bytes: u64,
    other_bytes: u64,
};
pub const ExtendedLimits = extern struct {
    basic: BasicLimits,
    reserved_io: IoCounters,
    process_memory: usize,
    job_memory: usize,
    peak_process_memory: usize,
    peak_job_memory: usize,
};
pub const Accounting = extern struct {
    user_time: i64,
    kernel_time: i64,
    period_user_time: i64,
    period_kernel_time: i64,
    page_faults: u32,
    total_processes: u32,
    active_processes: u32,
    terminated_for_limit: u32,
};
pub const AccountingIo = extern struct { basic: Accounting, io: IoCounters };
pub const ProcessList = extern struct { assigned: u32, returned: u32, pids: [64]usize };
pub const AssociatePort = extern struct { key: *anyopaque, port: H };
pub const MemoryStatus = extern struct {
    length: u32,
    load: u32,
    total_physical: u64,
    available_physical: u64,
    total_pagefile: u64,
    available_pagefile: u64,
    total_virtual: u64,
    available_virtual: u64,
    available_extended_virtual: u64,
};
pub const FileId = extern struct { volume: u64, id: [16]u8 };
pub const AttributeTag = extern struct { attributes: u32, reparse_tag: u32 };
pub const FindData = extern struct {
    attributes: u32,
    creation: FileTime,
    access: FileTime,
    write: FileTime,
    size_high: u32,
    size_low: u32,
    reserved0: u32,
    reserved1: u32,
    name: [260]u16,
    alternate: [14]u16,
};
pub const ProcessEntry = extern struct {
    size: u32,
    usage: u32,
    pid: u32,
    default_heap: usize,
    module: u32,
    threads: u32,
    parent_pid: u32,
    priority: i32,
    flags: u32,
    executable: [260]u16,
};

pub extern "kernel32" fn GetLastError() callconv(.winapi) u32;
pub extern "kernel32" fn CloseHandle(H) callconv(.winapi) B;
pub extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
pub extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
pub extern "kernel32" fn GetSystemTimePreciseAsFileTime(*FileTime) callconv(.winapi) void;
pub extern "kernel32" fn GlobalMemoryStatusEx(*MemoryStatus) callconv(.winapi) B;
pub extern "kernel32" fn GetHandleInformation(H, *u32) callconv(.winapi) B;
pub extern "kernel32" fn SetHandleInformation(H, u32, u32) callconv(.winapi) B;
pub extern "kernel32" fn CreateJobObjectW(?*const Security, ?[*:0]const u16) callconv(.winapi) ?H;
pub extern "kernel32" fn SetInformationJobObject(H, u32, *const anyopaque, u32) callconv(.winapi) B;
pub extern "kernel32" fn QueryInformationJobObject(H, u32, *anyopaque, u32, ?*u32) callconv(.winapi) B;
pub extern "kernel32" fn IsProcessInJob(H, ?H, *B) callconv(.winapi) B;
pub extern "kernel32" fn TerminateJobObject(H, u32) callconv(.winapi) B;
pub extern "kernel32" fn CreateIoCompletionPort(H, ?H, usize, u32) callconv(.winapi) ?H;
// Job ports use the LPOVERLAPPED-sized output as an integer PID, not a pointer
// to aligned OVERLAPPED storage. Preserve raw bits without pointer assumptions.
pub extern "kernel32" fn GetQueuedCompletionStatus(H, *u32, *usize, *usize, u32) callconv(.winapi) B;
pub extern "kernel32" fn CreateProcessW([*:0]const u16, [*:0]u16, ?*const Security, ?*const Security, B, u32, ?*const anyopaque, [*:0]const u16, *Startup, *ProcessInfo) callconv(.winapi) B;
pub extern "kernel32" fn InitializeProcThreadAttributeList(?*anyopaque, u32, u32, *usize) callconv(.winapi) B;
pub extern "kernel32" fn UpdateProcThreadAttribute(*anyopaque, u32, usize, *anyopaque, usize, ?*anyopaque, ?*usize) callconv(.winapi) B;
pub extern "kernel32" fn DeleteProcThreadAttributeList(*anyopaque) callconv(.winapi) void;
pub extern "kernel32" fn GetProcessId(H) callconv(.winapi) u32;
pub extern "kernel32" fn GetProcessTimes(H, *FileTime, *FileTime, *FileTime, *FileTime) callconv(.winapi) B;
pub extern "kernel32" fn QueryFullProcessImageNameW(H, u32, [*]u16, *u32) callconv(.winapi) B;
pub extern "kernel32" fn GetExitCodeProcess(H, *u32) callconv(.winapi) B;
pub extern "kernel32" fn OpenProcess(u32, B, u32) callconv(.winapi) ?H;
pub extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, B, u32) callconv(.winapi) B;
pub extern "kernel32" fn ResumeThread(H) callconv(.winapi) u32;
pub extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
pub extern "kernel32" fn WaitForMultipleObjects(u32, [*]const H, B, u32) callconv(.winapi) u32;
pub extern "kernel32" fn CreateEventW(?*const Security, B, B, ?[*:0]const u16) callconv(.winapi) ?H;
pub extern "kernel32" fn SetEvent(H) callconv(.winapi) B;
pub extern "kernel32" fn ResetEvent(H) callconv(.winapi) B;
pub extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const Security, u32, u32, ?H) callconv(.winapi) H;
pub extern "kernel32" fn ReadFile(H, *anyopaque, u32, ?*u32, ?*Overlapped) callconv(.winapi) B;
pub extern "kernel32" fn WriteFile(H, *const anyopaque, u32, ?*u32, ?*Overlapped) callconv(.winapi) B;
pub extern "kernel32" fn GetOverlappedResult(H, *Overlapped, *u32, B) callconv(.winapi) B;
pub extern "kernel32" fn CancelIoEx(H, ?*Overlapped) callconv(.winapi) B;
pub extern "kernel32" fn FlushFileBuffers(H) callconv(.winapi) B;
pub extern "kernel32" fn GetFileInformationByHandleEx(H, u32, *anyopaque, u32) callconv(.winapi) B;
pub extern "kernel32" fn GetFileSizeEx(H, *i64) callconv(.winapi) B;
pub extern "kernel32" fn FindFirstFileW([*:0]const u16, *FindData) callconv(.winapi) H;
pub extern "kernel32" fn FindNextFileW(H, *FindData) callconv(.winapi) B;
pub extern "kernel32" fn FindClose(H) callconv(.winapi) B;
pub extern "kernel32" fn CreateDirectoryW([*:0]const u16, ?*const Security) callconv(.winapi) B;
pub extern "kernel32" fn CreateToolhelp32Snapshot(u32, u32) callconv(.winapi) H;
pub extern "kernel32" fn Process32FirstW(H, *ProcessEntry) callconv(.winapi) B;
pub extern "kernel32" fn Process32NextW(H, *ProcessEntry) callconv(.winapi) B;
pub extern "kernel32" fn DeviceIoControl(H, u32, ?*const anyopaque, u32, ?*anyopaque, u32, *u32, ?*Overlapped) callconv(.winapi) B;
pub extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]u16;
pub extern "kernel32" fn GetModuleFileNameW(?H, [*]u16, u32) callconv(.winapi) u32;
pub extern "kernel32" fn GetStdHandle(u32) callconv(.winapi) ?H;
pub extern "kernel32" fn ExitProcess(u32) callconv(.winapi) noreturn;
pub extern "kernel32" fn MoveFileExW([*:0]const u16, [*:0]const u16, u32) callconv(.winapi) B;
pub extern "kernel32" fn CopyFileW([*:0]const u16, [*:0]const u16, B) callconv(.winapi) B;
pub extern "kernel32" fn CompareStringOrdinal([*]const u16, i32, [*]const u16, i32, B) callconv(.winapi) i32;
pub extern "kernel32" fn CreateThread(?*const Security, usize, *const fn (?*anyopaque) callconv(.winapi) u32, ?*anyopaque, u32, ?*u32) callconv(.winapi) ?H;
pub extern "kernel32" fn LocalFree(?H) callconv(.winapi) ?H;
pub extern "kernel32" fn CreateNamedPipeW([*:0]const u16, u32, u32, u32, u32, u32, u32, ?*const Security) callconv(.winapi) H;
pub extern "kernel32" fn ConnectNamedPipe(H, ?*Overlapped) callconv(.winapi) B;
pub extern "kernel32" fn GetNamedPipeClientProcessId(H, *u32) callconv(.winapi) B;
pub extern "kernel32" fn GetNamedPipeServerProcessId(H, *u32) callconv(.winapi) B;
pub extern "advapi32" fn OpenProcessToken(H, u32, *H) callconv(.winapi) B;
pub extern "advapi32" fn GetTokenInformation(H, u32, *anyopaque, u32, *u32) callconv(.winapi) B;
pub extern "advapi32" fn ConvertSidToStringSidW(*anyopaque, *?[*:0]u16) callconv(.winapi) B;
pub extern "advapi32" fn ConvertStringSecurityDescriptorToSecurityDescriptorW([*:0]const u16, u32, *?*anyopaque, ?*u32) callconv(.winapi) B;
pub extern "bcrypt" fn BCryptGenRandom(?H, [*]u8, u32, u32) callconv(.winapi) i32;
pub extern "shell32" fn CommandLineToArgvW([*:0]const u16, *i32) callconv(.winapi) ?[*][*:0]u16;

comptime {
    if (@import("builtin").os.tag != .windows or @sizeOf(usize) != 8)
        @compileError("runtime reproduction owner supports Windows x86_64 only");
    if (@sizeOf(Startup) != 104 or @sizeOf(StartupEx) != 112 or
        @sizeOf(ProcessInfo) != 24 or @sizeOf(Overlapped) != 32 or
        @sizeOf(BasicLimits) != 64 or @sizeOf(ExtendedLimits) != 144 or
        @sizeOf(Accounting) != 48 or @sizeOf(AccountingIo) != 96 or
        @offsetOf(ProcessList, "pids") != 8 or @sizeOf(MemoryStatus) != 64)
        @compileError("Win32 ABI layout mismatch");
    if (@sizeOf(FindData) != 592) @compileError("FindData ABI layout mismatch");
    if (@sizeOf(ProcessEntry) != 568) @compileError("ProcessEntry ABI layout mismatch");
}
