//! The actual ordinary FileAuthStorageBackend class from Source 4954d760.
//! Public and TypeScript-private methods remain observable prototype methods;
//! state is the Source own authPath field, not an opaque/plain-record adapter.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const funcs = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Dependencies = struct { get_agent_dir: c.JSValue };
/// Production default for the selected immutable Source4954 package metadata.
pub fn createDefault(engine: *v.em.Engine) !c.JSValue {
    const get_agent_dir = try @import("native_sdk_agent_directory.zig").create(engine, .{});
    defer engine.freeValue(get_agent_dir);
    return create(engine, .{ .get_agent_dir = get_agent_dir });
}
const Method = enum(c_int) { ensureParentDir, ensureFileExists, acquireLockSyncWithRetry, withLock, acquireLockAsync, withLockAsync };
const Stage = enum(c_int) { lock, sleep, cancelled_release, acquired, callback, release };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn imported(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(owner, name), c.pi_js_undefined(), args);
}
/// get_agent_dir must be the genuine config.ts binding. The other dependencies
/// are captured from the actual installed native filesystem/path/timer modules.
pub fn create(engine: *v.em.Engine, dependencies: Dependencies) !c.JSValue {
    const io = engine.native_io orelse return error.NativeAuthFileStorageRequiresIo;
    if (!c.JS_IsFunction(engine.context, dependencies.get_agent_dir)) return error.NativeAuthFileStorageRequiresConfig;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("timers/promises")) try @import("timers.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "getAgentDir", dependencies.get_agent_dir);
    const fs = try scope.own(try @import("native_auth_storage_fs.zig").create(engine));
    inline for (.{ "existsSync", "mkdirSync", "readFileSync", "writeFileSync" }) |name| try scope.put(owner, name, try scope.get(fs, name));
    const path = engine.native_module_values.get("node:path").?;
    inline for (.{ "dirname", "join" }) |name| try scope.put(owner, name, try scope.get(path, name));
    try scope.put(owner, "lockfile", try scope.own(try @import("native_auth_directory_lock.zig").create(engine)));
    try scope.put(owner, "sleep", try scope.get(engine.native_module_values.get("timers/promises").?, "setTimeout"));
    const write_options = try scope.object();
    try scope.put(write_options, "encoding", try scope.text("utf-8"));
    try scope.put(write_options, "mode", c.JS_NewInt32(engine.context, 0o600));
    try scope.put(owner, "writeOptions", write_options);
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "FileAuthStorageBackend", 0, prototype, construct, &.{owner}));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const kind: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return dispatch(host, receiver, args, roots[0], kind);
            }
        };
        const method = try scope.own(try funcs.createMethod(engine, field.name, switch (kind) {
            .ensureParentDir, .ensureFileExists => 0,
            .acquireLockAsync, .withLockAsync => 2,
            else => 1,
        }, Adapter.call, &.{owner}));
        if (kind == .acquireLockAsync or kind == .withLockAsync) {
            const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, method, async_prototype) < 0) return v.js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, method), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    return c.JS_DupValue(engine.context, constructor);
}
fn construct(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.own(try @import("native_class.zig").object(engine, target));
    // Native class field definition must not invoke an inherited setter.
    try scope.put(receiver, "authPath", c.pi_js_undefined());
    var path = arg(args, 0);
    if (c.JS_IsUndefined(path)) path = try imported(&scope, roots[0], "join", &.{ try imported(&scope, roots[0], "getAgentDir", &.{}), try scope.text("auth.json") });
    try scope.set(receiver, "authPath", try scope.own(try @import("native_sdk_source_paths.zig").normalize(engine, path, c.pi_js_undefined())));
    return c.JS_DupValue(engine.context, receiver);
}
fn dispatch(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, owner: c.JSValue, method: Method) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .ensureParentDir => {
            const dir = try imported(&scope, owner, "dirname", &.{try scope.get(receiver, "authPath")});
            if (!scope.truthy(try imported(&scope, owner, "existsSync", &.{dir}))) {
                const options = try scope.object();
                try scope.put(options, "recursive", c.pi_js_bool(engine.context, 1));
                try scope.put(options, "mode", c.JS_NewInt32(engine.context, 0o700));
                _ = try imported(&scope, owner, "mkdirSync", &.{ dir, options });
            }
            return c.pi_js_undefined();
        },
        .ensureFileExists => {
            if (!scope.truthy(try imported(&scope, owner, "existsSync", &.{try scope.get(receiver, "authPath")}))) _ = try imported(&scope, owner, "writeFileSync", &.{ try scope.get(receiver, "authPath"), try scope.text("{}"), try scope.get(owner, "writeOptions") });
            return c.pi_js_undefined();
        },
        .acquireLockSyncWithRetry => return acquireSync(&scope, owner, arg(args, 0)),
        .withLock => return withLock(&scope, owner, receiver, arg(args, 0)),
        .acquireLockAsync, .withLockAsync => {
            const pending = try flow.create(engine, owner);
            defer engine.freeValue(pending.owner);
            errdefer engine.freeValue(pending.promise);
            try scope.put(pending.owner, "self", receiver);
            try scope.put(pending.owner, "release", c.pi_js_undefined());
            if (method == .acquireLockAsync) {
                startAcquire(&scope, pending.owner, arg(args, 0), arg(args, 1)) catch |err| try flow.rejectError(engine, pending.owner, err);
            } else {
                startWithLock(&scope, pending.owner, arg(args, 0), arg(args, 1)) catch |err| try finishError(&scope, pending.owner, err);
            }
            return pending.promise;
        },
    }
}
fn retryCode(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return v.js.capture(scope.engine);
    var code = c.pi_js_undefined();
    if (instance != 0) {
        const atom = c.JS_NewAtom(scope.engine.context, "code");
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(scope.engine.context, atom);
        const has = c.JS_HasProperty(scope.engine.context, reason, atom);
        if (has < 0) return v.js.capture(scope.engine);
        if (has != 0) code = try scope.get(reason, "code");
    }
    if (try v.eq(scope, code, "ELOCKED")) return code;
    if (try v.eq(scope, code, "EPERM") and try v.eq(scope, try scope.get(try scope.global("process"), "platform"), "win32")) return code;
    return c.pi_js_undefined();
}
fn dateNow(scope: *Scope) !c.JSValue {
    return scope.invoke(try scope.global("Date"), "now", &.{});
}
fn acquireSync(scope: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    var attempt: usize = 1;
    while (true) : (attempt += 1) {
        const generation = scope.engine.native_allocation_generation;
        const result = lockSyncAttempt(scope, owner, path) catch |err| {
            const reason = try scope.own(flow.reason(scope.engine, err));
            if (!scope.truthy(try retryCode(scope, reason)) or attempt == 10) return throwValue(scope, reason);
            try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
            const start = try dateNow(scope);
            while (try elapsedLessThan20(scope.engine, start)) {}
            continue;
        };
        return c.JS_DupValue(scope.engine.context, result);
    }
}
fn elapsedLessThan20(engine: *v.em.Engine, start: c.JSValue) !bool {
    // A Source busy wait must not accumulate one host root per clock sample.
    var local: Scope = .{ .engine = engine };
    defer local.deinit();
    return arithmetic.compare(engine, .less, try local.own(try arithmetic.binary(engine, .subtract, try dateNow(&local), start)), c.JS_NewInt32(engine.context, 20));
}
fn lockSyncAttempt(scope: *Scope, owner: c.JSValue, path: c.JSValue) !c.JSValue {
    const lockfile = try scope.get(owner, "lockfile");
    const function = try scope.get(lockfile, "lockSync");
    const options = try scope.object();
    try scope.put(options, "realpath", c.pi_js_bool(scope.engine.context, 0));
    return scope.call(function, lockfile, &.{ path, options });
}
fn current(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    if (scope.truthy(try imported(scope, owner, "existsSync", &.{try scope.get(receiver, "authPath")}))) return imported(scope, owner, "readFileSync", &.{ try scope.get(receiver, "authPath"), try scope.text("utf-8") });
    return c.pi_js_undefined();
}
fn syncBody(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, function: c.JSValue, release_slot: *c.JSValue) !c.JSValue {
    const acquire = try scope.get(receiver, "acquireLockSyncWithRetry");
    release_slot.* = try scope.call(acquire, receiver, &.{try scope.get(receiver, "authPath")});
    const outcome = try scope.call(function, c.pi_js_undefined(), &.{try current(scope, owner, receiver)});
    const result = try scope.get(outcome, "result");
    const next = try scope.get(outcome, "next");
    if (!c.JS_IsUndefined(next)) _ = try imported(scope, owner, "writeFileSync", &.{ try scope.get(receiver, "authPath"), next, try scope.get(owner, "writeOptions") });
    return result;
}
fn withLock(scope: *Scope, owner: c.JSValue, receiver: c.JSValue, function: c.JSValue) !c.JSValue {
    _ = try scope.invoke(receiver, "ensureParentDir", &.{});
    _ = try scope.invoke(receiver, "ensureFileExists", &.{});
    var release = c.pi_js_undefined();
    const result = syncBody(scope, owner, receiver, function, &release) catch |err| {
        const reason = try scope.own(flow.reason(scope.engine, err));
        if (scope.truthy(release)) _ = try scope.call(release, c.pi_js_undefined(), &.{});
        return throwValue(scope, reason);
    };
    if (scope.truthy(release)) _ = try scope.call(release, c.pi_js_undefined(), &.{});
    return c.JS_DupValue(scope.engine.context, result);
}
fn throwValue(scope: *Scope, value: c.JSValue) anyerror {
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, c.JS_DupValue(scope.engine.context, value))) catch |err| return err;
    unreachable;
}
fn checkSignal(scope: *Scope, signal: c.JSValue) !void {
    if (!v.nullish(signal)) _ = try scope.invoke(signal, "throwIfAborted", &.{});
}
fn checkOptions(scope: *Scope, job: c.JSValue) !void {
    try checkSignal(scope, try v.optional(scope, try scope.get(job, "options"), "signal"));
}
fn startAcquire(scope: *Scope, job: c.JSValue, signal: c.JSValue, compromised: c.JSValue) !void {
    try scope.put(job, "signal", signal);
    try scope.put(job, "onCompromised", compromised);
    try scope.put(job, "deadline", try scope.own(try arithmetic.binary(scope.engine, .add, try dateNow(scope), c.JS_NewInt32(scope.engine.context, 30000))));
    try scope.put(job, "retry", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(job, "epermRetries", c.JS_NewInt32(scope.engine.context, 0));
    return attemptLock(scope, job);
}
fn attemptLock(scope: *Scope, job: c.JSValue) !void {
    try checkSignal(scope, try scope.get(job, "signal"));
    const generation = scope.engine.native_allocation_generation;
    const pending = lockAttempt(scope, job) catch |err| {
        const reason = try scope.own(flow.reason(scope.engine, err));
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return retryLock(scope, job, reason);
    };
    return flow.wait(acquireContinued, scope.engine, job, pending, @intFromEnum(Stage.lock));
}
fn lockAttempt(scope: *Scope, job: c.JSValue) !c.JSValue {
    const owner = try scope.get(job, "agent");
    const lockfile = try scope.get(owner, "lockfile");
    const lock = try scope.get(lockfile, "lock");
    const path = try scope.get(try scope.get(job, "self"), "authPath");
    const options = try scope.object();
    try scope.put(options, "realpath", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(options, "retries", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(options, "stale", c.JS_NewInt32(scope.engine.context, 30000));
    try scope.put(options, "onCompromised", try scope.get(job, "onCompromised"));
    return scope.call(lock, lockfile, &.{ path, options });
}
fn retryLock(scope: *Scope, job: c.JSValue, reason: c.JSValue) !void {
    try checkSignal(scope, try scope.get(job, "signal"));
    const code = try retryCode(scope, reason);
    const remaining = try scope.own(try arithmetic.binary(scope.engine, .subtract, try scope.get(job, "deadline"), try dateNow(scope)));
    if (!scope.truthy(code) or try arithmetic.compare(scope.engine, .less_equal, remaining, c.JS_NewInt32(scope.engine.context, 0))) return flow.settle(scope.engine, job, true, reason);
    if (try v.eq(scope, code, "EPERM")) {
        const count = try scope.own(try arithmetic.binary(scope.engine, .add, try scope.get(job, "epermRetries"), c.JS_NewInt32(scope.engine.context, 1)));
        try scope.put(job, "epermRetries", count);
        if (try arithmetic.compare(scope.engine, .greater, count, c.JS_NewInt32(scope.engine.context, 5))) return flow.settle(scope.engine, job, true, reason);
    }
    const math = try scope.global("Math");
    const min = try scope.get(math, "min");
    const power = try scope.own(try arithmetic.binary(scope.engine, .power, c.JS_NewInt32(scope.engine.context, 2), try scope.get(job, "retry")));
    const base = try scope.call(min, math, &.{ try scope.own(try arithmetic.binary(scope.engine, .multiply, c.JS_NewInt32(scope.engine.context, 10), power)), c.JS_NewInt32(scope.engine.context, 1000) });
    try scope.put(job, "retry", try scope.own(try arithmetic.binary(scope.engine, .add, try scope.get(job, "retry"), c.JS_NewInt32(scope.engine.context, 1))));
    const delay_math = try scope.global("Math");
    const delay_min = try scope.get(delay_math, "min");
    const round_math = try scope.global("Math");
    const round = try scope.get(round_math, "round");
    const factor = try scope.own(try arithmetic.binary(scope.engine, .add, c.JS_NewInt32(scope.engine.context, 1), try scope.invoke(try scope.global("Math"), "random", &.{})));
    const rounded = try scope.call(round, round_math, &.{try scope.own(try arithmetic.binary(scope.engine, .multiply, base, factor))});
    const delay = try scope.call(delay_min, delay_math, &.{ rounded, remaining });
    const owner = try scope.get(job, "agent");
    const signal = try scope.get(job, "signal");
    var sleeping: c.JSValue = undefined;
    if (scope.truthy(signal)) {
        const options = try scope.object();
        try scope.put(options, "signal", signal);
        sleeping = try imported(scope, owner, "sleep", &.{ delay, c.pi_js_undefined(), options });
    } else sleeping = try imported(scope, owner, "sleep", &.{delay});
    return flow.wait(acquireContinued, scope.engine, job, sleeping, @intFromEnum(Stage.sleep));
}
fn acquireContinued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .lock) return retryLock(&scope, job, value);
        return flow.settle(engine, job, true, value);
    }
    switch (stage) {
        .sleep => return attemptLock(&scope, job),
        .lock => {
            try scope.put(job, "release", value);
            const signal = try scope.get(job, "signal");
            if (!v.nullish(signal) and scope.truthy(try scope.get(signal, "aborted"))) {
                const released = try scope.call(value, c.pi_js_undefined(), &.{});
                return flow.wait(acquireContinued, engine, job, released, @intFromEnum(Stage.cancelled_release));
            }
            return flow.settle(engine, job, false, value);
        },
        .cancelled_release => {
            try checkSignal(&scope, try scope.get(job, "signal"));
            // A custom throwIfAborted may return. Source still returns release.
            return flow.settle(engine, job, false, try scope.get(job, "release"));
        },
        else => unreachable,
    }
}
fn startWithLock(scope: *Scope, job: c.JSValue, function: c.JSValue, options: c.JSValue) !void {
    try scope.put(job, "function", function);
    try scope.put(job, "options", options);
    try checkOptions(scope, job);
    const receiver = try scope.get(job, "self");
    _ = try scope.invoke(receiver, "ensureParentDir", &.{});
    _ = try scope.invoke(receiver, "ensureFileExists", &.{});
    try scope.put(job, "lockCompromised", c.pi_js_bool(scope.engine.context, 0));
    try scope.put(job, "lockCompromisedError", c.pi_js_undefined());
    const method = try scope.get(receiver, "acquireLockAsync");
    const signal = try v.optional(scope, options, "signal");
    const Callback = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            defer local.deinit();
            try local.put(roots[0], "lockCompromised", c.pi_js_bool(engine.context, 1));
            try local.put(roots[0], "lockCompromisedError", arg(args, 0));
            return c.pi_js_undefined();
        }
    };
    const compromised = try scope.own(try funcs.createArrow(scope.engine, "", 1, Callback.call, &.{job}));
    return flow.wait(withContinued, scope.engine, job, try scope.call(method, receiver, &.{ signal, compromised }), @intFromEnum(Stage.acquired));
}
fn checkCompromised(scope: *Scope, job: c.JSValue) !void {
    if (!scope.truthy(try scope.get(job, "lockCompromised"))) return;
    var reason = try scope.get(job, "lockCompromisedError");
    if (v.nullish(reason)) reason = try scope.own(try v.js.builtin(scope.engine, "Error", &.{try scope.text("Auth storage lock was compromised")}));
    return throwValue(scope, reason);
}
fn finishError(scope: *Scope, job: c.JSValue, err: anyerror) !void {
    return finish(scope, job, true, try scope.own(flow.reason(scope.engine, err)));
}
fn finish(scope: *Scope, job: c.JSValue, rejected: bool, value: c.JSValue) !void {
    const release = try scope.get(job, "release");
    if (!scope.truthy(release)) return flow.settle(scope.engine, job, rejected, value);
    try scope.put(job, "completion", value);
    try scope.put(job, "failed", c.pi_js_bool(scope.engine.context, @intFromBool(rejected)));
    const generation = scope.engine.native_allocation_generation;
    const returned = scope.call(release, c.pi_js_undefined(), &.{}) catch |err| {
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return flow.settle(scope.engine, job, rejected, value);
    };
    return flow.wait(withContinued, scope.engine, job, returned, @intFromEnum(Stage.release));
}
fn withContinued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .release) return flow.settle(engine, job, scope.truthy(try scope.get(job, "failed")), try scope.get(job, "completion"));
    if (rejected) return finish(&scope, job, true, value);
    advanceWith(&scope, job, value, stage) catch |err| try finishError(&scope, job, err);
}
fn advanceWith(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const receiver = try scope.get(job, "self");
    const owner = try scope.get(job, "agent");
    switch (stage) {
        .acquired => {
            try scope.put(job, "release", value);
            try checkCompromised(scope, job);
            try checkOptions(scope, job);
            const input = try current(scope, owner, receiver);
            const result = try scope.call(try scope.get(job, "function"), c.pi_js_undefined(), &.{input});
            return flow.wait(withContinued, scope.engine, job, result, @intFromEnum(Stage.callback));
        },
        .callback => {
            const result = try scope.get(value, "result");
            const next = try scope.get(value, "next");
            try checkCompromised(scope, job);
            try checkOptions(scope, job);
            if (!c.JS_IsUndefined(next)) _ = try imported(scope, owner, "writeFileSync", &.{ try scope.get(receiver, "authPath"), next, try scope.get(owner, "writeOptions") });
            try checkCompromised(scope, job);
            return finish(scope, job, false, result);
        },
        else => unreachable,
    }
}
