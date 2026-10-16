//! Real proper-lockfile directory-lock boundary used by FileAuthStorageBackend.
//! Atomic mkdir, source mtime precision/heartbeat and owner-local callbacks; no
//! guest value ever crosses a worker thread. The namespace is shared per realm.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const funcs = @import("native_node_function.zig");
const cache_key = "pi-native:auth-directory-lock";
const Lease = struct {
    engine: *v.em.Engine,
    io: std.Io,
    file: []u8,
    path: []u8,
    inode: u64 = 0,
    owned: bool = false,
    released: bool = false,
    mtime_ms: i64 = 0,
    last_update: i64 = 0,
    stale: i64,
    update: i64,
    delay: i64,
    seconds: bool = false,
    owner: c.JSValue,
    compromised: c.JSValue,
    timer: c.JSValue,
};
fn freeLease(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    // Realm destruction must not remove a lock subsequently acquired by another
    // owner at the same name. No recursive removal or foreign directory cleanup.
    if (lease.owned) {
        if (std.Io.Dir.cwd().statFile(lease.io, lease.path, .{})) |stat| {
            if (stat.inode == lease.inode and stat.mtime.toMilliseconds() == lease.mtime_ms) std.Io.Dir.cwd().deleteDir(lease.io, lease.path) catch {};
        } else |_| {}
    }
    c.JS_FreeValueRT(runtime, lease.owner);
    c.JS_FreeValueRT(runtime, lease.compromised);
    c.JS_FreeValueRT(runtime, lease.timer);
    lease.engine.gpa.free(lease.file);
    lease.engine.gpa.free(lease.path);
    lease.engine.gpa.destroy(lease);
}
fn markLease(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, lease.owner, marker);
    c.JS_MarkValue(runtime, lease.compromised, marker);
    c.JS_MarkValue(runtime, lease.timer, marker);
}
fn state(value: c.JSValue) *Lease {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn now(scope: *Scope) !i64 {
    var value: i64 = 0;
    if (c.JS_ToInt64(scope.engine.context, &value, try scope.invoke(try scope.global("Date"), "now", &.{})) < 0) return v.js.capture(scope.engine);
    return value;
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    const leases = try scope.own(try v.js.builtin(engine, "Map", &.{}));
    try scope.put(owner, "leases", leases);
    try scope.put(owner, "precision", c.pi_js_undefined());
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const def: c.JSClassDef = .{ .class_name = "Auth Directory Lock", .finalizer = freeLease, .gc_mark = markLease };
    if (c.JS_NewClass(engine.runtime, class, &def) < 0) return error.OutOfMemory;
    try scope.put(owner, "class", c.JS_NewUint32(engine.context, class));
    const lock = try scope.own(try funcs.createArrow(engine, "lock", 2, asyncLock, &.{owner}));
    const proto = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, lock, proto) < 0) return v.js.capture(engine);
    try scope.put(lock, "lock", lock);
    try scope.put(lock, "lockSync", try scope.own(try funcs.create(engine, "lockSync", 2, syncLock, &.{owner})));
    try engine.native_module_values.put(engine.gpa, cache_key, c.JS_DupValue(engine.context, lock));
    return c.JS_DupValue(engine.context, lock);
}
fn errorValue(scope: *Scope, message: []const u8, code: []const u8, file: ?[]const u8) !c.JSValue {
    const value = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text(message)}));
    try scope.put(value, "code", try scope.text(code));
    if (file) |path| try scope.put(value, "file", try scope.text(path));
    return value;
}
fn ioFailure(scope: *Scope, err: anyerror, syscall: []const u8, path: []const u8) anyerror {
    if (err == error.OutOfMemory) return err;
    const code: []const u8 = switch (err) {
        error.FileNotFound => "ENOENT",
        error.PathAlreadyExists => "EEXIST",
        error.AccessDenied, error.PermissionDenied => if (builtin.os.tag == .windows) "EPERM" else "EACCES",
        error.DirNotEmpty => "ENOTEMPTY",
        error.NotDir => "ENOTDIR",
        else => "EIO",
    };
    const description: []const u8 = if (std.mem.eql(u8, code, "ENOENT")) "no such file or directory" else if (std.mem.eql(u8, code, "EEXIST")) "file already exists" else if (std.mem.eql(u8, code, "ENOTEMPTY")) "directory not empty" else if (std.mem.eql(u8, code, "ENOTDIR")) "not a directory" else if (std.mem.eql(u8, code, "EPERM")) "operation not permitted" else if (std.mem.eql(u8, code, "EACCES")) "permission denied" else "i/o error";
    const text = std.fmt.allocPrint(scope.engine.gpa, "{s}: {s}, {s} '{s}'", .{ code, description, syscall, path }) catch |failure| return failure;
    defer scope.engine.gpa.free(text);
    const value = errorValue(scope, text, code, null) catch |failure| return failure;
    scope.put(value, "syscall", scope.text(syscall) catch |failure| return failure) catch |failure| return failure;
    scope.put(value, "path", scope.text(path) catch |failure| return failure) catch |failure| return failure;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |failure| return failure;
    unreachable;
}
fn failValue(scope: *Scope, value: c.JSValue) anyerror {
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |err| return err;
    unreachable;
}
fn number(scope: *Scope, options: c.JSValue, key: [*:0]const u8, fallback: i64) !i64 {
    const value = try v.optional(scope, options, key);
    if (v.nullish(value)) return fallback;
    var result: i64 = 0;
    if (c.JS_ToInt64(scope.engine.context, &result, value) < 0) return v.js.capture(scope.engine);
    return result;
}
fn acquire(scope: *Scope, owner: c.JSValue, file: c.JSValue, options: c.JSValue, synchronous: bool) !c.JSValue {
    // FileAuthStorageBackend always selects realpath:false; resolve the actual
    // path just as proper-lockfile's non-realpath branch does.
    const path_module = scope.engine.native_module_values.get("node:path") orelse return error.NativeAuthLockRequiresPath;
    const absolute = try scope.call(try scope.get(path_module, "resolve"), c.pi_js_undefined(), &.{file});
    const raw = try scope.engine.toString(absolute);
    defer scope.engine.gpa.free(raw);
    const lock_path = try std.fmt.allocPrint(scope.engine.gpa, "{s}.lock", .{raw});
    defer scope.engine.gpa.free(lock_path);
    const stale = @max(try number(scope, options, "stale", 10000), 2000);
    const io = scope.engine.native_io orelse return error.NativeAuthFileIoUnavailable;
    var may_check_stale = true;
    while (true) {
        std.Io.Dir.cwd().createDir(io, lock_path, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return ioFailure(scope, err, "mkdir", lock_path);
            if (!may_check_stale) return failValue(scope, try errorValue(scope, "Lock file is already being held", "ELOCKED", raw));
            const stat = std.Io.Dir.cwd().statFile(io, lock_path, .{}) catch |stat_err| {
                if (stat_err == error.FileNotFound) {
                    may_check_stale = false;
                    continue;
                }
                return ioFailure(scope, stat_err, "stat", lock_path);
            };
            if (stat.mtime.toMilliseconds() >= try now(scope) - stale) return failValue(scope, try errorValue(scope, "Lock file is already being held", "ELOCKED", raw));
            std.Io.Dir.cwd().deleteDir(io, lock_path) catch |remove_err| {
                if (remove_err != error.FileNotFound) return ioFailure(scope, remove_err, "rmdir", lock_path);
            };
            may_check_stale = false;
            continue;
        };
        break;
    }
    var attached = false;
    errdefer if (!attached) std.Io.Dir.cwd().deleteDir(io, lock_path) catch {};
    // proper-lockfile's sync adapter shallow-copies graceful-fs for every call.
    // Its nonenumerable precision symbol is consequently absent on each copy;
    // async acquisitions alone share the module's cached precision probe.
    const precision = if (synchronous) c.pi_js_undefined() else try scope.get(owner, "precision");
    if (c.JS_IsUndefined(precision)) {
        const probe_ms = @divFloor(try now(scope) + 999, 1000) * 1000 + 5;
        @import("native_auth_file_io.zig").setTimestamp(scope.engine.gpa, io, lock_path, .{ .nanoseconds = @as(i96, probe_ms) * std.time.ns_per_ms }) catch |err| return ioFailure(scope, err, "utime", lock_path);
    }
    const stat = std.Io.Dir.cwd().statFile(io, lock_path, .{}) catch |err| return ioFailure(scope, err, "stat", lock_path);
    const seconds = if (c.JS_IsUndefined(precision)) @mod(stat.mtime.toMilliseconds(), 1000) == 0 else scope.truthy(precision);
    if (!synchronous and c.JS_IsUndefined(precision)) try scope.put(owner, "precision", c.pi_js_bool(scope.engine.context, @intFromBool(seconds)));
    var class: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &class, try scope.get(owner, "class")) < 0) return v.js.capture(scope.engine);
    const value = try scope.own(try scope.engine.checked(c.JS_NewObjectClass(scope.engine.context, class)));
    const update = @max(1000, @min(try number(scope, options, "update", @divTrunc(stale, 2)), @divTrunc(stale, 2)));
    const acquired_at = try now(scope);
    const compromised = try v.optional(scope, options, "onCompromised");
    const lease = try scope.engine.gpa.create(Lease);
    errdefer if (!attached) scope.engine.gpa.destroy(lease);
    const owned_file = try scope.engine.gpa.dupe(u8, raw);
    errdefer if (!attached) scope.engine.gpa.free(owned_file);
    const owned_path = try scope.engine.gpa.dupe(u8, lock_path);
    errdefer if (!attached) scope.engine.gpa.free(owned_path);
    lease.* = .{ .engine = scope.engine, .io = io, .file = owned_file, .path = owned_path, .inode = @intCast(stat.inode), .owned = true, .mtime_ms = stat.mtime.toMilliseconds(), .last_update = acquired_at, .stale = stale, .update = update, .delay = update, .seconds = seconds, .owner = c.JS_DupValue(scope.engine.context, owner), .compromised = c.JS_DupValue(scope.engine.context, compromised), .timer = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, lease);
    attached = true;
    _ = try scope.invoke(try scope.get(owner, "leases"), "set", &.{ absolute, value });
    try schedule(scope, value);
    return value;
}
fn schedule(scope: *Scope, value: c.JSValue) !void {
    const lease = state(value);
    const timer = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try scope.own(try funcs.createArrow(scope.engine, "", 0, heartbeat, &.{value})), c.JS_NewInt64(scope.engine.context, lease.delay) });
    scope.engine.freeValue(lease.timer);
    lease.timer = c.JS_DupValue(scope.engine.context, timer);
    if (scope.truthy(try v.optional(scope, timer, "unref"))) _ = try scope.invoke(timer, "unref", &.{});
}
fn compromise(scope: *Scope, value: c.JSValue, reason: c.JSValue) !void {
    const lease = state(value);
    lease.owned = false;
    lease.released = true;
    _ = try scope.invoke(try scope.get(lease.owner, "leases"), "delete", &.{try scope.text(lease.file)});
    if (!c.JS_IsUndefined(lease.compromised)) _ = try scope.call(lease.compromised, c.pi_js_undefined(), &.{reason}) else return failValue(scope, reason);
}
fn heartbeat(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = roots[0];
    const lease = state(value);
    if (lease.released) return c.pi_js_undefined();
    engine.freeValue(lease.timer);
    lease.timer = c.pi_js_undefined();
    const current = try now(&scope);
    const stat = std.Io.Dir.cwd().statFile(lease.io, lease.path, .{}) catch |err| {
        if (err == error.FileNotFound or lease.last_update + lease.stale < current) {
            const reason = try errorValue(&scope, @errorName(err), "ECOMPROMISED", null);
            try compromise(&scope, value, reason);
        } else {
            lease.delay = 1000;
            try schedule(&scope, value);
        }
        return c.pi_js_undefined();
    };
    if (stat.mtime.toMilliseconds() != lease.mtime_ms) {
        try compromise(&scope, value, try errorValue(&scope, "Unable to update lock within the stale threshold", "ECOMPROMISED", null));
        return c.pi_js_undefined();
    }
    const mtime = if (lease.seconds) @divFloor(current + 999, 1000) * 1000 else current;
    @import("native_auth_file_io.zig").setTimestamp(engine.gpa, lease.io, lease.path, .{ .nanoseconds = @as(i96, mtime) * std.time.ns_per_ms }) catch |err| {
        if (err == error.FileNotFound or lease.last_update + lease.stale < try now(&scope)) try compromise(&scope, value, try errorValue(&scope, @errorName(err), "ECOMPROMISED", null)) else {
            lease.delay = 1000;
            try schedule(&scope, value);
        }
        return c.pi_js_undefined();
    };
    lease.mtime_ms = mtime;
    lease.last_update = try now(&scope);
    lease.delay = lease.update;
    try schedule(&scope, value);
    return c.pi_js_undefined();
}
fn release(scope: *Scope, value: c.JSValue) !void {
    const lease = state(value);
    if (lease.released) return failValue(scope, try errorValue(scope, "Lock is already released", "ERELEASED", null));
    _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{lease.timer});
    lease.released = true;
    lease.owned = false;
    _ = try scope.invoke(try scope.get(lease.owner, "leases"), "delete", &.{try scope.text(lease.file)});
    std.Io.Dir.cwd().deleteDir(lease.io, lease.path) catch |err| {
        if (err != error.FileNotFound) return ioFailure(scope, err, "rmdir", lease.path);
    };
}
fn releaseSync(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try release(&scope, roots[0]);
    return c.pi_js_undefined();
}
fn releaseAsync(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    release(&scope, roots[0]) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try flow.settle(engine, pending.owner, false, c.pi_js_undefined());
    return pending.promise;
}
fn syncLock(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const lease = try acquire(&scope, roots[0], arg(args, 0), arg(args, 1), true);
    return funcs.createArrow(engine, "", 0, releaseSync, &.{lease});
}
fn asyncLock(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    const lease = acquire(&scope, roots[0], arg(args, 0), arg(args, 1), false) catch |err| {
        try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    };
    try flow.settle(engine, pending.owner, false, try scope.own(try funcs.createArrow(engine, "", 0, releaseAsync, &.{lease})));
    return pending.promise;
}
