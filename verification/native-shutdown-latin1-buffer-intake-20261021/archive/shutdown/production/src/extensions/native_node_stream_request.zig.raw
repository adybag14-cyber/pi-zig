// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Genuine StreamReq / ShutdownWrap native state and completion lifetime.
//! The stream pointer is borrowed. This owner introduces no FileHandle root.
const a = @import("native_node_argument_values.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const streams = @import("native_node_stream_base.zig");
const latin1 = @import("native_node_one_byte_string.zig");
const c = a.c;

pub const Request = struct {
    stream: *streams.Base,
    get_async_wrap: *const fn (*Request) *wraps.State,
    on_done: *const fn (*Request, c_int) anyerror!void,

    /// StreamReq construction precedes the actual AsyncWrap base constructor.
    pub fn init(self: *Request, stream: *streams.Base, registry: *wraps.Registry,
        wrapper: c.JSValue, get_async_wrap: *const fn (*Request) *wraps.State,
        on_done: *const fn (*Request, c_int) anyerror!void) anyerror!void
    {
        self.* = .{ .stream = stream, .get_async_wrap = get_async_wrap,
            .on_done = on_done };
        try registry.attachRequestPointer(wrapper, self);
    }

    pub fn asyncWrap(self: *Request) *wraps.State {
        return self.get_async_wrap(self);
    }
    pub fn object(self: *Request) ?c.JSValue {
        return self.asyncWrap().object();
    }
    /// Source FromObject reads the independent StreamReq field. A fresh
    /// constructor has a null slot; it does not require a BaseObject pointer.
    pub fn fromObject(registry: *const wraps.Registry, object_value: c.JSValue) ?*Request {
        return @ptrCast(@alignCast(registry.requestPointer(object_value) orelse return null));
    }

    /// The optional error-string block owns its original HandleScope. A failed
    /// Set returns before OnDone; otherwise its locals retire before OnDone.
    pub fn done(self: *Request, status: c_int, error_string: ?[*:0]const u8) anyerror!void {
        if (error_string) |text| {
            const state = self.asyncWrap();
            const environment = state.registry.environment.retain();
            defer environment.release();
            const engine = try environment.requireEngine();
            var scope = a.Scope.init(engine);
            const ignored = try scope.finish(setErrorBody(&scope, self, text));
            engine.freeValue(ignored);
        }
        return self.on_done(self, status);
    }

    fn setErrorBody(s: *a.Scope, self: *Request, text: [*:0]const u8) anyerror!c.JSValue {
        const stream = self.stream;
        const bindings = stream.operations.shutdown orelse
            return error.ActualStreamShutdownBindingsRequired;
        const wrapper = self.object() orelse
            return error.ActualStreamRequestObjectRequired;
        const object_value = try s.own(a.duplicate(s.engine, wrapper));
        const error_value = try latin1.fromCString(s, text,
            stream.operations.heap_diagnostics);
        try setError(s, object_value, bindings.error_string, error_value);
        return c.pi_js_undefined();
    }

    /// Retain, clear the StreamReq slot, Detach, then retire the temporary
    /// BaseObjectPtr. The final release may destroy this whole request.
    pub fn dispose(self: *Request) anyerror!void {
        const state = self.asyncWrap();
        const environment = state.registry.environment.retain();
        defer environment.release();
        const engine = try environment.requireEngine();
        var scope = a.Scope.init(engine);
        var failure: ?anyerror = null;
        // retainNative increments before its possible ownership/engine check;
        // therefore this scope owns one release even on its failing path.
        state.retainNative() catch |err| {
            recordFailure(&scope, err);
            failure = err;
        };
        if (failure == null) {
            disposeBody(state) catch |err| {
                recordFailure(&scope, err);
                failure = err;
            };
        }
        state.releaseNative() catch |err| {
            recordFailure(&scope, err);
            if (failure == null) failure = err;
        };
        // No self/state access after releaseNative.
        const ignored = try scope.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }

    fn disposeBody(state: *wraps.State) anyerror!void {
        const object_value = state.object() orelse
            return error.ActualStreamRequestObjectRequired;
        try state.registry.clearRequestPointer(object_value);
        try state.detach();
    }
};

pub const Shutdown = struct {
    request: Request = undefined,

    pub fn init(self: *Shutdown, stream: *streams.Base, registry: *wraps.Registry,
        wrapper: c.JSValue,
        get_async_wrap: *const fn (*Request) *wraps.State) anyerror!void
    {
        return self.request.init(stream, registry, wrapper, get_async_wrap, onDone);
    }
    pub fn fromRequest(request: *Request) *Shutdown {
        return @fieldParentPtr("request", request);
    }

    fn onDone(request: *Request, status: c_int) anyerror!void {
        const self = fromRequest(request);
        const environment = request.asyncWrap().registry.environment.retain();
        defer environment.release();
        const engine = try environment.requireEngine();
        var scope = a.Scope.init(engine);
        var failure: ?anyerror = null;
        request.stream.resource.emitAfterShutdown(self, status) catch |err| {
            recordFailure(&scope, err);
            failure = err;
        };
        // The listener may throw, delete the stream, or alter its live chain.
        // Dispose still follows the void native callback. Do not read stream.
        request.dispose() catch |err| {
            recordFailure(&scope, err);
            if (failure == null) failure = err;
        };
        // Dispose can destroy self when no surrounding native pointer remains.
        const ignored = try scope.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }
};

/// V8 Object::Set selects kDontThrow: a false write result is not an empty
/// Maybe. Preserve the real pending exception from a setter/proxy, while a
/// non-writable data property permits the native continuation.
pub fn setError(s: *a.Scope, object_value: c.JSValue,
    key: c.JSValue, value: c.JSValue) anyerror!void
{
    try s.pending();
    const status = c.JS_SetPropertyValue(s.engine.context, object_value,
        a.duplicate(s.engine, key), a.duplicate(s.engine, value), 0);
    try s.pending();
    if (status < 0) return error.ActualStreamRequestSetErrorReasonRequired;
}

pub fn recordFailure(s: *a.Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
