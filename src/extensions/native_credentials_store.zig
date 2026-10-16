//! Actual ordinary auth/credential-store.ts class. Fields, receivers, methods,
//! Promise operations, cancellation getters and unknown credentials stay live.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const functions = @import("native_node_function.zig");
const classes = @import("native_class.zig");
const body = @import("native_async_body.zig");
const native = body.native;
const Method = enum { enqueue, read, list, modify, delete };
const Stage = enum(c_int) { previous, mutation };
const cache_key = "\x00actual-in-memory-credential-store-constructor";
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn arrow(s: *Scope, callback: functions.Callback, arity: c_int, roots: []const c.JSValue, asynchronous: bool) !c.JSValue {
    return s.own(if (asynchronous)
        try native.createArrow(s.engine, "", arity, callback, roots, c.pi_js_undefined())
    else
        try functions.createArrow(s.engine, "", arity, callback, roots));
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
        const callback = try s.own(if (method == .read or method == .list)
            try native.create(engine, field.name, arity, Adapter.call, &.{imports})
        else
            try functions.createMethod(engine, field.name, arity, Adapter.call, &.{imports}));
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
    if (method == .read or method == .list) return readOrList(&s, receiver, method, args);
    if (method == .enqueue) return enqueue(&s, receiver, id, arg(args, 1), arg(args, 2), imports);
    // Dynamic this.enqueue lookup precedes allocating the async task argument.
    const enqueue_method = try s.get(receiver, "enqueue");
    const options = arg(args, if (method == .modify) 2 else 1);
    const task = if (method == .modify)
        try s.own(try native.createResumableArrow(engine, "", 0, mutationTask, &.{ receiver, id, arg(args, 1), options }, c.pi_js_undefined()))
    else
        try arrow(&s, deleteTask, 0, &.{ receiver, id }, true);
    return c.JS_DupValue(engine.context, try s.call(enqueue_method, receiver, &.{ id, task, options }));
}
fn readOrList(s: *Scope, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    try checkOptionalSignal(s, arg(args, if (method == .read) 1 else 0));
    const credentials = try s.get(receiver, "credentials");
    if (method == .read) return c.JS_DupValue(s.engine.context, try s.invoke(credentials, "get", &.{arg(args, 0)}));
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
    return c.JS_DupValue(s.engine.context, try s.invoke(entries, "map", &.{try arrow(s, listEntry, 1, &.{}, false)}));
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
    const inner = try s.own(try native.createResumableArrow(s.engine, "", 0, queuedBody, &.{ previous, signal, task }, c.pi_js_undefined()));
    const queued = try s.call(inner, c.pi_js_undefined(), &.{});
    const tail = try s.invoke(queued, "catch", &.{try arrow(s, noop, 0, &.{}, false)});
    _ = try s.invoke(try s.get(receiver, "chains"), "set", &.{ id, tail });
    _ = try s.invoke(tail, "then", &.{try arrow(s, cleanTail, 0, &.{ receiver, id, tail }, false)});
    return c.JS_DupValue(s.engine.context, try s.call(try s.get(imports, "raceWithAbortSignal"), c.pi_js_undefined(), &.{ queued, signal }));
}
fn queuedBody(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        try s.put(job, "signal", roots[1]);
        try s.put(job, "task", roots[2]);
        queuedStart(&s, job, roots[0]) catch |err| return body.failure(engine, err);
    } else continued(engine, state.*, input, completion == .rejected, try body.stage(&s, state.*)) catch |err| return body.failure(engine, err);
    return body.action(&s, state.*);
}
fn queuedStart(s: *Scope, job: c.JSValue, previous: c.JSValue) !void {
    const caught = try s.invoke(previous, "catch", &.{try arrow(s, noop, 0, &.{}, false)});
    try body.wait(s, job, caught, @intFromEnum(Stage.previous));
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
    _ = try s.invoke(try s.get(roots[0], "credentials"), "delete", &.{roots[1]});
    return c.pi_js_undefined();
}
fn mutationTask(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, state: *c.JSValue, completion: native.Completion, input: c.JSValue) !native.Action {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (completion == .start) {
        const job = try body.init(&s, state);
        inline for (.{ "self", "id", "callback", "options" }, 0..) |name, index| try s.put(job, name, roots[index]);
        mutationStart(&s, job) catch |err| return body.failure(engine, err);
    } else continued(engine, state.*, input, completion == .rejected, try body.stage(&s, state.*)) catch |err| return body.failure(engine, err);
    return body.action(&s, state.*);
}
fn mutationStart(s: *Scope, job: c.JSValue) !void {
    const current = try s.invoke(try s.get(try s.get(job, "self"), "credentials"), "get", &.{try s.get(job, "id")});
    try s.put(job, "current", current);
    try body.wait(s, job, try s.call(try s.get(job, "callback"), c.pi_js_undefined(), &.{current}), @intFromEnum(Stage.mutation));
}
fn continued(engine: *v.em.Engine, job: c.JSValue, value: c.JSValue, failed: bool, raw_stage: c_int) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    if (failed) return body.reject(&s, job, value);
    switch (@as(Stage, @enumFromInt(raw_stage))) {
        .previous => {
            _ = try s.invoke(try s.get(job, "signal"), "throwIfAborted", &.{});
            try body.resolve(&s, job, try s.call(try s.get(job, "task"), c.pi_js_undefined(), &.{}));
        },
        .mutation => {
            try checkOptionalSignal(&s, try s.get(job, "options"));
            if (!c.JS_IsUndefined(value)) _ = try s.invoke(try s.get(try s.get(job, "self"), "credentials"), "set", &.{ try s.get(job, "id"), value });
            try body.resolve(&s, job, if (v.nullish(value)) try s.get(job, "current") else value);
        },
    }
}
