const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
test {
    _ = @import("native_sdk_session_events_test.zig");
    _ = @import("native_sdk_session_constructor_phase_test.zig");
}
fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const dependencies = try scope.object();
    try @import("extensions/native_sdk_session_estimate.zig").install(engine, dependencies);
    try scope.put(dependencies, "convertToLlm", try scope.own(try @import("extensions/native_sdk_messages.zig").create(engine)));
    try scope.put(dependencies, "normalizeToolResultImages", try scope.own(try @import("extensions/native_sdk_tool_result_images.zig").create(engine)));
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_hooks.zig").installWithDependencies(engine, prototype, dependencies);
    const api = try scope.object();
    try scope.put(api, "exceeds", try scope.get(prototype, "_exceedsCompactionThreshold"));
    try scope.put(api, "before", try scope.get(prototype, "_compactBeforeNextAssistantResponse"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "thresholdB06", api);
}
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    try setup(engine);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-compaction-threshold-b06.input.txt"), "compaction-threshold-original20.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    const actual = try engine.stringify(try scope.get(global, "thresholdB06Rows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-compaction-threshold-b06.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "threshold-original20.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual threshold20:\n{s}\nOriginal threshold20:\n{s}\n", .{ actual, raw });
        return error.NativeCompactionThresholdMismatch;
    }
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native compaction threshold selected inventory" {
    const tests = @import("builtin").test_functions;
    const names = try std.testing.allocator.alloc([]const u8, tests.len);
    defer std.testing.allocator.free(names);
    for (tests, names) |function, *name| name.* = function.name;
    const encoded = try std.json.Stringify.valueAlloc(std.testing.allocator, names, .{});
    defer std.testing.allocator.free(encoded);
    std.debug.print("COMPACTION_THRESHOLD_TEST_INVENTORY={s}\n", .{encoded});
}
test "native compaction threshold matches genuine b06 method and live override dispatch" {
    try run(std.testing.allocator);
}
test "native compaction threshold complete host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "compaction-threshold20", run, .{});
}
test "native compaction threshold ordinary descriptor" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    const evaluated = try engine.evalModule(
        \\const f=thresholdB06.exceeds;if(f.name!=='_exceedsCompactionThreshold'||f.length!==2||Object.hasOwn(f,'prototype')||Object.getPrototypeOf(f)!==Function.prototype)throw Error('ordinary threshold method descriptor');
    , "threshold-descriptor.mjs");
    engine.freeValue(evaluated);
}
