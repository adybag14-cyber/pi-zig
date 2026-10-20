//! Actual Node24.13 FSReqPromise<AliasedFloat64Array/BigInt64Array>.
//! The original request instance has one live "promise" property. Its native
//! request owns the genuine AsyncWrap, ReqWrap queue entry and BindingData
//! strong pointer. This file does not publish an internal/fs or fs namespace.
//!
//! Required graph dependencies remain explicit: the actual BindingData owner,
//! Environment request-state integration, and JS_PiNewPendingPromise. The latter
//! is the intrinsic same-Promise allocation with its real INIT hook, without
//! creating an unused pair of resolving functions.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const request_state = @import("native_node_request_state.zig");
const callbacks = @import("native_node_callback_scope.zig");
const binding = @import("native_node_fs_binding_data.zig");
const publication = @import("native_node_fs_private_publication.zig");
const uv = @import("native_node_uv_service.zig").uv;
const c = a.c;
pub const Engine = native.Engine;
pub const BindingData = binding.BindingData;
const Scope = a.Scope;
const Numbers = callbacks.Alias(f64, c.JS_TYPED_ARRAY_FLOAT64);
const BigInts = callbacks.Alias(i64, c.JS_TYPED_ARRAY_BIG_INT64);
const cache_key = "\x00native.node.fs.FSReqPromise.actual.v24.13";

/// The real uv_fs_t storage is allocated with the native ReqWrap, before any
/// AsyncWrap init hook. Admission later uses this same request without a new
/// wrapper allocation. Only the private compiled I/O owner supplies this input.
pub const Physical = struct { service: *uv.PiUvService, kind: c_int };

const Fields = union(enum) {
    empty,
    number: Numbers,
    bigint: BigInts,
    fn create(s: *Scope, count: usize, use_bigint: bool) !Fields {
        return if (use_bigint)
            .{ .bigint = try BigInts.create(s, count) }
        else
            .{ .number = try Numbers.create(s, count) };
    }
    fn release(self: *Fields, s: *Scope) void {
        var old = self.*;
        self.* = .empty;
        switch (old) {
            .empty => {},
            .number => |*values| values.release(s),
            .bigint => |*values| values.release(s),
        }
    }
};
const Factory = struct {
    registry: *native.Registry,
    // The original JS import is the binding target. It is a traced object
    // edge, not a persistent native BaseObjectPtr keeping BindingData alive.
    binding_target: c.JSValue,
};

pub const Request = struct {
    wrap: native.State,
    entry: request_state.Entry,
    binding_data: ?*BindingData = null,
    use_bigint: bool,
    finished: bool = false,
    constructed: bool = false,
    attached: bool = false,
    entry_initialized: bool = false,
    stats_field_array: Fields = .empty,
    statfs_field_array: Fields = .empty,
    native_request: ?*uv.PiUvFsRequest = null,

    /// Called only by the compiled physical request implementation. Its actual
    /// native cancellation ticket is stored in that derived I/O owner.
    cancel_native: request_state.Cancel,

    fn fromWrap(wrap: *native.State) *Request {
        return @alignCast(@fieldParentPtr("wrap", wrap));
    }
    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
        // Both AliasedBuffer Globals and BindingData's native strong pointer
        // are external roots, not JS edges owned by this wrapper graph.
    }
    fn retire(wrap: *native.State, s: *Scope) !void {
        const self = fromWrap(wrap);
        const request_environment = wrap.registry.environment;
        // A failed C++ construction does not invoke the derived destructor.
        if (self.constructed and !self.finished and request_environment.canCallIntoJs())
            return wrap.registry.check(.unfinished_live_fs_request);
        // Actual derived member destruction is reverse declaration order.
        self.statfs_field_array.release(s);
        self.stats_field_array.release(s);
        var failure: ?anyerror = null;
        // FSReqBase's BaseObjectPtr follows its final native buffer member;
        // the selected read/open request has no copied destination buffer.
        if (self.binding_data) |owner| {
            self.binding_data = null;
            owner.releaseNative() catch |err| {
                s.boundary.escaping();
                failure = err;
            };
        }
        // ReqWrapBase is destroyed before the AsyncWrap base and its frame.
        if (self.entry_initialized) {
            self.entry_initialized = false;
            self.entry.deinit();
        }
        if (failure) |err| return err;
    }
    fn destroy(wrap: *native.State) void {
        const allocator = wrap.registry.environment.allocator();
        const self = fromWrap(wrap);
        if (self.native_request) |actual| {
            self.native_request = null;
            uv.pi_uv_fs_request_release(actual);
        }
        allocator.destroy(self);
    }

    fn initialize(self: *Request, s: *Scope, data: *BindingData,
        wrapper: c.JSValue, use_bigint: bool, cancel_native: request_state.Cancel,
        native_request: ?*uv.PiUvFsRequest) !void
    {
        self.* = .{
            .wrap = undefined, .entry = undefined,
            .use_bigint = use_bigint, .cancel_native = cancel_native,
            .native_request = native_request,
        };
        const registry = try templates.registry(s.engine, data.template_owner);
        self.wrap.initialize(registry, wrapper,
            .{ .mark = mark, .retire = retire, .destroy = destroy },
            native.Provider.fsreqpromise, -1) catch |err|
        {
            self.attached = c.JS_GetOpaque(wrapper, registry.classId(.fsreqpromise)) != null;
            s.boundary.escaping();
            // AsyncWrap construction calls void AsyncReset. An ordinary init
            // rethrow does not skip the later native ReqWrap/derived members.
            // The caller's HandleScope retains that completion through the
            // subsequent SetReturnValue and actual Dispatch operations.
            if (!self.attached or !self.wrap.init_hook_ran or
                err != error.JavaScriptException or s.boundary.fatal) return err;
        };
        self.attached = true;
        // ReqWrapBase queues the real native object after AsyncWrap's init.
        try self.entry.initialize(&self.wrap, cancel_native);
        self.entry_initialized = true;
        try self.wrap.makeWeak();
        self.entry.reset();
        // Original FSReqBase initializes its native BindingData strong pointer
        // after ReqWrap construction and before the derived alias allocations.
        try data.retainNative();
        self.binding_data = data;
        self.stats_field_array = try Fields.create(s, 18, use_bigint);
        self.statfs_field_array = try Fields.create(s, 7, use_bigint);
        self.constructed = true;
    }

    pub fn object(self: *Request) !c.JSValue {
        return self.wrap.object() orelse return self.wrap.registry.check(.invalid_wrap_brand);
    }
    pub fn environment(self: *Request) *callbacks.Environment {
        return self.wrap.registry.environment;
    }

    /// GetReqWrap's SetReturnValue is a separate live lookup before Dispatch.
    /// The caller must preserve an ordinary failed lookup while completing the
    /// subsequent native dispatch, because the original void helper returns
    /// without replacing the non-null native FSReqBase pointer.
    pub fn returnPromise(self: *Request) !c.JSValue {
        const engine = try self.environment().requireEngine();
        return a.expression(engine, returnBody, .{self});
    }
    fn returnBody(s: *Scope, self: *Request) !c.JSValue {
        const data = self.binding_data orelse return self.wrap.registry.check(.invalid_wrap_brand);
        const value = try s.getKey(try self.object(), data.promise_string);
        // Resolver::GetPromise is the same native Promise value, not a new
        // wrapper/capability and not the original property value cached earlier.
        return a.duplicate(s.engine, value);
    }
    pub fn resolve(self: *Request, value: c.JSValue) !void {
        return self.settle(value, false);
    }
    pub fn reject(self: *Request, reason: c.JSValue) !void {
        return self.settle(reason, true);
    }
    fn settle(self: *Request, value: c.JSValue, is_reject: bool) !void {
        // This assignment precedes both native scope constructors in Source.
        self.finished = true;
        const engine = try self.environment().requireEngine();
        var handles = Scope.init(engine);
        var callback_scope: callbacks.Scope = undefined;
        callback_scope.initialized = false;
        var failure: ?anyerror = null;
        self.settleBody(&handles, &callback_scope, value, is_reject) catch |err| {
            handles.boundary.escaping();
            failure = err;
        };
        // The InternalCallbackScope destructor runs even after a failed Get,
        // before any of the enclosing HandleScope's local roots are released.
        if (callback_scope.initialized) {
            callback_scope.deinit() catch |err| {
                handles.boundary.escaping();
                if (failure == null) failure = err;
            };
        }
        const ignored = try handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
    fn settleBody(self: *Request, s: *Scope, callback_scope: *callbacks.Scope,
        value: c.JSValue, is_reject: bool) !void
    {
        const environment_value = self.environment();
        const data = self.binding_data orelse return self.wrap.registry.check(.invalid_wrap_brand);
        const wrapper = try self.object();
        try callback_scope.init(environment_value, wrapper, self.wrap.context(), .{}, self.wrap.context_frame);
        const resolver = try s.getKey(wrapper, data.promise_string);
        try s.pending();
        var result = c.JS_PiSettlePromise(s.engine.context, resolver, value, is_reject);
        // Resolver::{Resolve,Reject}.FromJust is a genuine native CHECK on an
        // empty Maybe. It is not an ordinary Promise rejection/guest catch.
        if (c.JS_IsException(result))
            return self.wrap.registry.check(.promise_property_settle);
        s.boundary.release(&result);
        try s.pending();
    }
};

fn factoryOf(engine: *Engine, known_owner: c.JSValue) !*Factory {
    const raw = c.JS_GetOpaque(known_owner, c.JS_GetClassID(known_owner)) orelse
        return error.ActualFSReqPromiseFactoryRequired;
    const self: *Factory = @ptrCast(@alignCast(raw));
    if ((try self.registry.environment.requireEngine()) != engine)
        return error.ActualFSReqPromiseEnvironmentMismatch;
    return self;
}
fn factoryData(engine: *Engine, known_owner: c.JSValue) !*BindingData {
    const self = try factoryOf(engine, known_owner);
    // Realm's actual weak store is authoritative. A retained JS function
    // after realm cleanup never dereferences the deleted native BaseObject.
    const data = binding.get(self.registry) orelse return error.ActualFSReqPromiseBindingDataRequired;
    const target = data.wrapper orelse return error.ActualFSReqPromiseBindingDataRequired;
    if (!c.JS_IsStrictEqual(engine.context, target, self.binding_target))
        return error.ActualFSReqPromiseBindingDataMismatch;
    return data;
}
fn factoryFinalizer(runtime: ?*c.JSRuntime, owner: c.JSValue) callconv(.c) void {
    const self: *Factory = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    _ = c.JS_SetOpaque(owner, null);
    const registry = self.registry;
    const target = self.binding_target;
    self.binding_target = c.pi_js_undefined();
    registry.environment.allocator().destroy(self);
    c.JS_FreeValueRT(runtime, target);
    registry.release();
}
fn factoryMark(runtime: ?*c.JSRuntime, owner: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Factory = @ptrCast(@alignCast(c.JS_GetOpaque(owner, c.JS_GetClassID(owner)) orelse return));
    c.JS_MarkValue(runtime, self.binding_target, marker);
}
fn createFactoryBody(s: *Scope, data: *BindingData) !c.JSValue {
    if ((try data.environment.requireEngine()) != s.engine)
        return error.ActualFSReqPromiseEnvironmentMismatch;
    const registry = try templates.registry(s.engine, data.template_owner);
    const target = data.wrapper orelse return error.ActualFSReqPromiseBindingDataRequired;
    if (binding.get(registry) != data) return error.ActualFSReqPromiseBindingDataMismatch;
    const generation = try s.beforeAllocation();
    var class_id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &class_id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{
        .class_name = "Node FSReqPromise native factory",
        .finalizer = factoryFinalizer, .gc_mark = factoryMark,
    };
    if (c.JS_NewClass(s.engine.runtime, class_id, &definition) < 0) return error.OutOfMemory;
    try s.boundary.checkPendingSince(generation);
    const allocation = try s.beforeAllocation();
    const owner = try s.checkedAllocation(c.JS_NewObjectProtoClass(s.engine.context, c.pi_js_null(), class_id), allocation);
    const self = try data.environment.allocator().create(Factory);
    self.* = .{
        .registry = registry.retain(),
        .binding_target = a.duplicate(s.engine, target),
    };
    _ = c.JS_SetOpaque(owner, self);
    return a.duplicate(s.engine, owner);
}
pub fn acquire(engine: *Engine, data: *BindingData) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |owner| {
        if ((try factoryData(engine, owner)) != data)
            return error.ActualFSReqPromiseBindingDataMismatch;
        return a.duplicate(engine, owner);
    }
    const candidate = try a.expression(engine, createFactoryBody, .{data});
    if (engine.native_module_values.get(cache_key)) |owner| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, owner));
        completion.release(candidate);
        const result = try completion.finishValue();
        const selected_data = factoryData(engine, result) catch |err| {
            var failure = a.owned.Completion.initVoid(engine, err);
            failure.release(result);
            try failure.finishVoid();
            unreachable;
        };
        if (selected_data != data) {
            var failure = a.owned.Completion.initVoid(engine, error.ActualFSReqPromiseBindingDataMismatch);
            failure.release(result);
            try failure.finishVoid();
            unreachable;
        }
        return result;
    }
    return publication.publish(engine, cache_key, candidate);
}
/// These native constructors use the caller's actual HandleScope. In
/// particular, an ordinary init-hook rethrow remains escrowed while the
/// non-null native request proceeds to SetReturnValue and Dispatch.
/// The returned owned wrapper must be retained in that same caller scope.
pub fn createRequest(s: *Scope, known_factory: c.JSValue,
    use_bigint: bool, cancel_native: request_state.Cancel) !c.JSValue
{
    return createRequestBody(s, known_factory, use_bigint, cancel_native, null);
}
pub fn createPhysicalRequest(s: *Scope, known_factory: c.JSValue,
    use_bigint: bool, cancel_native: request_state.Cancel, physical: Physical) !c.JSValue
{
    return createRequestBody(s, known_factory, use_bigint, cancel_native, physical);
}
fn createRequestBody(s: *Scope, known_factory: c.JSValue,
    use_bigint: bool, cancel_native: request_state.Cancel, physical: ?Physical) !c.JSValue
{
    const data = try factoryData(s.engine, known_factory);
    const wrapper = try s.own(try templates.newInstance(s.engine, data.template_owner, .fsreqpromise));
    // INIT hook execution makes this a guest-capable operation. Never tag its
    // whole allocation span as a purely native producer.
    try s.pending();
    const resolver = try s.checked(c.JS_PiNewPendingPromise(s.engine.context));
    // Original Object::Set uses kDontThrow; a normal false result continues.
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, wrapper,
        a.duplicate(s.engine, data.promise_string), a.duplicate(s.engine, resolver), 0);
    try s.pending();
    if (status < 0) return error.MissingActualFSReqPromiseSetReason;

    const self = try data.environment.allocator().create(Request);
    var native_request: ?*uv.PiUvFsRequest = null;
    if (physical) |input| {
        // Only native charged storage is created here. The actual init hook
        // remains in initialize(), outside this proven allocation producer.
        const result = uv.pi_uv_fs_request_create(input.service, input.kind, 0, &native_request);
        if (result.allocation_failed != 0 or result.status < 0) {
            const failure: anyerror = if (result.allocation_failed != 0)
                error.OutOfMemory else error.ActualFSReqPhysicalInputsRequired;
            var completion = a.owned.Completion.initVoid(s.engine, failure);
            data.environment.allocator().destroy(self);
            try completion.finishVoid();
            unreachable;
        }
        if (native_request == null) {
            var completion = a.owned.Completion.initVoid(s.engine, error.ActualFSReqNativeStorageRequired);
            data.environment.allocator().destroy(self);
            try completion.finishVoid();
            unreachable;
        }
    }
    self.initialize(s, data, wrapper, use_bigint, cancel_native, native_request) catch |err| {
        // Record the real construction failure before its partially attached
        // native owner or any derived alias is retired.
        var completion = a.owned.Completion.initVoid(s.engine, err);
        completion.release(c.pi_js_undefined());
        if (self.attached) {
            self.wrap.retire(false) catch {};
        } else {
            if (native_request) |actual| uv.pi_uv_fs_request_release(actual);
            data.environment.allocator().destroy(self);
        }
        try completion.finishVoid();
        unreachable;
    };
    return a.duplicate(s.engine, wrapper);
}
pub fn unwrap(engine: *Engine, known_factory: c.JSValue, wrapper: c.JSValue) !*Request {
    const data = try factoryData(engine, known_factory);
    const registry = try templates.registry(engine, data.template_owner);
    if (c.JS_GetClassID(wrapper) != registry.classId(.fsreqpromise))
        return registry.check(.invalid_wrap_brand);
    const state = registry.unwrap(wrapper) orelse return registry.check(.invalid_wrap_brand);
    const self = Request.fromWrap(state);
    if (self.binding_data != data)
        return registry.check(.invalid_wrap_brand);
    return self;
}
