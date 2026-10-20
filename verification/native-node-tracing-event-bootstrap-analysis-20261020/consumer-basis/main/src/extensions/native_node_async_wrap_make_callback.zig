// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual AsyncWrap::MakeCallback composition. The caller supplies its existing
//! HandleScope and the genuine native trace owner. No trace implementation or
//! category admission is fabricated here.
const a = @import("native_node_argument_values.zig");
const callbacks = @import("native_node_callback_scope.zig");
const wraps = @import("native_node_async_wrap_state.zig");
const make_callback = @import("native_node_make_callback.zig");
const c = a.c;

/// These are the compiled native EmitTraceEventBefore/After operations. They
/// must not call guest JS. The before operation receives the live State so its
/// actual category gate can precede the async-ID read. The after operation
/// receives only the Source snapshots: the original State may already be dead.
/// The supplied native trace owner must outlive the enclosing Environment.
pub const Trace = struct {
    raw: ?*anyopaque,
    before: *const fn (?*anyopaque, *wraps.State) void,
    after: *const fn (?*anyopaque, u32, f64) void,
};

/// Inputs are borrowed caller-local handles. A nonempty return is also borrowed
/// from that SAME caller HandleScope; null is the original empty MaybeLocal.
/// Keep the Environment/VM and caller Scope alive through native teardown.
pub fn call(s: *a.Scope, state: *wraps.State, trace: Trace,
    callback: c.JSValue, arguments: []const c.JSValue) !?c.JSValue
{
    const environment = state.registry.environment;
    if ((try environment.requireEngine()) != s.engine)
        return error.ActualAsyncWrapEnvironmentMismatch;
    _ = environment.retain();
    defer environment.release();

    trace.before(trace.raw, state);
    const provider = state.provider;
    const context = state.context();

    var returned: ?c.JSValue = null;
    var failure: ?anyerror = null;
    if (callBody(s, environment, state, callback, arguments, context)) |value| {
        returned = value;
    } else |err| {
        recordFailure(s, err);
        failure = err;
    }
    // Do not read state or any derived native member here. InternalMakeCallback
    // may have completed the actual native object's destruction.
    trace.after(trace.raw, provider, context.async_id);

    if (failure) |err| return err;
    if (returned) |value| return try s.own(value);
    return null;
}

fn callBody(s: *a.Scope, environment: *callbacks.Environment,
    state: *wraps.State, callback: c.JSValue, arguments: []const c.JSValue,
    context: callbacks.AsyncContext) !?c.JSValue
{
    const first = state.object() orelse
        return environment.operations.native_check_failure(environment, .invalid_wrap_brand);
    const resource = try s.own(a.duplicate(s.engine, first));
    const second = state.object() orelse
        return environment.operations.native_check_failure(environment, .invalid_wrap_brand);
    const receiver = try s.own(a.duplicate(s.engine, second));
    const frame = try s.own(a.duplicate(s.engine, state.context_frame));
    return make_callback.call(environment, resource, receiver, callback,
        arguments, context, frame);
}

fn recordFailure(s: *a.Scope, err: anyerror) void {
    s.boundary.escaping();
    if (err == error.OutOfMemory and !s.boundary.isFatal()) {
        _ = s.engine.throwNativeOutOfMemoryFatal();
        s.boundary.escaping();
    }
}
