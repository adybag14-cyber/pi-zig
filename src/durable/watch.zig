//! Portable snapshot watches. Polling is explicit; no fabricated native events.
const std = @import("std");
const types = @import("types.zig");
const filesystem = @import("filesystem.zig");
const builtin = @import("builtin");
const native = if (builtin.os.tag == .windows) @import("watch_windows.zig") else if (builtin.os.tag == .macos) @import("watch_macos.zig") else @import("watch_linux.zig");
const native_supported = builtin.os.tag == .linux or builtin.os.tag == .windows or builtin.os.tag == .macos;
const identity = @import("watch_identity.zig");
pub const Mode = enum(u8) { native, polling };
pub const Exclude = struct { hidden: bool = false, names: []const []const u8 = &.{} };
pub const Target = struct { path: []const u8, recursive: bool = false, exclude: Exclude = .{} };
pub const Options = struct { mode: ?Mode = null, pollIntervalMs: u64 = 2000, maxDirectories: usize = 10000, maxEntries: usize = 100000 };
pub const Change = union(enum) { paths: []const []const u8, overflow, @"error": types.FileError };
/// This native callback runs on the owned polling thread. A language-runtime
/// adapter must queue delivery to its context's owning thread.
pub const Callback = *const fn (?*anyopaque, Change) anyerror!void;
const Resolved = struct {
    path: []u8,
    recursive: bool,
    hidden: bool,
    names: [][]u8,
    fn deinit(self: *Resolved, gpa: std.mem.Allocator) void {
        gpa.free(self.path);
        for (self.names) |name| gpa.free(name);
        gpa.free(self.names);
    }
    fn excluded(self: Resolved, name: []const u8) bool {
        if (self.hidden and std.mem.startsWith(u8, name, ".")) return true;
        for (self.names) |excluded_name| if (std.mem.eql(u8, excluded_name, name)) return true;
        return false;
    }
};
const Kind = enum { file, directory, symlink, other };
const Entry = struct { kind: Kind, device: u64, inode: std.Io.File.INode, size: u64, mtime: i96, ctime: i96, hash: ?[32]u8 = null };
const Snapshot = std.StringHashMapUnmanaged(Entry);
fn denied(err: anyerror) bool {
    return err == error.AccessDenied or err == error.PermissionDenied;
}
fn freeSnapshot(gpa: std.mem.Allocator, snapshot: *Snapshot) void {
    var keys = snapshot.keyIterator();
    while (keys.next()) |key| gpa.free(key.*);
    snapshot.deinit(gpa);
    snapshot.* = .empty;
}
fn freeSnapshotKeys(gpa: std.mem.Allocator, values: anytype) void {
    var keys = values.keyIterator();
    while (keys.next()) |key| gpa.free(key.*);
    values.deinit(gpa);
    values.* = .empty;
}
fn within(path: []const u8, parent: []const u8) bool {
    if (std.mem.eql(u8, path, parent)) return true;
    if (!std.mem.startsWith(u8, path, parent)) return false;
    return parent.len != 0 and (std.fs.path.isSep(parent[parent.len - 1]) or (path.len > parent.len and std.fs.path.isSep(path[parent.len])));
}
fn kindOf(stat: std.Io.File.Stat) Kind {
    return switch (stat.kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        else => .other,
    };
}
const Utf16Units = struct {
    iterator: std.unicode.Utf8Iterator,
    pending: ?u16 = null,
    fn init(bytes: []const u8) Utf16Units {
        return .{ .iterator = std.unicode.Utf8View.initUnchecked(bytes).iterator() };
    }
    fn next(self: *Utf16Units) ?u16 {
        if (self.pending) |value| {
            self.pending = null;
            return value;
        }
        const point = self.iterator.nextCodepoint() orelse return null;
        if (point < 0x10000) return @intCast(point);
        self.pending = @intCast(0xdc00 + ((point - 0x10000) & 0x3ff));
        return @intCast(0xd800 + ((point - 0x10000) >> 10));
    }
};
fn lessLikeJavascript(_: void, a: []const u8, b: []const u8) bool {
    var lhs = Utf16Units.init(a);
    var rhs = Utf16Units.init(b);
    while (true) {
        const left = lhs.next();
        const right = rhs.next();
        if (left == null) return right != null;
        if (right == null) return false;
        if (left.? != right.?) return left.? < right.?;
    }
}
pub const Watcher = struct {
    mode: std.atomic.Value(Mode) = .init(.polling),
    gpa: std.mem.Allocator,
    io: std.Io,
    targets: []Resolved,
    options: Options,
    callback: Callback,
    callback_context: ?*anyopaque,
    snapshot: Snapshot = .empty,
    closed: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    worker_id: std.atomic.Value(std.Thread.Id) = .init(0),
    close_mutex: std.Io.Mutex = .init,
    backend: ?native.Backend = null,
    events: std.StringHashMapUnmanaged(void) = .empty,
    flush_at: ?i64 = null,
    settle_at: ?i64 = null,

    pub fn open(fs: anytype, targets: []const Target, options: Options, callback: Callback, callback_context: ?*anyopaque, context: types.Context) !types.Result(*Watcher) {
        if (context.aborted()) return types.failure(*Watcher, fs.gpa, .aborted, null, null, "aborted");
        if (options.mode == .native and !native_supported) return types.failure(*Watcher, fs.gpa, .not_supported, null, null, "Native event backend is not installed for this platform");
        const resolved = try fs.gpa.alloc(Resolved, targets.len);
        var count: usize = 0;
        errdefer {
            for (resolved[0..count]) |*target| target.deinit(fs.gpa);
            fs.gpa.free(resolved);
        }
        for (targets) |target| {
            const path = try fs.resolvePath(target.path);
            errdefer fs.gpa.free(path);
            const names = try fs.gpa.alloc([]u8, target.exclude.names.len);
            var names_count: usize = 0;
            errdefer {
                for (names[0..names_count]) |name| fs.gpa.free(name);
                fs.gpa.free(names);
            }
            for (target.exclude.names) |name| {
                names[names_count] = try fs.gpa.dupe(u8, name);
                names_count += 1;
            }
            resolved[count] = .{ .path = path, .recursive = target.recursive, .hidden = target.exclude.hidden, .names = names };
            count += 1;
        }
        const self = try fs.gpa.create(Watcher);
        errdefer fs.gpa.destroy(self);
        self.* = .{ .gpa = fs.gpa, .io = fs.io, .targets = resolved, .options = options, .callback = callback, .callback_context = callback_context };
        if (native_supported and (options.mode == .native or (options.mode == null and builtin.os.tag != .windows and !try native.unreliable(fs.gpa, resolved)))) self.mode.store(.native, .release);
        self.snapshot = self.scan() catch |err| {
            if (err == error.OutOfMemory) return err;
            // Allocation is still fallible when representing an expected error.
            const result = try types.failure(*Watcher, fs.gpa, if (denied(err)) .permission_denied else .invalid, null, err, @errorName(err));
            for (resolved) |*target| target.deinit(fs.gpa);
            fs.gpa.free(resolved);
            fs.gpa.destroy(self);
            return result;
        };
        errdefer freeSnapshot(fs.gpa, &self.snapshot);
        errdefer {
            if (self.backend) |*backend| backend.deinit();
            freeSnapshotKeys(fs.gpa, &self.events);
        }
        if (self.mode.load(.acquire) == .native) {
            self.backend = native.Backend.init(fs.gpa) catch |err| blk: {
                if (err == error.OutOfMemory) return err;
                self.mode.store(.polling, .release);
                self.callback(self.callback_context, .overflow) catch {};
                break :blk null;
            };
            if (self.backend != null) for (0..10) |_| {
                if (!try self.reconcile()) break;
                const next = try self.scan();
                freeSnapshot(fs.gpa, &self.snapshot);
                self.snapshot = next;
            };
            if (builtin.os.tag == .macos and self.backend != null) self.backend.?.prepare() catch |err| {
                if (err == error.OutOfMemory) return err;
                self.switchToPolling();
            };
        }
        if (context.aborted()) {
            const result = try types.failure(*Watcher, fs.gpa, .aborted, null, null, "aborted");
            freeSnapshot(fs.gpa, &self.snapshot);
            if (self.backend) |*backend| backend.deinit();
            freeSnapshotKeys(fs.gpa, &self.events);
            for (resolved) |*target| target.deinit(fs.gpa);
            fs.gpa.free(resolved);
            fs.gpa.destroy(self);
            return result;
        }
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch |err| {
            if (err == error.OutOfMemory) return err;
            const result = try types.failure(*Watcher, fs.gpa, .unknown, null, err, @errorName(err));
            freeSnapshot(fs.gpa, &self.snapshot);
            if (self.backend) |*backend| backend.deinit();
            freeSnapshotKeys(fs.gpa, &self.events);
            for (resolved) |*target| target.deinit(fs.gpa);
            fs.gpa.free(resolved);
            fs.gpa.destroy(self);
            return result;
        };
        return .{ .value = self };
    }
    pub fn close(self: *Watcher, _: types.Context) void {
        self.closed.store(true, .release);
        // Closing inside a callback stops delivery immediately. The owning
        // caller later joins the thread before destroying this watcher.
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
        freeSnapshot(self.gpa, &self.snapshot);
        if (self.backend) |*backend| backend.deinit();
        freeSnapshotKeys(self.gpa, &self.events);
        for (self.targets) |*target| target.deinit(self.gpa);
        self.gpa.free(self.targets);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }
    fn run(self: *Watcher) void {
        self.worker_id.store(std.Thread.getCurrentId(), .release);
        defer self.worker_id.store(0, .release);
        if (self.mode.load(.acquire) == .native) return self.runNative();
        while (!self.closed.load(.acquire)) {
            const began = std.Io.Clock.awake.now(self.io).toMilliseconds();
            const delay: i64 = @intCast(@min(@max(self.options.pollIntervalMs, 1), std.math.maxInt(i64)));
            while (!self.closed.load(.acquire) and std.Io.Clock.awake.now(self.io).toMilliseconds() - began < delay) {
                std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(@min(delay, 20)), .clock = .awake } }, self.io) catch {};
            }
            if (self.closed.load(.acquire)) break;
            self.poll() catch |err| {
                if (!self.closed.load(.acquire)) self.callback(self.callback_context, .{ .@"error" = .{ .code = if (denied(err)) .permission_denied else .invalid, .message = @errorName(err), .cause = err } }) catch {};
                self.closed.store(true, .release);
                break;
            };
        }
    }
    fn inScope(self: *Watcher, path: []const u8) bool {
        for (self.targets) |target| {
            if (within(target.path, path)) return true;
            if (!within(path, target.path) or std.mem.eql(u8, path, target.path)) continue;
            var relative = path[target.path.len..];
            while (relative.len > 0 and std.fs.path.isSep(relative[0])) relative = relative[1..];
            var parts = std.mem.tokenizeAny(u8, relative, if (builtin.os.tag == .windows) "/\\" else "/");
            var count: usize = 0;
            var excluded = false;
            while (parts.next()) |part| {
                count += 1;
                if (target.excluded(part)) excluded = true;
            }
            if (!excluded and (target.recursive or count <= 1)) return true;
        }
        return false;
    }
    const NativeSink = struct {
        watcher: *Watcher,
        pub fn event(self: @This(), path: []const u8) !void {
            const owner = self.watcher;
            if (!owner.inScope(path)) return;
            const reported = owner.report(path);
            if (!owner.events.contains(reported)) {
                const owned = try owner.gpa.dupe(u8, reported);
                errdefer owner.gpa.free(owned);
                try owner.events.put(owner.gpa, owned, {});
            }
            if (owner.flush_at == null) owner.flush_at = std.Io.Clock.awake.now(owner.io).toMilliseconds() + 50;
        }
        pub fn overflow(self: @This()) !void {
            // Like notify's need_rescan flag, native queue overflow triggers
            // a rescan; a switch of backend separately reports overflow.
            self.watcher.flush_at = std.Io.Clock.awake.now(self.watcher.io).toMilliseconds() + 50;
        }
    };
    fn runNative(self: *Watcher) void {
        while (!self.closed.load(.acquire)) {
            if (self.mode.load(.acquire) == .polling) {
                self.run();
                return;
            }
            self.backend.?.drain(NativeSink{ .watcher = self }) catch |err| {
                if (err == error.OutOfMemory) {
                    self.failWatch(err);
                    return;
                }
                self.switchToPolling();
                continue;
            };
            if (self.settle_at) |at| if (std.Io.Clock.awake.now(self.io).toMilliseconds() >= at) {
                self.settle_at = null;
                self.flush_at = std.Io.Clock.awake.now(self.io).toMilliseconds();
            };
            if (self.flush_at) |at| if (std.Io.Clock.awake.now(self.io).toMilliseconds() >= at) {
                self.flush_at = null;
                self.poll() catch |err| {
                    self.failWatch(err);
                    return;
                };
                for (0..10) |_| {
                    const added = self.reconcile() catch |err| {
                        self.failWatch(err);
                        return;
                    };
                    if (!added) break;
                    self.poll() catch |err| {
                        self.failWatch(err);
                        return;
                    };
                }
            };
            self.io.sleep(.fromMilliseconds(10), .awake) catch {};
        }
    }
    fn failWatch(self: *Watcher, err: anyerror) void {
        if (!self.closed.load(.acquire)) self.callback(self.callback_context, .{ .@"error" = .{ .code = if (denied(err)) .permission_denied else .invalid, .message = @errorName(err), .cause = err } }) catch {};
        self.closed.store(true, .release);
    }
    fn switchToPolling(self: *Watcher) void {
        if (self.mode.load(.acquire) == .polling) return;
        self.mode.store(.polling, .release);
        if (self.backend) |*backend| backend.deinit();
        self.backend = null;
        self.callback(self.callback_context, .overflow) catch {};
    }
    fn reconcile(self: *Watcher) !bool {
        if (self.backend == null) return false;
        const backend = &self.backend.?;
        var stale: std.ArrayList([]const u8) = .empty;
        defer stale.deinit(self.gpa);
        var installed = backend.installed.iterator();
        while (installed.next()) |entry| {
            const signature = self.snapshot.get(entry.key_ptr.*);
            if (signature == null or signature.?.device != entry.value_ptr.device or signature.?.inode != entry.value_ptr.inode or !self.wantedNative(entry.key_ptr.*, signature.?)) try stale.append(self.gpa, entry.key_ptr.*);
        }
        for (stale.items) |path| backend.remove(path);
        var added = false;
        var iterator = self.snapshot.iterator();
        while (iterator.next()) |entry| if (self.wantedNative(entry.key_ptr.*, entry.value_ptr.*)) {
            const was_added = backend.add(entry.key_ptr.*, entry.value_ptr.inode, entry.value_ptr.device) catch |err| {
                if (err == error.OutOfMemory) return err;
                self.switchToPolling();
                return false;
            };
            added = added or was_added;
        };
        if (builtin.os.tag == .macos and added) self.settle_at = std.Io.Clock.awake.now(self.io).toMilliseconds() + 500;
        return added;
    }
    fn wantedNative(self: *Watcher, path: []const u8, entry: Entry) bool {
        if (entry.kind == .directory) {
            for (self.targets) |target| if (within(target.path, path) or (target.recursive and within(path, target.path))) return true;
            return false;
        }
        if (entry.kind != .file) return false;
        for (self.targets) |target| if (std.mem.eql(u8, target.path, path)) {
            const stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch return false;
            return stat.kind == .sym_link;
        };
        return false;
    }
    fn report(self: *Watcher, path: []const u8) []const u8 {
        for (self.targets) |target| if (within(path, target.path)) return path;
        for (self.targets) |target| if (within(target.path, path)) return target.path;
        return path;
    }
    fn poll(self: *Watcher) !void {
        var next = try self.scan();
        defer freeSnapshot(self.gpa, &next);
        var changed: std.StringHashMapUnmanaged(void) = .empty;
        defer changed.deinit(self.gpa);
        var events = self.events.keyIterator();
        while (events.next()) |key| try changed.put(self.gpa, key.*, {});
        defer {
            freeSnapshotKeys(self.gpa, &self.events);
            self.events = .empty;
        }
        var items = next.iterator();
        while (items.next()) |item| {
            const previous = self.snapshot.get(item.key_ptr.*);
            if (previous == null or !std.meta.eql(previous.?, item.value_ptr.*)) try changed.put(self.gpa, self.report(item.key_ptr.*), {});
        }
        var keys = self.snapshot.keyIterator();
        while (keys.next()) |key| if (!next.contains(key.*)) try changed.put(self.gpa, self.report(key.*), {});
        if (changed.count() != 0 and !self.closed.load(.acquire)) {
            const paths = try self.gpa.alloc([]const u8, changed.count());
            defer self.gpa.free(paths);
            var changed_keys = changed.keyIterator();
            var index: usize = 0;
            while (changed_keys.next()) |key| : (index += 1) paths[index] = key.*;
            std.mem.sort([]const u8, paths, {}, lessLikeJavascript);
            // Borrowed paths stay valid throughout this call. Exceptions do
            // not stop watching, as in the pinned environment contract.
            self.callback(self.callback_context, .{ .paths = paths }) catch {};
        }
        std.mem.swap(Snapshot, &self.snapshot, &next);
    }
    fn hashFile(self: *Watcher, path: []const u8, stat: std.Io.File.Stat) !?[32]u8 {
        if (self.mode.load(.acquire) != .polling or stat.kind != .file or stat.size > 256 * 1024 or std.Io.Clock.real.now(self.io).toMilliseconds() - stat.mtime.toMilliseconds() >= 5000) return null;
        const file = filesystem.openRegular(self.io, self.gpa, path, .{}) catch |err| {
            if (err == error.OutOfMemory) return err;
            return null;
        };
        defer file.close(self.io);
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var buffer: [4096]u8 = undefined;
        var position: u64 = 0;
        while (position <= 256 * 1024) {
            var vectors = [_][]u8{&buffer};
            const count = file.readPositional(self.io, &vectors, position) catch return null;
            if (count == 0) {
                var digest: [32]u8 = undefined;
                hasher.final(&digest);
                return digest;
            }
            hasher.update(buffer[0..count]);
            position += count;
        }
        return null;
    }
    fn record(self: *Watcher, snapshot: *Snapshot, path: []const u8, stat: std.Io.File.Stat, ancestor: bool, replace: bool) !void {
        if (snapshot.contains(path) and !replace) return;
        if (!snapshot.contains(path) and snapshot.count() >= self.options.maxEntries) return error.WatchEntryLimit;
        const kind = kindOf(stat);
        const file_identity = try identity.query(self.gpa, path, stat.kind != .sym_link, stat.inode);
        const identity_only = ancestor or kind == .directory;
        const signature: Entry = .{ .kind = kind, .device = file_identity.device, .inode = file_identity.inode, .size = if (identity_only) 0 else stat.size, .mtime = if (identity_only) 0 else stat.mtime.nanoseconds, .ctime = 0, .hash = if (ancestor) null else try self.hashFile(path, stat) };
        if (snapshot.getPtr(path)) |entry| {
            entry.* = signature;
            return;
        }
        const key = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(key);
        try snapshot.put(self.gpa, key, signature);
    }
    fn scan(self: *Watcher) !Snapshot {
        var snapshot: Snapshot = .empty;
        errdefer freeSnapshot(self.gpa, &snapshot);
        var counted: std.StringHashMapUnmanaged(void) = .empty;
        defer counted.deinit(self.gpa);
        var listed: std.StringHashMapUnmanaged(Kind) = .empty;
        defer listed.deinit(self.gpa);
        for (self.targets) |target| {
            var parent = std.fs.path.dirname(target.path);
            while (parent) |path| {
                if (!snapshot.contains(path)) if (std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch null) |stat| try self.record(&snapshot, path, stat, true, false);
                const next = std.fs.path.dirname(path);
                if (next != null and std.mem.eql(u8, next.?, path)) break;
                parent = next;
            }
            const stat = std.Io.Dir.cwd().statFile(self.io, target.path, .{}) catch |err| {
                if (denied(err)) return err;
                continue;
            };
            try self.record(&snapshot, target.path, stat, false, true);
            if (stat.kind != .directory) continue;
            var pending: std.ArrayList([]u8) = .empty;
            defer pending.deinit(self.gpa);
            defer for (pending.items) |path| self.gpa.free(path);
            const root = try self.gpa.dupe(u8, target.path);
            pending.append(self.gpa, root) catch |err| {
                self.gpa.free(root);
                return err;
            };
            var index: usize = 0;
            while (index < pending.items.len) : (index += 1) {
                // Traversal belongs to each target's recursion/exclusions;
                // the directory budget counts each lexical path once.
                try counted.put(self.gpa, snapshot.getKey(pending.items[index]).?, {});
                if (counted.count() > self.options.maxDirectories) return error.WatchDirectoryLimit;
                if (self.closed.load(.acquire)) return error.WatchClosed;
                const directory = std.Io.Dir.cwd().openDir(self.io, pending.items[index], .{ .iterate = true, .follow_symlinks = index == 0 }) catch |err| {
                    if (index == 0 and denied(err)) return err;
                    if (err == error.FileNotFound or err == error.AccessDenied or err == error.PermissionDenied or err == error.NotDir or err == error.SymLinkLoop) continue;
                    return err;
                };
                defer directory.close(self.io);
                var iterator = directory.iterate();
                while (try iterator.next(self.io)) |entry| {
                    if (target.excluded(entry.name)) continue;
                    const path = try std.fs.path.join(self.gpa, &.{ pending.items[index], entry.name });
                    var transferred = false;
                    defer if (!transferred) self.gpa.free(path);
                    var child_kind = listed.get(path);
                    if (child_kind == null) {
                        const child_stat = std.Io.Dir.cwd().statFile(self.io, path, .{ .follow_symlinks = false }) catch continue;
                        child_kind = kindOf(child_stat);
                        try self.record(&snapshot, path, child_stat, false, false);
                        const stable_key = snapshot.getKey(path).?;
                        try listed.put(self.gpa, stable_key, child_kind.?);
                    }
                    if (target.recursive and child_kind.? == .directory) {
                        try pending.append(self.gpa, path);
                        transferred = true;
                    }
                }
            }
        }
        return snapshot;
    }
};

const Capture = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    paths: std.ArrayList([]u8) = .empty,
    errors: usize = 0,
    close_on_callback: ?*Watcher = null,
    fn deinit(self: *Capture) void {
        for (self.paths.items) |path| self.gpa.free(path);
        self.paths.deinit(self.gpa);
    }
    fn callback(context: ?*anyopaque, change: Change) !void {
        const self: *Capture = @ptrCast(@alignCast(context.?));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        switch (change) {
            .paths => |paths| for (paths) |path| {
                const owned = try self.gpa.dupe(u8, path);
                errdefer self.gpa.free(owned);
                try self.paths.append(self.gpa, owned);
            },
            .@"error" => self.errors += 1,
            .overflow => {},
        }
        if (self.close_on_callback) |watcher| watcher.close(.{});
    }
    fn has(self: *Capture, path: []const u8) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (self.paths.items) |seen| if (std.mem.eql(u8, seen, path)) return true;
        return false;
    }
    fn count(self: *Capture) usize {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.paths.items.len;
    }
    fn wait(self: *Capture, path: []const u8) !void {
        const until = std.Io.Clock.awake.now(self.io).toMilliseconds() + 2000;
        while (std.Io.Clock.awake.now(self.io).toMilliseconds() < until) {
            if (self.has(path)) return;
            try std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(10), .clock = .awake } }, self.io);
        }
        std.debug.print("Durable watch did not report {s}\n", .{path});
        return error.WatchFixtureTimedOut;
    }
};
test "durable b7df overlapping targets retain independent traversal and count unique directories" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    try scratch.dir.createDirPath(io, "root/child/deep");
    try scratch.dir.writeFile(io, .{ .sub_path = "root/child/deep/file", .data = "initial" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, buffer[0..length], null);
    defer fs.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    const watcher = try expectWatcher(gpa, try fs.watch(&.{ .{ .path = "root", .recursive = false }, .{ .path = "root/child", .recursive = true } }, .{ .mode = .polling, .pollIntervalMs = 5, .maxDirectories = 3 }, Capture.callback, &capture, .{}));
    defer watcher.deinit();
    const file = try fs.resolvePath("root/child/deep/file");
    defer gpa.free(file);
    try std.testing.expect(watcher.snapshot.contains(file));
    try scratch.dir.writeFile(io, .{ .sub_path = "root/child/deep/file", .data = "changed" });
    try capture.wait(file);
    watcher.close(.{});
    const redundant = try expectWatcher(gpa, try fs.watch(&.{ .{ .path = "root", .recursive = true }, .{ .path = "root/child", .recursive = true } }, .{ .mode = .polling, .pollIntervalMs = 5, .maxDirectories = 3 }, Capture.callback, &capture, .{}));
    defer redundant.deinit();
    redundant.close(.{});
}

test "durable b7df real target permission failure is distinguished from an unreadable descendant" {
    if (builtin.os.tag == .windows or builtin.os.tag == .wasi) return error.SkipZigTest;
    if (std.posix.system.geteuid() == 0) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    try scratch.dir.createDirPath(io, "root/denied");
    const directory = try scratch.dir.openDir(io, "root/denied", .{ .iterate = true });
    defer directory.close(io);
    try directory.setPermissions(io, .fromMode(0));
    defer directory.setPermissions(io, .fromMode(0o700)) catch {};
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try scratch.dir.realPath(io, &buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, buffer[0..length], null);
    defer fs.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    var failed = try fs.watch(&.{.{ .path = "root/denied", .recursive = true }}, .{ .mode = .polling, .pollIntervalMs = 5 }, Capture.callback, &capture, .{});
    try std.testing.expect(failed == .failure);
    defer failed.failure.deinit(gpa);
    try std.testing.expectEqual(types.FileErrorCode.permission_denied, failed.failure.code);
    const watcher = try expectWatcher(gpa, try fs.watch(&.{.{ .path = "root", .recursive = true }}, .{ .mode = .polling, .pollIntervalMs = 5 }, Capture.callback, &capture, .{}));
    defer watcher.deinit();
    watcher.close(.{});
}
fn expectWatcher(gpa: std.mem.Allocator, result: types.Result(*Watcher)) !*Watcher {
    return switch (result) {
        .value => |watcher| watcher,
        .failure => |err| {
            var owned = err;
            defer owned.deinit(gpa);
            std.debug.print("Durable watch error {s}: {s}\n", .{ @tagName(err.code), err.message });
            return error.UnexpectedWatchFailure;
        },
    };
}
test "durable polling watch initial coverage missing paths excludes recursive changes rename and close" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    try temporary_dir.dir.createDirPath(io, "watched/sub");
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "watched/initial", .data = "old" });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    const watcher = try expectWatcher(gpa, try Watcher.open(&fs, &.{ .{ .path = "watched", .recursive = true, .exclude = .{ .hidden = true, .names = &.{"ignored"} } }, .{ .path = "missing" } }, .{ .mode = .polling, .pollIntervalMs = 20 }, Capture.callback, &capture, .{}));
    defer watcher.deinit();
    try std.testing.expectEqual(Mode.polling, watcher.mode.load(.acquire));
    // A write immediately after open is observed against the established first
    // snapshot; the target did not exist during that snapshot.
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "missing", .data = "created" });
    const missing = try fs.resolvePath("missing");
    defer gpa.free(missing);
    try capture.wait(missing);
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "watched/.hidden", .data = "hidden" });
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "watched/ignored", .data = "ignored" });
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "watched/sub/new", .data = "nested" });
    const nested = try fs.resolvePath("watched/sub/new");
    defer gpa.free(nested);
    try capture.wait(nested);
    const hidden = try fs.resolvePath("watched/.hidden");
    defer gpa.free(hidden);
    const ignored = try fs.resolvePath("watched/ignored");
    defer gpa.free(ignored);
    try std.testing.expect(!capture.has(hidden) and !capture.has(ignored));
    try temporary_dir.dir.rename("watched", temporary_dir.dir, "moved", io);
    const watched = try fs.resolvePath("watched");
    defer gpa.free(watched);
    try capture.wait(watched);
    watcher.close(.{});
    watcher.close(.{});
    const previous = capture.count();
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "missing", .data = "after-close" });
    try std.Io.Timeout.sleep(.{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } }, io);
    try std.testing.expectEqual(previous, capture.count());
    try std.testing.expectEqual(@as(usize, 0), capture.errors);
}
test "durable polling watch budgets fail closed and callback close cannot join its own thread" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, path_buffer[0..length], null);
    defer fs.deinit();
    var capture: Capture = .{ .gpa = gpa, .io = io };
    defer capture.deinit();
    for ([_]Options{ .{ .mode = .native }, .{ .maxDirectories = 0 }, .{ .maxEntries = 0 } }, 0..) |options, index| {
        if (index == 0 and native_supported) continue;
        var result = try Watcher.open(&fs, &.{.{ .path = ".", .recursive = true }}, options, Capture.callback, &capture, .{});
        switch (result) {
            .failure => |*err| {
                defer err.deinit(gpa);
                try std.testing.expectEqual(if (index == 0) types.FileErrorCode.not_supported else types.FileErrorCode.invalid, err.code);
            },
            .value => return error.ExpectedWatchLimit,
        }
    }
    const watcher = try expectWatcher(gpa, try Watcher.open(&fs, &.{.{ .path = "created" }}, .{ .mode = .polling, .pollIntervalMs = 20 }, Capture.callback, &capture, .{}));
    defer watcher.deinit();
    capture.close_on_callback = watcher;
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "created", .data = "change" });
    const changed = try fs.resolvePath("created");
    defer gpa.free(changed);
    try capture.wait(changed);
    watcher.close(.{});
    try std.testing.expect(watcher.closed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), capture.count());
}
fn watchAllocationProbe(gpa: std.mem.Allocator, cwd: []const u8, mode: ?Mode) !void {
    var fs = try filesystem.FileSystem.init(gpa, std.testing.io, cwd, null);
    defer fs.deinit();
    const Null = struct {
        fn callback(_: ?*anyopaque, _: Change) !void {}
    };
    const watcher = try expectWatcher(gpa, try Watcher.open(&fs, &.{.{ .path = ".", .recursive = true, .exclude = .{ .names = &.{ "ignore", "other" } } }}, .{ .mode = mode }, Null.callback, null, .{}));
    watcher.deinit();
}
test "durable watch initial snapshot resources release on every allocation failure" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    try temporary_dir.dir.createDirPath(io, "sub");
    try temporary_dir.dir.writeFile(io, .{ .sub_path = "sub/file", .data = "small hashed file" });
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary_dir.dir.realPath(io, &path_buffer);
    try std.testing.checkAllAllocationFailures(gpa, watchAllocationProbe, .{ path_buffer[0..length], @as(?Mode, null) });
    if (builtin.os.tag == .windows) try std.testing.checkAllAllocationFailures(gpa, watchAllocationProbe, .{ path_buffer[0..length], @as(?Mode, .native) });
}

test "durable watch macOS default native stream observes immediate startup writes and repeated close" {
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try tmp.dir.realPath(io, &buffer);
    var fs = try filesystem.FileSystem.init(gpa, io, buffer[0..length], null);
    defer fs.deinit();
    for (0..4) |index| {
        var capture: Capture = .{ .gpa = gpa, .io = io };
        defer capture.deinit();
        const watcher = try expectWatcher(gpa, try Watcher.open(&fs, &.{.{ .path = ".", .recursive = true }}, .{}, Capture.callback, &capture, .{}));
        defer watcher.deinit();
        try std.testing.expectEqual(Mode.native, watcher.mode.load(.acquire));
        const name = try std.fmt.allocPrint(gpa, "immediate-Ω-{d}", .{index});
        defer gpa.free(name);
        try tmp.dir.writeFile(io, .{ .sub_path = name, .data = "before-FSEvents-settles" });
        const path = try fs.resolvePath(name);
        defer gpa.free(path);
        try capture.wait(path);
        try std.testing.expectEqual(Mode.native, watcher.mode.load(.acquire));
        try std.testing.expectEqual(@as(usize, 0), capture.errors);
        watcher.close(.{});
        watcher.close(.{});
        const count = capture.count();
        try tmp.dir.writeFile(io, .{ .sub_path = name, .data = "after-close" });
        try io.sleep(.fromMilliseconds(100), .awake);
        try std.testing.expectEqual(count, capture.count());
    }
}
