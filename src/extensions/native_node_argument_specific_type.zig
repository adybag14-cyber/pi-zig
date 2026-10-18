// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual internal/errors determineSpecificType. Each conditional getter and
//! template operand retires at its Source expression boundary.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const Frame = a.frames.Frame(enum { value });
pub const Inputs = struct {
    internal_inspect: c.JSValue, string: c.JSValue, json_stringify: c.JSValue,
    string_slice: c.JSValue, string_index_of: c.JSValue,
};
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    return a.expression(engine, createBody, .{inputs});
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    if (!c.JS_IsObject(inputs.internal_inspect)) return error.ActualInternalInspectRequired;
    inline for (.{ inputs.string, inputs.json_stringify, inputs.string_slice, inputs.string_index_of }) |function|
        if (!c.JS_IsFunction(s.engine.context, function)) return error.ActualSpecificTypePrimordialsRequired;
    return functions.create(s.engine, "determineSpecificType", 1, true, invoke, &.{ inputs.internal_inspect, inputs.string, inputs.json_stringify, inputs.string_slice, inputs.string_index_of });
}
fn invoke(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = Frame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, body(&s, frame, a.arg(args, 0), roots));
}
fn phrase(s: *Scope, prefix: []const u8, value: c.JSValue, suffix: []const u8) !c.JSValue {
    return a.add(s, try a.add(s, try s.text(prefix), try s.toString(value)), try s.text(suffix));
}
fn constructorHasName(s: *Scope, value: c.JSValue) !c.JSValue {
    const constructor_value = try s.get(value, "constructor");
    // Linked VM js_operator_in rejects a primitive RHS before converting its
    // key. JS_HasProperty alone returns false for that input.
    if (!c.JS_IsObject(constructor_value)) {
        const generation = try s.beforeAllocation();
        _ = try s.checkedAllocation(c.JS_ThrowTypeError(s.engine.context, "%s", @as([*:0]const u8, "invalid 'in' operand")), generation);
        unreachable;
    }
    return a.boolean(s, try s.hasKey(constructor_value, try s.text("name")));
}
fn constructorName(s: *Scope, value: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.get(try s.get(value, "constructor"), "name"));
}
fn instancePhrase(s: *Scope, value: c.JSValue) !c.JSValue {
    // The constructor receiver retires after its .name get, before the
    // returned name's ToString can invoke another guest operation.
    const name = try s.own(try a.expression(s.engine, constructorName, .{value}));
    return a.duplicate(s.engine, try phrase(s, "an instance of ", name, ""));
}
fn inspectedCall(s: *Scope, value: c.JSValue, module: c.JSValue) !c.JSValue {
    const inspect = try s.get(module, "inspect");
    const options = try s.object();
    try s.define(options, "depth", c.JS_NewInt32(s.engine.context, -1), c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, try s.call(inspect, module, &.{value, options}));
}
fn inspectedPhrase(s: *Scope, value: c.JSValue, module: c.JSValue) !c.JSValue {
    const inspected = try s.own(try a.expression(s.engine, inspectedCall, .{value, module}));
    return a.duplicate(s.engine, try s.toString(inspected));
}
fn longerThan28(s: *Scope, value: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(6, try s.get(value, "length"), c.JS_NewInt32(s.engine.context, 28))));
}
fn truncated(s: *Scope, value: c.JSValue, slice: c.JSValue) !c.JSValue {
    const part = try s.call(slice, value, &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 25) });
    return a.duplicate(s.engine, try a.add(s, try s.toString(part), try s.text("...")));
}
fn noApostrophe(s: *Scope, value: c.JSValue, index_of: c.JSValue) !c.JSValue {
    const position = try s.call(index_of, value, &.{try s.text("'")});
    return a.boolean(s, s.equal(position, c.JS_NewInt32(s.engine.context, -1)));
}
fn jsonPhrase(s: *Scope, value: c.JSValue, json: c.JSValue) !c.JSValue {
    const quoted = try s.call(json, c.pi_js_undefined(), &.{value});
    return a.duplicate(s.engine, try phrase(s, "type string (", quoted, ")"));
}
fn body(s: *Scope, frame: *Frame, input: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try s.pending();
    try frame.copy(.value, input);
    if (c.JS_IsNull(input)) return a.duplicate(s.engine, try s.text("null"));
    if (c.JS_IsUndefined(input)) return a.duplicate(s.engine, try s.text("undefined"));
    if (c.JS_IsBigInt(input)) return a.duplicate(s.engine, try phrase(s, "type bigint (", input, "n)"));
    if (c.JS_IsNumber(input)) {
        var number: f64 = 0;
        if (c.JS_ToFloat64(s.engine.context, &number, input) < 0) return @as(anyerror!c.JSValue, v.js.capture(s.engine));
        try s.pending();
        if (number == 0 and std.math.signbit(number)) return a.duplicate(s.engine, try s.text("type number (-0)"));
        return a.duplicate(s.engine, try phrase(s, "type number (", input, ")"));
    }
    if (c.JS_IsBool(input)) return a.duplicate(s.engine, try s.text(if (s.truthy(input)) "type boolean (true)" else "type boolean (false)"));
    if (c.JS_IsSymbol(input)) return a.duplicate(s.engine, try phrase(s, "type symbol (", try s.call(roots[1], c.pi_js_undefined(), &.{input}), ")"));
    if (c.JS_IsFunction(s.engine.context, input)) {
        const name = try s.own(try a.fieldText(s.engine, input, "name"));
        return a.duplicate(s.engine, try a.add(s, try s.text("function "), name));
    }
    if (c.JS_IsObject(input)) {
        if (try a.condition(s.engine, a.fieldTruthy, .{ input, @as([*:0]const u8, "constructor") }) and
            try a.condition(s.engine, constructorHasName, .{input}))
            return a.expression(s.engine, instancePhrase, .{input});
        return a.expression(s.engine, inspectedPhrase, .{ input, roots[0] });
    }
    if (c.JS_IsString(input)) {
        if (try a.condition(s.engine, longerThan28, .{frame.get(.value)}))
            try frame.take(.value, a.expression(s.engine, truncated, .{ frame.get(.value), roots[3] }));
        if (try a.condition(s.engine, noApostrophe, .{ frame.get(.value), roots[4] }))
            return a.duplicate(s.engine, try phrase(s, "type string ('", frame.get(.value), "')"));
        return a.expression(s.engine, jsonPhrase, .{ frame.get(.value), roots[2] });
    }
    // The actual VM has no undetectable host object or additional ECMAScript
    // typeof category requiring Source's host-only default branch.
    return error.UnsupportedActualSpecificTypeValue;
}
