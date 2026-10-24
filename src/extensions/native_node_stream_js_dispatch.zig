// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! StreamBase::JSMethod, ReadStartJS/ReadStopJS, Shutdown/UseUserBuffer dispatch,
//! and the fd/bytesRead/bytesWritten accessors from Node v24.13 stream_base.cc.
//!
//! These are callback bodies over the actual wrapper slots and native stream.
//! Public AddMethods/template publication still requires its complete original
//! signature/accessor/constructor owner before that surface can be exposed.
//! The caller supplies its existing Scope; no extra HandleScope is introduced.
const a = @import("native_node_argument_values.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const streams = @import("native_node_stream_base.zig");
const resources = @import("native_node_stream_resource.zig");
const custom = @import("native_node_custom_buffer_listener.zig");
const shutdown = @import("native_node_stream_shutdown.zig");
const writes = @import("native_node_stream_write.zig");
const string_writes = @import("native_node_stream_write_string.zig");
const vector_writes = @import("native_node_stream_writev.zig");
const external = @import("native_node_external_value.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;

pub const Method = enum {
    read_start, read_stop, shutdown, use_user_buffer, write_buffer, writev,
    write_ascii_string, write_latin1_string, write_utf8_string, write_ucs2_string,
};

/// Source JSMethod returns without setting ReturnValue when FromObject is null.
/// In particular, do not apply argument CHECKs, inspect virtuals, or enter the
/// trigger scope for a missing or retired native receiver.
pub fn jsMethod(s: *a.Scope, registry: *wraps.Registry, receiver: c.JSValue,
    method: Method, args: []const c.JSValue) anyerror!c.JSValue
{
    const stream = streams.Base.fromObject(registry, receiver) orelse
        return c.pi_js_undefined();
    const is_alive = stream.virtuals.is_alive orelse
        return error.ActualStreamIsAliveVirtualRequired;
    if (!is_alive(stream))
        return c.JS_NewInt32(s.engine.context, resources.uv.UV_EINVAL);

    // Snapshot the Environment and async id before invoking the native method.
    // The method can delete its own stream: the scope destructor must not read
    // stream, its AsyncWrap, or its virtual table after the invocation.
    const environment = stream.environment.retain();
    defer environment.release();
    if ((try environment.requireEngine()) != s.engine)
        return error.ActualStreamJSMethodEnvironmentMismatch;
    const wrap = stream.virtuals.get_async_wrap(stream) orelse
        return error.ActualStreamJSMethodAsyncWrapRequired;
    const async_id = wrap.async_id;
    if (environment.field(.check).* > 0 and !(async_id >= 0))
        check.assertion(s.engine, .{
            .file_line = "src/env.cc:268",
            .message = "(default_trigger_async_id) >= (0)",
            .function = "node::AsyncHooks::DefaultTriggerAsyncIdScope",
        });
    const saved_trigger = environment.uidField(.default_trigger).*;
    environment.uidField(.default_trigger).* = async_id;
    defer environment.uidField(.default_trigger).* = saved_trigger;

    // Setting a small integer ReturnValue cannot call JavaScript. Restoration
    // runs before the caller retires its local handles, including on failure.
    return c.JS_NewInt32(s.engine.context, try invoke(s, stream, method, args));
}

fn invoke(s: *a.Scope, stream: *streams.Base, method: Method,
    args: []const c.JSValue) anyerror!c_int
{
    return switch (method) {
        .read_start => (stream.virtuals.read_start orelse
            return error.ActualStreamReadStartVirtualRequired)(stream, s),
        .read_stop => (stream.virtuals.read_stop orelse
            return error.ActualStreamReadStopVirtualRequired)(stream),
        .shutdown => blk: {
            const request = a.arg(args, 0);
            if (!c.JS_IsObject(request)) check.assertion(s.engine, .{
                .file_line = "src/stream_base.cc:169",
                .message = "args[0]->IsObject()",
                .function = "node::StreamBase::Shutdown",
            });
            // The JS entry always passes the supplied object. Do not turn an
            // absent argument into Shutdown's distinct native default request.
            break :blk try shutdown.run(s, stream, request);
        },
        .use_user_buffer => custom.useUserBuffer(stream, a.arg(args, 0)),
        .write_buffer => writes.writeBuffer(s, stream, args),
        .writev => vector_writes.writev(s, stream, args),
        .write_ascii_string => string_writes.writeString(s, stream, args, .ascii),
        .write_latin1_string => string_writes.writeString(s, stream, args, .latin1),
        .write_utf8_string => string_writes.writeString(s, stream, args, .utf8),
        .write_ucs2_string => string_writes.writeString(s, stream, args, .ucs2),
    };
}

/// Original GetExternal returns a fresh External for any remaining native
/// stream, including a closed one. It does not consult IsAlive, cache the value,
/// enter a trigger scope, or acquire a native pointer/JS wrapper keepalive.
pub fn getExternal(s: *a.Scope, registry: *wraps.Registry,
    receiver: c.JSValue) !c.JSValue
{
    const stream = streams.Base.fromObject(registry, receiver) orelse
        return c.pi_js_undefined();
    return a.duplicate(s.engine, try external.create(s, @ptrCast(stream)));
}

/// GetFD uses the same FromObject and IsAlive guards, but has no trigger scope.
/// The virtual default is the original -1; concrete streams provide their fd.
pub fn getFD(s: *a.Scope, registry: *wraps.Registry,
    receiver: c.JSValue) anyerror!c.JSValue
{
    const stream = streams.Base.fromObject(registry, receiver) orelse
        return c.JS_NewInt32(s.engine.context, resources.uv.UV_EINVAL);
    const is_alive = stream.virtuals.is_alive orelse
        return error.ActualStreamIsAliveVirtualRequired;
    if (!is_alive(stream))
        return c.JS_NewInt32(s.engine.context, resources.uv.UV_EINVAL);
    return c.JS_NewInt32(s.engine.context, stream.virtuals.get_fd(stream));
}

/// Source reads uint64_t counters even after IsAlive becomes false, then casts
/// to double. JavaScript observes Number rounding, never a BigInt or truncation.
pub fn getBytesRead(s: *a.Scope, registry: *wraps.Registry,
    receiver: c.JSValue) c.JSValue
{
    const stream = streams.Base.fromObject(registry, receiver) orelse
        return c.JS_NewInt32(s.engine.context, 0);
    return c.JS_NewFloat64(s.engine.context,
        @as(f64, @floatFromInt(stream.resource.bytes_read)));
}

pub fn getBytesWritten(s: *a.Scope, registry: *wraps.Registry,
    receiver: c.JSValue) c.JSValue
{
    const stream = streams.Base.fromObject(registry, receiver) orelse
        return c.JS_NewInt32(s.engine.context, 0);
    return c.JS_NewFloat64(s.engine.context,
        @as(f64, @floatFromInt(stream.resource.bytes_written)));
}
