//! Actual reload body and shared compat reset on caller-owned receivers.
//! Empty caller builtin dependencies do not qualify builtin transports or the
//! complete production factory; the real full-class diagnostic stays separate.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn run(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const compat = try scope.own(try @import("extensions/native_ai_compat.zig").create(engine, .{ .builtin_apis = &.{}, .compat_models = c.pi_js_undefined(), .get_env_api_key = c.pi_js_undefined() }));
    const prototype = try scope.object();
    try @import("extensions/native_sdk_session_reload.zig").install(engine, prototype, try scope.get(compat, "resetApiProviders"));
    const api = try scope.object();
    try scope.put(api, "reload", try scope.get(prototype, "reload"));
    try scope.put(api, "registerApiProvider", try scope.get(compat, "registerApiProvider"));
    try scope.put(api, "getApiProvider", try scope.get(compat, "getApiProvider"));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "reloadAPI", api);
    const evaluated = engine.evalModule(@embedFile("extensions/fixtures/sdk-session-reload-b45.input.txt"), "reload-original24.mjs") catch |err| {
        std.debug.print("Native ordinary reload Source24 failed: {s}\n", .{engine.last_error orelse @errorName(err)});
        return engine.nativeAllocationError(err, generation);
    };
    engine.freeValue(evaluated);
    if (generation != engine.native_allocation_generation) return error.OutOfMemory;
    const actual = try engine.stringify(try scope.get(global, "reloadRows"));
    defer gpa.free(actual);
    const bytes = @embedFile("extensions/fixtures/sdk-session-reload-b45.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "reload-original24.json")));
    const raw = try engine.stringify(try scope.get(expected, "rows"));
    defer gpa.free(raw);
    if (!std.mem.eql(u8, actual, raw)) {
        std.debug.print("Actual reload24:\n{s}\nExpected original24:\n{s}\n", .{ actual, raw });
        return error.NativeOrdinaryReloadMismatch;
    }
}
test "native ordinary reload matches actual b45 Source24 and shared provider reset" {
    try run(std.testing.allocator);
}
test "native ordinary reload complete representative host allocation universe" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "sdk-reload24", run, .{});
}
test "native ordinary reload async method metadata and explicit shared reset dependency" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    try std.testing.expectError(error.RequiredSharedNativeApiProviderReset, @import("extensions/native_sdk_session_reload.zig").install(engine, prototype, c.pi_js_undefined()));
    const compat = try scope.own(try @import("extensions/native_ai_compat.zig").create(engine, .{ .builtin_apis = &.{}, .compat_models = c.pi_js_undefined(), .get_env_api_key = c.pi_js_undefined() }));
    try @import("extensions/native_sdk_session_reload.zig").install(engine, prototype, try scope.get(compat, "resetApiProviders"));
    const method = try scope.get(prototype, "reload");
    const length = try scope.get(method, "length");
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, length, c.JS_NewInt32(engine.context, 1)));
    const parent = try scope.own(try engine.checked(c.JS_GetPrototype(engine.context, method)));
    const async_parent = try scope.own(try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context)));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, parent, async_parent));
}
