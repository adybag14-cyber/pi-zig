//! Private command metadata ownership. Public properties retain their JS identity.
//! Enter the registered owner only for the original argument callback and the
//! existing Source await continuation; do not wrap or replace the callable.
const std = @import("std");
const js = @import("native_js_values.zig");
const bindings = @import("native_bindings.zig");
const scopes = @import("native_async_scope.zig");
const lifetime = @import("native_context_lifetime.zig");
const ui = @import("native_ui.zig");
const c = js.c;
pub const Continue = *const fn (?*anyopaque, c.JSValue, c.JSValue) anyerror!c.JSValue;
pub const Publish = *const fn (?*anyopaque, u64, []const u8) anyerror!void;
const Manager = struct {
    engine: *js.Engine,
    row_class: c.JSClassID,
    task_class: c.JSClassID,
    head: ?*Task = null,
    pending: std.ArrayList(c.JSValue) = .empty,
};
const Row = struct {
    gpa: std.mem.Allocator,
    owner: c.JSValue,
    owner_class: c.JSClassID,
    owner_id: u64,
    guard: c.JSValue,
    definition: c.JSValue,
    callback: c.JSValue,
    snapshot: c.JSValue,
    registration_key: ?[]u8,
    captured: ?bindings.Bindings.SdkContext,
    publish: ?Publish,
    publish_context: ?*anyopaque,
    fn entry(self: *Row, engine: *js.Engine) !?*bindings.Bindings {
        const binding = bindings.Bindings.liveOwner(engine, self.owner, self.owner_class) orelse return null;
        if (!binding.sdk_resource_owner) {
            const message = try engine.checked(c.JS_GetPropertyStr(engine.context, self.guard, "message"));
            defer engine.freeValue(message);
            if (!c.JS_IsUndefined(message) and c.JS_ToBool(engine.context, message) != 0) return null;
        }
        const group: *@import("native_group.zig").Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return null));
        var member = false;
        for (group.entries.items) |registration| if (registration.binding == binding and registration.id == self.owner_id) {
            if (registration.sdk_scope) |scope| if (scope.retired or scope.runtime_invalidated) return null;
            member = true;
            break;
        };
        if (!member) return null;
        return binding;
    }
    fn validate(self: *Row, engine: *js.Engine) !*bindings.Bindings {
        const binding = bindings.Bindings.liveOwner(engine, self.owner, self.owner_class) orelse {
            try scopes.throwMessage(engine, lifetime.default_message);
            unreachable;
        };
        if (binding.sdk_resource_owner) {
            // Pi belongs to the shared loader runtime, not the session that
            // produced this row. API entry validates its current binding.
            try @import("native_sdk_resource_owners.zig").assertPiRuntime(binding);
        } else try lifetime.assertActive(engine, self.guard);
        return binding;
    }
};
const Task = struct {
    engine: *js.Engine,
    gpa: std.mem.Allocator,
    manager: ?*Manager,
    previous: ?*Task = null,
    next: ?*Task = null,
    owner: c.JSValue,
    row_value: c.JSValue,
    row: *Row,
    token: c.JSValue,
    binding: *bindings.Bindings,
    invocation: bindings.Bindings.InvocationState = .{},
    ui_state: ui.Manager.InvocationState = .{},
    previous_broker: ?*bindings.Bindings = null,
    pending: c.JSValue,
    snapshot_value: ?c.JSValue = null,
    active: bool = false,
    completed: bool = false,
    closed: bool = false,
    activation_failed: bool = false,
    fn validate(engine: *js.Engine, raw: ?*anyopaque) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        if (self.closed) return;
        if (self.activation_failed or try self.row.entry(engine) == null) self.close();
    }
    fn validateTarget(engine: *js.Engine, raw: ?*anyopaque, target: c.JSValue) !void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        if (c.JS_IsStrictEqual(engine.context, self.row.owner, target)) {
            _ = try self.row.validate(engine);
        } else try validate(engine, self);
    }
    fn activate(raw: ?*anyopaque) void {
        const self: *Task = @ptrCast(@alignCast(raw.?));
        if (self.closed) return;
        const binding = bindings.Bindings.liveOwner(self.engine, self.row.owner, self.row.owner_class) orelse return;
        self.binding = binding;
        self.previous_broker = if (binding.broker) |broker| broker.active else null;
        binding.exchangeInvocation(&self.invocation);
        if (!self.completed) {
            if (!binding.sdk_resource_owner) binding.ui_manager.exchangeInvocation(&self.ui_state);
        } else {
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
            if (!self.binding.sdk_resource_owner) self.binding.ui_manager.exchangeInvocation(&self.ui_state);
        } else self.binding.retireSdkScope();
        self.binding.exchangeInvocation(&self.invocation);
        if (self.binding.broker) |broker| broker.active = self.previous_broker;
    }
    fn releaseUi(self: *Task) void {
        self.ui_state.pending.deinit(self.gpa);
        self.ui_state.pending = .empty;
        self.ui_state.customs.deinit(self.gpa);
        self.ui_state.customs = .empty;
        if (self.ui_state.components) |*components| components.deinit();
        self.ui_state.components = null;
    }
    fn removePending(self: *Task) void {
        const manager_ = self.manager orelse return;
        for (manager_.pending.items, 0..) |value, index| if (c.JS_IsStrictEqual(self.engine.context, value, self.owner)) {
            _ = manager_.pending.swapRemove(index);
            self.engine.freeValue(value);
            break;
        };
    }
    fn flush(self: *Task) !void {
        if (self.row.captured != null or self.binding.actions.items.len == 0) return;
        if (self.row.publish) |publish| {
            const actions = try self.binding.finishTicket(c.pi_js_undefined());
            defer self.gpa.free(actions);
            try publish(self.row.publish_context, self.row.owner_id, actions);
            for (self.binding.actions.items) |action| self.engine.freeValue(action);
            self.binding.actions.clearRetainingCapacity();
        }
    }
    fn complete(self: *Task) !void {
        if (self.closed or self.completed) return;
        try validate(self.engine, self);
        if (self.closed) return;
        const outer = scopes.enter(self.engine, self.token);
        defer outer.restore();
        try self.flush();
        if (self.binding.context_snapshot) |snapshot| self.snapshot_value = c.JS_DupValue(self.engine.context, snapshot);
        self.binding.retireTicket();
        const dormant = scopes.enter(self.engine, c.pi_js_undefined());
        defer dormant.restore();
        self.completed = true;
        self.releaseUi();
        self.removePending();
    }
    fn close(self: *Task) void {
        if (self.closed) return;
        scopes.disable(self.engine, self.token);
        const outer = scopes.enter(self.engine, self.token);
        defer outer.restore();
        if (self.active) {
            if (self.completed) self.binding.retireSdkScope() else self.binding.retireTicket();
        }
        const dormant = scopes.enter(self.engine, c.pi_js_undefined());
        defer dormant.restore();
        self.closed = true;
        if (!self.completed) self.releaseUi();
        self.completed = true;
        scopes.retire(self.engine, self.token);
        self.removePending();
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
fn manager(engine: *js.Engine) !*Manager {
    if (engine.native_command_metadata) |raw| return @ptrCast(@alignCast(raw));
    if (engine.native_command_metadata_row_class == 0) {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Object", .finalizer = finalizeRow, .gc_mark = markRow };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        engine.native_command_metadata_row_class = class;
    }
    if (engine.native_command_metadata_task_class == 0) {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native command argument owner", .finalizer = finalizeTask, .gc_mark = markTask };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        engine.native_command_metadata_task_class = class;
    }
    const result = try engine.gpa.create(Manager);
    result.* = .{ .engine = engine, .row_class = engine.native_command_metadata_row_class, .task_class = engine.native_command_metadata_task_class };
    engine.native_command_metadata = result;
    engine.native_command_metadata_deinit = deinit;
    engine.native_command_metadata_pump = pump;
    return result;
}
fn rowRecord(engine: *js.Engine, value: c.JSValue) ?*Row {
    if (engine.native_command_metadata_row_class == 0) return null;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_command_metadata_row_class)));
}
pub const Capture = struct {
    binding: *bindings.Bindings,
    definition: c.JSValue,
    snapshot: c.JSValue,
    registration_key: ?[]const u8 = null,
    captured: ?bindings.Bindings.SdkContext = null,
    publish: ?Publish = null,
    publish_context: ?*anyopaque = null,
};
/// Called after Source has projected an ordinary metadata row. Spreading that
/// data-only result adds no reads of the original registration's getters.
pub fn create(engine: *js.Engine, metadata: c.JSValue, capture: Capture) !c.JSValue {
    const self = try manager(engine);
    const callback = if (c.JS_IsUndefined(metadata)) c.pi_js_undefined() else try js.get(engine, metadata, "getArgumentCompletions");
    errdefer engine.freeValue(callback);
    const key = if (capture.registration_key) |name| try engine.gpa.dupe(u8, name) else null;
    errdefer if (key) |name| engine.gpa.free(name);
    const row = try engine.gpa.create(Row);
    errdefer engine.gpa.destroy(row);
    const result = try engine.checked(c.JS_NewObjectClass(engine.context, self.row_class));
    errdefer engine.freeValue(result);
    const ordinary = try js.object(engine);
    defer engine.freeValue(ordinary);
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, ordinary));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, result, prototype) < 0) return js.capture(engine);
    if (!c.JS_IsUndefined(metadata)) try js.spreadInto(engine, result, metadata);
    row.* = .{ .gpa = engine.gpa, .owner = c.JS_DupValue(engine.context, capture.binding.owner_token), .owner_class = capture.binding.owner_class, .owner_id = capture.binding.owner_id, .guard = c.JS_DupValue(engine.context, capture.binding.context_guard), .definition = c.JS_DupValue(engine.context, capture.definition), .callback = callback, .snapshot = c.JS_DupValue(engine.context, capture.snapshot), .registration_key = key, .captured = if (capture.captured) |scope| .{ .session = c.JS_DupValue(engine.context, scope.session), .registry = c.JS_DupValue(engine.context, scope.registry), .manager = c.JS_DupValue(engine.context, scope.manager), .lease = scope.lease } else null, .publish = capture.publish, .publish_context = capture.publish_context };
    _ = c.JS_SetOpaque(result, row);
    return result;
}
pub fn isOwned(engine: *js.Engine, value: c.JSValue) bool {
    return rowRecord(engine, value) != null;
}
pub fn matchesDefinition(engine: *js.Engine, anchor: c.JSValue, definition: c.JSValue) bool {
    const row = rowRecord(engine, anchor) orelse return false;
    return c.JS_IsStrictEqual(engine.context, row.definition, definition);
}
/// Copy a native association without dereferencing its former Bindings pointer.
/// An anchor is rooted before guest metadata getters can replace/remove owners.
pub fn copyMetadata(engine: *js.Engine, anchor: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const original = rowRecord(engine, anchor) orelse return error.UnownedNativeCommandProjection;
    const self = try manager(engine);
    const callback = try js.get(engine, metadata, "getArgumentCompletions");
    errdefer engine.freeValue(callback);
    const key = if (original.registration_key) |name| try engine.gpa.dupe(u8, name) else null;
    errdefer if (key) |name| engine.gpa.free(name);
    const row = try engine.gpa.create(Row);
    errdefer engine.gpa.destroy(row);
    const result = try engine.checked(c.JS_NewObjectClass(engine.context, self.row_class));
    errdefer engine.freeValue(result);
    const prototype = try engine.checked(c.JS_GetPrototype(engine.context, anchor));
    defer engine.freeValue(prototype);
    if (c.JS_SetPrototype(engine.context, result, prototype) < 0) return js.capture(engine);
    try js.spreadInto(engine, result, metadata);
    row.* = .{ .gpa = engine.gpa, .owner = c.JS_DupValue(engine.context, original.owner), .owner_class = original.owner_class, .owner_id = original.owner_id, .guard = c.JS_DupValue(engine.context, original.guard), .definition = c.pi_js_undefined(), .callback = callback, .snapshot = c.JS_DupValue(engine.context, original.snapshot), .registration_key = key, .captured = if (original.captured) |scope| .{ .session = c.JS_DupValue(engine.context, scope.session), .registry = c.JS_DupValue(engine.context, scope.registry), .manager = c.JS_DupValue(engine.context, scope.manager), .lease = scope.lease } else null, .publish = original.publish, .publish_context = original.publish_context };
    _ = c.JS_SetOpaque(result, row);
    return result;
}
/// Source frontend copies properties but must not grant a guest replacement
/// the original registration's capability scope.
pub fn copyRetainedMetadata(engine: *js.Engine, anchor: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const original = rowRecord(engine, anchor) orelse return error.UnownedNativeCommandProjection;
    const result = try copyMetadata(engine, anchor, metadata);
    const retained = rowRecord(engine, result).?;
    engine.freeValue(retained.callback);
    retained.callback = c.JS_DupValue(engine.context, original.callback);
    return result;
}
/// Preserve both Source getter reads at the caller. The caller supplies the
/// second read and its existing await operation; no added JS promise handlers.
pub fn invoke(engine: *js.Engine, receiver: c.JSValue, callback: c.JSValue, prefix: c.JSValue, signal: c.JSValue, continuation: Continue, context: ?*anyopaque) !c.JSValue {
    const row = rowRecord(engine, receiver) orelse {
        const raw_result = try js.call(engine, callback, receiver, &.{prefix});
        defer engine.freeValue(raw_result);
        return continuation(context, raw_result, c.pi_js_undefined());
    };
    // A user-replaced callback is still an ordinary dynamic call, but cannot
    // acquire the original registration's native owner authority.
    if (!c.JS_IsStrictEqual(engine.context, callback, row.callback)) {
        const raw_result = try js.call(engine, callback, receiver, &.{prefix});
        defer engine.freeValue(raw_result);
        return continuation(context, raw_result, c.pi_js_undefined());
    }
    const live_binding = try row.entry(engine);
    const self = try manager(engine);
    if (self.pending.items.len >= 1024) return error.NativeCommandArgumentLimit;
    try self.pending.ensureUnusedCapacity(engine.gpa, 1);
    var transferred = false;
    const task = try engine.gpa.create(Task);
    errdefer if (!transferred) engine.gpa.destroy(task);
    const owner = try engine.checked(c.JS_NewObjectClass(engine.context, self.task_class));
    errdefer if (!transferred) engine.freeValue(owner);
    const token = try scopes.create(engine, task, Task.activate, Task.deactivate);
    task.* = .{ .engine = engine, .gpa = engine.gpa, .manager = self, .owner = owner, .row_value = c.JS_DupValue(engine.context, receiver), .row = row, .token = token, .binding = live_binding orelse undefined, .pending = c.pi_js_undefined(), .closed = live_binding == null, .completed = live_binding == null };
    if (live_binding) |binding| task.ui_state.components = binding.ui_manager.components.forkInvocation();
    _ = c.JS_SetOpaque(owner, task);
    task.next = self.head;
    if (self.head) |head| head.previous = task;
    self.head = task;
    scopes.bindOwner(engine, token, owner, Task.validate);
    scopes.bindTargetGuard(engine, token, Task.validateTarget);
    if (row.captured != null) scopes.markSdk(engine, token);
    if (live_binding != null) self.pending.appendAssumeCapacity(c.JS_DupValue(engine.context, owner)) else scopes.retire(engine, token);
    transferred = true;
    defer engine.freeValue(owner);
    // Opaque ownership has transferred. Later failures close before freeing
    // the local root; finalization performs the native allocation cleanup.
    return run(task, callback, prefix, signal, continuation, context) catch |err| {
        closePreservingException(task);
        return err;
    };
}
fn run(task: *Task, callback: c.JSValue, prefix: c.JSValue, signal: c.JSValue, continuation: Continue, context: ?*anyopaque) !c.JSValue {
    const engine = task.engine;
    const guard = scopes.enter(engine, task.token);
    defer guard.restore();
    try Task.validate(engine, task);
    if (task.closed) {
        const raw_result = try js.call(engine, callback, task.row_value, &.{prefix});
        defer engine.freeValue(raw_result);
        return continuation(context, raw_result, task.token);
    }
    // Source invokes the raw completion callable. SDK Pi methods resolve
    // their own loader runtime's current default context at each API entry;
    // a producer session must not replace that shared-runtime binding.
    const snapshot = try engine.stringify(task.row.snapshot);
    defer engine.gpa.free(snapshot);
    try task.binding.beginTicket(signal, snapshot);
    const raw_result = try js.call(engine, callback, task.row_value, &.{prefix});
    defer engine.freeValue(raw_result);
    const result = try continuation(context, raw_result, task.token);
    task.pending = c.JS_DupValue(engine.context, result);
    return result;
}
pub fn pump(engine: *js.Engine) !bool {
    const raw = engine.native_command_metadata orelse return false;
    const self: *Manager = @ptrCast(@alignCast(raw));
    var worked = false;
    const pending = try engine.gpa.alloc(c.JSValue, self.pending.items.len);
    defer engine.gpa.free(pending);
    for (self.pending.items, pending) |value, *root| root.* = c.JS_DupValue(engine.context, value);
    defer for (pending) |root| engine.freeValue(root);
    for (pending) |value| {
        const task: *Task = @ptrCast(@alignCast(c.JS_GetOpaque(value, self.task_class).?));
        if (task.closed or task.completed or c.JS_IsUndefined(task.pending)) continue;
        const root = c.JS_DupValue(engine.context, task.owner);
        defer engine.freeValue(root);
        try Task.validate(engine, task);
        if (task.closed) {
            worked = true;
            continue;
        }
        if (!task.binding.sdk_resource_owner) {
            const guard = scopes.enter(engine, task.token);
            defer guard.restore();
            worked = (try task.binding.ui_manager.poll()) or worked;
            try task.flush();
        }
        if (c.JS_PromiseState(engine.context, task.pending) == c.JS_PROMISE_PENDING) continue;
        try task.complete();
        worked = true;
    }
    return worked;
}
fn taskForToken(engine: *js.Engine, token: c.JSValue) ?*Task {
    if (engine.native_command_metadata_task_class == 0) return null;
    const owner = scopes.ownerValue(engine, token);
    defer engine.freeValue(owner);
    return @ptrCast(@alignCast(c.JS_GetOpaque(owner, engine.native_command_metadata_task_class)));
}
pub fn validateToken(engine: *js.Engine, token: c.JSValue) !void {
    if (c.JS_IsUndefined(token)) return;
    const task = taskForToken(engine, token) orelse return error.InvalidNativeCommandArgumentOwner;
    try Task.validate(engine, task);
}
/// Finish within the already-existing Source argument await continuation, so
/// even a final fulfilled job releases its ticket without another engine pump.
pub fn completeToken(engine: *js.Engine, token: c.JSValue) !void {
    if (taskForToken(engine, token)) |task| if (!task.closed) try task.complete();
}
pub fn closeToken(engine: *js.Engine, token: c.JSValue) void {
    if (taskForToken(engine, token)) |task| closePreservingException(task);
}
fn closePreservingException(task: *Task) void {
    const engine = task.engine;
    const original = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
    task.close();
    if (original) |value| {
        if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
        if (engine.captured_exception) |current| engine.freeValue(current);
        engine.captured_exception = value;
    }
}
pub fn retireOwner(engine: *js.Engine, owner_id: u64) void {
    const raw = engine.native_command_metadata orelse return;
    const self: *Manager = @ptrCast(@alignCast(raw));
    while (true) {
        var found: ?*Task = null;
        var cursor = self.head;
        while (cursor) |task| {
            if (!task.closed and task.row.owner_id == owner_id) {
                found = task;
                break;
            }
            cursor = task.next;
        }
        const task = found orelse break;
        const root = c.JS_DupValue(engine.context, task.owner);
        scopes.denyWithMessage(engine, task.token, lifetime.default_message) catch {};
        task.close();
        engine.freeValue(root);
    }
}
pub fn deinit(engine: *js.Engine) void {
    const raw = engine.native_command_metadata orelse return;
    const self: *Manager = @ptrCast(@alignCast(raw));
    while (self.head) |task| {
        const root = c.JS_DupValue(engine.context, task.owner);
        task.close();
        task.unlink();
        engine.freeValue(root);
    }
    self.pending.deinit(engine.gpa);
    engine.native_command_metadata = null;
    engine.native_command_metadata_deinit = null;
    engine.native_command_metadata_pump = null;
    engine.gpa.destroy(self);
}
fn finalizeRow(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const row: *Row = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ row.owner, row.guard, row.definition, row.callback, row.snapshot }) |root| c.JS_FreeValueRT(runtime, root);
    if (row.captured) |captured| for ([_]c.JSValue{ captured.session, captured.registry, captured.manager }) |root| c.JS_FreeValueRT(runtime, root);
    if (row.registration_key) |key| row.gpa.free(key);
    row.gpa.destroy(row);
}
fn markRow(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const row: *Row = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ row.owner, row.guard, row.definition, row.callback, row.snapshot }) |root| c.JS_MarkValue(runtime, root, marker);
    if (row.captured) |captured| for ([_]c.JSValue{ captured.session, captured.registry, captured.manager }) |root| c.JS_MarkValue(runtime, root, marker);
}
fn finalizeTask(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const task: *Task = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    std.debug.assert(task.completed);
    task.unlink();
    for ([_]c.JSValue{ task.row_value, task.token, task.pending }) |root| c.JS_FreeValueRT(runtime, root);
    if (task.snapshot_value) |snapshot| c.JS_FreeValueRT(runtime, snapshot);
    task.gpa.destroy(task);
}
fn markTask(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const task: *Task = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for ([_]c.JSValue{ task.row_value, task.token, task.pending }) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.snapshot_value) |snapshot| c.JS_MarkValue(runtime, snapshot, marker);
    for (task.invocation.actions.items) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.invocation.context_snapshot) |snapshot| c.JS_MarkValue(runtime, snapshot, marker);
    if (task.invocation.sdk_context) |captured| for ([_]c.JSValue{ captured.session, captured.registry, captured.manager }) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.invocation.invocation_signal) |root| c.JS_MarkValue(runtime, root, marker);
    if (task.ui_state.signal) |root| c.JS_MarkValue(runtime, root, marker);
}
