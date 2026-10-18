// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual internal/assert with lazy access to the single argument-error owner.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const errors = @import("native_node_argument_errors.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/internal-assert";
pub fn create(engine: *v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn createBody(s: *Scope) !c.JSValue {
    const cell = try s.objectProto(c.pi_js_null());
    try s.put(cell, "error", c.pi_js_undefined());
    const function = try s.own(try functions.create(s.engine, "assert", 2, true, invoke, &.{cell}));
    const fail_function = try s.own(try functions.create(s.engine, "fail", 1, true, fail, &.{cell}));
    try s.put(function, "fail", fail_function);
    return a.duplicate(s.engine, function);
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, invokeBody, .{args, roots[0]});
}
fn invokeBody(s: *Scope, args: []const c.JSValue, cell: c.JSValue) !c.JSValue {
    if (!s.truthy(a.arg(args, 0))) return raise(s, a.arg(args, 1), cell);
    return c.pi_js_undefined();
}
fn fail(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, raise, .{a.arg(args, 0), roots[0]});
}
fn raise(s: *Scope, message: c.JSValue, cell: c.JSValue) !c.JSValue {
    var error_class = try s.get(cell, "error");
    if (v.nullish(error_class)) {
        error_class = try s.own(try errors.assertion(s.engine));
        try s.put(cell, "error", error_class);
    }
    return a.raise(s, try s.construct(error_class, &.{message}));
}
