//! Owned RFC6455 worker for the native Codex facade. No JS or provider JSON.
//! One network owner pumps complete frames even while idle. Commands race a
//! non-consuming peek; canceled peeks join before any write or parser mutation.
const std = @import("std");
const socket = @import("../ai/codex_websocket.zig");
const framing = @import("native_ai_codex_frames.zig");
const a = std.heap.page_allocator;
pub const Input = struct {
    url: []const u8,
    headers: []const std.http.Header,
    connect_timeout_ms: u64 = socket.DEFAULT_CONNECT_TIMEOUT_MS,
    proxy_url: ?[]const u8 = null,
};
pub const Event = union(enum) {
    connected,
    sent,
    message: []u8,
    closed: struct { code: u16, reason: []u8, was_clean: bool },
    pub fn deinit(self: Event) void {
        if (self == .message) a.free(self.message);
        if (self == .closed) a.free(self.closed.reason);
    }
};
const Command = union(enum) { send: []u8, read: u64 };
pub const Worker = struct {
    io: std.Io,
    url: []u8,
    headers: []std.http.Header,
    proxy_url: ?[]u8,
    connect_timeout_ms: u64,
    notify_context: ?*anyopaque,
    notify: ?*const fn (?*anyopaque) void,
    abort_flag: bool = false,
    finished: std.atomic.Value(bool) = .init(false),
    failure: ?anyerror = null,
    thread: ?std.Thread = null,
    mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    commands: [16]?Command = @splat(null),
    command_head: usize = 0,
    command_count: usize = 0,
    events: [16]?Event = @splat(null),
    event_head: usize = 0,
    event_count: usize = 0,
    read_deadline_ms: ?i64 = null,

    pub fn create(io: std.Io, input: Input, context: ?*anyopaque, notify: ?*const fn (?*anyopaque) void) !*Worker {
        // std.http performs the RFC6455 HTTP upgrade on http/https; the public
        // WebSocket URL uses the corresponding ws/wss scheme.
        const url = if (std.ascii.startsWithIgnoreCase(input.url, "wss://")) try std.mem.concat(a, u8, &.{ "https://", input.url[6..] }) else if (std.ascii.startsWithIgnoreCase(input.url, "ws://")) try std.mem.concat(a, u8, &.{ "http://", input.url[5..] }) else try a.dupe(u8, input.url);
        errdefer a.free(url);
        const proxy = if (input.proxy_url) |value| try a.dupe(u8, value) else null;
        errdefer if (proxy) |value| a.free(value);
        const headers = try a.alloc(std.http.Header, input.headers.len);
        errdefer a.free(headers);
        var count: usize = 0;
        errdefer for (headers[0..count]) |header| {
            a.free(header.name);
            a.free(header.value);
        };
        for (input.headers, headers) |source, *target| {
            const name = try a.dupe(u8, source.name);
            errdefer a.free(name);
            target.* = .{ .name = name, .value = try a.dupe(u8, source.value) };
            count += 1;
        }
        const self = try a.create(Worker);
        errdefer a.destroy(self);
        self.* = .{ .io = io, .url = url, .headers = headers, .proxy_url = proxy, .connect_timeout_ms = input.connect_timeout_ms, .notify_context = context, .notify = notify };
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return self;
    }
    pub fn cancel(self: *Worker) void {
        @atomicStore(bool, &self.abort_flag, true, .release);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.changed.broadcast(self.io);
    }
    pub fn destroy(self: *Worker) void {
        self.cancel();
        if (self.thread) |thread| thread.join();
        while (self.pop()) |event| event.deinit();
        for (self.commands) |queued_command| if (queued_command) |cmd| if (cmd == .send) {
            a.free(cmd.send);
        };
        for (self.headers) |header| {
            a.free(header.name);
            a.free(header.value);
        }
        a.free(self.headers);
        a.free(self.url);
        if (self.proxy_url) |value| a.free(value);
        a.destroy(self);
    }
    pub fn send(self: *Worker, payload: []const u8) !void {
        const owned = try a.dupe(u8, payload);
        errdefer a.free(owned);
        try self.command(.{ .send = owned });
    }
    pub fn read(self: *Worker, timeout_ms: u64) !void {
        try self.command(.{ .read = timeout_ms });
    }
    fn command(self: *Worker, value: Command) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (@atomicLoad(bool, &self.abort_flag, .acquire) or self.finished.load(.acquire)) return error.WebSocketAborted;
        if (self.command_count == self.commands.len) return error.NativeWebSocketCommandLimit;
        self.commands[(self.command_head + self.command_count) % self.commands.len] = value;
        self.command_count += 1;
        self.changed.broadcast(self.io);
    }
    fn commandAvailable(self: *Worker) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.command_count == 0) {
            if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
            try self.changed.wait(self.io, &self.mutex);
        }
    }
    fn popCommand(self: *Worker) ?Command {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.command_count == 0) return null;
        const value = self.commands[self.command_head].?;
        self.commands[self.command_head] = null;
        self.command_head = (self.command_head + 1) % self.commands.len;
        self.command_count -= 1;
        return value;
    }
    fn push(self: *Worker, event: Event) !void {
        errdefer event.deinit();
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.event_count == self.events.len) {
            if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
            try self.changed.wait(self.io, &self.mutex);
        }
        if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
        self.events[(self.event_head + self.event_count) % self.events.len] = event;
        self.event_count += 1;
        if (self.notify) |notify| notify(self.notify_context);
    }
    pub fn pop(self: *Worker) ?Event {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.event_count == 0) return null;
        const event = self.events[self.event_head].?;
        self.events[self.event_head] = null;
        self.event_head = (self.event_head + 1) % self.events.len;
        self.event_count -= 1;
        self.changed.broadcast(self.io);
        return event;
    }
    fn run(self: *Worker) void {
        self.process() catch |err| {
            self.failure = err;
        };
        self.finished.store(true, .release);
        if (self.notify) |notify| notify(self.notify_context);
    }
    fn process(self: *Worker) !void {
        var connection = try socket.Client.connectWithTimeoutAndAbortProxy(a, self.io, self.url, self.headers, self.connect_timeout_ms, &self.abort_flag, .{ .setting = self.proxy_url });
        defer connection.deinit();
        try self.push(.connected);
        var decoder: framing.Decoder = .{};
        defer decoder.deinit(a);
        var fragments: std.ArrayList(u8) = .empty;
        defer fragments.deinit(a);
        var fragment_opcode: ?socket.Opcode = null;
        while (true) {
            if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
            while (self.popCommand()) |cmd| switch (cmd) {
                .send => |payload| {
                    defer a.free(payload);
                    try self.write(&connection, .text, payload);
                    try self.push(.sent);
                },
                .read => |timeout| {
                    self.read_deadline_ms = if (timeout > 0) std.math.add(i64, std.Io.Clock.awake.now(self.io).toMilliseconds(), @intCast(@min(timeout, @as(u64, @intCast(std.math.maxInt(i64)))))) catch std.math.maxInt(i64) else null;
                },
            };
            const reader = connection.connection.reader();
            const buffered = reader.buffered();
            if (buffered.len > 0) {
                try decoder.append(a, buffered);
                reader.toss(buffered.len);
            }
            while (try decoder.next(a)) |frame| {
                switch (frame.opcode) {
                    .close => {
                        defer a.free(frame.data);
                        if (frame.data.len == 1) return error.WebSocketInvalidCloseFrame;
                        const code: u16 = if (frame.data.len >= 2) std.mem.readInt(u16, frame.data[0..2], .big) else 1005;
                        if (frame.data.len >= 2 and !(code == 1000 or code == 1001 or code == 1002 or code == 1003 or (code >= 1007 and code <= 1014) or (code >= 3000 and code <= 4999))) return error.WebSocketInvalidCloseCode;
                        const reason = if (frame.data.len >= 2) frame.data[2..] else "";
                        if (!std.unicode.utf8ValidateSlice(reason)) return error.WebSocketInvalidCloseReason;
                        const clean = if (self.write(&connection, .close, frame.data)) |_| true else |_| false;
                        try self.push(.{ .closed = .{ .code = code, .reason = try a.dupe(u8, reason), .was_clean = clean } });
                        return;
                    },
                    .ping => {
                        defer a.free(frame.data);
                        try self.write(&connection, .pong, frame.data);
                    },
                    .pong => a.free(frame.data),
                    .text, .binary => {
                        if (fragment_opcode != null) {
                            a.free(frame.data);
                            return error.WebSocketUnexpectedOpcode;
                        }
                        if (frame.fin) {
                            if (frame.opcode == .text and !std.unicode.utf8ValidateSlice(frame.data)) {
                                a.free(frame.data);
                                return error.WebSocketInvalidText;
                            }
                            self.read_deadline_ms = null;
                            try self.push(.{ .message = frame.data });
                        } else {
                            defer a.free(frame.data);
                            fragment_opcode = frame.opcode;
                            try fragments.appendSlice(a, frame.data);
                        }
                    },
                    .continuation => {
                        defer a.free(frame.data);
                        const opcode = fragment_opcode orelse return error.WebSocketUnexpectedOpcode;
                        try fragments.appendSlice(a, frame.data);
                        if (frame.fin) {
                            if (opcode == .text and !std.unicode.utf8ValidateSlice(fragments.items)) return error.WebSocketInvalidText;
                            fragment_opcode = null;
                            self.read_deadline_ms = null;
                            try self.push(.{ .message = try fragments.toOwnedSlice(a) });
                        }
                    },
                    else => {
                        a.free(frame.data);
                        return error.WebSocketUnexpectedOpcode;
                    },
                }
            }
            self.awaitInput(&connection) catch |err| {
                if (err == error.EndOfStream) {
                    try self.push(.{ .closed = .{ .code = 1006, .reason = try a.dupe(u8, ""), .was_clean = false } });
                    return;
                }
                return err;
            };
        }
    }
    fn peek(connection: *socket.Client) !void {
        _ = connection.connection.reader().peekGreedy(1) catch |err| {
            // Io.Reader wraps cancellation and network failures in ReadFailed.
            // Recover the real error so a deliberately canceled peek is not
            // mistaken for a transport failure when a send command wins.
            if (err == error.ReadFailed) return connection.connection.getReadError() orelse err;
            return err;
        };
    }
    fn abortAvailable(self: *Worker) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (!@atomicLoad(bool, &self.abort_flag, .acquire)) try self.changed.wait(self.io, &self.mutex);
    }
    fn writeTask(connection: *socket.Client, opcode: socket.Opcode, payload: []const u8) !void {
        try socket.writeClientFrame(connection.io, connection.connection.writer(), opcode, payload);
        try connection.connection.flush();
    }
    fn write(self: *Worker, connection: *socket.Client, opcode: socket.Opcode, payload: []const u8) !void {
        const Race = union(enum) { sent: anyerror!void, aborted: anyerror!void };
        var queue: [2]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        defer while (select.cancel()) |_| {};
        try select.concurrent(.sent, writeTask, .{ connection, opcode, payload });
        try select.concurrent(.aborted, abortAvailable, .{self});
        switch (try select.await()) {
            .sent => |value| try value,
            .aborted => return error.WebSocketAborted,
        }
    }
    fn deadline(io: std.Io, milliseconds: i64) bool {
        const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(@max(0, milliseconds)), .clock = .awake } };
        timeout.sleep(io) catch return false;
        return true;
    }
    fn awaitInput(self: *Worker, connection: *socket.Client) !void {
        const Race = union(enum) { input: anyerror!void, command: anyerror!void, timeout: bool };
        var queue: [3]Race = undefined;
        var select = std.Io.Select(Race).init(self.io, &queue);
        try select.concurrent(.input, peek, .{connection});
        errdefer while (select.cancel()) |_| {};
        try select.concurrent(.command, commandAvailable, .{self});
        if (self.read_deadline_ms) |expires| try select.concurrent(.timeout, deadline, .{ self.io, expires - std.Io.Clock.awake.now(self.io).toMilliseconds() });
        const winner = try select.await();
        // In particular, the TLS reader is no longer running when a send
        // command is processed. No concurrent cipher-state or writer access.
        var input_failure: ?anyerror = null;
        while (select.cancel()) |completion| switch (completion) {
            .input => |value| value catch |err| {
                if (err != error.Canceled) input_failure = err;
            },
            else => {},
        };
        switch (winner) {
            .input => |value| try value,
            .command => |value| {
                try value;
                if (input_failure) |err| return err;
            },
            .timeout => |expired| if (expired) return error.WebSocketIdleTimeout,
        }
    }
};
