// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The actual internal/errors families consumed by internal/url's path helpers.
//! They retain the existing argument owner, inspector and kIsNodeError marker.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const registration = @import("native_node_argument_error_registration.zig");
const string_registration = @import("native_node_string_error_registration.zig");
const publication = @import("native_node_fs_private_publication.zig");
const key = "pi-native:private/file-url-error-owner";
const SchemeFrame = a.frames.Frame(enum { expected, result });

fn arrayBody(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try a.array(s);
    try a.index(s, result, 0, value);
    return a.duplicate(s.engine, result);
}
fn atTextBody(s: *Scope, value: c.JSValue, position: u32) !c.JSValue {
    return a.duplicate(s.engine, try s.toString(try s.getKey(value, c.JS_NewUint32(s.engine.context, position))));
}
fn maximumExpected(s: *Scope, expected: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.binary(5, try s.get(expected, "length"), c.JS_NewInt32(s.engine.context, 2))));
}
fn twoExpected(s: *Scope, expected: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(expected, "length"), c.JS_NewInt32(s.engine.context, 2)));
}
fn assertExpected(s: *Scope, assertion: c.JSValue, expected: c.JSValue) !c.JSValue {
    const valid = try a.condition(s.engine, maximumExpected, .{expected});
    _ = try s.call(assertion, c.pi_js_undefined(), &.{a.boolean(s, valid)});
    return c.pi_js_undefined();
}
fn schemeResult(s: *Scope, expected: c.JSValue, two: bool) !c.JSValue {
    var result = try s.text(if (two) "one of scheme " else "of scheme ");
    result = try a.add(s, result, try s.own(try a.expression(s.engine, atTextBody, .{expected, @as(u32, 0)})));
    if (two) {
        result = try a.add(s, result, try s.text(" or "));
        result = try a.add(s, result, try s.own(try a.expression(s.engine, atTextBody, .{expected, @as(u32, 1)})));
    }
    return a.duplicate(s.engine, result);
}
fn scheme(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = SchemeFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, schemeBody(&s, frame, a.arg(args, 0), roots[0]));
}
fn schemeBody(s: *Scope, frame: *SchemeFrame, expected: c.JSValue, assertion: c.JSValue) !c.JSValue {
    try frame.copy(.expected, expected);
    if (c.JS_IsString(frame.get(.expected)))
        try frame.take(.expected, a.expression(s.engine, arrayBody, .{frame.get(.expected)}));
    _ = try a.expression(s.engine, assertExpected, .{assertion, frame.get(.expected)});
    const two = try a.condition(s.engine, twoExpected, .{frame.get(.expected)});
    try frame.take(.result, a.expression(s.engine, schemeResult, .{frame.get(.expected), two}));
    return a.duplicate(s.engine, try a.add(s, try s.text("The URL must be "), try s.toString(frame.get(.result))));
}
fn path(engine: *a.v.em.Engine, receiver: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return a.expression(engine, pathBody, .{receiver, args});
}
fn pathBody(s: *Scope, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    try s.put(receiver, "input", a.arg(args, 1));
    return a.duplicate(s.engine, try a.add(s, try s.text("File URL path "), try s.toString(a.arg(args, 0))));
}
fn adoptPrepared(s: *Scope, prepared: @import("native_node_argument_bootstrap.zig").Prepared) !void {
    var values = [_]c.JSValue{
        prepared.internal_inspect, prepared.assert_function,
        prepared.arguments.invalid_arg_type, prepared.arguments.hidden_invalid_arg_type,
        prepared.arguments.invalid_arg_value, prepared.arguments.internal_assertion,
        prepared.arguments.validate_string,
    };
    for (&values, 0..) |*slot, position| {
        const moved = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(moved) catch |err| {
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
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
    const prepared = try @import("native_node_argument_bootstrap.zig").prepare(s.engine);
    try adoptPrepared(s, prepared);
    const core = try s.own(a.duplicate(s.engine, try @import("native_node_stream.zig").owner(s.engine)));
    const system = try s.own(a.duplicate(s.engine, try @import("native_node_system_errors.zig").registry(s.engine)));
    const base = try s.get(core, "TypeError");
    const marker = try s.get(system, "marker");
    const original_arguments = @import("native_node_argument_errors.zig");
    const apply = try s.own(try original_arguments.reflectApply(s.engine));
    const unshift = try s.own(try original_arguments.arrayUnshift(s.engine));
    const scheme_message = try s.own(try functions.create(s.engine, "", 1, false, scheme, &.{prepared.assert_function}));
    const path_message = try s.own(try functions.create(s.engine, "", 2, true, path, &.{}));
    const scheme_class = try registration.register(s, base, "ERR_INVALID_URL_SCHEME", scheme_message, marker, prepared.assert_function, apply);
    const path_class = try registration.register(s, base, "ERR_INVALID_FILE_URL_PATH", path_message, marker, prepared.assert_function, apply);
    const host_class = try string_registration.register(s, base, "ERR_INVALID_FILE_URL_HOST",
        "File URL host must be \"localhost\" or empty on %s", marker, prepared.assert_function, apply, prepared.internal_inspect, unshift);
    const record = try s.objectProto(c.pi_js_null());
    try s.put(record, "invalid_arg_type", prepared.arguments.invalid_arg_type);
    try s.put(record, "invalid_url_scheme", scheme_class);
    try s.put(record, "invalid_file_url_path", path_class);
    try s.put(record, "invalid_file_url_host", host_class);
    try s.put(record, "internal_inspect", prepared.internal_inspect);
    try s.put(record, "marker", marker);
    return a.duplicate(s.engine, record);
}
