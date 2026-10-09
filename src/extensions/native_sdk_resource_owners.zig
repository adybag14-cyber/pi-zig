//! An actual ResourceLoader's native scope owns its private invocation broker.
//! Main membership and JSON context cannot create this scope or SDK admission.
const std = @import("std");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const group_mod = @import("native_group.zig");
const bindings = @import("native_bindings.zig");
const sdk = @import("native_sdk.zig");
const vm = @import("native_values.zig");
pub const Scope = struct {
    engine: *Engine,
    group: *group_mod.Group,
    renderers: ?*@import("native_renderers.zig").Manager,
    broker: bindings.Bindings.InvocationBroker = .{},
    provider_clock: u64 = 0,
    references: usize = 1,
    retired: bool = false,
    next_retired: ?*Scope = null,
    pub fn retain(self: *Scope) *Scope {
        self.references += 1;
        return self;
    }
    pub fn release(self: *Scope) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references == 0) {
            self.closeRenderers();
            self.engine.gpa.destroy(self);
        }
    }
    pub fn closeRenderers(self: *Scope) void {
        const renderer = self.renderers orelse return;
        self.renderers = null;
        renderer.deinit();
    }
};
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const engine: *Engine = @ptrCast(@alignCast(c.JS_GetRuntimeOpaque(runtime)));
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_resource_scope_class) orelse return));
    if (!scope.retired and engine.native_sdk_extension_group == @as(?*anyopaque, @ptrCast(scope.group)) and !scope.group.deinitializing) {
        scope.retired = true;
        // A class finalizer must not invoke guest component disposal. Retire
        // API tokens now; the owner VM drains native registrations later.
        for (scope.group.entries.items) |entry| if (entry.sdk_scope == scope) entry.binding.retireOwnerToken();
        _ = scope.retain();
        scope.next_retired = if (engine.native_sdk_resource_retire_pending) |raw| @ptrCast(@alignCast(raw)) else null;
        engine.native_sdk_resource_retire_pending = scope;
    }
    scope.release();
}
pub fn create(group: *group_mod.Group) !c.JSValue {
    const engine = group.engine;
    engine.native_sdk_resource_owner_pump = pump;
    engine.native_sdk_resource_owner_deinit = deinit;
    if (engine.native_sdk_resource_scope_class == 0) {
        var id: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &id);
        const definition: c.JSClassDef = .{ .class_name = "Private SDK resource owner", .finalizer = finalizer };
        if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
        engine.native_sdk_resource_scope_class = id;
    }
    const scope = try engine.gpa.create(Scope);
    errdefer engine.gpa.destroy(scope);
    const renderers = try @import("native_renderers.zig").Manager.init(engine);
    errdefer renderers.deinit();
    scope.* = .{ .engine = engine, .group = group, .renderers = renderers };
    const result = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_sdk_resource_scope_class));
    errdefer engine.freeValue(result);
    try group.sdk_scopes.ensureUnusedCapacity(engine.gpa, 1);
    _ = c.JS_SetOpaque(result, scope);
    group.sdk_scopes.appendAssumeCapacity(scope.retain());
    return result;
}
pub fn fromValue(group: *group_mod.Group, value: c.JSValue) !*Scope {
    if (group.engine.native_sdk_resource_scope_class == 0) return error.InvalidSDKResourceOwner;
    const scope: *Scope = @ptrCast(@alignCast(c.JS_GetOpaque(value, group.engine.native_sdk_resource_scope_class) orelse return error.InvalidSDKResourceOwner));
    if (scope.engine != group.engine or scope.group != group or scope.retired or group.deinitializing) return error.InvalidSDKResourceOwner;
    return scope;
}
pub fn pump(engine: *Engine) !bool {
    var worked = false;
    while (engine.native_sdk_resource_retire_pending) |raw| {
        const scope: *Scope = @ptrCast(@alignCast(raw));
        engine.native_sdk_resource_retire_pending = scope.next_retired;
        scope.next_retired = null;
        defer scope.release();
        if (engine.native_sdk_extension_group == @as(?*anyopaque, @ptrCast(scope.group)) and !scope.group.deinitializing) {
            while (true) {
                var found: ?u64 = null;
                for (scope.group.entries.items) |entry| if (entry.sdk_scope == scope) {
                    found = entry.id;
                    break;
                };
                try scope.group.remove(found orelse break);
            }
            for (scope.group.sdk_scopes.items, 0..) |candidate, index| if (candidate == scope) {
                _ = scope.group.sdk_scopes.orderedRemove(index);
                scope.release();
                break;
            };
        }
        worked = true;
    }
    return worked;
}
pub fn deinit(engine: *Engine) void {
    engine.native_sdk_resource_owner_pump = null;
    engine.native_sdk_resource_owner_deinit = null;
    while (engine.native_sdk_resource_retire_pending) |raw| {
        const scope: *Scope = @ptrCast(@alignCast(raw));
        engine.native_sdk_resource_retire_pending = scope.next_retired;
        scope.release();
    }
}
pub fn uninitialized(engine: *Engine) !c.JSValue {
    const message = try engine.checked(c.JS_NewString(engine.context, "Extension runtime not initialized. Action methods cannot be called during extension loading."));
    defer engine.freeValue(message);
    const reason = try @import("native_js_values.zig").builtin(engine, "Error", &.{message});
    return engine.checked(c.JS_Throw(engine.context, reason));
}
fn sessionScope(owner: *sdk.State) !?*Scope {
    const engine = owner.engine;
    const resource = try vm.get(engine, owner.data, "resourceLoader");
    defer engine.freeValue(resource);
    const raw = c.JS_GetOpaque(resource, engine.native_sdk_class) orelse return null;
    const loader: *sdk.State = @ptrCast(@alignCast(raw));
    if (loader.kind != .resource_loader) return null;
    const value = try vm.get(engine, loader.data, "_sdkExtensionOwnerScope");
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return null;
    if (engine.native_sdk_resource_scope_class == 0) return error.InvalidSDKResourceOwner;
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_sdk_resource_scope_class) orelse return error.InvalidSDKResourceOwner));
}
pub fn sessionScopeRetired(owner: *sdk.State) !bool {
    const scope = (try sessionScope(owner)) orelse return false;
    return scope.retired or owner.engine.native_sdk_extension_group != @as(?*anyopaque, @ptrCast(scope.group));
}
pub fn assertSessionScope(owner: *sdk.State, group: *group_mod.Group) !void {
    const scope = (try sessionScope(owner)) orelse return;
    if (scope.retired or scope.group != group or scope.engine != group.engine) return error.InvalidSDKResourceOwner;
}
/// Root the exact session, registry and manager before observing private data.
pub const Caller = struct {
    engine: *Engine,
    session: c.JSValue,
    registry: c.JSValue,
    manager: c.JSValue,
    owner: *sdk.State,
    pub fn deinit(self: *Caller) void {
        self.engine.freeValue(self.session);
        self.engine.freeValue(self.registry);
        self.engine.freeValue(self.manager);
    }
    pub fn owns(self: *Caller, id: u64) !bool {
        const resource = try vm.get(self.engine, self.owner.data, "resourceLoader");
        defer self.engine.freeValue(resource);
        const raw = c.JS_GetOpaque(resource, self.engine.native_sdk_class) orelse return false;
        const loader: *sdk.State = @ptrCast(@alignCast(raw));
        if (loader.kind != .resource_loader) return false;
        const ids = try vm.get(self.engine, loader.data, "extensionOwnerIds");
        defer self.engine.freeValue(ids);
        if (!c.JS_IsArray(ids)) return false;
        for (0..try vm.length(self.engine, ids)) |index| {
            const value = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, ids, @intCast(index)));
            defer self.engine.freeValue(value);
            var integer: i64 = 0;
            if (c.JS_ToInt64(self.engine.context, &integer, value) < 0) return error.JavaScriptException;
            if (integer > 0 and @as(u64, @intCast(integer)) == id) return true;
        }
        return false;
    }
};
pub fn retainCaller(caller: *bindings.Bindings) !Caller {
    const engine = caller.engine;
    const scope = caller.sdk_context orelse return error.NativeSDKContextUnavailable;
    var retained: Caller = .{ .engine = engine, .session = c.JS_DupValue(engine.context, scope.session), .registry = c.JS_DupValue(engine.context, scope.registry), .manager = c.JS_DupValue(engine.context, scope.manager), .owner = undefined };
    errdefer retained.deinit();
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    if (try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    retained.owner = try sdk.state(engine, retained.session);
    try assertSessionScope(retained.owner, group);
    const actual = try sdk.sessionModelLease(retained.owner);
    if (actual.runtime_id != scope.lease.runtime_id or actual.generation != scope.lease.generation) return error.InvalidNativeSDKModelLease;
    const registry = try vm.get(engine, retained.owner.data, "modelRegistry");
    defer engine.freeValue(registry);
    const manager = try vm.get(engine, retained.owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const lease = try sdk.modelRegistryLease(engine, retained.registry);
    if (!c.JS_IsStrictEqual(engine.context, registry, retained.registry) or !c.JS_IsStrictEqual(engine.context, manager, retained.manager) or lease.runtime_id != actual.runtime_id) return error.InvalidNativeSDKContext;
    return retained;
}
