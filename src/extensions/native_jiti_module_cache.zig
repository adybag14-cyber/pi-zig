//! Actual jiti2.7.0 require.ts/eval.ts cache operations. These JS cache roots
//! are independent of context-pinned private C graphs; no graph is retired here.
//! Derived from jiti2.7.0, Copyright Pooya Parsa, MIT; see the retained authority LICENSE.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const interop = @import("native_jiti_interop.zig");
pub const Lookup = struct { hit: bool, value: c.JSValue };
/// Owned actual ctx.parentCache || {} value. Root jitiRequire calls receive a
/// new ordinary object when there is no truthy parent cache; nested contexts
/// retain the original object. Source Object.prototype behavior is preserved.
pub fn forRequire(engine: *v.em.Engine, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const parent = try s.get(context, "parentCache");
    return if (s.truthy(parent)) c.JS_DupValue(engine.context, parent) else v.js.object(engine);
}
/// Owned optional cached export. Read cache[filename] twice on a parent hit,
/// matching Source's if condition followed by optional-chain exports lookup.
pub fn lookup(engine: *v.em.Engine, context: c.JSValue, parent: c.JSValue, filename: c.JSValue) !Lookup {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.own(try v.js.getKey(engine, parent, filename));
    if (s.truthy(first)) {
        const second = try s.own(try v.js.getKey(engine, parent, filename));
        const exports = if (v.nullish(second)) c.pi_js_undefined() else try s.get(second, "exports");
        return .{ .hit = true, .value = try interop.jitiInteropDefault(engine, context, exports) };
    }
    if (s.truthy(try s.get(try s.get(context, "opts"), "moduleCache"))) {
        const cache = try s.get(try s.get(context, "nativeRequire"), "cache");
        const entry = try s.own(try v.js.getKey(engine, cache, filename));
        const loaded = if (v.nullish(entry)) c.pi_js_undefined() else try s.get(entry, "loaded");
        if (s.truthy(loaded)) return .{ .hit = true, .value = try interop.jitiInteropDefault(engine, context, try s.get(entry, "exports")) };
    }
    return .{ .hit = false, .value = c.pi_js_undefined() };
}
/// Publish the caller's real Module before user evaluation, so cycles see its
/// actual partial exports. Source assignment semantics (including setters) are
/// used. No Module/factory/registry is synthesized by this helper.
pub fn publishBeforeEval(engine: *v.em.Engine, context: c.JSValue, parent: c.JSValue, filename: c.JSValue, module: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try v.js.setKey(engine, parent, filename, module);
    if (s.truthy(try s.get(try s.get(context, "opts"), "moduleCache"))) try v.js.setKey(engine, try s.get(try s.get(context, "nativeRequire"), "cache"), filename, module);
}
fn deleteNative(engine: *v.em.Engine, context: c.JSValue, filename: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cache = try s.get(try s.get(context, "nativeRequire"), "cache");
    const atom = try v.js.atom(engine, filename); defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DeleteProperty(engine.context, cache, atom, c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
/// Source eval compile/evaluation catch cleanup only affects nativeRequire.cache
/// when moduleCache is truthy. Parent partial records are NOT globally cleared.
/// Caller retains its original ordinary reason across this fallible operation;
/// an ordinary delete failure overrides it, while fatal failures stay fatal.
pub fn afterEvalFailure(engine: *v.em.Engine, context: c.JSValue, filename: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.truthy(try s.get(try s.get(context, "opts"), "moduleCache"))) try deleteNative(engine, context, filename);
}
/// Source tryNative success cleanup uses === false, not generic falsiness.
/// Deleting the CJS cache does not delete native ESM namespaces or old closures.
pub fn afterNativeSuccess(engine: *v.em.Engine, context: c.JSValue, filename: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.equal(try s.get(try s.get(context, "opts"), "moduleCache"), c.pi_js_bool(engine.context, 0))) try deleteNative(engine, context, filename);
}
/// Source next() tail, after the caller has handled actual __JITI_ERROR__.
/// That Babel marker/stack conversion is deliberately not fabricated here.
pub fn loadedExports(engine: *v.em.Engine, context: c.JSValue, module: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    try s.set(module, "loaded", c.pi_js_bool(engine.context, 1));
    return interop.jitiInteropDefault(engine, context, try s.get(module, "exports"));
}
