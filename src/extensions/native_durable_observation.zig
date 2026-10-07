//! Owner-thread C VM document observations. Native workers never access VM roots.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const durable = @import("native_durable.zig");
const docs = @import("native_durable_documents.zig");
const json = @import("../durable/backend/json.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Frame = struct { value: c.JSValue, ops: c.JSValue, context: c.JSValue };
const Watch = struct {
    engine: *Engine,
    parent: c.JSValue,
    value: c.JSValue,
    closed: c.JSValue,
    resolve: c.JSValue,
    listener: c.JSValue,
    commit_detach: c.JSValue,
    close_detach: c.JSValue,
    signal: c.JSValue,
    cancellation: c.JSValue,
    end: c.JSValue,
    id: u64,
    version: u64,
    pending: std.ArrayList(Frame) = .empty,
    started: bool = false,
    scheduled: bool = false,
    running: bool = false,
    retired: bool = false,
    fn clear(self: *Watch, runtime: ?*c.JSRuntime) void {
        for (self.pending.items) |frame| {
            c.JS_FreeValueRT(runtime, frame.value);
            c.JS_FreeValueRT(runtime, frame.ops);
            c.JS_FreeValueRT(runtime, frame.context);
        }
        self.pending.clearRetainingCapacity();
    }
    fn detach(self: *Watch) !void {
        inline for (.{ "commit_detach", "close_detach" }) |name| {
            const callback = @field(self, name);
            if (!c.JS_IsUndefined(callback)) {
                @field(self, name) = c.pi_js_undefined();
                defer self.engine.freeValue(callback);
                const result = try self.engine.checked(c.JS_Call(self.engine.context, callback, c.pi_js_undefined(), 0, null));
                self.engine.freeValue(result);
            }
        }
        if (!c.JS_IsUndefined(self.signal) and !c.JS_IsUndefined(self.cancellation)) {
            const abort = try sdk.text(self.engine, "abort");
            defer self.engine.freeValue(abort);
            const result = try sdk.invoke(self.engine, self.signal, "removeEventListener", &.{ abort, self.cancellation });
            self.engine.freeValue(result);
        }
    }
    fn terminate(self: *Watch, reason: []const u8, failure: ?c.JSValue) !void {
        if (!c.JS_IsUndefined(self.end)) return;
        const end = try sdk.object(self.engine);
        errdefer self.engine.freeValue(end);
        try sdk.put(self.engine, end, "reason", try sdk.text(self.engine, reason));
        if (failure) |value| {
            const global = c.JS_GetGlobalObject(self.engine.context);
            defer self.engine.freeValue(global);
            const constructor = try sdk.get(self.engine, global, "Error");
            defer self.engine.freeValue(constructor);
            const instance = c.JS_IsInstanceOf(self.engine.context, value, constructor);
            if (instance < 0) return error.JavaScriptException;
            if (instance > 0) try sdk.put(self.engine, end, "error", c.JS_DupValue(self.engine.context, value)) else {
                const message = try self.engine.toString(value);
                defer self.engine.gpa.free(message);
                const text = try sdk.text(self.engine, message);
                defer self.engine.freeValue(text);
                var args = [_]c.JSValue{text};
                const normalized = try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, 1, &args));
                try sdk.put(self.engine, end, "error", normalized);
            }
        }
        self.end = end;
        try self.detach();
        self.clear(self.engine.runtime);
        var args = [_]c.JSValue{end};
        const result = try self.engine.checked(c.JS_Call(self.engine.context, self.resolve, c.pi_js_undefined(), 1, &args));
        self.engine.freeValue(result);
    }
};
fn state(engine: *Engine, value: c.JSValue) !*Watch {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, value, engine.native_durable_watch_class) orelse return error.InvalidDocumentWatch));
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Watch = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_watch_class) orelse return));
    self.clear(runtime);
    self.pending.deinit(engine.gpa);
    inline for (.{ "parent", "value", "closed", "resolve", "listener", "commit_detach", "close_detach", "signal", "cancellation", "end" }) |name| c.JS_FreeValueRT(runtime, @field(self, name));
    engine.gpa.destroy(self);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Watch = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_durable_watch_class) orelse return));
    inline for (.{ "parent", "value", "closed", "resolve", "listener", "commit_detach", "close_detach", "signal", "cancellation", "end" }) |name| c.JS_MarkValue(runtime, @field(self, name), marker);
    for (self.pending.items) |frame| {
        c.JS_MarkValue(runtime, frame.value, marker);
        c.JS_MarkValue(runtime, frame.ops, marker);
        c.JS_MarkValue(runtime, frame.context, marker);
    }
}
pub fn acquire(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const array = try sdk.array(engine);
    defer engine.freeValue(array);
    for (args) |value| try sdk.append(engine, array, c.JS_DupValue(engine.context, value));
    var data = [_]c.JSValue{ session, array };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, queued, 0, 0, data.len, &data));
    defer engine.freeValue(callback);
    return durable.enqueue(engine, session, callback);
}
fn queued(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return queuedOwned(engine, data) catch |err| durable.reject(engine, err);
}
fn queuedOwned(engine: *Engine, data: [*c]c.JSValue) !c.JSValue {
    var args: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (args.items) |value| engine.freeValue(value);
        args.deinit(engine.gpa);
    }
    const length = try sdk.length(engine, data[1]);
    try args.ensureTotalCapacity(engine.gpa, length);
    for (0..length) |index| args.appendAssumeCapacity(try engine.checked(c.JS_GetPropertyUint32(engine.context, data[1], @intCast(index))));
    var observation = (try docs.observe(engine, data[0], args.items)) orelse return c.pi_js_undefined();
    defer {
        engine.freeValue(observation.value);
        engine.freeValue(observation.context);
        observation.record.deinit();
    }
    return create(engine, data[0], observation);
}
fn create(engine: *Engine, parent: c.JSValue, observation: docs.Observation) !c.JSValue {
    if (engine.native_durable_watch_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_watch_class);
    const definition: c.JSClassDef = .{ .class_name = "Native document watch", .finalizer = finalizer, .gc_mark = mark, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_watch_class)) {
        if (c.JS_NewClass(engine.runtime, engine.native_durable_watch_class, &definition) < 0) return error.OutOfMemory;
        try installPrototype(engine);
    }
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_watch_class));
    errdefer engine.freeValue(object);
    const self = try engine.gpa.create(Watch);
    self.* = .{ .engine = engine, .parent = c.JS_DupValue(engine.context, parent), .value = c.JS_DupValue(engine.context, observation.value), .closed = c.pi_js_undefined(), .resolve = c.pi_js_undefined(), .listener = c.pi_js_undefined(), .commit_detach = c.pi_js_undefined(), .close_detach = c.pi_js_undefined(), .signal = c.pi_js_undefined(), .cancellation = c.pi_js_undefined(), .end = c.pi_js_undefined(), .id = try json.asInteger(try json.required(observation.record.value, "id")), .version = observation.version };
    _ = c.JS_SetOpaque(object, self);
    errdefer self.detach() catch {};
    var functions: [2]c.JSValue = undefined;
    self.closed = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    self.resolve = functions[0];
    engine.freeValue(functions[1]);
    var captures = [_]c.JSValue{object};
    const committed = try engine.checked(c.JS_NewCFunctionData(engine.context, publication, 2, 0, 1, &captures));
    defer engine.freeValue(committed);
    self.commit_detach = try durable.subscribe(try durable.state(engine, parent), parent, .subscribeCommits, committed);
    const closing = try engine.checked(c.JS_NewCFunctionData(engine.context, terminateCallback, 0, 0, 1, &captures));
    defer engine.freeValue(closing);
    self.close_detach = try durable.subscribe(try durable.state(engine, parent), parent, .subscribeClose, closing);
    const signal = try sdk.get(engine, observation.context, "abortSignal");
    if (!c.JS_IsUndefined(signal)) {
        self.signal = signal;
        self.cancellation = try engine.checked(c.JS_NewCFunctionData(engine.context, terminateCallback, 0, 1, 1, &captures));
        const abort = try sdk.text(engine, "abort");
        defer engine.freeValue(abort);
        const returned = try sdk.invoke(engine, signal, "addEventListener", &.{ abort, self.cancellation });
        engine.freeValue(returned);
    } else engine.freeValue(signal);
    return object;
}
fn installPrototype(engine: *Engine) !void {
    const prototype = try sdk.object(engine);
    errdefer engine.freeValue(prototype);
    inline for (.{ "value", "closed" }, 0..) |name, operation| {
        const atom = c.JS_NewAtom(engine.context, name);
        defer c.JS_FreeAtom(engine.context, atom);
        const accessor = try engine.checked(c.pi_js_function_magic(engine.context, getter, name, 0, @intCast(operation)));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, accessor, c.pi_js_undefined(), 0) < 0) return error.JavaScriptException;
    }
    inline for (.{ "start", "stop" }, 0..) |name, operation| {
        const callback = try engine.checked(c.pi_js_function_magic(engine.context, method, name, 1, @intCast(operation)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    }
    c.JS_SetClassProto(engine.context, engine.native_durable_watch_class, prototype);
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return durable.reject(engine, err);
    return c.JS_DupValue(engine.context, if (operation == 0) self.value else self.closed);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return methodOwned(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), operation) catch |err| durable.reject(engine, err);
}
fn methodOwned(engine: *Engine, receiver: c.JSValue, listener: c.JSValue, operation: c_int) !c.JSValue {
    const self = try state(engine, receiver);
    if (operation == 1) {
        try self.terminate("stopped", null);
        return c.JS_DupValue(engine.context, self.closed);
    }
    if (self.started) return error.WatchAlreadyStarted;
    if (!c.JS_IsUndefined(self.end)) return error.WatchStopped;
    self.started = true;
    self.listener = c.JS_DupValue(engine.context, listener);
    if (self.pending.items.len > 0) try schedule(self, receiver);
    return c.pi_js_undefined();
}
fn terminateCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, cancelled: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return durable.reject(engine, err);
    self.terminate(if (cancelled == 1) "cancelled" else "session_closed", null) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn schedule(self: *Watch, object: c.JSValue) !void {
    if (self.scheduled or self.running or !c.JS_IsUndefined(self.end)) return;
    var data = [_]c.JSValue{object};
    const callback = try self.engine.checked(c.JS_NewCFunctionData(self.engine.context, drainCallback, 0, 0, 1, &data));
    defer self.engine.freeValue(callback);
    const resolved = try sdk.promise(self.engine, c.pi_js_undefined());
    defer self.engine.freeValue(resolved);
    const queued_value = try sdk.invoke(self.engine, resolved, "then", &.{callback});
    self.engine.freeValue(queued_value);
    self.scheduled = true;
}
fn drainCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return drain(engine, data[0]) catch |err| durable.reject(engine, err);
}
fn drain(engine: *Engine, object: c.JSValue) !c.JSValue {
    const self = try state(engine, object);
    self.scheduled = false;
    if (self.running or !self.started or !c.JS_IsUndefined(self.end) or self.pending.items.len == 0) return c.pi_js_undefined();
    const frame = self.pending.orderedRemove(0);
    defer {
        engine.freeValue(frame.value);
        engine.freeValue(frame.ops);
        engine.freeValue(frame.context);
    }
    engine.freeValue(self.value);
    self.value = c.JS_DupValue(engine.context, frame.value);
    self.running = true;
    var args = [_]c.JSValue{ frame.value, frame.ops, frame.context };
    const returned = c.JS_Call(engine.context, self.listener, c.pi_js_undefined(), 3, &args);
    if (c.JS_IsException(returned)) {
        const failure = c.JS_GetException(engine.context);
        defer engine.freeValue(failure);
        self.running = false;
        try self.terminate("listener_error", failure);
        return c.pi_js_undefined();
    }
    defer engine.freeValue(returned);
    const promise = try sdk.promise(engine, returned);
    defer engine.freeValue(promise);
    var data = [_]c.JSValue{ object, c.pi_js_bool(engine.context, @intFromBool(c.JS_IsNull(frame.value))) };
    const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 0, 2, &data));
    defer engine.freeValue(fulfilled);
    const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 1, 2, &data));
    defer engine.freeValue(rejected);
    const result = try sdk.invoke(engine, promise, "then", &.{ fulfilled, rejected });
    engine.freeValue(result);
    return c.pi_js_undefined();
}
fn settled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, failure: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return durable.reject(engine, err);
    self.running = false;
    if (!c.JS_IsUndefined(self.end)) return c.pi_js_undefined();
    if (failure == 1) {
        self.terminate("listener_error", if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return durable.reject(engine, err);
    } else if (c.JS_ToBool(engine.context, data[1]) > 0) {
        self.terminate("retired", null) catch |err| return durable.reject(engine, err);
    } else if (self.pending.items.len > 0) schedule(self, data[0]) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn publication(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    receive(engine, data[0], argv[0], if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn receive(engine: *Engine, object: c.JSValue, publication_value: c.JSValue, context: c.JSValue) !void {
    const self = try state(engine, object);
    if (!c.JS_IsUndefined(self.end) or self.retired) return;
    const changes = try sdk.get(engine, publication_value, "changes");
    defer engine.freeValue(changes);
    const length = try sdk.length(engine, changes);
    for (0..length) |index| {
        const change = try engine.checked(c.JS_GetPropertyUint32(engine.context, changes, @intCast(index)));
        defer engine.freeValue(change);
        const kind = try sdk.get(engine, change, "type");
        defer engine.freeValue(kind);
        const tag = try engine.toString(kind);
        defer engine.gpa.free(tag);
        if (!std.mem.eql(u8, tag, "document")) continue;
        const record = try sdk.get(engine, change, "record");
        defer engine.freeValue(record);
        const id = try sdk.get(engine, record, "id");
        defer engine.freeValue(id);
        if (try durable.number(engine, id) != self.id) continue;
        var admitted = false;
        const value = try sdk.get(engine, change, "value");
        errdefer if (!admitted) engine.freeValue(value);
        var ops: c.JSValue = undefined;
        if (c.JS_IsNull(value)) {
            self.retired = true;
            ops = try replacement(engine, value);
        } else {
            const version_value = try sdk.get(engine, change, "version");
            defer engine.freeValue(version_value);
            const version = try durable.number(engine, version_value);
            if (self.version != version) {
                ops = try replacement(engine, value);
                self.version = version;
            } else ops = try sdk.get(engine, change, "ops");
        }
        errdefer if (!admitted) engine.freeValue(ops);
        if (try sdk.length(engine, ops) == 0) {
            engine.freeValue(value);
            engine.freeValue(ops);
            continue;
        }
        const clean_context = try @import("native_durable_context.zig").withoutAbortSignal(engine, context);
        errdefer if (!admitted) engine.freeValue(clean_context);
        try self.pending.ensureUnusedCapacity(engine.gpa, 1);
        if (self.pending.items.len >= 100) {
            const replace = try replacement(engine, value);
            engine.freeValue(ops);
            ops = replace;
            self.clear(engine.runtime);
        }
        self.pending.appendAssumeCapacity(.{ .value = value, .ops = ops, .context = clean_context });
        admitted = true;
        if (self.started) try schedule(self, object);
    }
}
fn replacement(engine: *Engine, value: c.JSValue) !c.JSValue {
    const ops = try sdk.array(engine);
    errdefer engine.freeValue(ops);
    const tuple = try sdk.array(engine);
    defer engine.freeValue(tuple);
    try sdk.append(engine, tuple, try sdk.text(engine, "r"));
    try sdk.append(engine, tuple, c.JS_DupValue(engine.context, value));
    try sdk.append(engine, ops, c.JS_DupValue(engine.context, tuple));
    return ops;
}
fn allocationExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try durable.install(engine);
    const storage = try durable.memoryObject(engine);
    defer engine.freeValue(storage);
    const session = try durable.sessionObject(engine, storage);
    defer engine.freeValue(session);
    var record = try json.Owned.parse(gpa, "{\"id\":7}");
    defer record.deinit();
    const initial = try engine.eval("({n:1})", "watch-initial-data-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(initial);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    const watch = try create(engine, session, .{ .value = initial, .record = record, .version = 1, .context = context });
    defer engine.freeValue(watch);
    const event = try engine.eval("({changes:[{type:'document',record:{id:7},version:1,value:{n:2},ops:[['s',['n'],2]]}]})", "watch-publication-data-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(event);
    try receive(engine, watch, event, context);
    const listener = try engine.eval("async()=>{}", "watch-listener-input-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(listener);
    const started = try methodOwned(engine, watch, listener, 0);
    engine.freeValue(started);
    const stopped = try methodOwned(engine, watch, c.pi_js_undefined(), 1);
    defer engine.freeValue(stopped);
}
test "native durable VM document watch construction subscriptions queued frame and detach roll back every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
