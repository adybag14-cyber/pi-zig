//! Compare six actual lazy factories with the genuine Source45 capture.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_highlight_scope.zig").Scope;
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
    }
    const prepared = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-lazy-batch2-10_7_3.input.txt"), "highlight-lazy-batch2-original45.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(prepared);
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const hooks = try s.get(global, "highlightLazyBatch2Hooks");
        _ = try s.invoke(hooks, "beforeLoad", &.{});
        const factories = try s.object();
        inline for (.{ .{ "xml", @import("extensions/native_highlight_grammar_xml.zig") }, .{ "css", @import("extensions/native_highlight_grammar_css.zig") }, .{ "markdown", @import("extensions/native_highlight_grammar_markdown.zig") }, .{ "powershell", @import("extensions/native_highlight_grammar_powershell.zig") }, .{ "sql", @import("extensions/native_highlight_grammar_sql.zig") }, .{ "yaml", @import("extensions/native_highlight_grammar_yaml.zig") } }) |entry| try s.put(factories, entry[0], try s.own(try entry[1].create(engine)));
        try s.put(global, "highlightLazyFactories", factories);
        _ = try s.invoke(hooks, "afterLoad", &.{});
        _ = s.invoke(hooks, "run", &.{}) catch |err| return engine.nativeAllocationError(err, generation);
    }
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const actual_rows = try s.get(global, "sdkHighlightLazyBatch2Rows");
        const bytes = @embedFile("extensions/fixtures/sdk-highlight-lazy-batch2-10_7_3.json");
        const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-lazy-batch2-original45.json")));
        const expected_rows = try s.get(original, "rows");
        const actual = try engine.stringify(actual_rows);
        defer gpa.free(actual);
        const expected = try engine.stringify(expected_rows);
        defer gpa.free(expected);
        if (!std.mem.eql(u8, actual, expected)) {
            const native = try std.json.parseFromSlice(std.json.Value, gpa, actual, .{});
            defer native.deinit();
            const source = try std.json.parseFromSlice(std.json.Value, gpa, expected, .{});
            defer source.deinit();
            for (native.value.array.items, source.value.array.items) |native_row, source_row| {
                const a = try std.json.Stringify.valueAlloc(gpa, native_row, .{});
                defer gpa.free(a);
                const e = try std.json.Stringify.valueAlloc(gpa, source_row, .{});
                defer gpa.free(e);
                if (!std.mem.eql(u8, a, e)) {
                    std.debug.print("Actual lazy grammar Source45 mismatch: {s}\nNative: {s}\nOriginal: {s}\n", .{ source_row.object.get("name").?.string, a, e });
                    break;
                }
            }
            return error.HighlightLazyBatch2SourceMismatch;
        }
    }
    const released = engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightLazyFactories;delete globalThis.highlightLazyBatch2Hooks;delete globalThis.sdkHighlightLazyBatch2Rows;", "highlight-lazy-batch2-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}
test "native actual lazy batch2 grammar bodies match genuine Source45 graphs helpers module initialization and scanner outputs" {
    try exercise(std.testing.allocator);
}
