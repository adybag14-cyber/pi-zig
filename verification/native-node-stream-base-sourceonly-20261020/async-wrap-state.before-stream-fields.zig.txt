//! Native AsyncWrap state for the actual Node24.13 request/handle templates.
//! The shared callback Environment supplies IDs, provider strings, context data,
//! init/destroy hooks and realm shutdown. Template creation is a separate owner.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const callable = @import("native_node_module_callable.zig");
const c = a.c;
pub const Engine = a.v.em.Engine;
pub const LocalScope = a.Scope;
pub const Environment = callbacks.Environment;

pub const Kind = enum { async_wrap, fsreqpromise, filehandleclosereq, filehandle };
pub const Provider = struct {
    pub const none: u32 = 0;
    pub const filehandle: u32 = 4;
    pub const filehandleclosereq: u32 = 5;
    pub const fsreqpromise: u32 = 9;
};
/// Native CHECK sites belong to the shared Environment's actual terminal owner.
pub const Check = callbacks.Check;

/// The functions are the compiled derived C++ destructor/mark equivalents.
/// A concrete FSReq/handle embeds State and supplies its own real fields.
/// retire must release all derived fields before State releases its frame.
pub const Derived = struct {
    mark: *const fn (?*c.JSRuntime, *State, ?*const c.JS_MarkFunc) void,
    retire: *const fn (*State, *LocalScope) anyerror!void,
    destroy: *const fn (*State) void,
};

/// Every actual BaseObject, including fs::BindingData, enters the same FIFO.
/// The callback is the compiled native DeleteMe implementation, never guest JS.
pub const BaseEntry = struct {
    raw: *anyopaque,
    delete_me: *const fn (*anyopaque) anyerror!void,
    previous: ?*BaseEntry = null,
    next: ?*BaseEntry = null,
    linked: bool = false,
};

/// Realm's selected BindingDataStore keeps a native weak pointer whose
/// metadata can outlive the BaseObject. It never roots its JS wrapper.
pub const WeakBindingSlot = struct {
    raw: *anyopaque,
    get: *const fn (*anyopaque) ?*anyopaque,
    release: *const fn (*anyopaque) void,
};

/// Independently retained native owner. One realm cleanup registration covers
/// the real intrusive list, and every attached State retains this allocation.
/// Clearing a JS wrapper does not depend on the order of other GC finalizers.
pub const Registry = struct {
    environment: *Environment,
    references: usize = 1,
    class_ids: [4]c.JSClassID = .{ 0, 0, 0, 0 },
    head: ?*BaseEntry = null,
    tail: ?*BaseEntry = null,
    fs_binding_data: ?WeakBindingSlot = null,
    modules_binding_data: ?WeakBindingSlot = null,
    cleanup: callbacks.RealmCleanup,

    pub fn create(engine: *Engine, environment: *Environment) !*Registry {
        if ((try environment.requireEngine()) != engine) return error.ActualAsyncWrapEnvironmentMismatch;
        var scope = LocalScope.init(engine);
        var result: ?*Registry = null;
        const ignored = scope.finish(createBody(&scope, environment, &result)) catch |err| {
            if (result) |created| created.release();
            return err;
        };
        engine.freeValue(ignored);
        return result.?;
    }
    fn createBody(s: *LocalScope, environment: *Environment, output: *?*Registry) !c.JSValue {
        try s.pending();
        const self = try environment.allocator().create(Registry);
        self.* = .{
            .environment = environment.retain(),
            .cleanup = .{ .raw = self, .run = cleanupRealm },
        };
        errdefer {
            environment.allocator().destroy(self);
            environment.release();
        }
        inline for (.{ "AsyncWrap", "FSReqPromise", "FileHandleCloseReq", "FileHandle" }, 0..) |name, index| {
            const generation = try s.beforeAllocation();
            if (c.JS_NewClassID(s.engine.runtime, &self.class_ids[index]) == 0)
                return error.OutOfMemory;
            const definition: c.JSClassDef = .{
                .class_name = name, .finalizer = wrapperFinalizer, .gc_mark = wrapperMark,
            };
            const status = c.JS_NewClass(s.engine.runtime, self.class_ids[index], &definition);
            try s.boundary.checkPendingSince(generation);
            if (status < 0) return error.OutOfMemory;
        }
        try environment.registerRealmCleanup(&self.cleanup);
        output.* = self;
        return c.pi_js_undefined();
    }
    pub fn retain(self: *Registry) *Registry {
        std.debug.assert(self.references != 0);
        self.references += 1;
        return self;
    }
    pub fn release(self: *Registry) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references != 0) return;
        std.debug.assert(self.head == null and self.tail == null);
        const environment = self.environment;
        if (self.cleanup.environment != null) environment.unregisterRealmCleanup(&self.cleanup);
        if (self.fs_binding_data) |slot| {
            self.fs_binding_data = null;
            slot.release(slot.raw);
        }
        if (self.modules_binding_data) |slot| {
            self.modules_binding_data = null;
            slot.release(slot.raw);
        }
        environment.allocator().destroy(self);
        environment.release();
    }
    pub fn check(self: *Registry, site: Check) anyerror {
        return self.environment.operations.native_check_failure(self.environment, site);
    }
    pub fn classId(self: *const Registry, kind: Kind) c.JSClassID {
        return self.class_ids[@intFromEnum(kind)];
    }
    pub fn hasTemplateBrand(self: *const Registry, value: c.JSValue) bool {
        const id = c.JS_GetClassID(value);
        for (self.class_ids) |known| if (id == known) return true;
        return false;
    }
    /// Brand survives clearing the native pointer, as with a retained V8
    /// template instance after its BaseObject has been deleted.
    pub fn unwrap(self: *const Registry, value: c.JSValue) ?*State {
        if (!self.hasTemplateBrand(value)) return null;
        const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return null;
        const state: *State = @ptrCast(@alignCast(raw));
        return if (state.registry == self) state else null;
    }
    /// Caller has already selected the genuine template's instance prototype.
    /// This is the actual object allocation, with no constructor-body callback.
    pub fn newInstance(self: *Registry, s: *LocalScope, kind: Kind, prototype: c.JSValue) !c.JSValue {
        if ((try self.environment.requireEngine()) != s.engine) return error.ActualAsyncWrapEnvironmentMismatch;
        const generation = try s.beforeAllocation();
        return s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, prototype, self.classId(kind)), generation);
    }
    pub fn append(self: *Registry, state: *BaseEntry) void {
        std.debug.assert(!state.linked and state.previous == null and state.next == null);
        state.previous = self.tail;
        state.next = null;
        if (self.tail) |last| last.next = state else self.head = state;
        self.tail = state;
        state.linked = true;
    }
    pub fn unlink(self: *Registry, state: *BaseEntry) void {
        if (!state.linked) return;
        if (state.previous) |previous| previous.next = state.next else self.head = state.next;
        if (state.next) |next| next.previous = state.previous else self.tail = state.previous;
        state.previous = null;
        state.next = null;
        state.linked = false;
    }
    fn cleanupRealm(environment: *Environment, raw: ?*anyopaque) !void {
        const self: *Registry = @ptrCast(@alignCast(raw.?));
        std.debug.assert(self.environment == environment and !environment.canCallIntoJs());
        _ = self.retain();
        defer self.release();
        const engine = try environment.requireEngine();
        var scope = LocalScope.init(engine);
        var failure: ?anyerror = null;
        while (self.head) |state| {
            // Realm's cleanup loop PopFront precedes BaseObject::DeleteMe.
            const delete_me = state.delete_me;
            const object = state.raw;
            self.unlink(state);
            delete_me(object) catch |err| {
                scope.boundary.escaping();
                if (failure == null) failure = err;
            };
        }
        const ignored = try scope.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
};

pub const State = struct {
    registry: *Registry,
    wrapper: ?c.JSValue,
    // Native Global<Object> entitlement. It is an external VM root while
    // strong, not a GC-visible self edge of the JS wrapper.
    strong_wrapper: ?c.JSValue = null,
    wants_weak: bool = false,
    native_references: usize = 0,
    detached: bool = false,
    derived: Derived,
    base_entry: BaseEntry,
    retiring: bool = false,
    provider: u32 = Provider.none,
    async_id: f64 = -1,
    trigger_async_id: f64 = -1,
    context_frame: c.JSValue,
    init_hook_ran: bool = false,

    /// BaseObject attaches/tracks the native pointer before either context
    /// capture or the provider's init hook. The caller allocated the actual
    /// derived object and initialized its fields for partial-construction GC.
    pub fn initialize(self: *State, registry: *Registry, wrapper: c.JSValue, derived: Derived, provider: u32, execution_async_id: f64) !void {
        const environment = registry.environment;
        const engine = try environment.requireEngine();
        var scope = LocalScope.init(engine);
        const ignored = try scope.finish(self.initializeBody(&scope, registry, wrapper, derived, provider, execution_async_id));
        engine.freeValue(ignored);
    }
    fn initializeBody(self: *State, s: *LocalScope, registry: *Registry, wrapper: c.JSValue, derived: Derived, provider: u32, execution_async_id: f64) !c.JSValue {
        try s.pending();
        if (!registry.hasTemplateBrand(wrapper))
            return registry.check(.invalid_wrap_brand);
        if (c.JS_GetOpaque(wrapper, c.JS_GetClassID(wrapper)) != null)
            return registry.check(.invalid_wrap_brand);
        self.* = .{
            .registry = registry.retain(), .wrapper = wrapper,
            .strong_wrapper = a.duplicate(s.engine, wrapper), .derived = derived,
            .base_entry = .{ .raw = self, .delete_me = deleteBaseEntry },
            .context_frame = c.pi_js_undefined(),
        };
        _ = c.JS_SetOpaque(wrapper, self);
        registry.append(&self.base_entry);
        const environment = registry.environment;
        self.context_frame = try environment.currentContextFrame();
        if (provider == Provider.none) return registry.check(.invalid_provider);
        self.provider = provider;
        // Constructor AsyncReset has no previous ID and resource == object:
        // neither of its conditional ordinary property Set operations occurs.
        self.async_id = if (execution_async_id == -1) environment.newAsyncId() else execution_async_id;
        self.trigger_async_id = environment.getDefaultTriggerAsyncId();
        const replacement = try environment.currentContextFrame();
        var previous = self.context_frame;
        self.context_frame = replacement;
        s.boundary.release(&previous);
        const provider_string = try environment.providerString(provider);
        var init_failure: ?anyerror = null;
        environment.emitInit(self.async_id, provider_string, self.trigger_async_id, wrapper) catch |err| {
            s.boundary.escaping();
            init_failure = err;
        };
        // AsyncReset is void in the native constructor. Its ordinary rethrow
        // does not skip the following native initialization-state write.
        self.init_hook_ran = true;
        if (init_failure) |err| return err;
        return c.pi_js_undefined();
    }
    /// General AsyncReset retains the native continuation after each ignored
    /// V8 Object::Set. Each genuine Set is a separate completed operation:
    /// its ordinary pending reason survives native ID/frame updates, and a
    /// later failing operation can publish its actual new reason. A current
    /// native fatal remains owned by the enclosing invocation throughout.
    pub fn reset(self: *State, resource: c.JSValue, execution_async_id: f64) !void {
        const engine = try self.registry.environment.requireEngine();
        var scope = LocalScope.init(engine);
        const ignored = try scope.finish(self.resetBody(&scope, resource, execution_async_id));
        engine.freeValue(ignored);
    }
    fn resetBody(self: *State, s: *LocalScope, resource: c.JSValue, execution_async_id: f64) !c.JSValue {
        const env = self.registry.environment;
        if (self.provider == Provider.none) return self.registry.check(.invalid_provider);
        var ignored_set_error: ?anyerror = null;
        if (self.async_id != -1) {
            try env.emitDestroy(self.async_id);
            self.async_id = -1;
            if (self.wrapper) |wrapper| {
                ignoreSet(s.engine, wrapper, try env.resourceSymbol(), wrapper) catch |err| {
                    ignored_set_error = err;
                };
            }
        }
        self.async_id = if (execution_async_id == -1) env.newAsyncId() else execution_async_id;
        self.trigger_async_id = env.getDefaultTriggerAsyncId();
        const wrapper = self.wrapper orelse return self.registry.check(.invalid_wrap_brand);
        if (!c.JS_IsStrictEqual(s.engine.context, wrapper, resource)) {
            ignoreSet(s.engine, wrapper, try env.resourceSymbol(), resource) catch |err| {
                ignored_set_error = err;
            };
        }
        const replacement = try env.currentContextFrame();
        var previous = self.context_frame;
        self.context_frame = replacement;
        s.boundary.release(&previous);
        try env.emitInit(self.async_id, try env.providerString(self.provider), self.trigger_async_id, resource);
        if (ignored_set_error) |err| return err;
        return c.pi_js_undefined();
    }
    /// BaseObject::MakeWeak records the preference, but an actual native
    /// BaseObjectPtr keeps the persistent handle strong until its last release.
    pub fn makeWeak(self: *State) !void {
        self.wants_weak = true;
        if (self.native_references != 0) return;
        const engine = try self.registry.environment.requireEngine();
        var scope = LocalScope.init(engine);
        var previous = self.strong_wrapper orelse return finishEmpty(&scope);
        self.strong_wrapper = null;
        // This may invoke the real weak finalizer. Do not access self afterward.
        scope.boundary.release(&previous);
        try finishEmpty(&scope);
    }
    /// ReqWrap::Dispatch selects this only after actual native admission.
    pub fn clearWeak(self: *State) !void {
        self.wants_weak = false;
        try self.ensureStrong();
    }
    fn ensureStrong(self: *State) !void {
        if (self.strong_wrapper != null) return;
        const engine = try self.registry.environment.requireEngine();
        if (self.wrapper) |wrapper| self.strong_wrapper = a.duplicate(engine, wrapper);
    }
    pub fn retainNative(self: *State) !void {
        const previous = self.native_references;
        self.native_references += 1;
        if (previous == 0) try self.ensureStrong();
    }
    pub fn detach(self: *State) !void {
        if (self.native_references == 0) return self.registry.check(.invalid_wrap_brand);
        self.detached = true;
    }
    /// No access to self follows the last detached-pointer release: it invokes
    /// the actual derived destructor even if JavaScript retains the instance.
    pub fn releaseNative(self: *State) !void {
        if (self.native_references == 0) return self.registry.check(.invalid_wrap_brand);
        self.native_references -= 1;
        if (self.native_references != 0) return;
        if (self.detached) return self.retire(false);
        if (self.wants_weak and self.wrapper != null) return self.makeWeak();
    }
    pub fn deleteMe(self: *State) !void {
        if (self.native_references != 0) return self.detach();
        return self.retire(false);
    }
    pub fn context(self: *const State) callbacks.AsyncContext {
        return .{ .async_id = self.async_id, .trigger_async_id = self.trigger_async_id };
    }
    pub fn object(self: *const State) ?c.JSValue { return self.wrapper; }
    pub fn mark(self: *State, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        self.derived.mark(runtime, self, marker);
        // context_frame_ is an independent native v8::Global. Its retained
        // value is an external collector root, as is strong_wrapper. Marking
        // either as an internal JS edge would collect genuine native cycles.
    }
    /// Normal completion deletes the native request even when its JS instance
    /// is retained. A weak finalizer first clears the persistent wrapper, as
    /// BaseObject's weak callback does before invoking the actual destructor.
    fn deleteBaseEntry(raw: *anyopaque) !void {
        const self: *State = @ptrCast(@alignCast(raw));
        return self.deleteMe();
    }
    pub fn retire(self: *State, from_gc: bool) !void {
        if (self.retiring) return;
        if (self.native_references != 0) return self.registry.check(.invalid_wrap_brand);
        self.retiring = true;
        const registry = self.registry;
        const environment = registry.environment;
        const engine = try environment.requireEngine();
        if (from_gc) {
            std.debug.assert(self.strong_wrapper == null);
            if (self.wrapper) |wrapper| _ = c.JS_SetOpaque(wrapper, null);
            self.wrapper = null;
        }
        var scope = LocalScope.init(engine);
        var failure: ?anyerror = null;
        self.derived.retire(self, &scope) catch |err| {
            scope.boundary.escaping();
            failure = err;
        };
        environment.emitDestroy(self.async_id) catch |err| {
            scope.boundary.escaping();
            if (failure == null) failure = err;
        };
        self.async_id = -1;
        scope.boundary.release(&self.context_frame);
        registry.unlink(&self.base_entry);
        if (self.wrapper) |wrapper| _ = c.JS_SetOpaque(wrapper, null);
        self.wrapper = null;
        if (self.strong_wrapper) |value| {
            self.strong_wrapper = null;
            var persistent = value;
            scope.boundary.release(&persistent);
        }
        self.derived.destroy(self);
        defer registry.release();
        const ignored = try scope.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
};
fn wrapperFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.registry.environment.requireEngine() catch return;
    state.retire(true) catch |err| { _ = callable.failure(engine, err, 0); };
}
fn wrapperMark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    state.mark(runtime, marker);
}

fn ignoreSet(engine: *Engine, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const ignored = try a.expression(engine, setBody, .{ receiver, key, value });
    engine.freeValue(ignored);
}
fn setBody(s: *LocalScope, receiver: c.JSValue, key: c.JSValue, value: c.JSValue) !c.JSValue {
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, receiver,
        a.duplicate(s.engine, key), a.duplicate(s.engine, value), 0);
    try s.pending();
    if (status < 0) return error.MissingActualAsyncWrapSetReason;
    return c.pi_js_undefined();
}

fn finishEmpty(scope: *LocalScope) !void {
    const engine = scope.engine;
    const ignored = try scope.finish(c.pi_js_undefined());
    engine.freeValue(ignored);
}
