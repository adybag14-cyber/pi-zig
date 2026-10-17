//! Canonical REAL source declarations/cyclic cells. No fake callbacks/default
//! namespace is supplied; absent actual dependencies prevent completion.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
pub const cells = @import("native_jiti_module_cells.zig");
const core = @import("native_jiti_core_factory.zig");
const frontend = @import("native_jiti_eval_frontend.zig");
pub fn declare(engine: *v.em.Engine) !cells.Cells {
    return cells.declare(engine, .{ .core = coreDeclaration, .frontend = frontendDeclaration });
}
pub fn create(engine: *v.em.Engine, actual_imports: cells.Bindings) !cells.Cells {
    var graph = try declare(engine); errdefer graph.deinit(engine);
    try cells.link(engine, &graph, actual_imports);
    try cells.initialize(engine, &graph);
    return graph;
}
/// Canonical production composition entry. The external dependency structs
/// have no supplied require/core/eval counterpart fields. Missing native-import
/// policy/transform/resolver/etc remain actual required bindings, not aliases.
pub fn createCanonical(engine: *v.em.Engine, actual_imports: cells.CanonicalBindings) !cells.Cells {
    // Declaration/construction failures must not format Source error getters
    // before the actual cyclic imports have been completely linked.
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    var graph = try declare(engine); errdefer graph.deinit(engine);
    try cells.linkCanonical(engine, &graph, actual_imports);
    try cells.initialize(engine, &graph);
    return graph;
}
fn coreDeclaration(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const imports = try cells.coreImports(engine, roots[0]);
    return core.instantiate(engine, imports, try cells.isWindows(engine, roots[0]), args);
}
fn frontendDeclaration(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return frontend.evaluate(engine, try cells.frontendImports(engine, roots[0]), args);
}
