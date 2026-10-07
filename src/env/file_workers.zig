//! Sixteen bounded filesystem workers, with writeChunk arrival-order lanes.
const std = @import("std");
const files = @import("files.zig");
const transport = @import("daemon_input.zig");
const output = @import("daemon_output.zig");
const Io = std.Io;
const gpa = std.heap.page_allocator;
pub const workers = 16;
const Job = struct { pending: *transport.Pending, lane: ?u64 };
pub const Pool = struct {
    io: Io,
    input: *transport.Input,
    output: *output.Output,
    server: *files.Server,
    mutex: Io.Mutex = .init,
    ready: Io.Condition = .init,
    jobs: std.ArrayList(Job) = .empty,
    active: std.AutoHashMapUnmanaged(u64, void) = .empty,
    group: Io.Group = .init,
    stopping: bool = false,
    failure: ?anyerror = null,
    pub fn start(self: *Pool) !void {
        try self.jobs.ensureTotalCapacity(gpa, 64);
        errdefer self.jobs.deinit(gpa);
        try self.active.ensureTotalCapacity(gpa, workers);
        errdefer self.active.deinit(gpa);
        errdefer self.group.cancel(self.io);
        for (0..workers) |_| try self.group.concurrent(self.io, run, .{self});
    }
    pub fn enqueue(self: *Pool, pending: *transport.Pending) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.stopping) return error.FileWorkersStopped;
        if (self.failure) |err| return err;
        if (self.jobs.items.len >= 64) return error.FileWorkerQueueFull;
        const json = pending.frame.json.value;
        const op = if (json == .object) json.object.get("op") else null;
        const handle = if (json == .object) json.object.get("handle") else null;
        const lane = if (op != null and op.? == .string and std.mem.eql(u8, op.?.string, "writeChunk") and handle != null and handle.? == .integer and handle.?.integer >= 0) @as(?u64, @intCast(handle.?.integer)) else null;
        self.jobs.appendAssumeCapacity(.{ .pending = pending, .lane = lane });
        self.ready.broadcast(self.io);
    }
    fn next(self: *Pool) !?Job {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);
        while (!self.stopping) {
            for (self.jobs.items, 0..) |job, index| {
                if (job.lane) |lane| if (self.active.contains(lane)) continue;
                if (job.lane) |lane| self.active.putAssumeCapacityNoClobber(lane, {});
                return self.jobs.orderedRemove(index);
            }
            try self.ready.wait(self.io, &self.mutex);
        }
        return null;
    }
    fn finish(self: *Pool, job: Job) void {
        self.mutex.lockUncancelable(self.io);
        if (job.lane) |lane| _ = self.active.remove(lane);
        self.ready.broadcast(self.io);
        self.mutex.unlock(self.io);
        self.input.complete(job.pending);
    }
    fn respond(self: *Pool, job: Job) !void {
        const request = job.pending.frame;
        const json = request.json.value;
        const op = if (json == .object) json.object.get("op") else null;
        const is_scan = op != null and op.? == .string and std.mem.eql(u8, op.?.string, "scanLines");
        var reply = try self.server.dispatch(json, request.payload, .{ .abort_flag = if (is_scan) &job.pending.aborted else null });
        defer reply.deinit();
        try self.output.sendJson(reply.kind, request.id, reply.json, reply.payload);
    }
    fn run(self: *Pool) void {
        while (self.next() catch return) |job| {
            defer self.finish(job);
            self.respond(job) catch |err| {
                if (err == error.Canceled) return;
                self.output.send(.remote_error, job.pending.frame.id, .{ .code = "EIO", .message = @errorName(err) }, "") catch {};
                self.mutex.lockUncancelable(self.io);
                self.failure = err;
                self.mutex.unlock(self.io);
            };
        }
    }
    pub fn deinit(self: *Pool) void {
        self.mutex.lockUncancelable(self.io);
        self.stopping = true;
        self.ready.broadcast(self.io);
        self.mutex.unlock(self.io);
        self.group.cancel(self.io);
        // Registered records belong to Input until completion, even on EOF.
        for (self.jobs.items) |job| self.input.complete(job.pending);
        self.jobs.deinit(gpa);
        self.active.deinit(gpa);
    }
};
