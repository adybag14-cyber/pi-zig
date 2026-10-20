//! Actual ReqWrap dispatch and original native callback delivery for private
//! FS requests. The existing Environment owns the only request queue/counter; the
//! shared Hub service owns the only libuv thread, event FIFO and stop/join.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const request_state = @import("native_node_request_state.zig");
const requests = @import("native_node_fs_request_promise.zig");
const after_scope = @import("native_node_fs_after_scope.zig");
const shared_service = @import("native_node_uv_service.zig");
const env_io = @import("native_env_io.zig");
const Completion = @import("native_sdk_owned_completion.zig").Completion;
const c = a.c;
pub const uv = shared_service.uv;
pub const Engine = a.v.em.Engine;
const Scope = a.Scope;
const controller_tag: u8 = 0;
pub const Acquisition = union(enum) { ready: *Controller, failed: c_int };

pub const Controller = struct {
    hub: *env_io.Hub,
    environment: *callbacks.Environment,
    service: *uv.PiUvService,
    busy: usize = 0,
    stopping: bool = false,
    references: usize = 1, // Hub plus actual retained native binding owners.

    pub fn retain(self: *Controller) *Controller {
        std.debug.assert(self.references != 0);
        self.references += 1;
        return self;
    }
    pub fn release(self: *Controller) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references != 0) return;
        std.debug.assert(self.stopping);
        const environment = self.environment;
        uv.pi_uv_service_release(self.service);
        environment.allocator().destroy(self);
        environment.release();
    }
    pub fn beginCall(self: *Controller, engine: *Engine) !void { return self.enter(engine); }
    pub fn endCall(self: *Controller) void { self.leave(); }

    fn enter(self: *Controller, engine: *Engine) !void {
        // A retained actual binding can outlive the Hub. Never dereference
        // that retired Hub after its native resource has been stopped.
        if (self.stopping) return error.NativeEnvClosed;
        try self.hub.assertOwner();
        if ((try self.environment.requireEngine()) != engine or self.hub.engine != engine)
            return error.ActualFSRequestEnvironmentMismatch;
        if (self.stopping or self.hub.stopping) return error.NativeEnvClosed;
        self.busy += 1;
    }
    fn leave(self: *Controller) void {
        std.debug.assert(self.busy != 0);
        self.busy -= 1;
    }

    /// Creation uses the caller's real HandleScope and native constructor
    /// allocation cutpoint. No extra Promise or native request is made at
    /// Dispatch. The caller preserves this Local through SetReturnValue.
    pub fn createReadRequest(self: *Controller, s: *Scope, factory: c.JSValue) !*requests.Request {
        try self.enter(s.engine);
        defer self.leave();
        const wrapper = try s.own(try requests.createPhysicalRequest(s, factory,
            false, cancelRequest, .{ .service = self.service, .kind = uv.PI_UV_FS_READ }));
        const request = try requests.unwrap(s.engine, factory, wrapper);
        if (request.environment() != self.environment)
            return error.ActualFSRequestEnvironmentMismatch;
        return request;
    }

    /// Private inputs were checked by the genuine native Read binding. The
    /// stored request is the one constructed above, not a worker Task copy.
    /// An immediate negative Dispatch calls the original AfterInteger directly
    /// and never enters Wrapper or the waiting counter.
    pub fn dispatchRead(self: *Controller, s: *Scope, request: *requests.Request,
        descriptor: c_int, backing: *const c.JSPiArrayBufferLease,
        offset: usize, length: u32, position: i64) !void
    {
        try self.enter(s.engine);
        defer self.leave();
        if (request.environment() != self.environment or
            request.entry.cancel_native != cancelRequest or request.entry.dispatched or
            backing.owner == null or length > std.math.maxInt(i32) or
            offset > backing.byte_length or length > backing.byte_length - offset)
            return error.ActualFSReadDispatchInputsRequired;
        const actual = request.native_request orelse return error.ActualFSNativeRequestRequired;
        request.entry.dispatchStarted();
        try request.entry.setCallback(.{ .request = actual, .call = afterIntegerCallback });
        const status = uv.pi_uv_fs_read(actual, descriptor, @ptrCast(backing),
            offset, length, position);
        if (status >= 0) {
            try request.entry.dispatchAccepted();
            return;
        }
        // AfterInteger may delete the native request. Do not read it afterward.
        try afterInteger(request, actual);
    }

    /// FileHandleReadWrap supplies its actual StreamResource span and original
    /// native completion. The caller retains the backing through delivery and
    /// EmitRead consumption. A failed native Dispatch returns its status and
    /// does not manufacture a callback; the original ReadStart ignores it.
    pub fn dispatchRawRead(self: *Controller, s: *Scope, entry: *request_state.Entry,
        actual: *uv.PiUvFsRequest, descriptor: c_int, base: ?[*]u8,
        length: usize, position: i64,
        callback: *const fn (*request_state.Entry, *anyopaque) anyerror!void) !c_int
    {
        try self.enter(s.engine);
        defer self.leave();
        if (entry.wrap.registry.environment != self.environment or
            entry.queue != &self.environment.requests)
            return error.ActualFSRequestEnvironmentMismatch;
        entry.dispatchStarted();
        try entry.setCallback(.{ .request = actual, .call = callback });
        const status = uv.pi_uv_fs_read_buffer(actual, descriptor,
            @ptrCast(base), length, position);
        if (status >= 0) try entry.dispatchAccepted();
        return status;
    }

    fn ready(raw: *anyopaque) bool {
        const self: *Controller = @ptrCast(@alignCast(raw));
        return self.busy == 0;
    }
    fn find(self: *Controller, actual: *uv.PiUvFsRequest) !*request_state.Entry {
        // The one intrusive Environment queue and the actual request address
        // stored at Dispatch identify the selected native original callback.
        // No parallel map or Promise-only cancellation-function cast is used.
        var cursor = self.environment.requests.head;
        while (cursor) |entry| : (cursor = entry.next) {
            if (entry.original_callback) |callback|
                if (callback.request == @as(*anyopaque, @ptrCast(actual))) return entry;
        }
        return error.ActualFSCompletionRequestRequired;
    }
    fn deliver(raw: *anyopaque, event: *uv.PiUvEvent) !void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        try self.hub.assertOwner();
        const actual = uv.pi_uv_event_fs_request(event) orelse
            return error.ActualFSCompletionEventRequired;
        const entry = try self.find(actual);
        if (!entry.dispatched or !entry.counted)
            return error.ActualFSAcceptedCompletionRequired;
        self.busy += 1;
        defer self.leave();
        // MakeLibuvRequestCallback::Wrapper: native strong pointer, Detach,
        // decrement, then select/call the original callback. Its pointer dies
        // last, even if that callback resets and redispatches this same Entry.
        try entry.beginCallback();
        const engine = self.hub.engine;
        var handles = Scope.init(engine);
        var failure: ?anyerror = null;
        const outcome: anyerror!void = if (entry.original_callback) |callback|
            callback.call(entry, callback.request) else error.ActualFSOriginalCallbackRequired;
        outcome catch |err| {
            record(&handles, err);
            failure = err;
        };
        entry.endCallback() catch |err| {
            record(&handles, err);
            if (failure == null) failure = err;
        };
        const ignored = try handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
    fn abandon(raw: *anyopaque, event: *uv.PiUvEvent) !void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        // Original AfterScope::Proceed reads this actual Environment state.
        // Lifecycle must disable JS before Hub shutdown; no fake completion
        // or forced Promise settlement substitutes for that transition.
        if (self.environment.canCallIntoJs())
            return error.ActualFSShutdownJavascriptDisableRequired;
        return deliver(raw, event);
    }
    fn stop(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        if (self.stopping) return;
        std.debug.assert(self.busy == 0);
        if (self.environment.canCallIntoJs())
            @panic("actual Node environment must disable JS before FS shutdown");
        self.stopping = true;
        // The sole shared service resource was registered first. It has joined
        // all native callbacks, while its event FIFO still owns their results.
        const state = uv.pi_uv_service_snapshot(self.service);
        if (state.thread_joined == 0 or state.pending_requests != 0)
            @panic("FS controller stopped before the shared libuv service");
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Controller = @ptrCast(@alignCast(raw));
        std.debug.assert(self.stopping and self.busy == 0);
        const environment = self.environment;
        const engine = self.hub.engine;
        // The earlier shared stopped() has executed each genuine Wrapper and
        // native AfterScope with JS disabled. Do not reset the actual counter.
        var handles = Scope.init(engine);
        var failure: ?anyerror = null;
        environment.requests.requireNoWaiting(environment) catch |err| {
            record(&handles, err);
            failure = err;
        };
        self.release(); // Drop only the Hub's native entitlement.
        const ignored = handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined()) catch return;
        engine.freeValue(ignored);
    }
};

fn cancelRequest(entry: *request_state.Entry) void {
    const request: *requests.Request = @alignCast(@fieldParentPtr("entry", entry));
    if (request.native_request) |actual| {
        // An accepted cancellation still has its real eventual callback.
        _ = uv.pi_uv_fs_cancel(actual);
    }
}
fn cleanupRequest(raw: *anyopaque) void {
    const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(raw));
    uv.pi_uv_fs_request_cleanup(actual);
}
fn afterIntegerCallback(entry: *request_state.Entry, raw: *anyopaque) !void {
    const request: *requests.Request = @alignCast(@fieldParentPtr("entry", entry));
    const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(raw));
    return afterInteger(request, actual);
}
fn afterInteger(request: *requests.Request, actual: *uv.PiUvFsRequest) !void {
    const info = uv.pi_uv_fs_request_info(actual);
    if (info.kind != uv.PI_UV_FS_READ) return error.ActualFSReadCompletionRequired;
    var after: after_scope.AfterScope = undefined;
    try after.init(request, .{ .raw = actual, .run = cleanupRequest });
    return after.finish(afterIntegerBody(&after, request, info));
}
fn afterIntegerBody(after: *after_scope.AfterScope, request: *requests.Request,
    info: uv.PiUvFsInfo) !void
{
    // Read's validated Int32 length bounds every successful uv result.
    const result = std.math.cast(c_int, info.result) orelse
        return error.ActualFSReadResultRequired;
    const path: ?[]const u8 = if (info.path == null) null else
        std.mem.span(@as([*:0]const u8, @ptrCast(info.path)));
    if (try after.proceed(.{ .code = result, .syscall = "read", .path = path }))
        try request.resolve(c.JS_NewInt32(after.handles.engine.context, result));
}
fn record(s: *Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}

/// One native FS client on the already shared service. An ordinary loop status
/// is returned unchanged for the real bootstrap caller's native error owner.
pub fn acquire(engine: *Engine, environment: *callbacks.Environment) !Acquisition {
    try engine.checkNativeEntry();
    if ((try environment.requireEngine()) != engine)
        return error.ActualFSRequestEnvironmentMismatch;
    const hub = try env_io.get(engine);
    try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    for (hub.resources.items) |resource|
        if (resource.tag == @as(?*const anyopaque, &controller_tag)) {
            const existing: *Controller = @ptrCast(@alignCast(resource.raw));
            if (existing.stopping or existing.environment != environment)
                return error.ActualFSRequestEnvironmentMismatch;
            return .{ .ready = existing };
        };
    const shared = switch (try shared_service.acquire(engine)) {
        .ready => |actual| actual,
        .failed => |status| return .{ .failed = status },
    };
    const self = try environment.allocator().create(Controller);
    hub.resources.ensureUnusedCapacity(engine.gpa, 1) catch |err| {
        var completion = Completion.initVoid(engine, err);
        environment.allocator().destroy(self);
        try completion.finishVoid();
        unreachable;
    };
    self.* = .{ .hub = hub, .environment = environment.retain(), .service = shared.service };
    shared.attach(.fs, .{
        .raw = self, .ready = Controller.ready,
        .complete = Controller.deliver, .abandon = Controller.abandon,
    }) catch |err| {
        var completion = Completion.initVoid(engine, err);
        environment.allocator().destroy(self);
        environment.release();
        try completion.finishVoid();
        unreachable;
    };
    // Publication has no remaining fallible/guest operation. This independent
    // native entitlement survives the earlier shared stopped() FIFO drain.
    uv.pi_uv_service_retain(shared.service);
    hub.resources.appendAssumeCapacity(.{
        .raw = self, .tag = &controller_tag,
        .stop = Controller.stop, .stopped = Controller.stopped,
    });
    return .{ .ready = self };
}
