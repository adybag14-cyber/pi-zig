// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24.14.0 actual .js/.json/.node extension-handler bodies.
//! A registry is not publishable until its real loader/compiler/NAPI inputs
//! exist. No handler pretends to implement a missing native-addon runtime.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
pub const Inputs = struct {
    load_source: c.JSValue,
    nearest_package_json: c.JSValue,
    require_esm_error: c.JSValue,
    process: c.JSValue,
    path: c.JSValue,
    json_parse: c.JSValue,
    strip_bom: c.JSValue,
    string_ends_with: c.JSValue,
    strip_types: bool,
    require_module: bool,
};
const Kind = enum { javascript, json, addon };
fn roots(engine: *v.em.Engine, inputs: Inputs) [10]c.JSValue {
    return .{ inputs.load_source, inputs.nearest_package_json, inputs.require_esm_error,
        inputs.process, inputs.path, inputs.json_parse, inputs.strip_bom, inputs.string_ends_with,
        c.pi_js_bool(engine.context, @intFromBool(inputs.strip_types)), c.pi_js_bool(engine.context, @intFromBool(inputs.require_module)) };
}
fn fromRoots(engine: *v.em.Engine, values: []const c.JSValue) Inputs {
    return .{ .load_source = values[0], .nearest_package_json = values[1], .require_esm_error = values[2],
        .process = values[3], .path = values[4], .json_parse = values[5], .strip_bom = values[6], .string_ends_with = values[7],
        .strip_types = c.JS_ToBool(engine.context, values[8]) == 1, .require_module = c.JS_ToBool(engine.context, values[9]) == 1 };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn method(engine: *v.em.Engine, inputs: Inputs, comptime kind: Kind) !c.JSValue {
    const values = roots(engine, inputs);
    const callback = switch (kind) { .javascript => jsCallback, .json => jsonCallback, .addon => addonCallback };
    return @import("native_node_module_callable.zig").create(engine, "", 2, true, callback, &values);
}
/// Returns an owned null-prototype registry with the three real Source handlers.
/// Bootstrap must provide a genuine process.dlopen before this registry can be
/// selected; a stub that always throws is not an admissible binding.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!c.JS_IsFunction(engine.context, inputs.load_source) or
        !c.JS_IsFunction(engine.context, inputs.nearest_package_json) or
        !c.JS_IsFunction(engine.context, inputs.require_esm_error) or
        !c.JS_IsFunction(engine.context, inputs.json_parse) or
        !c.JS_IsFunction(engine.context, inputs.strip_bom) or
        !c.JS_IsFunction(engine.context, try s.get(inputs.process, "dlopen"))) return error.ActualNodeCommonJSLoaderDependenciesRequired;
    const object = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try s.put(object, ".js", try s.own(try method(engine, inputs, .javascript)));
    try s.put(object, ".json", try s.own(try method(engine, inputs, .json)));
    try s.put(object, ".node", try s.own(try method(engine, inputs, .addon)));
    return c.JS_DupValue(engine.context, object);
}
fn ends(s: *Scope, inputs: Inputs, filename: c.JSValue, suffix: []const u8) !bool {
    return s.truthy(try s.call(inputs.string_ends_with, filename, &.{try s.text(suffix)}));
}
fn jsCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return javascript(engine, fromRoots(engine, values), arg(args, 0), arg(args, 1));
}
pub fn javascript(engine: *v.em.Engine, inputs: Inputs, module: c.JSValue, filename: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var format = c.pi_js_undefined();
    var package = c.pi_js_undefined();
    if (try ends(&s, inputs, filename, ".cjs")) format = try s.text("commonjs") else
    if (try ends(&s, inputs, filename, ".mjs")) format = try s.text("module") else
    if (try ends(&s, inputs, filename, ".js")) {
        package = try s.call(inputs.nearest_package_json, c.pi_js_undefined(), &.{filename});
        const data = try v.optional(&s, package, "data");
        const package_type = if (v.nullish(package)) c.pi_js_undefined() else try s.get(data, "type");
        if (s.equal(package_type, try s.text("module")) or s.equal(package_type, try s.text("commonjs")) or !s.truthy(package_type)) format = package_type;
    } else if (try ends(&s, inputs, filename, ".mts") and inputs.strip_types) format = try s.text("module-typescript") else
    if (try ends(&s, inputs, filename, ".cts") and inputs.strip_types) format = try s.text("commonjs-typescript") else
    if (try ends(&s, inputs, filename, ".ts") and inputs.strip_types) {
        package = try s.call(inputs.nearest_package_json, c.pi_js_undefined(), &.{filename});
        const data = try v.optional(&s, package, "data");
        const package_type = if (v.nullish(package)) c.pi_js_undefined() else try s.get(data, "type");
        format = if (s.equal(package_type, try s.text("module"))) try s.text("module-typescript") else
            if (s.equal(package_type, try s.text("commonjs"))) try s.text("commonjs-typescript") else try s.text("typescript");
    }
    const loaded = try s.call(inputs.load_source, c.pi_js_undefined(), &.{ module, filename, format });
    const source = try s.get(loaded, "source");
    const loaded_format = try s.get(loaded, "format");
    if ((s.equal(loaded_format, try s.text("module")) or s.equal(loaded_format, try s.text("module-typescript"))) and !inputs.require_module) {
        const reason = try s.call(inputs.require_esm_error, c.pi_js_undefined(), &.{ module, package, source, filename });
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
    const compile = try s.get(module, "_compile");
    _ = try s.call(compile, module, &.{ source, filename, loaded_format });
    return c.pi_js_undefined();
}
fn jsonCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    return json(engine, fromRoots(engine, values), arg(args, 0), arg(args, 1));
}
pub fn json(engine: *v.em.Engine, inputs: Inputs, module: c.JSValue, filename: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const loaded = try s.call(inputs.load_source, c.pi_js_undefined(), &.{ module, filename, try s.text("json") });
    const source = try s.get(loaded, "source");
    const generation = engine.native_allocation_generation;
    parseJson(engine, inputs, module, source) catch |err| {
        if (err != error.JavaScriptException) return err;
        const reason = engine.captured_exception orelse return error.MissingNodeJsonException;
        if (c.JS_IsUncatchableError(reason)) return err;
        try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
        engine.captured_exception = null;
        defer engine.freeValue(reason);
        const prefix = try s.concat(filename, try s.text(": "));
        const message = try s.get(reason, "message");
        try s.set(reason, "message", try s.concat(prefix, message));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    };
    return c.pi_js_undefined();
}
fn parseJson(engine: *v.em.Engine, inputs: Inputs, module: c.JSValue, source: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const stripped = try s.call(inputs.strip_bom, c.pi_js_undefined(), &.{source});
    const value = try s.call(inputs.json_parse, c.pi_js_undefined(), &.{stripped});
    try s.put(module, "exports", value);
}
fn addonCallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, values: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const inputs = fromRoots(engine, values);
    const dlopen = try s.get(inputs.process, "dlopen");
    const namespaced = try s.get(inputs.path, "toNamespacedPath");
    const path = try s.call(namespaced, inputs.path, &.{arg(args, 1)});
    return v.js.call(engine, dlopen, inputs.process, &.{ arg(args, 0), path });
}
