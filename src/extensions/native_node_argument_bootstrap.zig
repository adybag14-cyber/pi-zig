//! Genuine bootstrap cycle closure for internal/assert and argument errors.
//! The real process/Stream owner is already installed by the public bootstrap.
//! No new marker, synthetic inspector, or public Module constructor is created.
const std = @import("std");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const errors = @import("native_node_argument_errors.zig");
const messages = @import("native_node_argument_messages.zig");
const specific = @import("native_node_argument_specific_type.zig");
const assertion = @import("native_node_internal_assert.zig");
const inspector = @import("native_node_internal_inspect_binding.zig");

pub const Prepared = struct {
    internal_inspect: c.JSValue,
    assert_function: c.JSValue,
    arguments: errors.Exports,
    pub fn deinit(self: Prepared, engine: *a.v.em.Engine) void {
        var completion = a.owned.Completion.initVoid(engine, {});
        completion.release(self.internal_inspect);
        completion.release(self.assert_function);
        inline for (std.meta.fields(errors.Exports)) |field|
            completion.release(@field(self.arguments, field.name));
        completion.finishVoid() catch {};
    }
};
fn adopt(s: *a.Scope, value: anytype) !void {
    const T = @TypeOf(value);
    var values: [std.meta.fields(T).len]c.JSValue = undefined;
    inline for (std.meta.fields(T), 0..) |field, position| values[position] = @field(value, field.name);
    for (&values, 0..) |*slot, position| {
        const moved = slot.*; slot.* = c.pi_js_undefined();
        _ = s.own(moved) catch |err| {
            for (values[position + 1 ..]) |*remaining| s.boundary.release(remaining);
            return err;
        };
    }
}
pub fn prepare(engine: *a.v.em.Engine) !Prepared {
    var s = a.Scope.init(engine);
    var output = [_]c.JSValue{c.pi_js_undefined()} ** 7;
    var failure: ?anyerror = null;
    if (prepareBody(&s)) |result| output = result else |err| failure = err;
    try s.boundary.finishMany(failure, &s.values, &output);
    return .{
        .internal_inspect = output[0], .assert_function = output[1],
        .arguments = .{ .invalid_arg_type = output[2], .hidden_invalid_arg_type = output[3],
            .invalid_arg_value = output[4], .internal_assertion = output[5], .validate_string = output[6] },
    };
}
fn prepareBody(s: *a.Scope) ![7]c.JSValue {
    try s.pending();
    const inspect_record = try s.own(try inspector.acquire(s.engine));
    const assert_function = try s.own(try assertion.create(s.engine));
    const arguments = if (try errors.acquire(s.engine)) |known| known else created: {
        const core = try s.own(a.duplicate(s.engine, try @import("native_node_stream.zig").owner(s.engine)));
        const system_errors = try s.own(a.duplicate(s.engine, try @import("native_node_system_errors.zig").registry(s.engine)));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        const string = try s.get(global, "String");
        const strings = try s.get(string, "prototype");
        const determine = try s.own(try specific.create(s.engine, .{
            .internal_inspect = inspect_record, .string = string,
            .json_stringify = try s.get(try s.get(global, "JSON"), "stringify"),
            .string_slice = try s.get(strings, "slice"),
            .string_index_of = try s.get(strings, "indexOf"),
        }));
        const actual_messages = try messages.create(s.engine, .{
            .internal_inspect = inspect_record, .assert = assert_function, .determine_specific_type = determine,
        });
        try adopt(s, actual_messages);
        const error_constructor = try s.get(core, "Error");
        break :created try errors.create(s.engine, .{
            .error_constructor = error_constructor,
            .type_error = try s.get(core, "TypeError"), .range_error = try s.get(core, "RangeError"),
            .marker = try s.get(system_errors, "marker"), .assert_function = assert_function,
            .capture_stack_trace = try s.get(error_constructor, "captureStackTrace"),
            .reflect_apply = try s.get(try s.get(global, "Reflect"), "apply"),
            .array_unshift = try s.get(try s.get(try s.get(global, "Array"), "prototype"), "unshift"),
            .invalid_arg_type_message = actual_messages.invalid_arg_type,
            .invalid_arg_value_message = actual_messages.invalid_arg_value,
            .internal_assertion_message = actual_messages.internal_assertion,
        });
    };
    try adopt(s, arguments);
    return .{ a.duplicate(s.engine, inspect_record), a.duplicate(s.engine, assert_function),
        a.duplicate(s.engine, arguments.invalid_arg_type), a.duplicate(s.engine, arguments.hidden_invalid_arg_type),
        a.duplicate(s.engine, arguments.invalid_arg_value), a.duplicate(s.engine, arguments.internal_assertion),
        a.duplicate(s.engine, arguments.validate_string) };
}
