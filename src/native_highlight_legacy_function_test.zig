//! Isolated actual Original CJS legacy20 differential. No production binding.
const std = @import("std");
const em = @import("extensions/engine.zig");
const inherit = @import("extensions/native_highlight_inherit.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn setup(engine: *em.Engine) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "inheritAPI", try scope.own(try inherit.createLegacyPrototype(engine)));
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    setup(engine) catch |err| return engine.nativeAllocationError(err, generation);
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-legacy-b45.input.txt"), "highlight-legacy-original20.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        const rows = try scope.get(global, "sdkHighlightInheritRows");
        const raw = try engine.stringify(rows);
        defer gpa.free(raw);
        const expected_bytes = @embedFile("extensions/fixtures/sdk-highlight-legacy-b45.json");
        const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, expected_bytes, expected_bytes.len, "highlight-legacy-original20.json")));
        const expected_raw = try engine.stringify(expected);
        defer gpa.free(expected_raw);
        if (!std.mem.eql(u8, raw, expected_raw)) {
            std.debug.print("Actual Original legacy20 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
            return error.LegacyFunctionSourceMismatch;
        }
    }
    const released = engine.eval("globalThis.legacyWeak=new WeakRef(inheritAPI);delete globalThis.inheritAPI;delete globalThis.sdkHighlightInheritRows;", "highlight-legacy-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    const collected = engine.eval("legacyWeak.deref()===undefined", "highlight-legacy-gc.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    defer engine.freeValue(collected);
    if (c.JS_ToBool(engine.context, collected) != 1) return error.LegacyFunctionOwnerRetained;
}
test "native legacy CJS function matches actual Original20 callers arguments poison descriptors freeze and GC" {
    try exercise(std.testing.allocator);
}
test "native legacy CJS function releases every full original probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-legacy-function", exercise, .{});
}
fn cancel(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    em.Engine.fromContext(context.?).cancelled.store(true, .release);
    return c.pi_js_undefined();
}
test "native legacy CJS function restores inactive frames after actual native enumeration cancellation" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try setup(engine);
    {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const global = try scope.own(c.JS_GetGlobalObject(engine.context));
        try scope.put(global, "cancelLegacyProbe", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, cancel, "cancelLegacyProbe", 0))));
    }
    const result = engine.eval("inheritAPI({get a(){cancelLegacyProbe();return 1},b:2})", "highlight-legacy-cancel.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.cancelled.store(false, .release);
    try std.testing.expectError(error.JavaScriptException, result);
    const restored = try engine.eval("if(inheritAPI.arguments!==null||inheritAPI.caller!==null||inheritAPI({ok:1}).ok!==1)throw Error('legacy cancellation frame not restored');", "highlight-legacy-restored.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(restored);
}
