// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Native StreamBase::Write, WriteBuffer, and SimpleWriteWrap<AsyncWrap>.
//! The original FileHandle DoWrite returns UV_ENOSYS. Successful native writes
//! require a concrete stream's DoWrite/try-write owner; none is synthesized here.
const a = @import("native_node_argument_values.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const templates = @import("native_node_async_wrap.zig");
const streams = @import("native_node_stream_base.zig");
const resources = @import("native_node_stream_resource.zig");
const requests = @import("native_node_stream_request.zig");
const callbacks = @import("native_node_callback_scope.zig");
const latin1 = @import("native_node_one_byte_string.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = resources.uv;

/// This is an owning native result. Its BaseObjectPtr remains alive even after
/// a synchronous DoWrite error disposed/cleared the public request pointer.
/// Release exactly once, at the source result's destructor point.
pub const Result = struct {
    is_async: bool = false,
    err: c_int = uv.UV_EBUSY,
    wrap: ?*requests.Write = null,
    bytes: usize = 0,
    wrap_obj: ?*wraps.State = null,

    pub fn release(self: *Result, s: *a.Scope) anyerror!void {
        const pointer = self.wrap_obj orelse return;
        self.wrap_obj = null;
        self.wrap = null;
        pointer.releaseNative() catch |err| {
            requests.recordFailure(s, err);
            return err;
        };
    }
};

/// The attempted-byte counter advances before try-write, template creation, or
/// DoWrite. A partial try-write changes the slice passed onward, not that total.
/// skip_try_write and a non-null send handle independently bypass DoTryWrite.
pub fn run(parent: *a.Scope, stream: *streams.Base, input_buffers: []uv.uv_buf_t,
    send_handle: ?*uv.uv_stream_t, input: ?c.JSValue,
    skip_try_write: bool) anyerror!Result
{
    const environment = stream.environment.retain();
    defer environment.release();
    if ((try environment.requireEngine()) != parent.engine)
        return error.ActualStreamWriteEnvironmentMismatch;
    var total_bytes: usize = 0;
    for (input_buffers) |buffer| total_bytes +%= @as(usize, buffer.len);
    stream.resource.bytes_written +%= @as(u64, total_bytes);
    var buffers = input_buffers;
    if (send_handle == null and stream.virtuals.has_do_try_write(stream) and
        !skip_try_write)
    {
        const status = try stream.virtuals.do_try_write(stream, parent, &buffers);
        if (status != 0 or buffers.len == 0)
            return .{ .err = status, .bytes = total_bytes };
    }

    var locals = a.Scope.init(parent.engine);
    var pointer: ?*wraps.State = null;
    var saved_trigger: ?f64 = null;
    var result: Result = .{};
    var failure: ?anyerror = null;
    runBody(&locals, stream, buffers, send_handle, input, total_bytes,
        &pointer, &saved_trigger, &result) catch |err|
    {
        requests.recordFailure(&locals, err);
        failure = err;
    };
    if (failure == null) {
        // Source moves this BaseObjectPtr into its returned StreamWriteResult.
        result.wrap_obj = pointer;
        pointer = null;
    }
    // Write declares HandleScope, trigger scope, then BaseObjectPtr. On the
    // early error-set path its pointer retires BEFORE trigger restoration.
    if (pointer) |state| state.releaseNative() catch |err| {
        requests.recordFailure(&locals, err);
        if (failure == null) failure = err;
    };
    if (saved_trigger) |old| environment.uidField(.default_trigger).* = old;
    const ignored = locals.finish(if (failure) |err|
        @as(anyerror!c.JSValue, err) else c.pi_js_undefined()) catch |err|
    {
        requests.recordFailure(parent, err);
        // Original void constructor/hook work can leave a pending JS reason
        // while Write still returns its native result to the caller.
        if (err == error.JavaScriptException and !parent.boundary.isFatal())
            return result;
        result.release(parent) catch {};
        return err;
    };
    parent.engine.freeValue(ignored);
    return result;
}

fn runBody(s: *a.Scope, stream: *streams.Base, buffers: []uv.uv_buf_t,
    send_handle: ?*uv.uv_stream_t, input: ?c.JSValue, total_bytes: usize,
    pointer: *?*wraps.State, saved_trigger: *?f64, result: *Result) anyerror!void
{
    const bindings = stream.operations.write orelse
        return error.ActualStreamWriteBindingsRequired;
    const environment = stream.environment;
    const registry = try templates.registry(s.engine, bindings.request.template_owner);
    if (registry.environment != environment)
        return error.ActualStreamWriteTemplateEnvironmentMismatch;
    const do_write = stream.virtuals.do_write orelse
        return error.ActualStreamWriteImplementationRequired;
    const object = if (input) |value|
        try s.own(a.duplicate(s.engine, value))
    else blk: {
        const created = try templates.newWriteWrapInstance(s, bindings.request.template_owner);
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
    var request: ?*requests.Write = try stream.virtuals.create_write(stream, s, object);
    pointer.* = request.?.request.asyncWrap();
    // retainNative increments before its possible port ownership check.
    try pointer.*.?.retainNative();
    const status = try do_write(stream, s, request.?, buffers, send_handle);
    const is_async = status == 0;
    if (!is_async) {
        request.?.request.dispose() catch |err| {
            requests.recordFailure(s, err);
            if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
        };
        request = null;
    }
    if (stream.virtuals.error_string(stream)) |message| {
        const value = try latin1.fromCString(s, message, stream.operations.heap_diagnostics);
        // IsNothing returns {false, UV_EBUSY, null, 0, {}} before ClearError.
        try requests.setError(s, object, bindings.request.error_string, value);
        stream.virtuals.clear_error(stream);
    }
    result.* = .{ .is_async = is_async, .err = status, .wrap = request,
        .bytes = total_bytes };
}

pub fn setResult(environment: *callbacks.Environment, result: *const Result) void {
    environment.streamBaseField(.bytes_written).* =
        @bitCast(@as(u32, @truncate(result.bytes)));
    environment.streamBaseField(.last_write_was_async).* = @intFromBool(result.is_async);
}

/// Original callback body after JSMethod's real receiver/alive/trigger guards.
/// Invalid input retains the TypeError and returns native 0 without touching
/// shared write-result state. A failed IPC handle Set returns native -1.
pub fn writeBuffer(s: *a.Scope, stream: *streams.Base,
    args: []const c.JSValue) anyerror!c_int
{
    const object = a.arg(args, 0);
    if (!c.JS_IsObject(object)) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:298",
        .message = "args[0]->IsObject()",
        .function = "node::StreamBase::WriteBuffer",
    });
    const value = a.arg(args, 1);
    if (c.JS_GetTypedArrayType(value) != c.JS_TYPED_ARRAY_UINT8) {
        try invalidBuffer(s, stream.operations.heap_diagnostics);
        return 0;
    }
    var buffer: [1]uv.uv_buf_t = .{.{
        .base = @ptrCast(c.JS_PiArrayBufferViewData(value)),
        // Source directly assigns uv_buf_t.len, which is 32-bit on Windows.
        .len = @truncate(c.JS_PiArrayBufferViewByteLength(value)),
    }};
    var send_handle: ?*uv.uv_stream_t = null;
    const handle_object = a.arg(args, 2);
    if (c.JS_IsObject(handle_object) and stream.virtuals.is_ipc_pipe(stream)) {
        const unwrap = stream.operations.unwrap_send_handle orelse
            return error.ActualStreamIPCHandleWrapRequired;
        send_handle = try unwrap(s, handle_object) orelse return uv.UV_EINVAL;
        const bindings = stream.operations.write orelse
            return error.ActualStreamWriteBindingsRequired;
        requests.setError(s, object, bindings.handle_string, handle_object) catch |err| {
            requests.recordFailure(s, err);
            if (err == error.JavaScriptException and !s.boundary.isFatal()) return -1;
            return err;
        };
    }
    const environment = stream.environment.retain();
    defer environment.release();
    var result = try run(s, stream, &buffer, send_handle, object, false);
    setResult(environment, &result);
    const status = result.err;
    result.release(s) catch |err| {
        requests.recordFailure(s, err);
        if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
    };
    return status;
}

fn invalidBuffer(s: *a.Scope, diagnostics: ?*const check.Diagnostics) anyerror!void {
    // node_errors.h ERRORS_WITH_CODE: intrinsic TypeError plus ordinary
    // kDontThrow Set(code). A prototype setter is intentionally observable.
    const code = try latin1.fromCString(s, "ERR_INVALID_ARG_TYPE", diagnostics);
    const generation = try s.beforeAllocation();
    const occurrence = c.JS_PiOutOfMemoryOccurrence(s.engine.runtime);
    const raw = c.JS_NewTypeError(s.engine.context, "Second argument must be a buffer");
    if (c.JS_IsException(raw)) {
        if (c.JS_PiOutOfMemoryOccurrence(s.engine.runtime) != occurrence)
            check.heapOutOfMemory(s.engine, diagnostics);
        check.fatal(s.engine, "v8::ToLocalChecked", "Empty MaybeLocal", diagnostics);
    }
    const reason = try s.checkedAllocation(raw, generation);
    const key = try latin1.fromCString(s, "code", diagnostics);
    requests.setError(s, reason, key, code) catch
        check.maybeCheck(s.engine, diagnostics);
    _ = a.raise(s, reason);
}

pub fn createDefault(stream: *streams.Base, s: *a.Scope,
    object: c.JSValue) anyerror!*requests.Write
{
    return &((try Simple.create(s, stream, object)).write);
}

const Simple = struct {
    write: requests.Write = .{},
    wrap: wraps.State = undefined,
    request_attached: bool = false,
    state_attached: bool = false,

    fn fromRequest(request: *requests.Request) *Simple {
        return @fieldParentPtr("write", requests.Write.fromRequest(request));
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
        const self = fromWrap(state);
        // SimpleWriteWrap inherits WriteWrap, then AsyncWrap. Base destruction
        // runs in reverse: State's AsyncWrap/BaseObject retirement and pointer
        // clearing finish before WriteWrap's unique backing-store destructor.
        self.write.deinit();
        state.registry.environment.allocator().destroy(self);
    }
    const derived: wraps.Derived = .{ .mark = mark, .retire = retire, .destroy = destroy };

    fn create(s: *a.Scope, stream: *streams.Base, object: c.JSValue) anyerror!*Simple {
        const stream_wrap = stream.virtuals.get_async_wrap(stream) orelse
            return error.ActualStreamAsyncWrapRequired;
        const registry = stream_wrap.registry;
        if (registry.environment != stream.environment)
            return error.ActualStreamWriteEnvironmentMismatch;
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
        try self.write.init(stream, registry, object, getAsyncWrap);
        self.request_attached = true;
        self.wrap.initialize(registry, object, derived, wraps.Provider.writewrap, -1) catch |err| {
            self.state_attached = registry.unwrap(object) == &self.wrap;
            requests.recordFailure(s, err);
            // The original constructor continues after a completed ordinary
            // AsyncReset/init-hook rethrow, exactly as SimpleShutdownWrap.
            if (!self.state_attached or !self.wrap.init_hook_ran or
                err != error.JavaScriptException or s.boundary.isFatal()) return err;
        };
        self.state_attached = true;
        self.wrap.makeWeak() catch |err| {
            requests.recordFailure(s, err);
            // MakeWeak is an original void native operation. An inherited
            // ordinary init-hook reason cannot discard the completed wrapper.
            if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
        };
    }
};
