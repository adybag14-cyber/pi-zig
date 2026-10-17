// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.14.0 loader.js self/exports package-resolution wrappers. These call
//! the actual Node24 package resolver, not an automatically equivalent older
//! import-meta-resolve clone. Real captured FS/URL/package helpers are required.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct {
    path: c.JSValue,
    process: c.JSValue,
    nearest_package_json: c.JSValue,
    read_package: c.JSValue,
    path_to_file_url: c.JSValue,
    package_exports_resolve: c.JSValue,
    finalize_esm_resolution: c.JSValue,
    esm_not_found_error: c.JSValue,
    regexp_exec: c.JSValue,
    exports_pattern: c.JSValue,
    string_starts_with: c.JSValue,
    string_slice: c.JSValue,
};
pub const Graph = struct { try_self_parent_path: c.JSValue, try_self: c.JSValue, resolve_exports: c.JSValue };
pub fn createPattern(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var args = [_]c.JSValue{try s.text("^((?:@[^/\\\\%]+/)?[^./\\\\%][^/\\\\%]*)(/.*)?$")};
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, args.len, &args));
}
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Graph {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const values = [_]c.JSValue{ inputs.path, inputs.process, inputs.nearest_package_json, inputs.read_package,
        inputs.path_to_file_url, inputs.package_exports_resolve, inputs.finalize_esm_resolution, inputs.esm_not_found_error,
        inputs.regexp_exec, inputs.exports_pattern, inputs.string_starts_with, inputs.string_slice };
    const functions = @import("native_node_module_callable.zig");
    const parent = try s.own(try functions.create(engine, "trySelfParentPath", 1, true, parentCallback, &values));
    const self_function = try s.own(try functions.create(engine, "trySelf", 3, true, selfCallback, &values));
    const exports_function = try s.own(try functions.create(engine, "resolveExports", 3, true, exportsCallback, &values));
    return .{ .try_self_parent_path = c.JS_DupValue(engine.context, parent), .try_self = c.JS_DupValue(engine.context, self_function), .resolve_exports = c.JS_DupValue(engine.context, exports_function) };
}
fn fromRoots(values: []const c.JSValue) Inputs {
    return .{ .path = values[0], .process = values[1], .nearest_package_json = values[2], .read_package = values[3],
        .path_to_file_url = values[4], .package_exports_resolve = values[5], .finalize_esm_resolution = values[6], .esm_not_found_error = values[7],
        .regexp_exec = values[8], .exports_pattern = values[9], .string_starts_with = values[10], .string_slice = values[11] };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn parentCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return parentPath(engine, fromRoots(values), arg(args, 0));
}
fn selfCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return self(engine, fromRoots(values), arg(args, 0), arg(args, 1), arg(args, 2));
}
fn exportsCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return exports(engine, fromRoots(values), arg(args, 0), arg(args, 1), arg(args, 2));
}
pub fn parentPath(engine: *v.em.Engine, inputs: Inputs, parent: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(parent)) return c.pi_js_bool(engine.context, 0);
    if (s.truthy(try s.get(parent, "filename"))) return v.js.get(engine, parent, "filename");
    if (s.equal(try s.get(parent, "id"), try s.text("<repl>")) or s.equal(try s.get(parent, "id"), try s.text("internal/preload"))) {
        const generation = engine.native_allocation_generation;
        return cwdPath(engine, inputs) catch |err| {
            const reason = try takeOrdinary(engine, err, generation); engine.freeValue(reason);
            return c.pi_js_bool(engine.context, 0);
        };
    }
    return c.pi_js_undefined();
}
fn cwdPath(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cwd = try s.get(inputs.process, "cwd");
    const directory = try s.call(cwd, inputs.process, &.{});
    return c.JS_DupValue(engine.context, try s.concat(directory, try s.get(inputs.path, "sep")));
}
pub fn self(engine: *v.em.Engine, inputs: Inputs, parent_path: c.JSValue, request: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(parent_path)) return c.pi_js_bool(engine.context, 0);
    const package = try s.call(inputs.nearest_package_json, c.pi_js_undefined(), &.{parent_path});
    const exported = if (v.nullish(package)) c.pi_js_undefined() else try s.get(try s.get(package, "data"), "exports");
    if (c.JS_IsUndefined(exported) or c.JS_IsUndefined(try s.get(try s.get(package, "data"), "name"))) return c.pi_js_bool(engine.context, 0);
    var expansion = c.pi_js_undefined();
    if (s.equal(request, try s.get(try s.get(package, "data"), "name"))) expansion = try s.text(".") else {
        const name = try s.get(try s.get(package, "data"), "name");
        const prefix = try s.concat(try s.stringify(name), try s.text("/"));
        if (!s.truthy(try s.call(inputs.string_starts_with, request, &.{prefix}))) return c.pi_js_bool(engine.context, 0);
        const size = try s.get(try s.get(try s.get(package, "data"), "name"), "length");
        expansion = try s.concat(try s.text("."), try s.call(inputs.string_slice, request, &.{size}));
    }
    const generation = engine.native_allocation_generation;
    return selfResolution(engine, inputs, package, expansion, parent_path, conditions) catch |err| {
        const reason = try takeOrdinary(engine, err, generation); defer engine.freeValue(reason);
        if (s.equal(try s.get(reason, "code"), try s.text("ERR_MODULE_NOT_FOUND"))) {
            const replacement = try s.call(inputs.esm_not_found_error, c.pi_js_undefined(), &.{ request, try s.get(package, "path") });
            return throwReason(engine, replacement);
        }
        return throwReason(engine, reason);
    };
}
fn selfResolution(engine: *v.em.Engine, inputs: Inputs, package: c.JSValue, expansion: c.JSValue, parent_path: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const package_url = try s.call(inputs.path_to_file_url, c.pi_js_undefined(), &.{try s.get(package, "path")});
    const data = try s.get(package, "data");
    const parent_url = try s.call(inputs.path_to_file_url, c.pi_js_undefined(), &.{parent_path});
    const resolved = try s.call(inputs.package_exports_resolve, c.pi_js_undefined(), &.{ package_url, expansion, data, parent_url, conditions });
    return v.js.call(engine, inputs.finalize_esm_resolution, c.pi_js_undefined(), &.{ resolved, parent_path, try s.get(package, "path") });
}
pub fn exports(engine: *v.em.Engine, inputs: Inputs, node_modules: c.JSValue, request: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const result = try s.call(inputs.regexp_exec, inputs.exports_pattern, &.{request});
    const name = if (s.truthy(result)) try v.at(&s, result, 1) else c.pi_js_undefined();
    const candidate_expansion = if (s.truthy(result)) try v.at(&s, result, 2) else c.pi_js_undefined();
    const expansion = if (c.JS_IsUndefined(candidate_expansion)) try s.text("") else candidate_expansion;
    if (!s.truthy(name)) return c.pi_js_undefined();
    const resolve = try s.get(inputs.path, "resolve");
    const package_path = try s.call(resolve, inputs.path, &.{ node_modules, name });
    const package = try s.call(inputs.read_package, c.pi_js_undefined(), &.{package_path});
    if (s.truthy(try s.get(package, "exists")) and !v.nullish(try s.get(package, "exports"))) {
        const generation = engine.native_allocation_generation;
        return exportsResolution(engine, inputs, package_path, expansion, package, conditions) catch |err| {
            const reason = try takeOrdinary(engine, err, generation); defer engine.freeValue(reason);
            if (s.equal(try s.get(reason, "code"), try s.text("ERR_MODULE_NOT_FOUND"))) {
                const json_path = try s.concat(package_path, try s.text("/package.json"));
                const replacement = try s.call(inputs.esm_not_found_error, c.pi_js_undefined(), &.{ request, json_path });
                return throwReason(engine, replacement);
            }
            return throwReason(engine, reason);
        };
    }
    return c.pi_js_undefined();
}
fn exportsResolution(engine: *v.em.Engine, inputs: Inputs, path: c.JSValue, expansion: c.JSValue, package: c.JSValue, conditions: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const json_path = try s.concat(path, try s.text("/package.json"));
    const url = try s.call(inputs.path_to_file_url, c.pi_js_undefined(), &.{json_path});
    const subpath = try s.concat(try s.text("."), expansion);
    const result = try s.call(inputs.package_exports_resolve, c.pi_js_undefined(), &.{ url, subpath, package, c.pi_js_null(), conditions });
    return v.js.call(engine, inputs.finalize_esm_resolution, c.pi_js_undefined(), &.{ result, c.pi_js_null(), path });
}
fn takeOrdinary(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingActualNodePackageReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null; return reason;
}
fn throwReason(engine: *v.em.Engine, reason: c.JSValue) anyerror {
    _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason))) catch |err| return err;
    unreachable;
}
