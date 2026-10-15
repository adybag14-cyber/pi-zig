//! Production replay entrypoint: callers supply real assembled classes and I/O.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
pub fn replay(engine: *em.Engine, actual_classes: c.JSValue, actual_io: c.JSValue, owned_directory: []const u8, expected_source: c.JSValue) !void {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try js.define(engine, global, "modelsPersistenceClasses", c.JS_DupValue(engine.context, actual_classes));
    try js.define(engine, global, "modelsPersistenceIO", c.JS_DupValue(engine.context, actual_io));
    try js.define(engine, global, "modelsPersistenceDir", try @import("extensions/native_sdk.zig").text(engine, owned_directory));
    try js.define(engine, global, "modelsPersistenceSource", c.JS_DupValue(engine.context, expected_source));
    const pending = try engine.evalModule(@embedFile("extensions/fixtures/sdk-model-config-stores-4954.input.mjs") ++
        \\
        \\if(modelsPersistenceSource.sourceHead!=='4954d760504c11df9b2cbdc040346107b6a8153d'||modelsPersistenceSource.rows.length!==modelsPersistenceObservation.rows.length)throw Error('actual latest models persistence Source inventory');for(let index=0;index<modelsPersistenceSource.rows.length;index++){const actual=modelsPersistenceObservation.rows[index],expected=modelsPersistenceSource.rows[index];if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error(JSON.stringify({index,actual,expected}))}export const pass=true;
    , "actual-modelconfig-modelsstore-4954.mjs");
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending);
    engine.freeValue(settled);
}
test "production model persistence refuses absent real filesystem and schema dependencies" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const imports = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(imports);
    try std.testing.expectError(error.MissingActualModelConfigImport, @import("extensions/native_sdk_model_config_production.zig").create(engine, imports));
    try std.testing.expectError(error.MissingActualModelsStoreImport, @import("extensions/native_sdk_models_store_production.zig").create(engine, imports));
}
