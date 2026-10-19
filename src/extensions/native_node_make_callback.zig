// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Original Node24.13 InternalMakeCallback over the actual Environment.
//! Inputs are borrowed caller-local handles. A nonempty return is owned; null
//! is the Source empty MaybeLocal without an invented exception.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const c = a.c;

/// This call does not implement public MakeCallback overloads or an
/// uncaught-exception policy. The genuine caller owns those Source boundaries.
pub fn call(environment: *callbacks.Environment, resource: c.JSValue,
    receiver: c.JSValue, callback: c.JSValue, arguments: []const c.JSValue,
    context: callbacks.AsyncContext, frame: c.JSValue) !?c.JSValue
{
    const engine = try environment.requireEngine();
    var handles = a.Scope.init(engine);
    var scope: callbacks.Scope = undefined;
    scope.initialized = false;
    var result: ?c.JSValue = null;
    var failure: ?anyerror = null;
    if (body(&handles, &scope, environment, resource, receiver,
        callback, arguments, context, frame)) |value|
    {
        result = value;
    } else |err| {
        // Record the actual failed call before scope, native args, or local
        // handle retirement. No returned Error is classified as a throw.
        handles.boundary.escaping();
        failure = err;
        if (scope.initialized) scope.markFailed();
    }
    if (scope.initialized and !scope.deinitialized) {
        scope.deinit() catch |err| {
            handles.boundary.escaping();
            if (failure == null) failure = err;
        };
    }
    const empty = result == null;
    const completed: anyerror!c.JSValue = if (failure) |err| err
        else result orelse c.pi_js_undefined();
    // A failed destructor also retires a formerly successful return.
    var values = [_]c.JSValue{result orelse c.pi_js_undefined()};
    if (failure != null) {
        try handles.boundary.finishMany(failure, &handles.values, &values);
        unreachable;
    }
    const value = try handles.finish(completed);
    if (empty) {
        engine.freeValue(value);
        return null;
    }
    return value;
}

fn body(handles: *a.Scope, scope: *callbacks.Scope,
    environment: *callbacks.Environment, resource: c.JSValue,
    receiver: c.JSValue, callback: c.JSValue, arguments: []const c.JSValue,
    context: callbacks.AsyncContext, frame: c.JSValue) !?c.JSValue
{
    if (!c.JS_IsObject(receiver))
        return environment.operations.native_check_failure(environment, .invalid_resource);
    // The selected Local<Function> precedes the constructor's before hook.
    // A hook may replace the Environment's persistent trampoline during init.
    const trampoline: ?c.JSValue = if (environment.trampoline) |value|
        try handles.own(a.duplicate(handles.engine, value)) else null;
    var flags: callbacks.Flags = .{};
    var use_trampoline = false;
    if (trampoline != null) {
        flags.skip_async_hooks = true;
        // Source adds three uint32 fields; preserve that arithmetic.
        const total = environment.field(.before).* +%
            environment.field(.after).* +%
            environment.field(.uses_execution_async_resource).*;
        use_trampoline = total > 0;
    }
    try scope.init(environment, resource, context, flags, frame);
    if (scope.failed) return null;

    const returned = if (use_trampoline)
        try callTrampoline(handles, environment, trampoline.?, resource,
            receiver, callback, arguments, context.async_id)
        else try handles.call(callback, receiver, arguments);
    try scope.close();
    if (scope.failed) return null;
    return a.duplicate(handles.engine, returned);
}

fn callTrampoline(handles: *a.Scope, environment: *callbacks.Environment,
    trampoline: c.JSValue, resource: c.JSValue, receiver: c.JSValue,
    callback: c.JSValue, arguments: []const c.JSValue, async_id: f64) !c.JSValue
{
    // Actual MaybeStackBuffer<Local<Value>,16>: no native allocation at <=16,
    // otherwise one native array, retired before scope.Close() on every path.
    const count = std.math.add(usize, 3, arguments.len) catch
        return environment.operations.native_check_failure(environment, .callback_argument_count);
    if (count > std.math.maxInt(c_int))
        return environment.operations.native_check_failure(environment, .callback_argument_count);
    var stack: [16]c.JSValue = undefined;
    const heap = count > stack.len;
    const values = if (heap) try allocateArguments(environment, count) else stack[0..count];
    defer if (heap) environment.allocator().free(values);
    values[0] = c.JS_NewFloat64(handles.engine.context, async_id);
    values[1] = resource;
    values[2] = callback;
    @memcpy(values[3..], arguments);
    return handles.call(trampoline, receiver, values);
}

fn allocateArguments(environment: *callbacks.Environment, count: usize) ![]c.JSValue {
    const engine = try environment.requireEngine();
    // Original node::Realloc calls LowMemoryNotification and retries the
    // actual native allocation once; its second failure is native CHECK.
    // This owner has the live current VM, so its full collector is available.
    return environment.allocator().alloc(c.JSValue, count) catch {
        c.JS_RunGC(engine.runtime);
        return environment.allocator().alloc(c.JSValue, count) catch
            return environment.operations.native_check_failure(environment, .callback_argument_buffer);
    };
}
