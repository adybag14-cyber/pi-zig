// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual four-encoding StreamBase::WriteString from stream_base.cc:337-443.
//! This consumes an actual primitive String view and the existing native Write
//! result/request owner. It publishes no public StreamBase or FileHandle surface.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const streams = @import("native_node_stream_base.zig");
const writes = @import("native_node_stream_write.zig");
const requests = @import("native_node_stream_request.zig");
const managed = @import("native_node_managed_buffers.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = managed.uv;

pub const Encoding = enum { ascii, latin1, utf8, ucs2 };

fn unit(view: *const c.JSPiStringView, position: usize) u16 {
    return if (view.data8 != null) view.data8[position] else view.data16[position];
}
fn scalar(view: *const c.JSPiStringView, position: *usize) u21 {
    const first = unit(view, position.*);
    position.* += 1;
    if (first >= 0xd800 and first <= 0xdbff) {
        if (position.* < view.length) {
            const second = unit(view, position.*);
            if (second >= 0xdc00 and second <= 0xdfff) {
                position.* += 1;
                return 0x10000 + ((@as(u21, first) - 0xd800) << 10) +
                    (@as(u21, second) - 0xdc00);
            }
        }
        return 0xfffd;
    }
    if (first >= 0xdc00 and first <= 0xdfff) return 0xfffd;
    return first;
}
fn utf8Width(point: u21) usize {
    return if (point < 0x80) 1 else if (point < 0x800) 2
        else if (point < 0x10000) 3 else 4;
}
fn exactUtf8Size(view: *const c.JSPiStringView) usize {
    var position: usize = 0;
    var size: usize = 0;
    while (position < view.length) size +%= utf8Width(scalar(view, &position));
    return size;
}
fn storageSize(view: *const c.JSPiStringView, comptime encoding: Encoding) usize {
    // Preserve the actual Source boolean expression, not its preceding comment:
    // for long UTF8, Size succeeds and StorageSize is still evaluated afterward.
    // This selected primitive-string path cannot invoke ToString or throw.
    if (encoding == .utf8 and view.length > 65535) _ = exactUtf8Size(view);
    return view.length *% switch (encoding) {
        .ascii, .latin1 => @as(usize, 1),
        .ucs2 => @as(usize, 2),
        .utf8 => @as(usize, 3),
    };
}
fn encodeScalar(output: [*c]u8, point: u21) usize {
    if (point < 0x80) {
        output[0] = @intCast(point);
        return 1;
    }
    if (point < 0x800) {
        output[0] = @intCast(0xc0 | (point >> 6));
        output[1] = @intCast(0x80 | (point & 0x3f));
        return 2;
    }
    if (point < 0x10000) {
        output[0] = @intCast(0xe0 | (point >> 12));
        output[1] = @intCast(0x80 | ((point >> 6) & 0x3f));
        output[2] = @intCast(0x80 | (point & 0x3f));
        return 3;
    }
    output[0] = @intCast(0xf0 | (point >> 18));
    output[1] = @intCast(0x80 | ((point >> 12) & 0x3f));
    output[2] = @intCast(0x80 | ((point >> 6) & 0x3f));
    output[3] = @intCast(0x80 | (point & 0x3f));
    return 4;
}
/// This private leaf is only called with the full fixed-encoding StorageSize.
/// Writev's mutable two-pass sizing and base64/hex decoder are separate work.
fn encode(view: *const c.JSPiStringView, output: [*c]u8,
    comptime encoding: Encoding) usize
{
    if (encoding == .ascii or encoding == .latin1) {
        for (0..view.length) |position| output[position] = @truncate(unit(view, position));
        return view.length;
    }
    if (encoding == .ucs2) {
        // StringBytes::WriteUCS2 explicitly emits LE, including lone surrogates.
        for (0..view.length) |position| {
            const value = unit(view, position);
            output[position * 2] = @truncate(value);
            output[position * 2 + 1] = @intCast(value >> 8);
        }
        return view.length * 2;
    }
    var position: usize = 0;
    var size: usize = 0;
    while (position < view.length) {
        const point = scalar(view, &position);
        size += encodeScalar(output + size, point);
    }
    return size;
}

/// Callback body after the real JSMethod receiver/alive/trigger guards.
/// Byte counters record the direct try-write shortcut separately from Write.
/// The unique backing token moves only to the actually returned WriteWrap.
pub fn writeString(s: *a.Scope, stream: *streams.Base,
    args: []const c.JSValue, comptime encoding: Encoding) anyerror!c_int
{
    const object = a.arg(args, 0);
    if (!c.JS_IsObject(object)) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:340",
        .message = "args[0]->IsObject()",
        .function = "node::StreamBase::WriteString",
    });
    const input = a.arg(args, 1);
    if (!c.JS_IsString(input)) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:341",
        .message = "args[1]->IsString()",
        .function = "node::StreamBase::WriteString",
    });
    // ValueView uses actual primitive-string flattening before borrowing data.
    // JS_ToString cannot select guest coercion after the native String CHECK.
    // Its owned flat result pins normal/sliced/indirect storage through every
    // allocation retry, init hook and callback in the existing Write owner.
    const generation = try s.beforeAllocation();
    const string = try s.checkedAllocation(c.JS_ToString(s.engine.context, input), generation);
    var view: c.JSPiStringView = undefined;
    if (c.JS_PiBorrowFlatStringView(string, &view) != 1)
        return error.ActualStreamPrimitiveStringViewRequired;
    const handle_object = a.arg(args, 2);
    const has_handle_object = c.JS_IsObject(handle_object);
    const storage_size = storageSize(&view, encoding);
    if (storage_size > std.math.maxInt(c_int)) return uv.UV_ENOBUFS;

    const environment = stream.environment.retain();
    defer environment.release();
    if ((try environment.requireEngine()) != s.engine)
        return error.ActualStreamStringEnvironmentMismatch;

    var stack_storage: [16384]u8 = undefined;
    var data_size: usize = 0;
    var synchronously_written: usize = 0;
    var buffer: [1]uv.uv_buf_t = undefined;
    const try_write = stream.virtuals.has_do_try_write(stream) and
        storage_size <= stack_storage.len and
        (!stream.virtuals.is_ipc_pipe(stream) or !has_handle_object);
    if (try_write) {
        data_size = encode(&view, @ptrCast(&stack_storage), encoding);
        buffer[0] = uv.uv_buf_init(@ptrCast(&stack_storage), @intCast(data_size));
        var remaining: []uv.uv_buf_t = &buffer;
        const status = try stream.virtuals.do_try_write(stream, s, &remaining);
        synchronously_written = if (remaining.len == 0) data_size else
            data_size -% @as(usize, buffer[0].len);
        stream.resource.bytes_written +%= @as(u64, synchronously_written);
        if (status != 0 or remaining.len == 0) {
            const result: writes.Result = .{ .err = status, .bytes = data_size };
            writes.setResult(environment, &result);
            return status;
        }
        if (remaining.len != 1) check.assertion(s.engine, .{
            .file_line = "src/stream_base.cc:395",
            .message = "(count) == (1)",
            .function = "node::StreamBase::WriteString",
        });
    }

    var backing = std.mem.zeroes(managed.Token);
    // Source declares bs before res: res's native pointer retires first, then
    // any token that was not transferred retires before callback handles.
    defer c.JS_PiReleaseArrayBufferBackingStore(&backing);
    const allocation = stream.operations.allocation;
    if (try_write) {
        const remaining_bytes: usize = buffer[0].len;
        backing = allocation.new_backing_store(allocation.raw, environment,
            remaining_bytes, .uninitialized);
        if (remaining_bytes != 0) {
            const destination = c.JS_PiArrayBufferBackingStoreData(&backing);
            const source: [*]const u8 = @ptrCast(buffer[0].base);
            @memcpy(destination[0..remaining_bytes], source[0..remaining_bytes]);
        }
        data_size = remaining_bytes;
    } else {
        backing = allocation.new_backing_store(allocation.raw, environment,
            storage_size, .uninitialized);
        data_size = encode(&view, c.JS_PiArrayBufferBackingStoreData(&backing), encoding);
    }
    if (data_size > storage_size) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:417",
        .message = "(data_size) <= (storage_size)",
        .function = "node::StreamBase::WriteString",
    });
    buffer[0] = uv.uv_buf_init(
        @ptrCast(c.JS_PiArrayBufferBackingStoreData(&backing)), @intCast(data_size));

    var send_handle: ?*uv.uv_stream_t = null;
    if (stream.virtuals.is_ipc_pipe(stream) and has_handle_object) {
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

    var result = try writes.run(s, stream, &buffer, send_handle, object, try_write);
    result.bytes +%= synchronously_written;
    writes.setResult(environment, &result);
    if (result.wrap) |request| request.setBackingStore(&backing);
    const status = result.err;
    result.release(s) catch |err| {
        requests.recordFailure(s, err);
        if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
    };
    return status;
}
