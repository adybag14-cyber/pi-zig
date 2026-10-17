//! Host admission of an already converted native CJS body into the actual
//! canonical Module/cache. This is not a filesystem loader or compiler.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const constructor = @import("native_node_module_constructor.zig");
pub const Inputs = struct {
    module_constructor: c.JSValue,
    filename: c.JSValue,
    parent: c.JSValue,
    /// Exact completed native implementation supplied by its real owner.
    exports: c.JSValue,
};
fn property(s: *Scope, value: c.JSValue, key: c.JSValue) !c.JSValue { return s.own(try v.js.getKey(s.engine, value, key)); }
fn remove(s: *Scope, value: c.JSValue, key: c.JSValue) !void {
    const atom = try v.js.atom(s.engine, key);
    defer c.JS_FreeAtom(s.engine.context, atom);
    if (c.JS_DeleteProperty(s.engine.context, value, atom, c.JS_PROP_THROW) < 0) return v.js.capture(s.engine);
}
fn setPrivate(s: *Scope, inputs: Inputs, module: c.JSValue, key: constructor.LoaderKey, value: c.JSValue) !void {
    try v.js.setKey(s.engine, module, try s.own(try constructor.loaderKey(s.engine, inputs.module_constructor, key)), value);
}
fn initialize(s: *Scope, inputs: Inputs, module: c.JSValue, paths: c.JSValue) !void {
    if (v.nullish(try s.get(module, "filename"))) try s.set(module, "filename", inputs.filename);
    if (v.nullish(try s.get(module, "paths"))) {
        // Same live callee-before-dirname order as Module.prototype.load.
        const node_paths = try s.get(inputs.module_constructor, "_nodeModulePaths");
        const dirname = try s.invoke(paths, "dirname", &.{inputs.filename});
        try s.set(module, "paths", try s.call(node_paths, inputs.module_constructor, &.{dirname}));
    }
    // This assignment is the explicit native-converted body. No generated JS,
    // substitute require, fake parse result or fabricated extension handler.
    try s.set(module, "exports", inputs.exports);
    try s.set(module, "loaded", c.pi_js_bool(s.engine.context, 1));
    try constructor.snapshotExports(s.engine, inputs.module_constructor, module, try s.get(module, "exports"));
}
fn initializeWithCleanup(s: *Scope, inputs: Inputs, module: c.JSValue, paths: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    initialize(s, inputs, module, paths) catch |err| {
        if (err != error.JavaScriptException) return err;
        const original = s.engine.captured_exception orelse return error.MissingConvertedModuleException;
        if (c.JS_IsUncatchableError(original)) return err;
        try @import("native_async_body.zig").rethrowRecognizedAllocation(s.engine, original, generation);
        s.engine.captured_exception = null;
        const cache = s.get(inputs.module_constructor, "_cache") catch |cleanup_error| { s.engine.freeValue(original); return cleanup_error; };
        remove(s, cache, inputs.filename) catch |cleanup_error| { s.engine.freeValue(original); return cleanup_error; };
        constructor.removeChild(s.engine, inputs.module_constructor, inputs.parent, module) catch |cleanup_error| { s.engine.freeValue(original); return cleanup_error; };
        if (s.engine.captured_exception) |prior| s.engine.freeValue(prior);
        s.engine.captured_exception = original;
        return err;
    };
}
/// Returns an owned real Module. Caller keeps every Inputs value alive through
/// the call. The exact constructor/private parent map authenticates records;
/// matching a public prototype or user properties is insufficient.
pub fn publish(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return publishBody(engine, inputs) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            try @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation);
        };
        return err;
    };
}
fn publishBody(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!c.JS_IsString(inputs.filename)) return error.ConvertedModuleRequiresPhysicalFilename;
    // Authenticates before reading arbitrary guest cache/module properties.
    const paths = try s.own(try constructor.pathObject(engine, inputs.module_constructor));
    const cache = try s.get(inputs.module_constructor, "_cache");
    if (!s.equal(cache, engine.commonjs_cache)) return error.ConvertedModuleRequiresCanonicalCache;
    const existing = try property(&s, cache, inputs.filename);
    if (!c.JS_IsUndefined(existing)) {
        if (!try constructor.hasPrivateModuleRecord(engine, inputs.module_constructor, existing)) return error.ConvertedModuleCacheCollision;
        if (!s.equal(try s.get(existing, "filename"), inputs.filename) or !s.equal(try s.get(existing, "exports"), inputs.exports)) return error.ConvertedModuleCacheCollision;
        if (!s.truthy(try s.get(existing, "loaded"))) return error.ConvertedModuleStillInitializing;
        try constructor.addCachedChild(engine, inputs.module_constructor, inputs.parent, existing);
        try constructor.setLastParent(engine, inputs.module_constructor, existing, inputs.parent);
        return c.JS_DupValue(engine.context, existing);
    }
    var args = [_]c.JSValue{ inputs.filename, inputs.parent };
    const module = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.module_constructor, args.len, &args)));
    try setPrivate(&s, inputs, module, .is_main, c.pi_js_bool(engine.context, 0));
    // Publication precedes the native-converted body, exposing the real Module
    // and initial exports to genuine cyclic cache consumers.
    try v.js.setKey(engine, cache, inputs.filename, module);
    try setPrivate(&s, inputs, module, .cached_by_esm, c.pi_js_bool(engine.context, 0));
    try setPrivate(&s, inputs, module, .url, c.pi_js_undefined());
    try setPrivate(&s, inputs, module, .format, c.pi_js_undefined());
    try initializeWithCleanup(&s, inputs, module, paths);
    return c.JS_DupValue(engine.context, module);
}
