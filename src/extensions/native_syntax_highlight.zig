//! Actual b45 syntax highlight/supportsLanguage frontend and complete eager21.
//! Private only. The separate lazy191-language loader is not claimed or stubbed.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
fn highlightCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const code = if (args.len > 0) args[0] else c.pi_js_undefined();
    const supplied = if (args.len > 1) args[1] else c.pi_js_undefined();
    const options = if (c.JS_IsUndefined(supplied)) try s.object() else supplied;
    const core = roots[0];
    const result = if (s.truthy(try s.get(options, "language"))) blk: {
        const fn_value = try s.get(core, "highlight");
        const forwarded = try s.object();
        try s.put(forwarded, "language", try s.get(options, "language"));
        try s.put(forwarded, "ignoreIllegals", try s.get(options, "ignoreIllegals"));
        break :blk try s.call(fn_value, core, &.{ code, forwarded });
    } else try s.invoke(core, "highlightAuto", &.{ code, try s.get(options, "languageSubset") });
    const html = try s.get(result, "value");
    return @import("native_syntax_highlight_html.zig").renderHtml(engine, html, try s.get(options, "theme"));
}
fn supportsCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const result = try s.invoke(roots[0], "getLanguage", &.{if (args.len > 0) args[0] else c.pi_js_undefined()});
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsUndefined(result)));
}
fn renderCall(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
    return @import("native_syntax_highlight_html.zig").renderHtml(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), if (args.len > 1) args[1] else c.pi_js_undefined());
}
pub const Eager = struct {
    core: c.JSValue,
    syntax: c.JSValue,
    factories: c.JSValue,
    pub fn deinit(self: Eager, engine: *em.Engine) void {
        engine.freeValue(self.core);
        engine.freeValue(self.syntax);
        engine.freeValue(self.factories);
    }
};
pub fn createEager(engine: *em.Engine) !Eager {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const core = try s.own(try @import("native_highlight_core.zig").create(engine, try s.own(try @import("native_highlight_loggers.zig").create(engine))));
    const factories = try s.object();
    inline for (.{ .{ "python", @import("native_highlight_grammar_python.zig") }, .{ "java", @import("native_highlight_grammar_java.zig") }, .{ "go", @import("native_highlight_grammar_go.zig") }, .{ "json", @import("native_highlight_grammar_json.zig") }, .{ "php", @import("native_highlight_grammar_php.zig") }, .{ "ruby", @import("native_highlight_grammar_ruby.zig") }, .{ "csharp", @import("native_highlight_grammar_csharp.zig") }, .{ "nix", @import("native_highlight_grammar_nix.zig") }, .{ "bash", @import("native_highlight_grammar_bash.zig") }, .{ "rust", @import("native_highlight_grammar_rust.zig") }, .{ "scala", @import("native_highlight_grammar_scala.zig") }, .{ "kotlin", @import("native_highlight_grammar_kotlin.zig") }, .{ "swift", @import("native_highlight_grammar_swift.zig") }, .{ "dart", @import("native_highlight_grammar_dart.zig") }, .{ "groovy", @import("native_highlight_grammar_groovy.zig") }, .{ "perl", @import("native_highlight_grammar_perl.zig") }, .{ "lua", @import("native_highlight_grammar_lua.zig") } }) |entry| try s.put(factories, entry[0], try s.own(try entry[1].create(engine)));
    try s.put(factories, "javascript", try s.own(try @import("native_highlight_grammar_js_family.zig").create(engine, false)));
    try s.put(factories, "typescript", try s.own(try @import("native_highlight_grammar_js_family.zig").create(engine, true)));
    try s.put(factories, "c", try s.own(try @import("native_highlight_grammar_c_family.zig").create(engine, false)));
    try s.put(factories, "cpp", try s.own(try @import("native_highlight_grammar_c_family.zig").create(engine, true)));
    // Preserve Source eager registration order and factory-map own key order.
    const ordered = try s.object();
    inline for (@import("native_highlight_core.zig").eager_order) |name| try s.put(ordered, name, try s.get(factories, name));
    try @import("native_highlight_core.zig").registerEager(engine, core, ordered);
    const syntax = try s.object();
    try s.put(syntax, "highlight", try s.own(try ordinary.create(engine, "highlight", 1, highlightCall, &.{core})));
    try s.put(syntax, "supportsLanguage", try s.own(try ordinary.create(engine, "supportsLanguage", 1, supportsCall, &.{core})));
    try s.put(syntax, "renderHighlightedHtml", try s.own(try ordinary.create(engine, "renderHighlightedHtml", 1, renderCall, &.{})));
    return .{ .core = c.JS_DupValue(engine.context, core), .syntax = c.JS_DupValue(engine.context, syntax), .factories = c.JS_DupValue(engine.context, ordered) };
}
