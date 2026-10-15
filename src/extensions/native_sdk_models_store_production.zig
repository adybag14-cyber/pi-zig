//! Actual latest models-store classes. Ordinary instance fields stay observable.
//! File coordination composes mandatory real imported filesystem/lock helpers.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const flow = @import("native_agent_async.zig");
const classes = @import("native_class.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const Method = enum(c_int) { memory_read, memory_write, memory_delete, parse, update, reload, latest, read, write, delete, reload_callback, write_callback, delete_callback, clear_reload };
const Stage = enum(c_int) { latest, read, modified };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn construct(scope: *Scope, constructor: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, @intCast(args.len), @constCast(args.ptr))));
}
fn function(scope: *Scope, method: Method, name: [*:0]const u8, length: c_int, roots: []const c.JSValue, asynchronous: bool) !c.JSValue {
    const value = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, dispatch, name, length, @intFromEnum(method), @intCast(roots.len), @constCast(roots.ptr))));
    if (asynchronous) {
        const prototype = try scope.own(try scope.engine.checked(c.JS_GetAsyncFunctionPrototype(scope.engine.context)));
        if (c.JS_SetPrototype(scope.engine.context, value, prototype) < 0) return v.js.capture(scope.engine);
    }
    return value;
}
fn define(scope: *Scope, prototype: c.JSValue, method: Method, name: [*:0]const u8, length: c_int, env: c.JSValue, asynchronous: bool) !void {
    if (c.JS_DefinePropertyValueStr(scope.engine.context, prototype, name, c.JS_DupValue(scope.engine.context, try function(scope, method, name, length, &.{env}, asynchronous)), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return v.js.capture(scope.engine);
}
pub fn create(engine: *v.em.Engine, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = try scope.object();
    inline for (.{ "join", "getAgentDir", "normalizePath", "getFileRevision", "raceWithAbortSignal", "FileAuthStorageBackend" }) |name| {
        const value = try scope.get(imports, name);
        if (!c.JS_IsFunction(engine.context, value)) return error.MissingActualModelsStoreImport;
        try scope.put(env, name, value);
    }
    try scope.put(env, "shared", c.pi_js_undefined());
    const exports = try scope.object();
    try scope.put(exports, "InMemoryModelsStore", try scope.own(try createInMemory(engine)));
    try scope.put(exports, "InMemoryCodingAgentModelsStore", try scope.own(try createInMemoryCodingAgent(engine)));
    const prototype = try scope.object();
    inline for (.{ .{ Method.parse, "parse", 1, false }, .{ Method.update, "updateReadState", 3, false }, .{ Method.reload, "reloadFromStorage", 2, false }, .{ Method.latest, "readLatest", 2, true }, .{ Method.read, "read", 2, true }, .{ Method.write, "write", 3, true }, .{ Method.delete, "delete", 2, true } }) |entry| try define(&scope, prototype, entry[0], entry[1], entry[2], env, entry[3]);
    try scope.put(exports, "FileModelsStore", try scope.own(try classes.constructor(engine, "FileModelsStore", 0, prototype, fileConstructor, &.{env})));
    return c.JS_DupValue(engine.context, exports);
}
fn memoryClass(engine: *v.em.Engine, comptime name: [:0]const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try define(&scope, prototype, .memory_read, "read", 2, c.pi_js_undefined(), true);
    try define(&scope, prototype, .memory_write, "write", 3, c.pi_js_undefined(), true);
    try define(&scope, prototype, .memory_delete, "delete", 2, c.pi_js_undefined(), true);
    return classes.constructor(engine, name, 0, prototype, memoryConstructor, &.{});
}
pub fn createInMemory(engine: *v.em.Engine) !c.JSValue {
    return memoryClass(engine, "InMemoryModelsStore");
}
pub fn createInMemoryCodingAgent(engine: *v.em.Engine) !c.JSValue {
    return memoryClass(engine, "InMemoryCodingAgentModelsStore");
}
fn memoryConstructor(engine: *v.em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.own(try classes.object(engine, target));
    try scope.put(object, "entries", try construct(&scope, try scope.global("Map"), &.{}));
    return c.JS_DupValue(engine.context, object);
}
fn imported(scope: *Scope, env: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    return scope.call(try scope.get(env, name), c.pi_js_undefined(), args);
}
fn fileConstructor(engine: *v.em.Engine, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const env = roots[0];
    var path = arg(args, 0);
    if (c.JS_IsUndefined(path)) {
        const join = try scope.get(env, "join");
        path = try scope.call(join, c.pi_js_undefined(), &.{ try imported(&scope, env, "getAgentDir", &.{}), try scope.text("models-store.json") });
    }
    const object = try scope.own(try classes.object(engine, target));
    inline for (.{ "storage", "path", "readState" }) |name| try scope.put(object, name, c.pi_js_undefined());
    try scope.set(object, "path", try imported(&scope, env, "normalizePath", &.{path}));
    try scope.set(object, "storage", try construct(&scope, try scope.get(env, "FileAuthStorageBackend"), &.{try scope.get(object, "path")}));
    const shared = try scope.get(env, "shared");
    const read_state = if (!v.nullish(shared) and scope.equal(try scope.get(shared, "path"), try scope.get(object, "path"))) try scope.get(shared, "readState") else new_state: {
        const state = try scope.object();
        try scope.put(state, "data", try scope.object());
        break :new_state state;
    };
    try scope.set(object, "readState", read_state);
    if (!scope.truthy(shared)) {
        const next = try scope.object();
        try scope.put(next, "path", try scope.get(object, "path"));
        try scope.put(next, "readState", try scope.get(object, "readState"));
        try scope.set(env, "shared", next);
    }
    return c.JS_DupValue(engine.context, object);
}
fn signal(scope: *Scope, options: c.JSValue) !c.JSValue {
    return v.optional(scope, options, "signal");
}
fn check(scope: *Scope, options: c.JSValue) !void {
    const value = try signal(scope, options);
    if (!v.nullish(value)) _ = try scope.invoke(value, "throwIfAborted", &.{});
}
fn clone(scope: *Scope, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global("structuredClone"), c.pi_js_undefined(), &.{value});
}
fn parse(scope: *Scope, content: c.JSValue) !c.JSValue {
    if (!scope.truthy(content)) return scope.object();
    const json = try scope.global("JSON");
    const parse_fn = try scope.get(json, "parse");
    const first = try scope.invoke(content, "charCodeAt", &.{c.JS_NewInt32(scope.engine.context, 0)});
    const stripped = if (scope.equal(first, c.JS_NewInt32(scope.engine.context, 0xfeff))) try scope.invoke(content, "slice", &.{c.JS_NewInt32(scope.engine.context, 1)}) else content;
    return scope.call(parse_fn, json, &.{stripped});
}
fn update(scope: *Scope, state: c.JSValue, data: c.JSValue, revision: c.JSValue) !void {
    try scope.set(state, "data", data);
    try scope.set(state, "revision", revision);
}
fn dispatch(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const method: Method = @enumFromInt(raw);
    const args: []const c.JSValue = if (argc > 0) argv[0..@intCast(argc)] else &.{};
    if (method == .parse or method == .update or method == .reload or method == .clear_reload) return sync(engine, receiver, method, args, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
    return asynchronous(engine, receiver, method, args, roots[0]) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn sync(engine: *v.em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue, env: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    switch (method) {
        .parse => return c.JS_DupValue(engine.context, try parse(&scope, arg(args, 0))),
        .update => {
            try update(&scope, arg(args, 0), arg(args, 1), arg(args, 2));
            return c.pi_js_undefined();
        },
        .reload => {
            const job = try scope.object();
            try scope.put(job, "receiver", receiver);
            try scope.put(job, "env", env);
            try scope.put(job, "readState", arg(args, 0));
            const callback = try function(&scope, .reload_callback, "", 1, &.{job}, true);
            return v.js.invoke(engine, try scope.get(receiver, "storage"), "withLockAsync", &.{ callback, arg(args, 1) });
        },
        .clear_reload => {
            const state = try scope.get(env, "state");
            if (scope.equal(try scope.get(state, "reload"), try scope.get(env, "reload"))) try scope.set(state, "reload", c.pi_js_undefined());
            return c.pi_js_undefined();
        },
        else => unreachable,
    }
}
fn asynchronous(engine: *v.em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue, env: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    start(engine, pending.owner, receiver, method, args, env) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn start(engine: *v.em.Engine, owner: c.JSValue, receiver: c.JSValue, method: Method, args: []const c.JSValue, env: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (method == .memory_read or method == .memory_write or method == .memory_delete) {
        try check(&scope, arg(args, if (method == .memory_write) 2 else 1));
        const entries = try scope.get(receiver, "entries");
        var result = c.pi_js_undefined();
        if (method == .memory_read) {
            const entry = try scope.invoke(entries, "get", &.{arg(args, 0)});
            if (scope.truthy(entry)) result = try clone(&scope, entry);
        } else if (method == .memory_write) {
            const set = try scope.get(entries, "set");
            _ = try scope.call(set, entries, &.{ arg(args, 0), try clone(&scope, arg(args, 1)) });
        } else _ = try scope.invoke(entries, "delete", &.{arg(args, 0)});
        return flow.settle(engine, owner, false, result);
    }
    if (method == .reload_callback) {
        const target = try scope.get(env, "receiver");
        const data = try scope.invoke(target, "parse", &.{arg(args, 0)});
        const update_fn = try scope.get(target, "updateReadState");
        const state = try scope.get(env, "readState");
        const imported_env = try scope.get(env, "env");
        const revision = try imported(&scope, imported_env, "getFileRevision", &.{try scope.get(target, "path")});
        _ = try scope.call(update_fn, target, &.{ state, data, revision });
        const output = try scope.object();
        try scope.put(output, "result", data);
        return flow.settle(engine, owner, false, output);
    }
    if (method == .write_callback or method == .delete_callback) {
        const target = try scope.get(env, "agent");
        const current = try scope.invoke(target, "parse", &.{arg(args, 0)});
        const id = try scope.get(env, "id");
        if (method == .write_callback) {
            const atom = c.JS_ValueToAtom(engine.context, id);
            if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
            defer c.JS_FreeAtom(engine.context, atom);
            const cloned = try clone(&scope, try scope.get(env, "entry"));
            if (c.JS_SetProperty(engine.context, current, atom, c.JS_DupValue(engine.context, cloned)) < 0) return v.js.capture(engine);
        } else {
            const atom = c.JS_ValueToAtom(engine.context, id);
            if (atom == c.JS_ATOM_NULL) return v.js.capture(engine);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, current, atom, c.JS_PROP_THROW) < 0) return v.js.capture(engine);
        }
        try scope.put(env, "latest", current);
        const output = try scope.object();
        try scope.put(output, "result", c.pi_js_undefined());
        try scope.put(output, "next", try scope.invoke(try scope.global("JSON"), "stringify", &.{ current, c.pi_js_null(), c.JS_NewInt32(engine.context, 2) }));
        return flow.settle(engine, owner, false, output);
    }
    try scope.put(owner, "env", env);
    try scope.put(owner, "options", arg(args, if (method == .write) 2 else 1));
    try scope.put(owner, "id", arg(args, 0));
    if (method == .read) {
        const read_fn = try scope.get(receiver, "readLatest");
        const pending = try scope.call(read_fn, receiver, &.{ try scope.get(receiver, "readState"), arg(args, 1) });
        return flow.wait(continued, engine, owner, pending, @intFromEnum(Stage.read));
    }
    if (method == .write or method == .delete) {
        try scope.put(owner, "entry", arg(args, 1));
        try scope.put(owner, "latest", c.pi_js_undefined());
        const storage = try scope.get(receiver, "storage");
        const lock_fn = try scope.get(storage, "withLockAsync");
        const body = try function(&scope, if (method == .write) .write_callback else .delete_callback, "", 1, &.{owner}, true);
        return flow.wait(continued, engine, owner, try scope.call(lock_fn, storage, &.{ body, arg(args, if (method == .write) 2 else 1) }), @intFromEnum(Stage.modified));
    }
    const read_state = arg(args, 0);
    const options = arg(args, 1);
    try scope.put(owner, "options", options);
    try check(&scope, options);
    const revision = try imported(&scope, env, "getFileRevision", &.{try scope.get(receiver, "path")});
    if (!c.JS_IsUndefined(revision) and scope.equal(revision, try scope.get(read_state, "revision"))) return flow.settle(engine, owner, false, try scope.get(read_state, "data"));
    if (!scope.truthy(try scope.get(read_state, "reload"))) {
        const controller = try construct(&scope, try scope.global("AbortController"), &.{});
        const reload = try scope.object();
        try scope.put(reload, "controller", controller);
        const reload_fn = try scope.get(receiver, "reloadFromStorage");
        const reload_options = try scope.object();
        try scope.put(reload_options, "signal", try scope.get(controller, "signal"));
        try scope.put(reload, "promise", try scope.call(reload_fn, receiver, &.{ read_state, reload_options }));
        try scope.put(reload, "readers", c.JS_NewInt32(engine.context, 0));
        try scope.set(read_state, "reload", reload);
        const clear_env = try scope.object();
        try scope.put(clear_env, "state", read_state);
        try scope.put(clear_env, "reload", reload);
        const clear_good = try function(&scope, .clear_reload, "", 0, &.{clear_env}, false);
        const clear_bad = try function(&scope, .clear_reload, "", 0, &.{clear_env}, false);
        _ = try scope.invoke(try scope.get(reload, "promise"), "then", &.{ clear_good, clear_bad });
    }
    const reload = try scope.get(read_state, "reload");
    try scope.put(owner, "readState", read_state);
    try scope.put(owner, "reload", reload);
    try scope.set(reload, "readers", try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, try scope.get(reload, "readers")))));
    const wait = try scope.get(env, "raceWithAbortSignal");
    const raced = scope.call(wait, c.pi_js_undefined(), &.{ try scope.get(reload, "promise"), try signal(&scope, options) }) catch |err| {
        try finishLatest(&scope, owner);
        return err;
    };
    try flow.wait(continued, engine, owner, raced, @intFromEnum(Stage.latest));
}
fn finishLatest(scope: *Scope, owner: c.JSValue) !void {
    const reload = try scope.get(owner, "reload");
    const state = try scope.get(owner, "readState");
    try scope.set(reload, "readers", try scope.own(try arithmetic.binary(scope.engine, .subtract, try scope.get(reload, "readers"), c.JS_NewInt32(scope.engine.context, 1))));
    if (scope.equal(try scope.get(reload, "readers"), c.JS_NewInt32(scope.engine.context, 0)) and scope.equal(try scope.get(state, "reload"), reload)) {
        try scope.set(state, "reload", c.pi_js_undefined());
        _ = try scope.invoke(try scope.get(reload, "controller"), "abort", &.{});
    }
}
fn continued(engine: *v.em.Engine, owner: c.JSValue, value: c.JSValue, failed: bool, raw: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .latest) {
        try finishLatest(&scope, owner);
        return flow.settle(engine, owner, failed, value);
    }
    if (failed) return flow.settle(engine, owner, true, value);
    if (stage == .read) {
        const entry = try scope.own(try v.js.getKey(engine, value, try scope.get(owner, "id")));
        try check(&scope, try scope.get(owner, "options"));
        return flow.settle(engine, owner, false, if (scope.truthy(entry)) try clone(&scope, entry) else c.pi_js_undefined());
    }
    const latest = try scope.get(owner, "latest");
    if (scope.truthy(latest)) {
        const receiver = try scope.get(owner, "agent");
        const update_fn = try scope.get(receiver, "updateReadState");
        _ = try scope.call(update_fn, receiver, &.{ try scope.get(receiver, "readState"), latest });
    }
    try flow.settle(engine, owner, false, c.pi_js_undefined());
}
