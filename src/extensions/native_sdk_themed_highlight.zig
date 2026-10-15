//! Private Source theme frontend over an explicitly installed real syntax core.
//! Missing grammar bodies fail before the ordinary Source highlighting catch.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const module_name = "pi-native:themed-highlight";

fn color(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return colorValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic, roots) catch |err| sdk.fail(engine, err);
}
fn colorValue(engine: *em.Engine, text: c.JSValue, magic: c_int, roots: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const output = if (magic == 0) try s.invoke(roots[0], "fg", &.{ roots[1], text }) else try s.invoke(roots[0], if (magic == 1) "italic" else if (magic == 2) "bold" else "underline", &.{text});
    return c.JS_DupValue(engine.context, output);
}
fn formatter(s: *Scope, theme: c.JSValue, token: []const u8, style: c_int) !c.JSValue {
    var roots = [_]c.JSValue{ theme, try s.text(token) };
    return s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, color, "", 1, style, roots.len, &roots)));
}
fn cliTheme(s: *Scope, state: c.JSValue, theme: c.JSValue) !c.JSValue {
    const cached = try s.get(state, "cachedCliHighlightTheme");
    if (s.equal(try s.get(state, "cachedHighlightThemeFor"), theme) and s.truthy(cached)) return cached;
    // Source publishes Theme identity before building the mapping. Getter errors
    // therefore preserve its partially updated cache state.
    try s.set(state, "cachedHighlightThemeFor", theme);
    const mapping = try s.object();
    inline for (.{
        .{ "keyword", "syntaxKeyword" },         .{ "built_in", "syntaxType" },
        .{ "literal", "syntaxNumber" },          .{ "number", "syntaxNumber" },
        .{ "regexp", "syntaxString" },           .{ "string", "syntaxString" },
        .{ "subst", "text" },                    .{ "comment", "syntaxComment" },
        .{ "doctag", "syntaxComment" },          .{ "meta", "muted" },
        .{ "function", "syntaxFunction" },       .{ "title", "syntaxFunction" },
        .{ "class", "syntaxType" },              .{ "type", "syntaxType" },
        .{ "tag", "syntaxPunctuation" },         .{ "name", "syntaxKeyword" },
        .{ "attr", "syntaxVariable" },           .{ "variable", "syntaxVariable" },
        .{ "params", "syntaxVariable" },         .{ "operator", "syntaxOperator" },
        .{ "punctuation", "syntaxPunctuation" },
    }) |entry| try s.put(mapping, entry[0], try formatter(s, theme, entry[1], 0));
    try s.put(mapping, "emphasis", try formatter(s, theme, "", 1));
    try s.put(mapping, "strong", try formatter(s, theme, "", 2));
    try s.put(mapping, "link", try formatter(s, theme, "", 3));
    try s.put(mapping, "addition", try formatter(s, theme, "toolDiffAdded", 0));
    try s.put(mapping, "deletion", try formatter(s, theme, "toolDiffRemoved", 0));
    try s.set(state, "cachedCliHighlightTheme", mapping);
    return mapping;
}
pub fn install(engine: *em.Engine, syntax: c.JSValue, runtime: c.JSValue) !void {
    // runtime.theme is the live module binding, not a copied color table.
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    try s.put(state, "syntax", syntax);
    try s.put(state, "runtime", runtime);
    try s.put(state, "cachedHighlightThemeFor", c.pi_js_undefined());
    try s.put(state, "cachedCliHighlightTheme", c.pi_js_undefined());
    try engine.registerValueModule(module_name, state);
}
pub fn language(engine: *em.Engine, path: c.JSValue) !c.JSValue {
    return @import("native_sdk_highlight_paths.zig").get(engine, path);
}
fn highlightedLines(s: *Scope, syntax: c.JSValue, code: c.JSValue, options: c.JSValue) !c.JSValue {
    const result = try s.invoke(syntax, "highlight", &.{ code, options });
    return s.invoke(result, "split", &.{try s.text("\n")});
}
pub fn highlight(engine: *em.Engine, code: c.JSValue, lang: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = engine.native_module_values.get(module_name) orelse return error.NativeThemedHighlightNotInstalled;
    const syntax = try s.get(state, "syntax");
    const supported = if (s.truthy(lang)) try s.invoke(syntax, "supportsLanguage", &.{lang}) else lang;
    // The installed owner currently provides only actual eager grammars. A
    // missing lazy grammar must remain an explicit dependency failure; it must
    // never be represented by Source's unhighlighted unsupported-language path.
    if (s.truthy(lang) and !s.truthy(supported)) return error.NativeThemedHighlightGrammarUnavailable;
    const valid = if (s.truthy(supported)) lang else c.pi_js_undefined();
    if (!s.truthy(valid)) {
        const lines = try s.invoke(code, "split", &.{try s.text("\n")});
        const map = try s.get(lines, "map");
        const theme = try s.get(try s.get(state, "runtime"), "theme");
        const callback = try formatter(&s, theme, "mdCodeBlock", 0);
        return c.JS_DupValue(engine.context, try s.call(map, lines, &.{callback}));
    }
    const options = try s.object();
    try s.put(options, "language", valid);
    try s.put(options, "ignoreIllegals", c.pi_js_bool(engine.context, 1));
    try s.put(options, "theme", try cliTheme(&s, state, try s.get(try s.get(state, "runtime"), "theme")));
    // Exactly the Source try boundary: option/theme construction is outside it.
    const result = highlightedLines(&s, syntax, code, options) catch |err| {
        if (err != error.JavaScriptException) return err;
        // Host allocator tags remain available to the outer fresh-generation
        // diagnostic even when Source's ordinary catch returns the raw lines.
        return c.JS_DupValue(engine.context, try s.invoke(code, "split", &.{try s.text("\n")}));
    };
    return c.JS_DupValue(engine.context, result);
}
