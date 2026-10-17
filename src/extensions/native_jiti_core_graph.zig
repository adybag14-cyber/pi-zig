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
fn coreDeclaration(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    const imports = try cells.coreImports(engine, roots[0]);
    return core.instantiate(engine, imports, try cells.isWindows(engine, roots[0]), args);
}
fn frontendDeclaration(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return frontend.evaluate(engine, try cells.frontendImports(engine, roots[0]), args);
}
