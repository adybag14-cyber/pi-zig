//! Persistent framed input owner, registered cancellation, and byte liveness.
const std = @import("std");
const wire = @import("frame.zig");
const Io = std.Io;
pub const Pending = struct {
    frame: wire.Frame,
    aborted: std.atomic.Value(bool) = .init(false),
    killed: std.atomic.Value(bool) = .init(false),
    wire_bytes: usize = 0,
};
pub const Event = union(enum) { request: *Pending, tick, ended };
pub const Input = struct {
    io: Io,
    file: Io.File,
    mutex: Io.Mutex = .init,
    wake: Io.Event = .unset,
    requests: std.ArrayList(*Pending) = .empty,
    registered: std.AutoHashMapUnmanaged(u32, *Pending) = .empty,
    bytes: usize = 0,
    finished: bool = false,
    failure: ?anyerror = null,
    last_seen: std.atomic.Value(i64),
    stopping: std.atomic.Value(bool) = .init(false),
    reader: ?Io.Future(anyerror!void) = null,
    timer: ?Io.Future(anyerror!void) = null,
    const gpa = std.heap.page_allocator;
    pub fn init(io: Io, file: Io.File) Input {
        return .{ .io = io, .file = file, .last_seen = .init(Io.Clock.awake.now(io).toMilliseconds()) };
    }
    pub fn start(self: *Input) !void {
        self.reader = try self.io.concurrent(read, .{self});
        errdefer self.stop();
        self.timer = try self.io.concurrent(monitor, .{self});
    }
    pub fn stop(self: *Input) void {
        if (!self.stopping.swap(true, .acq_rel)) self.file.close(self.io);
        self.wake.set(self.io);
        if (self.reader) |*future| _ = future.cancel(self.io) catch {};
        if (self.timer) |*future| _ = future.cancel(self.io) catch {};
        self.reader = null;
        self.timer = null;
    }
    pub fn deinit(self: *Input) void {
        self.stop();
        var iterator = self.registered.valueIterator();
        while (iterator.next()) |pending| {
            pending.*.frame.deinit();
            gpa.destroy(pending.*);
        }
        self.registered.deinit(gpa);
        self.requests.deinit(gpa);
    }
    fn exact(self: *Input, bytes: []u8) !usize {
        var count: usize = 0;
        while (count < bytes.len) {
            var buffers = [_][]u8{bytes[count..]};
            const size = try self.file.readStreaming(self.io, &buffers);
            if (size == 0) break;
            count += size;
            self.last_seen.store(Io.Clock.awake.now(self.io).toMilliseconds(), .release);
        }
        return count;
    }
    fn read(self: *Input) anyerror!void {
        defer {
            self.mutex.lockUncancelable(self.io);
            self.finished = true;
            var iterator = self.registered.valueIterator();
            while (iterator.next()) |pending| pending.*.aborted.store(true, .release);
            self.mutex.unlock(self.io);
            self.wake.set(self.io);
        }
        self.readFrames() catch |err| {
            self.mutex.lockUncancelable(self.io);
            self.failure = err;
            self.mutex.unlock(self.io);
            return err;
        };
    }
    fn readFrames(self: *Input) !void {
        while (!self.stopping.load(.acquire)) {
            var prefix: [4]u8 = undefined;
            const size = try self.exact(&prefix);
            if (size == 0) return;
            if (size != 4) return error.TruncatedFrame;
            const length = std.mem.readInt(u32, &prefix, .big);
            if (length < 9 or length > wire.maximum_frame) return error.InvalidFrameLength;
            const encoded = try gpa.alloc(u8, 4 + @as(usize, length));
            defer gpa.free(encoded);
            @memcpy(encoded[0..4], &prefix);
            if (try self.exact(encoded[4..]) != length) return error.TruncatedFrame;
            var frame = try wire.decode(gpa, encoded);
            var transferred = false;
            defer if (!transferred) frame.deinit();
            if (frame.kind == .ping) continue;
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            if (frame.kind == .cancel) {
                if (self.registered.get(frame.id)) |pending| {
                    const mode = if (frame.json.value == .object) frame.json.value.object.get("mode") else null;
                    if (mode != null and mode.? == .string and std.mem.eql(u8, mode.?.string, "kill")) pending.killed.store(true, .release) else pending.aborted.store(true, .release);
                }
                continue;
            }
            if (frame.kind != .request) continue;
            if (self.registered.contains(frame.id) or self.registered.count() >= 64 or self.bytes + encoded.len > 64 * 1024 * 1024) return error.DaemonRequestBudgetExceeded;
            const pending = try gpa.create(Pending);
            errdefer gpa.destroy(pending);
            try self.registered.ensureUnusedCapacity(gpa, 1);
            try self.requests.ensureUnusedCapacity(gpa, 1);
            pending.* = .{ .frame = frame, .wire_bytes = encoded.len };
            self.registered.putAssumeCapacityNoClobber(frame.id, pending);
            self.requests.appendAssumeCapacity(pending);
            self.bytes += encoded.len;
            transferred = true;
            self.wake.set(self.io);
        }
    }
    fn monitor(self: *Input) anyerror!void {
        while (!self.stopping.load(.acquire)) {
            try self.io.sleep(.fromMilliseconds(100), .awake);
            if (Io.Clock.awake.now(self.io).toMilliseconds() - self.last_seen.load(.acquire) < 30_000) continue;
            self.mutex.lockUncancelable(self.io);
            var iterator = self.registered.valueIterator();
            while (iterator.next()) |pending| pending.*.aborted.store(true, .release);
            self.failure = error.DaemonPeerSilent;
            self.finished = true;
            self.mutex.unlock(self.io);
            if (!self.stopping.swap(true, .acq_rel)) self.file.close(self.io);
            self.wake.set(self.io);
        }
    }
    pub fn next(self: *Input) !Event {
        while (true) {
            self.wake.reset();
            self.mutex.lockUncancelable(self.io);
            if (self.requests.items.len > 0) {
                const pending = self.requests.orderedRemove(0);
                self.mutex.unlock(self.io);
                return .{ .request = pending };
            }
            const finished = self.finished;
            const failure = self.failure;
            self.mutex.unlock(self.io);
            if (finished) {
                if (failure) |err| return err;
                return .ended;
            }
            self.wake.waitTimeout(self.io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } }) catch |err| switch (err) {
                error.Timeout => return .tick,
                else => return err,
            };
        }
    }
    pub fn complete(self: *Input, pending: *Pending) void {
        self.mutex.lockUncancelable(self.io);
        _ = self.registered.remove(pending.frame.id);
        self.bytes -= pending.wire_bytes;
        self.mutex.unlock(self.io);
        pending.frame.deinit();
        gpa.destroy(pending);
    }
};
