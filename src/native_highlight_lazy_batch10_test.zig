//! Compare twenty actual lazy grammar factories with the genuine Source113 corpus.
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
        const register = try s.get(eager.core, "registerLanguage");
        const xml_factory = try s.own(try @import("extensions/native_highlight_grammar_xml.zig").create(engine));
        _ = try s.call(register, eager.core, &.{ try s.text("xml"), xml_factory });
        const factories = try s.object();
        inline for (.{
            .{ "livecodeserver", @import("extensions/native_highlight_grammar_livecodeserver.zig") },
            .{ "livescript", @import("extensions/native_highlight_grammar_livescript.zig") },
            .{ "lsl", @import("extensions/native_highlight_grammar_lsl.zig") },
            .{ "mathematica", @import("extensions/native_highlight_grammar_mathematica.zig") },
            .{ "maxima", @import("extensions/native_highlight_grammar_maxima.zig") },
            .{ "mel", @import("extensions/native_highlight_grammar_mel.zig") },
            .{ "nsis", @import("extensions/native_highlight_grammar_nsis.zig") },
            .{ "pgsql", @import("extensions/native_highlight_grammar_pgsql.zig") },
            .{ "reasonml", @import("extensions/native_highlight_grammar_reasonml.zig") },
            .{ "scss", @import("extensions/native_highlight_grammar_scss.zig") },
            .{ "sqf", @import("extensions/native_highlight_grammar_sqf.zig") },
            .{ "sql_more", @import("extensions/native_highlight_grammar_sql_more.zig") },
            .{ "stan", @import("extensions/native_highlight_grammar_stan.zig") },
            .{ "stata", @import("extensions/native_highlight_grammar_stata.zig") },
            .{ "stylus", @import("extensions/native_highlight_grammar_stylus.zig") },
            .{ "vbnet", @import("extensions/native_highlight_grammar_vbnet.zig") },
            .{ "verilog", @import("extensions/native_highlight_grammar_verilog.zig") },
            .{ "vim", @import("extensions/native_highlight_grammar_vim.zig") },
            .{ "x86asm", @import("extensions/native_highlight_grammar_x86asm.zig") },
            .{ "xquery", @import("extensions/native_highlight_grammar_xquery.zig") },
        }) |entry| try s.put(factories, entry[0], try s.own(try entry[1].create(engine)));
        try s.put(global, "highlightCoreAPI", eager.core);
        try s.put(global, "highlightLazyFactories", factories);
    }
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-lazy-batch10-10_7_3.input.txt"), "highlight-lazy-batch10-original113.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const actual_rows = try s.get(global, "sdkHighlightLazyBatch10Rows");
        const bytes = @embedFile("extensions/fixtures/sdk-highlight-lazy-batch10-10_7_3.json");
        const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-lazy-batch10-original113.json")));
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
                const native_bytes = try std.json.Stringify.valueAlloc(gpa, native_row, .{});
                defer gpa.free(native_bytes);
                const source_bytes = try std.json.Stringify.valueAlloc(gpa, source_row, .{});
                defer gpa.free(source_bytes);
                if (!std.mem.eql(u8, native_bytes, source_bytes)) {
                    std.debug.print("Actual lazy grammar Source113 mismatch: {s}\nNative: {s}\nOriginal: {s}\n", .{ source_row.object.get("name").?.string, native_bytes, source_bytes });
                    break;
                }
            }
            return error.HighlightLazyGrammarSourceMismatch;
        }
    }
    const released = engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightLazyFactories;delete globalThis.sdkHighlightLazyBatch10Rows;", "highlight-lazy-batch10-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native actual lazy batch10 grammar bodies match genuine Source113 graphs helpers aliases and scanner outputs" {
    try exercise(std.testing.allocator);
}
