// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! StreamBase::Shutdown, SimpleShutdownWrap<AsyncWrap>, and the genuine
//! ReportWritesToJSStreamListener completion body. No public JS installation
//! or process trace/template bootstrap is synthesized here.
const a = @import("native_node_argument_values.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const streams = @import("native_node_stream_base.zig");
const resources = @import("native_node_stream_resource.zig");
const requests = @import("native_node_stream_request.zig");
const async_callback = @import("native_node_async_wrap_make_callback.zig");
const latin1 = @import("native_node_one_byte_string.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = resources.uv;

/// The native integer result remains available to the caller's Scope even
/// when an ordinary original void callback has left a pending exception.
pub fn run(parent: *a.Scope, stream: *streams.Base,
    input: ?c.JSValue) anyerror!c_int
{
    const environment = stream.environment.retain();
    defer environment.release();
    if ((try environment.requireEngine()) != parent.engine)
        return error.ActualStreamShutdownEnvironmentMismatch;
    var locals = a.Scope.init(parent.engine);
    var pointer: ?*wraps.State = null;
    var saved_trigger: ?f64 = null;
    var status: c_int = uv.UV_EBUSY;
    var failure: ?anyerror = null;
    runBody(&locals, stream, input, &pointer, &saved_trigger, &status) catch |err| {
        requests.recordFailure(&locals, err);
        failure = err;
    };
    // Declaration order in Source is HandleScope, BaseObjectPtr, trigger scope.
    // Restore trigger first, then release the request, then retire local handles.
    if (saved_trigger) |old| environment.uidField(.default_trigger).* = old;
    if (pointer) |state| state.releaseNative() catch |err| {
        requests.recordFailure(&locals, err);
        if (failure == null) failure = err;
    };
    const ignored = locals.finish(if (failure) |err|
        @as(anyerror!c.JSValue, err) else c.pi_js_undefined()) catch |err|
    {
        requests.recordFailure(parent, err);
        if (err == error.JavaScriptException and !parent.boundary.isFatal())
            return status;
        return err;
    };
    parent.engine.freeValue(ignored);
    return status;
}

fn runBody(s: *a.Scope, stream: *streams.Base, input: ?c.JSValue,
    pointer: *?*wraps.State, saved_trigger: *?f64, status: *c_int) anyerror!void
{
    const bindings = stream.operations.shutdown orelse
        return error.ActualStreamShutdownBindingsRequired;
    const environment = stream.environment;
    const registry = try templates.registry(s.engine, bindings.template_owner);
    if (registry.environment != environment)
        return error.ActualStreamShutdownTemplateEnvironmentMismatch;
    const do_shutdown = stream.virtuals.do_shutdown orelse
        return error.ActualStreamShutdownImplementationRequired;

    const object = if (input) |value|
        try s.own(a.duplicate(s.engine, value))
    else blk: {
        // A failing real template operation leaves status UV_EBUSY, as ToLocal.
        const created = try templates.newShutdownWrapInstance(s, bindings.template_owner);
        try registry.resetRequestObject(created);
        break :blk created;
    };

    const stream_wrap = stream.virtuals.get_async_wrap(stream) orelse
        return error.ActualStreamAsyncWrapRequired;
    if (environment.field(.check).* > 0 and !(stream_wrap.async_id >= 0))
        check.assertion(s.engine, .{
            .file_line = "src/env.cc:268",
            .message = "(default_trigger_async_id) >= (0)",
            .function = "node::AsyncHooks::DefaultTriggerAsyncIdScope",
        });
    saved_trigger.* = environment.uidField(.default_trigger).*;
    environment.uidField(.default_trigger).* = stream_wrap.async_id;
    const request = try stream.virtuals.create_shutdown(stream, s, object);
    if (request) |selected| {
        pointer.* = selected.request.asyncWrap();
        // The actual BaseObjectPtr increments before any possible port check.
        try pointer.*.?.retainNative();
    }
    status.* = try do_shutdown(stream, s, request);
    if (status.* != 0) if (request) |selected| {
        selected.request.dispose() catch |err| {
            requests.recordFailure(s, err);
            if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
        };
    };

    if (stream.virtuals.error_string(stream)) |message| {
        const value = try latin1.fromCString(s, message, stream.operations.heap_diagnostics);
        requests.setError(s, object, bindings.error_string, value) catch |err| {
            status.* = uv.UV_EBUSY;
            return err; // IsNothing returns before ClearError.
        };
        stream.virtuals.clear_error(stream);
    }
}

pub fn createDefault(stream: *streams.Base, s: *a.Scope,
    object: c.JSValue) anyerror!?*requests.Shutdown
{
    return &((try Simple.create(s, stream, object)).shutdown);
}

const Simple = struct {
    shutdown: requests.Shutdown = .{},
    wrap: wraps.State = undefined,
    request_attached: bool = false,
    state_attached: bool = false,

    fn fromRequest(request: *requests.Request) *Simple {
        return @fieldParentPtr("shutdown", requests.Shutdown.fromRequest(request));
    }
    fn getAsyncWrap(request: *requests.Request) *wraps.State {
        return &fromRequest(request).wrap;
    }
    fn fromWrap(state: *wraps.State) *Simple {
        return @fieldParentPtr("wrap", state);
    }
    fn mark(_: ?*c.JSRuntime, _: *wraps.State, _: ?*const c.JS_MarkFunc) void {}
    fn retire(_: *wraps.State, _: *a.Scope) anyerror!void {}
    fn destroy(state: *wraps.State) void {
        state.registry.environment.allocator().destroy(fromWrap(state));
    }
    const derived: wraps.Derived = .{ .mark = mark, .retire = retire, .destroy = destroy };

    fn create(s: *a.Scope, stream: *streams.Base, object: c.JSValue) anyerror!*Simple {
        const stream_wrap = stream.virtuals.get_async_wrap(stream) orelse
            return error.ActualStreamAsyncWrapRequired;
        const registry = stream_wrap.registry;
        if (registry.environment != stream.environment)
            return error.ActualStreamShutdownEnvironmentMismatch;
        try s.pending();
        const self = try registry.environment.allocator().create(Simple);
        self.* = .{};
        initialize(self, s, stream, registry, object) catch |err| {
            var completion = a.owned.Completion.initVoid(s.engine, err);
            if (self.request_attached) registry.clearRequestPointer(object) catch {};
            if (self.state_attached) self.wrap.retire(false) catch {}
            else registry.environment.allocator().destroy(self);
            try completion.finishVoid();
            unreachable;
        };
        return self;
    }

    fn initialize(self: *Simple, s: *a.Scope, stream: *streams.Base,
        registry: *wraps.Registry, object: c.JSValue) anyerror!void
    {
        try self.shutdown.init(stream, registry, object, getAsyncWrap);
        self.request_attached = true;
        self.wrap.initialize(registry, object, derived, wraps.Provider.shutdownwrap, -1) catch |err| {
            self.state_attached = registry.unwrap(object) == &self.wrap;
            requests.recordFailure(s, err);
            // The original native constructor continues after completed
            // ordinary AsyncReset/init-hook rethrow.
            if (!self.state_attached or !self.wrap.init_hook_ran or
                err != error.JavaScriptException or s.boundary.isFatal()) return err;
        };
        self.state_attached = true;
        try self.wrap.makeWeak();
    }
};

/// Exact reusable ReportWritesToJSStreamListener native callback. Derived
/// listeners (including CustomBufferJSListener) select this operation rather
/// than the base StreamListener's forward-to-previous implementation.
pub fn reportAfterShutdown(listener: *resources.Listener,
    request: *requests.Shutdown, status: c_int) anyerror!void
{
    return reportAfterRequest(listener, &request.request, status);
}

pub fn reportAfterWrite(listener: *resources.Listener,
    request: *requests.Write, status: c_int) anyerror!void
{
    return reportAfterRequest(listener, &request.request, status);
}

pub fn reportAfterRequest(listener: *resources.Listener,
    request: *requests.Request, status: c_int) anyerror!void
{
    // Source static_cast<StreamBase*>(stream_): the installed listener must be
    // attached to an actual Base resource, as in the original inheritance.
    const resource = listener.stream orelse return error.ActualStreamListenerRequired;
    const stream: *streams.Base = @fieldParentPtr("resource", resource);
    const environment = stream.environment;
    if (!environment.canCallIntoJs()) return;
    _ = environment.retain();
    defer environment.release();
    const engine = try environment.requireEngine();
    const state = request.asyncWrap();
    var locals = a.Scope.init(engine);
    const ignored = try locals.finish(reportBody(&locals, stream, state, request.bindings, status));
    engine.freeValue(ignored);
}

fn reportBody(s: *a.Scope, stream: *streams.Base, state: *wraps.State,
    request_bindings: ?streams.RequestBindings, status: c_int) anyerror!c.JSValue
{
    const wrapper = state.object() orelse check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:763",
        .message = "!async_wrap->persistent().IsEmpty()",
        .function = "node::ReportWritesToJSStreamListener::OnStreamAfterReqFinished",
    });
    const object = try s.own(a.duplicate(s.engine, wrapper));
    const stream_object = stream.virtuals.get_object(stream) orelse
        return error.ActualStreamObjectRequired;
    var arguments = [_]c.JSValue{
        c.JS_NewInt32(s.engine.context, status),
        try s.own(a.duplicate(s.engine, stream_object)),
        c.pi_js_undefined(),
    };
    const bindings = request_bindings orelse stream.operations.shutdown orelse
        return error.ActualStreamShutdownBindingsRequired;
    const diagnostics = stream.operations.heap_diagnostics;
    if (stream.virtuals.error_string(stream)) |message| {
        arguments[2] = try latin1.fromCString(s, message, diagnostics);
        stream.virtuals.clear_error(stream);
    }
    // Has(...).FromJust() is the original native terminal policy, even when the
    // proxy Has trap produced an ordinary pending reason.
    const has_callback = s.hasKey(object, bindings.oncomplete_string) catch
        check.maybeCheck(s.engine, diagnostics);
    if (has_callback) {
        // AsyncWrap::MakeCallback(Local<Name>) performs ordinary Get and
        // returns undefined without invoking JS/trace when it is not Function.
        const callback = try s.getKey(object, bindings.oncomplete_string);
        if (!c.JS_IsFunction(s.engine.context, callback)) return c.pi_js_undefined();
        const trace = stream.operations.trace;
        _ = try async_callback.call(s, state, trace, callback, &arguments);
        // The native callback may have destroyed stream/state.
    }
    return c.pi_js_undefined();
}
