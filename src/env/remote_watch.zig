//! Owned remote watch subscription, retrying only transport loss.
const std = @import("std");
const adapter = @import("remote_env.zig");
const native = @import("connection.zig");
const watch = @import("../durable/watch.zig");
const types = @import("../durable/types.zig");
pub const Options = struct { mode: ?watch.Mode = null, pollIntervalMs: u64 = 2000, maxDirectories: usize = 10000 };
pub const Watcher = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    connection: adapter.Transport,
    targets: []watch.Target,
    options: Options,
    callback: watch.Callback,
    callback_context: ?*anyopaque,
    mode: std.atomic.Value(watch.Mode) = .init(.native),
    closed: std.atomic.Value(bool) = .init(false),
    mutex: std.Io.Mutex = .init,
    close_mutex: std.Io.Mutex = .init,
    ticket: ?native.Ticket = null,
    thread: ?std.Thread = null,
    worker_id: std.atomic.Value(std.Thread.Id) = .init(0),
    pub fn open(gpa: std.mem.Allocator, io: std.Io, connection: adapter.Transport, targets: []const watch.Target, options: Options, callback: watch.Callback, callback_context: ?*anyopaque) !types.Result(*Watcher) {
        const owned = try gpa.alloc(watch.Target, targets.len);
        var copied: usize = 0;
        errdefer {
            for (owned[0..copied]) |target| freeTarget(gpa, target);
            gpa.free(owned);
        }
        for (targets, owned) |target, *slot| {
            const path = try gpa.dupe(u8, target.path);
            errdefer gpa.free(path);
            const names = try gpa.alloc([]const u8, target.exclude.names.len);
            var count: usize = 0;
            errdefer {
                for (names[0..count]) |name| gpa.free(name);
                gpa.free(names);
            }
            for (target.exclude.names, names) |name, *value| {
                value.* = try gpa.dupe(u8, name);
                count += 1;
            }
            slot.* = .{ .path = path, .recursive = target.recursive, .exclude = .{ .hidden = target.exclude.hidden, .names = names } };
            copied += 1;
        }
        const self = try gpa.create(Watcher);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .connection = connection, .targets = owned, .options = options, .callback = callback, .callback_context = callback_context };
        const ready = try self.start();
        if (ready == .failure) {
            for (owned) |target| freeTarget(gpa, target);
            gpa.free(owned);
            gpa.destroy(self);
            return .{ .failure = ready.failure };
        }
        errdefer {
            self.ticket.?.cancel(false) catch {};
            self.retire();
        }
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        return .{ .value = self };
    }
    fn freeTarget(gpa: std.mem.Allocator, target: watch.Target) void {
        gpa.free(target.path);
        for (target.exclude.names) |name| gpa.free(name);
        gpa.free(target.exclude.names);
    }
    fn deliver(self: *Watcher, change: watch.Change) void {
        if (self.closed.load(.acquire)) return;
        self.callback(self.callback_context, change) catch {};
    }
    fn event(self: *Watcher, json: std.json.Value) !bool {
        const kind = json.object.get("kind") orelse return error.InvalidDaemonJson;
        if (kind != .string) return error.InvalidDaemonJson;
        if (std.mem.eql(u8, kind.string, "ready")) {
            const mode = json.object.get("mode");
            self.mode.store(if (mode != null and mode.? == .string and std.mem.eql(u8, mode.?.string, "polling")) .polling else .native, .release);
            return true;
        }
        if (std.mem.eql(u8, kind.string, "change")) {
            if (json.object.get("mode")) |mode| if (mode == .string and std.mem.eql(u8, mode.string, "polling")) {
                self.mode.store(.polling, .release);
            };
            const overflow = json.object.get("overflow");
            if (overflow != null and overflow.? == .bool and overflow.?.bool) {
                self.deliver(.overflow);
                return false;
            }
            const paths = json.object.get("paths") orelse return error.InvalidDaemonJson;
            if (paths != .array) return error.InvalidDaemonJson;
            const values = try self.gpa.alloc([]const u8, paths.array.items.len);
            defer self.gpa.free(values);
            for (paths.array.items, values) |path, *slot| {
                if (path != .string) return error.InvalidDaemonJson;
                slot.* = path.string;
            }
            self.deliver(.{ .paths = values });
        } else if (std.mem.eql(u8, kind.string, "error")) {
            const code = json.object.get("code");
            const message = json.object.get("message");
            self.deliver(.{ .@"error" = .{ .code = if (code != null and code.? == .string and std.mem.eql(u8, code.?.string, "permission_denied")) .permission_denied else .invalid, .message = if (message != null and message.? == .string) message.?.string else "Invalid remote watch error" } });
            self.closed.store(true, .release);
        }
        return false;
    }
    fn start(self: *Watcher) !types.Result(void) {
        var ticket = try self.connection.begin(.{ .op = "watch", .targets = self.targets, .mode = self.options.mode, .pollIntervalMs = self.options.pollIntervalMs, .maxDirectories = self.options.maxDirectories }, "", null);
        self.mutex.lockUncancelable(self.io);
        self.ticket = ticket;
        self.mutex.unlock(self.io);
        var transferred = false;
        defer if (!transferred) self.retire();
        errdefer ticket.cancel(false) catch {};
        while (true) {
            var record = try ticket.next(60_000);
            defer record.deinit();
            if (record.kind == .remote_error) return adapter.remoteFailure(void, self.gpa, record.json.value, null);
            if (record.kind != .event) return types.failure(void, self.gpa, .unknown, null, null, "Remote watch ended before ready");
            if (try self.event(record.json.value)) {
                transferred = true;
                return .{ .value = {} };
            }
        }
    }
    fn retire(self: *Watcher) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.ticket) |*ticket| ticket.deinit();
        self.ticket = null;
    }
    fn lost(err: anyerror) bool {
        return err == error.ConnectionLost or err == error.DaemonSpawnFailed;
    }
    fn reportError(self: *Watcher, err: anyerror) void {
        self.deliver(.{ .@"error" = .{ .code = .unknown, .message = @errorName(err), .cause = err } });
        self.closed.store(true, .release);
    }
    fn reconnect(self: *Watcher) bool {
        var delay: u64 = 1000;
        while (!self.closed.load(.acquire)) {
            const until = std.Io.Clock.awake.now(self.io).toMilliseconds() + @as(i64, @intCast(delay));
            while (!self.closed.load(.acquire) and std.Io.Clock.awake.now(self.io).toMilliseconds() < until) self.io.sleep(.fromMilliseconds(20), .awake) catch {};
            if (self.closed.load(.acquire)) return false;
            var ready = self.start() catch |err| {
                if (lost(err)) {
                    delay = @min(delay * 2, 30000);
                    continue;
                }
                self.reportError(err);
                return false;
            };
            if (ready == .failure) {
                defer ready.failure.deinit(self.gpa);
                self.deliver(.{ .@"error" = ready.failure });
                self.closed.store(true, .release);
                return false;
            }
            self.deliver(.overflow);
            return true;
        }
        return false;
    }
    fn run(self: *Watcher) void {
        self.worker_id.store(std.Thread.getCurrentId(), .release);
        defer self.worker_id.store(0, .release);
        defer self.retire();
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const ticket = self.ticket.?;
            self.mutex.unlock(self.io);
            var record = ticket.next(100) catch |err| {
                if (err == error.Timeout) continue;
                self.retire();
                if (self.closed.load(.acquire)) return;
                if (lost(err) and self.reconnect()) continue;
                if (!lost(err)) self.reportError(err);
                return;
            };
            defer record.deinit();
            if (record.kind == .event) {
                _ = self.event(record.json.value) catch |err| {
                    self.reportError(err);
                    return;
                };
                continue;
            }
            if (record.kind == .remote_error) {
                var failure = adapter.remoteFailure(void, self.gpa, record.json.value, null) catch |err| {
                    self.reportError(err);
                    return;
                };
                defer failure.failure.deinit(self.gpa);
                self.deliver(.{ .@"error" = failure.failure });
            }
            self.closed.store(true, .release);
            return;
        }
    }
    pub fn close(self: *Watcher, _: types.Context) void {
        self.closed.store(true, .release);
        self.mutex.lockUncancelable(self.io);
        if (self.ticket) |ticket| ticket.cancel(false) catch {};
        self.mutex.unlock(self.io);
        if (self.worker_id.load(.acquire) == std.Thread.getCurrentId()) return;
        self.close_mutex.lockUncancelable(self.io);
        defer self.close_mutex.unlock(self.io);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
    }
    pub fn deinit(self: *Watcher) void {
        std.debug.assert(self.worker_id.load(.acquire) != std.Thread.getCurrentId());
        self.close(.{});
        for (self.targets) |target| freeTarget(self.gpa, target);
        self.gpa.free(self.targets);
        const gpa = self.gpa;
        gpa.destroy(self);
    }
};
