// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Selected actual StreamBase read path over the shared Environment, native
//! managed-buffer table, StreamResource, and the wrapper's internal onread edge.
//! Native allocation retry/GC and trace category/controller owners are required
//! inputs. This module does not install a substitute implementation for either.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const resources = @import("native_node_stream_resource.zig");
const managed = @import("native_node_managed_buffers.zig");
const async_callback = @import("native_node_async_wrap_make_callback.zig");
const check = @import("native_node_check_failure.zig");
const requests = @import("native_node_stream_request.zig");
const shutdown = @import("native_node_stream_shutdown.zig");
const c = a.c;
const uv = managed.uv;

pub const Initialization = enum { zero_initialized, uninitialized };

/// The original ArrayBuffer::NewBackingStore operation returns an owned native
/// store or takes its genuine native terminal path. Its retry/GC/default-fatal
/// implementation is a separate required owner. A single TryNew attempt is not
/// a valid replacement for this operation, and no nullable success is admitted.
pub const Allocation = struct {
    raw: ?*anyopaque,
    new_backing_store: *const fn (?*anyopaque, *callbacks.Environment,
        usize, Initialization) managed.Token,
};

/// Borrowed actual Environment template/key roots. Their embedding owner must
/// retain them through every native stream/request completion; this record is
/// not an installation hook or a substitute template/key allocator.
pub const ShutdownBindings = struct {
    template_owner: c.JSValue,
    error_string: c.JSValue,
    oncomplete_string: c.JSValue,
};

pub const Operations = struct {
    allocation: Allocation,
    trace: async_callback.Trace,
    // The actual native report policy supplied by the embedding. Null retains
    // the original report-disabled configuration; it is not a guest callback.
    heap_diagnostics: ?*const check.Diagnostics,
    shutdown: ?ShutdownBindings = null,
};

pub const Virtuals = struct {
    get_async_wrap: *const fn (*Base) ?*wraps.State,
    get_object: *const fn (*Base) ?c.JSValue = defaultGetObject,
    error_string: *const fn (*Base) ?[*:0]const u8 = defaultError,
    clear_error: *const fn (*Base) void = defaultClearError,
    create_shutdown: *const fn (*Base, *a.Scope, c.JSValue) anyerror!?*requests.Shutdown = shutdown.createDefault,
    do_shutdown: ?*const fn (*Base, *a.Scope, ?*requests.Shutdown) anyerror!c_int = null,
};
fn defaultGetObject(stream: *Base) ?c.JSValue {
    const wrap = stream.virtuals.get_async_wrap(stream) orelse return null;
    return wrap.object();
}
// These are the original StreamResource virtual default bodies.
fn defaultError(_: *Base) ?[*:0]const u8 { return null; }
fn defaultClearError(_: *Base) void {}
pub const ReadChecks = enum { check_nread, skip_nread_checks };

/// This is embedded in the actual derived stream at a stable address. Like the
/// original StreamBase, it borrows its Environment; the actual derived native
/// owner must keep that Environment and VM alive through deinit and callbacks.
pub const Base = struct {
    resource: resources.Resource,
    environment: *callbacks.Environment,
    default_listener: resources.Listener,
    virtuals: Virtuals,
    operations: Operations,
    initialized: bool = false,

    pub fn init(self: *Base, environment: *callbacks.Environment,
        virtuals: Virtuals, operations: Operations) !void
    {
        const engine = try environment.requireEngine();
        self.* = .{
            .resource = resources.Resource.init(engine),
            .environment = environment,
            .default_listener = .{ .read_methods = &default_read_methods,
                .after_shutdown = shutdown.reportAfterShutdown },
            .virtuals = virtuals,
            .operations = operations,
            .initialized = true,
        };
        self.resource.push(&self.default_listener);
    }

    /// The default listener is a native member. Its destructor unlinks it
    /// before the StreamResource base destructor processes remaining listeners.
    pub fn deinit(self: *Base) void {
        if (!self.initialized) return;
        self.initialized = false;
        self.default_listener.deinit();
        self.resource.deinit();
    }

    pub fn attachToObject(self: *Base, registry: *wraps.Registry,
        wrapper: c.JSValue) !void
    {
        try registry.setStreamPointer(wrapper, self);
    }
    pub fn fromObject(registry: *wraps.Registry, wrapper: c.JSValue) ?*Base {
        const pointer = registry.streamPointer(wrapper) orelse return null;
        return @ptrCast(@alignCast(pointer));
    }

    pub fn shutdownRequest(self: *Base, s: *a.Scope,
        wrapper: ?c.JSValue) anyerror!c_int
    {
        return shutdown.run(s, self, wrapper);
    }

    /// No new HandleScope: the Source Local result and selected onread remain
    /// in the caller's existing scope. A callback may delete this Base.
    pub fn callJSOnread(self: *Base, s: *a.Scope, nread: isize,
        array_buffer: ?c.JSValue, offset: usize, checks: ReadChecks) !?c.JSValue
    {
        const environment = self.environment;
        std.debug.assert(@as(isize, @as(i32, @truncate(nread))) == nread);
        std.debug.assert(offset <= std.math.maxInt(i32));
        if (checks == .check_nread) {
            if (array_buffer == null) {
                std.debug.assert(offset == 0);
                std.debug.assert(nread <= 0);
            } else std.debug.assert(nread >= 0);
        }
        environment.streamBaseField(.read_bytes_or_error).* = @truncate(nread);
        environment.streamBaseField(.array_buffer_offset).* =
            @bitCast(@as(u32, @truncate(offset)));
        const arguments = [_]c.JSValue{array_buffer orelse c.pi_js_undefined()};

        const state = self.virtuals.get_async_wrap(self) orelse
            check.assertion(s.engine, .{
                .file_line = "src/stream_base.cc:473",
                .message = "(wrap) != nullptr",
                .function = "node::StreamBase::CallJSOnreadMethod",
            });
        const wrapper = state.object() orelse
            return environment.operations.native_check_failure(environment, .invalid_wrap_brand);
        const object = try s.own(a.duplicate(s.engine, wrapper));
        const onread = try state.registry.streamOnRead(s, object);
        if (!c.JS_IsFunction(s.engine.context, onread))
            check.assertion(s.engine, .{
                .file_line = "src/stream_base.cc:477",
                .message = "onread->IsFunction()",
                .function = "node::StreamBase::CallJSOnreadMethod",
            });
        // Copy before the callback: neither self nor state is used afterwards.
        const trace = self.operations.trace;
        return async_callback.call(s, state, trace, onread, &arguments);
    }
};

const default_read_methods: resources.ReadMethods = .{
    .allocate = defaultAllocate,
    .read = defaultRead,
};

fn selectedBase(listener: *resources.Listener, comptime file_line: [*:0]const u8,
    comptime function_name: [*:0]const u8) *Base
{
    const resource = listener.stream orelse check.assertion(null, .{
        .file_line = file_line,
        .message = "(stream_) != nullptr",
        .function = function_name,
    });
    return @fieldParentPtr("resource", resource);
}

fn defaultAllocate(listener: *resources.Listener, suggested_size: usize) !uv.uv_buf_t {
    const stream = selectedBase(listener, "src/stream_base.cc:688",
        "node::EmitToJSStreamListener::OnStreamAlloc");
    const environment = stream.environment;
    const allocation = stream.operations.allocation;
    var backing = allocation.new_backing_store(allocation.raw, environment,
        suggested_size, .uninitialized);
    defer c.JS_PiReleaseArrayBufferBackingStore(&backing);
    return environment.adoptManagedBuffer(&backing);
}

fn defaultRead(listener: *resources.Listener, nread: isize, buffer: uv.uv_buf_t) !void {
    const stream = selectedBase(listener, "src/stream_base.cc:694",
        "node::EmitToJSStreamListener::OnStreamRead");
    const environment = stream.environment.retain();
    defer environment.release();
    const engine = try environment.requireEngine();
    var handles = a.Scope.init(engine);
    var backing: managed.Token = std.mem.zeroes(managed.Token);
    var failure: ?anyerror = null;
    readBody(&handles, stream, environment, nread, buffer, &backing) catch |err| {
        recordFailure(&handles, err);
        failure = err;
    };
    // Native backing destruction precedes the enclosing HandleScope, including
    // the <=0 and empty/failed MakeCallback paths. stream may already be dead.
    c.JS_PiReleaseArrayBufferBackingStore(&backing);
    const ignored = try handles.finish(if (failure) |err|
        @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
    engine.freeValue(ignored);
}

fn readBody(handles: *a.Scope, stream: *Base, environment: *callbacks.Environment,
    nread: isize, buffer: uv.uv_buf_t, backing: *managed.Token) !void
{
    backing.* = try environment.releaseManagedBuffer(buffer);
    if (nread <= 0) {
        if (nread < 0) _ = try stream.callJSOnread(handles, nread, null, 0, .check_nread);
        return;
    }

    const length: usize = @intCast(nread);
    const available = c.JS_PiArrayBufferBackingStoreByteLength(backing);
    if (length > available) check.assertion(handles.engine, .{
        .file_line = "src/stream_base.cc:708",
        .message = "(static_cast<size_t>(nread)) <= (bs->ByteLength())",
        .function = "node::EmitToJSStreamListener::OnStreamRead",
    });
    const allocation = stream.operations.allocation;
    const diagnostics = stream.operations.heap_diagnostics;
    if (length != available) {
        var old_backing = backing.*;
        backing.* = std.mem.zeroes(managed.Token);
        defer c.JS_PiReleaseArrayBufferBackingStore(&old_backing);
        backing.* = allocation.new_backing_store(allocation.raw, environment,
            length, .uninitialized);
        const destination = c.JS_PiArrayBufferBackingStoreData(backing);
        const source = c.JS_PiArrayBufferBackingStoreData(&old_backing);
        @memcpy(destination[0..length], source[0..length]);
    }
    // The block above has retired old_backing before the later intrinsic
    // ArrayBuffer wrapper construction, exactly as the original C++ local.
    const array_buffer = try adoptArrayBuffer(handles, backing, diagnostics);
    _ = try stream.callJSOnread(handles, nread, array_buffer, 0, .check_nread);
}

/// The VM's consuming API also releases its input on construction failure.
/// Preserve the original native operand entitlement until this operation's new
/// actual OOM occurrence has reached the genuine terminal owner. Dup is native
/// reference counting only; no box, JS object, or extra allocation is added.
fn adoptArrayBuffer(handles: *a.Scope, backing: *managed.Token,
    diagnostics: ?*const check.Diagnostics) !c.JSValue
{
    const generation = try handles.beforeAllocation();
    var incoming: managed.Token = std.mem.zeroes(managed.Token);
    c.JS_PiDupArrayBufferBackingStore(&incoming, backing);
    const occurrence = c.JS_PiOutOfMemoryOccurrence(handles.engine.runtime);
    const raw = c.JS_PiAdoptArrayBufferBackingStore(handles.engine.context, &incoming);
    if (c.JS_IsException(raw) and
        c.JS_PiOutOfMemoryOccurrence(handles.engine.runtime) != occurrence)
        check.heapOutOfMemory(handles.engine, diagnostics);
    const result = handles.checkedAllocation(raw, generation) catch |err| {
        recordFailure(handles, err);
        c.JS_PiReleaseArrayBufferBackingStore(backing);
        return err;
    };
    c.JS_PiReleaseArrayBufferBackingStore(backing);
    return result;
}

fn recordFailure(s: *a.Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
