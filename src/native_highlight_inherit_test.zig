//! Original Node comparison. Guest VM self-agreement is insufficient here.
const std = @import("std");
const em = @import("extensions/engine.zig");
const sdk = @import("extensions/native_sdk.zig");
const inherit = @import("extensions/native_highlight_inherit.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn collect(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
    return c.pi_js_undefined();
}
fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const global = try scope.own(c.JS_GetGlobalObject(engine.context));
    try scope.put(global, "inheritAPI", try scope.own(try inherit.create(engine)));
    try scope.put(global, "collectInheritanceGarbage", try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, collect, "collectInheritanceGarbage", 0))));
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-inherit-1692.input.txt"), "highlight-inherit-original24.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    const raw = try engine.stringify(try scope.get(global, "sdkHighlightInheritRows"));
    defer gpa.free(raw);
    const bytes = @embedFile("extensions/fixtures/sdk-highlight-inherit-1692.json");
    const expected = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-inherit-original24.json")));
    const expected_raw = try engine.stringify(expected);
    defer gpa.free(expected_raw);
    if (!std.mem.eql(u8, raw, expected_raw)) {
        std.debug.print("Actual Original inherit24 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
        return error.InheritSourceMismatch;
    }
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native highlight inherit matches actual Original24 ordering proxy traps errors callbacks and GC" {
    try exercise(std.testing.allocator);
}
test "native highlight inherit releases every full original probe allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-inherit", exercise, .{});
}
