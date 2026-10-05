//! Owned native Windows pseudoconsole fixture, never a desktop console.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const w = std.os.windows;
const H = w.HANDLE;
const B = w.BOOL;
const Coord = extern struct { x: i16, y: i16 };
const Startup = extern struct { info: w.STARTUPINFOW, attributes: ?*anyopaque };
const FileTime = extern struct { low: u32, high: u32 };
const BasicLimits = extern struct { process_time: i64, job_time: i64, flags: u32, minimum_working_set: usize, maximum_working_set: usize, active_processes: u32, affinity: usize, priority: u32, scheduling: u32 };
const Counters = extern struct { read_ops: u64, write_ops: u64, other_ops: u64, read_bytes: u64, write_bytes: u64, other_bytes: u64 };
const Limits = extern struct { basic: BasicLimits, counters: Counters, process_memory: usize, job_memory: usize, peak_process_memory: usize, peak_job_memory: usize };
extern "kernel32" fn CreatePipe(*H, *H, ?*w.SECURITY_ATTRIBUTES, u32) callconv(.winapi) B;
extern "kernel32" fn CreatePseudoConsole(Coord, H, H, u32, *H) callconv(.winapi) i32;
extern "kernel32" fn ResizePseudoConsole(H, Coord) callconv(.winapi) i32;
extern "kernel32" fn ClosePseudoConsole(H) callconv(.winapi) void;
extern "kernel32" fn InitializeProcThreadAttributeList(?*anyopaque, u32, u32, *usize) callconv(.winapi) B;
extern "kernel32" fn UpdateProcThreadAttribute(*anyopaque, u32, usize, *anyopaque, usize, ?*anyopaque, ?*usize) callconv(.winapi) B;
extern "kernel32" fn DeleteProcThreadAttributeList(*anyopaque) callconv(.winapi) void;
extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, B, u32) callconv(.winapi) B;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
extern "kernel32" fn GetProcessId(H) callconv(.winapi) u32;
extern "kernel32" fn GetProcessTimes(H, *FileTime, *FileTime, *FileTime, *FileTime) callconv(.winapi) B;
extern "kernel32" fn CreateJobObjectW(?*w.SECURITY_ATTRIBUTES, ?[*:0]const u16) callconv(.winapi) ?H;
extern "kernel32" fn SetInformationJobObject(H, u32, *const anyopaque, u32) callconv(.winapi) B;
extern "kernel32" fn AssignProcessToJobObject(H, H) callconv(.winapi) B;
extern "kernel32" fn TerminateJobObject(H, u32) callconv(.winapi) B;
extern "kernel32" fn TerminateProcess(H, u32) callconv(.winapi) B;
extern "kernel32" fn ResumeThread(H) callconv(.winapi) u32;
extern "kernel32" fn WaitForSingleObject(H, u32) callconv(.winapi) u32;
extern "kernel32" fn GetExitCodeProcess(H, *u32) callconv(.winapi) B;
extern "kernel32" fn ReadFile(H, *anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) B;
extern "kernel32" fn WriteFile(H, *const anyopaque, u32, *u32, ?*anyopaque) callconv(.winapi) B;
extern "kernel32" fn CancelSynchronousIo(H) callconv(.winapi) B;

const Capture = struct {
    gpa: std.mem.Allocator,
    handle: H,
    io: Io,
    mutex: Io.Mutex = .init,
    pending: std.ArrayList(u8) = .empty,
    received: usize = 0,
    eof: bool = false,
    failure: ?anyerror = null,
    thread: ?std.Thread = null,
    fn run(self: *Capture) void {
        var buffer: [65536]u8 = undefined;
        while (true) {
            var count: u32 = 0;
            const read = ReadFile(self.handle, &buffer, buffer.len, &count, null).toBool();
            const cause = if (!read) w.GetLastError() else .SUCCESS;
            if (!read or count == 0) {
                self.mutex.lockUncancelable(self.io);
                if (!read and cause != .BROKEN_PIPE and cause != .OPERATION_ABORTED and self.failure == null) self.failure = error.ConPtyReadFailed;
                self.eof = true;
                self.mutex.unlock(self.io);
                return;
            }
            self.mutex.lockUncancelable(self.io);
            if (self.failure == null) {
                if (count > 8 * 1024 * 1024 - self.received) self.failure = error.ConPtyOutputLimit else {
                    self.pending.appendSlice(self.gpa, buffer[0..count]) catch |err| {
                        self.failure = err;
                    };
                    self.received += count;
                }
            }
            self.mutex.unlock(self.io);
            // Continue draining after allocation/limit failure so owned console
            // teardown cannot block on a full output pipe.
        }
    }
};

fn appendArgument(gpa: std.mem.Allocator, command: *std.ArrayList(u8), argument: []const u8) !void {
    if (command.items.len > 0) try command.append(gpa, ' ');
    try command.append(gpa, '"');
    var slashes: usize = 0;
    for (argument) |byte| {
        if (byte == '\\') {
            slashes += 1;
            continue;
        }
        try command.appendNTimes(gpa, '\\', if (byte == '"') slashes * 2 + 1 else slashes);
        slashes = 0;
        try command.append(gpa, byte);
    }
    try command.appendNTimes(gpa, '\\', slashes * 2);
    try command.append(gpa, '"');
}

pub const Session = struct {
    gpa: std.mem.Allocator,
    io: Io,
    input: ?H,
    output_pipe: H,
    console: ?H,
    job: H,
    child: std.process.Child,
    pid: u32,
    created: FileTime,
    capture: *Capture,
    output: std.ArrayList(u8) = .empty,
    eof: bool = false,
    term: ?std.process.Child.Term = null,
    native_exit_code: ?u32 = null,
    operation_deadline_ms: i64,

    pub fn spawn(gpa: std.mem.Allocator, io: Io, launcher: []const u8, options: std.process.SpawnOptions, timeout_ms: u32) !Session {
        if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
        if (options.argv.len == 0 or options.stderr != .file) return error.InvalidConPtyOptions;
        var input_read: H = undefined;
        var input_write: H = undefined;
        if (!CreatePipe(&input_read, &input_write, null, 65536).toBool()) return error.ConPtyPipeFailed;
        defer w.CloseHandle(input_read);
        errdefer w.CloseHandle(input_write);
        var output_read: H = undefined;
        var output_write: H = undefined;
        if (!CreatePipe(&output_read, &output_write, null, 65536).toBool()) return error.ConPtyPipeFailed;
        defer w.CloseHandle(output_write);
        errdefer w.CloseHandle(output_read);
        var console: H = undefined;
        if (CreatePseudoConsole(.{ .x = 100, .y = 40 }, input_read, output_write, 0, &console) < 0) return error.ConPtyCreateFailed;
        errdefer ClosePseudoConsole(console);
        const job = CreateJobObjectW(null, null) orelse return error.ConPtyJobFailed;
        errdefer w.CloseHandle(job);
        var limits = std.mem.zeroes(Limits);
        limits.basic.flags = 0x2000; // KILL_ON_JOB_CLOSE, only this owned subtree.
        if (!SetInformationJobObject(job, 9, &limits, @sizeOf(Limits)).toBool()) return error.ConPtyJobFailed;
        var stderr_handle: H = undefined;
        const current = GetCurrentProcess();
        if (!DuplicateHandle(current, options.stderr.file.handle, current, &stderr_handle, 0, .TRUE, 2).toBool()) return error.ConPtyStderrDuplicateFailed;
        defer w.CloseHandle(stderr_handle);
        var size: usize = 0;
        _ = InitializeProcThreadAttributeList(null, 2, 0, &size);
        if (size == 0) return error.ConPtyAttributesFailed;
        const attributes = try gpa.alloc(usize, (size + @sizeOf(usize) - 1) / @sizeOf(usize));
        defer gpa.free(attributes);
        const attribute_pointer: *anyopaque = @ptrCast(attributes.ptr);
        if (!InitializeProcThreadAttributeList(attribute_pointer, 2, 0, &size).toBool()) return error.ConPtyAttributesFailed;
        defer DeleteProcThreadAttributeList(attribute_pointer);
        if (!UpdateProcThreadAttribute(attribute_pointer, 0, 0x00020016, console, @sizeOf(H), null, null).toBool()) return error.ConPtyAttributesFailed;
        var inherited = [_]H{stderr_handle};
        if (!UpdateProcThreadAttribute(attribute_pointer, 0, 0x00020002, &inherited, @sizeOf(@TypeOf(inherited)), null, null).toBool()) return error.ConPtyAttributesFailed;
        var command: std.ArrayList(u8) = .empty;
        defer command.deinit(gpa);
        try appendArgument(gpa, &command, launcher);
        const descriptor = try std.fmt.allocPrint(gpa, "{d}", .{@intFromPtr(stderr_handle)});
        defer gpa.free(descriptor);
        const duration = try std.fmt.allocPrint(gpa, "{d}", .{timeout_ms});
        defer gpa.free(duration);
        try appendArgument(gpa, &command, descriptor);
        try appendArgument(gpa, &command, duration);
        for (options.argv) |argument| try appendArgument(gpa, &command, argument);
        const command_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, command.items);
        defer gpa.free(command_w);
        const launcher_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, launcher);
        defer gpa.free(launcher_w);
        const cwd_w = if (options.cwd == .path) try std.unicode.wtf8ToWtf16LeAllocZ(gpa, options.cwd.path) else null;
        defer if (cwd_w) |path| gpa.free(path);
        const environment = if (options.environ_map) |map| try map.createWindowsBlock(gpa, .{}) else null;
        defer if (environment) |block| block.deinit(gpa);
        var startup = std.mem.zeroes(Startup);
        startup.info.cb = @sizeOf(Startup);
        startup.attributes = attribute_pointer;
        var process: w.PROCESS.INFORMATION = undefined;
        if (!w.kernel32.CreateProcessW(launcher_w.ptr, command_w.ptr, null, null, .TRUE, .{ .create_suspended = true, .create_unicode_environment = true, .extended_startupinfo_present = true }, if (environment) |block| block.slice.ptr else null, if (cwd_w) |path| path.ptr else null, &startup.info, &process).toBool()) return error.ConPtySpawnFailed;
        var child: std.process.Child = .{ .id = process.hProcess, .thread_handle = process.hThread, .stdin = null, .stdout = null, .stderr = null, .request_resource_usage_statistics = false };
        errdefer cleanupChild(io, &child, job);
        if (!AssignProcessToJobObject(job, process.hProcess).toBool()) return error.ConPtyJobAssignFailed;
        var created: FileTime = undefined;
        var exited_time: FileTime = undefined;
        var kernel_time: FileTime = undefined;
        var user_time: FileTime = undefined;
        if (!GetProcessTimes(process.hProcess, &created, &exited_time, &kernel_time, &user_time).toBool()) return error.ConPtyIdentityFailed;
        const capture = try gpa.create(Capture);
        errdefer gpa.destroy(capture);
        capture.* = .{ .gpa = gpa, .io = io, .handle = output_read };
        capture.thread = try std.Thread.spawn(.{}, Capture.run, .{capture});
        errdefer {
            _ = TerminateJobObject(job, 129);
            if (capture.thread) |thread| {
                _ = CancelSynchronousIo(thread.getHandle());
                thread.join();
            }
            capture.pending.deinit(gpa);
        }
        // Start draining before the child can fill the pseudoconsole pipe.
        if (ResumeThread(process.hThread) == 0xffffffff) return error.ConPtyResumeFailed;
        return .{ .gpa = gpa, .io = io, .input = input_write, .output_pipe = output_read, .console = console, .job = job, .child = child, .pid = GetProcessId(process.hProcess), .created = created, .capture = capture, .operation_deadline_ms = now(io) + timeout_ms };
    }
    fn now(io: Io) i64 {
        return Io.Clock.awake.now(io).toMilliseconds();
    }
    fn cleanupChild(io: Io, child: *std.process.Child, job: H) void {
        const handle = child.id orelse return;
        _ = TerminateJobObject(job, 129);
        // Assignment can itself have failed: the suspended exact child still
        // belongs to this launcher, but is not necessarily inside the job yet.
        _ = TerminateProcess(handle, 129);
        const end = now(io) + 3000;
        while (now(io) < end) {
            switch (WaitForSingleObject(handle, 10)) {
                0 => {
                    _ = child.wait(io) catch {};
                    return;
                },
                258 => {},
                else => break,
            }
        }
        // Never perform an unbounded Child.wait after a failed observation.
        // Closing the private KILL_ON_JOB_CLOSE job still retires its subtree.
        w.CloseHandle(child.thread_handle);
        w.CloseHandle(handle);
        child.id = null;
        child.thread_handle = undefined;
    }
    pub fn drain(self: *Session) !void {
        self.capture.mutex.lockUncancelable(self.io);
        var pending = self.capture.pending;
        self.capture.pending = .empty;
        const failure = self.capture.failure;
        self.eof = self.capture.eof;
        self.capture.mutex.unlock(self.io);
        defer pending.deinit(self.gpa);
        if (failure) |err| return err;
        try self.output.appendSlice(self.gpa, pending.items);
    }
    pub fn send(self: *Session, bytes: []const u8) !void {
        const handle = self.input orelse return error.ConPtyInputClosed;
        if (bytes.len > 8192) return error.ConPtyInputLimit;
        const Write = struct {
            handle: H,
            bytes: []const u8,
            io: Io,
            done: Io.Event = .unset,
            failure: ?anyerror = null,
            fn run(task: *@This()) void {
                defer task.done.set(task.io);
                var offset: usize = 0;
                while (offset < task.bytes.len) {
                    var count: u32 = 0;
                    if (!WriteFile(task.handle, task.bytes[offset..].ptr, @intCast(task.bytes.len - offset), &count, null).toBool() or count == 0) {
                        task.failure = error.ConPtyWriteFailed;
                        return;
                    }
                    offset += count;
                }
            }
        };
        var write: Write = .{ .handle = handle, .bytes = bytes, .io = self.io };
        const thread = try std.Thread.spawn(.{}, Write.run, .{&write});
        const end = @min(self.operation_deadline_ms, now(self.io) + 5000);
        var expired = false;
        while (!write.done.isSet()) {
            const remaining = end - now(self.io);
            if (remaining <= 0) {
                expired = true;
                _ = CancelSynchronousIo(thread.getHandle());
                break;
            }
            write.done.waitTimeout(self.io, .{ .duration = .{ .raw = .fromMilliseconds(remaining), .clock = .awake } }) catch |err| switch (err) {
                error.Timeout => continue,
                else => {
                    _ = CancelSynchronousIo(thread.getHandle());
                    thread.join();
                    return err;
                },
            };
        }
        thread.join();
        if (expired) return error.ConPtyTimeout;
        if (write.failure) |err| return err;
    }
    pub fn resize(self: *Session, columns: u16, rows: u16) !void {
        if (columns == 0 or rows == 0 or columns > 32767 or rows > 32767) return error.InvalidConPtySize;
        if (ResizePseudoConsole(self.console orelse return error.ConPtyClosed, .{ .x = @intCast(columns), .y = @intCast(rows) }) < 0) return error.ConPtyResizeFailed;
    }
    pub fn exited(self: *Session) !bool {
        if (self.term != null) return true;
        return switch (WaitForSingleObject(self.child.id orelse return error.ConPtyAlreadyReaped, 0)) {
            0 => true,
            258 => false,
            else => error.ConPtyWaitFailed,
        };
    }
    pub fn wait(self: *Session, timeout_ms: u32) !std.process.Child.Term {
        const end = @min(self.operation_deadline_ms, now(self.io) + timeout_ms);
        while (!try self.exited()) {
            try self.drain();
            if (now(self.io) >= end) return error.ConPtyTimeout;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        try self.drain();
        if (self.term == null) {
            var code: u32 = undefined;
            if (!GetExitCodeProcess(self.child.id.?, &code).toBool()) return error.ConPtyExitCodeFailed;
            self.native_exit_code = code;
            self.term = try self.child.wait(self.io);
        }
        return self.term.?;
    }
    pub fn waitFor(self: *Session, marker: []const u8, start: usize, timeout_ms: u32) !usize {
        const end = @min(self.operation_deadline_ms, now(self.io) + timeout_ms);
        while (now(self.io) < end) {
            try self.drain();
            if (std.mem.indexOfPos(u8, self.output.items, @min(start, self.output.items.len), marker)) |position| return position + marker.len;
            if (try self.exited()) break;
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
        std.debug.print("ConPTY missing {s}; tail:\n{s}\n", .{ marker, self.output.items[self.output.items.len - @min(self.output.items.len, 8000) ..] });
        return error.ConPtyMarkerMissing;
    }
    pub fn hangup(self: *Session) void {
        if (self.input) |handle| w.CloseHandle(handle);
        self.input = null;
    }
    pub fn deinit(self: *Session) void {
        if (self.term == null) {
            if (!(self.exited() catch false)) _ = TerminateJobObject(self.job, 129);
            const end = now(self.io) + 3000;
            while (!(self.exited() catch true) and now(self.io) < end) self.io.sleep(.fromMilliseconds(10), .awake) catch break;
            if (self.exited() catch false) self.term = self.child.wait(self.io) catch null;
        }
        self.hangup();
        if (self.console) |console| ClosePseudoConsole(console);
        if (self.capture.thread) |thread| {
            _ = CancelSynchronousIo(thread.getHandle());
            thread.join();
        }
        self.capture.pending.deinit(self.gpa);
        self.gpa.destroy(self.capture);
        w.CloseHandle(self.output_pipe);
        w.CloseHandle(self.job);
        self.output.deinit(self.gpa);
    }
};

test "owned Windows ConPTY has real console input output and isolated stderr with exact child cleanup" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const launcher = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_LAUNCHER") orelse "zig-out/bin/pi-conpty-launcher.exe");
    defer gpa.free(launcher);
    const probe = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_PROBE") orelse "zig-out/bin/pi-terminal-probe.exe");
    defer gpa.free(probe);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const errors = try tmp.dir.createFile(io, "stderr.log", .{});
    defer errors.close(io);
    errdefer {
        const bytes = tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536)) catch null;
        if (bytes) |text| {
            defer gpa.free(text);
            std.debug.print("ConPTY child stderr: {s}\n", .{text});
        }
    }
    var child = try Session.spawn(gpa, io, launcher, .{ .argv = &.{probe}, .stderr = .{ .file = errors }, .environ_map = &environment }, 15000);
    defer child.deinit();
    try std.testing.expect(child.pid != 0);
    _ = try child.waitFor("native-conpty-ready", 0, 5000);
    try child.send("native-input Ω\r");
    _ = try child.waitFor("native-input Ω", 0, 5000);
    _ = try child.waitFor("native-conpty-done", 0, 5000);
    const term = try child.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
    const stderr = try tmp.dir.readFileAlloc(io, "stderr.log", gpa, .limited(65536));
    defer gpa.free(stderr);
    try std.testing.expectEqualStrings("native-conpty-stderr\n", stderr);
    try std.testing.expect(std.mem.indexOf(u8, child.output.items, "native-conpty-stderr") == null);
}

test "owned Windows ConPTY timeout terminates only its private child job" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const launcher = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_LAUNCHER") orelse "zig-out/bin/pi-conpty-launcher.exe");
    defer gpa.free(launcher);
    const probe = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_PROBE") orelse "zig-out/bin/pi-terminal-probe.exe");
    defer gpa.free(probe);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const errors = try tmp.dir.createFile(io, "stderr.log", .{});
    defer errors.close(io);
    var sibling = try Session.spawn(gpa, io, launcher, .{ .argv = &.{probe}, .stderr = .{ .file = errors }, .environ_map = &environment }, 15000);
    defer sibling.deinit();
    _ = try sibling.waitFor("native-conpty-ready", 0, 5000);
    var child = try Session.spawn(gpa, io, launcher, .{ .argv = &.{probe}, .stderr = .{ .file = errors }, .environ_map = &environment }, 15000);
    var cleanup = true;
    defer if (cleanup) child.deinit();
    _ = try child.waitFor("native-conpty-ready", 0, 5000);
    var exact_handle: H = undefined;
    if (!DuplicateHandle(GetCurrentProcess(), child.child.id.?, GetCurrentProcess(), &exact_handle, 0, .FALSE, 2).toBool()) return error.ConPtyIdentityFailed;
    defer w.CloseHandle(exact_handle);
    try std.testing.expectError(error.ConPtyTimeout, child.wait(30));
    child.deinit();
    cleanup = false;
    try std.testing.expectEqual(@as(u32, 0), WaitForSingleObject(exact_handle, 0));
    var code: u32 = undefined;
    try std.testing.expect(GetExitCodeProcess(exact_handle, &code).toBool());
    try std.testing.expectEqual(@as(u32, 129), code);
    try std.testing.expect(!try sibling.exited());
    try sibling.send("surviving sibling\r");
    _ = try sibling.waitFor("native-conpty-done", 0, 5000);
    const term = try sibling.wait(5000);
    try std.testing.expect(term == .exited and term.exited == 0);
}

test "owned Windows ConPTY drains after capture allocation failure and reaps its exact child" {
    if (comptime builtin.os.tag != .windows) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environment = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environment.deinit();
    const launcher = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_LAUNCHER") orelse "zig-out/bin/pi-conpty-launcher.exe");
    defer gpa.free(launcher);
    const probe = try @import("pty.zig").executablePath(gpa, io, environment.get("PI_TEST_CONPTY_PROBE") orelse "zig-out/bin/pi-terminal-probe.exe");
    defer gpa.free(probe);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const errors = try tmp.dir.createFile(io, "stderr.log", .{});
    defer errors.close(io);
    var failing = std.testing.FailingAllocator.init(gpa, .{});
    var child = try Session.spawn(failing.allocator(), io, launcher, .{ .argv = &.{probe}, .stderr = .{ .file = errors }, .environ_map = &environment }, 15000);
    var cleanup = true;
    defer if (cleanup) child.deinit();
    _ = try child.waitFor("native-conpty-ready", 0, 5000);
    var exact_handle: H = undefined;
    if (!DuplicateHandle(GetCurrentProcess(), child.child.id.?, GetCurrentProcess(), &exact_handle, 0, .FALSE, 2).toBool()) return error.ConPtyIdentityFailed;
    defer w.CloseHandle(exact_handle);
    // Capture.pending is empty after drain, so the next burst must allocate.
    child.capture.mutex.lockUncancelable(io);
    failing.fail_index = failing.alloc_index;
    child.capture.mutex.unlock(io);
    try child.send("burst\r");
    const end = Session.now(io) + 5000;
    var failed = false;
    while (Session.now(io) < end) {
        child.drain() catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            failed = true;
            break;
        };
        try io.sleep(.fromMilliseconds(10), .awake);
    }
    try std.testing.expect(failed);
    child.deinit();
    cleanup = false;
    try std.testing.expectEqual(@as(u32, 0), WaitForSingleObject(exact_handle, 0));
}
