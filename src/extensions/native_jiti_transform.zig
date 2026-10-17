//! Actual jiti2.7 transform.ts orchestration, not a default Babel substitute.
//! Derived from jiti, Copyright Pooya Parsa, MIT; retained source/LICENSE.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const cache = @import("native_jiti_fs_cache.zig");
pub const Inputs = struct { get_cache: c.JSValue, debug: c.JSValue };
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, inputs.get_cache) or !c.JS_IsFunction(engine.context, inputs.debug)) return error.RequiredActualJitiTransformImport;
    return functions.create(engine, "transform", 2, true, call, &.{ inputs.get_cache, inputs.debug });
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return transform(engine, .{ .get_cache = roots[0], .debug = roots[1] }, arg(args, 0), arg(args, 1));
}
pub fn transform(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return transformValues(engine, inputs, context, options) catch |err| return cache.exactFailure(engine, err, generation);
}
fn transformValues(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const get = try s.own(try functions.create(engine, "", 0, false, generate, &.{ context, options, inputs.debug }));
    var code = try s.call(inputs.get_cache, c.pi_js_undefined(), &.{ context, options, get });
    if (s.truthy(try s.invoke(code, "startsWith", &.{try s.text("#!")}))) code = try s.concat(try s.text("// "), code);
    return c.JS_DupValue(engine.context, code);
}
fn generate(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const context = roots[0]; const top_options = roots[1];
    // Source acquires ctx.opts.transform and its receiver before evaluating
    // any option spread/getter. A user hook is called as that actual method.
    const receiver = try s.get(context, "opts");
    const function = try s.get(receiver, "transform");
    const options = try s.object();
    try v.js.spreadInto(engine, options, try s.get(try s.get(context, "opts"), "transformOptions"));
    const babel = try s.object();
    if (s.truthy(try s.get(try s.get(context, "opts"), "sourceMaps"))) {
        try s.put(babel, "sourceFileName", try s.get(top_options, "filename"));
        try s.put(babel, "sourceMaps", try s.text("inline"));
    }
    const transform_options = try s.get(try s.get(context, "opts"), "transformOptions");
    const babel_options = if (v.nullish(transform_options)) c.pi_js_undefined() else try s.get(transform_options, "babel");
    try v.js.spreadInto(engine, babel, babel_options);
    try s.put(options, "babel", babel);
    try s.put(options, "interopDefault", try s.get(try s.get(context, "opts"), "interopDefault"));
    try v.js.spreadInto(engine, options, top_options);
    const result = try s.call(function, receiver, &.{options});
    if (s.truthy(try s.get(result, "error")) and s.truthy(try s.get(try s.get(context, "opts"), "debug"))) {
        const error_value = try s.get(result, "error");
        const ignored = try v.js.call(engine, roots[2], c.pi_js_undefined(), &.{ context, error_value }); engine.freeValue(ignored);
    }
    return v.js.get(engine, result, "code");
}
