//! Windows kernel spawn with owned pipes, explicit environment and detached
//! flags. Paths/argv are already validated by the owner-side Node normalizer.
const std = @import("std");
const w = std.os.windows;
const transport = @import("native_child_process_transport.zig");
const stdin = @import("native_child_process_stdin_windows.zig");
const output_pipe = @import("native_child_process_output_windows.zig");
const inherited_stdio = @import("native_child_process_stdio_windows.zig");
const Native = struct {
    extern "kernel32" fn CreatePipe(*w.HANDLE, *w.HANDLE, *w.SECURITY_ATTRIBUTES, u32) callconv(.winapi) i32;
    extern "kernel32" fn SetHandleInformation(w.HANDLE, u32, u32) callconv(.winapi) i32;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, *w.SECURITY_ATTRIBUTES, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
    extern "kernel32" fn InitializeProcThreadAttributeList(?*anyopaque, u32, u32, *usize) callconv(.winapi) i32;
    extern "kernel32" fn UpdateProcThreadAttribute(*anyopaque, u32, usize, *anyopaque, usize, ?*anyopaque, ?*usize) callconv(.winapi) i32;
    extern "kernel32" fn DeleteProcThreadAttributeList(*anyopaque) callconv(.winapi) void;
};
const StartupInfoEx = extern struct { info: w.STARTUPINFOW, attributes: *anyopaque };
const Endpoint = struct { child: w.HANDLE, parent: ?w.HANDLE = null, input_slot: ?*stdin.Slot = null, child_lease: ?inherited_stdio.Lease = null, crt_flags: u8 };
fn closeChild(item: Endpoint) void {
    if (item.child_lease) |lease| { inherited_stdio.release(lease) catch {}; } else w.CloseHandle(item.child);
}
/// Real prelaunch pipe ownership for Source getValidStdio. It exists before the
/// options.stdio assignment/file/args getters and transfers only at native spawn.
pub const Prepared = struct {
    endpoints: [3]?Endpoint = .{null} ** 3,
    output_slots: [2]?*output_pipe.Slot,
    modes: [3]transport.Stdio,
    source_leases: [3]?inherited_stdio.Lease = .{null} ** 3,
    consumed: bool = false,
    pub fn closeBeforeLaunch(self: *Prepared, index: usize) !void {
        if (self.consumed) return error.NativePreparedStdioOwnershipMoved;
        if (index >= 3) return error.NativePreparedStdioIndex;
        if (self.endpoints[index]) |item| {
            self.endpoints[index] = null;
            closeChild(item);
            if (item.parent) |handle| w.CloseHandle(handle);
            if (item.input_slot) |slot| { _ = slot.retire(); }
        }
        if (index != 0) if (self.output_slots[index - 1]) |slot| { self.output_slots[index - 1] = null; _ = slot.retire(); };
    }
    pub fn retire(self: *Prepared) void {
        if (self.consumed) return;
        for (0..3) |index| self.closeBeforeLaunch(index) catch {};
        self.consumed = true;
    }
    fn take(self: *Prepared, modes: [3]transport.Stdio, leases: [3]?inherited_stdio.Lease) ![3]Endpoint {
        if (self.consumed) return error.NativePreparedStdioOwnershipMoved;
        var result: [3]Endpoint = undefined;
        for (self.endpoints, self.modes, modes, 0..) |maybe_item, original, requested, index| {
            if (original != requested) return error.NativePreparedStdioModeMismatch;
            if (!std.meta.eql(self.source_leases[index], leases[index])) return error.NativePreparedStdioLeaseMismatch;
            result[index] = maybe_item orelse return error.NativePreparedStdioClosed;
        }
        self.consumed = true; self.endpoints = .{null} ** 3;
        return result;
    }
};
pub fn prepare(stdio: [3]transport.Stdio) !Prepared {
    return prepareWithLeases(stdio, .{null} ** 3);
}
pub fn prepareWithLeases(stdio: [3]transport.Stdio, leases: [3]?inherited_stdio.Lease) !Prepared {
    const outputs = try output_pipe.reserveSet(.{ stdio[1] == .pipe, stdio[2] == .pipe });
    var result: Prepared = .{ .output_slots = outputs, .modes = stdio, .source_leases = leases };
    errdefer result.retire();
    var attributes: w.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = null, .bInheritHandle = .TRUE };
    for (stdio, 0..) |mode, index| result.endpoints[index] = try endpoint(mode, index == 0, &attributes, if (index == 0) null else outputs[index - 1], leases[index]);
    return result;
}
fn endpoint(mode: transport.Stdio, input: bool, attributes: *w.SECURITY_ATTRIBUTES, output_slot: ?*output_pipe.Slot, lease: ?inherited_stdio.Lease) !Endpoint {
    if ((mode == .inherited) != (lease != null)) return error.NativeWindowsStdioLeaseModeMismatch;
    if (mode == .inherited) {
        const actual = try inherited_stdio.duplicateForChild(lease.?);
        return .{ .child = actual.handle, .child_lease = actual.lease, .crt_flags = actual.crt_flags };
    }
    if (mode == .ignore) {
        const handle = Native.CreateFileW(std.unicode.utf8ToUtf16LeStringLiteral("NUL"), if (input) 0x80000000 else 0x40000000, 3, attributes, 3, 0x80, null);
        if (handle == w.INVALID_HANDLE_VALUE) return error.NativeChildNullDeviceFailed;
        return .{ .child = handle, .crt_flags = 0x41 };
    }
    if (input) {
        const connected = try stdin.connect();
        return .{ .child = connected.child, .input_slot = connected.slot, .crt_flags = 0x09 };
    }
    if (output_slot) |slot| {
        const connected = try output_pipe.connect(slot);
        return .{ .child = connected.child, .crt_flags = 0x09 };
    }
    var read: w.HANDLE = undefined;
    var write: w.HANDLE = undefined;
    if (Native.CreatePipe(&read, &write, attributes, 0) == 0) return error.NativeChildPipeFailed;
    errdefer { w.CloseHandle(read); w.CloseHandle(write); }
    const parent = if (input) write else read;
    if (Native.SetHandleInformation(parent, 1, 0) == 0) return error.NativeChildPipeInheritanceFailed;
    return .{ .child = if (input) read else write, .parent = parent, .crt_flags = 0x09 };
}
fn quote(gpa: std.mem.Allocator, output: *std.ArrayList(u8), value: []const u8, verbatim: bool) !void {
    if (verbatim or (value.len != 0 and std.mem.indexOfAny(u8, value, " \t\"") == null)) return output.appendSlice(gpa, value);
    try output.append(gpa, '"');
    var slashes: usize = 0;
    for (value) |byte| {
        if (byte == '\\') { slashes += 1; continue; }
        if (byte == '"') {
            for (0..slashes * 2 + 1) |_| try output.append(gpa, '\\');
        } else for (0..slashes) |_| try output.append(gpa, '\\');
        slashes = 0;
        try output.append(gpa, byte);
    }
    for (0..slashes * 2) |_| try output.append(gpa, '\\');
    try output.append(gpa, '"');
}
pub const Spawned = struct { child: std.process.Child, input_slot: ?*stdin.Slot, output_slots: [2]?*output_pipe.Slot };
/// Real failed CreateProcess attempt, with no Process/PID identity. Child-side
/// handles are already closed before return; actual parent endpoints stay owned
/// so output EOF/write failure can be observed rather than fabricated.
pub const Failed = struct { failure: anyerror, input_slot: ?*stdin.Slot, output_slots: [2]?*output_pipe.Slot };
pub const Attempt = union(enum) { spawned: Spawned, failed: Failed };
fn creationFlags(options: transport.Options) w.CreateProcessFlags {
    // libuv 1.51 uv_spawn keeps the inherited console available whenever any
    // normalized stdio entry is UV_INHERIT_FD, even when windowsHide is true.
    var inherited_fd = false;
    for (options.stdio) |mode| if (mode == .inherited) { inherited_fd = true; };
    return .{ .create_unicode_environment = true, .create_no_window = options.windows_hide and !inherited_fd, .detached_process = options.detached, .create_new_process_group = options.detached, .extended_startupinfo_present = true };
}
pub fn spawnAttempt(gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: transport.Options) !Attempt {
    if (!options.windows_overlapped_output) return error.RequiredOverlappedFailedLaunchEndpoints;
    if (options.prepared_stdio) |prepared| return spawnPreparedAttempt(gpa, argv, cwd, env, options, prepared);
    const output_slots = try output_pipe.reserveSet(.{ options.stdio[1] == .pipe, options.stdio[2] == .pipe });
    var failure: ?Failed = null;
    const spawned = spawnOwned(gpa, argv, cwd, env, options, output_slots, &failure, null) catch |err| {
        if (failure) |retained| return .{ .failed = retained };
        var pending_cleanup = false;
        for (output_slots) |maybe_slot| if (maybe_slot) |slot| { if (!slot.retire()) pending_cleanup = true; };
        if (pending_cleanup) return error.NativeChildOutputRetirementPending;
        return err;
    };
    return .{ .spawned = spawned };
}
fn spawnPreparedAttempt(gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: transport.Options, prepared: *Prepared) !Attempt {
    if (prepared.consumed) return error.NativePreparedStdioOwnershipMoved;
    defer if (!prepared.consumed) prepared.retire();
    const output_slots = prepared.output_slots;
    var failure: ?Failed = null;
    const spawned = spawnOwned(gpa, argv, cwd, env, options, output_slots, &failure, prepared) catch |err| {
        if (failure) |retained| return .{ .failed = retained };
        if (prepared.consumed) {
            var pending_cleanup = false;
            for (output_slots) |maybe_slot| if (maybe_slot) |slot| { if (!slot.retire()) pending_cleanup = true; };
            if (pending_cleanup) return error.NativeChildOutputRetirementPending;
        }
        return err;
    };
    return .{ .spawned = spawned };
}
pub fn spawn(gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: transport.Options) !Spawned {
    const output_slots = try output_pipe.reserveSet(.{ options.windows_overlapped_output and options.stdio[1] == .pipe, options.windows_overlapped_output and options.stdio[2] == .pipe });
    return spawnOwned(gpa, argv, cwd, env, options, output_slots, null, null) catch |err| {
        var pending_cleanup = false;
        for (output_slots) |maybe_slot| if (maybe_slot) |slot| {
            if (!slot.retire()) pending_cleanup = true;
        };
        if (pending_cleanup) return error.NativeChildOutputRetirementPending;
        return err;
    };
}
fn spawnOwned(gpa: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8, env: *const @import("native_child_process_environment.zig").Environment, options: transport.Options, output_slots: [2]?*output_pipe.Slot, retained_failure: ?*?Failed, prepared: ?*Prepared) !Spawned {
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(gpa);
    for (argv, 0..) |value, index| { if (index != 0) try line.append(gpa, ' '); try quote(gpa, &line, value, options.windows_verbatim_arguments); }
    const command_line = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, line.items);
    defer gpa.free(command_line);
    const executable = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, options.executable orelse argv[0]);
    defer gpa.free(executable);
    const directory = if (cwd) |path| try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path) else null;
    defer if (directory) |path| gpa.free(path);
    var environment: std.ArrayList(u8) = .empty;
    defer environment.deinit(gpa);
    for (env.pairs.items) |pair| { try environment.appendSlice(gpa, pair); try environment.append(gpa, 0); }
    if (environment.items.len == 0) try environment.append(gpa, 0);
    const environment_wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, environment.items);
    defer gpa.free(environment_wide);
    var attributes: w.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = null, .bInheritHandle = .TRUE };
    var endpoints: [3]Endpoint = undefined;
    var initialized: usize = 0;
    var transferred = false;
    defer for (endpoints[0..initialized]) |item| {
        closeChild(item);
        if (!transferred) {
            if (item.parent) |handle| w.CloseHandle(handle);
            if (item.input_slot) |slot| _ = slot.retire();
        }
    };
    if (prepared) |source| { endpoints = try source.take(options.stdio, options.windows_stdio); initialized = 3; }
    else for (&endpoints, options.stdio, 0..) |*slot, mode, index| { slot.* = try endpoint(mode, index == 0, &attributes, if (index == 0) null else output_slots[index - 1], options.windows_stdio[index]); initialized += 1; }
    var required: usize = 0;
    _ = Native.InitializeProcThreadAttributeList(null, 1, 0, &required);
    if (required == 0) return error.NativeChildHandleListFailed;
    const attribute_words = try gpa.alloc(usize, std.math.divCeil(usize, required, @sizeOf(usize)) catch return error.NativeChildHandleListFailed);
    defer gpa.free(attribute_words);
    const attributes_list: *anyopaque = @ptrCast(attribute_words.ptr);
    if (Native.InitializeProcThreadAttributeList(attributes_list, 1, 0, &required) == 0) return error.NativeChildHandleListFailed;
    defer Native.DeleteProcThreadAttributeList(attributes_list);
    // Only these three child endpoints are inheritable by this new process.
    // Concurrent children must never inherit one another's pipe handles.
    var inherited = [_]w.HANDLE{ endpoints[0].child, endpoints[1].child, endpoints[2].child };
    if (Native.UpdateProcThreadAttribute(attributes_list, 0, 0x00020002, &inherited, @sizeOf(@TypeOf(inherited)), null, null) == 0) return error.NativeChildHandleListFailed;
    var startup: StartupInfoEx = .{ .info = std.mem.zeroes(w.STARTUPINFOW), .attributes = attributes_list };
    startup.info.cb = @sizeOf(StartupInfoEx);
    startup.info.dwFlags = w.STARTF_USESTDHANDLES | (if (options.windows_hide) w.STARTF_USESHOWWINDOW else @as(u32, 0));
    startup.info.wShowWindow = 0;
    startup.info.hStdInput = endpoints[0].child; startup.info.hStdOutput = endpoints[1].child; startup.info.hStdError = endpoints[2].child;
    var crt = inherited_stdio.CrtStartup.init(inherited, .{ endpoints[0].crt_flags, endpoints[1].crt_flags, endpoints[2].crt_flags });
    startup.info.cbReserved2 = @intCast(crt.bytes.len); startup.info.lpReserved2 = &crt.bytes[0];
    var information: w.PROCESS.INFORMATION = undefined;
    const flags = creationFlags(options);
    if (w.kernel32.CreateProcessW(executable, command_line, null, null, .TRUE, flags, environment_wide, if (directory) |path| path.ptr else null, &startup.info, &information) == .FALSE) {
        const failure = switch (w.GetLastError()) { .FILE_NOT_FOUND, .PATH_NOT_FOUND, .DIRECTORY => error.FileNotFound, .ACCESS_DENIED => error.AccessDenied, .BAD_EXE_FORMAT => error.InvalidExe, else => error.NativeChildSpawnFailed };
        if (retained_failure) |capture| {
            capture.* = .{ .failure = failure, .input_slot = endpoints[0].input_slot, .output_slots = output_slots };
            transferred = true;
        }
        return failure;
    }
    transferred = true;
    return .{ .input_slot = endpoints[0].input_slot, .output_slots = output_slots, .child = .{ .id = information.hProcess, .thread_handle = information.hThread, .stdin = null, .stdout = if (endpoints[1].parent) |handle| .{ .handle = handle, .flags = .{ .nonblocking = false } } else null, .stderr = if (endpoints[2].parent) |handle| .{ .handle = handle, .flags = .{ .nonblocking = false } } else null, .request_resource_usage_statistics = false } };
}

test "windowsHide preserves inherited descriptor console creation semantics" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
    const hidden: transport.Options = .{ .windows_hide = true };
    try std.testing.expect(creationFlags(hidden).create_no_window);
    for (0..3) |index| {
        var options = hidden;
        options.stdio[index] = .inherited;
        try std.testing.expect(!creationFlags(options).create_no_window);
        options.detached = true;
        const flags = creationFlags(options);
        try std.testing.expect(!flags.create_no_window and flags.detached_process and flags.create_new_process_group);
    }
    try std.testing.expect(!creationFlags(.{}).create_no_window);
}
