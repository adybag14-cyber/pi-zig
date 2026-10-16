//! Actual API + lazy namespace modules + aliases + cached extension loader.
//! Source-only: genuine queued dynamic import and native createJiti are required.
//! Construction is not production selection and supplies no fallback facade.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
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
    if (!c.JS_IsFunction(engine.context, inputs.lazy_modules.dynamic_import)) return error.RequiredGenuineQueuedDynamicImport;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const module_url = try s.get(inputs.import_meta, "url");
    const filename_value = try s.call(try s.get(inputs.url, "fileURLToPath"), c.pi_js_undefined(), &.{module_url});
    const filename = try engine.toString(filename_value); defer engine.gpa.free(filename);
    if (!@import("std").mem.eql(u8, filename, inputs.lazy_modules.loader_filename)) return error.ActualLoaderMetadataFilenameMismatch;
    const existing_resolve = try s.get(inputs.import_meta, "resolve");
    if (c.JS_IsUndefined(existing_resolve)) {
        const resolver = try s.own(try @import("native_sdk_extension_alias_resolver.zig").create(engine, filename));
        try v.js.define(engine, inputs.import_meta, "resolve", c.JS_DupValue(engine.context, resolver));
    } else if (!c.JS_IsFunction(engine.context, existing_resolve)) return error.RequiredActualLoaderImportMetaResolve;
    const aliases = try s.own(try @import("native_sdk_extension_aliases.zig").create(engine, .{ .paths = inputs.paths, .filesystem = inputs.filesystem, .url = inputs.url, .node_module = inputs.node_module, .import_meta = inputs.import_meta }));
    const lazy = try s.own(try @import("native_sdk_extension_lazy_imports.zig").create(engine, inputs.lazy_modules));
    const api = try s.own(try @import("native_sdk_extension_api.zig").create(engine, inputs.api));
    return @import("native_sdk_extension_loader_production.zig").create(engine, .{
        .initializer = .{ .create_extension_api = api, .paths = inputs.paths, .timing = inputs.timing },
        .get_create_jiti = try s.get(lazy, "getCreateJiti"),
        .import_virtual_module = try s.get(lazy, "importVirtualModule"),
        .get_aliases = aliases,
        .loader_module_url = module_url,
        .uses_embedded_modules = inputs.lazy_modules.uses_embedded_modules,
        .is_typescript_source_runtime = inputs.is_typescript_source_runtime,
    });
}
