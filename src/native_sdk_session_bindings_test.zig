//! Caller differential for the actual ordinary session binding/resource bodies.
//! Full DefaultResourceLoader path extension and the factory are separate gates.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const generation = engine.native_allocation_generation;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_bindings.zig").install(engine, prototype);
    const compat = try scope.own(try @import("extensions/native_ai_compat.zig").create(engine, .{ .builtin_apis = &.{}, .compat_models = c.pi_js_undefined(), .get_env_api_key = c.pi_js_undefined() }));
    try @import("extensions/native_sdk_session_reload.zig").install(engine, prototype, try scope.get(compat, "resetApiProviders"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "bindingsAPI", prototype);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-bindings-5ab.input.txt"), "bindings-original-5ab.mjs") catch |err| {
        std.debug.print("Native ordinary extension bindings failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "bindingsRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-bindings-5ab.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "bindings-original-5ab.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual bindings:\n{s}\nExpected Source:\n{s}\n", .{ actual, raw });
        return error.NativeOrdinaryBindingsMismatch;
    }
}
test "native ordinary extension bindings match actual 5ab caller semantics" {
    try run(std.testing.allocator);
}
test "native ordinary extension bindings complete representative allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-bindings5ab", run, .{});
}
