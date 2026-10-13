//! Native async FileAuthStorageBackend. Only the owning realm invokes JS.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_models_stream_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const fileio = @import("native_auth_file_io.zig");
const c = em.c;
const Stage = enum(c_int) { attempt, fulfilled, rejected, heartbeat, aborted };
fn nullish(value: c.JSValue) bool {
    return c.JS_IsUndefined(value) or c.JS_IsNull(value);
}
fn clock(scope: *Scope) !i64 {
    var value: i64 = 0;
    if (c.JS_ToInt64(scope.engine.context, &value, try scope.invoke(try scope.global("Date"), "now", &.{})) < 0) return js.capture(scope.engine);
    return value;
}
fn pathText(scope: *Scope, state: c.JSValue) ![]u8 {
    return scope.engine.toString(try scope.get(state, "path"));
}
fn checkSignal(scope: *Scope, job: c.JSValue) !void {
    const signal = try scope.get(job, "signal");
    if (!nullish(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
fn errorValue(scope: *Scope, message: []const u8, code: []const u8) !c.JSValue {
    const text = try scope.text(message);
    var args = [_]c.JSValue{text};
    const value = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, try scope.global("Error"), 1, &args)));
    try scope.put(value, "code", try scope.text(code));
    return value;
}
fn ioError(scope: *Scope, err: anyerror) !c.JSValue {
    if (err == error.OutOfMemory) return err;
    return errorValue(scope, @errorName(err), switch (err) {
        error.FileNotFound => "ENOENT",
        error.AccessDenied, error.PermissionDenied => "EACCES",
        error.PathAlreadyExists => "EEXIST",
        error.NotDir => "ENOTDIR",
        else => "EIO",
    });
}
pub fn install(engine: *em.Engine, exports: c.JSValue, cache: c.JSValue) !void {
    try fileio.initialize(engine, cache);
    var data = [_]c.JSValue{cache};
    const constructor = try engine.checked(c.JS_NewCFunctionData2(engine.context, construct, "FileAuthStorageBackend", 1, 0, data.len, &data));
    defer engine.freeValue(constructor);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    try js.define(engine, exports, "FileAuthStorageBackend", c.JS_DupValue(engine.context, constructor));
}
fn construct(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return create(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
pub fn create(engine: *em.Engine, cache: c.JSValue, path: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!c.JS_IsString(path)) return js.typeError(engine, "Native FileAuthStorageBackend requires an auth path");
    const state = try scope.object();
    try scope.put(state, "path", path);
    try scope.put(state, "cache", cache);
    const result = try scope.object();
    var data = [_]c.JSValue{state};
    inline for (.{ "withLock", "withLockAsync" }, 0..) |name, index| try scope.put(result, name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, name, 1, @intCast(index), data.len, &data))));
    return c.JS_DupValue(engine.context, result);
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined(), magic == 1) catch |err| if (magic == 1) @import("native_durable.zig").rejectedPromise(engine, err) else @import("native_durable.zig").reject(engine, err);
}
fn function(scope: *Scope, job: c.JSValue, stage: Stage) !c.JSValue {
    var data = [_]c.JSValue{job};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callback, "", 1, @intFromEnum(stage), data.len, &data)));
}
fn intrinsics(scope: *Scope, job: c.JSValue) !awaiting.Intrinsics {
    const cache = try scope.get(try scope.get(job, "backend"), "cache");
    return .{ .constructor = try scope.get(cache, "promise_constructor"), .resolve = try scope.get(cache, "promise_resolve"), .then_function = try scope.get(cache, "promise_then") };
}
fn observe(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    var captured = try intrinsics(scope, job);
    return scope.own(try awaiting.continueWith(after, scope.engine, &captured, job, value, @intFromEnum(stage)));
}
fn invoke(engine: *em.Engine, backend: c.JSValue, fn_value: c.JSValue, options: c.JSValue, asynchronous: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const job = try scope.object();
    try scope.put(job, "backend", backend);
    try scope.put(job, "fn", fn_value);
    const signal = if (nullish(options)) c.pi_js_undefined() else try scope.get(options, "signal");
    try scope.put(job, "signal", signal);
    try checkSignal(&scope, job);
    const path = try pathText(&scope, backend);
    defer engine.gpa.free(path);
    fileio.ensureFile(engine, path) catch |err| return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, try ioError(&scope, err))));
    try scope.put(job, "lease", try fileio.newLease(&scope, try scope.get(backend, "cache"), try scope.get(backend, "path")));
    if (!asynchronous) return runSync(&scope, job);
    var caps: [2]c.JSValue = undefined;
    const promise = try scope.own(try engine.checked(c.JS_NewPromiseCapability(engine.context, &caps)));
    defer for (caps) |value| engine.freeValue(value);
    try scope.put(job, "resolve", caps[0]);
    try scope.put(job, "reject", caps[1]);
    try scope.put(job, "closed", c.pi_js_bool(engine.context, 0));
    try scope.put(job, "deadline", c.JS_NewInt64(engine.context, try clock(&scope) + 30000));
    try scope.put(job, "retry", c.JS_NewInt32(engine.context, 0));
    if (!nullish(signal)) {
        const listener = try function(&scope, job, .aborted);
        try scope.put(job, "abortListener", listener);
        const listener_options = try scope.object();
        try scope.put(listener_options, "once", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(signal, "addEventListener", &.{ try scope.text("abort"), listener, listener_options });
    }
    _ = try observe(&scope, job, c.pi_js_undefined(), .attempt);
    return c.JS_DupValue(engine.context, promise);
}
fn current(scope: *Scope, job: c.JSValue) !c.JSValue {
    const path = try pathText(scope, try scope.get(job, "backend"));
    defer scope.engine.gpa.free(path);
    const bytes = try fileio.read(scope.engine, path);
    defer scope.engine.gpa.free(bytes);
    return scope.text(bytes);
}
fn writeNext(scope: *Scope, job: c.JSValue, value: c.JSValue) !void {
    const next = try scope.get(value, "next");
    if (c.JS_IsUndefined(next)) return;
    const text = try scope.engine.toString(next);
    defer scope.engine.gpa.free(text);
    const path = try pathText(scope, try scope.get(job, "backend"));
    defer scope.engine.gpa.free(path);
    try fileio.write(scope.engine, path, text);
}
fn runSync(scope: *Scope, job: c.JSValue) !c.JSValue {
    const lease = fileio.state(try scope.get(job, "lease"));
    defer fileio.release(lease);
    var attempts: usize = 0;
    while (!try fileio.tryAcquire(lease, 10000, try clock(scope))) {
        attempts += 1;
        if (attempts >= 10) return scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, try errorValue(scope, "Lock file is already being held", "ELOCKED"))));
        try lease.io.sleep(.fromMilliseconds(20), .awake);
    }
    const result = try scope.call(try scope.get(job, "fn"), c.pi_js_undefined(), &.{try current(scope, job)});
    try writeNext(scope, job, result);
    return c.JS_DupValue(scope.engine.context, try scope.get(result, "result"));
}
fn cleanup(scope: *Scope, job: c.JSValue) !void {
    inline for (.{ "retryTimer", "heartbeatTimer" }) |key| {
        const timer = try scope.get(job, key);
        if (!c.JS_IsUndefined(timer)) {
            _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{timer});
            try scope.put(job, key, c.pi_js_undefined());
        }
    }
    const listener = try scope.get(job, "abortListener");
    if (c.JS_IsFunction(scope.engine.context, listener)) {
        _ = try scope.invoke(try scope.get(job, "signal"), "removeEventListener", &.{ try scope.text("abort"), listener });
        try scope.put(job, "abortListener", c.pi_js_undefined());
    }
    fileio.release(fileio.state(try scope.get(job, "lease")));
}
fn settle(scope: *Scope, job: c.JSValue, value: c.JSValue, rejected: bool) !c.JSValue {
    if (scope.truthy(try scope.get(job, "closed"))) return c.pi_js_undefined();
    try cleanup(scope, job);
    try scope.put(job, "closed", c.pi_js_bool(scope.engine.context, 1));
    _ = try scope.call(try scope.get(job, if (rejected) "reject" else "resolve"), c.pi_js_undefined(), &.{value});
    return c.pi_js_undefined();
}
fn schedule(scope: *Scope, job: c.JSValue, stage: Stage, delay: i64, key: [*:0]const u8) !void {
    const timer = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ try function(scope, job, stage), c.JS_NewInt64(scope.engine.context, delay) });
    try scope.put(job, key, timer);
    const unref = try scope.get(timer, "unref");
    if (c.JS_IsFunction(scope.engine.context, unref)) _ = try scope.call(unref, timer, &.{});
}
fn attempt(scope: *Scope, job: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(job, "closed"))) return c.pi_js_undefined();
    try checkSignal(scope, job);
    const lease = fileio.state(try scope.get(job, "lease"));
    const now = try clock(scope);
    if (!try fileio.tryAcquire(lease, 30000, now)) {
        var deadline: i64 = 0;
        if (c.JS_ToInt64(scope.engine.context, &deadline, try scope.get(job, "deadline")) < 0) return js.capture(scope.engine);
        if (now >= deadline) return settle(scope, job, try errorValue(scope, "Lock file is already being held", "ELOCKED"), true);
        var retry: u32 = 0;
        if (c.JS_ToUint32(scope.engine.context, &retry, try scope.get(job, "retry")) < 0) return js.capture(scope.engine);
        try scope.put(job, "retry", c.JS_NewInt64(scope.engine.context, retry + 1));
        var random: f64 = 0;
        if (c.JS_ToFloat64(scope.engine.context, &random, try scope.invoke(try scope.global("Math"), "random", &.{})) < 0) return js.capture(scope.engine);
        const base = @min(@as(i64, 10) << @as(u6, @intCast(@min(retry, 7))), 1000);
        const delay = @min(@as(i64, @intFromFloat(@floor(@as(f64, @floatFromInt(base)) * (1 + random) + 0.5))), deadline - now);
        try schedule(scope, job, .attempt, delay, "retryTimer");
        return c.pi_js_undefined();
    }
    try checkSignal(scope, job);
    try schedule(scope, job, .heartbeat, 15000, "heartbeatTimer");
    const pending = try scope.call(try scope.get(job, "fn"), c.pi_js_undefined(), &.{try current(scope, job)});
    var captured = try intrinsics(scope, job);
    const good = try function(scope, job, .fulfilled);
    const bad = try function(scope, job, .rejected);
    _ = try scope.own(try captured.chain(scope.engine, pending, good, bad));
    return c.pi_js_undefined();
}
fn callback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return after(engine, data[0], if (argc > 0) args[0] else c.pi_js_undefined(), false, raw) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn after(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    return advance(engine, job, value, rejected, @enumFromInt(raw)) catch |err| {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        _ = @import("native_durable.zig").reject(engine, err);
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        _ = settle(&scope, job, reason, true) catch {};
        return err;
    };
}
fn compromisedReason(scope: *Scope, job: c.JSValue) !c.JSValue {
    const reason = try scope.get(job, "compromisedError");
    if (!c.JS_IsUndefined(reason)) return reason;
    return errorValue(scope, "Auth storage lock was compromised", "ECOMPROMISED");
}
fn advance(engine: *em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, stage: Stage) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(job, "closed"))) return c.pi_js_undefined();
    if (rejected) return settle(&scope, job, value, true);
    switch (stage) {
        .attempt => return attempt(&scope, job),
        .rejected => return settle(&scope, job, value, true),
        .fulfilled => {
            try checkSignal(&scope, job);
            const lease = fileio.state(try scope.get(job, "lease"));
            if (lease.compromised) return settle(&scope, job, try compromisedReason(&scope, job), true);
            try writeNext(&scope, job, value);
            if (lease.compromised) return settle(&scope, job, try compromisedReason(&scope, job), true);
            return settle(&scope, job, try scope.get(value, "result"), false);
        },
        .heartbeat => {
            const lease = fileio.state(try scope.get(job, "lease"));
            fileio.heartbeat(lease) catch |err| {
                if (err == error.OutOfMemory) return err;
                lease.compromised = true;
                if (err == error.AuthLockCompromised) try scope.put(job, "compromisedError", try errorValue(&scope, "Unable to update lock within the stale threshold", "ECOMPROMISED"));
                return c.pi_js_undefined();
            };
            try schedule(&scope, job, .heartbeat, 15000, "heartbeatTimer");
            return c.pi_js_undefined();
        },
        .aborted => {
            // Source aborts lock waiting promptly, but active callbacks finish
            // under their lease and the signal is checked before persistence.
            if (fileio.state(try scope.get(job, "lease")).owned) return c.pi_js_undefined();
            return settle(&scope, job, try scope.get(try scope.get(job, "signal"), "reason"), true);
        },
    }
}
