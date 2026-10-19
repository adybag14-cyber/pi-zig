// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Actual Node v24.14 helpers.js makeRequireFunction. The real Module and
//! validateString owners are captured once; public methods remain live.
const a = @import("native_node_argument_values.zig");
const v = a.v;
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
pub const Inputs = struct {
    module_constructor: c.JSValue,
    process: c.JSValue,
    invalid_arg_type: c.JSValue,
    validate_string: c.JSValue,
};
fn statement(engine: *v.em.Engine, comptime body: anytype, args: anytype) !void {
    var stage = Scope.init(engine);
    var failure: ?anyerror = null;
    @call(.auto, body, .{&stage} ++ args) catch |err| { failure = err; };
    _ = try stage.finish(if (failure) |err| @as(anyerror!c.JSValue, err) else c.pi_js_undefined());
}
fn invalidReason(s: *Scope, constructor: c.JSValue, name: []const u8, expected: []const u8, actual: c.JSValue) !c.JSValue {
    const name_value = try s.text(name);
    const expected_value = try s.text(expected);
    return a.duplicate(s.engine, try s.construct(constructor, &.{ name_value, expected_value, actual }));
}
fn invalidBody(s: *Scope, constructor: c.JSValue, name: []const u8, expected: []const u8, actual: c.JSValue) !c.JSValue {
    // Complete the constructor expression before the Source's explicit throw.
    const reason = try s.own(try a.expression(s.engine, invalidReason, .{ constructor, name, expected, actual }));
    return @as(anyerror!c.JSValue, a.raise(s, reason));
}
pub fn invalidArgumentType(engine: *v.em.Engine, constructor: c.JSValue, name: []const u8, expected: []const u8, actual: c.JSValue) anyerror {
    _ = a.expression(engine, invalidBody, .{ constructor, name, expected, actual }) catch |err| return err;
    unreachable;
}
fn instance(s: *Scope, parent: c.JSValue, constructor: c.JSValue) !c.JSValue {
    try s.pending();
    const result = c.JS_IsInstanceOf(s.engine.context, parent, constructor);
    try s.pending();
    if (result < 0) return error.MissingActualModuleInstanceReason;
    return a.boolean(s, result == 1);
}
fn defineMain(s: *Scope, require: c.JSValue, process: c.JSValue) !void {
    const main = try s.get(process, "mainModule");
    // Source setOwnProperty bypasses inherited setters for this one field.
    try s.define(require, "main", main, c.JS_PROP_C_W_E);
}
fn copyField(s: *Scope, target: c.JSValue, name: [*:0]const u8, source: c.JSValue, source_name: [*:0]const u8) !void {
    try s.put(target, name, try s.get(source, source_name));
}
fn setField(s: *Scope, target: c.JSValue, name: [*:0]const u8, incoming: c.JSValue) !void {
    try s.put(target, name, incoming);
}
pub fn create(engine: *v.em.Engine, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    return a.expression(engine, createBody, .{ inputs, parent });
}
fn createBody(s: *Scope, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    // Both callbacks below consume the genuine internal validateString
    // function, including its hidden-stack error boundary, on every call.
    if (!c.JS_IsFunction(s.engine.context, inputs.validate_string))
        return error.ActualModuleValidateStringRequired;
    if (!try a.condition(s.engine, instance, .{ parent, inputs.module_constructor }))
        return @as(anyerror!c.JSValue, invalidArgumentType(s.engine, inputs.invalid_arg_type, "mod", "Module", parent));
    const values = [_]c.JSValue{ inputs.module_constructor, inputs.process, inputs.invalid_arg_type, parent, inputs.validate_string };
    const require = try s.own(try functions.create(s.engine, "require", 1, true, requireCallback, &values));
    const resolve = try s.own(try functions.create(s.engine, "resolve", 2, true, resolveCallback, &values));
    const paths = try s.own(try functions.create(s.engine, "paths", 1, true, pathsCallback, &values));
    try statement(s.engine, setField, .{ require, @as([*:0]const u8, "resolve"), resolve });
    try statement(s.engine, setField, .{ resolve, @as([*:0]const u8, "paths"), paths });
    try statement(s.engine, defineMain, .{ require, inputs.process });
    try statement(s.engine, copyField, .{ require, @as([*:0]const u8, "extensions"), inputs.module_constructor, @as([*:0]const u8, "_extensions") });
    try statement(s.engine, copyField, .{ require, @as([*:0]const u8, "cache"), inputs.module_constructor, @as([*:0]const u8, "_cache") });
    return a.duplicate(s.engine, require);
}
fn requireBody(s: *Scope, parent: c.JSValue, request: c.JSValue) !c.JSValue {
    const function = try s.get(parent, "require");
    return a.duplicate(s.engine, try s.call(function, parent, &.{request}));
}
fn requireCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return a.expression(engine, requireBody, .{ values[3], a.arg(args, 0) });
}
fn validateRequest(s: *Scope, validate_string: c.JSValue, request: c.JSValue) !void {
    _ = try s.call(validate_string, c.pi_js_undefined(), &.{ request, try s.text("request") });
}
fn resolveBody(s: *Scope, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    const request = a.arg(args, 0);
    try statement(s.engine, validateRequest, .{ values[4], request });
    const function = try s.get(values[0], "_resolveFilename");
    return a.duplicate(s.engine, try s.call(function, values[0], &.{ request, values[3], a.boolean(s, false), a.arg(args, 1) }));
}
fn resolveCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return a.expression(engine, resolveBody, .{ args, values });
}
fn pathsBody(s: *Scope, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    const request = a.arg(args, 0);
    try statement(s.engine, validateRequest, .{ values[4], request });
    const function = try s.get(values[0], "_resolveLookupPaths");
    return a.duplicate(s.engine, try s.call(function, values[0], &.{ request, values[3] }));
}
fn pathsCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return a.expression(engine, pathsBody, .{ args, values });
}
