//! Real proper-lockfile directory-lock boundary used by FileAuthStorageBackend.
//! Atomic mkdir, source mtime precision/heartbeat and owner-local callbacks; no
//! guest value ever crosses a worker thread. The namespace is shared per realm.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const body = @import("native_async_body.zig");
const af = body.native;
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
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
    return checkedInt64(scope, try checkedInvoke(scope, try checkedGlobal(scope, "Date"), "now", &.{}));
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
    const lock = try scope.own(try af.createResumable(engine, "lock", 2, asyncLock, &.{owner}));
    try scope.put(lock, "lock", lock);
    try scope.put(lock, "lockSync", try scope.own(try funcs.create(engine, "lockSync", 2, syncLock, &.{owner})));
    try engine.native_module_values.put(engine.gpa, cache_key, c.JS_DupValue(engine.context, lock));
    return c.JS_DupValue(engine.context, lock);
}
fn errorValue(scope: *Scope, message: []const u8, code: []const u8, file: ?[]const u8) !c.JSValue {
    const constructor = try checkedGlobal(scope, "Error");
    const value = try checkedConstruct(scope, constructor, &.{try checkedText(scope, message)});
    try checkedPut(scope, value, "code", try checkedText(scope, code));
    if (file) |path| try checkedPut(scope, value, "file", try checkedText(scope, path));
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
    checkedPut(scope, value, "syscall", checkedText(scope, syscall) catch |failure| return failure) catch |failure| return failure;
    checkedPut(scope, value, "path", checkedText(scope, path) catch |failure| return failure) catch |failure| return failure;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |failure| return failure;
    unreachable;
}
fn failValue(scope: *Scope, value: c.JSValue) anyerror {
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |err| return err;
    unreachable;
}
fn number(scope: *Scope, options: c.JSValue, key: [*:0]const u8, fallback: i64) !i64 {
    const value = try checkedOptional(scope, options, key);
    if (v.nullish(value)) return fallback;
    return checkedInt64(scope, value);
}
fn acquire(scope: *Scope, owner: c.JSValue, file: c.JSValue, options: c.JSValue, synchronous: bool) !c.JSValue {
    // FileAuthStorageBackend always selects realpath:false; resolve the actual
    // path just as proper-lockfile's non-realpath branch does.
    const path_module = scope.engine.native_module_values.get("node:path") orelse return error.NativeAuthLockRequiresPath;
    const absolute = try checkedCall(scope, try checkedGet(scope, path_module, "resolve"), c.pi_js_undefined(), &.{file});
    const raw = try checkedString(scope, absolute);
    defer scope.engine.gpa.free(raw);
    // proper-lockfile 4.1.2 getLockFile: the selected realpath:false
    // consumers supply a String path. Preserve a supplied lockfilePath exactly
    // (including a relative spelling); only a falsy option selects file.lock.
    // The owned Lease.path below feeds all physical operations and retirement.
    const explicit_path = try checkedOptional(scope, options, "lockfilePath");
    const lock_path = if (scope.truthy(explicit_path))
        try checkedString(scope, explicit_path)
    else
        try std.fmt.allocPrint(scope.engine.gpa, "{s}.lock", .{raw});
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
    const precision = if (synchronous) c.pi_js_undefined() else try checkedGet(scope, owner, "precision");
    if (c.JS_IsUndefined(precision)) {
        const probe_ms = @divFloor(try now(scope) + 999, 1000) * 1000 + 5;
        @import("native_auth_file_io.zig").setTimestamp(scope.engine.gpa, io, lock_path, .{ .nanoseconds = @as(i96, probe_ms) * std.time.ns_per_ms }) catch |err| return ioFailure(scope, err, "utime", lock_path);
    }
    const stat = std.Io.Dir.cwd().statFile(io, lock_path, .{}) catch |err| return ioFailure(scope, err, "stat", lock_path);
    const seconds = if (c.JS_IsUndefined(precision)) @mod(stat.mtime.toMilliseconds(), 1000) == 0 else scope.truthy(precision);
    if (!synchronous and c.JS_IsUndefined(precision)) try checkedPut(scope, owner, "precision", c.pi_js_bool(scope.engine.context, @intFromBool(seconds)));
    var class: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &class, try checkedGet(scope, owner, "class")) < 0) return v.js.capture(scope.engine);
    const object_generation = scope.engine.native_allocation_generation;
    const value = try checkedOwn(scope, object_generation, scope.engine.checked(c.JS_NewObjectClass(scope.engine.context, class)));
    const update = @max(1000, @min(try number(scope, options, "update", @divTrunc(stale, 2)), @divTrunc(stale, 2)));
    const acquired_at = try now(scope);
    const compromised = try checkedOptional(scope, options, "onCompromised");
    const lease = try scope.engine.gpa.create(Lease);
    errdefer if (!attached) scope.engine.gpa.destroy(lease);
    const owned_file = try scope.engine.gpa.dupe(u8, raw);
    errdefer if (!attached) scope.engine.gpa.free(owned_file);
    const owned_path = try scope.engine.gpa.dupe(u8, lock_path);
    errdefer if (!attached) scope.engine.gpa.free(owned_path);
    lease.* = .{ .engine = scope.engine, .io = io, .file = owned_file, .path = owned_path, .inode = @intCast(stat.inode), .owned = true, .mtime_ms = stat.mtime.toMilliseconds(), .last_update = acquired_at, .stale = stale, .update = update, .delay = update, .seconds = seconds, .owner = c.JS_DupValue(scope.engine.context, owner), .compromised = c.JS_DupValue(scope.engine.context, compromised), .timer = c.pi_js_undefined() };
    _ = c.JS_SetOpaque(value, lease);
    attached = true;
    _ = try checkedInvoke(scope, try checkedGet(scope, owner, "leases"), "set", &.{ absolute, value });
    try schedule(scope, value);
    return value;
}
fn schedule(scope: *Scope, value: c.JSValue) !void {
    const lease = state(value);
    const timeout = try checkedGlobal(scope, "setTimeout");
    const handler = try checkedFunction(scope, "", 0, heartbeat, &.{value}, true);
    const timer = try checkedCall(scope, timeout, c.pi_js_undefined(), &.{ handler, c.JS_NewInt64(scope.engine.context, lease.delay) });
    scope.engine.freeValue(lease.timer);
    lease.timer = c.JS_DupValue(scope.engine.context, timer);
    if (scope.truthy(try checkedOptional(scope, timer, "unref"))) _ = try checkedInvoke(scope, timer, "unref", &.{});
}
fn compromise(scope: *Scope, value: c.JSValue, reason: c.JSValue) !void {
    const lease = state(value);
    lease.owned = false;
    lease.released = true;
    _ = try checkedInvoke(scope, try checkedGet(scope, lease.owner, "leases"), "delete", &.{try checkedText(scope, lease.file)});
    if (!c.JS_IsUndefined(lease.compromised)) _ = try checkedCall(scope, lease.compromised, c.pi_js_undefined(), &.{reason}) else return failValue(scope, reason);
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
    _ = try checkedCall(scope, try checkedGlobal(scope, "clearTimeout"), c.pi_js_undefined(), &.{lease.timer});
    lease.released = true;
    lease.owned = false;
    _ = try checkedInvoke(scope, try checkedGet(scope, lease.owner, "leases"), "delete", &.{try checkedText(scope, lease.file)});
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
fn syncLock(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const lease = try acquire(&scope, roots[0], arg(args, 0), arg(args, 1), true);
    return funcs.createArrow(engine, "", 0, releaseSync, &.{lease});
}
// proper-lockfile 4.1.2 index.js really declares async function lock. Its
// adapter's returned release is an ORDINARY rest arrow, not an AsyncFunction.
// Preserve the inner Await: the raw callback release is the Promise result;
// toPromise(release) is created only after that actual Await resumes.
fn asyncLock(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    return owned.finishAction(&scope, lockStep(&scope, args, roots[0], completion, input) catch |err| actionFailure(engine, err));
}
fn actionFailure(engine: *v.em.Engine, err: anyerror) !af.Action {
    try engine.checkNativeEntry();
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        return .{ .thrown = reason };
    };
    return body.failure(engine, err);
}
fn lockStep(s: *Scope, args: []const c.JSValue, owner: c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    if (completion == .rejected) {
        try body.enterRejectedContinuation(s.engine);
        return .{ .thrown = c.JS_DupValue(s.engine.context, input) }; // DATA.
    }
    if (completion == .fulfilled) return .{ .returned = c.JS_DupValue(s.engine.context, try toPromise(s, input)) };
    const raw_lock = try checkedFunction(s, "lock", 3, callbackLock, &.{owner}, false);
    const wrapper = try toPromise(s, raw_lock);
    return .{ .awaited = c.JS_DupValue(s.engine.context, try checkedCall(s, wrapper, c.pi_js_undefined(), &.{ arg(args, 0), arg(args, 1) })) };
}
fn normal(s: *Scope, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
    const value = try guards.guard(s.engine, generation, result);
    // A native callee/getter can return a value while publishing a real event.
    _ = try guards.guard(s.engine, generation, s.engine.checked(c.pi_js_undefined()));
    try s.engine.checkNativeEntry();
    return value;
}
fn checkedCall(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, v.js.call(s.engine, function, receiver, args));
}
fn checkedGet(s: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, v.js.get(s.engine, object, name));
}
fn checkedGlobal(s: *Scope, name: [*:0]const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, v.js.global(s.engine, name));
}
fn checkedText(s: *Scope, text: []const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, @import("native_sdk.zig").text(s.engine, text));
}
fn checkedOptional(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(value)) c.pi_js_undefined() else checkedGet(s, value, name);
}
fn checkedInvoke(s: *Scope, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return checkedCall(s, try checkedGet(s, object, name), object, args);
}
fn checkedConstruct(s: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, s.engine.checked(c.JS_CallConstructor(s.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
}
fn checkedOwn(s: *Scope, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
    const value = try guards.guard(s.engine, generation, result);
    const checked = try guards.guard(s.engine, generation, s.engine.checked(value));
    return owned.ownRoot(s, checked);
}
fn checkedFunction(s: *Scope, name: [*:0]const u8, length: c_int, callback: funcs.Callback, roots: []const c.JSValue, arrow: bool) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return checkedOwn(s, generation, if (arrow) funcs.createArrow(s.engine, name, length, callback, roots) else funcs.create(s.engine, name, length, callback, roots));
}
fn checkedPut(s: *Scope, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    const result = s.put(object, name, value);
    _ = try normal(s, generation, if (result) |_| c.pi_js_undefined() else |err| err);
}
fn checkedString(s: *Scope, value: c.JSValue) ![]u8 {
    const generation = s.engine.native_allocation_generation;
    const result = s.engine.toString(value) catch |err| {
        _ = try normal(s, generation, @as(anyerror!c.JSValue, err));
        unreachable;
    };
    errdefer s.engine.gpa.free(result);
    _ = try normal(s, generation, s.engine.checked(c.pi_js_undefined()));
    return result;
}
fn checkedInt64(s: *Scope, value: c.JSValue) !i64 {
    const generation = s.engine.native_allocation_generation;
    var result: i64 = 0;
    const status = c.JS_ToInt64(s.engine.context, &result, value);
    _ = try normal(s, generation, if (status < 0) v.js.capture(s.engine) else c.pi_js_undefined());
    return result;
}
fn checkedTypeError(s: *Scope, message: [*:0]const u8) anyerror {
    const generation = s.engine.native_allocation_generation;
    _ = normal(s, generation, @as(anyerror!c.JSValue, v.js.typeError(s.engine, message))) catch |err| return err;
    unreachable;
}
fn caught(s: *Scope, err: anyerror) !c.JSValue {
    return switch (try actionFailure(s.engine, err)) {
        .thrown => |reason| reason,
        else => unreachable,
    };
}
fn callbackLock(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, callbackLockBody(&s, args, roots[0]));
}
fn callbackLockBody(s: *Scope, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    const lease = acquire(s, owner, arg(args, 0), arg(args, 1), false) catch |err| {
        const reason = try caught(s, err);
        var completion = owned.Completion.initValue(s.engine, callbackFailure(s, arg(args, 2), reason));
        completion.release(reason);
        return completion.finishValue();
    };
    try s.engine.checkNativeEntry();
    const raw_release = try checkedFunction(s, "", 1, callbackRelease, &.{lease}, true);
    return c.JS_DupValue(s.engine.context, try checkedCall(s, arg(args, 2), c.pi_js_undefined(), &.{ c.pi_js_null(), raw_release }));
}
fn callbackFailure(s: *Scope, callback: c.JSValue, reason: c.JSValue) !c.JSValue {
    return c.JS_DupValue(s.engine.context, try checkedCall(s, callback, c.pi_js_undefined(), &.{reason}));
}
fn callbackRelease(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, callbackReleaseBody(&s, args, roots[0]));
}
fn callbackReleaseBody(s: *Scope, args: []const c.JSValue, lease: c.JSValue) !c.JSValue {
    release(s, lease) catch |err| {
        const reason = try caught(s, err);
        var completion = owned.Completion.initValue(s.engine, callbackFailure(s, arg(args, 0), reason));
        completion.release(reason);
        return completion.finishValue();
    };
    try s.engine.checkNativeEntry();
    return c.JS_DupValue(s.engine.context, try checkedCall(s, arg(args, 0), c.pi_js_undefined(), &.{}));
}
fn toPromise(s: *Scope, method: c.JSValue) !c.JSValue {
    return checkedFunction(s, "", 0, promiseCall, &.{method}, true);
}
fn promiseCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, promiseCallBody(&s, args, roots[0]));
}
fn promiseCallBody(s: *Scope, args: []const c.JSValue, method: c.JSValue) !c.JSValue {
    const array_generation = s.engine.native_allocation_generation;
    const rest = try checkedOwn(s, array_generation, v.js.array(s.engine));
    for (args, 0..) |value, index| {
        const generation = s.engine.native_allocation_generation;
        const result = s.index(rest, @intCast(index), value);
        _ = try normal(s, generation, if (result) |_| c.pi_js_undefined() else |err| err);
    }
    const constructor = try checkedGlobal(s, "Promise");
    const executor = try checkedFunction(s, "", 2, promiseExecutor, &.{ method, rest }, true);
    return c.JS_DupValue(s.engine.context, try checkedConstruct(s, constructor, &.{executor}));
}
fn promiseExecutor(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, executorBody(&s, args, roots));
}
fn executorBody(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try pushCallback(s.engine, args, roots[1]);
    _ = try owned.ownRoot(s, try spreadCall(s.engine, roots[0], roots[1]));
    return c.pi_js_undefined();
}
fn pushCallback(engine: *v.em.Engine, args: []const c.JSValue, rest: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return owned.finishVoid(&s, pushCallbackBody(&s, args, rest));
}
fn pushCallbackBody(s: *Scope, args: []const c.JSValue, rest: c.JSValue) !void {
    const push = try checkedGet(s, rest, "push");
    const callback = try checkedFunction(s, "", 2, promiseCallback, &.{ arg(args, 0), arg(args, 1) }, true);
    // Actual live push then actual iterable argument spread, in adapter order.
    // Neither object CopyDataProperties nor a length-index substitute is used.
    _ = try checkedCall(s, push, rest, &.{callback});
    // Source has completed the push expression. Its callee, callback argument
    // and ignored return retire before any subsequent iterable getter/call.
}
fn promiseCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, promiseCallbackBody(&s, args, roots));
}
fn promiseCallbackBody(s: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const rejected = s.truthy(arg(args, 0));
    _ = try checkedCall(s, roots[@intFromBool(rejected)], c.pi_js_undefined(), &.{arg(args, if (rejected) 0 else 1)});
    return c.pi_js_undefined();
}
fn spreadCall(engine: *v.em.Engine, method: c.JSValue, iterable: c.JSValue) !c.JSValue {
    var arguments: Scope = .{ .engine = engine };
    var items: std.ArrayList(c.JSValue) = .empty;
    defer items.deinit(engine.gpa); // Borrowed pointers only, never VM roots.
    return owned.finishValue(&arguments, spreadCallBody(&arguments, &items, method, iterable));
}
fn spreadCallBody(arguments: *Scope, items: *std.ArrayList(c.JSValue), method: c.JSValue, iterable: c.JSValue) !c.JSValue {
    const engine = arguments.engine;
    var record: Scope = .{ .engine = engine };
    try owned.finishVoid(&record, spreadInto(&record, arguments, items, iterable));
    // IteratorRecord/method temporaries retire before Source invokes method.
    return c.JS_DupValue(engine.context, try checkedCall(arguments, method, c.pi_js_undefined(), items.items));
}
fn iteratorValue(engine: *v.em.Engine, iterable: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return owned.finishValue(&s, iteratorValueBody(&s, iterable));
}
fn iteratorValueBody(s: *Scope, iterable: c.JSValue) !c.JSValue {
    const symbol_generation = s.engine.native_allocation_generation;
    const symbol = try checkedOwn(s, symbol_generation, s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)));
    const generation = s.engine.native_allocation_generation;
    const method = try checkedOwn(s, generation, v.js.getKey(s.engine, iterable, symbol));
    const value = try checkedCall(s, method, iterable, &.{});
    if (!c.JS_IsObject(value)) return checkedTypeError(s, "Iterator is not an object");
    return c.JS_DupValue(s.engine.context, value);
}
fn spreadInto(record: *Scope, arguments: *Scope, items: *std.ArrayList(c.JSValue), iterable: c.JSValue) !void {
    const iterator = try owned.ownRoot(record, try iteratorValue(record.engine, iterable));
    const next = try checkedGet(record, iterator, "next");
    var steps: usize = 0;
    while (true) {
        steps +|= 1;
        try @import("native_jiti_budget.zig").check(record.engine, steps);
        const value = try nextValue(record.engine, iterator, next);
        if (value == null) break;
        const item = try owned.ownRoot(arguments, value.?);
        try items.append(record.engine.gpa, item);
    }
    // Array/call spread abrupt IteratorStep does not call iterator.return.
}
fn nextValue(engine: *v.em.Engine, iterator: c.JSValue, next: c.JSValue) !?c.JSValue {
    var step: Scope = .{ .engine = engine };
    const result = nextValueBody(&step, iterator, next);
    const completed = if (result) |value| value == null else |_| false;
    const selected: anyerror!c.JSValue = if (result) |value| value orelse c.pi_js_undefined() else |err| err;
    const value = try owned.finishValue(&step, selected);
    return if (completed) null else value;
}
fn nextValueBody(s: *Scope, iterator: c.JSValue, next: c.JSValue) !?c.JSValue {
    const step = try checkedCall(s, next, iterator, &.{});
    if (!c.JS_IsObject(step)) return checkedTypeError(s, "Iterator result is not an object");
    const done = try doneValue(s.engine, step);
    if (done) return null;
    return c.JS_DupValue(s.engine.context, try checkedGet(s, step, "value"));
}
fn doneValue(engine: *v.em.Engine, step: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const result = doneValueBody(&s, step);
    // Record Boolean before done's owned reference can run a native finalizer.
    const selected: anyerror!c.JSValue = if (result) |done| c.pi_js_bool(engine.context, @intFromBool(done)) else |err| err;
    return c.JS_ToBool(engine.context, try owned.finishValue(&s, selected)) != 0;
}
fn doneValueBody(s: *Scope, step: c.JSValue) !bool {
    return s.truthy(try checkedGet(s, step, "done"));
}
