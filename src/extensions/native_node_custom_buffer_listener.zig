// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual CustomBufferJSListener and the already-admitted UseUserBuffer body.
//! The listener stores only the native StreamListener and caller-borrowed
//! uv_buf_t. It owns no JS value or backing-store entitlement. The caller keeps
//! the supplied view/storage alive and valid through every native read.
//!
//! Full FunctionTemplate receiver admission, JSMethod liveness/outer trigger,
//! public method publication and the write-request reporter remain separate.
//! The actual selected Shutdown reporter is used directly, not forwarded.
const a = @import("native_node_argument_values.zig");
const streams = @import("native_node_stream_base.zig");
const resources = @import("native_node_stream_resource.zig");
const shutdown = @import("native_node_stream_shutdown.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = resources.uv;
const BufferBase = @TypeOf(@as(uv.uv_buf_t, undefined).base);

extern fn pi_node_custom_buffer_listener_allocate(
    ?*c.JSContext, *anyopaque, usize, usize) *anyopaque;
extern fn pi_node_custom_buffer_listener_free(
    ?*c.JSContext, *anyopaque) void;

/// Native instance storage is created by the genuine standard-new policy.
/// This record must remain at its allocated address until OnStreamDestroy.
/// It never retains the Engine, JS view, or the view's native backing owner.
pub const CustomBufferJSListener = struct {
    listener: resources.Listener,
    buffer: uv.uv_buf_t,

    fn create(engine: *a.v.em.Engine, buffer: uv.uv_buf_t) *CustomBufferJSListener {
        const storage = pi_node_custom_buffer_listener_allocate(
            engine.context, engine.native_memory_owner,
            @sizeOf(CustomBufferJSListener), @alignOf(CustomBufferJSListener));
        const self: *CustomBufferJSListener = @ptrCast(@alignCast(storage));
        self.* = .{
            .listener = .{
                .on_destroy = onDestroy,
                .read_methods = &read_methods,
                .after_shutdown = shutdown.reportAfterShutdown,
            },
            .buffer = buffer,
        };
        return self;
    }

    fn onDestroy(listener: *resources.Listener) void {
        const self: *CustomBufferJSListener = @fieldParentPtr("listener", listener);
        const context = if (listener.stream) |stream| stream.engine.context else null;
        // delete this destroys the StreamListener base before freeing storage.
        listener.deinit();
        pi_node_custom_buffer_listener_free(context, self);
    }

    fn onAllocate(listener: *resources.Listener, _: usize) !uv.uv_buf_t {
        const self: *CustomBufferJSListener = @fieldParentPtr("listener", listener);
        // Source deliberately ignores suggested_size and does not replace or
        // acquire the user's backing store.
        return self.buffer;
    }

    fn onRead(listener: *resources.Listener, nread: isize,
        incoming: uv.uv_buf_t) !void
    {
        const resource = listener.stream orelse check.assertion(null, .{
            .file_line = "src/stream_base.cc:726",
            .message = "(stream_) != nullptr",
            .function = "node::CustomBufferJSListener::OnStreamRead",
        });
        const stream: *streams.Base = @fieldParentPtr("resource", resource);
        const environment = stream.environment.retain();
        defer environment.release();
        const engine = try environment.requireEngine();
        var handles = a.Scope.init(engine);
        var failure: ?anyerror = null;
        readBody(&handles, listener, stream, nread, incoming) catch |err| {
            recordFailure(&handles, err);
            failure = err;
        };
        // The callback can retire the stream/listener on its undefined or
        // empty-result path. Only the retained local Environment/Scope is used
        // here; neither native record is touched after readBody returns.
        const ignored = try handles.finish(if (failure) |err|
            @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
        engine.freeValue(ignored);
    }

    const read_methods: resources.ReadMethods = .{
        .allocate = onAllocate,
        .read = onRead,
    };
};

fn readBody(handles: *a.Scope, listener: *resources.Listener,
    stream: *streams.Base, nread: isize, incoming: uv.uv_buf_t) !void
{
    // Original null-buffer error/EOF branch neither compares buffer_.base nor
    // consumes any non-undefined callback result as a replacement buffer.
    if (incoming.base == null and nread < 0) {
        _ = try stream.callJSOnread(handles, nread, null, 0, .check_nread);
        return;
    }
    const self: *CustomBufferJSListener = @fieldParentPtr("listener", listener);
    if (incoming.base != self.buffer.base) check.assertion(handles.engine, .{
        .file_line = "src/stream_base.cc:741",
        .message = "(buf.base) == (buffer_.base)",
        .function = "node::CustomBufferJSListener::OnStreamRead",
    });
    const result = try stream.callJSOnread(handles, nread, null, 0,
        .skip_nread_checks);
    if (result) |next| {
        if (!c.JS_IsUndefined(next)) {
            // These two operations retain their own original Buffer CHECKs.
            // The source writes base first, then the native uv_buf_t.len field;
            // unlike initial uv_buf_init, this is not always unsigned-int wide.
            self.buffer.base = bufferData(handles.engine, next);
            self.buffer.len = @truncate(bufferLength(handles.engine, next));
        }
    }
}

/// The actual VM class predicates, without getters or a property-name test.
/// A live empty view still has the proper brand; Data()==NULL is not branding.
fn hasBufferInstance(value: c.JSValue) bool {
    return c.JS_GetTypedArrayType(value) >= 0 or c.JS_IsDataView(value);
}

fn bufferData(engine: *a.v.em.Engine, value: c.JSValue) BufferBase {
    if (!hasBufferInstance(value)) check.assertion(engine, .{
        .file_line = "src/node_buffer.cc:250",
        .message = "val->IsArrayBufferView()",
        .function = "node::Buffer::Data",
    });
    return @ptrCast(c.JS_PiArrayBufferViewData(value));
}

fn bufferLength(engine: *a.v.em.Engine, value: c.JSValue) usize {
    if (!hasBufferInstance(value)) check.assertion(engine, .{
        .file_line = "src/node_buffer.cc:262",
        .message = "val->IsArrayBufferView()",
        .function = "node::Buffer::Length",
    });
    return c.JS_PiArrayBufferViewByteLength(value);
}

/// Source StreamBase::UseUserBuffer after its genuine public receiver and VM
/// entry have already been admitted. The value belongs to stream's actual VM.
/// This body has no new pending/JS-allocation boundary: CHECK, Data/Length,
/// native standard allocation and listener publication are the original order.
pub fn useUserBuffer(stream: *streams.Base, value: c.JSValue) c_int {
    const engine = stream.resource.engine;
    if (!hasBufferInstance(value)) check.assertion(engine, .{
        .file_line = "src/stream_base.cc:161",
        .message = "Buffer::HasInstance(args[0])",
        .function = "node::StreamBase::UseUserBuffer",
    });
    const address = bufferData(engine, value);
    const length = bufferLength(engine, value);
    // The actual libuv function takes unsigned int even on 64-bit Unix.
    const buffer = uv.uv_buf_init(address, @truncate(length));
    const listener = CustomBufferJSListener.create(engine, buffer);
    stream.resource.push(&listener.listener);
    return 0;
}

fn recordFailure(s: *a.Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
