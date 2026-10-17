//! Actual jiti/lib/jiti.mjs nativeImport arrow, over qualified C3 Graph0.
//! Source physical basename is captured, never a private-graph ambient token.
const em = @import("engine.zig");
const c = em.c;
// Same raw ABI as qualified native_extension_dynamic_import_graph0141989E9.
extern "c" fn JS_PiDynamicImportGraph0(context: ?*c.JSContext, physical_basename: c.JSValue, specifier: c.JSValue) c.JSValue;
pub fn create(engine: *em.Engine, physical_basename: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(physical_basename)) return error.RequiredPhysicalJitiModuleFilename;
    var roots = [_]c.JSValue{physical_basename};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, invoke, "nativeImport", 1, 0, roots.len, &roots));
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    // No Engine.checked/capture, extra Promise, user then lookup or adoption.
    return JS_PiDynamicImportGraph0(context, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined());
}
