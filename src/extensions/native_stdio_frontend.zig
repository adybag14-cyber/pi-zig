//! Actual stdio for a directly embedded SDK script. Internal framed extension
//! workers use process_stream_parent instead; this owner never reads their wire.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const streams = @import("native_process_streams.zig");
const scope = @import("native_async_scope.zig");
const timers = @import("timers.zig");
const platform = @import("../tui/platform_terminal.zig");
const Io = std.Io;

const Size = struct { columns: ?u32 = null, rows: ?u32 = null };
const Console = struct {
    const Input = if (builtin.os.tag == .windows) struct { mode: u32, cp: u32 } else std.posix.termios;
    input: ?Input = null,
    output_mode: ?u32 = null,
    error_mode: ?u32 = null,
    output_cp: ?u32 = null,
    raw: bool = false,
    fn init(self: *Console, input_tty: bool, output_tty: bool, error_tty: bool) !void {
        errdefer self.close();
        if (comptime builtin.os.tag == .windows) {
            if (input_tty) {
                var mode: u32 = 0;
                if (!platform.win.GetConsoleMode(Io.File.stdin().handle, &mode).toBool()) return error.ConsoleInputModeFailed;
                self.input = .{ .mode = mode, .cp = platform.win.GetConsoleCP() };
                if (!platform.win.SetConsoleCP(65001).toBool()) return error.ConsoleInputEncodingFailed;
            }
            if (output_tty or error_tty) {
                self.output_cp = platform.win.GetConsoleOutputCP();
                if (!platform.win.SetConsoleOutputCP(65001).toBool()) return error.ConsoleOutputEncodingFailed;
            }
            if (output_tty) {
                var mode: u32 = 0;
                if (!platform.win.GetConsoleMode(Io.File.stdout().handle, &mode).toBool()) return error.ConsoleOutputModeFailed;
                self.output_mode = mode;
                if (!platform.win.SetConsoleMode(Io.File.stdout().handle, mode | 4).toBool()) return error.ConsoleOutputModeFailed;
            }
            if (error_tty) {
                var mode: u32 = 0;
                if (!platform.win.GetConsoleMode(Io.File.stderr().handle, &mode).toBool()) return error.ConsoleOutputModeFailed;
                self.error_mode = mode;
                if (!platform.win.SetConsoleMode(Io.File.stderr().handle, mode | 4).toBool()) return error.ConsoleOutputModeFailed;
            }
        } else if (comptime builtin.os.tag == .linux or builtin.os.tag == .macos) {
            if (input_tty) {
                var attributes: std.posix.termios = undefined;
                while (true) switch (std.posix.errno(std.posix.system.tcgetattr(Io.File.stdin().handle, &attributes))) {
                    .SUCCESS => break,
                    .INTR => continue,
                    .IO, .NOTTY => return error.ConsoleInputModeFailed,
                    else => |err| return std.posix.unexpectedErrno(err),
                };
                self.input = attributes;
            }
        }
    }
    fn setRaw(self: *Console, raw: bool) !void {
        const original = self.input orelse return error.NotATerminal;
        if (raw == self.raw) return;
        if (comptime builtin.os.tag == .windows) {
            // Node24 uses UV_TTY_MODE_RAW_VT: libuv tries WINDOW_INPUT +
            // VIRTUAL_TERMINAL_INPUT, then WINDOW_INPUT for older consoles.
            // NORMAL is the standard echo/line/processed mode. Owner teardown
            // separately restores the exact mode captured on entry.
            const mode: u32 = if (raw) 8 else 1 | 2 | 4;
            const requested = mode | @as(u32, if (raw) 0x200 else 0);
            if (!platform.win.SetConsoleMode(Io.File.stdin().handle, requested).toBool() and
                !platform.win.SetConsoleMode(Io.File.stdin().handle, mode).toBool()) return error.ConsoleInputModeFailed;
        } else if (comptime builtin.os.tag == .linux or builtin.os.tag == .macos) {
            var attributes = original;
            if (raw) {
                // libuv1.51 UV_TTY_MODE_RAW (not its distinct MODE_IO).
                attributes.lflag.ICANON = false;
                attributes.lflag.ECHO = false;
                attributes.lflag.ISIG = false;
                attributes.lflag.IEXTEN = false;
                attributes.iflag.BRKINT = false;
                attributes.iflag.ICRNL = false;
                attributes.iflag.INPCK = false;
                attributes.iflag.ISTRIP = false;
                attributes.iflag.IXON = false;
                attributes.oflag.ONLCR = true;
                attributes.cflag.CSIZE = .CS8;
                attributes.cc[@intFromEnum(std.posix.V.MIN)] = 1;
                attributes.cc[@intFromEnum(std.posix.V.TIME)] = 0;
            }
            while (true) switch (std.posix.errno(std.posix.system.tcsetattr(Io.File.stdin().handle, .DRAIN, &attributes))) {
                .SUCCESS => break,
                .INTR => continue,
                .IO, .NOTTY => return error.ConsoleInputModeFailed,
                else => |err| return std.posix.unexpectedErrno(err),
            };
        } else return error.UnsupportedTerminal;
        self.raw = raw;
    }
    fn close(self: *Console) void {
        if (self.input != null) self.setRaw(false) catch {};
        if (comptime builtin.os.tag == .windows) {
            if (self.input) |original| {
                _ = platform.win.SetConsoleMode(Io.File.stdin().handle, original.mode);
                _ = platform.win.SetConsoleCP(original.cp);
            }
            if (self.output_mode) |mode| _ = platform.win.SetConsoleMode(Io.File.stdout().handle, mode);
            if (self.error_mode) |mode| _ = platform.win.SetConsoleMode(Io.File.stderr().handle, mode);
            if (self.output_cp) |cp| _ = platform.win.SetConsoleOutputCP(cp);
        }
        self.* = .{};
    }
};

fn dimensions(output_tty: bool) Size {
    if (!output_tty) return .{};
    if (comptime builtin.os.tag == .windows) {
        var info: platform.win.BufferInfo = undefined;
        if (!platform.win.GetConsoleScreenBufferInfo(Io.File.stdout().handle, &info).toBool()) return .{};
        // Node24's libuv1.51 virtual width is the screen buffer width, while
        // height is the visible window height (src/win/tty.c get_winsize).
        return .{ .columns = @intCast(@max(0, info.size.x)), .rows = @intCast(@max(0, @as(i32, info.window.bottom) - info.window.top + 1)) };
    } else if (comptime builtin.os.tag == .linux or builtin.os.tag == .macos) {
        var size: std.posix.winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };
        if (std.posix.errno(std.posix.system.ioctl(Io.File.stdout().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&size))) != .SUCCESS) return .{};
        return .{ .columns = size.col, .rows = size.row };
    } else return .{};
}

pub const Frontend = struct {
    engine: *js.Engine,
    io: Io,
    owner: std.Thread.Id,
    active: std.atomic.Value(bool) = .init(false),
    lease: ?streams.Lease = null,
    previous_context: ?*anyopaque = null,
    previous_pump: ?*const fn (*js.Engine) anyerror!bool = null,
    console: Console = .{},
    output_tty: bool = false,
    size: Size = .{},
    mutex: Io.Mutex = .init,
    changed: Io.Condition = .init,
    queue: std.ArrayList([]u8) = .empty,
    bytes: usize = 0,
    flowing: bool = false,
    closed: bool = false,
    eof: bool = false,
    end_delivered: bool = false,
    failure: ?anyerror = null,
    reader_started: bool = false,
    reader_group: Io.Group = .init,
    pumping: bool = false,
    pub fn init(self: *Frontend, engine: *js.Engine, io: Io) !void {
        if (engine.host_control_context != null or engine.host_control_pump != null) return error.NativeStdioControlPumpAlreadyBound;
        self.* = .{ .engine = engine, .io = io, .owner = std.Thread.getCurrentId() };
        const input_tty = try Io.File.stdin().isTty(io);
        self.output_tty = try Io.File.stdout().isTty(io);
        const error_tty = try Io.File.stderr().isTty(io);
        try self.console.init(input_tty, self.output_tty, error_tty);
        errdefer self.console.close();
        self.size = dimensions(self.output_tty);
        try streams.hydrateInput(engine, false, input_tty);
        try streams.hydrateOutput(engine, self.output_tty, error_tty, self.size.columns, self.size.rows);
        self.active.store(true, .release);
        errdefer self.active.store(false, .release);
        self.lease = try streams.bind(engine, .{ .context = self, .guard_fn = guard, .control_fn = control, .write_fn = write });
        self.previous_context = engine.host_control_context;
        self.previous_pump = engine.host_control_pump;
    }
    pub fn deinit(self: *Frontend) void {
        self.active.store(false, .release);
        if (self.engine.host_control_context == @as(?*anyopaque, @ptrCast(self))) {
            self.engine.host_control_context = self.previous_context;
            self.engine.host_control_pump = self.previous_pump;
        }
        self.mutex.lockUncancelable(self.io);
        self.closed = true;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
        if (self.reader_started) {
            self.reader_group.cancel(self.io);
            self.reader_group.await(self.io) catch {};
        }
        if (self.lease) |lease| _ = streams.unbind(self.engine, lease);
        for (self.queue.items) |bytes| std.heap.page_allocator.free(bytes);
        self.queue.deinit(std.heap.page_allocator);
        self.console.close();
    }
    fn guard(raw: ?*anyopaque) !void {
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        if (!self.active.load(.acquire)) return error.NativeProcessFrontendClosed;
        if (self.owner != std.Thread.getCurrentId()) return error.NativeProcessWrongOwnerThread;
    }
    fn write(raw: ?*anyopaque, output: streams.Output, bytes: []const u8) !void {
        try guard(raw);
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        try (if (output == .stdout) Io.File.stdout() else Io.File.stderr()).writeStreamingAll(self.io, bytes);
    }
    fn control(raw: ?*anyopaque, operation: streams.Control) !void {
        try guard(raw);
        const self: *Frontend = @ptrCast(@alignCast(raw.?));
        switch (operation) {
            .raw_mode => |raw_mode| try self.console.setRaw(raw_mode),
            .encoding => {}, // Decoding belongs to the genuine VM stream state.
            .@"resume", .pause => {
                const resumed = operation == .@"resume";
                if (resumed and !self.reader_started) {
                    try self.reader_group.concurrent(self.io, reader, .{self});
                    self.reader_started = true;
                    // Scripts that never resume stdin must not acquire a
                    // permanently pending IO handle just by reading metadata.
                    self.engine.host_control_context = self;
                    self.engine.host_control_pump = pump;
                }
                self.mutex.lockUncancelable(self.io);
                self.flowing = resumed;
                self.changed.broadcast(self.io);
                self.mutex.unlock(self.io);
            },
        }
    }
    fn reader(self: *Frontend) void {
        var buffer: [64 * 1024]u8 = undefined;
        while (true) {
            self.mutex.lockUncancelable(self.io);
            while (!self.closed and (!self.flowing or self.bytes >= 4 * 1024 * 1024)) self.changed.waitUncancelable(self.io, &self.mutex);
            const closed = self.closed;
            self.mutex.unlock(self.io);
            if (closed) return;
            var vectors = [_][]u8{&buffer};
            const count = Io.File.stdin().readStreaming(self.io, &vectors) catch |err| {
                self.mutex.lockUncancelable(self.io);
                defer self.mutex.unlock(self.io);
                if (!self.closed) {
                    if (err == error.EndOfStream) self.eof = true else self.failure = err;
                }
                return;
            };
            if (count == 0) {
                self.mutex.lockUncancelable(self.io);
                self.eof = true;
                self.mutex.unlock(self.io);
                return;
            }
            const bytes = std.heap.page_allocator.dupe(u8, buffer[0..count]) catch |err| {
                self.mutex.lockUncancelable(self.io);
                self.failure = err;
                self.mutex.unlock(self.io);
                return;
            };
            self.mutex.lockUncancelable(self.io);
            if (self.closed) {
                self.mutex.unlock(self.io);
                std.heap.page_allocator.free(bytes);
                return;
            }
            self.queue.append(std.heap.page_allocator, bytes) catch |err| {
                self.failure = err;
                self.mutex.unlock(self.io);
                std.heap.page_allocator.free(bytes);
                return;
            };
            self.bytes += bytes.len;
            self.mutex.unlock(self.io);
        }
    }
    fn pump(engine: *js.Engine) !bool {
        const self: *Frontend = @ptrCast(@alignCast(engine.host_control_context.?));
        if (self.pumping) return false;
        try guard(self);
        if (!streams.ownsLease(engine, self.lease.?)) return false;
        // Native input is an IO turn. Finish the current microtask checkpoint
        // before starting another data/EOF/resize callback, as Source does.
        if (js.c.JS_IsJobPending(engine.runtime)) return false;
        self.pumping = true;
        defer self.pumping = false;
        var neutral = scope.enter(engine, js.c.pi_js_undefined());
        defer neutral.restore();
        const current = dimensions(self.output_tty);
        if (!std.meta.eql(current, self.size) and current.columns != null and current.rows != null) {
            self.size = current;
            try streams.deliverResize(engine, current.columns.?, current.rows.?);
            // Resize is its own physical IO callback; its Promise checkpoint
            // completes before an input/EOF callback enters the VM.
            return true;
        }
        self.mutex.lockUncancelable(self.io);
        if (self.failure) |failure| {
            self.failure = null;
            self.mutex.unlock(self.io);
            return failure;
        }
        const input = if (self.flowing and self.queue.items.len != 0) self.queue.orderedRemove(0) else null;
        if (input) |bytes| self.bytes -= bytes.len;
        const ended = self.eof and self.queue.items.len == 0 and !self.end_delivered;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
        if (input) |bytes| {
            defer std.heap.page_allocator.free(bytes);
            try streams.deliverInput(engine, bytes);
            return true;
        }
        if (ended) {
            self.end_delivered = true;
            try streams.deliverEnd(engine);
            return true;
        }
        return false;
    }
    fn referencedInput(self: *Frontend) bool {
        if (!streams.ownsLease(self.engine, self.lease.?)) return false;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return !self.closed and (self.failure != null or (self.eof and self.queue.items.len == 0 and !self.end_delivered) or (self.flowing and (self.queue.items.len != 0 or (self.reader_started and !self.eof))));
    }
    pub fn runUntilIdle(self: *Frontend) !void {
        while (true) {
            _ = try self.engine.drainReadyJobs();
            const referenced_timer = try timers.nextReferencedDeadline(self.engine);
            const builtin_pending = if (self.engine.native_sdk_builtin_execution_pending) |pending| pending(self.engine) else false;
            if (!self.referencedInput() and referenced_timer == null and !builtin_pending) return;
            _ = try self.engine.pumpControls();
            _ = try timers.pumpReady(self.engine);
            _ = try self.engine.drainReadyJobs();
            const deadline = try timers.nextDeadline(self.engine);
            const now = Io.Clock.awake.now(self.io).toMilliseconds();
            const delay = if (deadline) |due| @min(@as(i64, 5), @max(@as(i64, 0), due - now)) else 5;
            try self.io.sleep(.fromMilliseconds(delay), .awake);
        }
    }
};
