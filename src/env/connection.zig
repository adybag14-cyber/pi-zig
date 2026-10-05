//! Native framed daemon session. Tickets fence handles and own ordered replies.
const std = @import("std");
const builtin = @import("builtin");
const wire = @import("frame.zig");
const ownership = @import("../durable/process_ownership.zig");
const event_wait = @import("event_wait.zig");
const Io = std.Io;
const record_allocator = std.heap.page_allocator;
const Pending = struct {
    records: std.ArrayList(wire.Frame) = .empty,
    bytes: usize = 0,
    terminal: bool = false,
    fn deinit(self: *Pending) void {
        for (self.records.items) |*record| record.deinit();
        self.records.deinit(record_allocator);
    }
};
pub const Ticket = struct {
    connection: *Connection,
    session: u64,
    id: u32,
    pub fn next(self: Ticket, timeout_ms: u64) !wire.Frame {
        return self.connection.next(self, timeout_ms);
    }
    pub fn cancel(self: Ticket, kill: bool) !void {
        try self.connection.send(.cancel, self.id, .{ .mode = if (kill) "kill" else "abort" }, "");
    }
    pub fn deinit(self: *Ticket) void {
        self.connection.release(self.*);
        self.* = undefined;
    }
};
pub const Connection = struct {
    gpa: std.mem.Allocator,
    io: Io,
    child: std.process.Child,
    control: ?ownership.Control = null,
    input: Io.File,
    output: Io.File,
    diagnostics: Io.File,
    token: [32]u8,
    session: u64,
    next_id: u32 = 1,
    mutex: Io.Mutex = .init,
    write_mutex: Io.Mutex = .init,
    wake: Io.Event = .unset,
    pending: std.AutoHashMapUnmanaged(u32, Pending) = .empty,
    unsolicited: Pending = .{},
    buffered: usize = 0,
    live: bool = true,
    synced: bool = false,
    failure: ?anyerror = null,
    last_seen: std.atomic.Value(i64),
    stopping: std.atomic.Value(bool) = .init(false),
    reader: ?Io.Future(anyerror!void) = null,
    logger: ?Io.Future(anyerror!void) = null,
    monitor: ?Io.Future(anyerror!void) = null,
    log: std.ArrayList(u8) = .empty,

    /// The caller advances session across replacement connections. A retained
    /// remote handle must supply the session that originally opened it.
    pub fn start(gpa: std.mem.Allocator, io: Io, command: []const []const u8, session: u64) !*Connection {
        if (command.len == 0 or session == 0) return error.InvalidConnectionCommand;
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        const token = std.fmt.bytesToHex(random, .lower);
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.appendSlice(gpa, command);
        try argv.appendSlice(gpa, &.{ "serve", "--token", &token });
        const self = try gpa.create(Connection);
        errdefer gpa.destroy(self);
        const child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .pipe, .stdout = .pipe, .stderr = .pipe, .create_no_window = true, .start_suspended = builtin.os.tag == .windows, .pgid = if (builtin.os.tag == .windows) null else 0 });
        self.* = .{ .gpa = gpa, .io = io, .child = child, .input = child.stdin.?, .output = child.stdout.?, .diagnostics = child.stderr.?, .token = token, .session = session, .last_seen = .init(Io.Clock.awake.now(io).toMilliseconds()) };
        // The session owns pipe leases; Child cannot close them while readers
        // still have an outstanding syscall during cancellation or teardown.
        self.child.stdin = null;
        self.child.stdout = null;
        self.child.stderr = null;
        errdefer self.cleanup();
        // Own this exact transport process while allowing daemon command
        // lifetimes to follow its own job policy rather than an outer job.
        self.control = try ownership.Control.initWithFlags(&self.child, 0x1c00);
        self.reader = try io.concurrent(read, .{self});
        self.logger = try io.concurrent(readLog, .{self});
        self.monitor = try io.concurrent(heartbeat, .{self});
        return self;
    }
    pub fn fail(self: *Connection, err: anyerror) void {
        self.mutex.lockUncancelable(self.io);
        if (self.live) {
            self.live = false;
            self.failure = err;
        }
        self.mutex.unlock(self.io);
        self.wake.set(self.io);
    }
    pub fn stop(self: *Connection) void {
        if (self.stopping.swap(true, .acq_rel)) return;
        self.fail(error.ConnectionClosed);
        if (self.control) |*control| control.kill();
        self.child.kill(self.io);
        if (self.reader) |*future| _ = future.cancel(self.io) catch {};
        if (self.logger) |*future| _ = future.cancel(self.io) catch {};
        if (self.monitor) |*future| _ = future.cancel(self.io) catch {};
        self.reader = null;
        self.logger = null;
        self.monitor = null;
        self.input.close(self.io);
        self.output.close(self.io);
        self.diagnostics.close(self.io);
        if (self.control) |*control| control.deinit();
        self.control = null;
    }
    fn cleanup(self: *Connection) void {
        self.stop();
        var iterator = self.pending.valueIterator();
        while (iterator.next()) |pending| pending.deinit();
        self.pending.deinit(self.gpa);
        self.unsolicited.deinit();
        self.log.deinit(record_allocator);
    }
    /// Release all tickets before destroying their connection; ticket records
    /// are independent owned frames after next() returns them.
    pub fn deinit(self: *Connection) void {
        self.cleanup();
        self.gpa.destroy(self);
    }
    pub fn diagnosticSnapshot(self: *Connection, gpa: std.mem.Allocator) ![]u8 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return gpa.dupe(u8, self.log.items);
    }
    /// Watch notifications and future protocol-v1 broadcast event kinds retain
    /// their complete owned JSON/payload instead of disappearing as unknown ids.
    pub fn events(self: *Connection) Ticket {
        return .{ .connection = self, .session = self.session, .id = 0 };
    }
    fn send(self: *Connection, kind: wire.Kind, id: u32, value: anytype, payload: []const u8) !void {
        const encoded = try wire.encode(record_allocator, kind, id, value, payload);
        defer record_allocator.free(encoded);
        self.write_mutex.lockUncancelable(self.io);
        defer self.write_mutex.unlock(self.io);
        try self.input.writeStreamingAll(self.io, encoded);
    }
    pub fn begin(self: *Connection, value: anytype, payload: []const u8, expected_session: ?u64) !Ticket {
        try self.ready(60_000);
        self.mutex.lockUncancelable(self.io);
        if (!self.live) {
            self.mutex.unlock(self.io);
            return error.ConnectionLost;
        }
        if (expected_session != null and expected_session.? != self.session) {
            self.mutex.unlock(self.io);
            return error.StaleDaemonSession;
        }
        if (self.pending.count() >= 64 or self.next_id == std.math.maxInt(u32)) {
            self.mutex.unlock(self.io);
            return error.ConnectionRequestBudgetExceeded;
        }
        const id = self.next_id;
        self.pending.putNoClobber(self.gpa, id, .{}) catch |err| {
            self.mutex.unlock(self.io);
            return err;
        };
        self.next_id += 1;
        self.mutex.unlock(self.io);
        const ticket: Ticket = .{ .connection = self, .session = self.session, .id = id };
        self.send(.request, id, value, payload) catch |err| {
            self.release(ticket);
            self.fail(err);
            return err;
        };
        return ticket;
    }
    pub fn ready(self: *Connection, timeout_ms: u64) !void {
        const deadline = Io.Clock.awake.now(self.io).addDuration(.fromMilliseconds(@intCast(@min(timeout_ms, std.math.maxInt(i64)))));
        while (true) {
            self.wake.reset();
            self.mutex.lockUncancelable(self.io);
            const live = self.live;
            const synced = self.synced;
            self.mutex.unlock(self.io);
            if (!live) return error.ConnectionLost;
            if (synced) return;
            try event_wait.wake(self.io, &self.wake, deadline);
        }
    }
    fn next(self: *Connection, ticket: Ticket, timeout_ms: u64) !wire.Frame {
        const deadline = Io.Clock.awake.now(self.io).addDuration(.fromMilliseconds(@intCast(@min(timeout_ms, std.math.maxInt(i64)))));
        while (true) {
            self.wake.reset();
            self.mutex.lockUncancelable(self.io);
            const pending = (if (ticket.id == 0) &self.unsolicited else self.pending.getPtr(ticket.id)) orelse {
                self.mutex.unlock(self.io);
                return error.RequestRetired;
            };
            if (pending.records.items.len != 0) {
                const record = pending.records.orderedRemove(0);
                const size = recordSize(record);
                pending.bytes -= size;
                self.buffered -= size;
                self.mutex.unlock(self.io);
                return record;
            }
            const live = self.live;
            const terminal = pending.terminal;
            self.mutex.unlock(self.io);
            if (!live) return error.ConnectionLost;
            if (terminal) return error.RequestSettled;
            try event_wait.wake(self.io, &self.wake, deadline);
        }
    }
    fn release(self: *Connection, ticket: Ticket) void {
        if (ticket.id == 0) return;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.pending.fetchRemove(ticket.id)) |entry| {
            var pending = entry.value;
            self.buffered -= pending.bytes;
            pending.deinit();
        }
    }
    fn recordSize(record: wire.Frame) usize {
        // Charge serialized JSON as well as payload, plus per-record overhead.
        return record.wire_bytes + 4096;
    }
    fn admit(self: *Connection, incoming: wire.Frame) !void {
        var record = incoming;
        var transferred = false;
        defer if (!transferred) record.deinit();
        if (record.kind == .ping) return;
        if (record.kind != .event and record.kind != .result and record.kind != .remote_error) return error.UnexpectedDaemonFrame;
        if (record.json.value != .object) return error.InvalidDaemonJson;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const pending = (if (record.id == 0 and record.kind == .event) &self.unsolicited else self.pending.getPtr(record.id)) orelse return;
        if (pending.terminal) return error.DuplicateDaemonResult;
        const size = recordSize(record);
        if (self.buffered + size > 64 * 1024 * 1024 or pending.records.items.len >= 256) return error.ConnectionReplyBudgetExceeded;
        try pending.records.append(record_allocator, record);
        pending.terminal = record.kind != .event;
        pending.bytes += size;
        self.buffered += size;
        transferred = true;
        self.wake.set(self.io);
    }
    fn read(self: *Connection) anyerror!void {
        defer self.fail(error.ConnectionLost);
        self.readFrames() catch |err| {
            self.fail(err);
            return err;
        };
    }
    fn readFrames(self: *Connection) !void {
        var sync = try wire.Sync.init(&self.token);
        var decoder = wire.Decoder.init(record_allocator);
        defer decoder.deinit();
        var bytes: [64 * 1024]u8 = undefined;
        var banner_bytes: usize = 0;
        while (!self.stopping.load(.acquire)) {
            const count = self.output.readStreaming(self.io, &.{&bytes}) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return err,
            };
            if (count == 0) return decoder.end();
            self.last_seen.store(Io.Clock.awake.now(self.io).toMilliseconds(), .release);
            var offset: usize = 0;
            if (!sync.ready) {
                offset = sync.receive(bytes[0..count]);
                banner_bytes += offset;
                if (banner_bytes > 1024 * 1024) return error.DaemonBannerTooLarge;
                if (sync.ready) {
                    self.mutex.lockUncancelable(self.io);
                    self.synced = true;
                    self.mutex.unlock(self.io);
                    self.wake.set(self.io);
                }
            }
            while (sync.ready and offset < count) {
                offset += try decoder.receive(bytes[offset..count]);
                if (try decoder.next()) |record| try self.admit(record);
            }
        }
    }
    fn readLog(self: *Connection) anyerror!void {
        var bytes: [4096]u8 = undefined;
        while (!self.stopping.load(.acquire)) {
            const count = self.diagnostics.readStreaming(self.io, &.{&bytes}) catch |err| switch (err) {
                error.EndOfStream => 0,
                else => return err,
            };
            if (count == 0) return;
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            const take = @min(count, 1024 * 1024 -| self.log.items.len);
            try self.log.appendSlice(record_allocator, bytes[0..take]);
        }
    }
    fn heartbeat(self: *Connection) anyerror!void {
        var last_ping = Io.Clock.awake.now(self.io).toMilliseconds();
        const started = last_ping;
        while (!self.stopping.load(.acquire)) {
            try self.io.sleep(.fromMilliseconds(100), .awake);
            const now = Io.Clock.awake.now(self.io).toMilliseconds();
            self.mutex.lockUncancelable(self.io);
            const synced = self.synced;
            self.mutex.unlock(self.io);
            if (!synced) {
                if (now - started < 60_000) continue;
                self.fail(error.DaemonStartTimeout);
                return error.DaemonStartTimeout;
            }
            if (now - self.last_seen.load(.acquire) >= 30_000) {
                self.fail(error.DaemonPeerSilent);
                return error.DaemonPeerSilent;
            }
            if (now - last_ping < 5000) continue;
            self.send(.ping, 0, std.json.Value{ .object = .empty }, "") catch |err| {
                self.fail(err);
                return err;
            };
            last_ping = now;
        }
    }
};
test "native daemon client multiplexes tickets and rejects handles from another session without Node" {
    const gpa = std.testing.allocator;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const connection = try Connection.start(gpa, std.testing.io, &.{program}, 41);
    defer connection.deinit();
    var hello = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", null);
    defer hello.deinit();
    var response = hello.next(10_000) catch |err| {
        const diagnostics = try connection.diagnosticSnapshot(gpa);
        defer gpa.free(diagnostics);
        std.debug.print("Owned daemon diagnostics: {s}\n", .{diagnostics});
        return err;
    };
    defer response.deinit();
    try std.testing.expectEqual(wire.Kind.result, response.kind);
    try std.testing.expectEqual(@as(i64, 1), response.json.value.object.get("protocol").?.integer);
    try std.testing.expectEqual(@as(u64, 41), hello.session);
    try std.testing.expectError(error.RequestSettled, hello.next(10));
    try std.testing.expectError(error.StaleDaemonSession, connection.begin(.{ .op = "close", .handle = 1 }, "", 40));
    var first = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", 41);
    defer first.deinit();
    var second = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", 41);
    defer second.deinit();
    var second_reply = try second.next(10_000);
    defer second_reply.deinit();
    var first_reply = try first.next(10_000);
    defer first_reply.deinit();
    try std.testing.expectEqual(second.id, second_reply.id);
    try std.testing.expectEqual(first.id, first_reply.id);
    try std.testing.expect(first.id != second.id);
    var malformed = try connection.begin(.{ .op = "hello", .protocol = 2 }, "", 41);
    defer malformed.deinit();
    var rejected = try malformed.next(10_000);
    defer rejected.deinit();
    try std.testing.expectEqual(wire.Kind.remote_error, rejected.kind);
    try std.testing.expectEqualStrings("EINVAL", rejected.json.value.object.get("code").?.string);
}
test "native client streams Unicode nonzero output and cancels an entered process while serving other requests" {
    const gpa = std.testing.allocator;
    var environ = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ.deinit();
    const program = environ.get("PI_TEST_ENV_DAEMON") orelse return error.SkipZigTest;
    const fixture = environ.get("PI_TEST_SSH_FIXTURE") orelse return error.SkipZigTest;
    const connection = try Connection.start(gpa, std.testing.io, &.{program}, 42);
    defer connection.deinit();
    var ticket = try connection.begin(.{ .op = "exec", .argv = &[_][]const u8{ fixture, "unicode" } }, "", null);
    defer ticket.deinit();
    var stdout: std.ArrayList(u8) = .empty;
    defer stdout.deinit(gpa);
    var stderr: std.ArrayList(u8) = .empty;
    defer stderr.deinit(gpa);
    while (true) {
        var record = try ticket.next(10_000);
        defer record.deinit();
        if (record.kind == .event) {
            const stream = record.json.value.object.get("stream").?.string;
            if (std.mem.eql(u8, stream, "stdout")) try stdout.appendSlice(gpa, record.payload) else try stderr.appendSlice(gpa, record.payload);
        } else {
            try std.testing.expectEqual(wire.Kind.result, record.kind);
            try std.testing.expectEqual(@as(i64, 37), record.json.value.object.get("exitCode").?.integer);
            break;
        }
    }
    try std.testing.expectEqualStrings("Ω🦊\n", stdout.items);
    try std.testing.expectEqualStrings("owned-error\n", stderr.items);
    var waiting = try connection.begin(.{ .op = "exec", .argv = &[_][]const u8{ fixture, "tick" } }, "", 42);
    defer waiting.deinit();
    var entered = try waiting.next(10_000);
    defer entered.deinit();
    try std.testing.expectEqual(wire.Kind.event, entered.kind);
    try std.testing.expectEqualStrings("producer-entered\n", entered.payload);
    var alive = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", 42);
    defer alive.deinit();
    var alive_reply = try alive.next(2000);
    defer alive_reply.deinit();
    try std.testing.expectEqual(wire.Kind.result, alive_reply.kind);
    try waiting.cancel(false);
    while (true) {
        var final = try waiting.next(10_000);
        defer final.deinit();
        if (final.kind == .event) continue;
        try std.testing.expectEqual(wire.Kind.remote_error, final.kind);
        try std.testing.expectEqualStrings("aborted", final.json.value.object.get("code").?.string);
        break;
    }
    var reuse = try connection.begin(.{ .op = "hello", .protocol = 1 }, "", 42);
    defer reuse.deinit();
    var reused = try reuse.next(2000);
    defer reused.deinit();
    try std.testing.expectEqual(wire.Kind.result, reused.kind);
}
