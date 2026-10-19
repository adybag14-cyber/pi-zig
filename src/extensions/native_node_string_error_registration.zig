// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The actual string-message branch of internal/errors.makeNodeErrorWithCode.
//! The formatter remains the live field of the retained internal inspect owner.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const classes = @import("native_node_error_class.zig");
const functions = @import("native_node_module_callable.zig");
const Frame = a.frames.Frame(enum { rest });

fn expectedArguments(message: []const u8) usize {
    // The bootstrap message is a fixed Source string. This is the result of
    // its /%[dfijoOs]/g scan; a preceding percent does not escape a later match.
    var result: usize = 0;
    var position: usize = 0;
    while (position + 1 < message.len) : (position += 1) {
        if (message[position] == '%' and std.mem.indexOfScalar(u8, "dfijoOs", message[position + 1]) != null) {
            result += 1;
            position += 1;
        }
    }
    return result;
}
fn getter(engine: *a.v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    return a.duplicate(engine, roots[0]);
}
fn accessor(s: *Scope, target: c.JSValue, key: c.JSValue, name: [*:0]const u8, returned: c.JSValue) !void {
    const function = try s.own(try functions.create(s.engine, name, 0, false, getter, &.{returned}));
    try s.pending();
    const atom = c.JS_ValueToAtom(s.engine.context, key);
    defer if (atom != c.JS_ATOM_NULL) c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    if (atom == c.JS_ATOM_NULL) return error.MissingActualStringErrorAccessorKeyReason;
    const status = c.JS_DefinePropertyGetSet(s.engine.context, target, atom, a.duplicate(s.engine, function), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_THROW);
    try s.pending();
    if (status < 0) return error.MissingActualStringErrorAccessorReason;
}
fn stringifier(engine: *a.v.em.Engine, receiver: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return a.expression(engine, stringBody, .{receiver, roots[0]});
}
fn stringBody(s: *Scope, receiver: c.JSValue, key: c.JSValue) !c.JSValue {
    const name = try s.own(try a.fieldText(s.engine, receiver, "name"));
    var result = try a.add(s, name, try s.text(" ["));
    result = try a.add(s, result, key);
    result = try a.add(s, result, try s.text("]: "));
    const message = try s.own(try a.fieldText(s.engine, receiver, "message"));
    return a.duplicate(s.engine, try a.add(s, result, message));
}
fn restBody(s: *Scope, args: []const c.JSValue) !c.JSValue {
    const generation = try s.beforeAllocation();
    return a.duplicate(s.engine, try s.checkedAllocation(c.JS_PiCreateRestArray(s.engine.context, @intCast(args.len), @constCast(args.ptr)), generation));
}
fn correctCount(s: *Scope, rest: c.JSValue, expected: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(rest, "length"), expected));
}
fn assertionBody(s: *Scope, rest: c.JSValue, key: c.JSValue, expected: c.JSValue, assertion: c.JSValue) !c.JSValue {
    const valid = try a.condition(s.engine, correctCount, .{rest, expected});
    var message = try a.add(s, try s.text("Code: "), key);
    message = try a.add(s, message, try s.text("; The provided arguments length ("));
    message = try a.add(s, message, try s.own(try a.fieldText(s.engine, rest, "length")));
    message = try a.add(s, message, try s.text(") does not match the required ones ("));
    message = try a.add(s, message, try s.toString(expected));
    message = try a.add(s, message, try s.text(")."));
    _ = try s.call(assertion, c.pi_js_undefined(), &.{a.boolean(s, valid), message});
    return c.pi_js_undefined();
}
fn unshiftBody(s: *Scope, unshift: c.JSValue, rest: c.JSValue, message: c.JSValue) !c.JSValue {
    _ = try s.call(unshift, rest, &.{message});
    return c.pi_js_undefined();
}
fn formatBody(s: *Scope, inspect_record: c.JSValue, apply: c.JSValue, rest: c.JSValue) !c.JSValue {
    const formatter = try s.get(inspect_record, "format");
    return a.duplicate(s.engine, try s.call(apply, c.pi_js_undefined(), &.{formatter, c.pi_js_null(), rest}));
}
fn superBody(s: *Scope, lexical: c.JSValue, target: c.JSValue, rest: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // Source resolves super before evaluating its format(...) argument. The
    // live format getter/call may mutate the declared class's prototype.
    const base = try s.prototype(lexical);
    const message = if (s.equal(roots[2], c.JS_NewInt32(s.engine.context, 0)))
        roots[1]
    else try s.own(try a.expression(s.engine, formatBody, .{roots[5], roots[4], rest}));
    var argv = [_]c.JSValue{message};
    try s.pending();
    return a.duplicate(s.engine, try s.checked(c.JS_CallConstructor2(s.engine.context, base, target, 1, &argv)));
}
fn construct(engine: *a.v.em.Engine, lexical: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, constructBody(&s, frame, lexical, target, args, roots));
}
fn constructBody(s: *Scope, frame: *Frame, lexical: c.JSValue, target: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try frame.take(.rest, a.expression(s.engine, restBody, .{args}));
    _ = try a.expression(s.engine, assertionBody, .{frame.get(.rest), roots[0], roots[2], roots[3]});
    if (!s.equal(roots[2], c.JS_NewInt32(s.engine.context, 0)))
        _ = try a.expression(s.engine, unshiftBody, .{roots[6], frame.get(.rest), roots[1]});
    const receiver = try s.own(try a.expression(s.engine, superBody, .{lexical, target, frame.get(.rest), roots}));
    // Source public field initialization occurs immediately after super returns.
    try s.define(receiver, "code", roots[0], c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, receiver);
}
pub fn register(s: *Scope, base: c.JSValue, key: []const u8, message: []const u8, marker: c.JSValue, assertion: c.JSValue, apply: c.JSValue, inspect_record: c.JSValue, unshift: c.JSValue) !c.JSValue {
    const prototype = try s.objectProto(try s.get(base, "prototype"));
    const code = try s.text(key);
    const text = try s.text(message);
    const expected = c.JS_NewInt32(s.engine.context, @intCast(expectedArguments(message)));
    const function = try s.own(try classes.create(s.engine, "NodeError", 0, prototype, base, construct, &.{code, text, expected, assertion, apply, inspect_record, unshift}));
    try accessor(s, prototype, try s.text("constructor"), "get constructor", base);
    try accessor(s, prototype, marker, "get [kIsNodeError]", a.boolean(s, true));
    const to_string = try s.own(try functions.create(s.engine, "toString", 0, false, stringifier, &.{code}));
    try s.define(prototype, "toString", to_string, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE);
    return function;
}
