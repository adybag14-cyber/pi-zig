// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Complete selected internal/async_hooks.js ID/stack declarations.
//! The private bootstrap supplies its actual already-installed async_wrap binding.
//! This owner does not publish async_hooks or replace the active-hooks/fatalError owner.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const functions = @import("native_node_module_callable.zig");
const publication = @import("native_node_fs_private_publication.zig");
const c = a.c;
const Scope = a.Scope;
const Engine = a.v.em.Engine;
const Environment = callbacks.Environment;
const key = "pi-native:private/async-hooks-id-stack";
const Captures = struct {
    binding: c.JSValue,
    fields: c.JSValue,
    uid: c.JSValue,
    resources: c.JSValue,
    push_native: c.JSValue,
    pop_native: c.JSValue,
    clear_native: c.JSValue,
};
const State = struct {
    engine: *Engine,
    environment: *Environment,
    values: Captures,
    exported: c.JSValue,
};

fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    _ = c.JS_SetOpaque(holder, null);
    const engine = data.engine;
    const environment = data.environment;
    inline for (std.meta.fields(Captures)) |field|
        c.JS_FreeValueRT(runtime, @field(data.values, field.name));
    c.JS_FreeValueRT(runtime, data.exported);
    engine.gpa.destroy(data);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(State));
    environment.release();
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (std.meta.fields(Captures)) |field|
        c.JS_MarkValue(runtime, @field(data.values, field.name), marker);
    c.JS_MarkValue(runtime, data.exported, marker);
}
fn stateOf(engine: *Engine, known: c.JSValue) !*State {
    // Only the known private cache entry or its callable capture reaches here.
    const data: *State = @ptrCast(@alignCast(c.JS_GetOpaque(known, c.JS_GetClassID(known)) orelse
        return error.ActualAsyncIdStackOwnerRequired));
    if (data.engine != engine or try data.environment.requireEngine() != engine)
        return error.ActualAsyncIdStackEnvironmentMismatch;
    return data;
}
fn capture(s: *Scope, holder: c.JSValue) !*State {
    const retained = try s.own(a.duplicate(s.engine, holder));
    try s.pending();
    return stateOf(s.engine, retained);
}
fn knownBody(s: *Scope, known: c.JSValue, environment: *Environment, binding: c.JSValue) !c.JSValue {
    const data = try capture(s, known);
    if (data.environment != environment or !s.equal(data.values.binding, binding))
        return error.ActualAsyncIdStackInputsConflict;
    return a.duplicate(s.engine, known);
}
fn acquireHolder(engine: *Engine, environment: *Environment, binding: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (try environment.requireEngine() != engine) return error.ActualAsyncIdStackEnvironmentMismatch;
    _ = environment.retain();
    defer environment.release();
    if (engine.native_module_values.get(key)) |known|
        return a.expression(engine, knownBody, .{ known, environment, binding });
    const candidate = try a.expression(engine, createBody, .{ environment, binding });
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine,
            a.expression(engine, knownBody, .{ known, environment, binding }));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
pub fn create(engine: *Engine, environment: *Environment, binding: c.JSValue) !c.JSValue {
    const holder = try acquireHolder(engine, environment, binding);
    var s = Scope.init(engine);
    const retained = s.own(holder) catch |err| return s.finish(err);
    return s.finish(exportsBody(&s, retained));
}
fn exportsBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try stateOf(s.engine, holder);
    return a.duplicate(s.engine, data.exported);
}
fn createBody(s: *Scope, environment: *Environment, binding: c.JSValue) !c.JSValue {
    try s.pending();
    _ = try s.own(a.duplicate(s.engine, binding));
    const installed = environment.async_hooks_binding orelse return error.ActualAsyncWrapBindingRequired;
    if (!s.equal(installed, binding)) return error.ActualAsyncWrapBindingIdentityRequired;
    // These are the exact captured destructuring reads of the selected Source.
    // Only the stack property stays live on binding during push/pop.
    const fields = try s.get(binding, "async_hook_fields");
    const uid = try s.get(binding, "async_id_fields");
    const resources = try s.get(binding, "execution_async_resources");
    if (!s.equal(fields, environment.fields.view orelse return error.ActualAsyncHookFieldsRequired) or
        !s.equal(uid, environment.uid.view orelse return error.ActualAsyncIdFieldsRequired) or
        !s.equal(resources, environment.js_resources orelse return error.ActualExecutionResourcesRequired))
        return error.ActualAsyncWrapSharedViewsRequired;
    const values: Captures = .{
        .binding = binding, .fields = fields, .uid = uid, .resources = resources,
        .push_native = try s.get(binding, "pushAsyncContext"),
        .pop_native = try s.get(binding, "popAsyncContext"),
        .clear_native = try s.get(binding, "clearAsyncIdStack"),
    };
    if (!c.JS_IsFunction(s.engine.context, values.push_native) or
        !c.JS_IsFunction(s.engine.context, values.pop_native) or
        !c.JS_IsFunction(s.engine.context, values.clear_native))
        return error.ActualAsyncWrapNativeOperationsRequired;
    // A binding getter may retire its Environment. Never attach a closed owner.
    if (try environment.requireEngine() != s.engine) return error.ActualAsyncIdStackEnvironmentMismatch;
    const exported = try s.object();
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(State)) == 0)
        return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(State));
    const data = try s.engine.gpa.create(State);
    errdefer if (!attached) s.engine.gpa.destroy(data);
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Native async ID stack declarations",
        .finalizer = finalize, .gc_mark = mark,
    };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    const generation = try s.beforeAllocation();
    const holder = try s.checkedAllocation(
        c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), class_id), generation);
    data.* = .{ .engine = s.engine, .environment = environment.retain(),
        .values = values, .exported = a.duplicate(s.engine, exported) };
    inline for (std.meta.fields(Captures)) |field|
        @field(data.values, field.name) = a.duplicate(s.engine, @field(values, field.name));
    _ = c.JS_SetOpaque(holder, data);
    attached = true;
    inline for (.{
        .{ "newAsyncId", 0, newAsyncId },
        .{ "getDefaultTriggerAsyncId", 0, getDefaultTriggerAsyncId },
        .{ "clearDefaultTriggerAsyncId", 0, clearDefaultTriggerAsyncId },
        .{ "enabledHooksExist", 0, enabledHooksExist },
        .{ "initHooksExist", 0, initHooksExist },
        .{ "afterHooksExist", 0, afterHooksExist },
        .{ "destroyHooksExist", 0, destroyHooksExist },
        .{ "hasAsyncIdStack", 0, hasAsyncIdStack },
        .{ "pushAsyncContext", 3, pushAsyncContext },
        .{ "popAsyncContext", 1, popAsyncContext },
        .{ "executionAsyncId", 0, executionAsyncId },
        .{ "triggerAsyncId", 0, triggerAsyncId },
    }) |entry| {
        const function_value = try s.own(try functions.create(
            s.engine, entry[0], entry[1], true, entry[2], &.{holder}));
        try s.define(exported, entry[0], function_value, c.JS_PROP_C_W_E);
    }
    // Source exports the captured native function itself, retaining its identity.
    try s.define(exported, "clearAsyncIdStack", values.clear_native, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, holder);
}

fn readHookField(s: *Scope, data: *State, index: callbacks.Field) !c.JSValue {
    try s.pending();
    return s.checked(c.JS_GetPropertyUint32(s.engine.context, data.values.fields, @intFromEnum(index)));
}
fn uidField(s: *Scope, data: *State, index: callbacks.Uid) !c.JSValue {
    try s.pending();
    return s.checked(c.JS_GetPropertyUint32(s.engine.context, data.values.uid, @intFromEnum(index)));
}
fn putKey(s: *Scope, target: c.JSValue, property: c.JSValue, value: c.JSValue) !void {
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, target,
        a.duplicate(s.engine, property), a.duplicate(s.engine, value), c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.ActualAsyncIdStackWriteReason;
}
fn putUid(s: *Scope, data: *State, index: callbacks.Uid, value: c.JSValue) !void {
    try putKey(s, data.values.uid, c.JS_NewUint32(s.engine.context, @intFromEnum(index)), value);
}
fn hasHooksBody(s: *Scope, data: *State, index: callbacks.Field) !c.JSValue {
    return a.duplicate(s.engine, try s.binary(6, try readHookField(s, data, index), c.JS_NewInt32(s.engine.context, 0)));
}
fn predicateBody(s: *Scope, holder: c.JSValue, index: callbacks.Field) !c.JSValue {
    const data = try capture(s, holder);
    return hasHooksBody(s, data, index);
}
fn enabledHooksExist(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, predicateBody, .{ roots[0], callbacks.Field.check });
}
fn initHooksExist(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, predicateBody, .{ roots[0], callbacks.Field.init });
}
fn afterHooksExist(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, predicateBody, .{ roots[0], callbacks.Field.after });
}
fn destroyHooksExist(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, predicateBody, .{ roots[0], callbacks.Field.destroy });
}
fn hasAsyncIdStack(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, predicateBody, .{ roots[0], callbacks.Field.stack_length });
}
fn readUidBody(s: *Scope, holder: c.JSValue, index: callbacks.Uid) !c.JSValue {
    const data = try capture(s, holder);
    return a.duplicate(s.engine, try uidField(s, data, index));
}
fn executionAsyncId(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, readUidBody, .{ roots[0], callbacks.Uid.execution });
}
fn triggerAsyncId(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, readUidBody, .{ roots[0], callbacks.Uid.trigger });
}
fn newAsyncId(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, newIdBody, .{roots[0]});
}
fn newIdBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    const previous = try uidField(s, data, .counter);
    try s.pending();
    const updated = try s.checked(c.JS_PiIncrement(s.engine.context, previous));
    try putUid(s, data, .counter, updated);
    return a.duplicate(s.engine, updated);
}
fn getDefaultTriggerAsyncId(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, defaultIdBody, .{roots[0]});
}
fn defaultIdBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    const default_id = try uidField(s, data, .default_trigger);
    if (s.truthy(try s.binary(4, default_id, c.JS_NewInt32(s.engine.context, 0))))
        return a.duplicate(s.engine, try uidField(s, data, .execution));
    return a.duplicate(s.engine, default_id);
}
fn clearDefaultTriggerAsyncId(engine: *Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, clearDefaultBody, .{roots[0]});
}
fn clearDefaultBody(s: *Scope, holder: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    try putUid(s, data, .default_trigger, c.JS_NewInt32(s.engine.context, -1));
    return c.pi_js_undefined();
}

fn pushAsyncContext(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, pushBody, .{ roots[0], a.arg(args, 0), a.arg(args, 1), a.arg(args, 2) });
}
fn resourceAssignment(s: *Scope, data: *State, offset: c.JSValue, resource: c.JSValue) !c.JSValue {
    try putKey(s, data.values.resources, offset, resource);
    return c.pi_js_undefined();
}
fn stackFull(s: *Scope, data: *State, offset: c.JSValue) !c.JSValue {
    const twice = try s.binary(2, offset, c.JS_NewInt32(s.engine.context, 2));
    const stack = try s.get(data.values.binding, "async_ids_stack");
    const length = try s.get(stack, "length");
    return a.duplicate(s.engine, try s.binary(7, twice, length));
}
fn saveStackSlot(s: *Scope, data: *State, offset: c.JSValue, trigger: bool) !c.JSValue {
    // Resolve the live left-hand stack before evaluating the index and RHS.
    const stack = try s.get(data.values.binding, "async_ids_stack");
    const twice = try s.binary(2, offset, c.JS_NewInt32(s.engine.context, 2));
    const index = if (trigger) try s.binary(0, twice, c.JS_NewInt32(s.engine.context, 1)) else twice;
    const value = try uidField(s, data, if (trigger) .trigger else .execution);
    try putKey(s, stack, index, value);
    return c.pi_js_undefined();
}
fn incrementStackLength(s: *Scope, data: *State) !c.JSValue {
    const previous = try readHookField(s, data, .stack_length);
    try s.pending();
    const updated = try s.checked(c.JS_PiIncrement(s.engine.context, previous));
    try putKey(s, data.values.fields,
        c.JS_NewUint32(s.engine.context, @intFromEnum(callbacks.Field.stack_length)), updated);
    return c.pi_js_undefined();
}
fn assignUid(s: *Scope, data: *State, index: callbacks.Uid, value: c.JSValue) !c.JSValue {
    try putUid(s, data, index, value);
    return c.pi_js_undefined();
}
fn pushBody(s: *Scope, holder: c.JSValue, async_id: c.JSValue, trigger_id: c.JSValue, resource: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    const offset = try readHookField(s, data, .stack_length);
    _ = try a.expression(s.engine, resourceAssignment, .{ data, offset, resource });
    if (try a.condition(s.engine, stackFull, .{ data, offset }))
        return a.duplicate(s.engine, try s.call(data.values.push_native, c.pi_js_undefined(), &.{ async_id, trigger_id }));
    _ = try a.expression(s.engine, saveStackSlot, .{ data, offset, false });
    _ = try a.expression(s.engine, saveStackSlot, .{ data, offset, true });
    _ = try a.expression(s.engine, incrementStackLength, .{data});
    _ = try a.expression(s.engine, assignUid, .{ data, callbacks.Uid.execution, async_id });
    _ = try a.expression(s.engine, assignUid, .{ data, callbacks.Uid.trigger, trigger_id });
    return c.pi_js_undefined();
}

fn popAsyncContext(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, popBody, .{ roots[0], a.arg(args, 0) });
}
fn idsDiffer(s: *Scope, data: *State, async_id: c.JSValue) !c.JSValue {
    return a.boolean(s, !s.equal(try uidField(s, data, .execution), async_id));
}
fn restoreUid(s: *Scope, data: *State, offset: c.JSValue, trigger: bool) !c.JSValue {
    const stack = try s.get(data.values.binding, "async_ids_stack");
    const twice = try s.binary(2, c.JS_NewInt32(s.engine.context, 2), offset);
    const index = if (trigger) try s.binary(0, twice, c.JS_NewInt32(s.engine.context, 1)) else twice;
    const value = try s.getKey(stack, index);
    try putUid(s, data, if (trigger) .trigger else .execution, value);
    return c.pi_js_undefined();
}
fn popResources(s: *Scope, data: *State) !c.JSValue {
    const function_value = try s.get(data.values.resources, "pop");
    _ = try s.call(function_value, data.values.resources, &.{});
    return c.pi_js_undefined();
}
fn assignStackLength(s: *Scope, data: *State, offset: c.JSValue) !c.JSValue {
    try putKey(s, data.values.fields,
        c.JS_NewUint32(s.engine.context, @intFromEnum(callbacks.Field.stack_length)), offset);
    return c.pi_js_undefined();
}
fn popBody(s: *Scope, holder: c.JSValue, async_id: c.JSValue) !c.JSValue {
    const data = try capture(s, holder);
    const stack_length = try readHookField(s, data, .stack_length);
    if (s.equal(stack_length, c.JS_NewInt32(s.engine.context, 0))) return a.boolean(s, false);
    if (try a.condition(s.engine, hasHooksBody, .{ data, callbacks.Field.check }) and
        try a.condition(s.engine, idsDiffer, .{ data, async_id }))
        return a.duplicate(s.engine, try s.call(data.values.pop_native, c.pi_js_undefined(), &.{async_id}));
    const offset = try s.binary(1, stack_length, c.JS_NewInt32(s.engine.context, 1));
    _ = try a.expression(s.engine, restoreUid, .{ data, offset, false });
    _ = try a.expression(s.engine, restoreUid, .{ data, offset, true });
    // This is the original JS order, not Environment's native-pop order.
    // Pop's callee, result and completion retire before committing stackLength.
    _ = try a.expression(s.engine, popResources, .{data});
    _ = try a.expression(s.engine, assignStackLength, .{ data, offset });
    return a.duplicate(s.engine, try s.binary(6, offset, c.JS_NewInt32(s.engine.context, 0)));
}
