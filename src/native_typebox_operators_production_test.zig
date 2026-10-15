//! Exact genuine TypeBox operator probe comparison. Missing goldens fail.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
pub fn exercise(gpa: std.mem.Allocator, genuine: []const u8) !void {
    const engine = try v.em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var scope: v.Scope = .{ .engine = engine };
    defer scope.deinit();
    const graph = try scope.own(try @import("extensions/native_typebox_memory.zig").create(engine));
    const types = try scope.object();
    try scope.put(graph, "Type", types);
    @import("extensions/native_typebox_partial.zig").install(engine, types, graph) catch |err| return engine.nativeAllocationError(err, generation);
    @import("extensions/native_typebox_operators_production.zig").install(engine, types, graph) catch |err| return engine.nativeAllocationError(err, generation);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "TypeBoxOperatorGraph", graph);
    try scope.put(global, "gc", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "gc", 0))));
    const evaluation = engine.evalModule(@embedFile("extensions/fixtures/typebox-operators-production.input.txt"), "typebox-operators-production-probes.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(evaluation);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, genuine.ptr, genuine.len, "genuine-typebox-operators.json")));
    if (!try v.eq(&scope, try scope.get(expected, "version"), "1.3.27")) return error.TypeBoxAuthorityMismatch;
    const actual_rows = try scope.get(global, "TypeBoxOperatorRows");
    const expected_rows = try scope.get(expected, "rows");
    const actual_count = try v.length(&scope, actual_rows);
    const expected_count = try v.length(&scope, expected_rows);
    if (actual_count != expected_count or actual_count < 300) return error.TypeBoxOperatorProbeUniverseMismatch;
    for (0..actual_count) |index| {
        const actual = try engine.stringify(try v.at(&scope, actual_rows, @intCast(index)));
        defer gpa.free(actual);
        const oracle = try engine.stringify(try v.at(&scope, expected_rows, @intCast(index)));
        defer gpa.free(oracle);
        if (!std.mem.eql(u8, actual, oracle)) {
            std.debug.print("TypeBox actual Source operator probe {d} mismatch\nActual:{s}\nSource:{s}\n", .{ index, actual, oracle });
            return error.TypeBoxOperatorSourceMismatch;
        }
    }
    std.debug.print("TYPEBOX_OPERATOR_SOURCE_PARITY probes={d} pinned_version=1.3.27 complete_generic_closure=true full_HOST_GPA=false C_malloc_exhaustive=false\n", .{actual_count});
}
test "actual TypeBox generic operators match full genuine Source probe rows and metrics" {
    var environment = try std.process.Environ.createMap(std.testing.environ, std.testing.allocator);
    defer environment.deinit();
    const path = environment.get("PI_TYPEBOX_OPERATORS_GENUINE_JSON") orelse return error.MissingGenuineTypeBoxOperatorGolden;
    const genuine = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .limited(16 * 1024 * 1024));
    defer std.testing.allocator.free(genuine);
    try exercise(std.testing.allocator, genuine);
}
