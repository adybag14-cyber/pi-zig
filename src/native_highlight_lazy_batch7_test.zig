//! Compare twenty actual lazy grammar factories with the genuine Source106 corpus.
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
            @import("extensions/native_highlight_grammar_bnf.zig"),
            @import("extensions/native_highlight_grammar_fix.zig"),
            @import("extensions/native_highlight_grammar_shell.zig"),
            @import("extensions/native_highlight_grammar_ldif.zig"),
            @import("extensions/native_highlight_grammar_csp.zig"),
            @import("extensions/native_highlight_grammar_golo.zig"),
            @import("extensions/native_highlight_grammar_profile.zig"),
            @import("extensions/native_highlight_grammar_clean.zig"),
            @import("extensions/native_highlight_grammar_taggerscript.zig"),
            @import("extensions/native_highlight_grammar_subunit.zig"),
            @import("extensions/native_highlight_grammar_ebnf.zig"),
            @import("extensions/native_highlight_grammar_flix.zig"),
            @import("extensions/native_highlight_grammar_leaf.zig"),
            @import("extensions/native_highlight_grammar_mizar.zig"),
            @import("extensions/native_highlight_grammar_tap.zig"),
            @import("extensions/native_highlight_grammar_gherkin.zig"),
            @import("extensions/native_highlight_grammar_thrift.zig"),
            @import("extensions/native_highlight_grammar_dsconfig.zig"),
            @import("extensions/native_highlight_grammar_awk.zig"),
            @import("extensions/native_highlight_grammar_step21.zig"),
            @import("extensions/native_highlight_grammar_brainfuck.zig"),
            @import("extensions/native_highlight_grammar_diff.zig"),
            @import("extensions/native_highlight_grammar_roboconf.zig"),
            @import("extensions/native_highlight_grammar_capnproto.zig"),
            @import("extensions/native_highlight_grammar_smalltalk.zig"),
            @import("extensions/native_highlight_grammar_q.zig"),
            @import("extensions/native_highlight_grammar_rsl.zig"),
            @import("extensions/native_highlight_grammar_inform7.zig"),
            @import("extensions/native_highlight_grammar_prolog.zig"),
            @import("extensions/native_highlight_grammar_rib.zig"),
            @import("extensions/native_highlight_grammar_vala.zig"),
            @import("extensions/native_highlight_grammar_dos.zig"),
            @import("extensions/native_highlight_grammar_abnf.zig"),
            @import("extensions/native_highlight_grammar_pf.zig"),
            @import("extensions/native_highlight_grammar_ceylon.zig"),
            @import("extensions/native_highlight_grammar_fsharp.zig"),
            @import("extensions/native_highlight_grammar_openscad.zig"),
            @import("extensions/native_highlight_grammar_pony.zig"),
            @import("extensions/native_highlight_grammar_gcode.zig"),
            @import("extensions/native_highlight_grammar_cal.zig"),
            @import("extensions/native_highlight_grammar_erb.zig"),
            @import("extensions/native_highlight_grammar_python_repl.zig"),
            @import("extensions/native_highlight_grammar_node_repl.zig"),
            @import("extensions/native_highlight_grammar_mojolicious.zig"),
            @import("extensions/native_highlight_grammar_parser3.zig"),
            @import("extensions/native_highlight_grammar_php_template.zig"),
            @import("extensions/native_highlight_grammar_jboss_cli.zig"),
            @import("extensions/native_highlight_grammar_twig.zig"),
            @import("extensions/native_highlight_grammar_gradle.zig"),
            @import("extensions/native_highlight_grammar_scilab.zig"),
            @import("extensions/native_highlight_grammar_nim.zig"),
            @import("extensions/native_highlight_grammar_monkey.zig"),
            @import("extensions/native_highlight_grammar_dns.zig"),
            @import("extensions/native_highlight_grammar_properties.zig"),
            @import("extensions/native_highlight_grammar_http.zig"),
            @import("extensions/native_highlight_grammar_accesslog.zig"),
            @import("extensions/native_highlight_grammar_gams.zig"),
            @import("extensions/native_highlight_grammar_cmake.zig"),
            @import("extensions/native_highlight_grammar_dts.zig"),
            @import("extensions/native_highlight_grammar_r.zig"),
            @import("extensions/native_highlight_grammar_dust.zig"),
            @import("extensions/native_highlight_grammar_autohotkey.zig"),
            @import("extensions/native_highlight_grammar_sml.zig"),
            @import("extensions/native_highlight_grammar_smali.zig"),
            @import("extensions/native_highlight_grammar_apache.zig"),
            @import("extensions/native_highlight_grammar_basic.zig"),
            @import("extensions/native_highlight_grammar_lisp.zig"),
            @import("extensions/native_highlight_grammar_elm.zig"),
            @import("extensions/native_highlight_grammar_ocaml.zig"),
            @import("extensions/native_highlight_grammar_tp.zig"),
            @import("extensions/native_highlight_grammar_crmsh.zig"),
            @import("extensions/native_highlight_grammar_xl.zig"),
            @import("extensions/native_highlight_grammar_haml.zig"),
            @import("extensions/native_highlight_grammar_actionscript.zig"),
            @import("extensions/native_highlight_grammar_django.zig"),
            @import("extensions/native_highlight_grammar_vhdl.zig"),
            @import("extensions/native_highlight_grammar_nginx.zig"),
            @import("extensions/native_highlight_grammar_axapta.zig"),
            @import("extensions/native_highlight_grammar_avrasm.zig"),
            @import("extensions/native_highlight_grammar_tcl.zig"),
        }, .{ "xml", "css", "markdown", "dockerfile", "ini", "makefile", "powershell", "protobuf", "sql", "yaml", "bnf", "fix", "shell", "ldif", "csp", "golo", "profile", "clean", "taggerscript", "subunit", "ebnf", "flix", "leaf", "mizar", "tap", "gherkin", "thrift", "dsconfig", "awk", "step21", "brainfuck", "diff", "roboconf", "capnproto", "smalltalk", "q", "rsl", "inform7", "prolog", "rib", "vala", "dos", "abnf", "pf", "ceylon", "fsharp", "openscad", "pony", "gcode", "cal", "erb", "python-repl", "node-repl", "mojolicious", "parser3", "php-template", "jboss-cli", "twig", "gradle", "scilab", "nim", "monkey", "dns", "properties", "http", "accesslog", "gams", "cmake", "dts", "r", "dust", "autohotkey", "sml", "smali", "apache", "basic", "lisp", "elm", "ocaml", "tp", "crmsh", "xl", "haml", "actionscript", "django", "vhdl", "nginx", "axapta", "avrasm", "tcl" }) |grammar, name| {
            const register = try s.get(eager.core, "registerLanguage");
            const factory = try s.own(try grammar.create(engine));
            _ = try s.call(register, eager.core, &.{ try s.text(name), factory });
        }
        const factories = try s.object();
        inline for (.{
            .{ "plaintext", @import("extensions/native_highlight_grammar_plaintext.zig") },
            .{ "clojure-repl", @import("extensions/native_highlight_grammar_clojure_repl.zig") },
            .{ "vbscript-html", @import("extensions/native_highlight_grammar_vbscript_html.zig") },
            .{ "julia-repl", @import("extensions/native_highlight_grammar_julia_repl.zig") },
            .{ "erlang-repl", @import("extensions/native_highlight_grammar_erlang_repl.zig") },
            .{ "oxygene", @import("extensions/native_highlight_grammar_oxygene.zig") },
            .{ "angelscript", @import("extensions/native_highlight_grammar_angelscript.zig") },
            .{ "vbscript", @import("extensions/native_highlight_grammar_vbscript.zig") },
            .{ "delphi", @import("extensions/native_highlight_grammar_delphi.zig") },
            .{ "mercury", @import("extensions/native_highlight_grammar_mercury.zig") },
            .{ "haskell", @import("extensions/native_highlight_grammar_haskell.zig") },
            .{ "zephir", @import("extensions/native_highlight_grammar_zephir.zig") },
            .{ "matlab", @import("extensions/native_highlight_grammar_matlab.zig") },
            .{ "moonscript", @import("extensions/native_highlight_grammar_moonscript.zig") },
            .{ "processing", @import("extensions/native_highlight_grammar_processing.zig") },
            .{ "haxe", @import("extensions/native_highlight_grammar_haxe.zig") },
            .{ "hsp", @import("extensions/native_highlight_grammar_hsp.zig") },
            .{ "objectivec", @import("extensions/native_highlight_grammar_objectivec.zig") },
            .{ "hy", @import("extensions/native_highlight_grammar_hy.zig") },
            .{ "erlang", @import("extensions/native_highlight_grammar_erlang.zig") },
        }) |entry| try s.put(factories, entry[0], try s.own(try entry[1].create(engine)));
        try s.put(global, "highlightCoreAPI", eager.core);
        try s.put(global, "highlightLazyFactories", factories);
    }
    const result = engine.evalModule(@embedFile("extensions/fixtures/sdk-highlight-lazy-batch7-10_7_3.input.txt"), "highlight-lazy-batch7-original106.mjs") catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(result);
    if (engine.native_allocation_generation != generation) return error.OutOfMemory;
    {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const actual_rows = try s.get(global, "sdkHighlightLazyBatch7Rows");
        const bytes = @embedFile("extensions/fixtures/sdk-highlight-lazy-batch7-10_7_3.json");
        const original = try s.own(try engine.checked(c.JS_ParseJSON(engine.context, bytes, bytes.len, "highlight-lazy-batch7-original106.json")));
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
                    std.debug.print("Actual lazy grammar Source106 mismatch: {s}\nNative: {s}\nOriginal: {s}\n", .{ source_row.object.get("name").?.string, native_bytes, source_bytes });
                    break;
                }
            }
            return error.HighlightLazyGrammarSourceMismatch;
        }
    }
    const released = engine.eval("delete globalThis.highlightCoreAPI;delete globalThis.highlightLazyFactories;delete globalThis.sdkHighlightLazyBatch7Rows;", "highlight-lazy-batch7-release.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return engine.nativeAllocationError(err, generation);
    engine.freeValue(released);
    engine.finishJob();
    c.JS_RunGC(engine.runtime);
}

test "native actual lazy batch7 grammar bodies match genuine Source106 graphs helpers aliases and scanner outputs" {
    try exercise(std.testing.allocator);
}
