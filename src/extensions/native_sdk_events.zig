//! SDK event continuations own their original private session and invocation.
const std = @import("std");
const engine_mod = @import("engine.zig");
const bindings = @import("native_bindings.zig");
const ui_mod = @import("native_ui.zig");
const sdk = @import("native_sdk.zig");
const scopes = @import("native_async_scope.zig");
const c = engine_mod.c;
const Manager = struct { engine: *engine_mod.Engine, class: c.JSClassID, tasks: std.ArrayList(c.JSValue) = .empty, head: ?*Task = null };
const Task = struct {
    engine: *engine_mod.Engine,
    gpa: std.mem.Allocator,
    manager: ?*Manager,
    previous: ?*Task = null,
    next: ?*Task = null,
    binding: *bindings.Bindings,
    binding_owner: c.JSValue,
    binding_class: c.JSClassID,
    owner_id: u64,
    owner: c.JSValue,
    token: c.JSValue,
    session: c.JSValue,
    captured: ?bindings.Bindings.SdkContext,
    snapshot_value: ?c.JSValue = null,
    snapshot: []u8,
    event: []u8,
    payload: []u8,
    invocation: bindings.Bindings.InvocationState = .{},
    ui: ui_mod.Manager.InvocationState = .{},
    previous_active: ?*bindings.Bindings = null,
    active: bool = false,
    completed: bool = false,
    closed: bool = false,
    activation_failed: bool = false,
    fn liveBinding(self: *Task) ?*bindings.Bindings {
        return bindings.Bindings.liveOwner(self.engine, self.binding_owner, self.binding_class);
    }
    fn validate(engine: *engine_mod.Engine, raw: ?*anyopaque) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        const captured = self.captured orelse return scopes.throwMessage(engine, @import("native_context_lifetime.zig").default_message);
        const lease = sdk.sessionModelLease(try sdk.state(engine, self.session)) catch |err| switch (err) {
            error.NativeSDKDisposed, error.RetiredNativeSDKModelLease, error.NativeSDKModelLeaseUnavailable => return scopes.throwMessage(engine, @import("native_context_lifetime.zig").default_message),
            else => return err,
        };
        if (self.closed or self.activation_failed or self.liveBinding() == null or lease.generation != captured.lease.generation or lease.runtime_id != captured.lease.runtime_id) return scopes.throwMessage(engine, @import("native_context_lifetime.zig").default_message);
    }
    fn activate(raw: ?*anyopaque) void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        const binding = self.liveBinding() orelse return;
        self.binding = binding;
        self.previous_active = if (binding.broker) |broker| broker.active else null;
        binding.exchangeInvocation(&self.invocation);
        if (!self.completed) {
            if (!binding.sdk_resource_owner) binding.ui_manager.exchangeInvocation(&self.ui);
        } else if (self.captured) |captured| {
            _ = binding.pushSdkContext(captured) catch {
                self.activation_failed = true;
                self.active = true;
                return;
            };
            if (self.snapshot_value) |snapshot| binding.context_snapshot = c.JS_DupValue(self.engine.context, snapshot);
            if (binding.broker) |broker| broker.active = binding;
        }
        self.active = true;
    }
    fn deactivate(raw: ?*anyopaque) void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        if (!self.active) return;
        self.active = false;
        if (!self.completed) {
            if (!self.binding.sdk_resource_owner) self.binding.ui_manager.exchangeInvocation(&self.ui);
        } else self.binding.retireSdkScope();
        self.binding.exchangeInvocation(&self.invocation);
        if (self.binding.broker) |broker| broker.active = self.previous_active;
    }
    fn releaseUi(self: *Task) void {
        self.ui.pending.deinit(self.gpa);
        self.ui.pending = .empty;
        self.ui.customs.deinit(self.gpa);
        self.ui.customs = .empty;
        if (self.ui.components) |*components| components.deinit();
        self.ui.components = null;
    }
    fn removePending(self: *Task) void {
        const manager_ = self.manager orelse return;
        for (manager_.tasks.items, 0..) |value, index| if (c.JS_IsStrictEqual(self.engine.context, value, self.owner)) {
            _ = manager_.tasks.swapRemove(index);
            self.engine.freeValue(value);
            break;
        };
    }
    fn complete(self: *Task) void {
        if (self.closed or self.completed) return;
        const outer = scopes.enter(self.engine, self.token);
        if (self.binding.context_snapshot) |snapshot| self.snapshot_value = c.JS_DupValue(self.engine.context, snapshot);
        self.binding.retireTicket();
        const dormant = scopes.enter(self.engine, c.pi_js_undefined());
        self.completed = true;
        self.releaseUi();
        self.removePending();
        dormant.restore();
        outer.restore();
    }
    fn close(self: *Task) void {
        if (self.closed) return;
        const outer = scopes.enter(self.engine, self.token);
        if (self.active) {
            if (self.completed) self.binding.retireSdkScope() else self.binding.retireTicket();
        }
        const dormant = scopes.enter(self.engine, c.pi_js_undefined());
        self.closed = true;
        if (!self.completed) self.releaseUi();
        self.completed = true;
        scopes.retire(self.engine, self.token);
        self.removePending();
        dormant.restore();
        outer.restore();
    }
    fn unlink(self: *Task) void {
        const manager_ = self.manager orelse return;
        if (self.previous) |previous| previous.next = self.next else manager_.head = self.next;
        if (self.next) |next| next.previous = self.previous;
        self.manager = null;
        self.previous = null;
        self.next = null;
    }
};
fn manager(engine: *engine_mod.Engine) !*Manager {
    if (engine.native_sdk_events) |raw| return @ptrCast(@alignCast(raw));
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native SDK event owner", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const result = try engine.gpa.create(Manager);
    result.* = .{ .engine = engine, .class = class };
    engine.native_sdk_events = result;
    engine.native_sdk_events_deinit = deinit;
    engine.native_sdk_event_retire_owner = retireOwner;
    engine.native_sdk_default_admission = admitDefault;
    return result;
}
pub fn deinit(engine: *engine_mod.Engine) void {
    const raw = engine.native_sdk_events orelse return;
    const self: *Manager = @ptrCast(@alignCast(raw));
    while (self.head) |task| {
        const root = c.JS_DupValue(engine.context, task.owner);
        task.close();
        task.unlink();
        engine.freeValue(root);
    }
    self.tasks.deinit(engine.gpa);
    engine.native_sdk_events = null;
    engine.native_sdk_events_deinit = null;
    engine.native_sdk_event_retire_owner = null;
    engine.native_sdk_default_admission = null;
    engine.gpa.destroy(self);
}
fn admitDefault(engine: *engine_mod.Engine, _: u64) !void {
    try scopes.requireLive(engine);
}
pub fn retireOwner(engine: *engine_mod.Engine, owner_id: u64) void {
    const raw = engine.native_sdk_events orelse return;
    const self: *Manager = @ptrCast(@alignCast(raw));
    var cursor = self.head;
    while (cursor) |task| {
        cursor = task.next;
        if (task.owner_id != owner_id) continue;
        const root = c.JS_DupValue(engine.context, task.owner);
        scopes.denyWithMessage(engine, task.token, @import("native_context_lifetime.zig").default_message) catch {};
        task.close();
        engine.freeValue(root);
    }
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const task: *Task = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    std.debug.assert(task.completed);
    task.unlink();
    for ([_]c.JSValue{ task.token, task.session, task.binding_owner }) |root| c.JS_FreeValueRT(runtime, root);
    if (task.captured) |captured| for ([_]c.JSValue{ captured.session, captured.registry, captured.manager }) |root| c.JS_FreeValueRT(runtime, root);
    if (task.snapshot_value) |snapshot| c.JS_FreeValueRT(runtime, snapshot);
    task.gpa.free(task.snapshot);
    task.gpa.free(task.event);
    task.gpa.free(task.payload);
    task.gpa.destroy(task);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const task: *Task = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ task.token, task.session, task.binding_owner }) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.captured) |captured| for ([_]c.JSValue{ captured.session, captured.registry, captured.manager }) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.snapshot_value) |snapshot| c.JS_MarkValue(runtime, snapshot, marker);
    for (task.invocation.actions.items) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.invocation.context_snapshot) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.invocation.sdk_context) |scope| for ([_]c.JSValue{ scope.session, scope.registry, scope.manager }) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.invocation.invocation_signal) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.ui.signal) |root| c.JS_MarkValue(runtime, root, marker);
}
fn fromData(context: ?*c.JSContext, data: [*c]c.JSValue) *Task {
    _ = context;
    return @ptrCast(@alignCast(c.JS_GetOpaque(data[0], c.JS_GetClassID(data[0])).?));
}
fn finished(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const task = fromData(context, data);
    const engine = engine_mod.Engine.fromContext(context.?);
    task.complete();
    if (magic != 0) return c.JS_Throw(context, if (argc > 0) c.JS_DupValue(context, args[0]) else c.pi_js_undefined());
    _ = engine;
    return c.pi_js_undefined();
}
fn start(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const task = fromData(context, data);
    return run(task) catch |err| {
        task.close();
        return sdk.fail(engine_mod.Engine.fromContext(context.?), err);
    };
}
fn run(task: *Task) !c.JSValue {
    if (task.closed) return error.NativeSDKEventRetired;
    const engine = task.engine;
    const guard = scopes.enter(engine, task.token);
    defer guard.restore();
    const current_lease = sdk.sessionModelLease(try sdk.state(engine, task.session)) catch |err| switch (err) {
        error.NativeSDKDisposed, error.RetiredNativeSDKModelLease, error.NativeSDKModelLeaseUnavailable => null,
        else => return err,
    };
    var admitted = false;
    if (task.captured) |captured| if (current_lease) |current| {
        if (captured.lease.generation == current.generation and captured.lease.runtime_id == current.runtime_id) {
            _ = try task.binding.pushSdkContext(captured);
            admitted = true;
        }
    };
    if (!admitted) {
        // A disposed runner may still report errors from retained raw UI
        // services. It admits no SDK lease and denies every native capability.
        try scopes.denyWithMessage(engine, task.token, @import("native_context_lifetime.zig").default_message);
    }
    try task.binding.setContext(task.snapshot);
    const pending = try task.binding.invokeSdkHookPromise(task.event, task.payload, task.session, !admitted);
    defer engine.freeValue(pending);
    var data = [_]c.JSValue{task.owner};
    const complete = try engine.checked(c.JS_NewCFunctionData2(engine.context, finished, "sdkEventComplete", 1, 0, 1, &data));
    defer engine.freeValue(complete);
    const rejected = try engine.checked(c.JS_NewCFunctionData2(engine.context, finished, "sdkEventRejected", 1, 1, 1, &data));
    defer engine.freeValue(rejected);
    var callbacks = [_]c.JSValue{ complete, rejected };
    return engine.checked(c.JS_Call(engine.context, task.binding.ui_manager.components.promise_then, pending, callbacks.len, &callbacks));
}
pub fn emitOne(engine: *engine_mod.Engine, binding: *bindings.Bindings, session: c.JSValue, captured: ?bindings.Bindings.SdkContext, snapshot: []const u8, event: []const u8, payload: []const u8, previous: ?c.JSValue) !c.JSValue {
    const self = try manager(engine);
    if (self.tasks.items.len >= 1024) return error.NativeSDKEventLimit;
    var transferred = false;
    const owned_snapshot = try engine.gpa.dupe(u8, snapshot);
    errdefer if (!transferred) engine.gpa.free(owned_snapshot);
    const owned_event = try engine.gpa.dupe(u8, event);
    errdefer if (!transferred) engine.gpa.free(owned_event);
    const owned_payload = try engine.gpa.dupe(u8, payload);
    errdefer if (!transferred) engine.gpa.free(owned_payload);
    const task = try engine.gpa.create(Task);
    errdefer if (!transferred) engine.gpa.destroy(task);
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, self.class));
    errdefer if (!transferred) engine.freeValue(owner);
    const token = try scopes.create(engine, task, Task.activate, Task.deactivate);
    task.* = .{ .engine = engine, .gpa = engine.gpa, .manager = self, .binding = binding, .binding_owner = c.JS_DupValue(engine.context, binding.owner_token), .binding_class = binding.owner_class, .owner_id = binding.owner_id, .owner = owner, .token = token, .session = c.JS_DupValue(engine.context, session), .captured = if (captured) |scope| .{ .session = c.JS_DupValue(engine.context, scope.session), .registry = c.JS_DupValue(engine.context, scope.registry), .manager = c.JS_DupValue(engine.context, scope.manager), .lease = scope.lease } else null, .snapshot = owned_snapshot, .event = owned_event, .payload = owned_payload };
    task.ui.components = binding.ui_manager.components.forkInvocation();
    _ = c.JS_SetOpaque(owner, task);
    transferred = true;
    task.next = self.head;
    if (self.head) |head| head.previous = task;
    self.head = task;
    scopes.bindOwner(engine, token, owner, Task.validate);
    scopes.markSdk(engine, token);
    self.tasks.append(engine.gpa, owner) catch |err| {
        task.close();
        // Ownership was transferred to the opaque finalizer.
        engine.freeValue(owner);
        return err;
    };
    errdefer task.close();
    if (previous) |promise| {
        var data = [_]c.JSValue{owner};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, start, "sdkEventStart", 0, 0, 1, &data));
        defer engine.freeValue(callback);
        var args = [_]c.JSValue{callback};
        return engine.checked(c.JS_Call(engine.context, binding.ui_manager.components.promise_then, promise, 1, &args));
    }
    return run(task);
}
