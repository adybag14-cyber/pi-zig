//! Committed document state with synchronous hydration and independent subscribers.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const durable = @import("native_durable.zig");
const docs = @import("native_durable_documents.zig");
const context_mod = @import("native_durable_context.zig");
const json = @import("../durable/backend/json.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const Revision = struct { value: c.JSValue, context: c.JSValue };
const Delivery = struct { value: c.JSValue, context: c.JSValue, sequence: u64, hydrate: bool };
const State = struct {
    engine: *Engine,
    parent: c.JSValue,
    value: c.JSValue,
    commit_detach: c.JSValue,
    close_detach: c.JSValue,
    id: u64,
    version: u64,
    projected: bool = false,
    projection_report: ?c.JSValue = null,
    sequence: u64 = 0,
    subscribers: std.ArrayList(c.JSValue) = .empty,
    revisions: std.ArrayList(Revision) = .empty,
    scheduled: bool = false,
    delivering: bool = false,
    disposed: bool = false,
    retired: bool = false,
    fn clear(self: *State, runtime: ?*c.JSRuntime) void {
        for (self.revisions.items) |frame| {
            c.JS_FreeValueRT(runtime, frame.value);
            c.JS_FreeValueRT(runtime, frame.context);
        }
        self.revisions.clearRetainingCapacity();
    }
    fn dispose(self: *State) !void {
        if (self.disposed) return;
        self.disposed = true;
        self.clear(self.engine.runtime);
        inline for (.{ "commit_detach", "close_detach" }) |name| {
            const callback = @field(self, name);
            @field(self, name) = c.pi_js_undefined();
            defer self.engine.freeValue(callback);
            if (!c.JS_IsUndefined(callback)) {
                const returned = try self.engine.checked(c.JS_Call(self.engine.context, callback, c.pi_js_undefined(), 0, null));
                self.engine.freeValue(returned);
            }
        }
    }
};
const Subscriber = struct {
    engine: *Engine,
    owner: c.JSValue,
    listener: c.JSValue,
    pending: std.ArrayList(Delivery) = .empty,
    running: bool = false,
    started: bool = false,
    closed: bool = false,
    fn clear(self: *Subscriber, runtime: ?*c.JSRuntime) void {
        for (self.pending.items) |frame| {
            c.JS_FreeValueRT(runtime, frame.value);
            c.JS_FreeValueRT(runtime, frame.context);
        }
        self.pending.clearRetainingCapacity();
    }
    fn push(self: *Subscriber, value: c.JSValue, context: c.JSValue, sequence: u64, hydrate: bool) !void {
        if (self.closed) return;
        try self.pending.ensureUnusedCapacity(self.engine.gpa, 1);
        if (self.pending.items.len == 100) {
            if (!self.started and self.pending.items.len > 0) {
                const first = self.pending.orderedRemove(0);
                self.clear(self.engine.runtime);
                self.pending.appendAssumeCapacity(first);
            } else self.clear(self.engine.runtime);
        }
        self.pending.appendAssumeCapacity(.{ .value = c.JS_DupValue(self.engine.context, value), .context = c.JS_DupValue(self.engine.context, context), .sequence = sequence, .hydrate = hydrate });
    }
};
fn state(engine: *Engine, object: c.JSValue) !*State {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, object, engine.native_durable_state_class) orelse return error.InvalidDocumentState));
}
fn subscriber(engine: *Engine, object: c.JSValue) !*Subscriber {
    return @ptrCast(@alignCast(c.JS_GetOpaque2(engine.context, object, engine.native_durable_subscriber_class) orelse return error.InvalidDocumentSubscriber));
}
fn stateFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_durable_state_class) orelse return));
    self.clear(runtime);
    self.revisions.deinit(engine.gpa);
    for (self.subscribers.items) |value| c.JS_FreeValueRT(runtime, value);
    self.subscribers.deinit(engine.gpa);
    inline for (.{ "parent", "value", "commit_detach", "close_detach" }) |name| c.JS_FreeValueRT(runtime, @field(self, name));
    if (self.projection_report) |reporter| c.JS_FreeValueRT(runtime, reporter);
    engine.gpa.destroy(self);
}
fn stateMark(runtime: ?*c.JSRuntime, object: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *State = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_durable_state_class) orelse return));
    inline for (.{ "parent", "value", "commit_detach", "close_detach" }) |name| c.JS_MarkValue(runtime, @field(self, name), marker);
    if (self.projection_report) |reporter| c.JS_MarkValue(runtime, reporter, marker);
    for (self.subscribers.items) |value| c.JS_MarkValue(runtime, value, marker);
    for (self.revisions.items) |frame| {
        c.JS_MarkValue(runtime, frame.value, marker);
        c.JS_MarkValue(runtime, frame.context, marker);
    }
}
fn subscriberFinalizer(runtime: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Subscriber = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_durable_subscriber_class) orelse return));
    self.clear(runtime);
    self.pending.deinit(engine.gpa);
    c.JS_FreeValueRT(runtime, self.owner);
    c.JS_FreeValueRT(runtime, self.listener);
    engine.gpa.destroy(self);
}
fn subscriberMark(runtime: ?*c.JSRuntime, object: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const self: *Subscriber = @ptrCast(@alignCast(c.JS_GetOpaque(object, engine.native_durable_subscriber_class) orelse return));
    c.JS_MarkValue(runtime, self.owner, marker);
    c.JS_MarkValue(runtime, self.listener, marker);
    for (self.pending.items) |frame| {
        c.JS_MarkValue(runtime, frame.value, marker);
        c.JS_MarkValue(runtime, frame.context, marker);
    }
}
fn classes(engine: *Engine) !void {
    if (engine.native_durable_state_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_state_class);
    if (engine.native_durable_subscriber_class == 0) _ = c.JS_NewClassID(engine.runtime, &engine.native_durable_subscriber_class);
    const state_definition: c.JSClassDef = .{ .class_name = "Native document state", .finalizer = stateFinalizer, .gc_mark = stateMark, .call = null, .exotic = null };
    const subscriber_definition: c.JSClassDef = .{ .class_name = "Native state subscriber", .finalizer = subscriberFinalizer, .gc_mark = subscriberMark, .call = null, .exotic = null };
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_subscriber_class) and c.JS_NewClass(engine.runtime, engine.native_durable_subscriber_class, &subscriber_definition) < 0) return error.OutOfMemory;
    if (!c.JS_IsRegisteredClass(engine.runtime, engine.native_durable_state_class)) {
        if (c.JS_NewClass(engine.runtime, engine.native_durable_state_class, &state_definition) < 0) return error.OutOfMemory;
    }
    const existing = try engine.checked(c.JS_GetClassProto(engine.context, engine.native_durable_state_class));
    defer engine.freeValue(existing);
    if (c.JS_IsNull(existing) or c.JS_IsUndefined(existing)) {
        const prototype = try sdk.object(engine);
        errdefer engine.freeValue(prototype);
        const atom = c.JS_NewAtom(engine.context, "value");
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = try engine.checked(c.JS_NewCFunction(engine.context, valueGetter, "get value", 0));
        if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        inline for (.{ "subscribe", "dispose" }, 0..) |name, operation| {
            const callback = try engine.checked(c.pi_js_function_magic(engine.context, method, name, if (operation == 0) 1 else 0, @intCast(operation)));
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
        }
        c.JS_SetClassProto(engine.context, engine.native_durable_state_class, prototype);
    }
}
pub fn acquire(engine: *Engine, session: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const array = try sdk.array(engine);
    defer engine.freeValue(array);
    for (args) |value| try sdk.append(engine, array, c.JS_DupValue(engine.context, value));
    var data = [_]c.JSValue{ session, array };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, queued, 0, 0, 2, &data));
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
    const count = try sdk.length(engine, data[1]);
    try args.ensureTotalCapacity(engine.gpa, count);
    for (0..count) |index| args.appendAssumeCapacity(try engine.checked(c.JS_GetPropertyUint32(engine.context, data[1], @intCast(index))));
    var observation = (try docs.observeState(engine, data[0], args.items)) orelse return c.pi_js_undefined();
    defer {
        engine.freeValue(observation.value);
        engine.freeValue(observation.context);
        observation.record.deinit();
    }
    return create(engine, data[0], observation);
}
fn create(engine: *Engine, parent: c.JSValue, observation: docs.Observation) !c.JSValue {
    try classes(engine);
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_state_class));
    errdefer engine.freeValue(object);
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .parent = c.JS_DupValue(engine.context, parent), .value = c.JS_DupValue(engine.context, observation.value), .commit_detach = c.pi_js_undefined(), .close_detach = c.pi_js_undefined(), .id = try json.asInteger(try json.required(observation.record.value, "id")), .version = observation.version };
    _ = c.JS_SetOpaque(object, self);
    errdefer self.dispose() catch {};
    var data = [_]c.JSValue{object};
    const committed = try engine.checked(c.JS_NewCFunctionData(engine.context, publication, 2, 0, 1, &data));
    defer engine.freeValue(committed);
    self.commit_detach = try durable.subscribe(try durable.state(engine, parent), parent, .subscribeCommits, committed);
    const close_callback = try engine.checked(c.JS_NewCFunctionData(engine.context, closing, 0, 0, 1, &data));
    defer engine.freeValue(close_callback);
    self.close_detach = try durable.subscribe(try durable.state(engine, parent), parent, .subscribeClose, close_callback);
    return object;
}
/// A state of a conversation/task-graph mount, released by that mount rather
/// than by a document incarnation subscription.
pub fn createProjection(engine: *Engine, parent: c.JSValue, value: c.JSValue, release: c.JSValue, on_error: c.JSValue) !c.JSValue {
    try classes(engine);
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_state_class));
    errdefer engine.freeValue(object);
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .parent = c.JS_DupValue(engine.context, parent), .value = c.JS_DupValue(engine.context, value), .commit_detach = c.JS_DupValue(engine.context, release), .close_detach = c.pi_js_undefined(), .id = 0, .version = 0, .projected = true, .projection_report = c.JS_DupValue(engine.context, on_error) };
    _ = c.JS_SetOpaque(object, self);
    return object;
}
pub fn disposeProjection(engine: *Engine, object: c.JSValue) !void {
    try (try state(engine, object)).dispose();
}
pub fn advanceProjection(engine: *Engine, object: c.JSValue, value: c.JSValue, context: c.JSValue) !void {
    const self = try state(engine, object);
    if (!self.projected) return error.NotProjectedState;
    if (self.disposed) return;
    try self.revisions.ensureUnusedCapacity(engine.gpa, 1);
    self.revisions.appendAssumeCapacity(.{ .value = c.JS_DupValue(engine.context, value), .context = c.JS_DupValue(engine.context, context) });
    if (!self.delivering and !self.scheduled) {
        var data = [_]c.JSValue{object};
        const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, flushCallback, 0, 0, 1, &data));
        defer engine.freeValue(callback);
        const resolved = try sdk.promise(engine, c.pi_js_undefined());
        defer engine.freeValue(resolved);
        const result = try sdk.invoke(engine, resolved, "then", &.{callback});
        engine.freeValue(result);
        self.scheduled = true;
    }
}
fn valueGetter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, receiver) catch |err| return durable.reject(engine, err);
    return c.JS_DupValue(engine.context, self.value);
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, operation: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return methodOwned(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), operation) catch |err| durable.reject(engine, err);
}
fn methodOwned(engine: *Engine, receiver: c.JSValue, listener: c.JSValue, operation: c_int) !c.JSValue {
    const self = try state(engine, receiver);
    if (operation == 1) {
        try self.dispose();
        return c.pi_js_undefined();
    }
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_durable_subscriber_class));
    defer engine.freeValue(object);
    const sub = try engine.gpa.create(Subscriber);
    sub.* = .{ .engine = engine, .owner = c.JS_DupValue(engine.context, receiver), .listener = c.JS_DupValue(engine.context, listener) };
    _ = c.JS_SetOpaque(object, sub);
    var admitted = false;
    errdefer if (admitted) detach(engine, object) catch {};
    var data = [_]c.JSValue{object};
    const cancel = try engine.checked(c.JS_NewCFunctionData(engine.context, unsubscribe, 0, 0, 1, &data));
    errdefer engine.freeValue(cancel);
    const module = engine.native_module_values.get("@earendil-works/chord/context").?;
    const background = try sdk.get(engine, module, "BACKGROUND_CONTEXT");
    defer engine.freeValue(background);
    try sub.push(self.value, background, self.sequence, true);
    try self.subscribers.ensureUnusedCapacity(engine.gpa, 1);
    self.subscribers.appendAssumeCapacity(c.JS_DupValue(engine.context, object));
    admitted = true;
    try drainSubscriber(engine, object);
    return cancel;
}
fn unsubscribe(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    detach(engine, data[0]) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn detach(engine: *Engine, object: c.JSValue) !void {
    const sub = try subscriber(engine, object);
    if (sub.closed) return;
    sub.closed = true;
    sub.clear(engine.runtime);
    const self = try state(engine, sub.owner);
    for (self.subscribers.items, 0..) |value, index| if (c.JS_IsStrictEqual(engine.context, value, object)) {
        engine.freeValue(self.subscribers.orderedRemove(index));
        break;
    };
}
fn closing(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const self = state(engine, data[0]) catch |err| return durable.reject(engine, err);
    self.dispose() catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn publication(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    receive(engine, data[0], argv[0], if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn receive(engine: *Engine, object: c.JSValue, publication_value: c.JSValue, context: c.JSValue) !void {
    const self = try state(engine, object);
    if (self.disposed or self.retired) return;
    const changes = try sdk.get(engine, publication_value, "changes");
    defer engine.freeValue(changes);
    const count = try sdk.length(engine, changes);
    for (0..count) |index| {
        const change = try engine.checked(c.JS_GetPropertyUint32(engine.context, changes, @intCast(index)));
        defer engine.freeValue(change);
        const type_value = try sdk.get(engine, change, "type");
        defer engine.freeValue(type_value);
        const tag = try engine.toString(type_value);
        defer engine.gpa.free(tag);
        if (!std.mem.eql(u8, tag, "document")) continue;
        const record = try sdk.get(engine, change, "record");
        defer engine.freeValue(record);
        const id = try sdk.get(engine, record, "id");
        defer engine.freeValue(id);
        if (try durable.number(engine, id) != self.id) continue;
        const value = try sdk.get(engine, change, "value");
        var admitted = false;
        errdefer if (!admitted) engine.freeValue(value);
        var publish = c.JS_IsNull(value);
        if (publish) self.retired = true else {
            const version_value = try sdk.get(engine, change, "version");
            defer engine.freeValue(version_value);
            const version = try durable.number(engine, version_value);
            const ops = try sdk.get(engine, change, "ops");
            defer engine.freeValue(ops);
            publish = version != self.version or try sdk.length(engine, ops) > 0;
            self.version = version;
        }
        if (!publish) {
            engine.freeValue(value);
            continue;
        }
        const clean = try context_mod.withoutAbortSignal(engine, context);
        errdefer if (!admitted) engine.freeValue(clean);
        try self.revisions.ensureUnusedCapacity(engine.gpa, 1);
        self.revisions.appendAssumeCapacity(.{ .value = value, .context = clean });
        admitted = true;
        if (!self.delivering and !self.scheduled) {
            var data = [_]c.JSValue{object};
            const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, flushCallback, 0, 0, 1, &data));
            defer engine.freeValue(callback);
            const resolved = try sdk.promise(engine, c.pi_js_undefined());
            defer engine.freeValue(resolved);
            const result = try sdk.invoke(engine, resolved, "then", &.{callback});
            engine.freeValue(result);
            self.scheduled = true;
        }
    }
}
fn flushCallback(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    flush(engine, data[0]) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn flush(engine: *Engine, object: c.JSValue) !void {
    const self = try state(engine, object);
    self.scheduled = false;
    if (self.disposed or self.delivering) return;
    self.delivering = true;
    defer self.delivering = false;
    while (!self.disposed and self.revisions.items.len > 0) {
        const frame = self.revisions.orderedRemove(0);
        defer {
            engine.freeValue(frame.value);
            engine.freeValue(frame.context);
        }
        engine.freeValue(self.value);
        self.value = c.JS_DupValue(engine.context, frame.value);
        self.sequence += 1;
        const subscribers = try engine.gpa.dupe(c.JSValue, self.subscribers.items);
        for (subscribers) |*value| value.* = c.JS_DupValue(engine.context, value.*);
        defer {
            for (subscribers) |value| engine.freeValue(value);
            engine.gpa.free(subscribers);
        }
        for (subscribers) |value| try (try subscriber(engine, value)).push(frame.value, frame.context, self.sequence, false);
        for (subscribers) |value| try drainSubscriber(engine, value);
    }
}
fn drainSubscriber(engine: *Engine, object: c.JSValue) anyerror!void {
    const sub = try subscriber(engine, object);
    const self = try state(engine, sub.owner);
    if (sub.running or sub.closed) return;
    sub.running = true;
    var asynchronous = false;
    defer if (!asynchronous) {
        sub.running = false;
    };
    while (!sub.closed and sub.pending.items.len > 0) {
        const frame = sub.pending.orderedRemove(0);
        defer {
            engine.freeValue(frame.value);
            engine.freeValue(frame.context);
        }
        sub.started = true;
        const delivery = try sdk.object(engine);
        defer engine.freeValue(delivery);
        try sdk.put(engine, delivery, "kind", try sdk.text(engine, if (frame.hydrate) "hydrate" else "update"));
        try sdk.put(engine, delivery, "sequence", c.JS_NewInt64(engine.context, @intCast(frame.sequence)));
        var args = [_]c.JSValue{ frame.value, frame.context, delivery };
        const returned = c.JS_Call(engine.context, sub.listener, c.pi_js_undefined(), 3, &args);
        if (c.JS_IsException(returned)) {
            const failure = c.JS_GetException(engine.context);
            defer engine.freeValue(failure);
            try reportState(self, failure);
            continue;
        }
        defer engine.freeValue(returned);
        if (!c.JS_IsObject(returned) and !c.JS_IsFunction(engine.context, returned)) continue;
        const then = try sdk.get(engine, returned, "then");
        defer engine.freeValue(then);
        if (!c.JS_IsFunction(engine.context, then)) continue;
        const promise = try sdk.promise(engine, returned);
        defer engine.freeValue(promise);
        var data = [_]c.JSValue{object};
        const fulfilled = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 0, 1, &data));
        defer engine.freeValue(fulfilled);
        const rejected = try engine.checked(c.JS_NewCFunctionData(engine.context, settled, 1, 1, 1, &data));
        defer engine.freeValue(rejected);
        const result = try sdk.invoke(engine, promise, "then", &.{ fulfilled, rejected });
        engine.freeValue(result);
        asynchronous = true;
        return;
    }
}
fn settled(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, failure: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const sub = subscriber(engine, data[0]) catch |err| return durable.reject(engine, err);
    sub.running = false;
    if (failure == 1) reportState(state(engine, sub.owner) catch |err| return durable.reject(engine, err), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return durable.reject(engine, err);
    drainSubscriber(engine, data[0]) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn report(engine: *Engine, failure: c.JSValue) !void {
    const error_value = try normalizeError(engine, failure);
    defer engine.freeValue(error_value);
    var args = [_]c.JSValue{error_value};
    if (c.JS_EnqueueJob(engine.context, reportJob, 1, &args) < 0) return error.JavaScriptException;
}
fn normalizeError(engine: *Engine, failure: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Error");
    defer engine.freeValue(constructor);
    const instance = c.JS_IsInstanceOf(engine.context, failure, constructor);
    if (instance < 0) return error.JavaScriptException;
    return if (instance > 0) c.JS_DupValue(engine.context, failure) else blk: {
        const string = try sdk.get(engine, global, "String");
        defer engine.freeValue(string);
        var conversion = [_]c.JSValue{failure};
        const message = try engine.checked(c.JS_Call(engine.context, string, c.pi_js_undefined(), 1, &conversion));
        defer engine.freeValue(message);
        var args = [_]c.JSValue{message};
        break :blk try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
    };
}
fn reportState(self: *State, failure: c.JSValue) !void {
    const reporter = self.projection_report orelse return report(self.engine, failure);
    if (!self.projected or c.JS_IsUndefined(reporter)) return report(self.engine, failure);
    const normalized = try normalizeError(self.engine, failure);
    defer self.engine.freeValue(normalized);
    var args = [_]c.JSValue{normalized};
    const result = try self.engine.checked(c.JS_Call(self.engine.context, reporter, c.pi_js_undefined(), 1, &args));
    self.engine.freeValue(result);
}
fn reportJob(context: ?*c.JSContext, _: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_Throw(context, c.JS_DupValue(context, argv[0]));
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
    const value = try engine.eval("({n:1})", "state-initial-data-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    const object = try create(engine, session, .{ .value = value, .record = record, .version = 1, .context = context });
    defer engine.freeValue(object);
    const listener = try engine.eval("()=>{}", "state-listener-input-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(listener);
    const cancel = try methodOwned(engine, object, listener, 0);
    defer engine.freeValue(cancel);
    const publication_value = try engine.eval("({changes:[{type:'document',record:{id:7},version:1,value:{n:2},ops:[['s',['n'],2]]}]})", "state-publication-data-fixture", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(publication_value);
    try receive(engine, object, publication_value, context);
    try flush(engine, object);
    const returned = try engine.checked(c.JS_Call(engine.context, cancel, c.pi_js_undefined(), 0, null));
    engine.freeValue(returned);
    try (try state(engine, object)).dispose();
}
test "native durable VM document state construction subscriptions queued publication and disposal unwind every GPA failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
