// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node v24.13 env-inl.h Environment::ThrowUVException. UVException creates
//! the actual ordinary Error; this operation then throws that owned value.
//! There is no can_call_into_js guard on the native Source operation.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const Environment = @import("native_node_callback_scope.zig").Environment;
const uv = @import("native_node_uv_exception.zig");
pub const Input = uv.Input;

fn body(s: *Scope, input: Input) !c.JSValue {
    // Adopt before the explicit throw so root retirement stays under the
    // same pending/fatal completion, including a later native finalizer.
    const reason = try s.own(try uv.create(s.engine, input));
    return a.raise(s, reason);
}

pub fn throwException(env: *Environment, input: Input) !void {
    const engine = try env.requireEngine();
    const unexpected = try a.expression(engine, body, .{input});
    engine.freeValue(unexpected);
    return error.ActualNodeThrowUvExceptionDidNotThrow;
}
