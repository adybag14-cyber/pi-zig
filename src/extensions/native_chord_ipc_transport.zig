//! Native child IPC transport. Worker tasks own bytes only; VM callers consume ordered events.
const std = @import("std");
const Io = std.Io;
const records = std.heap.page_allocator;
/// IO tasks notify a leased owner signal; they never touch guest values or run
/// VM callbacks. The caller must join close() before releasing this context.
pub const Wake = struct {
    context: ?*anyopaque = null,
    notify: ?*const fn (?*anyopaque) void = null,
    pub fn signal(self: Wake) void {
        if (self.notify) |notify| notify(self.context);
    }
};
pub const maximum_message = 16 * 1024 * 1024;
pub const maximum_queued = 32 * 1024 * 1024;
pub const Send = struct { ticket: u64, bytes: []u8 };
pub const Event = union(enum) {
    message: []u8,
    sent: struct { ticket: u64, failure: ?anyerror },
    disconnected: ?anyerror,
    pub fn deinit(event: *Event) void {
        if (event.* == .message) records.free(event.message);
        event.* = undefined;
    }
};
pub const Endpoint = struct {
    io: Io,
    wake: Wake = .{},
    stream: Io.net.Stream,
    mutex: Io.Mutex = .init,
    writable: Io.Condition = .init,
    sends: std.ArrayList(Send) = .empty,
    events: std.ArrayList(Event) = .empty,
    sending_bytes: usize = 0,
    receiving_bytes: usize = 0,
    connected: bool = true,
    failure: ?anyerror = null,
    stopping: std.atomic.Value(bool) = .init(false),
    reader: ?Io.Future(anyerror!void) = null,
    writer: ?Io.Future(anyerror!void) = null,
    /// Consumes this exact socket on both success and failure.
    pub fn create(io: Io, stream: Io.net.Stream, wake: Wake) !*Endpoint {
        const self = records.create(Endpoint) catch |err| {
            stream.close(io);
            return err;
        };
        self.* = .{ .io = io, .stream = stream, .wake = wake };
        errdefer self.deinit();
        self.reader = try io.concurrent(read, .{self});
        self.writer = try io.concurrent(write, .{self});
        return self;
    }
    /// The caller keeps JSON serialization on its VM thread. A ticket identifies
    /// the eventual send callback; no function value crosses into an IO task.
    pub fn send(self: *Endpoint, ticket: u64, bytes: []const u8) !bool {
        if (bytes.len > maximum_message) return error.NativeChordIpcMessageTooLarge;
        const owned = try records.dupe(u8, bytes);
        errdefer records.free(owned);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.connected) return error.NativeChordIpcDisconnected;
        if (bytes.len > maximum_queued -| self.sending_bytes) return error.NativeChordIpcQueueLimit;
        try self.sends.append(records, .{ .ticket = ticket, .bytes = owned });
        self.sending_bytes += bytes.len;
        self.writable.signal(self.io);
        return self.sending_bytes < 65536;
    }
    pub fn take(self: *Endpoint) ?Event {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.events.items.len == 0) return null;
        const event = self.events.orderedRemove(0);
        if (event == .message) self.receiving_bytes -= event.message.len;
        return event;
    }
    pub fn isConnected(self: *Endpoint) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.connected;
    }
    /// Available even if disconnected event admission failed. The VM facade
    /// must reject every outstanding ticket on this terminal failure.
    pub fn terminalFailure(self: *Endpoint) ?anyerror {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.failure;
    }
    fn admit(self: *Endpoint, event: Event) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const bytes = if (event == .message) event.message.len else 0;
        if (bytes > maximum_queued -| self.receiving_bytes) return error.NativeChordIpcQueueLimit;
        self.receiving_bytes += bytes;
        errdefer self.receiving_bytes -= bytes;
        try self.events.append(records, event);
        self.wake.signal();
    }
    fn disconnect(self: *Endpoint, failure: ?anyerror) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (!self.connected) {
            if (self.failure == null) self.failure = failure;
            self.wake.signal();
            return;
        }
        self.connected = false;
        self.failure = failure;
        // If event admission itself exhausts memory, the caller still observes
        // connected=false and the retained terminal native failure.
        self.events.append(records, .{ .disconnected = failure }) catch |err| {
            if (self.failure == null) self.failure = err;
        };
        self.writable.signal(self.io);
        self.wake.signal();
    }
    fn read(self: *Endpoint) anyerror!void {
        var buffer: [8192]u8 = undefined;
        var input = self.stream.reader(self.io, &buffer);
        while (!self.stopping.load(.acquire)) {
            const header = input.interface.take(4) catch |err| {
                self.disconnect(if (err == error.EndOfStream) null else err);
                return;
            };
            const length = std.mem.readInt(u32, header[0..4], .big);
            if (length > maximum_message) {
                self.disconnect(error.NativeChordIpcMessageTooLarge);
                return;
            }
            const payload = input.interface.readAlloc(records, length) catch |err| {
                self.disconnect(err);
                return;
            };
            self.admit(.{ .message = payload }) catch |err| {
                records.free(payload);
                self.disconnect(err);
                return;
            };
        }
    }
    fn write(self: *Endpoint) anyerror!void {
        var buffer: [8192]u8 = undefined;
        var output = self.stream.writer(self.io, &buffer);
        while (!self.stopping.load(.acquire)) {
            self.mutex.lockUncancelable(self.io);
            while (self.sends.items.len == 0 and self.connected and !self.stopping.load(.acquire)) {
                self.writable.wait(self.io, &self.mutex) catch |err| {
                    self.mutex.unlock(self.io);
                    return err;
                };
            }
            if (self.sends.items.len == 0) {
                self.mutex.unlock(self.io);
                return;
            }
            const pending = self.sends.orderedRemove(0);
            const connected = self.connected;
            self.mutex.unlock(self.io);
            defer records.free(pending.bytes);
            var header: [4]u8 = undefined;
            std.mem.writeInt(u32, &header, @intCast(pending.bytes.len), .big);
            const completion: ?anyerror = if (!connected) error.NativeChordIpcDisconnected else result: {
                output.interface.writeAll(&header) catch |err| break :result err;
                output.interface.writeAll(pending.bytes) catch |err| break :result err;
                output.interface.flush() catch |err| break :result err;
                break :result null;
            };
            self.mutex.lockUncancelable(self.io);
            self.sending_bytes -= pending.bytes.len;
            self.mutex.unlock(self.io);
            self.admit(.{ .sent = .{ .ticket = pending.ticket, .failure = completion } }) catch |err| {
                self.disconnect(err);
                return;
            };
            if (completion) |err| self.disconnect(err);
        }
    }
    pub fn close(self: *Endpoint) void {
        if (self.stopping.swap(true, .acq_rel)) return;
        self.disconnect(null);
        self.stream.shutdown(self.io, .both) catch {};
        if (self.reader) |*future| _ = future.cancel(self.io) catch {};
        if (self.writer) |*future| _ = future.cancel(self.io) catch {};
        self.reader = null;
        self.writer = null;
        self.stream.close(self.io);
    }
    pub fn deinit(self: *Endpoint) void {
        self.close();
        for (self.sends.items) |pending| records.free(pending.bytes);
        self.sends.deinit(records);
        for (self.events.items) |*event| event.deinit();
        self.events.deinit(records);
        records.destroy(self);
    }
};
