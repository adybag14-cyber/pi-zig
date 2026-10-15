//! Actual ordinary public method plus real registry and loadout bodies.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-active-tools-5ab"});
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_registry.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_loadout.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_active_tools.zig").install(engine, prototype);
    const dependencies = try scope.object();
    try sdk.install(engine, dependencies);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "activeToolsAPI", prototype);
    try scope.put(global, "activeToolsDeps", dependencies);
    try scope.put(global, "activeFixtureRoot", try scope.text(path_buffer[0..path_length]));
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-active-tools-5ab.input.txt"), "active-tools-original-5ab.mjs") catch |err| {
        std.debug.print("Native ordinary active tool selection failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "activeToolsRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-active-tools-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "active-tools-original-5ab.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual active tools:\n{s}\nExpected Source:\n{s}\n", .{ actual, raw });
        return error.NativeOrdinaryActiveToolsMismatch;
    }
}
test "native ordinary active tool selection matches actual 5ab callers and registry loadout" {
    try run(std.testing.allocator);
}
test "native ordinary active tool selection complete representative allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-activetools5ab", run, .{});
}
