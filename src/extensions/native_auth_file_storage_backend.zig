//! FileAuthStorageBackend from pinned c268154c auth-storage.ts. Its two async
//! methods are genuine native AFs; the class and its other methods are ordinary.
//! Public and TypeScript-private methods remain observable prototype methods;
//! state is the Source own authPath field, not an opaque/plain-record adapter.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const body = @import("native_async_body.zig");
const af = body.native;
const owned = @import("native_sdk_owned_completion.zig");
const funcs = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Dependencies = struct { get_agent_dir: c.JSValue };
/// Production default retains c268154c's APP_NAME=pi, CONFIG_DIR_NAME=.pi.
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
            fn run(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
                return methodBody(host, receiver, args, roots, state, completion, input, kind);
            }
        };
        const length: c_int = switch (kind) {
            .ensureParentDir, .ensureFileExists => 0,
            .acquireLockAsync, .withLockAsync => 2,
            else => 1,
        };
        const method = try scope.own(if (kind == .acquireLockAsync or kind == .withLockAsync)
            try af.createResumable(engine, field.name, length, Adapter.run, &.{owner})
        else
            try funcs.createMethod(engine, field.name, length, Adapter.call, &.{owner}));
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
        .acquireLockAsync, .withLockAsync => unreachable,
    }
}
fn failed(engine: *v.em.Engine, err: anyerror) !af.Action {
    // Exact producers have already classified their own failed operation.
    // A body-wide generation would reclassify earlier successful DATA when a
    // later getter throws that same historical object. Preserve that reason.
    try engine.checkNativeEntry();
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        return .{ .thrown = reason };
    };
    return body.failure(engine, err);
}
fn methodBody(engine: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue, method: Method) !af.Action {
    var scope: Scope = .{ .engine = engine };
    return owned.finishAction(&scope, methodStep(&scope, receiver, args, roots, state, completion, input, method) catch |err| failed(engine, err));
}
fn methodStep(scope: *Scope, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: af.Completion, input: c.JSValue, method: Method) !af.Action {
    if (completion == .start) {
        const generation = scope.engine.native_allocation_generation;
        var writer: StateWriter = .{ .scope = scope, .engine = scope.engine };
        const job = try asyncNormal(scope, generation, body.init(&writer, state));
        try store(scope, job, "agent", roots[0]);
        try store(scope, job, "self", receiver);
        try store(scope, job, "release", c.pi_js_undefined());
        if (method == .acquireLockAsync) try startAcquire(scope, job, arg(args, 0), arg(args, 1))
        else try startWithLock(scope, job, arg(args, 0), arg(args, 1));
    } else {
        if (completion == .rejected) try body.enterRejectedContinuation(scope.engine);
        // The action record's extra reference to the already-awaited promise
        // is native bookkeeping, not a Source local needed in this stage.
        try retireAwaitedValue(scope, state.*);
        const stage_generation = scope.engine.native_allocation_generation;
        var reader: StateWriter = .{ .scope = scope, .engine = scope.engine };
        const stage = body.stage(&reader, state.*) catch |err| {
            _ = try asyncNormal(scope, stage_generation, @as(anyerror!c.JSValue, err));
            unreachable;
        };
        if (method == .acquireLockAsync) try acquireContinued(scope, state.*, input, completion == .rejected, stage)
        else try withContinued(scope, state.*, input, completion == .rejected, stage);
    }
    return selectedAction(scope, state.*);
}
fn selectedAction(scope: *Scope, job: c.JSValue) !af.Action {
    const generation = scope.engine.native_allocation_generation;
    var reader: StateWriter = .{ .scope = scope, .engine = scope.engine };
    return body.action(&reader, job) catch |err| {
        _ = try asyncNormal(scope, generation, @as(anyerror!c.JSValue, err));
        unreachable;
    };
}
fn retireAwaitedValue(scope: *Scope, job: c.JSValue) !void {
    const engine = scope.engine;
    const generation = engine.native_allocation_generation;
    const previous = try @import("native_agent_af_values.zig").guard(engine, generation, v.js.get(engine, job, "nativeAsyncValue"));
    var completion = owned.Completion.initVoid(engine, store(scope, job, "nativeAsyncValue", c.pi_js_undefined()));
    completion.release(previous);
    return completion.finishVoid();
}
fn wait(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    var writer: StateWriter = .{ .scope = scope, .engine = scope.engine };
    return body.wait(&writer, job, value, @intFromEnum(stage));
}
fn settle(scope: *Scope, job: c.JSValue, rejected: bool, value: c.JSValue) !void {
    var writer: StateWriter = .{ .scope = scope, .engine = scope.engine };
    return if (rejected) body.reject(&writer, job, value) else body.resolve(&writer, job, value);
}
const StateWriter = struct {
    scope: *Scope,
    engine: *v.em.Engine,
    pub fn put(self: *StateWriter, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
        return store(self.scope, target, name, value);
    }
    pub fn own(self: *StateWriter, value: c.JSValue) !c.JSValue { return owned.ownRoot(self.scope, value); }
    pub fn get(self: *StateWriter, target: c.JSValue, name: [*:0]const u8) !c.JSValue { return asyncGet(self.scope, target, name); }
};
fn recorded(scope: *Scope, result: anyerror!void, state: c.JSValue) owned.Completion {
    var reader: StateWriter = .{ .scope = scope, .engine = scope.engine };
    return owned.Completion.initRecorded(&reader, result, state);
}
fn store(scope: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try scope.engine.checkNativeEntry();
    const generation = scope.engine.native_allocation_generation;
    const result = scope.put(target, name, value);
    _ = try asyncNormal(scope, generation, if (result) |_| c.pi_js_undefined() else |err| err);
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
// New AF guest boundaries stop on successful native return + pending event,
// before any later getter/call/state write. Historical captured slots alone
// are not event authority. The inherited synchronous path above is unchanged.
fn asyncNormal(scope: *Scope, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
    const guards = @import("native_agent_af_values.zig");
    const value = try guards.guard(scope.engine, generation, result);
    _ = try guards.guard(scope.engine, generation, scope.engine.checked(c.pi_js_undefined()));
    try scope.engine.checkNativeEntry();
    return value;
}
fn asyncGet(scope: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncOwned(scope, generation, v.js.get(scope.engine, receiver, name));
}
fn asyncGlobal(scope: *Scope, name: [*:0]const u8) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncOwned(scope, generation, v.js.global(scope.engine, name));
}
fn asyncText(scope: *Scope, text: []const u8) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncOwned(scope, generation, @import("native_sdk.zig").text(scope.engine, text));
}
fn asyncObject(scope: *Scope) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncOwned(scope, generation, v.js.object(scope.engine));
}
fn asyncOwned(scope: *Scope, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
    const guards = @import("native_agent_af_values.zig");
    const value = try guards.guard(scope.engine, generation, result);
    const checked = try guards.guard(scope.engine, generation, scope.engine.checked(value));
    return owned.ownRoot(scope, checked);
}
fn asyncBinary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncNormal(scope, generation, arithmetic.binary(scope.engine, operation, left, right));
}
fn asyncCompare(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !bool {
    return scope.truthy(try owned.ownRoot(scope, try asyncBinary(scope, operation, left, right)));
}
fn asyncEq(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try asyncText(scope, text));
}
fn asyncCall(scope: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return asyncOwned(scope, generation, v.js.call(scope.engine, function, receiver, args));
}
fn asyncInvoke(scope: *Scope, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return asyncCall(scope, try asyncGet(scope, receiver, name), receiver, args);
}
fn asyncOptional(scope: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(receiver)) c.pi_js_undefined() else asyncGet(scope, receiver, name);
}
fn asyncImported(scope: *Scope, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return asyncCall(scope, try asyncGet(scope, owner, name), c.pi_js_undefined(), args);
}
fn asyncDateNow(scope: *Scope) !c.JSValue {
    return asyncInvoke(scope, try asyncGlobal(scope, "Date"), "now", &.{});
}
fn asyncRetryCode(scope: *Scope, reason: c.JSValue) !c.JSValue {
    const constructor = try asyncGlobal(scope, "Error");
    const generation = scope.engine.native_allocation_generation;
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, constructor);
    _ = try asyncNormal(scope, generation, if (instance < 0) v.js.capture(scope.engine) else c.pi_js_undefined());
    var code = c.pi_js_undefined();
    if (instance != 0) {
        const atom = c.JS_NewAtom(scope.engine.context, "code");
        if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
        defer c.JS_FreeAtom(scope.engine.context, atom);
        const has_generation = scope.engine.native_allocation_generation;
        const has = c.JS_HasProperty(scope.engine.context, reason, atom);
        _ = try asyncNormal(scope, has_generation, if (has < 0) v.js.capture(scope.engine) else c.pi_js_undefined());
        if (has != 0) code = try asyncGet(scope, reason, "code");
    }
    if (try asyncEq(scope, code, "ELOCKED")) return code;
    if (try asyncEq(scope, code, "EPERM") and try asyncEq(scope, try asyncGet(scope, try asyncGlobal(scope, "process"), "platform"), "win32")) return code;
    return c.pi_js_undefined();
}
fn asyncCurrent(scope: *Scope, owner: c.JSValue, receiver: c.JSValue) !c.JSValue {
    if (scope.truthy(try asyncImported(scope, owner, "existsSync", &.{try asyncGet(scope, receiver, "authPath")})))
        return asyncImported(scope, owner, "readFileSync", &.{ try asyncGet(scope, receiver, "authPath"), try asyncText(scope, "utf-8") });
    return c.pi_js_undefined();
}
fn checkSignal(scope: *Scope, signal: c.JSValue) !void {
    if (!v.nullish(signal)) _ = try asyncInvoke(scope, signal, "throwIfAborted", &.{});
}
fn checkOptions(scope: *Scope, job: c.JSValue) !void {
    try checkSignal(scope, try asyncOptional(scope, try asyncGet(scope, job, "options"), "signal"));
}
fn startAcquire(scope: *Scope, job: c.JSValue, signal: c.JSValue, compromised: c.JSValue) !void {
    try store(scope, job, "signal", signal);
    try store(scope, job, "onCompromised", compromised);
    try store(scope, job, "deadline", try owned.ownRoot(scope, try asyncBinary(scope, .add, try asyncDateNow(scope), c.JS_NewInt32(scope.engine.context, 30000))));
    try store(scope, job, "retry", c.JS_NewInt32(scope.engine.context, 0));
    try store(scope, job, "epermRetries", c.JS_NewInt32(scope.engine.context, 0));
    return attemptLock(scope, job);
}
fn attemptLock(scope: *Scope, job: c.JSValue) !void {
    try checkSignal(scope, try asyncGet(scope, job, "signal"));
    const pending = lockAttempt(scope, job) catch |err| {
        const action = try failed(scope.engine, err);
        const reason = switch (action) { .thrown => |value| value, else => unreachable };
        var completion = recorded(scope, retryLock(scope, job, reason), job);
        completion.release(reason);
        return completion.finishRecorded();
    };
    return wait(scope, job, pending, .lock);
}
fn lockAttempt(scope: *Scope, job: c.JSValue) !c.JSValue {
    const owner = try asyncGet(scope, job, "agent");
    const lockfile = try asyncGet(scope, owner, "lockfile");
    const lock = try asyncGet(scope, lockfile, "lock");
    const path = try asyncGet(scope, try asyncGet(scope, job, "self"), "authPath");
    const options = try asyncObject(scope);
    try store(scope, options, "realpath", c.pi_js_bool(scope.engine.context, 0));
    try store(scope, options, "retries", c.JS_NewInt32(scope.engine.context, 0));
    try store(scope, options, "stale", c.JS_NewInt32(scope.engine.context, 30000));
    try store(scope, options, "onCompromised", try asyncGet(scope, job, "onCompromised"));
    return asyncCall(scope, lock, lockfile, &.{ path, options });
}
fn retryLock(scope: *Scope, job: c.JSValue, reason: c.JSValue) !void {
    try checkSignal(scope, try asyncGet(scope, job, "signal"));
    const code = try asyncRetryCode(scope, reason);
    const remaining = try owned.ownRoot(scope, try asyncBinary(scope, .subtract, try asyncGet(scope, job, "deadline"), try asyncDateNow(scope)));
    if (!scope.truthy(code) or try asyncCompare(scope, .less_equal, remaining, c.JS_NewInt32(scope.engine.context, 0))) return settle(scope, job, true, reason);
    if (try asyncEq(scope, code, "EPERM")) {
        const count = try owned.ownRoot(scope, try asyncBinary(scope, .add, try asyncGet(scope, job, "epermRetries"), c.JS_NewInt32(scope.engine.context, 1)));
        try store(scope, job, "epermRetries", count);
        if (try asyncCompare(scope, .greater, count, c.JS_NewInt32(scope.engine.context, 5))) return settle(scope, job, true, reason);
    }
    const math = try asyncGlobal(scope, "Math");
    const min = try asyncGet(scope, math, "min");
    const power = try owned.ownRoot(scope, try asyncBinary(scope, .power, c.JS_NewInt32(scope.engine.context, 2), try asyncGet(scope, job, "retry")));
    const base = try asyncCall(scope, min, math, &.{ try owned.ownRoot(scope, try asyncBinary(scope, .multiply, c.JS_NewInt32(scope.engine.context, 10), power)), c.JS_NewInt32(scope.engine.context, 1000) });
    try store(scope, job, "retry", try owned.ownRoot(scope, try asyncBinary(scope, .add, try asyncGet(scope, job, "retry"), c.JS_NewInt32(scope.engine.context, 1))));
    const delay_math = try asyncGlobal(scope, "Math");
    const delay_min = try asyncGet(scope, delay_math, "min");
    const round_math = try asyncGlobal(scope, "Math");
    const round = try asyncGet(scope, round_math, "round");
    const factor = try owned.ownRoot(scope, try asyncBinary(scope, .add, c.JS_NewInt32(scope.engine.context, 1), try asyncInvoke(scope, try asyncGlobal(scope, "Math"), "random", &.{})));
    const rounded = try asyncCall(scope, round, round_math, &.{try owned.ownRoot(scope, try asyncBinary(scope, .multiply, base, factor))});
    const delay = try asyncCall(scope, delay_min, delay_math, &.{ rounded, remaining });
    const owner = try asyncGet(scope, job, "agent");
    const signal = try asyncGet(scope, job, "signal");
    var sleeping: c.JSValue = undefined;
    if (scope.truthy(signal)) {
        const options = try asyncObject(scope);
        try store(scope, options, "signal", signal);
        sleeping = try asyncImported(scope, owner, "sleep", &.{ delay, c.pi_js_undefined(), options });
    } else sleeping = try asyncImported(scope, owner, "sleep", &.{delay});
    return wait(scope, job, sleeping, .sleep);
}
fn acquireContinued(scope: *Scope, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    const stage: Stage = @enumFromInt(raw);
    if (rejected) {
        if (stage == .lock) return retryLock(scope, job, value);
        return settle(scope, job, true, value);
    }
    switch (stage) {
        .sleep => return attemptLock(scope, job),
        .lock => {
            try store(scope, job, "release", value);
            const signal = try asyncGet(scope, job, "signal");
            if (!v.nullish(signal) and scope.truthy(try asyncGet(scope, signal, "aborted"))) {
                const released = try asyncCall(scope, value, c.pi_js_undefined(), &.{});
                return wait(scope, job, released, .cancelled_release);
            }
            return settle(scope, job, false, value);
        },
        .cancelled_release => {
            try checkSignal(scope, try asyncGet(scope, job, "signal"));
            // A custom throwIfAborted may return. Source still returns release.
            return settle(scope, job, false, try asyncGet(scope, job, "release"));
        },
        else => unreachable,
    }
}
fn startWithLock(scope: *Scope, job: c.JSValue, function: c.JSValue, options: c.JSValue) !void {
    try store(scope, job, "function", function);
    try store(scope, job, "options", options);
    try checkOptions(scope, job);
    const receiver = try asyncGet(scope, job, "self");
    _ = try asyncInvoke(scope, receiver, "ensureParentDir", &.{});
    _ = try asyncInvoke(scope, receiver, "ensureFileExists", &.{});
    try store(scope, job, "lockCompromised", c.pi_js_bool(scope.engine.context, 0));
    try store(scope, job, "lockCompromisedError", c.pi_js_undefined());
    const action = try withTry(scope.engine, job, c.pi_js_undefined(), .acquired, true, receiver, options);
    return finishTryAction(scope, job, action);
}
fn beginWithLock(scope: *Scope, job: c.JSValue, receiver: c.JSValue, options: c.JSValue) !void {
    const method = try asyncGet(scope, receiver, "acquireLockAsync");
    const signal = try asyncOptional(scope, options, "signal");
    const Callback = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            var local: Scope = .{ .engine = engine };
            return owned.finishValue(&local, apply(&local, args, roots));
        }
        fn apply(local: *Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const engine = local.engine;
            try store(local, roots[0], "lockCompromised", c.pi_js_bool(engine.context, 1));
            try store(local, roots[0], "lockCompromisedError", arg(args, 0));
            return c.pi_js_undefined();
        }
    };
    const generation = scope.engine.native_allocation_generation;
    const compromised = try asyncOwned(scope, generation, funcs.createArrow(scope.engine, "", 1, Callback.call, &.{job}));
    return wait(scope, job, try asyncCall(scope, method, receiver, &.{ signal, compromised }), .acquired);
}
fn checkCompromised(scope: *Scope, job: c.JSValue) !void {
    if (!scope.truthy(try asyncGet(scope, job, "lockCompromised"))) return;
    var reason = try asyncGet(scope, job, "lockCompromisedError");
    if (v.nullish(reason)) {
        const constructor = try asyncGlobal(scope, "Error");
        var args = [_]c.JSValue{try asyncText(scope, "Auth storage lock was compromised")};
        const generation = scope.engine.native_allocation_generation;
        reason = try asyncOwned(scope, generation, scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args)));
    }
    return throwValue(scope, reason);
}
fn finishTryAction(scope: *Scope, job: c.JSValue, action: af.Action) !void {
    // The Source try block's roots have already retired under their owned
    // completion. Only then execute Source finally's actual release/Await.
    const Selection = struct { rejected: bool, value: c.JSValue };
    const selected: Selection = switch (action) {
        .awaited => |pending| {
            var completion = recorded(scope, {}, job);
            completion.release(pending);
            return completion.finishRecorded();
        },
        .returned => |result| .{ .rejected = false, .value = result },
        .thrown => |reason| .{ .rejected = true, .value = reason },
    };
    var completion = recorded(scope, finish(scope, job, selected.rejected, selected.value), job);
    completion.release(selected.value);
    return completion.finishRecorded();
}
fn withTry(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, stage: Stage, initial: bool, receiver: c.JSValue, options: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    return owned.finishAction(&scope, withTryBody(&scope, job, value, stage, initial, receiver, options) catch |err| failed(engine, err));
}
fn withTryBody(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage, initial: bool, receiver: c.JSValue, options: c.JSValue) !af.Action {
    if (initial) {
        try beginWithLock(scope, job, receiver, options);
    } else if (stage == .callback) {
        return .{ .returned = c.JS_DupValue(scope.engine.context, try callbackResult(scope, job, value)) };
    } else try advanceWith(scope, job, value, stage);
    return selectedAction(scope, job);
}
fn finish(scope: *Scope, job: c.JSValue, rejected: bool, value: c.JSValue) !void {
    const release = try asyncGet(scope, job, "release");
    if (!scope.truthy(release)) return settle(scope, job, rejected, value);
    try store(scope, job, "completion", value);
    try store(scope, job, "failed", c.pi_js_bool(scope.engine.context, @intFromBool(rejected)));
    const returned = asyncCall(scope, release, c.pi_js_undefined(), &.{}) catch |err| {
        const action = try failed(scope.engine, err);
        const ignored = switch (action) { .thrown => |reason| reason, else => unreachable };
        var completion = recorded(scope, settle(scope, job, rejected, value), job);
        completion.release(ignored);
        return completion.finishRecorded();
    };
    return wait(scope, job, returned, .release);
}
fn withContinued(scope: *Scope, job: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) !void {
    const stage: Stage = @enumFromInt(raw);
    if (stage == .release) return settle(scope, job, scope.truthy(try asyncGet(scope, job, "failed")), try asyncGet(scope, job, "completion"));
    if (rejected) return finish(scope, job, true, value);
    return finishTryAction(scope, job, try withTry(scope.engine, job, value, stage, false, c.pi_js_undefined(), c.pi_js_undefined()));
}
fn advanceWith(scope: *Scope, job: c.JSValue, value: c.JSValue, stage: Stage) !void {
    const receiver = try asyncGet(scope, job, "self");
    const owner = try asyncGet(scope, job, "agent");
    switch (stage) {
        .acquired => {
            try store(scope, job, "release", value);
            try checkCompromised(scope, job);
            try checkOptions(scope, job);
            const input = try asyncCurrent(scope, owner, receiver);
            const result = try asyncCall(scope, try asyncGet(scope, job, "function"), c.pi_js_undefined(), &.{input});
            return wait(scope, job, result, .callback);
        },
        else => unreachable,
    }
}
fn callbackResult(scope: *Scope, job: c.JSValue, value: c.JSValue) !c.JSValue {
    const result = try asyncGet(scope, value, "result");
    const next = try asyncGet(scope, value, "next");
    try checkCompromised(scope, job);
    try checkOptions(scope, job);
    if (!c.JS_IsUndefined(next)) {
        const receiver = try asyncGet(scope, job, "self");
        const owner = try asyncGet(scope, job, "agent");
        _ = try asyncImported(scope, owner, "writeFileSync", &.{ try asyncGet(scope, receiver, "authPath"), next, try asyncGet(scope, owner, "writeOptions") });
    }
    try checkCompromised(scope, job);
    return result;
}
