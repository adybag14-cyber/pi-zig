//! Private runtime-to-real-resource-owner association. Pristine WeakRefs avoid
//! adding fields to Source loader/runtime objects or keeping old incarnations alive.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const owners = @import("native_sdk_resource_owners.zig");
const Group = @import("native_group.zig").Group;
const c = em.c;
const Record = struct { runtime_ref: c.JSValue, scope_ref: c.JSValue };
const Registry = struct { engine: *em.Engine, records: std.ArrayList(Record) = .empty, seeded: bool = false };
fn groupFor(engine: *em.Engine) !*Group {
    return @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.ActualNativeResourceGroupRequired));
}
fn weak(engine: *em.Engine, target: c.JSValue) !c.JSValue {
    const constructor = engine.native_weak_ref_constructor orelse return error.NativeSDKWeakIntrinsicUnavailable;
    var args = [_]c.JSValue{target};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}
fn deref(engine: *em.Engine, reference: c.JSValue) !c.JSValue {
    return js.call(engine, engine.native_weak_ref_deref orelse return error.NativeSDKWeakIntrinsicUnavailable, reference, &.{});
}
fn registry(engine: *em.Engine) !*Registry {
    if (engine.native_sdk_resource_runtime_owners) |raw| return @ptrCast(@alignCast(raw));
    const value = try engine.gpa.create(Registry);
    value.* = .{ .engine = engine };
    engine.native_sdk_resource_runtime_owners = value;
    engine.native_sdk_resource_runtime_owners_deinit = deinit;
    return value;
}
fn remove(value: *Registry, index: usize) void {
    const record = value.records.orderedRemove(index);
    value.engine.freeValue(record.runtime_ref);
    value.engine.freeValue(record.scope_ref);
}
fn lookup(value: *Registry, runtime: c.JSValue) !?c.JSValue {
    const engine = value.engine;
    var index: usize = 0;
    while (index < value.records.items.len) {
        const record = value.records.items[index];
        const target = try deref(engine, record.runtime_ref);
        defer engine.freeValue(target);
        const private_scope = try deref(engine, record.scope_ref);
        defer engine.freeValue(private_scope);
        if (c.JS_IsUndefined(target) or c.JS_IsUndefined(private_scope)) {
            remove(value, index);
            continue;
        }
        if (c.JS_IsStrictEqual(engine.context, target, runtime)) return c.JS_DupValue(engine.context, private_scope);
        index += 1;
    }
    return null;
}
pub fn associate(engine: *em.Engine, runtime: c.JSValue, private_scope: c.JSValue) !void {
    if (!c.JS_IsObject(runtime)) return error.ActualNativeResourceRuntimeRequired;
    _ = try owners.fromValue(try groupFor(engine), private_scope);
    const value = try registry(engine);
    if (try lookup(value, runtime)) |existing| {
        defer engine.freeValue(existing);
        if (!c.JS_IsStrictEqual(engine.context, existing, private_scope)) return error.NativeResourceRuntimeOwnerMismatch;
        return;
    }
    const runtime_ref = try weak(engine, runtime);
    errdefer engine.freeValue(runtime_ref);
    const scope_ref = try weak(engine, private_scope);
    errdefer engine.freeValue(scope_ref);
    try value.records.append(engine.gpa, .{ .runtime_ref = runtime_ref, .scope_ref = scope_ref });
}
fn activate(engine: *em.Engine) !void {
    const group = try groupFor(engine);
    const state = try registry(engine);
    if (state.seeded) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    for (group.sdk_scopes.items) |private| {
        if (private.retired) continue;
        const value = private.owner_value orelse continue;
        const runtime = try scope.get(value, "_extensionRuntime");
        if (c.JS_IsObject(runtime)) try associate(engine, runtime, value);
    }
    state.seeded = true;
}
/// The actual loaded runtime receives a genuine Group scope. Existing legacy
/// runtime creation is unchanged; this entry point belongs to the new class.
pub fn create(engine: *em.Engine) !c.JSValue {
    try activate(engine);
    const private_scope = try owners.create(try groupFor(engine));
    defer engine.freeValue(private_scope);
    const runtime = try @import("native_sdk_extension_runtime.zig").create(engine, private_scope);
    errdefer engine.freeValue(runtime);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(private_scope, "_extensionRuntime", runtime);
    try scope.put(private_scope, "_extensionOwnerIds", try scope.array());
    try scope.put(private_scope, "_extensionRows", try scope.array());
    try associate(engine, runtime, private_scope);
    return runtime;
}
pub fn scopeFor(engine: *em.Engine, runtime: c.JSValue) !c.JSValue {
    try activate(engine);
    if (try lookup(try registry(engine), runtime)) |value| {
        errdefer engine.freeValue(value);
        _ = try owners.fromValue(try groupFor(engine), value);
        return value;
    }
    return error.ActualNativeResourceRuntimeOwnerRequired;
}
fn deinit(engine: *em.Engine) void {
    const raw = engine.native_sdk_resource_runtime_owners orelse return;
    engine.native_sdk_resource_runtime_owners = null;
    engine.native_sdk_resource_runtime_owners_deinit = null;
    const value: *Registry = @ptrCast(@alignCast(raw));
    for (value.records.items) |record| {
        engine.freeValue(record.runtime_ref);
        engine.freeValue(record.scope_ref);
    }
    value.records.deinit(engine.gpa);
    engine.gpa.destroy(value);
}
