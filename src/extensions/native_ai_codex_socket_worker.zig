//! Owned RFC6455 worker for the native Codex facade. No JS or provider JSON.
//! The owner requests one read at a time, so a completed response leaves the
//! connection idle without canceling a read or consuming the next turn's frame.
const std = @import("std");
const socket = @import("../ai/codex_websocket.zig");
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
    pub fn deinit(self: Event) void {
        if (self == .message) a.free(self.message);
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

    pub fn create(io: std.Io, input: Input, context: ?*anyopaque, notify: ?*const fn (?*anyopaque) void) !*Worker {
        const url = try a.dupe(u8, input.url);
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
    fn nextCommand(self: *Worker) !Command {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        while (self.command_count == 0) {
            if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
            try self.changed.wait(self.io, &self.mutex);
        }
        if (@atomicLoad(bool, &self.abort_flag, .acquire)) return error.WebSocketAborted;
        const command_value = self.commands[self.command_head].?;
        self.commands[self.command_head] = null;
        self.command_head = (self.command_head + 1) % self.commands.len;
        self.command_count -= 1;
        return command_value;
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
        while (true) {
            const cmd = try self.nextCommand();
            switch (cmd) {
                .send => |payload| {
                    defer a.free(payload);
                    try connection.sendText(payload);
                    try self.push(.sent);
                },
                .read => |timeout| {
                    const frame = try connection.readMessageWithControl(a, timeout, &self.abort_flag);
                    try self.push(.{ .message = frame.data });
                },
            }
        }
    }
};
