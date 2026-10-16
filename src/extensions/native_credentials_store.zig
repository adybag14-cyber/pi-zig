//! Actual ordinary auth/credential-store.ts class. Fields, receivers, methods,
//! Promise operations, cancellation getters and unknown credentials stay live.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const classes = @import("native_class.zig");
const flow = @import("native_agent_async.zig");
const Method = enum { enqueue, read, list, modify, delete };
const Stage = enum(c_int) { previous, mutation };
const cache_key = "\x00actual-in-memory-credential-store-constructor";
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn arrow(s: *Scope, callback: functions.Callback, arity: c_int, roots: []const c.JSValue, asynchronous: bool) !c.JSValue {
    const result = try s.own(try functions.createArrow(s.engine, "", arity, callback, roots));
    if (asynchronous) {
        const prototype = try s.own(try s.engine.checked(c.JS_GetAsyncFunctionPrototype(s.engine.context)));
        if (c.JS_SetPrototype(s.engine.context, result, prototype) < 0) return v.js.capture(s.engine);
    }
    return result;
}
pub fn constructor(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |cached| return c.JS_DupValue(engine.context, cached);
    if (engine.abort_signal_class == 0) try @import("abort_signal.zig").install(engine);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const imports = try s.own(try @import("native_ai_auth_abort.zig").create(engine));
    const prototype = try s.object();
    const result = try s.own(try classes.constructor(engine, "InMemoryCredentialStore", 0, prototype, construct, &.{}));
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                return dispatch(host, receiver, method, args, roots[0]);
            }
        };
        const arity: c_int = switch (method) {
            .enqueue, .modify => 3,
            .read, .delete => 2,
            .list => 1,
        };
        const callback = try s.own(try functions.createMethod(engine, field.name, arity, Adapter.call, &.{imports}));
        if (method == .read or method == .list) {
            const async_prototype = try s.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
            if (c.JS_SetPrototype(engine.context, callback, async_prototype) < 0) return v.js.capture(engine);
        }
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, callback), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
    const retained = c.JS_DupValue(engine.context, result);
    engine.native_module_values.put(engine.gpa, cache_key, retained) catch |err| {
        engine.freeValue(retained);
        return err;
    };
    return c.JS_DupValue(engine.context, result);
}
fn construct(engine: *v.em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.own(try classes.object(engine, target));
    try s.put(result, "credentials", try s.own(try v.js.builtin(engine, "Map", &.{})));
    try s.put(result, "chains", try s.own(try v.js.builtin(engine, "Map", &.{})));
    return c.JS_DupValue(engine.context, result);
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    const ctor = try constructor(engine);
    defer engine.freeValue(ctor);
    return engine.checked(c.JS_CallConstructor(engine.context, ctor, 0, null));
}
pub fn install(engine: *v.em.Engine, exports: c.JSValue) !void {
    const ctor = try constructor(engine);
    defer engine.freeValue(ctor);
    try v.js.define(engine, exports, "InMemoryCredentialStore", c.JS_DupValue(engine.context, ctor));
}
fn checkOptionalSignal(s: *Scope, options: c.JSValue) !void {
    const signal = try v.optional(s, options, "signal");
    if (!v.nullish(signal)) _ = try s.invoke(signal, "throwIfAborted", &.{});
}
fn dispatch(engine: *v.em.Engine, receiver: c.JSValue, method: Method, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const id = arg(args, 0);
    if (method == .read or method == .list) {
        const pending = try flow.create(engine, receiver);
        defer engine.freeValue(pending.owner);
        errdefer engine.freeValue(pending.promise);
        readOrList(&s, pending.owner, receiver, method, args) catch |err| try flow.rejectError(engine, pending.owner, err);
        return pending.promise;
    }
    if (method == .enqueue) return enqueue(&s, receiver, id, arg(args, 1), arg(args, 2), imports);
    // Dynamic this.enqueue lookup precedes allocating the async task argument.
    const enqueue_method = try s.get(receiver, "enqueue");
    const options = arg(args, if (method == .modify) 2 else 1);
    const task = if (method == .modify)
        try arrow(&s, mutationTask, 0, &.{ receiver, id, arg(args, 1), options }, true)
    else
        try arrow(&s, deleteTask, 0, &.{ receiver, id }, true);
    return c.JS_DupValue(engine.context, try s.call(enqueue_method, receiver, &.{ id, task, options }));
}
fn readOrList(s: *Scope, job: c.JSValue, receiver: c.JSValue, method: Method, args: []const c.JSValue) !void {
    try checkOptionalSignal(s, arg(args, if (method == .read) 1 else 0));
    const credentials = try s.get(receiver, "credentials");
    if (method == .read) return flow.settle(s.engine, job, false, try s.invoke(credentials, "get", &.{arg(args, 0)}));
    // Source completes the iterable spread before any row mapping side effects.
    const entries = try s.array();
    var iterator = try v.iterator(s, credentials);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry);
        try s.index(entries, index, entry);
        index += 1;
    }
    try flow.settle(s.engine, job, false, try s.invoke(entries, "map", &.{try arrow(s, listEntry, 1, &.{}, false)}));
}
fn listEntry(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    var iterator = try v.iterator(&s, arg(args, 0));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    const id = if (try iterator.next()) |value| try s.own(value) else c.pi_js_undefined();
    const credential = if (iterator.closed) c.pi_js_undefined() else if (try iterator.next()) |value| try s.own(value) else c.pi_js_undefined();
    try iterator.close();
    const result = try s.object();
    try s.put(result, "providerId", id);
    try s.put(result, "type", try s.get(credential, "type"));
    return c.JS_DupValue(engine.context, result);
}
fn noop(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
fn enqueue(s: *Scope, receiver: c.JSValue, id: c.JSValue, task: c.JSValue, options: c.JSValue, imports: c.JSValue) !c.JSValue {
    const signal = try s.call(try s.get(imports, "operationSignal"), c.pi_js_undefined(), &.{try v.optional(s, options, "signal")});
    const before = try s.invoke(try s.get(receiver, "chains"), "get", &.{id});
    const previous = if (v.nullish(before)) try s.invoke(try s.global("Promise"), "resolve", &.{}) else before;
    const pending = try flow.create(s.engine, receiver);
    defer s.engine.freeValue(pending.owner);
    defer s.engine.freeValue(pending.promise);
    try s.put(pending.owner, "signal", signal);
    try s.put(pending.owner, "task", task);
    queuedStart(s, pending.owner, previous) catch |err| try flow.rejectError(s.engine, pending.owner, err);
    const tail = try s.invoke(pending.promise, "catch", &.{try arrow(s, noop, 0, &.{}, false)});
    _ = try s.invoke(try s.get(receiver, "chains"), "set", &.{ id, tail });
    _ = try s.invoke(tail, "then", &.{try arrow(s, cleanTail, 0, &.{ receiver, id, tail }, false)});
    return c.JS_DupValue(s.engine.context, try s.call(try s.get(imports, "raceWithAbortSignal"), c.pi_js_undefined(), &.{ pending.promise, signal }));
}
fn queuedStart(s: *Scope, job: c.JSValue, previous: c.JSValue) !void {
    const caught = try s.invoke(previous, "catch", &.{try arrow(s, noop, 0, &.{}, false)});
    try flow.wait(continued, s.engine, job, caught, @intFromEnum(Stage.previous));
}
fn cleanTail(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (s.equal(try s.invoke(try s.get(roots[0], "chains"), "get", &.{roots[1]}), roots[2])) _ = try s.invoke(try s.get(roots[0], "chains"), "delete", &.{roots[1]});
    return c.pi_js_undefined();
}
fn deleteTask(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    deleteBody(&s, pending.owner, roots) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn deleteBody(s: *Scope, job: c.JSValue, roots: []const c.JSValue) !void {
    _ = try s.invoke(try s.get(roots[0], "credentials"), "delete", &.{roots[1]});
    try flow.settle(s.engine, job, false, c.pi_js_undefined());
}
fn mutationTask(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const pending = try flow.create(engine, roots[0]);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    inline for (.{ "self", "id", "callback", "options" }, 0..) |name, index| try s.put(pending.owner, name, roots[index]);
    mutationStart(&s, pending.owner) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn mutationStart(s: *Scope, job: c.JSValue) !void {
    const current = try s.invoke(try s.get(try s.get(job, "self"), "credentials"), "get", &.{try s.get(job, "id")});
    try s.put(job, "current", current);
    try flow.wait(continued, s.engine, job, try s.call(try s.get(job, "callback"), c.pi_js_undefined(), &.{current}), @intFromEnum(Stage.mutation));
}
fn continued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    if (failed) return flow.settle(engine, job, true, value);
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (@as(Stage, @enumFromInt(raw_stage))) {
        .previous => {
            _ = try s.invoke(try s.get(job, "signal"), "throwIfAborted", &.{});
            try flow.settle(engine, job, false, try s.call(try s.get(job, "task"), c.pi_js_undefined(), &.{}));
        },
        .mutation => {
            try checkOptionalSignal(&s, try s.get(job, "options"));
            if (!c.JS_IsUndefined(value)) _ = try s.invoke(try s.get(try s.get(job, "self"), "credentials"), "set", &.{ try s.get(job, "id"), value });
            try flow.settle(engine, job, false, if (v.nullish(value)) try s.get(job, "current") else value);
        },
    }
}
