//! Shared lexical owner and expression completions for the actual c268 RPC mode.
pub const v = @import("native_public_values.zig");
pub const c = v.c;
pub const Engine = v.em.Engine;
pub const Scope = v.Scope;
pub const af = v.af;
pub const lexical = @import("native_public_lexical_frame.zig");
pub const caught = @import("native_agent_af_values.zig").caught;
pub const enterRejected = @import("native_async_body.zig").enterRejectedContinuation;
pub const Names = enum {
    runtime_host, session, unsubscribe, unsubscribe_backpressure,
    output, success, failure, pending_requests, shutdown_requested, shutting_down,
    signal_cleanup_handlers, create_dialog, create_ui, rebind_session,
    register_signals, handle_command, detach_input, shutdown, check_shutdown,
    handle_input, on_input_end,
};
pub const Frame = lexical.Frame(Names);
pub fn expression(engine: *Engine, comptime body: anytype, args: anytype) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, @call(.auto, body, .{&s} ++ args));
}
pub fn statement(engine: *Engine, comptime body: anytype, args: anytype) anyerror!void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, @call(.auto, body, .{&s} ++ args));
}
pub fn duplicate(engine: *Engine, value: c.JSValue) c.JSValue { return c.JS_DupValue(engine.context, value); }
pub fn truthy(engine: *Engine, value: c.JSValue) bool { return c.JS_ToBool(engine.context, value) == 1; }
pub fn field(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const selected = try v.own(s, v.duplicate(s, receiver));
    return v.duplicate(s, try v.get(s, selected, name));
}
pub fn fieldOwned(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return expression(engine, field, .{ receiver, name });
}
pub fn fieldValue(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.own(s, try fieldOwned(s.engine, receiver, name));
}
pub fn optionalField(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (v.nullish(receiver)) c.pi_js_undefined() else fieldValue(s, receiver, name);
}
pub fn fieldTruthy(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8) !bool {
    return truthy(engine, try expression(engine, fieldTruthyBody, .{ receiver, name }));
}
fn fieldTruthyBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, v.truthy(s, try fieldValue(s, receiver, name)));
}
pub fn fieldEqual(engine: *Engine, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !bool {
    return truthy(engine, try expression(engine, fieldEqualBody, .{ receiver, name, expected }));
}
fn fieldEqualBody(s: *Scope, receiver: c.JSValue, name: [*:0]const u8, expected: []const u8) !c.JSValue {
    return v.boolean(s, try v.eq(s, try fieldValue(s, receiver, name), expected));
}
pub fn bindingField(s: *Scope, cell: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.duplicate(s, try v.get(s, try Frame.read(s, cell), name));
}
pub fn bindingMethod(s: *Scope, cell: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const receiver = try Frame.read(s, cell);
    const method = try v.get(s, receiver, name);
    return v.duplicate(s, try v.call(s, method, receiver, args));
}
pub fn bindingCall(s: *Scope, cell: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, try Frame.read(s, cell), c.pi_js_undefined(), args));
}
pub fn optionalBinding(s: *Scope, cell: c.JSValue) !void {
    const callable = try Frame.read(s, cell);
    if (!v.nullish(callable)) _ = try v.call(s, callable, c.pi_js_undefined(), &.{});
}
pub fn functionCall(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), args));
}
pub fn discardFunction(s: *Scope, callable: c.JSValue, args: []const c.JSValue) !void { _ = try v.call(s, callable, c.pi_js_undefined(), args); }
pub fn discardBinding(s: *Scope, cell: c.JSValue, args: []const c.JSValue) !void { _ = try v.call(s, try Frame.read(s, cell), c.pi_js_undefined(), args); }
pub fn bindingTruthy(engine: *Engine, cell: c.JSValue) !bool {
    return truthy(engine, try expression(engine, bindingTruthyBody, .{cell}));
}
fn bindingTruthyBody(s: *Scope, cell: c.JSValue) !c.JSValue { return v.boolean(s, v.truthy(s, try Frame.read(s, cell))); }
pub fn asyncArrow(s: *Scope, name: [*:0]const u8, length: c_int, body: af.Body, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createResumableArrow(s.engine, name, length, body, roots, c.pi_js_undefined()));
}
pub fn simpleAsync(s: *Scope, name: [*:0]const u8, length: c_int, body: af.Callback, roots: []const c.JSValue) !c.JSValue {
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    return boundary.finishValue(s, af.createArrow(s.engine, name, length, body, roots, c.pi_js_undefined()));
}
pub fn emptyText(s: *Scope) !c.JSValue { return v.duplicate(s, try v.text(s, "")); }
pub fn emptyArray(s: *Scope) !c.JSValue { return v.duplicate(s, try v.array(s)); }
pub fn emptyCallback(_: *Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return c.pi_js_undefined(); }
pub fn has(s: *Scope, receiver: c.JSValue, name: [*:0]const u8) !bool {
    if (!c.JS_IsObject(receiver)) return v.typeError(s, "invalid 'in' operand");
    const property = try v.text(s, @import("std").mem.span(name));
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const atom = c.JS_ValueToAtom(s.engine.context, property);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try boundary.finishStatus(if (atom == c.JS_ATOM_NULL) -1 else 0);
    var get_boundary: v.guest.Boundary = .{ .engine = s.engine }; try get_boundary.begin();
    const result = c.JS_HasProperty(s.engine.context, receiver, atom);
    try get_boundary.finishStatus(if (result < 0) -1 else 0);
    return result != 0;
}
pub fn instanceError(s: *Scope, reason: c.JSValue) !c.JSValue {
    const constructor = try v.global(s, "Error");
    var boundary: v.guest.Boundary = .{ .engine = s.engine }; try boundary.begin();
    const result = c.JS_IsInstanceOf(s.engine.context, reason, constructor);
    try boundary.finishStatus(if (result < 0) -1 else 0);
    return v.boolean(s, result != 0);
}
pub fn caughtMessage(s: *Scope, reason: c.JSValue) !c.JSValue {
    if (truthy(s.engine, try expression(s.engine, instanceError, .{reason})))
        return v.duplicate(s, try v.get(s, reason, "message"));
    const callable = try v.global(s, "String");
    return v.duplicate(s, try v.call(s, callable, c.pi_js_undefined(), &.{reason}));
}
