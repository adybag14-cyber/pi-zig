//! Trusted host registration of an actual native-converted CJS backend. The
//! registry is readiness, never a guest require cache or an eager Module.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const constructor = @import("native_node_module_constructor.zig");
const functions = @import("native_node_module_callable.zig");
pub const Inputs = struct { module_constructor: c.JSValue, filename: c.JSValue, exports: c.JSValue };
fn exactFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        @import("native_async_body.zig").rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    return err;
}
fn matches(engine: *v.em.Engine, body: c.JSValue, inputs: Inputs) !bool {
    if (c.JS_IsUndefined(body)) return false;
    const roots = try functions.capturedRoots(engine, body);
    return roots.len == 3 and c.JS_IsStrictEqual(engine.context, roots[0], inputs.module_constructor) and
        c.JS_IsStrictEqual(engine.context, roots[1], inputs.filename) and c.JS_IsStrictEqual(engine.context, roots[2], inputs.exports);
}
pub fn register(engine: *v.em.Engine, inputs: Inputs) !void {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return registerBody(engine, inputs) catch |err| return exactFailure(engine, err, generation);
}
fn registerBody(engine: *v.em.Engine, inputs: Inputs) !void {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const paths = try s.own(try constructor.pathObject(engine, inputs.module_constructor));
    if (!c.JS_IsString(inputs.filename) or !c.JS_IsFunction(engine.context, inputs.exports)) return error.ActualConvertedCJSProviderRequired;
    const is_absolute = try s.get(paths, "isAbsolute");
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const absolute = try s.call(is_absolute, paths, &.{inputs.filename});
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    if (!s.truthy(absolute)) return error.ConvertedProviderPhysicalFilenameRequired;
    // This conversion is explicitly CJS and cannot silently claim ESM parse or
    // extension/package-format policy. Other formats use the real compiler.
    const existing = try s.own(try constructor.convertedBody(engine, inputs.module_constructor, inputs.filename));
    if (!c.JS_IsUndefined(existing)) {
        if (!try matches(engine, existing, inputs)) return error.ConflictingConvertedCJSProvider;
        return;
    }
    const body = try s.own(try functions.create(engine, "", 5, true, initialize, &.{ inputs.module_constructor, inputs.filename, inputs.exports }));
    try constructor.retainConvertedBody(engine, inputs.module_constructor, inputs.filename, body);
}
/// Does not read guest Module._cache, construct a Module, set its parent, or
/// publish an ESM namespace. The trusted host uses this to admit lazy readiness.
pub fn ready(engine: *v.em.Engine, inputs: Inputs) !bool {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return readyBody(engine, inputs) catch |err| return exactFailure(engine, err, generation);
}
fn readyBody(engine: *v.em.Engine, inputs: Inputs) !bool {
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return matches(engine, try s.own(try constructor.convertedBody(engine, inputs.module_constructor, inputs.filename)), inputs);
}
/// Actual _compile calls this only for explicit commonjs format while its
/// canonical Module.wrap/wrapper is initialized and unpatched. Returns an owned
/// ordinary native CJS body or undefined; it is not a parse/metadata result.
pub fn compiledBody(engine: *v.em.Engine, module_constructor: c.JSValue, filename: c.JSValue, format: c.JSValue, wrapper_initialized: bool, wrapper_patched: bool) !c.JSValue {
    if (!wrapper_initialized or wrapper_patched) return c.pi_js_undefined();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!try v.eq(&s, format, "commonjs")) return c.pi_js_undefined();
    return constructor.convertedBody(engine, module_constructor, filename);
}
fn initialize(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // Same explicit CJS module argument as a five-argument VM wrapper. Reentry,
    // cache cycles, executing/stat-cache cells and completion belong to the
    // genuine surrounding _load/load/_compile flow, not a second registry.
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const module = if (args.len > 2) args[2] else c.pi_js_undefined();
    try s.set(module, "exports", roots[2]);
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    return c.pi_js_undefined();
}
