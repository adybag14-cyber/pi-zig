//! FileAuthStorageBackend owner-local primitives. Directory locks use the
//! original auth.json.lock namespace; no callback runs on a foreign thread.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const c = em.c;
pub const Lease = struct { gpa: std.mem.Allocator, io: std.Io, path: []u8, owned: bool = false, mtime_ms: i64 = 0, compromised: bool = false };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    release(lease);
    lease.gpa.free(lease.path);
    lease.gpa.destroy(lease);
    _ = runtime;
}
pub fn release(lease: *Lease) void {
    if (lease.owned) {
        lease.owned = false;
        std.Io.Dir.cwd().deleteDir(lease.io, lease.path) catch {};
    }
}
pub fn initialize(engine: *em.Engine, cache: c.JSValue) !void {
    var id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &id);
    var definition: c.JSClassDef = std.mem.zeroes(c.JSClassDef);
    definition.class_name = "NativeAuthFileLock";
    definition.finalizer = finalize;
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    try js.define(engine, cache, "fileLockClass", c.JS_NewInt64(engine.context, id));
}
pub fn newLease(scope: *Scope, cache: c.JSValue, path: c.JSValue) !c.JSValue {
    var id: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &id, try scope.get(cache, "fileLockClass")) < 0) return js.capture(scope.engine);
    const value = try scope.own(try scope.engine.checked(c.JS_NewObjectClass(scope.engine.context, @intCast(id))));
    const text = try scope.engine.toString(path);
    defer scope.engine.gpa.free(text);
    const lock_path = try std.fmt.allocPrint(scope.engine.gpa, "{s}.lock", .{text});
    errdefer scope.engine.gpa.free(lock_path);
    const io = scope.engine.native_io orelse return error.NativeAuthFileIoUnavailable;
    const lease = try scope.engine.gpa.create(Lease);
    lease.* = .{ .gpa = scope.engine.gpa, .io = io, .path = lock_path };
    _ = c.JS_SetOpaque(value, lease);
    return value;
}
pub fn state(value: c.JSValue) *Lease {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn permissions(comptime mode: u32) std.Io.File.Permissions {
    return if (@hasDecl(std.Io.File.Permissions, "fromMode")) std.Io.File.Permissions.fromMode(mode) else .default_file;
}
pub fn ensureFile(engine: *em.Engine, path: []const u8) !void {
    const io = engine.native_io orelse return error.NativeAuthFileIoUnavailable;
    if (std.fs.path.dirname(path)) |parent| _ = try std.Io.Dir.cwd().createDirPathStatus(io, parent, if (@hasDecl(std.Io.Dir.Permissions, "fromMode")) std.Io.Dir.Permissions.fromMode(0o700) else .default_dir);
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true, .permissions = permissions(0o600) }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close(io);
    try file.writePositionalAll(io, "{}", 0);
}
pub fn read(engine: *em.Engine, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(engine.native_io orelse return error.NativeAuthFileIoUnavailable, path, engine.gpa, .unlimited);
}
pub fn write(engine: *em.Engine, path: []const u8, text: []const u8) !void {
    const io = engine.native_io orelse return error.NativeAuthFileIoUnavailable;
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .permissions = permissions(0o600) });
    defer file.close(io);
    try file.writePositionalAll(io, text, 0);
}
pub fn revision(engine: *em.Engine, path: []const u8) !?[]u8 {
    const stat = std.Io.Dir.cwd().statFile(engine.native_io orelse return error.NativeAuthFileIoUnavailable, path, .{}) catch return null;
    return try std.fmt.allocPrint(engine.gpa, "{d}:{d}:{d}:{d}", .{ stat.inode, stat.size, stat.mtime.nanoseconds, stat.ctime.nanoseconds });
}
/// No waiting occurs here. The owner schedules the Source retry delay when
/// another process owns a fresh lock, keeping JavaScript and abort delivery live.
pub fn tryAcquire(lease: *Lease, stale_ms: i64, now_ms: i64) !bool {
    std.Io.Dir.cwd().createDir(lease.io, lease.path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {
            const stat = std.Io.Dir.cwd().statFile(lease.io, lease.path, .{}) catch |stat_err| switch (stat_err) {
                error.FileNotFound => return false,
                else => return stat_err,
            };
            if (stat.mtime.toMilliseconds() >= now_ms - stale_ms) return false;
            // Only an empty, stale lock directory is removed; this is never a
            // recursive filesystem operation or an auth-file replacement.
            std.Io.Dir.cwd().deleteDir(lease.io, lease.path) catch |remove_err| switch (remove_err) {
                error.FileNotFound => {},
                else => return remove_err,
            };
            std.Io.Dir.cwd().createDir(lease.io, lease.path, .default_dir) catch |retry_err| switch (retry_err) {
                error.PathAlreadyExists => return false,
                else => return retry_err,
            };
        },
        else => return err,
    };
    lease.owned = true;
    const stat = try std.Io.Dir.cwd().statFile(lease.io, lease.path, .{});
    lease.mtime_ms = stat.mtime.toMilliseconds();
    return true;
}
pub fn heartbeat(lease: *Lease) !void {
    if (!lease.owned) return;
    const stat = std.Io.Dir.cwd().statFile(lease.io, lease.path, .{}) catch |err| {
        lease.compromised = true;
        lease.owned = false;
        return err;
    };
    if (stat.mtime.toMilliseconds() != lease.mtime_ms) {
        lease.compromised = true;
        lease.owned = false;
        return error.AuthLockCompromised;
    }
    try setTimestamp(lease.gpa, lease.io, lease.path, std.Io.Clock.real.now(lease.io));
    lease.mtime_ms = (try std.Io.Dir.cwd().statFile(lease.io, lease.path, .{})).mtime.toMilliseconds();
}

/// Zig 0.16's Threaded directory timestamp operation is unimplemented on
/// Windows. Use its native directory handle API, retaining the same lock path
/// and write-attributes-only access as the application's OAuth lock primitive.
pub fn setTimestamp(gpa: std.mem.Allocator, io: std.Io, path: []const u8, timestamp: std.Io.Timestamp) !void {
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
        if (handle == windows.INVALID_HANDLE_VALUE) return error.AuthLockTimestampOpenFailed;
        defer _ = Native.CloseHandle(handle);
        const ticks = std.math.cast(u64, @divTrunc(timestamp.nanoseconds, 100) + 116444736000000000) orelse return error.AuthLockTimestampOutOfRange;
        const filetime: Native.FileTime = .{ .low = @truncate(ticks), .high = @truncate(ticks >> 32) };
        if (Native.SetFileTime(handle, null, &filetime, &filetime) == 0) return error.AuthLockTimestampFailed;
    } else try std.Io.Dir.cwd().setTimestamps(io, path, .{ .follow_symlinks = false, .access_timestamp = .init(timestamp), .modify_timestamp = .init(timestamp) });
}
