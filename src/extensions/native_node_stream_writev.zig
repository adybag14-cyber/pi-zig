// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original StreamBase::Writev, including its two observable passes, concrete
//! Array/ArrayBufferView brands and actual WriteWrap/backing-token result path.
//! This is a callback body; complete public StreamBase publication stays gated.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const streams = @import("native_node_stream_base.zig");
const writes = @import("native_node_stream_write.zig");
const requests = @import("native_node_stream_request.zig");
const bytes = @import("native_node_stream_string_bytes.zig");
const temporary = @import("native_node_maybe_stack_buffer.zig");
const managed = @import("native_node_managed_buffers.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = managed.uv;

fn arrayBufferView(value: c.JSValue) bool {
    // Buffer::HasInstance in this exact Node authority is IsArrayBufferView,
    // including DataView and non-Uint8 TypedArrays. It does not unwrap proxies.
    return c.JS_GetTypedArrayType(value) >= 0 or c.JS_IsDataView(value);
}
fn buffer(s: *a.Scope, value: c.JSValue) uv.uv_buf_t {
    if (!arrayBufferView(value)) check.assertion(s.engine, .{
        .file_line = "src/node_buffer.cc:250",
        .message = "val->IsArrayBufferView()",
        .function = "node::Buffer::Data",
    });
    return .{
        .base = @ptrCast(c.JS_PiArrayBufferViewData(value)),
        .len = @truncate(c.JS_PiArrayBufferViewByteLength(value)),
    };
}
fn get(s: *a.Scope, array: c.JSValue, index: usize) !c.JSValue {
    try s.pending();
    // Every returned chunk/encoding remains a real local handle through Write,
    // including when later getters replace or delete the original array entry.
    return s.checked(c.JS_GetPropertyUint32(s.engine.context, array, @intCast(index)));
}
fn failed(s: *a.Scope, err: anyerror) anyerror!c_int {
    requests.recordFailure(s, err);
    if (err == error.JavaScriptException and !s.boundary.isFatal()) return -1;
    return err;
}

pub fn writev(s: *a.Scope, stream: *streams.Base,
    args: []const c.JSValue) anyerror!c_int
{
    const object = a.arg(args, 0);
    if (!c.JS_IsObject(object)) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:185",
        .message = "args[0]->IsObject()",
        .function = "node::StreamBase::Writev",
    });
    const chunks = a.arg(args, 1);
    // This QuickJS version's JS_IsArray is a concrete class check, exactly like
    // V8 Value::IsArray. Revoked and live proxies cannot run a length trap here.
    if (!c.JS_IsArray(chunks)) check.assertion(s.engine, .{
        .file_line = "src/stream_base.cc:186",
        .message = "args[1]->IsArray()",
        .function = "node::StreamBase::Writev",
    });
    const all_arg = a.arg(args, 2);
    const all_buffers = c.JS_IsBool(all_arg) and c.JS_ToBool(s.engine.context, all_arg) == 1;
    const length_value = try s.get(chunks, "length");
    var length: u32 = undefined;
    // The concrete Array owns an undeletable data length, so this intrinsic
    // conversion cannot select a getter, proxy trap, or user coercion.
    if (c.JS_ToUint32(s.engine.context, &length, length_value) != 0)
        return error.ActualStreamWritevArrayLengthRequired;
    const count: usize = if (all_buffers) length else length >> 1;
    const environment = stream.environment.retain();
    defer environment.release();
    if ((try environment.requireEngine()) != s.engine)
        return error.ActualStreamWritevEnvironmentMismatch;

    var vectors: temporary.Buffer(uv.uv_buf_t, 16) = undefined;
    try vectors.init(environment, count);
    defer vectors.deinit();
    const buffers = vectors.data();
    var storage_size: usize = 0;
    if (!all_buffers) {
        for (0..count) |index| {
            const chunk = get(s, chunks, index * 2) catch |err| return failed(s, err);
            if (arrayBufferView(chunk)) continue;
            const string = s.toString(chunk) catch |err| return failed(s, err);
            const encoding_value = get(s, chunks, index * 2 + 1) catch |err| return failed(s, err);
            const encoding = bytes.parseEncoding(s, environment, encoding_value) catch |err|
                return failed(s, err);
            const size = bytes.storageSize(s, string, encoding) catch |err| return failed(s, err);
            storage_size +%= size;
        }
        // The complete sizing pass precedes this guard, even if an earlier
        // element already makes the eventual capacity exceed INT_MAX.
        if (storage_size > std.math.maxInt(c_int)) return uv.UV_ENOBUFS;
    } else {
        for (buffers, 0..) |*output, index| {
            const chunk = get(s, chunks, index) catch |err| return failed(s, err);
            output.* = buffer(s, chunk);
        }
    }

    var backing = std.mem.zeroes(managed.Token);
    // Declaration/destruction order: result's native pointer, backing token,
    // vector heap, then the callback's local handles. No per-view async lease.
    defer c.JS_PiReleaseArrayBufferBackingStore(&backing);
    if (storage_size > 0) {
        const allocation = stream.operations.allocation;
        backing = allocation.new_backing_store(allocation.raw, environment,
            storage_size, .uninitialized);
    }
    var offset: usize = 0;
    if (!all_buffers) {
        for (buffers, 0..) |*output, index| {
            const chunk = get(s, chunks, index * 2) catch |err| return failed(s, err);
            if (arrayBufferView(chunk)) {
                output.* = buffer(s, chunk);
                continue;
            }
            if (offset > storage_size) check.assertion(s.engine, .{
                .file_line = "src/stream_base.cc:266",
                .message = "(offset) <= (storage_size)",
                .function = "node::StreamBase::Writev",
            });
            const data = c.JS_PiArrayBufferBackingStoreData(&backing);
            // Source's null + zero denotes an empty buffer; avoid applying Zig
            // pointer arithmetic to null while preserving that exact uv_buf_t.
            const destination = if (data == null) data else data + offset;
            const capacity = c.JS_PiArrayBufferBackingStoreByteLength(&backing) - offset;
            const string = s.toString(chunk) catch |err| return failed(s, err);
            const encoding_value = get(s, chunks, index * 2 + 1) catch |err| return failed(s, err);
            const encoding = bytes.parseEncoding(s, environment, encoding_value) catch |err|
                return failed(s, err);
            const size = bytes.write(s, environment, string, encoding,
                destination, capacity) catch |err| return failed(s, err);
            output.* = .{ .base = @ptrCast(destination), .len = @intCast(size) };
            offset += size;
        }
    }

    var result = try writes.run(s, stream, buffers, null, object, false);
    writes.setResult(environment, &result);
    if (result.wrap) |request| {
        if (storage_size > 0) request.setBackingStore(&backing);
    }
    const status = result.err;
    result.release(s) catch |err| {
        requests.recordFailure(s, err);
        if (err != error.JavaScriptException or s.boundary.isFatal()) return err;
    };
    return status;
}
