//! Durable commands: direct argv, per-stream decoding and exact owned cleanup.
const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const decode = @import("decode.zig");
const output = @import("output_window.zig");
const ownership = @import("process_ownership.zig");
const startup = @import("startup.zig");
const temporary = @import("temporary.zig");
const paths = @import("path.zig");
pub const Command = union(enum) { text: []const u8, argv: []const []const u8 };
pub const Stream = enum { stdout, stderr };
pub const OutputInfo = struct { stream: Stream, skipped: ?output.ShellOutputSkip = null };
pub const OutputFn = *const fn (?*anyopaque, []const u8, types.Context, OutputInfo) anyerror!void;
pub const SpillOptions = struct { afterBytes: u64, afterLines: u64 };
pub const Options = struct {
    parent_owner: ?*ownership.ParentJob = null,
    cwd: ?[]const u8 = null,
    env: ?*const std.process.Environ.Map = null,
    inheritEnv: bool = true,
    timeout: ?f64 = null,
    onOutput: ?OutputFn = null,
    output_context: ?*anyopaque = null,
    spill: ?SpillOptions = null,
    window: ?output.ShellOutputWindow = null,
};
pub const ExecutionErrorCode = enum { aborted, timeout, shell_unavailable, spawn_error, callback_error, unknown };
pub const ExecutionError = struct {
    code: ExecutionErrorCode,
    message: []const u8,
    cause: ?anyerror = null,
    spillPath: ?[]u8 = null,
    pub fn deinit(self: *ExecutionError, gpa: std.mem.Allocator) void {
        if (self.spillPath) |path| gpa.free(path);
        self.* = undefined;
    }
};
pub const ExecResult = struct {
    exitCode: i64,
    spillPath: ?[]u8 = null,
    pub fn deinit(self: *ExecResult, gpa: std.mem.Allocator) void {
        if (self.spillPath) |path| gpa.free(path);
        self.* = undefined;
    }
};
pub const Result = union(enum) { value: ExecResult, failure: ExecutionError };
fn failure(code: ExecutionErrorCode, cause: ?anyerror) Result {
    return .{ .failure = .{ .code = code, .message = if (cause) |err| @errorName(err) else @tagName(code), .cause = cause } };
}
fn now(io: std.Io) i64 {
    return std.Io.Clock.awake.now(io).toMilliseconds();
}
pub fn timeoutMilliseconds(seconds: ?f64) !?f64 {
    const value = seconds orelse return null;
    if (!std.math.isFinite(value) or value <= 0 or value * 1000 > 2147483647) return error.InvalidTimeout;
    return value * 1000;
}
const Spill = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    options: SpillOptions,
    seen_bytes: u64 = 0,
    seen_newlines: u64 = 0,
    prefix: std.ArrayList(u8) = .empty,
    opened: ?std.Io.File = null,
    path: ?[]u8 = null,
    fn deinit(self: *Spill) void {
        if (self.opened) |file| file.close(self.io);
        if (self.path) |path| self.gpa.free(path);
        self.prefix.deinit(self.gpa);
    }
    fn push(self: *Spill, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        if (self.opened == null) {
            self.seen_bytes = std.math.add(u64, self.seen_bytes, bytes.len) catch return error.OutputSizeOverflow;
            self.seen_newlines = std.math.add(u64, self.seen_newlines, std.mem.count(u8, bytes, "\n")) catch return error.OutputSizeOverflow;
            const line_count = self.seen_newlines + @as(u64, @intFromBool(bytes[bytes.len - 1] != '\n'));
            if (self.seen_bytes <= self.options.afterBytes and line_count <= self.options.afterLines) {
                try self.prefix.appendSlice(self.gpa, bytes);
                return;
            }
            const created = try temporary.file(self.gpa, self.io, self.root, "pi-output-", ".log");
            self.opened = created.file;
            self.path = created.path;
            try created.file.writeStreamingAll(self.io, self.prefix.items);
            self.prefix.clearAndFree(self.gpa);
        }
        try self.opened.?.writeStreamingAll(self.io, bytes);
    }
};
const Pending = struct {
    gpa: std.mem.Allocator,
    window: output.ShellOutputWindow,
    text: std.ArrayList(u8) = .empty,
    skipped: output.ShellOutputSkip = .{ .bytes = 0, .newlines = 0, .endsWithNewline = false },
    stream: Stream = .stdout,
    gate: output.ProgressGate,
    fn init(gpa: std.mem.Allocator, window: output.ShellOutputWindow) Pending {
        return .{ .gpa = gpa, .window = window, .gate = .{ .minIntervalMs = window.minIntervalMs, .bytesPerSecond = window.bytesPerSecond } };
    }
    fn deinit(self: *Pending) void {
        self.text.deinit(self.gpa);
    }
    fn push(self: *Pending, text: []const u8, stream: Stream) !void {
        if (text.len == 0) return;
        try self.text.appendSlice(self.gpa, text);
        self.stream = stream;
        const start = output.tailMargin(self.text.items, .{ .maxBytes = self.window.maxBytes, .maxLines = self.window.maxLines });
        if (start != 0) {
            const skipped = output.measure(self.text.items[0..start]);
            self.skipped.bytes = std.math.add(u64, self.skipped.bytes, skipped.bytes) catch return error.OutputSizeOverflow;
            self.skipped.newlines = std.math.add(u64, self.skipped.newlines, skipped.newlines) catch return error.OutputSizeOverflow;
            self.skipped.endsWithNewline = skipped.endsWithNewline;
            const tail = self.text.items[start..];
            @memmove(self.text.items[0..tail.len], tail);
            self.text.items.len = tail.len;
        }
        self.gate.mark();
    }
    fn flush(self: *Pending, options: Options, context: types.Context, time: i64, force: bool) !void {
        if (self.text.items.len == 0 or (!force and !self.gate.begin(@floatFromInt(time)))) return;
        if (force) {
            self.gate.in_flight = true;
            self.gate.started_at_ms = @floatFromInt(time);
        }
        if (options.onOutput) |callback| try callback(options.output_context, self.text.items, context, .{ .stream = self.stream, .skipped = if (self.skipped.bytes == 0) null else self.skipped });
        self.gate.complete(self.text.items.len, true);
        self.text.clearRetainingCapacity();
        self.skipped = .{ .bytes = 0, .newlines = 0, .endsWithNewline = false };
    }
};

pub const Shell = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    cwd: []u8,
    temp_dir: []u8,
    shell_path: ?[]u8,
    inherited: std.process.Environ.Map,
    shell_env: ?std.process.Environ.Map,
    active_mutex: std.Io.Mutex = .init,
    active: std.ArrayList(*ownership.Control) = .empty,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, cwd: []const u8, inherited: *const std.process.Environ.Map, shell_env: ?*const std.process.Environ.Map, shell_path: ?[]const u8, temp_dir: []const u8) !Shell {
        const owned_cwd = try paths.absoluteCwd(gpa, io, cwd);
        errdefer gpa.free(owned_cwd);
        const owned_temp = try gpa.dupe(u8, temp_dir);
        errdefer gpa.free(owned_temp);
        const owned_shell = if (shell_path) |path| try gpa.dupe(u8, path) else null;
        errdefer if (owned_shell) |path| gpa.free(path);
        var parent = try inherited.clone(gpa);
        errdefer parent.deinit();
        return .{ .gpa = gpa, .io = io, .cwd = owned_cwd, .temp_dir = owned_temp, .shell_path = owned_shell, .inherited = parent, .shell_env = if (shell_env) |map| try map.clone(gpa) else null };
    }
    pub fn cleanup(self: *Shell, _: types.Context) void {
        self.active_mutex.lockUncancelable(self.io);
        defer self.active_mutex.unlock(self.io);
        for (self.active.items) |control| control.kill();
    }
    /// Call only once outstanding exec calls have settled.
    pub fn deinit(self: *Shell) void {
        self.cleanup(.{});
        std.debug.assert(self.active.items.len == 0);
        self.active.deinit(self.gpa);
        self.inherited.deinit();
        if (self.shell_env) |*map| map.deinit();
        self.gpa.free(self.cwd);
        self.gpa.free(self.temp_dir);
        if (self.shell_path) |path| self.gpa.free(path);
        self.* = undefined;
    }
    fn register(self: *Shell, control: *ownership.Control) !void {
        self.active_mutex.lockUncancelable(self.io);
        defer self.active_mutex.unlock(self.io);
        try self.active.append(self.gpa, control);
    }
    fn unregister(self: *Shell, control: *ownership.Control) void {
        self.active_mutex.lockUncancelable(self.io);
        defer self.active_mutex.unlock(self.io);
        for (self.active.items, 0..) |entry, index| if (entry == control) {
            _ = self.active.swapRemove(index);
            return;
        };
        unreachable;
    }
    fn environment(self: *Shell, options: Options) !std.process.Environ.Map {
        var result = if (options.inheritEnv) try self.inherited.clone(self.gpa) else std.process.Environ.Map.init(self.gpa);
        errdefer result.deinit();
        if (options.inheritEnv) if (self.shell_env) |*map| for (map.array_hash_map.keys(), map.array_hash_map.values()) |key, value| try result.put(key, value);
        if (options.env) |map| for (map.array_hash_map.keys(), map.array_hash_map.values()) |key, value| try result.put(key, value);
        return result;
    }
    pub fn exec(self: *Shell, command: Command, options: Options, context: types.Context) !Result {
        if (context.aborted()) return failure(.aborted, null);
        const timeout_ms = timeoutMilliseconds(options.timeout) catch return failure(.timeout, error.InvalidTimeout);
        const cwd = paths.resolve(self.gpa, self.cwd, options.cwd orelse self.cwd, startup.home(&self.inherited)) catch |err| {
            if (err == error.OutOfMemory) return err;
            return failure(.spawn_error, err);
        };
        defer self.gpa.free(cwd);
        std.Io.Dir.cwd().access(self.io, cwd, .{}) catch |err| return failure(.spawn_error, err);
        var environment_map = try self.environment(options);
        defer environment_map.deinit();
        var config: ?startup.ShellConfig = null;
        defer if (config) |*value| value.deinit(self.gpa);
        var shell_arguments: [3][]const u8 = undefined;
        const argv: []const []const u8 = switch (command) {
            .argv => |arguments| arguments,
            .text => |text| arguments: {
                config = startup.shellConfig(self.gpa, self.io, &self.inherited, self.shell_path) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return failure(.shell_unavailable, err);
                };
                shell_arguments = .{ config.?.program, if (config.?.command_on_stdin) "-s" else "-c", text };
                break :arguments shell_arguments[0..if (config.?.command_on_stdin) @as(usize, 2) else 3];
            },
        };
        if (argv.len == 0) return failure(.spawn_error, error.EmptyArgv);
        // Windows discovers a program through the parent's PATH when the child
        // environment omits PATH. An explicitly empty child PATH remains authoritative.
        const search_environment = if (builtin.os.tag == .windows and environment_map.get("PATH") == null) &self.inherited else &environment_map;
        const program = startup.resolveProgram(self.gpa, self.io, argv[0], cwd, search_environment) catch |err| {
            if (err == error.OutOfMemory) return err;
            return failure(.spawn_error, err);
        };
        defer self.gpa.free(program);
        const resolved_argv = try self.gpa.dupe([]const u8, argv);
        defer self.gpa.free(resolved_argv);
        resolved_argv[0] = program;
        const stdin_command = if (config != null and config.?.command_on_stdin) command.text else null;
        var child = std.process.spawn(self.io, .{ .argv = resolved_argv, .cwd = .{ .path = cwd }, .environ_map = &environment_map, .stdin = if (stdin_command != null) .pipe else .ignore, .stdout = .pipe, .stderr = .pipe, .pgid = if (builtin.os.tag == .windows) null else 0, .start_suspended = builtin.os.tag == .windows, .create_no_window = true }) catch |err| return failure(.spawn_error, err);
        defer child.kill(self.io);
        if (options.parent_owner) |owner| owner.assign(&child) catch |err| return failure(.spawn_error, err);
        var control = (if (options.parent_owner != null) ownership.Control.initForDaemon(&child, self.io) else ownership.Control.init(&child)) catch |err| return failure(.spawn_error, err);
        defer control.deinit();
        errdefer control.kill();
        try self.register(&control);
        var registered = true;
        defer if (registered) self.unregister(&control);
        var storage: [3]std.Io.Operation.Storage = undefined;
        var batch: std.Io.Batch = .init(&storage);
        defer batch.cancel(self.io);
        var raw: [2][64 * 1024]u8 = undefined;
        var vectors = [_][1][]u8{ .{&raw[0]}, .{&raw[1]} };
        const files = [_]std.Io.File{ child.stdout.?, child.stderr.? };
        for (files, 0..) |file, index| batch.addAt(@intCast(index), .{ .file_read_streaming = .{ .file = file, .data = &vectors[index] } });
        var stdin_vectors: [1][]const u8 = undefined;
        var stdin_position: usize = 0;
        if (stdin_command) |text| {
            stdin_vectors = .{text};
            batch.addAt(2, .{ .file_write_streaming = .{ .file = child.stdin.?, .data = &stdin_vectors } });
        }
        var decoders = [_]decode.Decoder{ decode.streamDecoder(), decode.streamDecoder() };
        var pending = if (options.window) |window| Pending.init(self.gpa, window) else null;
        defer if (pending) |*value| value.deinit();
        var spill = if (options.spill) |value| Spill{ .gpa = self.gpa, .io = self.io, .root = self.temp_dir, .options = value } else null;
        defer if (spill) |*value| value.deinit();
        const started = now(self.io);
        var idle_since: ?i64 = null;
        var exited: ?i64 = null;
        var eof = [_]bool{ false, false };
        var timed_out = false;
        var aborted = false;
        var callback_error: ?anyerror = null;
        var spill_error: ?anyerror = null;
        var io_error: ?anyerror = null;
        while (true) {
            const time = now(self.io);
            if (exited == null) exited = try control.peek();
            if (exited != null and idle_since == null) idle_since = time;
            if (exited == null and !timed_out and timeout_ms != null and @as(f64, @floatFromInt(time - started)) >= timeout_ms.?) {
                timed_out = true;
                control.kill();
            }
            if (!aborted and context.aborted()) {
                aborted = true;
                control.kill();
            }
            if (pending) |*value| if (callback_error == null) value.flush(options, context, time, false) catch |err| {
                callback_error = err;
                control.kill();
            };
            if (exited != null and ((eof[0] and eof[1]) or time - idle_since.? >= 100)) break;
            if (eof[0] and eof[1] and child.stdin == null) {
                std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .awake } }, self.io) catch |err| {
                    io_error = err;
                    control.kill();
                    break;
                };
                continue;
            }
            batch.awaitConcurrent(self.io, .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .awake } }) catch |err| {
                if (err != error.Timeout) {
                    io_error = err;
                    control.kill();
                    break;
                }
            };
            while (batch.next()) |operation| {
                if (operation.index == 2) {
                    const written = operation.result.file_write_streaming catch {
                        child.stdin.?.close(self.io);
                        child.stdin = null;
                        continue;
                    };
                    stdin_position += written;
                    if (stdin_position < stdin_command.?.len and written != 0) {
                        stdin_vectors[0] = stdin_command.?[stdin_position..];
                        batch.addAt(2, .{ .file_write_streaming = .{ .file = child.stdin.?, .data = &stdin_vectors } });
                    } else {
                        child.stdin.?.close(self.io);
                        child.stdin = null;
                    }
                    continue;
                }
                const index = operation.index;
                const count = operation.result.file_read_streaming catch |err| {
                    if (err != error.EndOfStream) io_error = err;
                    eof[index] = true;
                    continue;
                };
                if (count == 0) {
                    eof[index] = true;
                    continue;
                }
                if (idle_since != null) idle_since = now(self.io);
                const bytes = raw[index][0..count];
                if (spill) |*value| if (spill_error == null) value.push(bytes) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    spill_error = err;
                    control.kill();
                };
                var text: std.ArrayList(u8) = .empty;
                defer text.deinit(self.gpa);
                try decoders[index].push(bytes, decode.Text{ .gpa = self.gpa, .output = &text });
                if (callback_error == null and options.onOutput != null and text.items.len != 0) {
                    const stream: Stream = if (index == 0) .stdout else .stderr;
                    if (pending) |*value| try value.push(text.items, stream) else options.onOutput.?(options.output_context, text.items, context, .{ .stream = stream }) catch |err| {
                        callback_error = err;
                        control.kill();
                    };
                }
                batch.addAt(index, .{ .file_read_streaming = .{ .file = files[index], .data = &vectors[index] } });
            }
        }
        batch.cancel(self.io);
        self.unregister(&control);
        registered = false;
        // Reaping after reads finish prevents closing a pipe out from under a
        // concurrent read, and PID reuse cannot occur before this point.
        if (exited == null) {
            control.kill();
            const protection = self.io.swapCancelProtection(.blocked);
            defer _ = self.io.swapCancelProtection(protection);
            _ = child.wait(self.io) catch {
                child.kill(self.io);
            };
        } else {
            const protection = self.io.swapCancelProtection(.blocked);
            defer _ = self.io.swapCancelProtection(protection);
            _ = child.wait(self.io) catch {
                child.kill(self.io);
            };
        }
        for (&decoders, 0..) |*decoder, index| {
            var text: std.ArrayList(u8) = .empty;
            defer text.deinit(self.gpa);
            try decoder.finish(decode.Text{ .gpa = self.gpa, .output = &text });
            if (callback_error == null and options.onOutput != null and text.items.len != 0) {
                const stream: Stream = if (index == 0) .stdout else .stderr;
                if (pending) |*value| try value.push(text.items, stream) else options.onOutput.?(options.output_context, text.items, context, .{ .stream = stream }) catch |err| {
                    callback_error = err;
                };
            }
        }
        if (pending) |*value| if (callback_error == null) value.flush(options, context, now(self.io), true) catch |err| {
            callback_error = err;
        };
        const spill_path = if (spill) |*value| transferred: {
            const path = value.path;
            value.path = null;
            break :transferred path;
        } else null;
        const result = if (callback_error) |err| failure(.callback_error, err) else if (timed_out) failure(.timeout, null) else if (aborted) failure(.aborted, null) else if (spill_error) |err| failure(.unknown, err) else if (io_error) |err| failure(if (err == error.Canceled) .aborted else .unknown, err) else Result{ .value = .{ .exitCode = exited orelse -1 } };
        var owned_result = result;
        switch (owned_result) {
            .value => |*value| value.spillPath = spill_path,
            .failure => |*value| value.spillPath = spill_path,
        }
        return owned_result;
    }
};

test "durable direct argv executes a real owned native process and removes its active control" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var shell = try Shell.init(gpa, io, path_buffer[0..length], &environ, null, null, path_buffer[0..length]);
    defer shell.deinit();
    const argv: []const []const u8 = if (builtin.os.tag == .windows) &.{ "cmd.exe", "/C", "exit", "0" } else &.{ "/bin/sh", "-c", "exit 0" };
    var result = try shell.exec(.{ .argv = argv }, .{ .timeout = 5 }, .{});
    switch (result) {
        .value => |*value| {
            defer value.deinit(gpa);
            try std.testing.expectEqual(@as(i64, 0), value.exitCode);
        },
        .failure => |*err| {
            defer err.deinit(gpa);
            std.debug.print("Durable command error {s}: {s}\n", .{ @tagName(err.code), err.message });
            return error.UnexpectedCommandFailure;
        },
    }
    try std.testing.expectEqual(@as(usize, 0), shell.active.items.len);
}

const Capture = struct {
    gpa: std.mem.Allocator,
    stdout: std.ArrayList(u8) = .empty,
    stderr: std.ArrayList(u8) = .empty,
    combined: output.OutputBuffer,
    raw_seen: u64 = 0,
    decoded_seen: u64 = 0,
    newlines_seen: u64 = 0,
    skips: usize = 0,
    calls: usize = 0,
    abort_flag: ?*std.atomic.Value(bool) = null,
    fail_callback: bool = false,
    fn init(gpa: std.mem.Allocator, limits: output.Limits) Capture {
        return .{ .gpa = gpa, .combined = output.OutputBuffer.init(gpa, limits) };
    }
    fn deinit(self: *Capture) void {
        self.stdout.deinit(self.gpa);
        self.stderr.deinit(self.gpa);
        self.combined.deinit();
    }
    fn callback(context: ?*anyopaque, text: []const u8, _: types.Context, info: OutputInfo) !void {
        const self: *Capture = @ptrCast(@alignCast(context.?));
        self.calls += 1;
        if (self.fail_callback) return error.CallbackSentinel;
        if (self.abort_flag) |flag| flag.store(true, .release);
        self.raw_seen += text.len;
        self.decoded_seen += text.len;
        self.newlines_seen += std.mem.count(u8, text, "\n");
        if (info.skipped) |skipped| {
            self.skips += 1;
            self.decoded_seen += skipped.bytes;
            self.newlines_seen += skipped.newlines;
        }
        if (info.stream == .stdout) try self.stdout.appendSlice(self.gpa, text) else try self.stderr.appendSlice(self.gpa, text);
        _ = try self.combined.pushText(text, info.skipped);
    }
};
fn fixturePath(gpa: std.mem.Allocator, environ: *const std.process.Environ.Map) ![]u8 {
    const cwd = try std.process.currentPathAlloc(std.testing.io, gpa);
    defer gpa.free(cwd);
    return std.fs.path.resolve(gpa, &.{ cwd, environ.get("PI_DURABLE_FIXTURE") orelse if (builtin.os.tag == .windows) "zig-out/bin/pi-durable-fixture.exe" else "zig-out/bin/pi-durable-fixture" });
}
fn expectExit(gpa: std.mem.Allocator, result: Result, code: i64) !void {
    var owned = result;
    switch (owned) {
        .value => |*value| {
            defer value.deinit(gpa);
            try std.testing.expectEqual(code, value.exitCode);
        },
        .failure => |*err| {
            defer err.deinit(gpa);
            std.debug.print("Durable execution error {s}: {s}\n", .{ @tagName(err.code), err.message });
            return error.UnexpectedCommandFailure;
        },
    }
}
test "durable native argv stream labels BOM splits and inherited environment overlays" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const fixture = try fixturePath(gpa, &environ);
    defer gpa.free(fixture);
    try environ.put("PI_DURABLE_PARENT", "parent");
    try environ.put("PI_DURABLE_SHARED", "parent-shared");
    var base: std.process.Environ.Map = .init(gpa);
    defer base.deinit();
    try base.put("PI_DURABLE_BASE", "base");
    try base.put("PI_DURABLE_SHARED", "base-shared");
    var request: std.process.Environ.Map = .init(gpa);
    defer request.deinit();
    try request.put("PI_DURABLE_REQUEST", "request");
    try request.put("PI_DURABLE_SHARED", "request-shared");
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var shell = try Shell.init(gpa, io, path_buffer[0..length], &environ, &base, null, path_buffer[0..length]);
    defer shell.deinit();
    var args = Capture.init(gpa, .{});
    defer args.deinit();
    try expectExit(gpa, try shell.exec(.{ .argv = &.{ fixture, "args", "a b", "&|;<>$()", "quote\"slash\\", "", "é😀" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &args }, .{}), 0);
    try std.testing.expectEqualStrings("[\"a b\",\"&|;<>$()\",\"quote\\\"slash\\\\\",\"\",\"é😀\"]", args.stdout.items);
    var streams = Capture.init(gpa, .{});
    defer streams.deinit();
    try expectExit(gpa, try shell.exec(.{ .argv = &.{ fixture, "streams" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &streams }, .{}), 7);
    try std.testing.expectEqualStrings("a😀\n", streams.stdout.items);
    try std.testing.expectEqualStrings("e\xef\xbf\xbd\xef\xbb\xbf\n", streams.stderr.items);
    var inherited = Capture.init(gpa, .{});
    defer inherited.deinit();
    try expectExit(gpa, try shell.exec(.{ .argv = &.{ fixture, "environment" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &inherited, .env = &request }, .{}), 0);
    try std.testing.expectEqualStrings("{\"parent\":\"parent\",\"base\":\"base\",\"request\":\"request\",\"shared\":\"request-shared\"}", inherited.stdout.items);
    var isolated = Capture.init(gpa, .{});
    defer isolated.deinit();
    try expectExit(gpa, try shell.exec(.{ .argv = &.{ fixture, "environment" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &isolated, .env = &request, .inheritEnv = false }, .{}), 0);
    try std.testing.expectEqualStrings("{\"parent\":null,\"base\":null,\"request\":\"request\",\"shared\":\"request-shared\"}", isolated.stdout.items);
    try expectExit(gpa, try shell.exec(.{ .argv = &.{ fixture, "exit1000" } }, .{ .timeout = 5 }, .{}), if (builtin.os.tag == .windows) 1000 else 232);
    try std.testing.expectEqual(@as(usize, 0), shell.active.items.len);
}

test "durable native command window skips drain multi-megabyte output and spill complete raw bytes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const fixture = try fixturePath(gpa, &environ);
    defer gpa.free(fixture);
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var shell = try Shell.init(gpa, io, path_buffer[0..length], &environ, null, null, path_buffer[0..length]);
    defer shell.deinit();
    var capture = Capture.init(gpa, .{ .maxBytes = 256, .maxLines = 4 });
    defer capture.deinit();
    var result = try shell.exec(.{ .argv = &.{ fixture, "large" } }, .{ .timeout = 10, .onOutput = Capture.callback, .output_context = &capture, .spill = .{ .afterBytes = 1024, .afterLines = 20 }, .window = .{ .maxBytes = 256, .maxLines = 4, .minIntervalMs = 1000, .bytesPerSecond = 100 * 1024 } }, .{});
    const path = switch (result) {
        .value => |*value| path: {
            try std.testing.expectEqual(@as(i64, 0), value.exitCode);
            break :path value.spillPath orelse return error.MissingSpill;
        },
        .failure => |*err| {
            defer err.deinit(gpa);
            return error.UnexpectedCommandFailure;
        },
    };
    defer result.value.deinit(gpa);
    try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), capture.decoded_seen);
    try std.testing.expectEqual(@as(u64, 2 * 1024 * 1024), capture.newlines_seen);
    try std.testing.expect(capture.skips > 0);
    try std.testing.expect(capture.raw_seen < 4096);
    const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
    try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024), stat.size);
    var snapshot = try capture.combined.snapshot();
    defer snapshot.deinit(gpa);
    try std.testing.expectEqualStrings("L\nL\nL\nL\n", snapshot.text);
    try std.testing.expectEqual(@as(u64, 4 * 1024 * 1024 - 8), snapshot.droppedBytes);
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var bytes: [8]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 8), try file.readPositionalAll(io, &bytes, 0));
    try std.testing.expectEqualSlices(u8, "L\nL\nL\nL\n", &bytes);
}

test "durable native timeout abort callback failures reap owned trees and preserve unrelated child" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const fixture = try fixturePath(gpa, &environ);
    defer gpa.free(fixture);
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var shell = try Shell.init(gpa, io, path_buffer[0..length], &environ, null, null, path_buffer[0..length]);
    defer shell.deinit();
    const marker = try std.fs.path.join(gpa, &.{ path_buffer[0..length], "unrelated-marker" });
    defer gpa.free(marker);
    var unrelated = try std.process.spawn(io, .{ .argv = &.{ fixture, "sentinel", marker }, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore, .create_no_window = true });
    defer unrelated.kill(io);
    const started = now(io);
    var timeout_result = try shell.exec(.{ .argv = &.{ fixture, "tree" } }, .{ .timeout = 0.12 }, .{});
    switch (timeout_result) {
        .failure => |*err| {
            defer err.deinit(gpa);
            try std.testing.expectEqual(ExecutionErrorCode.timeout, err.code);
        },
        .value => return error.ExpectedTimeout,
    }
    try std.testing.expect(now(io) - started < 2500);
    const status = try unrelated.wait(io);
    try std.testing.expectEqual(@as(u8, 0), status.exited);
    const preserved = try temporary_dir.dir.readFileAlloc(io, "unrelated-marker", gpa, .limited(32));
    defer gpa.free(preserved);
    try std.testing.expectEqualStrings("survived", preserved);
    var flag: std.atomic.Value(bool) = .init(false);
    var aborted = Capture.init(gpa, .{});
    defer aborted.deinit();
    aborted.abort_flag = &flag;
    var abort_result = try shell.exec(.{ .argv = &.{ fixture, "sleep" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &aborted }, .{ .abort_flag = &flag });
    switch (abort_result) {
        .failure => |*err| {
            defer err.deinit(gpa);
            try std.testing.expectEqual(ExecutionErrorCode.aborted, err.code);
        },
        .value => return error.ExpectedAbort,
    }
    try std.testing.expectEqualStrings("before\n", aborted.stdout.items);
    var callback = Capture.init(gpa, .{});
    defer callback.deinit();
    callback.fail_callback = true;
    var callback_result = try shell.exec(.{ .argv = &.{ fixture, "sleep" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &callback }, .{});
    switch (callback_result) {
        .failure => |*err| {
            defer err.deinit(gpa);
            try std.testing.expectEqual(ExecutionErrorCode.callback_error, err.code);
            try std.testing.expectEqual(error.CallbackSentinel, err.cause.?);
        },
        .value => return error.ExpectedCallbackError,
    }
    const calls = callback.calls;
    try std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } }, io);
    try std.testing.expectEqual(calls, callback.calls);
    try std.testing.expectEqual(@as(usize, 0), shell.active.items.len);
}

fn allocationProbe(gpa: std.mem.Allocator, cwd: []const u8, fixture: []const u8) !void {
    var environ: std.process.Environ.Map = .init(gpa);
    defer environ.deinit();
    try environ.put("PI_DURABLE_PARENT", "gpa");
    var shell = try Shell.init(gpa, std.testing.io, cwd, &environ, null, null, cwd);
    defer shell.deinit();
    var capture = Capture.init(gpa, .{});
    defer capture.deinit();
    var result = try shell.exec(.{ .argv = &.{ fixture, "args", "native-gpa" } }, .{ .timeout = 5, .onOutput = Capture.callback, .output_context = &capture }, .{});
    switch (result) {
        .value => |*value| {
            defer value.deinit(gpa);
            try std.testing.expectEqual(@as(i64, 0), value.exitCode);
        },
        .failure => |*err| {
            defer err.deinit(gpa);
            if (err.cause) |cause| if (cause == error.OutOfMemory) return error.OutOfMemory;
            return error.UnexpectedCommandFailure;
        },
    }
    try std.testing.expectEqualStrings("[\"native-gpa\"]", capture.stdout.items);
    try std.testing.expectEqual(@as(usize, 0), shell.active.items.len);
}
test "durable shell every induced allocation failure releases active controls pipes and environment" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const fixture = try fixturePath(gpa, &environ);
    defer gpa.free(fixture);
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    try std.testing.checkAllAllocationFailures(gpa, allocationProbe, .{ path_buffer[0..length], fixture });
}
