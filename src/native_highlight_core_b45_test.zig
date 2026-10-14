//! Full actual Original74 eager21 factory/scanner/class/frontend comparator.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
pub fn exercise(gpa: std.mem.Allocator) !void {
    const engine = try em.Engine.init(gpa, .{ .host_await_timeout_ms = 10000 });
    defer engine.deinit();
    const generation = engine.native_allocation_generation;
    const eager = @import("extensions/native_syntax_highlight.zig").createEager(engine) catch |err| return engine.nativeAllocationError(err, generation);
    defer eager.deinit(engine);
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        try s.put(global, "highlightCoreAPI", eager.core);
        try s.put(global, "highlightSyntaxAPI", eager.syntax);
        try s.put(global, "highlightGrammarFactories", eager.factories);
    }
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-core-b45.input.txt"), "highlight-core-original74.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const raw = try engine.stringify(try s.get(global, "sdkHighlightCoreRows"));
        defer gpa.free(raw);
        const bytes = @embedFile("extensions/fixtures/sdk-highlight-core-b45.json");
        const expected = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-core-original74.json")));
        const expected_raw = try engine.stringify(expected);
        defer gpa.free(expected_raw);
        if (!std.mem.eql(u8, raw, expected_raw)) {
            std.debug.print("Actual Original core74 mismatch:\n{s}\nExpected:\n{s}\n", .{ raw, expected_raw });
            return error.HighlightCoreSourceMismatch;
        }
    }
    const released = engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightSyntaxAPI;delete globalThis.highlightGrammarFactories;delete globalThis.sdkHighlightCoreRows;", "highlight-core-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native full eager21 highlight core matches genuine Original74 factories scanner output token trees classes and frontend" {
    try exercise(std.testing.allocator);
}
test "native full eager21 highlight core releases every actual full probe host allocation failure" {
    try @import("test_support/exhaustive_allocation_shards.zig").check(.worker, "highlight-core-b45", exercise, .{});
}
