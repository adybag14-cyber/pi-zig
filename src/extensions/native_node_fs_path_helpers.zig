// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Genuine internal/fs/utils getOptions, assertEncoding and validatePath.
//! This private owner is shared by actual filesystem entry points; all Error,
//! Buffer and validator callables come from the completed bootstrap graph.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const functions = @import("native_node_module_callable.zig");
const registration = @import("native_node_argument_error_registration.zig");
const spread = @import("native_node_object_spread.zig");
const key = "pi-native:private/internal-fs-path-helpers";
const OptionsFrame = a.frames.Frame(enum { options, default_options });
pub const Inputs = struct {
    empty_object: c.JSValue,
    buffer: c.JSValue,
    invalid_arg_type: c.JSValue,
    invalid_arg_value: c.JSValue,
    hidden_invalid_arg_type: c.JSValue,
    hidden_invalid_arg_value: c.JSValue,
    validate_abort_signal: c.JSValue,
    error_constructor: c.JSValue,
    capture_stack_trace: c.JSValue,
    reflect_apply: c.JSValue,
    string_includes: c.JSValue,
    typed_array_includes: c.JSValue,
};
fn invalidType(s: *a.Scope, constructor: c.JSValue, name: c.JSValue, expected: []const []const u8, input: c.JSValue) !c.JSValue {
    const kinds = try a.array(s);
    for (expected, 0..) |kind, position| try a.index(s, kinds, @intCast(position), try s.text(kind));
    const reason = try s.construct(constructor, &.{name, kinds, input});
    return @as(anyerror!c.JSValue, a.raise(s, reason));
}
fn invalidValue(s: *a.Scope, constructor: c.JSValue, name: c.JSValue, input: c.JSValue, reason_text: []const u8) !c.JSValue {
    const reason = try s.construct(constructor, &.{name, input, try s.text(reason_text)});
    return @as(anyerror!c.JSValue, a.raise(s, reason));
}
fn hiddenTypeReason(s: *a.Scope, base: c.JSValue, name: c.JSValue, input: c.JSValue) !c.JSValue {
    const constructor = try s.get(base, "HideStackFramesError");
    const kinds = try a.array(s);
    inline for (.{ "string", "Buffer", "URL" }, 0..) |kind, position|
        try a.index(s, kinds, @intCast(position), try s.text(kind));
    return a.duplicate(s.engine, try s.construct(constructor, &.{name, kinds, input}));
}
fn hiddenValueReason(s: *a.Scope, base: c.JSValue, name: c.JSValue, input: c.JSValue) !c.JSValue {
    const constructor = try s.get(base, "HideStackFramesError");
    return a.duplicate(s.engine, try s.construct(constructor, &.{
        name, input, try s.text("must be a string, Uint8Array, or URL without null bytes"),
    }));
}
fn encodingInvalid(s: *a.Scope, buffer: c.JSValue, encoding: c.JSValue) !c.JSValue {
    const function = try s.get(buffer, "isEncoding");
    const result = try s.call(function, buffer, &.{encoding});
    return a.boolean(s, !s.truthy(result));
}
fn assertEncoding(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = a.Scope.init(engine);
    return s.finish(assertEncodingBody(&s, a.arg(args, 0), roots));
}
fn assertEncodingBody(s: *a.Scope, encoding: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (s.truthy(encoding) and try a.condition(s.engine, encodingInvalid, .{roots[0], encoding}))
        return invalidValue(s, roots[1], try s.text("encoding"), encoding, "is invalid encoding");
    return c.pi_js_undefined();
}
fn encodingIsBuffer(s: *a.Scope, options: c.JSValue) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(options, "encoding"), try s.text("buffer")));
}
fn signalIsUndefined(s: *a.Scope, options: c.JSValue) !c.JSValue {
    return a.boolean(s, c.JS_IsUndefined(try s.get(options, "signal")));
}
fn assignEncoding(s: *a.Scope, options: c.JSValue, encoding: c.JSValue) !c.JSValue {
    try s.put(options, "encoding", encoding);
    return c.pi_js_undefined();
}
fn checkEncoding(s: *a.Scope, function: c.JSValue, options: c.JSValue) !c.JSValue {
    _ = try s.call(function, c.pi_js_undefined(), &.{try s.get(options, "encoding")});
    return c.pi_js_undefined();
}
fn checkSignal(s: *a.Scope, function: c.JSValue, options: c.JSValue) !c.JSValue {
    _ = try s.call(function, c.pi_js_undefined(), &.{try s.get(options, "signal"), try s.text("options.signal")});
    return c.pi_js_undefined();
}
fn getOptions(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = a.Scope.init(engine);
    const frame = OptionsFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, getOptionsBody(&s, frame, args, roots));
}
fn getOptionsBody(s: *a.Scope, frame: *OptionsFrame, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    try frame.copy(.options, a.arg(args, 0));
    const supplied_default = a.arg(args, 1);
    try frame.copy(.default_options, if (c.JS_IsUndefined(supplied_default)) roots[0] else supplied_default);
    if (a.v.nullish(frame.get(.options)) or c.JS_IsFunction(s.engine.context, frame.get(.options)))
        return a.duplicate(s.engine, frame.get(.default_options));
    if (c.JS_IsString(frame.get(.options))) {
        try frame.take(.default_options, spread.copy(s.engine, frame.get(.default_options)));
        _ = try a.expression(s.engine, assignEncoding, .{frame.get(.default_options), frame.get(.options)});
        try frame.copy(.options, frame.get(.default_options));
    } else if (!c.JS_IsObject(frame.get(.options))) {
        return invalidType(s, roots[1], try s.text("options"), &.{ "string", "Object" }, frame.get(.options));
    }
    if (!try a.condition(s.engine, encodingIsBuffer, .{frame.get(.options)})) {
        _ = try a.expression(s.engine, checkEncoding, .{roots[2], frame.get(.options)});
    }
    if (!try a.condition(s.engine, signalIsUndefined, .{frame.get(.options)})) {
        _ = try a.expression(s.engine, checkSignal, .{roots[3], frame.get(.options)});
    }
    return a.duplicate(s.engine, frame.get(.options));
}
fn includes(s: *a.Scope, function: c.JSValue, input: c.JSValue, needle: c.JSValue) !c.JSValue {
    return a.boolean(s, s.truthy(try s.call(function, input, &.{needle})));
}
fn stringIncludesNull(s: *a.Scope, function: c.JSValue, input: c.JSValue) !c.JSValue {
    return includes(s, function, input, try s.text("\x00"));
}
fn validatePathRaw(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = a.Scope.init(engine);
    return s.finish(validatePathBody(&s, args, roots));
}
fn validatePathBody(s: *a.Scope, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const path = a.arg(args, 0);
    const supplied_name = a.arg(args, 1);
    const name = if (c.JS_IsUndefined(supplied_name)) try s.text("path") else supplied_name;
    if (!c.JS_IsString(path) and c.JS_GetTypedArrayType(path) != c.JS_TYPED_ARRAY_UINT8) {
        // The live constructor member is selected before the argument array.
        // Its call expression retires before the returned reason is thrown.
        const reason = try s.own(try a.expression(s.engine, hiddenTypeReason, .{roots[0], name, path}));
        return @as(anyerror!c.JSValue, a.raise(s, reason));
    }
    const path_is_string = c.JS_IsString(path);
    const path_is_uint8_array = c.JS_GetTypedArrayType(path) == c.JS_TYPED_ARRAY_UINT8;
    if ((!path_is_string and !path_is_uint8_array) or
        (path_is_string and !try a.condition(s.engine, stringIncludesNull, .{roots[2], path})) or
        (path_is_uint8_array and !try a.condition(s.engine, includes, .{roots[3], path, c.JS_NewInt32(s.engine.context, 0)})))
        return c.pi_js_undefined();
    const reason = try s.own(try a.expression(s.engine, hiddenValueReason, .{roots[1], name, path}));
    return @as(anyerror!c.JSValue, a.raise(s, reason));
}
fn body(s: *a.Scope, inputs: Inputs) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| {
        inline for (std.meta.fields(Inputs)) |field|
            if (!s.equal(try s.get(known, field.name), @field(inputs, field.name))) return error.ActualFsPathHelperOwnerConflict;
        return a.duplicate(s.engine, known);
    }
    const owner = try s.objectProto(c.pi_js_null());
    inline for (std.meta.fields(Inputs)) |field| try s.put(owner, field.name, @field(inputs, field.name));
    const assert_encoding = try s.own(try functions.create(s.engine, "assertEncoding", 1, true, assertEncoding,
        &.{inputs.buffer, inputs.invalid_arg_value}));
    const get_options = try s.own(try functions.create(s.engine, "getOptions", 1, true, getOptions,
        &.{inputs.empty_object, inputs.invalid_arg_type, assert_encoding, inputs.validate_abort_signal}));
    const raw = try s.own(try functions.create(s.engine, "", 1, false, validatePathRaw,
        &.{inputs.invalid_arg_type, inputs.invalid_arg_value, inputs.string_includes, inputs.typed_array_includes}));
    const validate_path = try registration.wrap(s, raw, inputs.error_constructor, inputs.capture_stack_trace, inputs.reflect_apply);
    try s.put(owner, "assertEncoding", assert_encoding);
    try s.put(owner, "getOptions", get_options);
    try s.put(owner, "validatePath", validate_path);
    return a.duplicate(s.engine, owner);
}
pub fn create(engine: *a.v.em.Engine, inputs: Inputs) !c.JSValue {
    var s = a.Scope.init(engine);
    const candidate = try s.finish(body(&s, inputs));
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return @import("native_node_fs_private_publication.zig").publish(engine, key, candidate);
}
