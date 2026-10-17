//! Actual public jiti2.7 lib/jiti.mjs wrapper and module-scoped lazy transform.
//! Canonical core comes only from the real once-linked production assembler.
//! Derived from jiti, Copyright Pooya Parsa, MIT; primary/license retained.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const f = @import("native_node_module_callable.zig");
const graph = @import("native_jiti_core_graph.zig");
const native_import = @import("native_jiti_native_import.zig");
pub const Inputs = struct {
    canonical: graph.cells.CanonicalBindings,
    /// Genuine shared Node.Module createRequire; legacy loader is not admitted
    /// as a complete bootstrap. Its owner publishes the actual Babel module.
    create_require: c.JSValue,
    /// Physical lib/jiti.mjs basename and its actual import.meta.url string.
    physical_filename: c.JSValue,
    module_url: c.JSValue,
};
pub const Exports = struct {
    create_jiti: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void { engine.freeValue(self.create_jiti); }
};
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
/// No module registration/default activation. Caller retains one completed
/// module graph per Source module lifetime and publishes real ESM exports only
/// after its external Node/CommonJS/default-transform dependencies are ready.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (!c.JS_IsFunction(engine.context, inputs.create_require)) return error.RequiredActualNodeCreateRequire;
    if (!c.JS_IsString(inputs.physical_filename) or !c.JS_IsString(inputs.module_url)) return error.RequiredPhysicalJitiModuleIdentity;
    var cells = try graph.createCanonical(engine, inputs.canonical); defer cells.deinit(engine);
    const actual = try graph.cells.exports(engine, &cells);
    defer engine.freeValue(actual.create_jiti); defer engine.freeValue(actual.eval_module);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // Private lexical cell, never exposed as an ordinary Source property.
    const lexical = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try put(engine, lexical, "transform", c.pi_js_undefined());
    const on_error = try s.own(try f.create(engine, "onError", 1, true, onError, &.{}));
    const import_function = try s.own(try native_import.create(engine, inputs.physical_filename));
    const lazy_transform = try s.own(try f.create(engine, "lazyTransform", 0, true, lazyTransform, &.{ lexical, inputs.create_require, inputs.module_url }));
    const public = try f.create(engine, "createJiti", 1, true, createJiti, &.{ actual.create_jiti, on_error, import_function, inputs.create_require, lazy_transform });
    return .{ .create_jiti = public };
}
fn onError(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, arg(args, 0))));
}
fn lazyTransform(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const cached = try v.js.get(engine, roots[0], "transform");
    const enabled = c.JS_ToBool(engine.context, cached) != 0; engine.freeValue(cached);
    if (!enabled) {
        // Assignment occurs only AFTER both real createRequire and require
        // calls succeed. A failed load is retried; a cached falsy is retried.
        var s: v.Scope = .{ .engine = engine }; defer s.deinit();
        const require = try s.call(roots[1], c.pi_js_undefined(), &.{roots[2]});
        const transformed = try s.call(require, c.pi_js_undefined(), &.{try s.text("../dist/babel.cjs")});
        try put(engine, roots[0], "transform", transformed);
    }
    const transform = try v.js.get(engine, roots[0], "transform"); defer engine.freeValue(transform);
    return v.js.call(engine, transform, c.pi_js_undefined(), args);
}
fn createJiti(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var options = if (c.JS_IsUndefined(arg(args, 1))) try s.object() else arg(args, 1);
    if (!s.truthy(try s.get(options, "transform"))) {
        const spread = try s.object(); try v.js.spreadInto(engine, spread, options);
        try put(engine, spread, "transform", roots[4]); options = spread;
    }
    const parent = try s.object();
    try put(engine, parent, "onError", roots[1]);
    try put(engine, parent, "nativeImport", roots[2]);
    try put(engine, parent, "createRequire", roots[3]);
    return v.js.call(engine, roots[0], c.pi_js_undefined(), &.{ arg(args, 0), options, parent });
}
