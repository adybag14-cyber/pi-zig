//! Actual raw queued-import binding for the separately reviewed Graph0 C ABI.
//! No AsyncFunction, Promise adoption, JS_LoadModule or ambient graph is used.
//! The required C symbol is intentionally unavailable until Root intakes and
//! qualifies its current vendor delta; this module is never auto-selected.
const em = @import("engine.zig");
const c = em.c;
// Kept explicit instead of copying an older/newer vendor header into this tree.
// Signature matches reviewed ae342bba / 0f424a02 DA14 C / A79 H exactly.
extern "c" fn JS_PiDynamicImportGraph0(context: ?*c.JSContext, physical_basename: c.JSValue, specifier: c.JSValue) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    return engine.checked(c.JS_NewCFunction(engine.context, invoke, "importModule", 2));
}
fn invoke(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const base = if (argc > 0) argv[0] else c.pi_js_undefined();
    const specifier = if (argc > 1) argv[1] else c.pi_js_undefined();
    // Forward borrowed values and return the exact native Promise or exception.
    // The C ABI duplicates/owns the base and queues the actual dynamic job.
    return JS_PiDynamicImportGraph0(context, base, specifier);
}
