//! Single-flight runtime connection. Shutdown joins the initializing client and retry wait.
const std = @import("std");
const session = @import("session.zig");
const Transport = @import("transport.zig").Transport;
pub const Lease = struct {
    transport: Transport,
    context: *anyopaque,
    destroy: *const fn (*anyopaque) void,
    pub fn deinit(self: Lease) void {
        self.destroy(self.context);
    }
};
pub const Factory = *const fn (?*anyopaque, std.mem.Allocator, std.Io, usize) anyerror!Lease;
pub const Options = struct { factory: Factory, factory_context: ?*anyopaque = null, client: session.Options = .{}, retry_delays_ms: []const u32 = &.{}, is_transient: ?*const fn (?*anyopaque, anyerror) bool = null };
pub const Borrow = struct {
    owner: *Connection,
    client: *session.Client,
    pub fn release(self: Borrow) void {
        self.owner.mutex.lockUncancelable(self.owner.io);
        self.owner.borrowers -= 1;
        self.owner.changed.broadcast(self.owner.io);
        self.owner.mutex.unlock(self.owner.io);
    }
};
pub const State = enum { idle, connecting, ready, failed, closed };
pub const Connection = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    options: Options,
    mutex: std.Io.Mutex = .init,
    close_mutex: std.Io.Mutex = .init,
    changed: std.Io.Condition = .init,
    shutdown: std.atomic.Value(bool) = .init(false),
    state: State = .idle,
    opening: bool = false,
    client: ?*session.Client = null,
    opening_client: ?*session.Client = null,
    lease: ?Lease = null,
    borrowers: usize = 0,
    closing_readers: usize = 0,
    cause: ?anyerror = null,
    attempts: usize = 0,
    pub fn init(gpa: std.mem.Allocator, io: std.Io, options: Options) Connection {
        return .{ .gpa = gpa, .io = io, .options = options };
    }
    pub fn deinit(self: *Connection) void {
        // Failed/reentrant close leaves live callback/Borrow ownership intact;
        // retry destruction from outside the callback after it has retired.
        self.close() catch return;
        if (self.client) |client| client.deinit();
        if (self.lease) |lease| lease.deinit();
        self.* = undefined;
    }
    pub fn connectionState(self: *Connection) State {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.state;
    }
    pub fn acquire(self: *Connection) !Borrow {
        try self.mutex.lock(self.io);
        while (self.opening and !self.shutdown.load(.acquire)) self.changed.wait(self.io, &self.mutex) catch |cause| {
            self.mutex.unlock(self.io);
            return cause;
        };
        if (self.shutdown.load(.acquire)) {
            self.mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        if (self.client) |client| {
            self.borrowers += 1;
            self.mutex.unlock(self.io);
            return .{ .owner = self, .client = client };
        }
        self.opening = true;
        self.state = .connecting;
        self.mutex.unlock(self.io);
        defer {
            self.mutex.lockUncancelable(self.io);
            self.opening = false;
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
        }
        var attempt: usize = 0;
        while (true) : (attempt += 1) {
            if (self.shutdown.load(.acquire)) return error.McpConnectionClosed;
            self.mutex.lockUncancelable(self.io);
            self.attempts += 1;
            self.mutex.unlock(self.io);
            const result = self.openOnce(attempt);
            if (result) |borrow| return borrow else |cause| {
                self.mutex.lockUncancelable(self.io);
                self.cause = cause;
                self.state = if (self.shutdown.load(.acquire)) .closed else .failed;
                self.mutex.unlock(self.io);
                const retry = self.options.is_transient orelse return cause;
                if (self.shutdown.load(.acquire) or attempt >= self.options.retry_delays_ms.len or !retry(self.options.factory_context, cause)) return cause;
                const end = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, self.options.retry_delays_ms[attempt]);
                while (!self.shutdown.load(.acquire) and std.Io.Clock.awake.now(self.io).toMilliseconds() < end) try self.io.sleep(.fromMilliseconds(5), .awake);
                if (self.shutdown.load(.acquire)) return cause;
            }
        }
    }
    fn openOnce(self: *Connection, attempt: usize) !Borrow {
        const lease = try self.options.factory(self.options.factory_context, self.gpa, self.io, attempt);
        errdefer {
            lease.transport.close() catch {};
            lease.deinit();
        }
        const client = try session.Client.create(self.gpa, self.io, lease.transport, self.options.client);
        client.callback_owner = self;
        errdefer client.deinit();
        self.mutex.lockUncancelable(self.io);
        self.opening_client = client;
        self.mutex.unlock(self.io);
        defer {
            self.mutex.lockUncancelable(self.io);
            self.opening_client = null;
            while (self.closing_readers > 0) self.changed.waitUncancelable(self.io, &self.mutex);
            self.mutex.unlock(self.io);
        }
        var initialized = try client.connect();
        initialized.deinit();
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.shutdown.load(.acquire)) return error.McpConnectionClosed;
        self.client = client;
        self.lease = lease;
        self.state = .ready;
        self.cause = null;
        self.borrowers += 1;
        return .{ .owner = self, .client = client };
    }
    pub fn inOwnerCallback(self: *const Connection) bool {
        return session.Client.inOwnerCallback(self);
    }
    /// Reuse stable synchronization storage after every old request/Borrow retires.
    pub fn reset(self: *Connection, options: Options, owner_closing: *const std.atomic.Value(bool)) !void {
        try self.close();
        self.close_mutex.lockUncancelable(self.io);
        defer self.close_mutex.unlock(self.io);
        if (owner_closing.load(.acquire)) return error.McpConnectionClosed;
        self.mutex.lockUncancelable(self.io);
        const client = self.client;
        const lease = self.lease;
        self.client = null;
        self.lease = null;
        self.mutex.unlock(self.io);
        if (client) |value| value.deinit();
        if (lease) |value| value.deinit();
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (owner_closing.load(.acquire)) return error.McpConnectionClosed;
        self.options = options;
        self.state = .idle;
        self.cause = null;
        self.shutdown.store(false, .release);
        self.changed.broadcast(self.io);
    }
    pub fn close(self: *Connection) !void {
        // Consult callback-owned identity before touching this connection's
        // locks or shutdown state. Another closer may already hold close_mutex
        // while waiting for this callback's request/Borrow to retire.
        if (session.Client.inOwnerCallback(self)) return error.ReentrantMcpConnectionClose;
        self.shutdown.store(true, .release);
        self.close_mutex.lockUncancelable(self.io);
        defer self.close_mutex.unlock(self.io);
        self.mutex.lockUncancelable(self.io);
        self.state = .closed;
        const client = self.opening_client orelse self.client;
        if (client != null) self.closing_readers += 1;
        self.changed.broadcast(self.io);
        self.mutex.unlock(self.io);
        if (client) |value| {
            var failure: ?anyerror = null;
            value.close() catch |cause| {
                failure = cause;
            };
            self.mutex.lockUncancelable(self.io);
            self.closing_readers -= 1;
            self.changed.broadcast(self.io);
            self.mutex.unlock(self.io);
            if (failure) |cause| return cause;
        }
        self.mutex.lockUncancelable(self.io);
        while (self.opening or self.borrowers > 0) self.changed.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
    }
};
