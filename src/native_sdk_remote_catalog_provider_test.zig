//! The positive differential gate requires the actual assembled wrapper namespace
//! and actual runtime UA, supplied by its production dependency owners.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const wrappers = @import("extensions/native_sdk_remote_catalog_provider.zig");
const c = em.c;
pub fn compareOriginal(engine: *em.Engine, actual_namespace: c.JSValue, actual_runtime_user_agent: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "catalogWrappers", c.JS_DupValue(engine.context, actual_namespace));
    try js.define(engine, global, "catalogRuntimeUA", c.JS_DupValue(engine.context, actual_runtime_user_agent));
    const expected = @embedFile("extensions/fixtures/sdk-remote-catalog-4954.json");
    try js.define(engine, global, "catalogWrapperSource", try engine.checked(c.JS_ParseJSON(engine.context, expected.ptr, expected.len, "sdk-remote-catalog-4954.json")));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-remote-catalog-4954.input.txt") ++
        "\nif(catalogWrapperSource.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||catalogWrapperRows.length!==catalogWrapperSource.count)throw Error('all original remote catalog observations required');for(let i=0;i<catalogWrapperRows.length;i++)if(JSON.stringify(catalogWrapperRows[i])!==JSON.stringify(catalogWrapperSource.rows[i]))throw Error(JSON.stringify({case:i,actual:catalogWrapperRows[i],expected:catalogWrapperSource.rows[i]}));", "native-remote-catalog-original4954.mjs") catch |err| {
        std.debug.print("Catalog wrappers: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
    c.JS_RunGC(engine.runtime);
}
test "native catalog wrapper namespace requires genuine dependency bindings" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const absent = c.pi_js_undefined();
    try std.testing.expectError(error.ActualRemoteCatalogDependenciesRequired, wrappers.create(engine, .{ .get_model_type = absent, .is_model_type = absent, .fetch_with_retry = absent, .get_pi_user_agent = absent, .version = absent }));
}
