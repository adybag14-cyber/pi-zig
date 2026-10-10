//! Lazy, retryable daemon starts; a new session never adopts old file handles.
const std = @import("std");
const native = @import("connection.zig");
const Io = std.Io;
pub const Command = struct {
    gpa: std.mem.Allocator,
    argv: [][]u8,
    pub fn init(gpa: std.mem.Allocator, arguments: []const []const u8) !Command {
        const argv = try gpa.alloc([]u8, arguments.len);
        var count: usize = 0;
        errdefer {
            for (argv[0..count]) |argument| gpa.free(argument);
            gpa.free(argv);
        }
        for (arguments, argv) |argument, *slot| {
            slot.* = try gpa.dupe(u8, argument);
            count += 1;
        }
        return .{ .gpa = gpa, .argv = argv };
    }
    pub fn deinit(self: *Command) void {
        for (self.argv) |argument| self.gpa.free(argument);
        self.gpa.free(self.argv);
    }
};
pub const PrepareFn = *const fn (?*anyopaque, std.mem.Allocator, Io) anyerror!Command;
pub const Connection = struct {
    gpa: std.mem.Allocator,
    io: Io,
    prepare: PrepareFn,
    context: ?*anyopaque = null,
    mutex: Io.Mutex = .init,
    current: ?*native.Connection = null,
    retired: std.ArrayList(*native.Connection) = .empty,
    session: u64 = 0,
    closed: bool = false,
    last_start_error: ?anyerror = null,
    /// Construction never probes SSH or starts a process. prepare() runs once
    /// for each attempted start, before launch, so it can verify the daemon.
    pub fn init(gpa: std.mem.Allocator, io: Io, prepare: PrepareFn, context: ?*anyopaque) Connection {
        return .{ .gpa = gpa, .io = io, .prepare = prepare, .context = context };
    }
    fn live(connection: *native.Connection) bool {
        connection.mutex.lockUncancelable(connection.io);
        defer connection.mutex.unlock(connection.io);
        return connection.live;
    }
    fn ensure(self: *Connection, expected_session: ?u64) !*native.Connection {
        if (self.closed) return error.ConnectionClosed;
        if (self.current) |current| {
            if (live(current)) {
                if (expected_session != null and expected_session.? != current.session) return error.StaleDaemonSession;
                return current;
            }
            // Failed sessions retain their tickets and records until callers
            // release them. Do not free a Connection behind a borrowed Ticket.
            try self.retired.ensureUnusedCapacity(self.gpa, 1);
            current.stop();
            self.retired.appendAssumeCapacity(current);
            self.current = null;
        }
        if (expected_session != null) return error.StaleDaemonSession;
        if (self.retired.items.len >= 64 or self.session == std.math.maxInt(u64)) return error.ConnectionSessionBudgetExceeded;
        var command = self.prepare(self.context, self.gpa, self.io) catch |err| {
            self.last_start_error = err;
            return error.DaemonSpawnFailed;
        };
        defer command.deinit();
        const next_session = self.session + 1;
        const started = native.Connection.start(self.gpa, self.io, command.argv, next_session) catch |err| {
            self.last_start_error = err;
            return error.DaemonSpawnFailed;
        };
        errdefer started.deinit();
        started.ready(60_000) catch |err| {
            self.last_start_error = err;
            return error.DaemonSpawnFailed;
        };
        self.current = started;
        self.session = next_session;
        self.last_start_error = null;
        return started;
    }
    pub fn begin(self: *Connection, value: anytype, payload: []const u8, expected_session: ?u64) !native.Ticket {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const connection = try self.ensure(expected_session);
        return connection.begin(value, payload, expected_session);
    }
    /// All tickets must be released first, just like a native connection.
    pub fn deinit(self: *Connection) void {
        self.closed = true;
        if (self.current) |current| current.deinit();
        for (self.retired.items) |connection| connection.deinit();
        self.retired.deinit(self.gpa);
    }
};
test "lazy native connection does nothing until requested and retries failed preparation without adopting stale handles" {
    const gpa = std.testing.allocator;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const Probe = struct {
        program: []const u8,
        attempts: usize = 0,
        fn prepare(raw: ?*anyopaque, allocator: std.mem.Allocator, _: Io) !Command {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.attempts += 1;
            if (self.attempts == 1) return error.HostKeyUnknown;
            return Command.init(allocator, &.{self.program});
        }
    };
    var probe: Probe = .{ .program = program };
    var connection = Connection.init(gpa, std.testing.io, Probe.prepare, &probe);
    defer connection.deinit();
    try std.testing.expectEqual(@as(usize, 0), probe.attempts);
    try std.testing.expectError(error.DaemonSpawnFailed, connection.begin(.{ .op = "hello", .protocol = 1 }, "", null));
    try std.testing.expectEqual(@as(?anyerror, error.HostKeyUnknown), connection.last_start_error);
    var first = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    var first_live = true;
    defer if (first_live) first.deinit();
    var result = try first.next(10_000);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), probe.attempts);
    const old_session = first.session;
    connection.current.?.fail(error.ConnectionLost);
    try std.testing.expectError(error.StaleDaemonSession, connection.begin(.{ .op = "close", .handle = 1 }, "", old_session));
    try std.testing.expectEqual(@as(usize, 2), probe.attempts);
    var replacement = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    defer replacement.deinit();
    var ready = try replacement.next(10_000);
    defer ready.deinit();
    try std.testing.expectEqual(@as(usize, 3), probe.attempts);
    try std.testing.expect(replacement.session != old_session);
    // The old ticket is still safe to release after a replacement is live.
    first.deinit();
    first_live = false;
}
