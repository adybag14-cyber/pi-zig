// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.13 FileHandle::ReadStart/ReadStop and the original read completion.
//!
//! This is the native read portion of the concrete FileHandle source port. The
//! Handle parameter supplies the SAME AsyncWrap, StreamBase, BindingData and
//! original fields; this module creates no second handle or ownership graph.
//! Handle.getReadState() returns State, getReadInputs() returns Inputs,
//! getStreamBase()/getAsyncWrap()/getBindingData() return their real owners.
//! NewInstance uses the genuine stored FSReqCallback template directly.
//! Its assembler must configure the same real shared Controller beforehand.
//!
//! Concrete FileHandle close/GC/transfer ownership and the production trace
//! and backing-allocation controllers remain explicit integration obligations.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const requests = @import("native_node_request_state.zig");
const read_wrap = @import("native_node_file_handle_read_wrap.zig");
const templates = @import("native_node_async_wrap.zig");
const io = @import("native_node_fs_request_io.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const uv = io.uv;
const native_uv = @import("native_node_stream_resource.zig").uv;

/// The original FS_ASYNC_TRACE_BEGIN0/END1 operations, compiled by the actual
/// native trace owner. The identity is FileHandleReadWrap*, not uv_fs_t*.
/// A disabled category is handled by that owner, never by a substitute here.
pub const Trace = struct {
    raw: ?*anyopaque,
    begin_read: *const fn (?*anyopaque, *anyopaque) void,
    end_read: *const fn (?*anyopaque, *anyopaque, c_int) void,
};

/// Borrowed Environment/isolate inputs; the concrete FileHandle keeps their
/// actual owners alive. handle_string is the original cached "handle" string,
/// so recycling does not allocate a replacement property key.
pub const Inputs = struct {
    controller: *io.Controller,
    handle_string: c.JSValue,
    trace: Trace,
};

pub fn Type(comptime Handle: type) type {
    return struct {
        pub const ReadWrap = read_wrap.Type(Handle);

        /// These are the original native FileHandle members. The concrete
        /// owner uses these SAME flags/fd for close and transfer operations.
        pub const State = struct {
            fd: c_int,
            closing: bool = false,
            closed: bool = false,
            reading: bool = false,
            read_offset: i64 = -1,
            read_length: i64 = -1,
            current_read: ?*ReadWrap = null,
        };

        /// The caller's native Scope owns pending completion, not the emitted
        /// buffer or FileHandle. The only actual JS locals allocated here live
        /// in acquireWrap's inner Source HandleScope.
        pub fn start(s: *a.Scope, handle: *Handle) !c_int {
            const state = handle.getReadState();
            if (state.closed or state.closing) return native_uv.UV_EOF;
            state.reading = true;
            if (state.current_read != null) return 0;
            if (state.read_length == 0) {
                handle.getStreamBase().resource.emitRead(
                    native_uv.UV_EOF, std.mem.zeroes(native_uv.uv_buf_t)) catch |err| {
                    record(s, err);
                    if (!canContinue(s, err)) return err;
                };
                return 0;
            }

            var selected: ?*ReadWrap = try acquireWrap(s, handle);
            if (selected == null) return native_uv.UV_EBUSY;
            errdefer if (selected) |request| releasePreserving(s, request);
            const request = selected.?;
            var recommended_read: i64 = 65536;
            if (state.read_length >= 0 and state.read_length <= recommended_read)
                recommended_read = state.read_length;
            request.buffer = try handle.getStreamBase().resource.emitAlloc(
                @intCast(recommended_read));

            // The Source move precedes tracing and actual libuv admission.
            state.current_read = request;
            selected = null;
            const inputs = handle.getReadInputs();
            inputs.trace.begin_read(inputs.trace.raw, request);
            // Original ReadStart deliberately ignores immediate negative
            // Dispatch. It does not synthesize a callback, free the buffer,
            // clear current_read_, or change reading_ at this point.
            _ = try inputs.controller.dispatchRawRead(s, &request.entry,
                request.actual orelse return error.ActualFileHandleReadRequestRequired,
                state.fd, if (request.buffer.base == null) null else
                    @as([*]u8, @ptrCast(request.buffer.base)),
                request.buffer.len, state.read_offset, completed);
            return 0;
        }

        /// ReadStop is a flag change only. An accepted read still delivers its
        /// real completion; stopping does not invoke uv_cancel or drop a span.
        pub fn stop(handle: *Handle) c_int {
            handle.getReadState().reading = false;
            return 0;
        }

        /// Source FileHandle::AfterClose uses the same fields as ReadStart.
        /// Its caller owns descriptor closure and native object lifetime.
        pub fn afterClose(handle: *Handle) !void {
            const state = handle.getReadState();
            state.closing = false;
            state.closed = true;
            state.fd = -1;
            if (state.reading and handle.getAsyncWrap().object() != null)
                try handle.getStreamBase().resource.emitRead(
                    native_uv.UV_EOF, std.mem.zeroes(native_uv.uv_buf_t));
        }

        fn acquireWrap(s: *a.Scope, handle: *Handle) !?*ReadWrap {
            const native = handle.getAsyncWrap();
            const environment = native.registry.environment;
            const inputs = handle.getReadInputs();
            if ((try environment.requireEngine()) != s.engine or
                inputs.controller.environment != environment or
                handle.getBindingData().environment != environment)
                return error.ActualFileHandleReadEnvironmentMismatch;

            var locals = a.Scope.init(s.engine);
            var selected: ?*ReadWrap = null;
            var failure: ?anyerror = null;

            // DefaultTriggerAsyncIdScope is constructed after HandleScope,
            // and destroyed before its local roots retire.
            if (environment.field(.check).* > 0 and native.async_id < 0)
                check.assertion(s.engine, .{
                    .file_line = "src/env.cc:268",
                    .message = "(default_trigger_async_id) >= (0)",
                    .function = "node::AsyncHooks::DefaultTriggerAsyncIdScope",
                });
            const old_trigger = environment.uidField(.default_trigger).*;
            environment.uidField(.default_trigger).* = native.async_id;
            acquireBody(&locals, handle, &selected) catch |err| {
                record(&locals, err);
                failure = err;
            };
            environment.uidField(.default_trigger).* = old_trigger;
            const ignored = locals.finish(if (failure) |err|
                @as(anyerror!c.JSValue, err) else c.pi_js_undefined()) catch |err| {
                record(s, err);
                // An ordinary pending exception does not turn the original
                // void AsyncReset/constructor continuation into a host abort.
                // A failed template with no request follows ToLocal -> EBUSY.
                if (err == error.JavaScriptException and !s.boundary.isFatal())
                    return selected;
                if (selected) |request| releasePreserving(s, request);
                return err;
            };
            s.engine.freeValue(ignored);
            return selected;
        }

        fn acquireBody(s: *a.Scope, handle: *Handle, selected: *?*ReadWrap) !void {
            const data = handle.getBindingData();
            const inputs = handle.getReadInputs();
            if (data.file_handle_read_wrap_freelist.items.len != 0) {
                const index = data.file_handle_read_wrap_freelist.items.len - 1;
                const native = data.file_handle_read_wrap_freelist.items[index];
                data.file_handle_read_wrap_freelist.items.len = index;
                const request: *ReadWrap = @alignCast(@fieldParentPtr("wrap", native));
                selected.* = request; // move one original BaseObjectPtr
                const resource = try s.object();
                const wrapper = request.wrap.object() orelse
                    return error.ActualFileHandleReadWrapObjectRequired;
                try s.pending();
                const status = c.JS_SetPropertyValue(s.engine.context, resource,
                    a.duplicate(s.engine, inputs.handle_string),
                    a.duplicate(s.engine, wrapper), 0);
                s.pending() catch |err| {
                    record(s, err);
                    if (!canContinue(s, err)) return err;
                };
                // A normal false Set is ignored by USE(Maybe<bool>).
                if (status < 0 and s.boundary.reason == null)
                    return error.ActualFileHandleReadResourceSetReasonRequired;
                request.wrap.reset(resource, -1) catch |err| {
                    record(s, err);
                    if (!canContinue(s, err)) return err;
                };
                request.file_handle = handle;
                return;
            }

            // node_file.cc stores fst->InstanceTemplate(), where fst is the
            // genuine FSReqCallback callback template. This actual template
            // operation bypasses its callback but keeps its prototype/brand.
            const wrapper = try templates.newFSReqCallbackInstance(s, data.template_owner);
            selected.* = try ReadWrap.createDetached(s, inputs.controller, handle, wrapper);
        }

        fn completed(entry: *requests.Entry, actual_raw: *anyopaque) !void {
            const request = ReadWrap.fromEntry(entry);
            const actual: *uv.PiUvFsRequest = @ptrCast(@alignCast(actual_raw));
            const info = uv.pi_uv_fs_request_info(actual);
            const handle = request.file_handle;
            const inputs = handle.getReadInputs();
            inputs.trace.end_read(inputs.trace.raw, request, @truncate(info.result));
            const state = handle.getReadState();
            if (state.current_read != request)
                check.assertion(try entry.wrap.registry.environment.requireEngine(), .{
                    .file_line = "src/node_file.cc:610",
                    .message = "(handle->current_read_.get()) == (req_wrap)",
                    .function = "node::fs::FileHandle::ReadStart callback",
                });

            // The actual Wrapper already owns another native pointer. Moving
            // this member to a local makes a reentrant ReadStart see no read.
            var local_request = state.current_read;
            state.current_read = null;
            var result: isize = @intCast(info.result);
            const buffer = request.buffer;
            uv.pi_uv_fs_request_cleanup(actual);

            const environment = entry.wrap.registry.environment;
            const engine = try environment.requireEngine();
            var completion = a.Scope.init(engine);
            var failure: ?anyerror = null;
            completeBody(&completion, handle, &local_request, &result, buffer) catch |err| {
                record(&completion, err);
                failure = err;
            };
            // Full freelist retains no extra pointer. If it was already full,
            // the Source local is destroyed AFTER EmitRead and the restart.
            if (local_request) |remaining| {
                local_request = null;
                remaining.release() catch |err| {
                    record(&completion, err);
                    if (failure == null) failure = err;
                };
            }
            const ignored = try completion.finish(if (failure) |err|
                @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
            engine.freeValue(ignored);
        }

        fn completeBody(s: *a.Scope, handle: *Handle,
            local_request: *?*ReadWrap, result: *isize, buffer: native_uv.uv_buf_t) !void
        {
            const data = handle.getBindingData();
            if (data.file_handle_read_wrap_freelist.items.len < 100) {
                const request = local_request.*.?;
                try request.reset();
                try data.file_handle_read_wrap_freelist.append(
                    data.environment.allocator(), &request.wrap);
                local_request.* = null;
            }

            const state = handle.getReadState();
            if (result.* >= 0) {
                if (state.read_length >= 0 and state.read_length < result.*)
                    result.* = @intCast(state.read_length);
                if (state.read_length >= 0) state.read_length -= result.*;
                if (state.read_offset >= 0) state.read_offset += result.*;
            }
            if (result.* == 0) result.* = native_uv.UV_EOF;
            handle.getStreamBase().resource.emitRead(result.*, buffer) catch |err| {
                record(s, err);
                if (!canContinue(s, err)) return err;
            };

            // Inspect the live flag AFTER EmitRead. The listener may have
            // stopped, closed, or synchronously restarted the same stream.
            if (handle.getReadState().reading)
                _ = try start(s, handle);
        }

        fn canContinue(s: *a.Scope, err: anyerror) bool {
            return err == error.JavaScriptException and !s.boundary.isFatal();
        }
        fn record(s: *a.Scope, err: anyerror) void {
            s.boundary.escaping();
            if (err == error.OutOfMemory and !s.boundary.isFatal()) {
                _ = s.engine.throwNativeOutOfMemoryFatal();
                s.boundary.escaping();
            }
        }
        fn releasePreserving(s: *a.Scope, request: *ReadWrap) void {
            request.release() catch |err| record(s, err);
        }
    };
}
