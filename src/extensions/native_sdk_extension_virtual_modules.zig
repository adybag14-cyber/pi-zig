//! Actual virtual-modules.ts object and loader.ts getVirtualModules cache.
//! The application supplies a real lazy module import; lookup only happens when
//! that import evaluates this module after all nine namespaces are completed.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const f = @import("native_node_function.zig");
pub const Names = struct {
    typebox: []const u8, typebox_compile: []const u8, typebox_value: []const u8,
    agent_core: []const u8, tui: []const u8, ai_compat: []const u8,
    ai_oauth: []const u8, ai_providers: []const u8, coding_agent: []const u8,
};
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    try v.js.define(engine, target, name, c.JS_DupValue(engine.context, value));
}
fn required(engine: *v.em.Engine, name: []const u8) !c.JSValue {
    if (!engine.native_module_names.contains(name)) return error.RequiredCompletedExtensionNamespace;
    const value = engine.native_module_values.get(name) orelse return error.RequiredCompletedExtensionNamespace;
    if (!c.JS_IsObject(value)) return error.RequiredCompletedExtensionNamespace;
    return value; // Borrowed from the real Engine module owner.
}
/// Host module-evaluation seam, deliberately not invoked by loader assembly.
/// Caller registers/owns this actual namespace once through its real module
/// importer. Missing dependencies reject; nothing is published partially.
pub fn evaluate(engine: *v.em.Engine, names: Names) !c.JSValue {
    // Match static import order before constructing the exported object.
    const core = try required(engine, names.agent_core);
    const compat = try required(engine, names.ai_compat);
    const oauth = try required(engine, names.ai_oauth);
    const providers = try required(engine, names.ai_providers);
    const tui = try required(engine, names.tui);
    const typebox = try required(engine, names.typebox);
    const compile = try required(engine, names.typebox_compile);
    const value = try required(engine, names.typebox_value);
    const sdk = try required(engine, names.coding_agent);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const modules = try s.object();
    inline for (.{ .{ "typebox", typebox }, .{ "typebox/compile", compile }, .{ "typebox/value", value }, .{ "@sinclair/typebox", typebox }, .{ "@sinclair/typebox/compile", compile }, .{ "@sinclair/typebox/value", value }, .{ "@earendil-works/pi-agent-core", core }, .{ "@earendil-works/pi-tui", tui }, .{ "@earendil-works/pi-ai", compat }, .{ "@earendil-works/pi-ai/compat", compat }, .{ "@earendil-works/pi-ai/oauth", oauth }, .{ "@earendil-works/pi-ai/providers/all", providers }, .{ "@earendil-works/pi-coding-agent", sdk }, .{ "@mariozechner/pi-agent-core", core }, .{ "@mariozechner/pi-tui", tui }, .{ "@mariozechner/pi-ai", compat }, .{ "@mariozechner/pi-ai/compat", compat }, .{ "@mariozechner/pi-ai/oauth", oauth }, .{ "@mariozechner/pi-ai/providers/all", providers }, .{ "@mariozechner/pi-coding-agent", sdk } }) |entry| try put(engine, modules, entry[0], entry[1]);
    const namespace = try s.object();
    try put(engine, namespace, "VIRTUAL_MODULES", modules);
    return c.JS_DupValue(engine.context, namespace);
}
/// Original ordinary getVirtualModules, length0, with one cached raw .then
/// result including rejection. real_import must perform the real lazy module
/// evaluation; this helper never substitutes an importer or Promise facade.
pub fn createLazy(engine: *v.em.Engine, real_import: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, real_import)) return error.RequiredActualLazyVirtualModuleImport;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try put(engine, owner, "promise", c.pi_js_undefined());
    const select = try s.own(try f.createArrow(engine, "", 1, selectModules, &.{}));
    return f.create(engine, "getVirtualModules", 0, getVirtualModules, &.{ owner, real_import, select });
}
fn selectModules(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return v.js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), "VIRTUAL_MODULES");
}
fn getVirtualModules(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cached = try s.get(roots[0], "promise");
    if (!v.nullish(cached)) return c.JS_DupValue(engine.context, cached);
    const importing = try s.call(roots[1], c.pi_js_undefined(), &.{});
    const promise = try s.invoke(importing, "then", &.{roots[2]});
    try put(engine, roots[0], "promise", promise);
    return c.JS_DupValue(engine.context, promise);
}
