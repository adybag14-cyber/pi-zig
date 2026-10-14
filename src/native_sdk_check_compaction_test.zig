const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
test {
    _ = @import("native_sdk_compaction_threshold_test.zig");
}
fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    const prototype = try scope.object();
    try @import("extensions/native_sdk_check_compaction.zig").install(engine, prototype, dependencies);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "checkCompactionB06", try scope.get(prototype, "_checkCompaction"));
}
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try setup(engine);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-check-compaction-b06.input.txt"), "check-compaction-original32.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "checkCompactionB06Rows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-check-compaction-b06.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "check-original32.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual check32:\n{s}\nOriginal check32:\n{s}\n", .{ actual, raw });
        return error.NativeCheckCompactionMismatch;
    }
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native check compaction selected inventory" {
    const tests = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, tests.len);
    defer std.testing.allocator.free(names);
    for (tests, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("CHECK_COMPACTION_TEST_INVENTORY={s}\n", .{encoded});
}
test "native check compaction actual b06 overflow length edits stale usage and one retry" {
    try run(std.testing.allocator);
}
test "native check compaction complete host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "check-compaction32", run, .{});
}
test "native check compaction actual async method descriptor" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    const evaluated = try engine.evalModule(
        \\const f=checkCompactionB06;if(f.name!=='_checkCompaction'||f.length!==1||Object.hasOwn(f,'prototype')||Object.getPrototypeOf(f)!==Object.getPrototypeOf(async()=>{}))throw Error('async checkCompaction descriptor');
    , "check-compaction-descriptor.mjs");
    engine.freeValue(evaluated);
}
