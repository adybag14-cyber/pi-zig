// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The genuine Node24.13 NewFSReqCallback native constructor and ownership.
//! Its actual instance is supplied by the FSReqCallback FunctionTemplate,
//! including the same prototype/brand used by FileHandleReadWrap NewInstance.
//! Construction reserves real unassigned uv_fs_t storage before AsyncWrap init,
//! then creates the original ReqWrap queue/weak/reset state and BindingData ptr.
//!
//! General FSReqBase Init/continuation/stat/settlement methods are separate
//! source work. No substitute operation or no-op completion is exposed here.
const a = @import("native_node_argument_values.zig");
const native = @import("native_node_async_wrap_state.zig");
const requests = @import("native_node_request_state.zig");
const binding = @import("native_node_fs_binding_data.zig");
const io = @import("native_node_fs_request_io.zig");
const c = a.c;
const uv = io.uv;

pub const Request = struct {
    wrap: native.State = undefined,
    entry: requests.Entry = undefined,

    // Selected original FSReqBase default members. The constructor does not
    // allocate a destination buffer or continuation object.
    encoding: enum { utf8 } = .utf8,
    has_data: bool = false,
    use_bigint: bool = false,
    is_plain_open: bool = false,
    with_file_types: bool = false,
    syscall: ?[*:0]const u8 = null,
    binding_data: ?*binding.BindingData = null,
    inline_buffer: [64]u8 = undefined,
    buffer_length: usize = 0,

    // These bookkeeping fields do not make an additional JS/native owner.
    actual: ?*uv.PiUvFsRequest = null,
    attached: bool = false,
    entry_initialized: bool = false,

    fn fromWrap(state: *native.State) *Request {
        return @alignCast(@fieldParentPtr("wrap", state));
    }
    fn fromEntry(entry: *requests.Entry) *Request {
        return @alignCast(@fieldParentPtr("entry", entry));
    }
    fn mark(_: ?*c.JSRuntime, _: *native.State, _: ?*const c.JS_MarkFunc) void {
        // BindingData's BaseObjectPtr is its own native strong root. The
        // unused inline buffer, unassigned request and queue are not JS edges.
    }
    fn retire(state: *native.State, s: *a.Scope) !void {
        const self = fromWrap(state);
        var failure: ?anyerror = null;
        // The untouched MaybeStackBuffer has no heap allocation to release.
        // FSReqBase's BindingData pointer then retires before ReqWrapBase.
        if (self.binding_data) |data| {
            self.binding_data = null;
            data.releaseNative() catch |err| {
                s.boundary.escaping();
                failure = err;
            };
        }
        if (self.entry_initialized) {
            self.entry_initialized = false;
            self.entry.deinit();
        }
        if (failure) |err| return err;
    }
    fn destroy(state: *native.State) void {
        const allocator = state.registry.environment.allocator();
        const self = fromWrap(state);
        if (self.actual) |request| {
            self.actual = null;
            uv.pi_uv_fs_request_release(request);
        }
        allocator.destroy(self);
    }
    fn cancel(entry: *requests.Entry) void {
        const self = fromEntry(entry);
        if (self.actual) |request| _ = uv.pi_uv_fs_cancel(request);
    }
    const derived: native.Derived = .{
        .mark = mark, .retire = retire, .destroy = destroy,
    };

    fn initialize(self: *Request, s: *a.Scope, registry: *native.Registry,
        data: *binding.BindingData, wrapper: c.JSValue, use_bigint: bool) !void
    {
        self.wrap.initialize(registry, wrapper, derived,
            native.Provider.fsreqcallback, -1) catch |err|
        {
            self.attached = registry.unwrap(wrapper) == &self.wrap;
            s.boundary.escaping();
            // AsyncReset is void in the original base constructor. The
            // completed ordinary init-hook rethrow does not skip ReqWrap,
            // use_bigint_ or the native BindingData pointer construction.
            if (!self.attached or !self.wrap.init_hook_ran or
                err != error.JavaScriptException or s.boundary.isFatal())
                return err;
        };
        self.attached = true;
        try self.entry.initialize(&self.wrap, cancel);
        self.entry_initialized = true;
        try self.wrap.makeWeak();
        self.entry.reset();
        if (uv.pi_uv_fs_request_reset(self.actual.?) != 0)
            return error.ActualFSReqCallbackInitialResetRequired;
        self.use_bigint = use_bigint;
        try data.retainNative();
        self.binding_data = data;
    }

    /// This is new FSReqCallback(binding_data, args.This(), args[0]->IsTrue()).
    /// The actual receiver local remains rooted by the caller's existing scope;
    /// this constructor creates no BaseObjectPtr and no completion Promise.
    pub fn construct(s: *a.Scope, registry: *native.Registry,
        controller: *io.Controller, wrapper: c.JSValue,
        use_bigint: bool) !void
    {
        try s.pending();
        if (registry.environment != controller.environment or
            (try registry.environment.requireEngine()) != s.engine)
            return error.ActualFSReqCallbackEnvironmentMismatch;
        if (c.JS_GetClassID(wrapper) != registry.classId(.fsreqcallback))
            return registry.check(.invalid_wrap_brand);
        // Realm::GetBindingData copies the real weak pointer. Retaining the
        // native BindingData belongs later to its actual member constructor.
        const data = binding.get(registry) orelse
            return error.ActualFSReqCallbackBindingDataRequired;
        try controller.beginCall(s.engine);
        defer controller.endCall();
        const allocator = registry.environment.allocator();
        const self = try allocator.create(Request);
        self.* = .{};
        const allocation = uv.pi_uv_fs_request_create(controller.service,
            uv.PI_UV_FS_UNASSIGNED, 0, &self.actual);
        if (allocation.allocation_failed != 0 or allocation.status < 0 or self.actual == null) {
            const failure: anyerror = if (allocation.allocation_failed != 0)
                error.OutOfMemory else error.ActualFSReqCallbackStorageRequired;
            return failConstruction(s, self, registry, failure);
        }
        self.initialize(s, registry, data, wrapper, use_bigint) catch |err|
            return failConstruction(s, self, registry, err);
    }

    fn failConstruction(s: *a.Scope, self: *Request,
        registry: *native.Registry, err: anyerror) !void
    {
        var completion = a.owned.Completion.initVoid(s.engine, err);
        if (self.attached) {
            self.wrap.retire(false) catch {};
        } else {
            if (self.actual) |request| {
                self.actual = null;
                uv.pi_uv_fs_request_release(request);
            }
            registry.environment.allocator().destroy(self);
        }
        try completion.finishVoid();
    }

    /// Only the genuine FSReqCallback native allocation has this derived type.
    /// The FileHandleReadWrap uses the same instance template/brand, but its
    /// different native allocation must not be reinterpreted as FSReqBase.
    pub fn unwrap(registry: *native.Registry, wrapper: c.JSValue) ?*Request {
        if (c.JS_GetClassID(wrapper) != registry.classId(.fsreqcallback)) return null;
        const state = registry.unwrap(wrapper) orelse return null;
        if (state.derived.destroy != destroy) return null;
        return fromWrap(state);
    }
};
