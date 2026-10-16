//! Compare twenty actual lazy grammar factories with the genuine Source109 corpus.
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
        inline for (.{
            @import("extensions/native_highlight_grammar_xml.zig"),
            @import("extensions/native_highlight_grammar_css.zig"),
            @import("extensions/native_highlight_grammar_markdown.zig"),
            @import("extensions/native_highlight_grammar_dockerfile.zig"),
            @import("extensions/native_highlight_grammar_ini.zig"),
            @import("extensions/native_highlight_grammar_makefile.zig"),
            @import("extensions/native_highlight_grammar_powershell.zig"),
            @import("extensions/native_highlight_grammar_protobuf.zig"),
            @import("extensions/native_highlight_grammar_sql.zig"),
            @import("extensions/native_highlight_grammar_yaml.zig"),
        }, .{ "xml", "css", "markdown", "dockerfile", "ini", "makefile", "powershell", "protobuf", "sql", "yaml" }) |grammar, name| {
            const register = try s.get(eager.core, "registerLanguage");
            const factory = try s.own(try grammar.create(engine));
            _ = try s.call(register, eager.core, &.{ try s.text(name), factory });
        }
        const factories = try s.object();
        inline for (.{
            .{ "1c", @import("extensions/native_highlight_grammar_1c.zig") },
            .{ "ada", @import("extensions/native_highlight_grammar_ada.zig") },
            .{ "arduino", @import("extensions/native_highlight_grammar_arduino.zig") },
            .{ "asciidoc", @import("extensions/native_highlight_grammar_asciidoc.zig") },
            .{ "autoit", @import("extensions/native_highlight_grammar_autoit.zig") },
            .{ "c-like", @import("extensions/native_highlight_grammar_c_like.zig") },
            .{ "coffeescript", @import("extensions/native_highlight_grammar_coffeescript.zig") },
            .{ "crystal", @import("extensions/native_highlight_grammar_crystal.zig") },
            .{ "d", @import("extensions/native_highlight_grammar_d.zig") },
            .{ "fortran", @import("extensions/native_highlight_grammar_fortran.zig") },
            .{ "gauss", @import("extensions/native_highlight_grammar_gauss.zig") },
            .{ "glsl", @import("extensions/native_highlight_grammar_glsl.zig") },
            .{ "gml", @import("extensions/native_highlight_grammar_gml.zig") },
            .{ "handlebars", @import("extensions/native_highlight_grammar_handlebars.zig") },
            .{ "htmlbars", @import("extensions/native_highlight_grammar_htmlbars.zig") },
            .{ "irpf90", @import("extensions/native_highlight_grammar_irpf90.zig") },
            .{ "isbl", @import("extensions/native_highlight_grammar_isbl.zig") },
            .{ "julia", @import("extensions/native_highlight_grammar_julia.zig") },
            .{ "latex", @import("extensions/native_highlight_grammar_latex.zig") },
            .{ "less", @import("extensions/native_highlight_grammar_less.zig") },
        }) |entry| try s.put(factories, entry[0], try s.own(try entry[1].create(engine)));
        try s.put(global, "highlightCoreAPI", eager.core);
        try s.put(global, "highlightLazyFactories", factories);
    }
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-lazy-batch9-10_7_3.input.txt"), "highlight-lazy-batch9-original109.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const actual_rows = try s.get(global, "sdkHighlightLazyBatch9Rows");
        const bytes = @embedFile("extensions/fixtures/sdk-highlight-lazy-batch9-10_7_3.json");
        const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-lazy-batch9-original109.json")));
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
                    std.debug.print("Actual lazy grammar Source109 mismatch: {s}\nNative: {s}\nOriginal: {s}\n", .{ source_row.object.get("name").?.string, native_bytes, source_bytes });
                    break;
                }
            }
            return error.HighlightLazyGrammarSourceMismatch;
        }
    }
    const released = engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightLazyFactories;delete globalThis.sdkHighlightLazyBatch9Rows;", "highlight-lazy-batch9-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native actual lazy batch9 grammar bodies match genuine Source109 graphs helpers aliases and scanner outputs" {
    try exercise(std.testing.allocator);
}
