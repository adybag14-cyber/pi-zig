//! Actual owned child process and authenticated native IPC admission.
//! This layer handles only OS capabilities and bytes; the VM facade and guest
//! bootstrap must install the actual Chord/process APIs before activation.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const ownership = @import("../durable/process_ownership.zig");
const transport = @import("native_chord_ipc_transport.zig");
const records = std.heap.page_allocator;
pub const port_env = "PI_NATIVE_CHORD_IPC_PORT";
pub const token_env = "PI_NATIVE_CHORD_IPC_TOKEN";
const win = struct {
    extern "kernel32" fn GetProcessId(std.os.windows.HANDLE) callconv(.winapi) std.os.windows.DWORD;
};
pub const Config = struct {
    argv: []const []const u8,
    environment: *const std.process.Environ.Map,
    output_tap: bool,
    wake: transport.Wake = .{},
};
pub const Output = struct {
    pub const Stream = enum { stdout, stderr };
    stream: Stream,
    bytes: []u8,
    pub fn deinit(value: *Output) void {
        records.free(value.bytes);
        value.* = undefined;
    }
};
pub const Exit = struct { term: std.process.Child.Term, killed: bool };
pub const Owner = struct {
    gpa: std.mem.Allocator,
    io: Io,
    wake: transport.Wake = .{},
    child: ?std.process.Child = null,
    control: ?ownership.Control = null,
    pid: u32 = 0,
    listener: Io.net.Server,
    listener_live: bool = true,
    token: [16]u8,
    process_mutex: Io.Mutex = .init,
    data_mutex: Io.Mutex = .init,
    endpoint: ?*transport.Endpoint = null,
    exit: ?Exit = null,
    killed: bool = false,
    failure: ?anyerror = null,
    output: std.ArrayList(Output) = .empty,
    output_bytes: usize = 0,
    stdout: ?Io.File = null,
    stderr: ?Io.File = null,
    acceptor: ?Io.Future(anyerror!void) = null,
    monitor: ?Io.Future(anyerror!void) = null,
    stdout_reader: ?Io.Future(anyerror!void) = null,
    stderr_reader: ?Io.Future(anyerror!void) = null,
    stopping: std.atomic.Value(bool) = .init(false),
    pub fn start(gpa: std.mem.Allocator, io: Io, config: Config) !*Owner {
        if (config.argv.len == 0) return error.NativeChordChildCommandMissing;
        const address = try Io.net.IpAddress.parseLiteral("127.0.0.1:0");
        var listener = try address.listen(io, .{});
        var listener_moved = false;
        errdefer if (!listener_moved) listener.deinit(io);
        var token: [16]u8 = undefined;
        try io.randomSecure(&token);
        const token_hex = std.fmt.bytesToHex(token, .lower);
        var environment = try config.environment.clone(gpa);
        defer environment.deinit();
        const port = try std.fmt.allocPrint(gpa, "{d}", .{listener.socket.address.getPort()});
        defer gpa.free(port);
        try environment.put(port_env, port);
        try environment.put(token_env, &token_hex);
        const self = try gpa.create(Owner);
        self.* = .{ .gpa = gpa, .io = io, .listener = listener, .token = token, .wake = config.wake };
        listener_moved = true;
        errdefer self.deinit();
        self.child = try std.process.spawn(io, .{ .argv = config.argv, .environ_map = &environment, .stdin = .ignore, .stdout = if (config.output_tap) .pipe else .inherit, .stderr = if (config.output_tap) .pipe else .inherit, .create_no_window = true, .start_suspended = builtin.os.tag == .windows, .pgid = if (builtin.os.tag == .windows) null else 0 });
        self.pid = if (builtin.os.tag == .windows) win.GetProcessId(self.child.?.id.?) else @intCast(self.child.?.id.?);
        if (self.pid == 0) return error.NativeChordChildIdentityUnavailable;
        self.stdout = self.child.?.stdout;
        self.stderr = self.child.?.stderr;
        // Reader tasks lease these exact handles until cancellation joins.
        self.child.?.stdout = null;
        self.child.?.stderr = null;
        // KILL_ON_JOB_CLOSE on Windows; POSIX children lead their own group.
        self.control = try ownership.Control.initWithFlags(&self.child.?, if (builtin.os.tag == .windows) 0x2000 else 0);
        self.acceptor = try io.concurrent(accept, .{self});
        self.monitor = try io.concurrent(watch, .{self});
        if (self.stdout) |file| self.stdout_reader = try io.concurrent(readOutput, .{ self, file, Output.Stream.stdout });
        if (self.stderr) |file| self.stderr_reader = try io.concurrent(readOutput, .{ self, file, Output.Stream.stderr });
        return self;
    }
    fn fail(self: *Owner, err: anyerror) void {
        self.data_mutex.lockUncancelable(self.io);
        defer self.data_mutex.unlock(self.io);
        if (self.failure == null) self.failure = err;
        self.wake.signal();
    }
    pub fn terminalFailure(self: *Owner) ?anyerror {
        self.data_mutex.lockUncancelable(self.io);
        defer self.data_mutex.unlock(self.io);
        return self.failure;
    }
    fn accept(self: *Owner) anyerror!void {
        while (!self.stopping.load(.acquire)) {
            const stream = self.listener.accept(self.io) catch |err| {
                self.fail(err);
                return err;
            };
            var stream_moved = false;
            defer if (!stream_moved) stream.close(self.io);
            var buffer: [64]u8 = undefined;
            var input = stream.reader(self.io, &buffer);
            const supplied = input.interface.take(16) catch |err| {
                if (err == error.Canceled) return err;
                continue;
            };
            if (!std.crypto.timing_safe.eql([16]u8, supplied[0..16].*, self.token)) continue;
            // A dedicated handshake read must not prefetch the first frame.
            // The child waits for this single-byte acknowledgement before send.
            var write_buffer: [1]u8 = undefined;
            var acknowledgement = stream.writer(self.io, &write_buffer);
            try acknowledgement.interface.writeByte(1);
            try acknowledgement.interface.flush();
            stream_moved = true;
            const endpoint = transport.Endpoint.create(self.io, stream, self.wake) catch |err| {
                self.fail(err);
                return err;
            };
            self.data_mutex.lockUncancelable(self.io);
            self.endpoint = endpoint;
            self.data_mutex.unlock(self.io);
            self.wake.signal();
            return;
        }
    }
    fn watch(self: *Owner) anyerror!void {
        while (!self.stopping.load(.acquire)) {
            self.process_mutex.lockUncancelable(self.io);
            const status = if (self.control) |*control| control.peek() else null;
            const ready = status catch |err| {
                self.process_mutex.unlock(self.io);
                self.fail(err);
                return err;
            };
            if (ready != null) {
                // Kill descendants while the exact leader is still unreaped.
                self.control.?.kill();
                const term = self.child.?.wait(self.io) catch |err| {
                    self.process_mutex.unlock(self.io);
                    self.fail(err);
                    return err;
                };
                self.exit = .{ .term = term, .killed = self.killed };
                self.process_mutex.unlock(self.io);
                self.wake.signal();
                return;
            }
            self.process_mutex.unlock(self.io);
            try self.io.sleep(.fromMilliseconds(10), .awake);
        }
    }
    fn readOutput(self: *Owner, file: Io.File, stream: Output.Stream) anyerror!void {
        var buffer: [8192]u8 = undefined;
        while (!self.stopping.load(.acquire)) {
            const size = file.readStreaming(self.io, &.{&buffer}) catch |err| {
                self.fail(err);
                return err;
            };
            if (size == 0) return;
            const bytes = records.dupe(u8, buffer[0..size]) catch |err| {
                self.fail(err);
                return err;
            };
            self.data_mutex.lockUncancelable(self.io);
            if (size > transport.maximum_queued -| self.output_bytes) {
                self.data_mutex.unlock(self.io);
                records.free(bytes);
                self.fail(error.NativeChordChildOutputLimit);
                return error.NativeChordChildOutputLimit;
            }
            self.output.append(records, .{ .stream = stream, .bytes = bytes }) catch |err| {
                self.data_mutex.unlock(self.io);
                records.free(bytes);
                self.fail(err);
                return err;
            };
            self.output_bytes += size;
            self.data_mutex.unlock(self.io);
            self.wake.signal();
        }
    }
    pub fn ipc(self: *Owner) ?*transport.Endpoint {
        self.data_mutex.lockUncancelable(self.io);
        defer self.data_mutex.unlock(self.io);
        return self.endpoint;
    }
    pub fn takeOutput(self: *Owner) ?Output {
        self.data_mutex.lockUncancelable(self.io);
        defer self.data_mutex.unlock(self.io);
        if (self.output.items.len == 0) return null;
        const item = self.output.orderedRemove(0);
        self.output_bytes -= item.bytes.len;
        return item;
    }
    pub fn exited(self: *Owner) ?Exit {
        self.process_mutex.lockUncancelable(self.io);
        defer self.process_mutex.unlock(self.io);
        return self.exit;
    }
    pub fn killTree(self: *Owner) void {
        self.process_mutex.lockUncancelable(self.io);
        defer self.process_mutex.unlock(self.io);
        if (self.exit != null or self.child == null or self.child.?.id == null) return;
        if (self.control) |*control| {
            if ((control.peek() catch null) == null) self.killed = true;
            control.kill();
        } else {
            self.killed = true;
            self.child.?.kill(self.io);
        }
    }
    pub fn close(self: *Owner) void {
        if (self.stopping.swap(true, .acq_rel)) return;
        self.killTree();
        if (self.acceptor) |*future| _ = future.cancel(self.io) catch {};
        if (self.monitor) |*future| _ = future.cancel(self.io) catch {};
        if (self.stdout_reader) |*future| _ = future.cancel(self.io) catch {};
        if (self.stderr_reader) |*future| _ = future.cancel(self.io) catch {};
        self.acceptor = null;
        self.monitor = null;
        self.stdout_reader = null;
        self.stderr_reader = null;
        if (self.child) |*child| if (child.id != null) {
            _ = child.wait(self.io) catch {};
        };
        if (self.endpoint) |endpoint| endpoint.deinit();
        self.endpoint = null;
        if (self.stdout) |file| file.close(self.io);
        if (self.stderr) |file| file.close(self.io);
        self.stdout = null;
        self.stderr = null;
        if (self.listener_live) self.listener.deinit(self.io);
        self.listener_live = false;
        if (self.control) |*control| control.deinit();
        self.control = null;
    }
    pub fn deinit(self: *Owner) void {
        self.close();
        for (self.output.items) |*item| item.deinit();
        self.output.deinit(records);
        self.gpa.destroy(self);
    }
};
/// The native child consumes only its private transport envelope, then exposes
/// the user environment unchanged to guest code.
pub fn connectChild(io: Io, port: u16, token: [16]u8, wake: transport.Wake) !*transport.Endpoint {
    const address = try Io.net.IpAddress.parse("127.0.0.1", port);
    const stream = try address.connect(io, .{ .mode = .stream, .protocol = .tcp });
    var moved = false;
    errdefer if (!moved) stream.close(io);
    var write_buffer: [16]u8 = undefined;
    var output = stream.writer(io, &write_buffer);
    try output.interface.writeAll(&token);
    try output.interface.flush();
    var read_buffer: [1]u8 = undefined;
    var input = stream.reader(io, &read_buffer);
    if (try input.interface.takeByte() != 1) return error.NativeChordIpcAdmissionRejected;
    moved = true;
    return transport.Endpoint.create(io, stream, wake);
}
