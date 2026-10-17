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
fn success(engine: *v.em.Engine, owned: c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) {
        // Own the ACTUAL event before releasing a guest-returned value.
        const pending = c.JS_GetException(engine.context);
        engine.freeValue(owned);
        return engine.checked(c.JS_Throw(engine.context, pending));
    }
    return owned;
}
fn get(s: *v.Scope, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return s.own(try success(s.engine, try v.js.get(s.engine, receiver, name)));
}
fn call(s: *v.Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return s.own(try success(s.engine, try v.js.call(s.engine, function, receiver, args)));
}
fn pending(engine: *v.em.Engine) !void { if (c.JS_HasException(engine.context)) return v.js.capture(engine); }
/// Local CopyDataProperties: a host callback's success+pending event must stop
/// before subsequent Proxy/getter effects. Shared spread policy is untouched.
fn spread(engine: *v.em.Engine, target: c.JSValue, source: c.JSValue) !void {
    if (v.nullish(source)) return;
    const boxed = try success(engine, try engine.checked(c.JS_ToObject(engine.context, source))); defer engine.freeValue(boxed);
    var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
    if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, boxed, c.JS_GPN_STRING_MASK | c.JS_GPN_SYMBOL_MASK) < 0) return v.js.capture(engine);
    defer c.JS_FreePropertyEnum(engine.context, names, count);
    try pending(engine);
    for (names[0..count]) |entry| {
        var descriptor: c.JSPropertyDescriptor = undefined;
        const present = c.JS_GetOwnProperty(engine.context, &descriptor, boxed, entry.atom);
        if (present < 0) return v.js.capture(engine);
        if (present == 0) { try pending(engine); continue; }
        defer engine.freeValue(descriptor.value); defer engine.freeValue(descriptor.getter); defer engine.freeValue(descriptor.setter);
        try pending(engine);
        if (descriptor.flags & c.JS_PROP_ENUMERABLE == 0) continue;
        const value = try success(engine, try engine.checked(c.JS_GetProperty(engine.context, boxed, entry.atom)));
        if (c.JS_DefinePropertyValue(engine.context, target, entry.atom, value, c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    }
}
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
    try pending(engine);
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
    const cached = try success(engine, try v.js.get(engine, roots[0], "transform"));
    const enabled = c.JS_ToBool(engine.context, cached) != 0; engine.freeValue(cached);
    if (!enabled) {
        // Assignment occurs only AFTER both real createRequire and require
        // calls succeed. A failed load is retried; a cached falsy is retried.
        var s: v.Scope = .{ .engine = engine }; defer s.deinit();
        const require = try call(&s, roots[1], c.pi_js_undefined(), &.{roots[2]});
        const transformed = try call(&s, require, c.pi_js_undefined(), &.{try s.text("../dist/babel.cjs")});
        try pending(engine);
        try put(engine, roots[0], "transform", transformed);
    }
    const transform = try success(engine, try v.js.get(engine, roots[0], "transform")); defer engine.freeValue(transform);
    return success(engine, try v.js.call(engine, transform, c.pi_js_undefined(), args));
}
fn createJiti(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    var options = if (c.JS_IsUndefined(arg(args, 1))) try s.object() else arg(args, 1);
    if (!s.truthy(try get(&s, options, "transform"))) {
        const copied = try s.object(); try spread(engine, copied, options);
        try put(engine, copied, "transform", roots[4]); options = copied;
    }
    const parent = try s.object();
    try put(engine, parent, "onError", roots[1]);
    try put(engine, parent, "nativeImport", roots[2]);
    try put(engine, parent, "createRequire", roots[3]);
    return success(engine, try v.js.call(engine, roots[0], c.pi_js_undefined(), &.{ arg(args, 0), options, parent }));
}
