// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node v24.13 FileHandle::Close: stack-native synchronous uv_fs_close followed
//! by a real Environment native immediate. A ticket owns only native captures;
//! it never stores a JSValue, a FileHandle pointer, or an Engine entitlement.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const immediates = @import("native_node_native_immediates.zig");
const io = @import("native_node_fs_request_io.zig");
const warning = @import("native_node_process_warning.zig");
const uv_exception = @import("native_node_uv_exception.zig");
const check = @import("native_node_check_failure.zig");
const c = a.c;
const native_uv = @import("native_node_stream_resource.zig").uv;
const uv = io.uv;
const Scope = a.Scope;
const Engine = a.v.em.Engine;

const deprecation =
    "Closing a FileHandle object on garbage collection is deprecated. " ++
    "Please close FileHandle objects explicitly using " ++
    "FileHandle.prototype.close(). In the future, an error will be " ++
    "thrown if a file descriptor is closed during garbage collection.";

const Ticket = struct {
    task: immediates.Task,
    environment: *callbacks.Environment,
    result: c_int,
    descriptor: c_int,

    fn fromTask(task: *immediates.Task) *Ticket {
        return @alignCast(@fieldParentPtr("task", task));
    }
    fn run(engine: *Engine, task: *immediates.Task) !void {
        const self = fromTask(task);
        if ((try self.environment.requireEngine()) != engine)
            return error.ActualFileHandleGcImmediateEnvironmentMismatch;
        const ignored = try a.expression(engine, body, .{self});
        engine.freeValue(ignored);
    }
    fn body(s: *Scope, self: *Ticket) !c.JSValue {
        if (self.result < 0) {
            // Original snprintf uses a 70-byte native stack buffer. Every
            // signed native-int descriptor fits this exact selected format.
            var buffer: [70]u8 = undefined;
            const message = std.fmt.bufPrint(&buffer,
                "Closing file descriptor {d} on garbage collection failed",
                .{self.descriptor}) catch unreachable;
            const reason = try s.own(try uv_exception.create(s.engine, .{
                .code = self.result, .syscall = "close", .message = message,
            }));
            // Native immediate queue owns the real catch/uncaught policy.
            // This is the original ThrowUVException, not a fabricated abort
            // or classification of a returned Error as an exception.
            return a.raise(s, reason);
        }

        const environment = self.environment;
        const formatted = try warning.formatFileHandleGcWarning(
            environment.allocator(), self.descriptor);
        var warning_failure: ?anyerror = null;
        _ = warning.emitFormattedWarning(environment, formatted) catch |err| result: {
            record(s, err);
            warning_failure = err;
            break :result false;
        };
        // ProcessEmitWarning's formatted native string is destroyed before
        // the later Environment flag test and optional deprecation call.
        environment.allocator().free(formatted);
        if (warning_failure) |err| if (!canContinue(s, err)) return err;

        // This flag belongs to the actual Environment, initially true. It is
        // consumed before calling the live process.emitWarning again, so
        // reentrant GC callbacks observe the original one-shot transition.
        if (environment.emit_filehandle_warning) {
            environment.emit_filehandle_warning = false;
            _ = warning.emitDeprecationWarning(environment, deprecation,
                "DEP0137") catch |err| ignored: {
                record(s, err);
                if (!canContinue(s, err)) return err;
                break :ignored false;
            };
        }
        return c.pi_js_undefined();
    }
    fn destroy(task: *immediates.Task) void {
        const self = fromTask(task);
        const environment = self.environment;
        environment.allocator().destroy(self);
        environment.release();
    }
};

/// Called by the concrete derived destructor while its native owners still
/// exist. The helper uses the retained real service's loop and caller-owned
/// canonical uv_fs_t. No command, request wrapper, callback, or worker lease
/// participates in this synchronous operation.
pub fn close(s: *Scope, handle: anytype) !void {
    const state = handle.getReadState();
    if (state.closed or state.closing) return;
    if (state.fd == -1) check.assertion(s.engine, .{
        .file_line = "src/node_file.cc:343",
        .message = "(fd_) != (-1)",
        .function = "node::fs::FileHandle::Close",
    });
    const environment = handle.getAsyncWrap().registry.environment;
    const inputs = handle.getReadInputs();
    const trace = handle.getCloseTrace();
    var request: native_uv.uv_fs_t = undefined;
    trace.begin_sync(trace.raw);
    const result = uv.pi_uv_fs_close_sync(inputs.controller.service,
        @ptrCast(&request), state.fd);
    trace.end_sync(trace.raw);
    native_uv.uv_fs_req_cleanup(&request);

    // Capture both scalars before AfterClose changes fd_ to -1 or emits EOF.
    const descriptor = state.fd;
    handle.afterClose() catch |err| {
        record(s, err);
        if (!canContinue(s, err)) return err;
    };

    // Source SetImmediate allocates its native callback after AfterClose.
    // Queue.enqueue consumes the ticket even after queue disarm; unrefed
    // cleanup skips run but always destroys these native captures.
    const ticket = try environment.allocator().create(Ticket);
    ticket.* = .{
        .task = .{ .refed = result < 0, .run = Ticket.run, .destroy = Ticket.destroy },
        .environment = environment.retain(),
        .result = result,
        .descriptor = descriptor,
    };
    handle.getImmediateQueue().enqueue(&ticket.task);
}

fn canContinue(s: *Scope, err: anyerror) bool {
    return err == error.JavaScriptException and !s.boundary.isFatal();
}
fn record(s: *Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
