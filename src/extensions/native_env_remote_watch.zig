//! Source RemoteWatcher coverage, delivery, reconnect backoff and close lifetimes.
const js = @import("native_js_values.zig");
const h = @import("native_env_remote_helpers.zig");
const Scope = h.Scope;
const c = js.c;
const Stage = enum(c_int) { opened, request, timer, reconnect, target, targets, env_opened, aborted_close };
const Callback = enum(c_int) { event, timer, wake, target };
const State = struct { engine: *js.Engine, fields: c.JSValue };
fn state(engine: *js.Engine, receiver: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, receiver, engine.native_env_watcher_class) orelse return js.capture(engine)));
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_env_watcher_class) orelse return));
    c.JS_FreeValueRT(runtime, owned.fields);
    engine.gpa.destroy(owned);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *js.Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_env_watcher_class) orelse return));
    c.JS_MarkValue(runtime, owned.fields, visit);
}
fn captures(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const fields = (try state(scope.engine, receiver)).fields;
    try scope.put(result, "self", receiver);
    try scope.put(result, "private", fields);
    try scope.put(result, "bindings", try scope.get(fields, "bindings"));
    try scope.put(result, "path", c.pi_js_undefined());
    return result;
}
fn function(scope: *Scope, saved: c.JSValue, kind: Callback, length: c_int) !c.JSValue {
    var values = [_]c.JSValue{saved};
    return scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, callbackInvoke, "", length, @intFromEnum(kind), 1, &values)));
}
fn deliver(scope: *Scope, saved: c.JSValue, change: c.JSValue) !void {
    const fields = try scope.get(saved, "private");
    if (scope.truthy(try scope.get(fields, "closed"))) return;
    _ = scope.call(try scope.get(fields, "onChange"), try scope.get(saved, "self"), &.{change}) catch |err| {
        if (err != error.JavaScriptException) return err;
        if (scope.engine.captured_exception) |reason| scope.engine.freeValue(reason);
        scope.engine.captured_exception = null;
        return;
    };
}
fn lost(scope: *Scope, saved: c.JSValue, reason: c.JSValue) !bool {
    return scope.truthy(try scope.call(try scope.get(try scope.get(saved, "bindings"), "isConnectionLost"), c.pi_js_undefined(), &.{reason}));
}
fn terminalError(scope: *Scope, saved: c.JSValue, reason: c.JSValue) !void {
    const result = try h.errors.mapError(scope, saved, reason);
    const change = try scope.object();
    try scope.put(change, "error", try scope.get(result, "error"));
    try deliver(scope, saved, change);
    try scope.put(try scope.get(saved, "private"), "closed", c.pi_js_bool(scope.engine.context, 1));
}
fn reconnect(scope: *Scope, saved: c.JSValue, delay: c.JSValue) !c.JSValue {
    const fields = try scope.get(saved, "private");
    if (scope.truthy(try scope.get(fields, "closed"))) return h.resolved(scope, c.pi_js_undefined());
    const step = try captures(scope, try scope.get(saved, "self"));
    try scope.put(step, "delay", delay);
    var resolvers: [2]c.JSValue = undefined;
    const pending = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &resolvers)));
    _ = try scope.own(resolvers[0]);
    _ = try scope.own(resolvers[1]);
    try scope.put(step, "resolve", resolvers[0]);
    const timer_callback = try function(scope, step, .timer, 0);
    const timer = try scope.call(try scope.global("setTimeout"), c.pi_js_undefined(), &.{ timer_callback, delay });
    _ = try scope.invoke(timer, "unref", &.{});
    try scope.put(step, "timer", timer);
    try scope.put(fields, "wake", try function(scope, step, .wake, 0));
    return h.wait(advance, scope, step, pending, Stage.timer);
}
fn event(scope: *Scope, saved: c.JSValue, value: c.JSValue) !void {
    const fields = try scope.get(saved, "private");
    const kind = try scope.get(value, "kind");
    if (scope.equal(kind, try scope.text("ready"))) {
        try scope.put(saved, "ready", c.pi_js_bool(scope.engine.context, 1));
        try scope.put(fields, "mode", try scope.text(if (scope.equal(try scope.get(value, "mode"), try scope.text("polling"))) "polling" else "native"));
        _ = try scope.call(try scope.get(saved, "resolve"), c.pi_js_undefined(), &.{});
    } else if (scope.equal(kind, try scope.text("change"))) {
        if (scope.equal(try scope.get(value, "mode"), try scope.text("polling"))) try scope.put(fields, "mode", try scope.text("polling"));
        const change = try scope.object();
        if (scope.equal(try scope.get(value, "overflow"), c.pi_js_bool(scope.engine.context, 1))) try scope.put(change, "overflow", c.pi_js_bool(scope.engine.context, 1)) else try scope.put(change, "paths", try scope.get(value, "paths"));
        try deliver(scope, saved, change);
    } else if (scope.equal(kind, try scope.text("error"))) {
        const args = [_]c.JSValue{ try scope.text(if (scope.equal(try scope.get(value, "code"), try scope.text("permission_denied"))) "permission_denied" else "invalid"), try scope.call(try scope.global("String"), c.pi_js_undefined(), &.{try scope.get(value, "message")}) };
        const constructor = try scope.get(try scope.get(saved, "bindings"), "FileError");
        const failure = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, @constCast(&args))));
        const change = try scope.object();
        try scope.put(change, "error", failure);
        try deliver(scope, saved, change);
        try scope.put(fields, "closed", c.pi_js_bool(scope.engine.context, 1));
    }
}
fn callbackInvoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, raw: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return callback(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(raw)) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn callback(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, kind: Callback) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (kind == .event) {
        try event(&scope, saved, value);
        return c.pi_js_undefined();
    }
    if (kind == .wake) _ = try scope.call(try scope.global("clearTimeout"), c.pi_js_undefined(), &.{try scope.get(saved, "timer")});
    if (kind == .timer or kind == .wake) {
        _ = try scope.call(try scope.get(saved, "resolve"), c.pi_js_undefined(), &.{});
        return c.pi_js_undefined();
    }
    const child = try scope.object();
    inline for (.{ "bindings", "self" }) |key| try scope.put(child, key, try scope.get(saved, key));
    try scope.put(child, "target", try scope.own(try js.spread(engine, value)));
    const pending = h.path.resolve(&scope, try scope.get(saved, "bindings"), try scope.get(saved, "self"), try scope.get(value, "path")) catch |err| try h.rejected(&scope, err);
    return c.JS_DupValue(engine.context, try h.wait(advance, &scope, child, pending, Stage.target));
}
fn targetBody(scope: *Scope, target: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", try scope.get(target, "path"));
    try scope.put(result, "recursive", c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try scope.get(target, "recursive"), c.pi_js_bool(scope.engine.context, 1)))));
    const exclude = try scope.object();
    const given = try scope.get(target, "exclude");
    try scope.put(exclude, "hidden", c.pi_js_bool(scope.engine.context, @intFromBool(scope.equal(try h.optional(scope, given, "hidden"), c.pi_js_bool(scope.engine.context, 1)))));
    const names = try h.optional(scope, given, "names");
    const array = try scope.array();
    if (!h.nullish(names)) {
        var iterator = try js.Iterator.init(scope.engine, names, try scope.get(try scope.global("Symbol"), "iterator"));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |name| {
            _ = try scope.own(name);
            _ = try scope.invoke(array, "push", &.{name});
        }
    }
    try scope.put(exclude, "names", array);
    try scope.put(result, "exclude", exclude);
    return result;
}
fn start(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const saved = try captures(scope, receiver);
    const fields = try scope.get(saved, "private");
    var resolvers: [2]c.JSValue = undefined;
    const pending = try scope.own(try scope.engine.checked(c.JS_NewPromiseCapability(scope.engine.context, &resolvers)));
    _ = try scope.own(resolvers[0]);
    _ = try scope.own(resolvers[1]);
    try scope.put(saved, "resolve", resolvers[0]);
    try scope.put(saved, "reject", resolvers[1]);
    try scope.put(saved, "ready", c.pi_js_bool(scope.engine.context, 0));
    startPrepared(scope, receiver, saved, fields) catch |err| {
        if (err != error.JavaScriptException) return err;
        _ = try scope.call(resolvers[1], c.pi_js_undefined(), &.{try h.errors.captured(scope)});
    };
    return pending;
}
fn startPrepared(scope: *Scope, _: c.JSValue, saved: c.JSValue, fields: c.JSValue) !void {
    const controller = try scope.own(try js.builtin(scope.engine, "AbortController", &.{}));
    try scope.put(fields, "controller", controller);
    const targets = try scope.array();
    var iterator = try js.Iterator.init(scope.engine, try scope.get(fields, "targets"), try scope.get(try scope.global("Symbol"), "iterator"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |target| {
        _ = try scope.own(target);
        _ = try scope.invoke(targets, "push", &.{try targetBody(scope, target)});
    }
    const json = try scope.object();
    try scope.put(json, "targets", targets);
    const given_options = try scope.own(try js.spread(scope.engine, try scope.get(fields, "options")));
    const descriptors = try scope.invoke(try scope.global("Object"), "getOwnPropertyDescriptors", &.{given_options});
    _ = try scope.invoke(try scope.global("Object"), "defineProperties", &.{ json, descriptors });
    const options = try scope.object();
    try scope.put(options, "signal", try scope.get(controller, "signal"));
    try scope.put(options, "onEvent", try function(scope, saved, .event, 1));
    const request = try scope.invoke(try scope.get(fields, "connection"), "request", &.{ try scope.text("watch"), json, options });
    try scope.put(fields, "request", try h.wait(advance, scope, saved, request, Stage.request));
}
fn advance(engine: *js.Engine, saved: c.JSValue, value: c.JSValue, rejected: bool, raw: c_int) anyerror!c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const stage: Stage = @enumFromInt(raw);
    if (stage == .target) {
        if (rejected) return h.throw(&scope, value);
        const target = try scope.get(saved, "target");
        try scope.put(target, "path", value);
        return c.JS_DupValue(engine.context, target);
    }
    if (stage == .targets or stage == .env_opened or stage == .aborted_close) {
        if (rejected) return c.JS_DupValue(engine.context, try h.errors.mapError(&scope, saved, value));
        const result = envContinuation(&scope, saved, value, stage) catch |err| {
            if (err != error.JavaScriptException) return err;
            return c.JS_DupValue(engine.context, try h.errors.mapError(&scope, saved, try h.errors.captured(&scope)));
        };
        return c.JS_DupValue(engine.context, result);
    }
    const fields = try scope.get(saved, "private");
    switch (stage) {
        .opened => {
            if (rejected) return h.throw(&scope, value);
            return c.JS_DupValue(engine.context, try scope.get(saved, "self"));
        },
        .request => {
            if (!rejected) return c.pi_js_undefined();
            if (!scope.truthy(try scope.get(saved, "ready"))) {
                _ = try scope.call(try scope.get(saved, "reject"), c.pi_js_undefined(), &.{value});
                return c.pi_js_undefined();
            }
            if (scope.truthy(try scope.get(fields, "closed"))) return c.pi_js_undefined();
            if (try lost(&scope, saved, value)) {
                _ = try reconnect(&scope, saved, c.JS_NewInt32(engine.context, 1000));
                return c.pi_js_undefined();
            }
            try terminalError(&scope, saved, value);
        },
        .timer => {
            try scope.put(fields, "wake", c.pi_js_undefined());
            if (scope.truthy(try scope.get(fields, "closed"))) return c.pi_js_undefined();
            const pending = start(&scope, try scope.get(saved, "self")) catch |err| try h.rejected(&scope, err);
            return c.JS_DupValue(engine.context, try h.wait(advance, &scope, saved, pending, Stage.reconnect));
        },
        .reconnect => {
            if (!rejected) {
                const change = try scope.object();
                try scope.put(change, "overflow", c.pi_js_bool(engine.context, 1));
                try deliver(&scope, saved, change);
                return c.pi_js_undefined();
            }
            if (try lost(&scope, saved, value)) {
                const doubled = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 2, try scope.get(saved, "delay"), c.JS_NewInt32(engine.context, 2))));
                return c.JS_DupValue(engine.context, try reconnect(&scope, saved, try scope.invoke(try scope.global("Math"), "min", &.{ doubled, c.JS_NewInt32(engine.context, 30_000) })));
            }
            try terminalError(&scope, saved, value);
        },
        else => unreachable,
    }
    return c.pi_js_undefined();
}
fn envContinuation(scope: *Scope, saved: c.JSValue, value: c.JSValue, stage: Stage) !c.JSValue {
    if (stage == .aborted_close) return scope.get(saved, "completion");
    if (stage == .env_opened) {
        if (try h.errors.aborted(scope, saved)) |early| {
            try scope.put(saved, "completion", early);
            return h.wait(advance, scope, saved, try scope.invoke(value, "close", &.{try scope.get(saved, "context")}), Stage.aborted_close);
        }
        return h.values.result(scope, true, value);
    }
    if (try h.errors.aborted(scope, saved)) |early| return early;
    const receiver = try scope.get(saved, "self");
    const constructor = try scope.get(try scope.get(saved, "bindings"), "RemoteWatcher");
    return h.wait(advance, scope, saved, try scope.invoke(constructor, "open", &.{ try scope.get(receiver, "connection"), value, try scope.get(saved, "onChange"), try scope.get(try scope.get(saved, "private"), "watch") }), Stage.env_opened);
}
fn construct(engine: *js.Engine, target: c.JSValue, args: []const c.JSValue, constants: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const receiver = try scope.own(try engine.checked(c.JS_NewObjectProtoClass(engine.context, try scope.get(target, "prototype"), engine.native_env_watcher_class)));
    const fields = try scope.object();
    inline for (.{ "connection", "targets", "onChange", "options" }, 0..) |key, index| try scope.put(fields, key, h.arg(args, index));
    try scope.put(fields, "bindings", constants[0]);
    try scope.put(fields, "closed", c.pi_js_bool(engine.context, 0));
    try scope.put(fields, "mode", try scope.text("native"));
    const owner = try engine.gpa.create(State);
    owner.* = .{ .engine = engine, .fields = c.JS_DupValue(engine.context, fields) };
    _ = c.JS_SetOpaque(receiver, owner);
    return c.JS_DupValue(engine.context, receiver);
}
fn mode(context: ?*c.JSContext, receiver: c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const owner = state(engine, receiver) catch |err| return @import("native_durable.zig").reject(engine, err);
    return js.get(engine, owner.fields, "mode") catch |err| @import("native_durable.zig").reject(engine, err);
}
fn close(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return closeValue(engine, receiver) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn closeValue(engine: *js.Engine, receiver: c.JSValue) !c.JSValue {
    const owner = try state(engine, receiver);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (scope.truthy(try scope.get(owner.fields, "closed"))) return @import("native_durable.zig").resolvedPromise(engine, c.pi_js_undefined());
    try scope.put(owner.fields, "closed", c.pi_js_bool(engine.context, 1));
    const wake = try scope.get(owner.fields, "wake");
    if (!h.nullish(wake)) _ = try scope.call(wake, c.pi_js_undefined(), &.{});
    const controller = try scope.get(owner.fields, "controller");
    if (!h.nullish(controller)) _ = try scope.invoke(controller, "abort", &.{});
    return @import("native_durable.zig").resolvedPromise(engine, try scope.get(owner.fields, "request"));
}
fn open(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    return openValue(engine, if (argc > 0) argv[0..@intCast(argc)] else &.{}, data[0]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn openValue(engine: *js.Engine, args: []const c.JSValue, constructor: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const call_args = [_]c.JSValue{ h.arg(args, 0), h.arg(args, 1), h.arg(args, 2), if (c.JS_IsUndefined(h.arg(args, 3))) try scope.object() else h.arg(args, 3) };
    const receiver = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, call_args.len, @constCast(&call_args))));
    const saved = try captures(&scope, receiver);
    return c.JS_DupValue(engine.context, try h.wait(advance, &scope, saved, try start(&scope, receiver), Stage.opened));
}
pub fn create(scope: *Scope, bindings: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    if (engine.abort_controller_class == 0) try @import("abort_signal.zig").install(engine);
    if (engine.host_scheduler == null) try @import("timers.zig").install(engine, engine.native_io orelse return error.NativeIoRequired);
    if (engine.native_env_watcher_class == 0) {
        _ = c.JS_NewClassID(engine.runtime, &engine.native_env_watcher_class);
        const definition: c.JSClassDef = .{ .class_name = "RemoteWatcher", .finalizer = finalize, .gc_mark = mark };
        if (c.JS_NewClass(engine.runtime, engine.native_env_watcher_class, &definition) < 0) return error.OutOfMemory;
    }
    const prototype = try scope.object();
    const getter = try engine.checked(c.JS_NewCFunction2(engine.context, @ptrCast(&mode), "get mode", 0, c.JS_CFUNC_getter, 0));
    const atom = c.JS_NewAtom(engine.context, "mode");
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    const close_function = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, close, "close", 1)));
    const async_prototype = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    if (c.JS_SetPrototype(engine.context, close_function, async_prototype) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "close", c.JS_DupValue(engine.context, close_function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "RemoteWatcher", 4, prototype, construct, &.{bindings}));
    var data = [_]c.JSValue{constructor};
    const open_function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, open, "open", 3, 0, 1, &data)));
    if (c.JS_SetPrototype(engine.context, open_function, async_prototype) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "open", c.JS_DupValue(engine.context, open_function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    return constructor;
}
pub fn invoke(scope: *Scope, saved: c.JSValue, args: []const c.JSValue) !c.JSValue {
    if (try h.errors.aborted(scope, saved)) |early| return h.resolved(scope, early);
    try scope.put(saved, "onChange", h.arg(args, 1));
    const mapper = try function(scope, saved, .target, 1);
    const pending = try scope.invoke(h.arg(args, 0), "map", &.{mapper});
    const all = try scope.invoke(try scope.global("Promise"), "all", &.{pending});
    return h.wait(advance, scope, saved, all, Stage.targets);
}
