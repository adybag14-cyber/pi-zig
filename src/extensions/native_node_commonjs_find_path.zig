// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.14.0 actual Module._findPath. Filesystem/package operations are real
//! private Source dependencies; caller-supplied candidates are not pre-resolved
//! through the incompatible extension SourceLoader normalizer.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const lookup = @import("native_node_commonjs_lookup.zig");
const files = @import("native_node_commonjs_try_files.zig");
pub const Inputs = struct {
    lookup: lookup.Inputs,
    files: files.Inputs,
    get_cjs_conditions: c.JSValue,
    array_join: c.JSValue,
    object_keys: c.JSValue,
    array_push_apply_target: c.JSValue,
    string_char_code_at: c.JSValue,
    resolve_exports: c.JSValue,
    report_module_not_found: c.JSValue,
    invalid_arg_type: c.JSValue,
};
const count = lookup.captured_root_count;
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var values: [count + 14]c.JSValue = undefined;
    for (lookup.captureRoots(engine, inputs.lookup), 0..) |value, index| values[index] = value;
    const tail = [_]c.JSValue{ inputs.files.process, inputs.files.to_real_path, inputs.files.read_package, inputs.files.error_constructor,
        c.pi_js_bool(engine.context, @intFromBool(inputs.files.preserve_symlinks)), c.pi_js_bool(engine.context, @intFromBool(inputs.files.preserve_symlinks_main)),
        inputs.get_cjs_conditions, inputs.array_join, inputs.object_keys, inputs.array_push_apply_target,
        inputs.string_char_code_at, inputs.resolve_exports, inputs.report_module_not_found, inputs.invalid_arg_type };
    for (tail, 0..) |value, index| values[count + index] = value;
    return @import("native_node_module_callable.zig").create(engine, "", 3, true, callback, &values);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn callback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const shared = lookup.restoreRoots(engine, values[0..count]);
    const inputs: Inputs = .{ .lookup = shared, .files = .{ .state = shared.state, .path = shared.path,
        .process = values[count], .to_real_path = values[count + 1], .read_package = values[count + 2], .error_constructor = values[count + 3],
        .preserve_symlinks = c.JS_ToBool(engine.context, values[count + 4]) == 1, .preserve_symlinks_main = c.JS_ToBool(engine.context, values[count + 5]) == 1 },
        .get_cjs_conditions = values[count + 6], .array_join = values[count + 7], .object_keys = values[count + 8],
        .array_push_apply_target = values[count + 9], .string_char_code_at = values[count + 10],
        .resolve_exports = values[count + 11], .report_module_not_found = values[count + 12], .invalid_arg_type = values[count + 13] };
    const conditions = if (c.JS_IsUndefined(arg(args, 3))) try s.call(inputs.get_cjs_conditions, c.pi_js_undefined(), &.{}) else arg(args, 3);
    return find(engine, inputs, arg(args, 0), arg(args, 1), arg(args, 2), conditions);
}
fn character(s: *Scope, inputs: Inputs, request: c.JSValue, offset: i32) !c.JSValue {
    const index = try s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, 1, try s.get(request, "length"), c.JS_NewInt32(s.engine.context, offset))));
    return s.call(inputs.string_char_code_at, request, &.{index});
}
fn number(s: *Scope, value: c.JSValue, expected: i32) bool { return s.equal(value, c.JS_NewInt32(s.engine.context, expected)); }
fn stat(s: *Scope, inputs: Inputs, path: c.JSValue) !c.JSValue {
    return s.call(try s.get(inputs.lookup.state, "stat"), c.pi_js_undefined(), &.{path});
}
pub fn find(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, original_paths: c.JSValue, is_main: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const path = inputs.lookup.path;
    const absolute_method = try s.get(path, "isAbsolute");
    const absolute = s.truthy(try s.call(absolute_method, path, &.{request}));
    var paths = original_paths;
    if (absolute) {
        paths = try s.array(); try s.index(paths, 0, try s.text(""));
    } else if (!s.truthy(paths) or number(&s, try s.get(paths, "length"), 0)) return c.pi_js_bool(engine.context, 0);
    const key = try s.concat(try s.concat(request, try s.text("\x00")), try s.call(inputs.array_join, paths, &.{try s.text("\x00")}));
    const entry = try s.own(try v.js.getKey(engine, try s.get(inputs.lookup.module_constructor, "_pathCache"), key));
    if (s.truthy(entry)) return c.JS_DupValue(engine.context, entry);
    var exts = c.pi_js_undefined();
    const positive_length = s.truthy(try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try s.get(request, "length"), c.JS_NewInt32(engine.context, 0)))));
    const trailing_slash = positive_length and (number(&s, try character(&s, inputs, request, 1), 47) or
        (number(&s, try character(&s, inputs, request, 1), 46) and
        (number(&s, try s.get(request, "length"), 1) or number(&s, try character(&s, inputs, request, 2), 47) or
        (number(&s, try character(&s, inputs, request, 2), 46) and
        (number(&s, try s.get(request, "length"), 2) or number(&s, try character(&s, inputs, request, 3), 47))))));
    var inside = true;
    if (try lookup.isRelative(engine, inputs.lookup, request)) {
        const normalize = try s.get(path, "normalize");
        const normalized = try s.call(normalize, path, &.{request});
        if (s.truthy(try s.call(inputs.lookup.string_starts_with, normalized, &.{try s.text("..")}))) inside = false;
    }
    var index = c.JS_NewInt32(engine.context, 0); defer engine.freeValue(index);
    var steps: usize = 0;
    while (true) {
        var frame: Scope = .{ .engine = engine }; defer frame.deinit();
        if (!frame.truthy(try frame.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, index, try frame.get(paths, "length")))))) break;
        try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
        const current = try frame.own(try v.js.getKey(engine, paths, index));
        if (!c.JS_IsString(current)) return @import("native_node_commonjs_require_function.zig").invalidArgumentType(engine, inputs.invalid_arg_type, "paths", "array of strings", paths);
        const next = try engine.checked(c.JS_PiIncrement(engine.context, index));
        engine.freeValue(index); index = next;
        if (inside and frame.truthy(current) and frame.truthy(try frame.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 4, try stat(&frame, inputs, current), c.JS_NewInt32(engine.context, 1)))))) continue;
        if (!absolute) {
            const exported = try frame.call(inputs.resolve_exports, c.pi_js_undefined(), &.{ current, request, conditions });
            if (frame.truthy(exported)) return c.JS_DupValue(engine.context, exported);
        }
        const resolve = try frame.get(path, "resolve");
        const base = try frame.call(resolve, path, &.{ current, request });
        const rc = try stat(&frame, inputs, base);
        var filename = c.pi_js_undefined();
        if (!trailing_slash) {
            if (number(&frame, rc, 0)) {
                const preserve = if (frame.truthy(is_main)) inputs.files.preserve_symlinks_main else inputs.files.preserve_symlinks;
                filename = if (preserve) try frame.call(try frame.get(path, "resolve"), path, &.{base}) else
                    try frame.call(inputs.files.to_real_path, c.pi_js_undefined(), &.{base});
            }
            if (!frame.truthy(filename)) {
                if (c.JS_IsUndefined(exts)) exts = try s.call(inputs.object_keys, c.pi_js_undefined(), &.{try frame.get(inputs.lookup.module_constructor, "_extensions")});
                filename = try frame.own(try files.extensions(engine, inputs.files, base, exts, is_main));
            }
        }
        if (!frame.truthy(filename) and number(&frame, rc, 1)) {
            if (c.JS_IsUndefined(exts)) exts = try s.call(inputs.object_keys, c.pi_js_undefined(), &.{try frame.get(inputs.lookup.module_constructor, "_extensions")});
            filename = try frame.own(try files.package(engine, inputs.files, base, exts, is_main, request));
        }
        if (frame.truthy(filename)) {
            try v.js.setKey(engine, try frame.get(inputs.lookup.module_constructor, "_pathCache"), key, filename);
            return c.JS_DupValue(engine.context, filename);
        }
        const report_exts = try frame.array(); try frame.index(report_exts, 0, try frame.text(""));
        if (!c.JS_IsUndefined(exts)) _ = try frame.call(inputs.lookup.reflect_apply, c.pi_js_undefined(), &.{ inputs.array_push_apply_target, report_exts, exts });
        _ = try frame.call(inputs.report_module_not_found, c.pi_js_undefined(), &.{ base, report_exts });
    }
    return c.pi_js_bool(engine.context, 0);
}
