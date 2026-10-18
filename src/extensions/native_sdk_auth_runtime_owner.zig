//! Genuine Auth-only SDK owner over the actual child-process frontend graph.
//! Source-only composition prerequisite: the separately reviewed FS frontend,
//! canonical Stream/TTY/Errno and data-safe C producers must first be intaken.
//! No Completed graph, child-process stub, host Node bridge or lease is made.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const guards = @import("native_agent_af_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const completion = @import("native_sdk_owned_completion.zig");
const child = @import("native_child_process_sdk_transport.zig");
const streams = @import("native_process_streams.zig");
const runtime = @import("native_sdk_runtime_imports.zig");
const js = @import("native_js_values.zig");

// Normalize each actual operation BEFORE appending its owned result. The
// generic Scope get/call helpers append via raw Scope.own and can retire an
// incoming sole root before an allocator failure becomes a trusted event.
const Ops = struct {
    scope: *Scope,
    fn adopt(self: Ops, generation: u64, result: anyerror!c.JSValue) !c.JSValue {
        const engine = self.scope.engine;
        const value = try guards.guard(engine, generation, result);
        const checked = try guards.guard(engine, generation, engine.checked(value));
        return completion.ownRoot(self.scope, checked);
    }
    fn own(self: Ops, value: c.JSValue) !c.JSValue {
        return completion.ownRoot(self.scope, value);
    }
    fn get(self: Ops, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
        const generation = self.scope.engine.native_allocation_generation;
        return self.adopt(generation, js.get(self.scope.engine, receiver, name));
    }
    fn globalObject(self: Ops) !c.JSValue {
        const generation = self.scope.engine.native_allocation_generation;
        return self.adopt(generation, self.scope.engine.checked(c.JS_GetGlobalObject(self.scope.engine.context)));
    }
    fn call(self: Ops, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
        const generation = self.scope.engine.native_allocation_generation;
        return self.adopt(generation, js.call(self.scope.engine, function, receiver, args));
    }
    fn invoke(self: Ops, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.call(try self.get(receiver, name), receiver, args);
    }
};

pub const Inputs = struct {
    /// Built by the actual canonical Node/Stream/TTY frontend owner. Its
    /// environment, providers and bridge context must outlive the Engine.
    frontend: child.Inputs,
    /// Real physical config.ts or packaged config.js URL, with genuine package
    /// metadata. The caller pins the actual authority; no filename is invented.
    config_module_url: c.JSValue,
};
/// Move-only native owner: do not copy it or retire its roots twice. The lease
/// is a borrowed live capability, not ownership of the bridge's host context.
pub const Owner = struct {
    engine: *em.Engine,
    lease: streams.Lease,
    frontend: ?child.FrontendExports,
    runtime_imports: c.JSValue,
    live: bool = true,

    fn check(self: *Owner) !void {
        if (!self.live) return error.ActualSdkAuthOwnerRetired;
        try self.engine.checkNativeEntry();
        try streams.assertLease(self.engine, self.lease);
    }
    /// Owned genuine createAuth export carrier, authenticated in the same
    /// Engine's pi-native:actual-sdk-auth-storage-owner module.
    pub fn authStorage(self: *Owner) !c.JSValue {
        return valueEntry(self, false);
    }
    /// Actual Source AuthStorage.inMemory(), without a File backend substitute
    /// or fabricated resolver. Its genuine module dependencies already exist.
    pub fn inMemory(self: *Owner) !c.JSValue {
        return valueEntry(self, true);
    }
    /// Consumes this native owner once. Module caches can still retain actual
    /// JS exports, so the real frontend bridge/environment must outlive Engine.
    /// This retires JS roots only; it does not unbind streams or control a child.
    pub fn deinit(self: *Owner) !void {
        if (!self.live) return error.ActualSdkAuthOwnerAlreadyRetired;
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        var selected = completion.Completion.initVoid(self.engine, {});
        self.retireInto(&selected);
        return selected.finishVoid();
    }
    /// SDK-native composition hook: consumes a live owner into the caller's
    /// already-recorded outcome. No guest operation or process control runs.
    pub fn retireInto(self: *Owner, selected: *completion.Completion) void {
        std.debug.assert(self.live);
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        self.live = false;
        const imports = self.runtime_imports;
        self.runtime_imports = c.pi_js_undefined();
        selected.release(imports);
        if (self.frontend) |frontend| {
            self.frontend = null;
            retireFrontend(selected, frontend);
        }
    }
};
fn valueEntry(self: *Owner, in_memory: bool) !c.JSValue {
    const engine = self.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try self.check();
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const value = valueScoped(self, in_memory) catch |err| {
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    };
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn valueScoped(self: *Owner, in_memory: bool) !c.JSValue {
    var scope: Scope = .{ .engine = self.engine };
    return completion.finishValue(&scope, if (in_memory) inMemoryScoped(self, &scope) else authStorageScoped(self, &scope));
}
fn authStorageScoped(self: *Owner, scope: *Scope) !c.JSValue {
    const o: Ops = .{ .scope = scope };
    const exports = try o.get(self.runtime_imports, "authStorage");
    const actual_owner = self.engine.native_module_values.get("pi-native:actual-sdk-auth-storage-owner") orelse return error.RequiredGenuineSdkAuthModuleOwner;
    if (!scope.equal(exports, try o.get(actual_owner, "exports"))) return error.ActualSdkAuthNamespaceChanged;
    return c.JS_DupValue(self.engine.context, exports);
}
fn inMemoryScoped(self: *Owner, scope: *Scope) !c.JSValue {
    const o: Ops = .{ .scope = scope };
    const exports = try o.own(try authStorageScoped(self, scope));
    const constructor = try o.get(exports, "AuthStorage");
    if (!c.JS_IsConstructor(self.engine.context, constructor)) return error.RequiredGenuineAuthStorageConstructor;
    return c.JS_DupValue(self.engine.context, try o.invoke(constructor, "inMemory", &.{}));
}

/// Owns creation of the actual frontend instead of accepting arbitrary eight
/// Completed values. No subprocess is launched by this construction entry.
pub fn create(engine: *em.Engine, inputs: Inputs) !Owner {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    const lease = inputs.frontend.stdio_source orelse return error.RequiredActualSdkFrontendLease;
    try streams.assertLease(engine, lease);
    var invocation: em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var result = createOwned(engine, inputs, lease) catch |err| {
        const escaped = engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
        if (escaped) |unexpected| {
            engine.freeValue(unexpected);
            return error.ActualSdkAuthCreationFailureDidNotEscape;
        } else |actual| return actual;
    };
    const terminal = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    if (c.JS_IsException(terminal) or c.JS_HasException(engine.context)) {
        // Keep the ACTUAL pending terminal event pending for initVoid, rather
        // than converting it into a diagnostic before the returned bundle dies.
        var failed = completion.Completion.initVoid(engine, error.JavaScriptException);
        result.retireInto(&failed);
        try failed.finishVoid();
        unreachable;
    }
    return result;
}
fn createOwned(engine: *em.Engine, inputs: Inputs, lease: streams.Lease) !Owner {
    const frontend = try child.createForFrontend(engine, inputs.frontend);
    var scope: Scope = .{ .engine = engine };
    var selected = completion.Completion.initValue(engine, createRuntime(&scope, inputs, frontend));
    selected.releaseScope(&scope);
    const imports = selected.finishValue() catch |err| {
        // Preserve this actual failure before retiring every returned frontend
        // root; calling raw FrontendExports.deinit here would lose ordinary A.
        var failed = completion.Completion.initVoid(engine, err);
        retireFrontend(&failed, frontend);
        try failed.finishVoid();
        unreachable;
    };
    return .{ .engine = engine, .lease = lease, .frontend = frontend, .runtime_imports = imports };
}
fn installed(engine: *em.Engine, name: []const u8) !c.JSValue {
    return engine.native_module_values.get(name) orelse error.RequiredInstalledGenuineSdkPlatformNamespace;
}
fn createRuntime(scope: *Scope, inputs: Inputs, frontend: child.FrontendExports) !c.JSValue {
    const engine = scope.engine;
    const o: Ops = .{ .scope = scope };
    try engine.checkNativeEntry();
    const global = try o.globalObject();
    const process = try o.get(global, "process");
    if (!scope.equal(process, inputs.frontend.process)) return error.ActualSdkFrontendProcessChanged;
    if (!c.JS_IsString(inputs.config_module_url)) return error.RequiredPhysicalSdkConfigModuleUrl;
    const url = try installed(engine, "node:url");
    const physical = try o.call(try o.get(url, "fileURLToPath"), c.pi_js_undefined(), &.{inputs.config_module_url});
    const filesystem = try installed(engine, "node:fs");
    if (!scope.truthy(try o.invoke(filesystem, "existsSync", &.{physical}))) return error.ActualSdkConfigModuleFileAbsent;
    const stat = try o.invoke(filesystem, "statSync", &.{physical});
    if (!scope.truthy(try o.invoke(stat, "isFile", &.{}))) return error.ActualSdkConfigModuleMustBeFile;
    // This is a separately owned multi-operation builder, not a single guest
    // producer boundary. Do not reclassify its diagnostic against body entry:
    // an internally historical successful DATA value must stay ordinary.
    const imports_result = try runtime.create(engine, .{
        .process = process,
        .os = try installed(engine, "node:os"),
        .url = url,
        .child_process = frontend.transport.child.node,
        .config_module_url = inputs.config_module_url,
        .user_agent_runtime = .native_zig,
    });
    const imports = try o.own(try engine.checked(imports_result));
    const auth = try o.get(imports, "authStorage");
    const constructor = try o.get(auth, "AuthStorage");
    if (!c.JS_IsConstructor(engine.context, constructor)) return error.RequiredGenuineAuthStorageConstructor;
    const prototype = try o.get(constructor, "prototype");
    inline for (.{ "reloadFromStorageAsync", "readLatestData", "read", "modify", "delete", "list" }) |name| {
        const method = try o.get(prototype, name);
        if (!c.JS_IsAsyncFunction(method) or c.JS_IsConstructor(engine.context, method)) return error.RequiredGenuineSdkAuthAsyncOwner;
    }
    return c.JS_DupValue(engine.context, imports);
}
fn retireFrontend(selected: *completion.Completion, frontend: child.FrontendExports) void {
    // Match the actual frozen FS FrontendExports/Exports/Bundle deinit ordering,
    // consuming each owned JS reference through the same SDK completion owner.
    inline for (std.meta.fields(@TypeOf(frontend.process_imports))) |field| selected.release(@field(frontend.process_imports, field.name));
    inline for (std.meta.fields(@TypeOf(frontend.output_guard))) |field| selected.release(@field(frontend.output_guard, field.name));
    selected.release(frontend.transport.utilities);
    inline for (.{ "node", "cross_spawn", "net" }) |name| selected.release(@field(frontend.transport.child, name));
}
