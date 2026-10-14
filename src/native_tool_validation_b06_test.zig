//! Genuine b06 argumentsError and early validation boundary comparisons.
const std = @import("std");
const em = @import("extensions/engine.zig");
const values = @import("extensions/native_values.zig");
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{});
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try @import("extensions/native_tool_arguments.zig").testFunctions(engine);
    const initialized = try engine.eval("globalThis.validationB06=validateToolArguments;globalThis.structuredClone=nativeDefaultClone;", "validation-b06-setup.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(initialized);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/tool-validation-b06.input.txt"), "validation-b06-original28.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const actual_rows = try values.get(engine, global, "validationB06Rows");
    defer engine.freeValue(actual_rows);
    const actual = try engine.stringify(actual_rows);
    defer gpa.free(actual);
    const source = @embedFile("extensions/fixtures/tool-validation-b06.json");
    const expected = try engine.checked(c.JS_ParseJSON(engine.context, source, source.len, "validation-b06-original28.json"));
    defer engine.freeValue(expected);
    const expected_rows = try values.get(engine, expected, "rows");
    defer engine.freeValue(expected_rows);
    const raw = try engine.stringify(expected_rows);
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual validation28:\n{s}\nOriginal validation28:\n{s}\n", .{ actual, raw });
        return error.NativeToolValidationB06Mismatch;
    }
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "native b06 tool validation matches actual upstream argumentsError guard and early evaluation order" {
    try run(std.testing.allocator);
}
test "native b06 tool validation complete host allocation failure universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "tool-validation-b06-28", run, .{});
}
