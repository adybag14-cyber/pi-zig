//! Zig owns terminal requests, input order, raw output, the retained child and
//! session-local registry. The C ABI performs only POSIX terminal syscalls.
const std = @import("std");
const builtin = @import("builtin");
const requests = @import("terminal_request.zig");
const transport = @import("daemon_input.zig");
const Output = @import("daemon_output.zig").Output;
const Io = std.Io;
const gpa = std.heap.page_allocator;
extern "c" fn pi_env_pty_spawn(program: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, env: [*:null]const ?[*:0]const u8, cwd: [*:0]const u8, cols: u16, rows: u16, master: *c_int, pid: *c_int) c_int;
extern "c" fn pi_env_pty_resize(master: c_int, cols: u16, rows: u16) c_int;
extern "c" fn pi_env_pty_read(master: c_int, bytes: [*]u8, length: usize) isize;
extern "c" fn pi_env_pty_write(master: c_int, bytes: [*]const u8, length: usize) isize;
extern "c" fn pi_env_pty_peek(pid: c_int, code: *i64) c_int;
extern "c" fn pi_env_pty_foreground(master: c_int) c_int;
extern "c" fn pi_env_pty_process_name(pid: c_int, bytes: [*]u8, length: usize) c_int;
extern "c" fn pi_env_pty_kill(pid: c_int) c_int;
extern "c" fn pi_env_pty_reap(pid: c_int) c_int;
extern "c" fn pi_env_pty_close(master: c_int) void;
extern "c" fn pi_env_pty_error(code: c_int, bytes: [*]u8, capacity: usize) c_int;
extern "c" fn pi_env_pty_error_code(code: c_int) [*:0]const u8;
fn failure(output: *Output, id: u32, code: []const u8, message: []const u8) !void {
    try output.send(.remote_error, id, .{ .code = code, .message = message }, "");
}
fn systemFailure(output: *Output, id: u32, code: []const u8, system: c_int, syscall: ?[]const u8) !void {
    var buffer: [1024]u8 = undefined;
    const length = pi_env_pty_error(system, &buffer, buffer.len);
    const message = if (length >= 0) buffer[0..@min(@as(usize, @intCast(length)), buffer.len - 1)] else "Terminal system call failed";
    if (syscall) |operation| {
        const actual_code = std.mem.span(pi_env_pty_error_code(system));
        const known = .{
            .{ "EACCES", "permission denied" },                  .{ "EAGAIN", "resource temporarily unavailable" }, .{ "EBADF", "bad file descriptor" },
            .{ "EBUSY", "resource busy or locked" },             .{ "EEXIST", "file already exists" },              .{ "EFBIG", "file too large" },
            .{ "EINVAL", "invalid argument" },                   .{ "EIO", "i/o error" },                           .{ "EISDIR", "illegal operation on a directory" },
            .{ "ELOOP", "too many symbolic links encountered" }, .{ "EMFILE", "too many open files" },              .{ "EMLINK", "too many links" },
            .{ "ENAMETOOLONG", "name too long" },                .{ "ENFILE", "file table overflow" },              .{ "ENOENT", "no such file or directory" },
            .{ "ENOMEM", "not enough memory" },                  .{ "ENOSPC", "no space left on device" },          .{ "ENOSYS", "function not implemented" },
            .{ "ENOTDIR", "not a directory" },                   .{ "ENOTEMPTY", "directory not empty" },           .{ "ENOTSUP", "operation not supported on socket" },
            .{ "EPERM", "operation not permitted" },             .{ "EROFS", "read-only file system" },             .{ "ETXTBSY", "text file is busy" },
            .{ "EXDEV", "cross-device link not permitted" },
        };
        const os_description = message[0 .. std.mem.indexOf(u8, message, " (os error") orelse message.len];
        const lowercase = try std.ascii.allocLowerString(gpa, os_description);
        defer gpa.free(lowercase);
        var description: []const u8 = lowercase;
        inline for (known) |row| if (std.mem.eql(u8, actual_code, row[0])) {
            description = row[1];
        };
        const detail = try std.fmt.allocPrint(gpa, "{s}: {s}, {s} 'pty'", .{ actual_code, description, operation });
        defer gpa.free(detail);
        try output.send(.remote_error, id, .{ .code = actual_code, .message = detail, .syscall = operation, .path = "pty" }, "");
    } else try failure(output, id, code, message);
}
pub const Registry = struct {
    io: Io,
    mutex: Io.Mutex = .init,
    live: std.AutoHashMapUnmanaged(u32, *Task) = .empty,
    pub fn deinit(self: *Registry) void {
        std.debug.assert(self.live.count() == 0);
        self.live.deinit(gpa);
    }
    /// Called directly by the frame owner, preserving control arrival order.
    pub fn respond(self: *Registry, pending: *transport.Pending, output: *Output) !bool {
        if (builtin.os.tag == .windows) return false;
        const json = pending.frame.json.value;
        if (json != .object) return false;
        const op = json.object.get("op") orelse return false;
        if (op != .string) return false;
        const write = std.mem.eql(u8, op.string, "ptyWrite");
        const resize = std.mem.eql(u8, op.string, "ptyResize");
        if (!write and !resize and !std.mem.eql(u8, op.string, "ptyForeground")) return false;
        const id = pending.frame.id;
        const target = requests.target(json) orelse {
            try failure(output, id, "EINVAL", "missing field target");
            return true;
        };
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const task = self.live.get(target) orelse {
            try failure(output, id, "EBADF", "no running terminal with this id");
            return true;
        };
        if (write) {
            const bytes = try gpa.dupe(u8, pending.frame.payload);
            var transferred = false;
            defer if (!transferred) gpa.free(bytes);
            task.queue_mutex.lockUncancelable(self.io);
            defer task.queue_mutex.unlock(self.io);
            if (task.writer_ended) {
                try failure(output, id, "EBADF", "the terminal has ended");
                return true;
            }
            try task.queue.append(gpa, bytes);
            transferred = true;
            task.wake.set(self.io);
        } else if (resize) {
            const cols = requests.size(json, "cols") orelse {
                try failure(output, id, "EINVAL", "cols must be between 1 and 4096");
                return true;
            };
            const rows = requests.size(json, "rows") orelse {
                try failure(output, id, "EINVAL", "rows must be between 1 and 4096");
                return true;
            };
            const result = pi_env_pty_resize(task.master, cols, rows);
            if (result < 0) {
                try systemFailure(output, id, "UNKNOWN", -result, "ioctl");
                return true;
            }
        } else {
            const group = pi_env_pty_foreground(task.master);
            if (group < 0) {
                try systemFailure(output, id, "UNKNOWN", -group, "tcgetpgrp");
            } else if (group == 0 or group == task.pid) {
                try output.send(.result, id, .{ .foreground = @as(std.json.Value, .null) }, "");
            } else {
                const name = try processName(self.io, group);
                defer if (name) |bytes| gpa.free(bytes);
                try output.send(.result, id, .{ .foreground = .{ .pid = group, .name = if (name) |bytes| std.json.Value{ .string = bytes } else @as(std.json.Value, .null) } }, "");
            }
            return true;
        }
        try output.send(.result, id, std.json.Value{ .object = .empty }, "");
        return true;
    }
};
fn processName(io: Io, pid: c_int) !?[]u8 {
    if (builtin.os.tag == .linux) {
        const path = try std.fmt.allocPrint(gpa, "/proc/{d}/comm", .{pid});
        defer gpa.free(path);
        const file = Io.Dir.cwd().openFile(io, path, .{}) catch return null;
        defer file.close(io);
        // procfs reports size zero. A sized reader would incorrectly return an
        // empty name; consume its actual streaming bytes instead.
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(gpa);
        var buffer: [128]u8 = undefined;
        while (true) {
            var vectors = [_][]u8{&buffer};
            const count = file.readStreaming(io, &vectors) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return null,
            };
            if (count == 0) break;
            if (bytes.items.len + count > 4096) return null;
            try bytes.appendSlice(gpa, buffer[0..count]);
        }
        if (!std.unicode.utf8ValidateSlice(bytes.items)) return null;
        const trimmed = trimUnicodeEnd(bytes.items);
        return if (trimmed.len == 0) null else try gpa.dupe(u8, trimmed);
    }
    if (builtin.os.tag == .macos) {
        var buffer: [256]u8 = undefined;
        const count = pi_env_pty_process_name(pid, &buffer, buffer.len);
        return if (count <= 0) null else try gpa.dupe(u8, buffer[0..@min(@as(usize, @intCast(count)), buffer.len)]);
    }
    return null;
}
fn trimUnicodeEnd(bytes: []const u8) []const u8 {
    var end = bytes.len;
    while (end != 0) {
        var start = end - 1;
        while (start != 0 and bytes[start] & 0xc0 == 0x80) start -= 1;
        const scalar = std.unicode.utf8Decode(bytes[start..end]) catch unreachable;
        switch (scalar) {
            0x09...0x0d, 0x20, 0x85, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000 => end = start,
            else => break,
        }
    }
    return bytes[0..end];
}
pub const Task = struct {
    input: *transport.Input,
    output: *Output,
    pending: *transport.Pending,
    registry: *Registry,
    environ: *const std.process.Environ.Map,
    master: c_int = -1,
    pid: c_int = -1,
    queue_mutex: Io.Mutex = .init,
    queue: std.ArrayList([]u8) = .empty,
    wake: Io.Event = .unset,
    stopped: std.atomic.Value(bool) = .init(false),
    writer_ended: bool = false,
    pub fn run(self: *Task) void {
        defer {
            self.input.complete(self.pending);
            gpa.destroy(self);
        }
        self.execute() catch |err| failure(self.output, self.pending.frame.id, "spawn_error", @errorName(err)) catch {};
    }
    fn writer(self: *Task) anyerror!void {
        const io = self.input.io;
        defer {
            self.queue_mutex.lockUncancelable(io);
            self.writer_ended = true;
            self.queue_mutex.unlock(io);
        }
        while (!self.stopped.load(.acquire)) {
            self.wake.reset();
            self.queue_mutex.lockUncancelable(io);
            const bytes = if (self.queue.items.len == 0) null else self.queue.orderedRemove(0);
            self.queue_mutex.unlock(io);
            if (bytes) |chunk| {
                defer gpa.free(chunk);
                var offset: usize = 0;
                while (offset < chunk.len and !self.stopped.load(.acquire)) {
                    const count = pi_env_pty_write(self.master, chunk[offset..].ptr, chunk.len - offset);
                    if (count == 0 or count < -1) return;
                    if (count > 0) offset += @intCast(count) else try io.sleep(.fromMilliseconds(1), .awake);
                }
            } else try self.wake.wait(io);
        }
    }
    fn execute(self: *Task) !void {
        const request = switch (requests.parse(self.pending.frame.json.value)) {
            .request => |value| value,
            .failure => |value| return failure(self.output, self.pending.frame.id, value.code, value.message),
        };
        const io = self.input.io;
        if (self.pending.aborted.load(.acquire)) return failure(self.output, self.pending.frame.id, "aborted", "aborted");
        Io.Dir.cwd().access(io, request.cwd, .{}) catch {
            const message = try std.fmt.allocPrint(gpa, "Working directory does not exist: {s}", .{request.cwd});
            defer gpa.free(message);
            return failure(self.output, self.pending.frame.id, "spawn_error", message);
        };
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var environment: std.process.Environ.Map = .init(gpa);
        defer environment.deinit();
        if (request.inherit_env) for (self.environ.keys(), self.environ.values()) |key, value| try environment.put(key, value);
        if (request.env) |env| {
            var entries = env.iterator();
            while (entries.next()) |entry| if (entry.value_ptr.* == .string) try environment.put(entry.key_ptr.*, entry.value_ptr.string);
        }
        var argv: std.ArrayList(?[*:0]const u8) = .empty;
        if (request.argv) |arguments| {
            for (arguments.items) |argument| {
                if (std.mem.indexOfScalar(u8, argument.string, 0) != null) return error.TerminalArgumentContainsNul;
                try argv.append(a, try a.dupeZ(u8, argument.string));
            }
        } else {
            const candidate: ?[]const u8 = if (request.env) |env| if (env.get("SHELL")) |value| if (value == .string) value.string else null else null else null;
            var shell = candidate orelse self.environ.get("SHELL") orelse "/bin/sh";
            Io.Dir.cwd().access(io, shell, .{}) catch {
                shell = "/bin/sh";
            };
            try argv.append(a, try std.fmt.allocPrintSentinel(a, "-{s}", .{std.fs.path.basename(shell)}, 0));
            const program = try a.dupeZ(u8, shell);
            return self.spawnAndRun(request, program, &argv, &environment, a);
        }
        const first = std.mem.span(argv.items[0].?);
        const program = @import("../durable/startup.zig").resolveProgram(a, io, first, request.cwd, &environment) catch |err| {
            if (err == error.ProgramNotFound) return systemFailure(self.output, self.pending.frame.id, "spawn_error", 2, null);
            return err;
        };
        return self.spawnAndRun(request, try a.dupeZ(u8, program), &argv, &environment, a);
    }
    fn spawnAndRun(self: *Task, request: requests.Request, program: [:0]const u8, argv: *std.ArrayList(?[*:0]const u8), environment: *const std.process.Environ.Map, a: std.mem.Allocator) !void {
        const io = self.input.io;
        try argv.append(a, null);
        var env: std.ArrayList(?[*:0]const u8) = .empty;
        for (environment.keys(), environment.values()) |key, value| {
            if (std.mem.indexOfScalar(u8, key, 0) != null or std.mem.indexOfScalar(u8, key, '=') != null or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidTerminalEnvironment;
            try env.append(a, try std.fmt.allocPrintSentinel(a, "{s}={s}", .{ key, value }, 0));
        }
        try env.append(a, null);
        if (std.mem.indexOfScalar(u8, request.cwd, 0) != null) return error.TerminalCwdContainsNul;
        const result = pi_env_pty_spawn(program, @ptrCast(argv.items.ptr), @ptrCast(env.items.ptr), try a.dupeZ(u8, request.cwd), request.cols, request.rows, &self.master, &self.pid);
        if (result < 0) return systemFailure(self.output, self.pending.frame.id, "spawn_error", -result, null);
        var cleanup_kill = true;
        defer {
            // Still unreaped: neither root PID nor its process group can alias
            // a newly created process when cancellation or cleanup runs.
            if (cleanup_kill) _ = pi_env_pty_kill(self.pid);
            pi_env_pty_close(self.master);
            _ = pi_env_pty_reap(self.pid);
        }
        self.registry.mutex.lockUncancelable(io);
        self.registry.live.putNoClobber(gpa, self.pending.frame.id, self) catch |err| {
            self.registry.mutex.unlock(io);
            return err;
        };
        self.registry.mutex.unlock(io);
        var registered = true;
        defer {
            if (registered) {
                self.registry.mutex.lockUncancelable(io);
                _ = self.registry.live.remove(self.pending.frame.id);
                self.registry.mutex.unlock(io);
            }
        }
        var writer_task = try io.concurrent(writer, .{self});
        defer {
            self.stopped.store(true, .release);
            self.wake.set(io);
            _ = writer_task.cancel(io) catch {};
            for (self.queue.items) |bytes| gpa.free(bytes);
            self.queue.deinit(gpa);
        }
        try self.output.send(.event, self.pending.frame.id, .{ .kind = "started", .pid = self.pid }, "");
        var code: i64 = 0;
        var exited = false;
        var ended = false;
        var idle_until: ?i128 = null;
        var killed = false;
        var buffer: [64 * 1024]u8 = undefined;
        while (!exited or !ended) {
            if (!killed and (self.pending.aborted.load(.acquire) or self.pending.killed.load(.acquire))) {
                _ = pi_env_pty_kill(self.pid);
                killed = true;
            }
            const now = Io.Clock.awake.now(io).nanoseconds;
            const state = pi_env_pty_peek(self.pid, &code);
            if (state < 0) return systemFailure(self.output, self.pending.frame.id, "spawn_error", -state, null);
            if (state == 1 and !exited) {
                exited = true;
                idle_until = now + 100 * std.time.ns_per_ms;
            }
            const count = pi_env_pty_read(self.master, &buffer, buffer.len);
            if (count == 0 or count < -1) ended = true;
            if (count > 0) {
                try self.output.waitForRoom(&self.pending.aborted, &self.pending.killed);
                try self.output.sendBulk(.event, self.pending.frame.id, .{ .kind = "output" }, buffer[0..@intCast(count)]);
                if (exited) idle_until = Io.Clock.awake.now(io).nanoseconds + 100 * std.time.ns_per_ms;
            } else if (idle_until != null and now >= idle_until.?) break;
            // Drain ready PTY bytes like Source's blocking reader. Sleeping
            // after every successful read throttles small macOS PTY chunks
            // and can stall a large write behind output backpressure.
            if (count <= 0 and (!exited or !ended)) try io.sleep(.fromMilliseconds(1), .awake);
        }
        // A reply can reach the client as soon as it is queued. Retire the
        // terminal before publishing its outcome, as upstream does.
        self.registry.mutex.lockUncancelable(io);
        _ = self.registry.live.remove(self.pending.frame.id);
        registered = false;
        self.registry.mutex.unlock(io);
        // A normally exited program may have background descendants. Closing
        // the master supplies terminal hangup; do not add a group kill.
        if (exited) cleanup_kill = false;
        if (self.pending.aborted.load(.acquire)) {
            try self.output.sendBulk(.remote_error, self.pending.frame.id, .{ .code = "aborted", .message = "aborted" }, "");
        } else try self.output.sendBulk(.result, self.pending.frame.id, .{ .exitCode = code }, "");
    }
};
