//! Actual bootstrap for the internal/fs/utils path helper owner.
//! Requires the genuine process/Stream/Buffer graph before guest execution.
const a = @import("native_node_argument_values.zig");
const c = a.c;
const argument_bootstrap = @import("native_node_argument_bootstrap.zig");
const argument_errors = @import("native_node_argument_errors.zig");
const helpers = @import("native_node_fs_path_helpers.zig");
const key = "pi-native:private/fs-path-helper-bootstrap";
fn adoptArguments(s: *a.Scope, prepared: argument_bootstrap.Prepared) !void {
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
fn body(s: *a.Scope) !c.JSValue {
    try s.pending();
    if (s.engine.native_module_values.get(key)) |known| return a.duplicate(s.engine, known);
    const prepared = try argument_bootstrap.prepare(s.engine);
    try adoptArguments(s, prepared);
    const stream = try s.own(a.duplicate(s.engine, try @import("native_node_stream.zig").owner(s.engine)));
    const buffer_namespace = try s.own(a.duplicate(s.engine,
        s.engine.native_module_values.get("node:buffer") orelse return error.ActualNodeBufferModuleRequired));
    const actual_buffer = try s.get(buffer_namespace, "Buffer");
    const empty = try s.own(try @import("native_node_internal_empty_object.zig").acquire(s.engine));
    const cache_key = try s.own(try @import("native_node_fs_realpath_key.zig").acquire(s.engine));
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const strings = try s.get(try s.get(global, "String"), "prototype");
    const uint8 = try s.get(try s.get(global, "Uint8Array"), "prototype");
    const typed_arrays = try s.prototype(uint8);
    const error_constructor = try s.get(stream, "Error");
    const actual_helpers = try s.own(try helpers.create(s.engine, .{
        .empty_object = empty,
        .buffer = actual_buffer,
        .invalid_arg_type = prepared.arguments.invalid_arg_type,
        .invalid_arg_value = prepared.arguments.invalid_arg_value,
        .hidden_invalid_arg_type = prepared.arguments.hidden_invalid_arg_type,
        .hidden_invalid_arg_value = try s.own(try argument_errors.hiddenValue(s.engine)),
        .validate_abort_signal = try s.own(try argument_errors.validateAbortSignal(s.engine)),
        .error_constructor = error_constructor,
        .capture_stack_trace = try s.get(error_constructor, "captureStackTrace"),
        .reflect_apply = try s.get(try s.get(global, "Reflect"), "apply"),
        .string_includes = try s.get(strings, "includes"),
        .typed_array_includes = try s.get(typed_arrays, "includes"),
    }));
    const owner = try s.objectProto(c.pi_js_null());
    try s.put(owner, "helpers", actual_helpers);
    try s.put(owner, "Buffer", actual_buffer);
    try s.put(owner, "kEmptyObject", empty);
    try s.put(owner, "realpathCacheKey", cache_key);
    return a.duplicate(s.engine, owner);
}
pub fn prepare(engine: *a.v.em.Engine) !c.JSValue {
    var s = a.Scope.init(engine);
    const candidate = try s.finish(body(&s));
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return @import("native_node_fs_private_publication.zig").publish(engine, key, candidate);
}
