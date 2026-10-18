//! Actual API + lazy namespace modules + aliases + cached extension loader.
//! Source-only: genuine queued dynamic import and native createJiti are required.
//! Construction is not production selection and supplies no fallback facade.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const owned = @import("native_sdk_owned_completion.zig");
const guards = @import("native_agent_af_values.zig");
fn root(s: *Scope, value: c.JSValue) !c.JSValue { return owned.ownRoot(s, value); }
fn get(s: *Scope, target: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return root(s, try guards.guard(s.engine, generation, v.js.get(s.engine, target, name)));
}
fn call(s: *Scope, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const generation = s.engine.native_allocation_generation;
    return root(s, try guards.guard(s.engine, generation, v.js.call(s.engine, function, receiver, args)));
}
fn define(s: *Scope, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    const generation = s.engine.native_allocation_generation;
    const status = c.JS_DefinePropertyValueStr(s.engine.context, target, name, c.JS_DupValue(s.engine.context, value), c.JS_PROP_C_W_E);
    const outcome: anyerror!c.JSValue = if (status < 0) v.js.capture(s.engine) else s.engine.checked(c.pi_js_undefined());
    _ = try guards.guard(s.engine, generation, outcome);
}
pub const Inputs = struct {
    api: @import("native_sdk_extension_api.zig").Inputs,
    paths: c.JSValue,
    filesystem: c.JSValue,
    url: c.JSValue,
    node_module: c.JSValue,
    /// Exact metadata object of the actual physical loader module. Only this
    /// private module receives the scoped fallback resolver, never global meta.
    import_meta: c.JSValue,
    timing: c.JSValue,
    lazy_modules: @import("native_sdk_extension_lazy_imports.zig").Inputs,
    is_typescript_source_runtime: bool,
};
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    try engine.checkNativeEntry();
    var invocation: v.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine };
    const value = owned.finishValue(&s, createBody(&s, inputs)) catch |err|
        return engine.checked(engine.leaveNativeInvocation(&invocation, @import("native_sdk.zig").fail(engine, err)));
    return engine.checked(engine.leaveNativeInvocation(&invocation, value));
}
fn createBody(s: *Scope, inputs: Inputs) !c.JSValue {
    const engine = s.engine;
    if (!c.JS_IsFunction(engine.context, inputs.lazy_modules.dynamic_import)) return error.RequiredGenuineQueuedDynamicImport;
    const module_url = try get(s, inputs.import_meta, "url");
    const filename_value = try call(s, try get(s, inputs.url, "fileURLToPath"), c.pi_js_undefined(), &.{module_url});
    const filename = try engine.toString(filename_value); defer engine.gpa.free(filename);
    if (!@import("std").mem.eql(u8, filename, inputs.lazy_modules.loader_filename)) return error.ActualLoaderMetadataFilenameMismatch;
    const existing_resolve = try get(s, inputs.import_meta, "resolve");
    if (c.JS_IsUndefined(existing_resolve)) {
        const resolver = try root(s, try @import("native_sdk_extension_alias_resolver.zig").create(engine, filename));
        try define(s, inputs.import_meta, "resolve", resolver);
    } else if (!c.JS_IsFunction(engine.context, existing_resolve)) return error.RequiredActualLoaderImportMetaResolve;
    const aliases = try root(s, try @import("native_sdk_extension_aliases.zig").create(engine, .{ .paths = inputs.paths, .filesystem = inputs.filesystem, .url = inputs.url, .node_module = inputs.node_module, .import_meta = inputs.import_meta }));
    const lazy = try root(s, try @import("native_sdk_extension_lazy_imports.zig").create(engine, inputs.lazy_modules));
    const api = try root(s, try @import("native_sdk_extension_api.zig").create(engine, inputs.api));
    return @import("native_sdk_extension_loader_production.zig").create(engine, .{
        .initializer = .{ .create_extension_api = api, .paths = inputs.paths, .timing = inputs.timing },
        .get_create_jiti = try get(s, lazy, "getCreateJiti"),
        .import_virtual_module = try get(s, lazy, "importVirtualModule"),
        .get_aliases = aliases,
        .loader_module_url = module_url,
        .uses_embedded_modules = inputs.lazy_modules.uses_embedded_modules,
        .is_typescript_source_runtime = inputs.is_typescript_source_runtime,
    });
}
