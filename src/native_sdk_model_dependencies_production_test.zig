//! Source53 comparator over real imported filesystem/backend and TypeBox graph.
//! The driver supplies actual assembled imports, an owned isolated directory,
//! and genuine captured bytes. No expected rows or collaborator stand-ins exist.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn exercise(engine: *em.Engine, imports: c.JSValue, typebox_graph: c.JSValue, fixture_directory: c.JSValue, genuine: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const generation = engine.native_allocation_generation;
    const stores = try scope.own(try @import("extensions/native_sdk_models_store_production.zig").create(engine, imports));
    const config = try scope.own(try @import("extensions/native_sdk_model_config_production.zig").create(engine, imports, typebox_graph));
    const dependencies = try scope.object();
    try @import("extensions/native_js_values.zig").spreadInto(engine, dependencies, stores);
    try @import("extensions/native_js_values.zig").spreadInto(engine, dependencies, config);
    const global = try scope.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try scope.put(global, "ActualSdkModelDependencies", dependencies);
    try scope.put(global, "ActualSdkModelFixtureDir", fixture_directory);
    const module = try scope.own(try engine.evalModule(@embedFile("extensions/fixtures/sdk-model-dependencies-4954.input.mjs"), "sdk-model-dependencies-4954.input.mjs"));
    _ = try scope.own(try engine.awaitValue(module));
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, genuine.ptr, genuine.len, "actual-sdk-model-dependencies-source53.json")));
    const actual = try scope.get(global, "ActualSdkModelDependencyRows");
    const expected_rows = try scope.get(expected, "rows");
    if (try @import("extensions/native_sdk.zig").length(engine, actual) != 53 or try @import("extensions/native_sdk.zig").length(engine, expected_rows) != 53) return error.ActualSdkModelDependenciesProbeUniverseMismatch;
    for (0..53) |index| {
        const actual_row = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, actual, @intCast(index))));
        const expected_row = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, expected_rows, @intCast(index))));
        const actual_json = try engine.stringify(actual_row);
        defer engine.gpa.free(actual_json);
        const expected_json = try engine.stringify(expected_row);
        defer engine.gpa.free(expected_json);
        if (!std.mem.eql(u8, actual_json, expected_json)) {
            std.debug.print("Actual SDK model dependency Source53 mismatch row={d}\nActual:{s}\nSource:{s}\n", .{ index, actual_json, expected_json });
            return error.ActualSdkModelDependenciesSourceMismatch;
        }
    }
}
