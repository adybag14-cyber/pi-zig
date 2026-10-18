//! Borrowed receiver causal controls, not a genuine SDK-owner bootstrap proof.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_session_bindings_values.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const bindings = @import("extensions/native_sdk_session_bindings.zig");
const c = em.c;
comptime { _ = @import("native_sdk_session_bindings_retirement_test.zig"); }
comptime { _ = @import("native_sdk_session_bindings_guest_guard_test.zig"); }
fn expose(scope: *Scope) !c.JSValue {
    const prototype = try scope.object();
    try bindings.install(scope.engine, prototype);
    const generation = scope.engine.native_allocation_generation;
    const global = try scope.own(try scope.raw(c.JS_GetGlobalObject(scope.engine.context), generation));
    try scope.put(global, "bindingsAF", prototype);
    return prototype;
}
test "native session bindings use two genuine AF and ordinary resource methods" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    return owned.finishVoid(&scope, brands(&scope));
}
fn brands(scope: *Scope) !void {
    const api = try expose(scope);
    inline for (.{ "bindExtensions", "extendResourcesFromExtensions" }) |name| {
        const function = try scope.get(api, name);
        try std.testing.expect(c.JS_IsAsyncFunction(scope.engine.context, function));
    }
    inline for (.{ "buildExtensionResourcePaths", "getExtensionSourceLabel" }) |name| {
        const function = try scope.get(api, name);
        try std.testing.expect(!c.JS_IsAsyncFunction(scope.engine.context, function));
    }
}
test "native session bindings borrowed receivers preserve live order actual Awaits and raw rejections" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    engine.native_io = std.testing.io;
    var scope: Scope = .{ .engine = engine };
    return owned.finishVoid(&scope, callers(&scope));
}
fn callers(scope: *Scope) !void {
    _ = try expose(scope);
    const result = try scope.engine.evalModule(@embedFile("extensions/fixtures/sdk-session-bindings-af.input.txt") ++
        "\nglobalThis.sessionBindingsAFRows=await runSessionBindingsAF(bindingsAF);\n", "session-bindings-af-borrowed.mjs");
    _ = try scope.own(result);
}
fn drain(engine: *em.Engine, promise: c.JSValue) !void {
    var turns: usize = 0;
    while (c.JS_PromiseState(engine.context, promise) == c.JS_PROMISE_PENDING and turns < 64) : (turns += 1) {
        var context: ?*c.JSContext = null;
        if (c.JS_ExecutePendingJob(engine.runtime, &context) <= 0) return error.SessionBindingsAwaitDidNotComplete;
    }
    try std.testing.expect(c.JS_PromiseState(engine.context, promise) != c.JS_PROMISE_PENDING);
}
test "native session bindings both Await rejection routes retain flagged private DATA" {
    for ([_]bool{ false, true }) |discover| {
        const engine = try em.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        engine.native_io = std.testing.io;
        var scope: Scope = .{ .engine = engine };
        try owned.finishVoid(&scope, rejection(&scope, discover));
    }
}
fn rejection(scope: *Scope, discover: bool) !void {
    const engine = scope.engine;
    _ = try expose(scope);
    // This is historical rejection DATA, not a fresh failed producer at resume.
    _ = engine.throwNativeOutOfMemory();
    const reason = try scope.own(c.JS_GetException(engine.context));
    const tag = c.pi_js_native_allocation_error_generation(reason);
    c.JS_SetUncatchableError(engine.context, reason);
    const promise = try scope.own(try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason)));
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "bindingRejectedInput", promise);
    const created = try scope.own(try engine.evalModule(
        \\globalThis.bindingBorrowed={_cwd:'cwd',_applyExtensionBindings(){},_extensionRunner:{emit(){return bindingRejectedInput},hasHandlers(){return true},emitResourcesDiscover(){return bindingRejectedInput}}};export const ready=true;
    , "session-bindings-rejected-data.mjs"));
    _ = created;
    const session = try scope.get(global, "bindingBorrowed");
    const api = try scope.get(global, "bindingsAF");
    const function = try scope.get(api, if (discover) "extendResourcesFromExtensions" else "bindExtensions");
    const input = if (discover) try scope.text("startup") else try scope.object();
    const pending = try scope.call(function, session, &.{input});
    try drain(engine, pending);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, pending));
    const result = try scope.own(c.JS_PromiseResult(engine.context, pending));
    try std.testing.expect(scope.equal(result, reason));
    try std.testing.expect(c.JS_IsUncatchableError(result));
    try std.testing.expectEqual(tag, c.pi_js_native_allocation_error_generation(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
