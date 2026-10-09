//! Owned discovery DTOs are produced off-thread and claimed once on the service line.
const std = @import("std");
const json = @import("protocol.zig").json;
pub const Fetch = *const fn (*anyopaque) anyerror!json.Owned;
pub const Delivery = struct { context: *anyopaque, value: ?json.Owned, cause: ?anyerror };
const Job = struct {
    owner: *Pool,
    context: *anyopaque,
    fetch: Fetch,
    direct: bool,
    ready: std.Io.Event = .unset,
    complete: bool = false,
    claimed: bool = false,
    value: ?json.Owned = null,
    cause: ?anyerror = null,
    retirement_mutex: std.Io.Mutex = .init,
    future: ?std.Io.Future(void) = null,
    fn retire(self: *Job) void {
        self.retirement_mutex.lockUncancelable(self.owner.io);
        defer self.retirement_mutex.unlock(self.owner.io);
        if (self.future) |*future| {
            future.cancel(self.owner.io);
            self.future = null;
        }
    }
    fn run(self: *Job) void {
        const fetched = self.fetch(self.context);
        self.owner.mutex.lockUncancelable(self.owner.io);
        if (fetched) |value| self.value = value else |cause| self.cause = cause;
        self.complete = true;
        self.owner.mutex.unlock(self.owner.io);
        self.ready.set(self.owner.io);
        if (self.owner.on_ready) |notify| notify(self.owner.ready_context);
    }
};
pub const Pool = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    jobs: std.ArrayList(*Job) = .empty,
    closed: bool = false,
    active_waiters: usize = 0,
    retired: std.Io.Condition = .init,
    ready_context: ?*anyopaque = null,
    on_ready: ?*const fn (?*anyopaque) void = null,
    pub fn add(self: *Pool, context: *anyopaque, fetch: Fetch, direct: bool) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.McpConnectionClosed;
        const job = try self.gpa.create(Job);
        errdefer self.gpa.destroy(job);
        job.* = .{ .owner = self, .context = context, .fetch = fetch, .direct = direct };
        try self.jobs.append(self.gpa, job);
        errdefer _ = self.jobs.pop();
        job.future = try self.io.concurrent(Job.run, .{job});
    }
    pub fn takeReady(self: *Pool) ?Delivery {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.jobs.items) |job| if (job.complete and !job.claimed) {
            job.claimed = true;
            const result: Delivery = .{ .context = job.context, .value = job.value, .cause = job.cause };
            job.value = null;
            return result;
        };
        return null;
    }
    pub fn wait(self: *Pool, direct_only: bool, timeout: std.Io.Timeout) !bool {
        return self.waitSelection(null, direct_only, timeout, null);
    }
    pub fn waitContext(self: *Pool, context: *anyopaque, timeout: std.Io.Timeout) !bool {
        return self.waitSelection(context, false, timeout, null);
    }
    pub fn waitAbort(self: *Pool, flag: ?*const bool) !bool {
        return self.waitSelection(null, false, .none, flag);
    }
    pub fn waitContextAbort(self: *Pool, context: *anyopaque, flag: ?*const bool) !bool {
        return self.waitSelection(context, false, .none, flag);
    }
    fn waitSelection(self: *Pool, context: ?*anyopaque, direct_only: bool, timeout: std.Io.Timeout, flag: ?*const bool) !bool {
        try self.mutex.lock(self.io);
        if (self.closed) {
            self.mutex.unlock(self.io);
            return error.McpConnectionClosed;
        }
        self.active_waiters += 1;
        self.retired.broadcast(self.io);
        self.mutex.unlock(self.io);
        defer {
            self.mutex.lockUncancelable(self.io);
            self.active_waiters -= 1;
            self.retired.broadcast(self.io);
            self.mutex.unlock(self.io);
        }
        const deadline = timeout.toDeadline(self.io);
        var index: usize = 0;
        while (true) : (index += 1) {
            try self.mutex.lock(self.io);
            if (self.closed) {
                self.mutex.unlock(self.io);
                return error.McpConnectionClosed;
            }
            if (index == self.jobs.items.len) {
                self.mutex.unlock(self.io);
                return true;
            }
            const job = self.jobs.items[index];
            const selected = (!direct_only or job.direct) and (context == null or job.context == context.?);
            self.mutex.unlock(self.io);
            if (!selected) continue;
            while (true) {
                if (flag) |aborted| if (@atomicLoad(bool, aborted, .acquire)) return error.Canceled;
                const observed_timeout = if (flag != null) blk: {
                    const remaining = deadline.toDurationFromNow(self.io);
                    if (remaining) |duration| if (duration.raw.nanoseconds <= 0) return false;
                    const nanos: i96 = if (remaining) |duration| @min(duration.raw.nanoseconds, 5 * std.time.ns_per_ms) else 5 * std.time.ns_per_ms;
                    break :blk std.Io.Timeout{ .duration = .{ .raw = .{ .nanoseconds = nanos }, .clock = .awake } };
                } else deadline;
                job.ready.waitTimeout(self.io, observed_timeout) catch |cause| switch (cause) {
                    error.Timeout => {
                        if (flag != null and deadline == .none) continue;
                        if (deadline.toDurationFromNow(self.io)) |remaining| if (remaining.raw.nanoseconds > 0) continue;
                        return false;
                    },
                    else => return cause,
                };
                break;
            }
        }
    }
    /// Retire only this exact server's producer before replacing its connection.
    pub fn retireContext(self: *Pool, context: *anyopaque) void {
        var index: usize = 0;
        while (true) : (index += 1) {
            self.mutex.lockUncancelable(self.io);
            if (index == self.jobs.items.len) {
                self.mutex.unlock(self.io);
                break;
            }
            const job = self.jobs.items[index];
            const selected = job.context == context;
            if (selected) job.claimed = true;
            self.mutex.unlock(self.io);
            if (!selected) continue;
            job.retire();
            self.mutex.lockUncancelable(self.io);
            if (job.value) |*value| value.deinit();
            job.value = null;
            self.mutex.unlock(self.io);
        }
    }
    pub fn close(self: *Pool) void {
        self.mutex.lockUncancelable(self.io);
        self.closed = true;
        self.mutex.unlock(self.io);
        for (self.jobs.items) |job| job.retire();
        self.mutex.lockUncancelable(self.io);
        while (self.active_waiters != 0) self.retired.waitUncancelable(self.io, &self.mutex);
        self.mutex.unlock(self.io);
    }
    /// The service stops admission and retires its caller leases before destruction.
    pub fn deinit(self: *Pool) void {
        self.close();
        for (self.jobs.items) |job| {
            if (job.value) |*value| value.deinit();
            self.gpa.destroy(job);
        }
        self.jobs.deinit(self.gpa);
        self.* = undefined;
    }
};

test "MCP startup pool publishes owned DTOs once while non-direct discovery stays pending" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const Worker = struct {
        gpa: std.mem.Allocator,
        io: std.Io,
        entered: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        fn fetch(raw: *anyopaque) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.entered.set(self.io);
            try self.release.wait(self.io);
            return json.Owned.parse(self.gpa, "{\"owned\":true}");
        }
    };
    var pool: Pool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    var worker: Worker = .{ .gpa = gpa, .io = io };
    defer worker.release.set(io);
    try pool.add(&worker, Worker.fetch, false);
    try worker.entered.wait(io);
    try std.testing.expect(try pool.wait(true, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } }));
    try std.testing.expect(pool.takeReady() == null);
    try std.testing.expect(!try pool.wait(false, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } }));
    worker.release.set(io);
    try std.testing.expect(try pool.wait(false, .none));
    var delivered = pool.takeReady().?;
    defer if (delivered.value) |*value| value.deinit();
    try std.testing.expect(delivered.cause == null);
    try std.testing.expect(delivered.value.?.value.object.get("owned").?.bool);
    try std.testing.expect(pool.takeReady() == null);
}

fn word(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
/// Matches upstream's deliberately textual regexp/includes check, including comments and strings.
pub fn scriptNeedsServer(gpa: std.mem.Allocator, code: []const u8, server: []const u8) !bool {
    for ([_][]const u8{ "searchTools", "describeNamespace", "describeTool", "ALL_TOOLS" }) |name| {
        var start: usize = 0;
        while (std.mem.indexOfPos(u8, code, start, name)) |index| {
            const end = index + name.len;
            if ((index == 0 or !word(code[index - 1])) and (end == code.len or !word(code[end]))) return true;
            start = end;
        }
    }
    const namespace = try std.fmt.allocPrint(gpa, "mcp__{s}", .{server});
    defer gpa.free(namespace);
    for (namespace) |*byte| if (byte.* == '-') {
        byte.* = '_';
    };
    return std.mem.indexOf(u8, code, namespace) != null;
}

test "MCP startup script waits replay original textual helper including strings comments and ASCII boundaries" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("fixtures/mcp-script-needs-original-6fb.json"));
    defer fixture.deinit();
    for (fixture.value.object.get("rows").?.array.items) |row| try std.testing.expectEqual(row.object.get("needed").?.bool, try scriptNeedsServer(gpa, row.object.get("code").?.string, row.object.get("server").?.string));
}

test "MCP startup retirement cancels one exact server and preserves another producer" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const Worker = struct {
        gpa: std.mem.Allocator,
        io: std.Io,
        entered: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        cleaned: std.atomic.Value(bool) = .init(false),
        fn fetch(raw: *anyopaque) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw));
            defer self.cleaned.store(true, .release);
            self.entered.set(self.io);
            try self.release.wait(self.io);
            return json.Owned.parse(self.gpa, "{\"ready\":true}");
        }
    };
    var pool: Pool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    var a: Worker = .{ .gpa = gpa, .io = io };
    var b: Worker = .{ .gpa = gpa, .io = io };
    defer {
        a.release.set(io);
        b.release.set(io);
    }
    try pool.add(&a, Worker.fetch, true);
    try pool.add(&b, Worker.fetch, false);
    try a.entered.wait(io);
    try b.entered.wait(io);
    pool.retireContext(&a);
    try std.testing.expect(a.cleaned.load(.acquire));
    try std.testing.expect(!b.cleaned.load(.acquire));
    try std.testing.expect(pool.takeReady() == null);
    b.release.set(io);
    try std.testing.expect(try pool.wait(false, .none));
    var result = pool.takeReady().?;
    defer if (result.value) |*value| value.deinit();
    try std.testing.expect(result.context == @as(*anyopaque, @ptrCast(&b)));
    try std.testing.expect(result.cause == null);
    try std.testing.expect(pool.takeReady() == null);
}

test "MCP startup allocation failures release producer admission result and retirement ownership" {
    const Sweep = struct {
        fn run(gpa: std.mem.Allocator) !void {
            const Worker = struct {
                gpa: std.mem.Allocator,
                fn fetch(raw: *anyopaque) !json.Owned {
                    const self: *@This() = @ptrCast(@alignCast(raw));
                    return json.Owned.parse(self.gpa, "{\"tools\":[{\"name\":\"one\",\"inputSchema\":{\"type\":\"object\",\"properties\":{\"arg\":{\"type\":\"string\"}}}}]}");
                }
            };
            var pool: Pool = .{ .gpa = gpa, .io = std.testing.io };
            defer pool.deinit();
            var worker: Worker = .{ .gpa = gpa };
            try pool.add(&worker, Worker.fetch, true);
            _ = try pool.wait(false, .none);
            var result = pool.takeReady().?;
            defer if (result.value) |*value| value.deinit();
            if (result.cause) |cause| return cause;
            try std.testing.expect(result.value.?.value.object.get("tools").?.array.items.len == 1);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Sweep.run, .{});
}

test "MCP startup canceling a selected wait preserves the exact background producer" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const Worker = struct {
        io: std.Io,
        gpa: std.mem.Allocator,
        entered: std.Io.Event = .unset,
        release: std.Io.Event = .unset,
        cleaned: std.atomic.Value(bool) = .init(false),
        fn fetch(raw: *anyopaque) !json.Owned {
            const self: *@This() = @ptrCast(@alignCast(raw));
            defer self.cleaned.store(true, .release);
            self.entered.set(self.io);
            try self.release.wait(self.io);
            return json.Owned.parse(self.gpa, "{\"ready\":true}");
        }
    };
    var pool: Pool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    var worker: Worker = .{ .io = io, .gpa = gpa };
    defer worker.release.set(io);
    try pool.add(&worker, Worker.fetch, false);
    try worker.entered.wait(io);
    var aborted = false;
    var waiting = try io.concurrent(Pool.waitContextAbort, .{ &pool, @as(*anyopaque, @ptrCast(&worker)), @as(?*const bool, &aborted) });
    var joined = false;
    defer {
        if (!joined) _ = waiting.cancel(io) catch {};
    }
    pool.mutex.lockUncancelable(io);
    while (pool.active_waiters == 0) pool.retired.waitUncancelable(io, &pool.mutex);
    pool.mutex.unlock(io);
    @atomicStore(bool, &aborted, true, .release);
    try std.testing.expectError(error.Canceled, waiting.await(io));
    joined = true;
    try std.testing.expect(!worker.cleaned.load(.acquire));
    try std.testing.expect(pool.takeReady() == null);
    worker.release.set(io);
    try std.testing.expect(try pool.wait(false, .none));
    var result = pool.takeReady().?;
    defer if (result.value) |*value| value.deinit();
    try std.testing.expect(result.cause == null);
}
