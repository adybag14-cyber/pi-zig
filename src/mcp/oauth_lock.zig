//! Interoperable proper-lockfile directory lease with bounded stale takeover.
const std = @import("std");
const builtin = @import("builtin");
fn modifyTimestamp(gpa: std.mem.Allocator, io: std.Io, path: []const u8, timestamp: std.Io.Timestamp) !void {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const Native = struct {
            const FileTime = extern struct { low: u32, high: u32 };
            extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, ?*const anyopaque, u32, u32, ?windows.HANDLE) callconv(.winapi) windows.HANDLE;
            extern "kernel32" fn SetFileTime(windows.HANDLE, ?*const FileTime, ?*const FileTime, ?*const FileTime) callconv(.winapi) i32;
            extern "kernel32" fn CloseHandle(windows.HANDLE) callconv(.winapi) i32;
        };
        const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
        defer gpa.free(wide);
        const handle = Native.CreateFileW(wide.ptr, 0x100, 7, null, 3, 0x02000000 | 0x00200000, null);
        if (handle == windows.INVALID_HANDLE_VALUE) return error.OAuthLockTimestampOpenFailed;
        defer _ = Native.CloseHandle(handle);
        const ticks: u64 = @intCast(@divTrunc(timestamp.nanoseconds, 100) + 116444736000000000);
        const filetime: Native.FileTime = .{ .low = @truncate(ticks), .high = @truncate(ticks >> 32) };
        if (Native.SetFileTime(handle, null, null, &filetime) == 0) return error.OAuthLockTimestampFailed;
    } else try std.Io.Dir.cwd().setTimestamps(io, path, .{ .follow_symlinks = false, .modify_timestamp = .init(timestamp) });
}
pub const Options = struct { stale_ms: i64 = 20_000, wait_ms: i64 = 25_000, retry_ms: i64 = 100, heartbeat_ms: i64 = 5_000 };
pub const Lease = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    path: []u8,
    inode: std.Io.File.INode,
    mtime: std.Io.Timestamp,
    options: Options,
    closing: std.atomic.Value(bool) = .init(false),
    compromised: std.atomic.Value(bool) = .init(false),
    heartbeat: ?std.Io.Future(anyerror!void) = null,
    pub fn acquire(gpa: std.mem.Allocator, io: std.Io, base_path: []const u8, options: Options, flag: ?*bool) !*Lease {
        if (options.stale_ms <= 0 or options.wait_ms < 0 or options.retry_ms <= 0 or options.heartbeat_ms <= 0 or options.heartbeat_ms >= options.stale_ms) return error.InvalidOAuthLockOptions;
        const path = try std.fmt.allocPrint(gpa, "{s}.lock", .{base_path});
        errdefer gpa.free(path);
        if (std.fs.path.dirname(path)) |parent| try std.Io.Dir.cwd().createDirPath(io, parent);
        const deadline = std.Io.Clock.awake.now(io).toMilliseconds() + options.wait_ms;
        while (true) {
            if (flag) |aborted| if (@atomicLoad(bool, aborted, .acquire)) return error.Canceled;
            std.Io.Dir.cwd().createDir(io, path, .default_dir) catch |cause| {
                if (cause != error.PathAlreadyExists) return cause;
                const existing = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |stat_cause| switch (stat_cause) {
                    error.FileNotFound => continue,
                    else => return stat_cause,
                };
                const age = std.Io.Clock.real.now(io).toMilliseconds() - @divTrunc(existing.mtime.nanoseconds, std.time.ns_per_ms);
                if (existing.kind == .directory and age > options.stale_ms) {
                    const current = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |stat_cause| switch (stat_cause) {
                        error.FileNotFound => continue,
                        else => return stat_cause,
                    };
                    if (current.inode == existing.inode and current.mtime.nanoseconds == existing.mtime.nanoseconds) {
                        if (std.Io.Dir.cwd().deleteDir(io, path)) |_| {
                            continue;
                        } else |_| {}
                    }
                }
                if (std.Io.Clock.awake.now(io).toMilliseconds() >= deadline) return error.McpOAuthRefreshLockTimeout;
                try io.sleep(.fromMilliseconds(options.retry_ms), .awake);
                continue;
            };
            break;
        }
        errdefer std.Io.Dir.cwd().deleteDir(io, path) catch {};
        const stat = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
        const self = try gpa.create(Lease);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .io = io, .path = path, .inode = stat.inode, .mtime = stat.mtime, .options = options };
        self.heartbeat = try io.concurrent(renew, .{self});
        return self;
    }
    fn renew(self: *Lease) anyerror!void {
        while (!self.closing.load(.acquire)) {
            try self.io.sleep(.fromMilliseconds(self.options.heartbeat_ms), .awake);
            if (self.closing.load(.acquire)) return;
            // Renewal is one ownership transition. Cancellation must not land
            // after the filesystem update but before retaining its new mtime.
            const protection = self.io.swapCancelProtection(.blocked);
            defer _ = self.io.swapCancelProtection(protection);
            const stat = std.Io.Dir.cwd().statFile(self.io, self.path, .{ .follow_symlinks = false }) catch {
                self.compromised.store(true, .release);
                return;
            };
            if (stat.inode != self.inode or stat.mtime.nanoseconds != self.mtime.nanoseconds) {
                self.compromised.store(true, .release);
                return;
            }
            modifyTimestamp(self.gpa, self.io, self.path, std.Io.Clock.real.now(self.io)) catch {
                self.compromised.store(true, .release);
                return;
            };
            const updated = try std.Io.Dir.cwd().statFile(self.io, self.path, .{ .follow_symlinks = false });
            self.mtime = updated.mtime;
        }
    }
    pub fn close(self: *Lease, _: std.Io) void {
        const io = self.io;
        const protection = io.swapCancelProtection(.blocked);
        defer _ = io.swapCancelProtection(protection);
        self.closing.store(true, .release);
        if (self.heartbeat) |*future| future.cancel(self.io) catch {};
        if (!self.compromised.load(.acquire)) {
            const stat = std.Io.Dir.cwd().statFile(self.io, self.path, .{ .follow_symlinks = false }) catch null;
            if (stat) |current| if (current.inode == self.inode and current.mtime.nanoseconds == self.mtime.nanoseconds) std.Io.Dir.cwd().deleteDir(self.io, self.path) catch {};
        }
        const gpa = self.gpa;
        gpa.free(self.path);
        gpa.destroy(self);
    }
};

test "mcp.runtime OAuth directory lease renews while held and releases only its owned lock" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const base = try std.fs.path.join(gpa, &.{ buffer[0..count], "refresh" });
    defer gpa.free(base);
    const options: Options = .{ .stale_ms = 150, .wait_ms = 100, .retry_ms = 10, .heartbeat_ms = 20 };
    const lease = try Lease.acquire(gpa, io, base, options, null);
    const path = try gpa.dupe(u8, lease.path);
    defer gpa.free(path);
    var closed = false;
    defer if (!closed) lease.close(io);
    try io.sleep(.fromMilliseconds(220), .awake);
    try std.testing.expect(!lease.compromised.load(.acquire));
    try std.testing.expectError(error.McpOAuthRefreshLockTimeout, Lease.acquire(gpa, io, base, options, null));
    lease.close(io);
    closed = true;
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }));
}

test "mcp.runtime OAuth directory lease does not remove a replacement owner's lock" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const base = try std.fs.path.join(gpa, &.{ buffer[0..count], "refresh" });
    defer gpa.free(base);
    const lease = try Lease.acquire(gpa, io, base, .{}, null);
    const path = try gpa.dupe(u8, lease.path);
    defer gpa.free(path);
    try std.Io.Dir.cwd().deleteDir(io, path);
    try std.Io.Dir.cwd().createDir(io, path, .default_dir);
    // Mark the new directory with an independently changed timestamp as inode
    // reuse alone must never authorize deletion of a new owner.
    try modifyTimestamp(gpa, io, path, .{ .nanoseconds = lease.mtime.nanoseconds + std.time.ns_per_s });
    lease.close(io);
    _ = try std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false });
}

test "mcp.runtime OAuth stale nonempty lock respects deadline and preserves foreign content" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const base = try std.fs.path.join(gpa, &.{ buffer[0..count], "foreign" });
    defer gpa.free(base);
    const path = try std.fmt.allocPrint(gpa, "{s}.lock", .{base});
    defer gpa.free(path);
    try scratch.dir.createDir(io, "foreign.lock", .default_dir);
    try scratch.dir.writeFile(io, .{ .sub_path = "foreign.lock/owner", .data = "preserved" });
    try modifyTimestamp(gpa, io, path, .{ .nanoseconds = std.Io.Clock.real.now(io).nanoseconds - 10 * std.time.ns_per_s });
    const started = std.Io.Clock.awake.now(io).toMilliseconds();
    try std.testing.expectError(error.McpOAuthRefreshLockTimeout, Lease.acquire(gpa, io, base, .{ .stale_ms = 100, .wait_ms = 60, .retry_ms = 10, .heartbeat_ms = 20 }, null));
    try std.testing.expect(std.Io.Clock.awake.now(io).toMilliseconds() - started < 1_000);
    const bytes = try scratch.dir.readFileAlloc(io, "foreign.lock/owner", gpa, .limited(100));
    defer gpa.free(bytes);
    try std.testing.expectEqualStrings("preserved", bytes);
}

test "mcp.runtime OAuth abandoned empty lock can be replaced and retired" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try scratch.dir.realPath(io, &buffer);
    const base = try std.fs.path.join(gpa, &.{ buffer[0..count], "abandoned" });
    defer gpa.free(base);
    const path = try std.fmt.allocPrint(gpa, "{s}.lock", .{base});
    defer gpa.free(path);
    try scratch.dir.createDir(io, "abandoned.lock", .default_dir);
    try modifyTimestamp(gpa, io, path, .{ .nanoseconds = std.Io.Clock.real.now(io).nanoseconds - 10 * std.time.ns_per_s });
    const lease = try Lease.acquire(gpa, io, base, .{ .stale_ms = 100, .wait_ms = 60, .retry_ms = 10, .heartbeat_ms = 20 }, null);
    lease.close(io);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }));
    try std.testing.expectError(error.InvalidOAuthLockOptions, Lease.acquire(gpa, io, base, .{ .heartbeat_ms = 20_000 }, null));
}
