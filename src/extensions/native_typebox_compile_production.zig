//! Actual typebox@1.3.27 Compile/Code/Validator dependency graph.
//! Algorithm functions, constructors, contexts, reference stack and visitors
//! have direct native bodies. Default acceleration uses typed native IR.
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const catalog = @import("native_typebox_compile_catalog.zig");
const bootstrap = @import("native_typebox_compile_bootstrap.zig");
const c = js.c;
const Engine = js.Engine;
/// Composition supplies the one actual shared Memory/Settings/Type graph.
/// No second settings store, Type operator instance or private-validator alias
/// is manufactured by the compiler.
pub fn create(e: *Engine, shared: c.JSValue) !c.JSValue {
    const key = "pi-native:typebox-compile-production";
    if (e.native_module_values.get(key)) |cached| return js.get(e, cached, "exports");
    var s: Scope = .{ .engine = e };
    defer s.deinit();
    const graph = try s.object();
    inline for (.{ "Settings", "Memory", "Type" }) |name| {
        const instance = try s.get(shared, name);
        if (!c.JS_IsObject(instance)) return error.NativeTypeBoxSharedModuleUnavailable;
        try s.put(graph, name, instance);
    }
    try catalog.allocate(e, graph);
    try bootstrap.external(e, graph, shared);
    try catalog.prepare(e, graph);
    try bootstrap.lower(e, graph);
    try catalog.refresh(e, graph);
    const exports = try s.get(try s.get(graph, "modules"), "compile/index.mjs");
    try s.put(graph, "exports", exports);
    try e.registerValueModule(key, graph);
    return c.JS_DupValue(e.context, exports);
}
