// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.14.0 Module._resolveFilename body, including actual second options.
//! Real private package/self/ESM helpers are required Source dependencies;
//! neither SourceLoader.normalizeRequire nor an identity function substitutes.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const lookup = @import("native_node_commonjs_lookup.zig");
pub const Inputs = struct {
    lookup: lookup.Inputs,
    get_cjs_conditions: c.JSValue,
    nearest_package_json: c.JSValue,
    path_to_file_url: c.JSValue,
    package_imports_resolve: c.JSValue,
    finalize_esm_resolution: c.JSValue,
    esm_not_found_error: c.JSValue,
    try_self_parent_path: c.JSValue,
    try_self: c.JSValue,
    first_parent: c.JSValue,
    array_join: c.JSValue,
    error_constructor: c.JSValue,
    process: c.JSValue,
};
const input_count = lookup.captured_root_count;
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var values: [input_count + 12]c.JSValue = undefined;
    for (lookup.captureRoots(engine, inputs.lookup), 0..) |value, index| values[index] = value;
    const additional = [_]c.JSValue{ inputs.get_cjs_conditions, inputs.nearest_package_json,
        inputs.path_to_file_url, inputs.package_imports_resolve, inputs.finalize_esm_resolution,
        inputs.esm_not_found_error, inputs.try_self_parent_path, inputs.try_self, inputs.first_parent,
        inputs.array_join, inputs.error_constructor, inputs.process };
    for (additional, 0..) |value, index| values[input_count + index] = value;
    return @import("native_node_module_callable.zig").create(engine, "", 4, true, callback, &values);
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn callback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    const inputs: Inputs = .{ .lookup = lookup.restoreRoots(engine, values[0..input_count]),
        .get_cjs_conditions = values[input_count], .nearest_package_json = values[input_count + 1],
        .path_to_file_url = values[input_count + 2], .package_imports_resolve = values[input_count + 3],
        .finalize_esm_resolution = values[input_count + 4], .esm_not_found_error = values[input_count + 5],
        .try_self_parent_path = values[input_count + 6], .try_self = values[input_count + 7],
        .first_parent = values[input_count + 8], .array_join = values[input_count + 9],
        .error_constructor = values[input_count + 10], .process = values[input_count + 11] };
    return resolve(engine, inputs, arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3));
}
pub fn resolve(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent: c.JSValue, is_main: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.truthy(try s.call(inputs.lookup.is_builtin, c.pi_js_undefined(), &.{request}))) return c.JS_DupValue(engine.context, request);
    const requested_conditions = try v.optional(&s, options, "conditions");
    const conditions = if (s.truthy(requested_conditions)) requested_conditions else try s.call(inputs.get_cjs_conditions, c.pi_js_undefined(), &.{});
    const paths = try s.own(try lookup.resolveSearchPaths(engine, inputs.lookup, request, parent, options));
    if (s.equal(try v.at(&s, request, 0), try s.text("#")) and (s.truthy(try v.optional(&s, parent, "filename")) or
        s.equal(try v.optional(&s, parent, "id"), try s.text("<repl>")))) {
        const parent_filename = try v.optional(&s, parent, "filename");
        const parent_path = if (!v.nullish(parent_filename)) parent_filename else path: {
            const process = inputs.process;
            const cwd = try s.get(process, "cwd");
            break :path try s.concat(try s.call(cwd, process, &.{}), try s.get(inputs.lookup.path, "sep"));
        };
        const package = try s.call(inputs.nearest_package_json, c.pi_js_undefined(), &.{parent_path});
        const imports = if (v.nullish(package)) c.pi_js_undefined() else try s.get(try s.get(package, "data"), "imports");
        if (!v.nullish(imports)) {
            const generation = engine.native_allocation_generation;
            if (importsResolution(engine, inputs, request, parent_path, package, conditions)) |result| return result else |err| {
                const reason = try takeOrdinary(engine, err, generation);
                defer engine.freeValue(reason);
                if (s.equal(try s.get(reason, "code"), try s.text("ERR_MODULE_NOT_FOUND"))) {
                    const replacement = try s.call(inputs.esm_not_found_error, c.pi_js_undefined(), &.{request});
                    return throwReason(engine, replacement);
                }
                return throwReason(engine, reason);
            }
        }
    }
    const parent_path = try s.call(inputs.try_self_parent_path, c.pi_js_undefined(), &.{parent});
    const self_resolved = try s.call(inputs.try_self, c.pi_js_undefined(), &.{ parent_path, request, conditions });
    if (s.truthy(self_resolved)) {
        const key_prefix = try s.concat(request, try s.text("\x00"));
        const key_tail = if (s.equal(try s.get(paths, "length"), c.JS_NewInt32(engine.context, 1))) try v.at(&s, paths, 0) else
            try s.call(inputs.array_join, paths, &.{try s.text("\x00")});
        const key = try s.concat(key_prefix, key_tail);
        const path_cache = try s.get(inputs.lookup.module_constructor, "_pathCache");
        try v.js.setKey(engine, path_cache, key, self_resolved);
        return c.JS_DupValue(engine.context, self_resolved);
    }
    const find_path = try s.get(inputs.lookup.module_constructor, "_findPath");
    const filename = try s.call(find_path, inputs.lookup.module_constructor, &.{ request, paths, is_main, conditions });
    if (s.truthy(filename)) return c.JS_DupValue(engine.context, filename);
    const require_stack = try s.array();
    var cursor = c.JS_DupValue(engine.context, parent); defer engine.freeValue(cursor);
    var steps: usize = 0;
    while (s.truthy(cursor)) {
        var frame: Scope = .{ .engine = engine }; defer frame.deinit();
        try @import("native_node_commonjs_interrupt.zig").step(engine, &steps);
        const name = try frame.get(cursor, "filename");
        _ = try frame.call(inputs.lookup.array_push, require_stack, &.{if (frame.truthy(name)) name else try frame.get(cursor, "id")});
        const next = try v.js.call(engine, inputs.first_parent, c.pi_js_undefined(), &.{cursor});
        engine.freeValue(cursor); cursor = next;
    }
    var message = try s.concat(try s.concat(try s.text("Cannot find module '"), try s.stringify(request)), try s.text("'"));
    if (s.truthy(try s.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, try s.get(require_stack, "length"), c.JS_NewInt32(engine.context, 0))))))
        message = try s.concat(try s.concat(message, try s.text("\nRequire stack:\n- ")), try s.call(inputs.array_join, require_stack, &.{try s.text("\n- ")}));
    var arguments = [_]c.JSValue{message};
    const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.error_constructor, arguments.len, &arguments)));
    try s.set(reason, "code", try s.text("MODULE_NOT_FOUND"));
    try s.set(reason, "requireStack", require_stack);
    return throwReason(engine, reason);
}
fn importsResolution(engine: *v.em.Engine, inputs: Inputs, request: c.JSValue, parent_path: c.JSValue, package: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const url = try s.call(inputs.path_to_file_url, c.pi_js_undefined(), &.{parent_path});
    const resolved = try s.call(inputs.package_imports_resolve, c.pi_js_undefined(), &.{ request, url, conditions });
    return v.js.call(engine, inputs.finalize_esm_resolution, c.pi_js_undefined(), &.{ resolved, parent_path, try s.get(package, "path") });
}
fn takeOrdinary(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingActualNodeCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
fn throwReason(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
