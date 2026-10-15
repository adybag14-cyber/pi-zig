//! Genuine Source loader caller fixture over real native filesystem resources.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = try temporary.dir.realPath(std.testing.io, &path_buffer);
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const generation = engine.native_allocation_generation;
    var environment: std.process.Environ.Map = .init(gpa);
    defer environment.deinit();
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"sdk-resource-paths-5ab"});
    try @import("extensions/node_fs.zig").install(engine, std.testing.io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const namespace = try scope.object();
    try sdk.install(engine, namespace);
    try @import("extensions/native_theme.zig").install(engine, namespace);
    try engine.registerValueModule("pi-coding-agent", namespace);
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_bindings.zig").install(engine, prototype);
    try @import("extensions/native_sdk_session_registry.zig").install(engine, prototype);
    try scope.put(namespace, "SessionPrototype", prototype);
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "resourcePathsAPI", namespace);
    const theme_json = @embedFile("extensions/fixtures/sdk-resource-paths-dark-5ab.json");
    try scope.put(global, "resourceFixtureTheme", try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, theme_json.ptr, theme_json.len, "resource-fixture-theme.json"))));
    try scope.put(global, "resourceFixtureRoot", try scope.text(path_buffer[0..length]));
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-resource-paths-5ab.input.txt"), "resource-paths-original-5ab.mjs") catch |err| {
        std.debug.print("Native real resource path extension failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "resourcePathsRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-resource-paths-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "resource-paths-original-5ab.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual resource paths:\n{s}\nExpected Source:\n{s}\n", .{ actual, raw });
        return error.NativeResourcePathExtensionMismatch;
    }
}
test "native real resource paths match actual 5ab caller fixture" {
    try run(std.testing.allocator);
}
test "native real resource paths complete representative allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-resourcepaths5ab", run, .{});
}
