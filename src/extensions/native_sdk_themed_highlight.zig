//! Actual c268 theme highlighting over retained real syntax and Theme owners.
//! Ordinary catches preserve the separate public and Markdown fallback bodies.
const v = @import("native_public_values.zig");
const agent = @import("native_agent_af_values.zig");
const c = v.c;
const Scope = v.Scope;
const Engine = v.em.Engine;
const module_name = "pi-native:themed-highlight";
pub const public_owner_key = "\x00public-theme-owner";

pub fn createState(engine: *Engine, syntax: c.JSValue, runtime: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, createStateBody(&s, syntax, runtime));
}
fn createStateBody(s: *Scope, syntax: c.JSValue, runtime: c.JSValue) !c.JSValue {
    const state = try v.stateObject(s);
    try v.put(s, state, "syntax", syntax);
    try v.put(s, state, "runtime", runtime);
    // These are the actual imported module bindings, retained once at linking.
    try v.put(s, state, "theme", try v.get(s, runtime, "theme"));
    try v.put(s, state, "supportsLanguage", try v.get(s, syntax, "supportsLanguage"));
    try v.put(s, state, "highlight", try v.get(s, syntax, "highlight"));
    try v.put(s, state, "cachedHighlightThemeFor", c.pi_js_undefined());
    try v.put(s, state, "cachedCliHighlightTheme", c.pi_js_undefined());
    return v.duplicate(s, state);
}
pub fn install(engine: *Engine, syntax: c.JSValue, runtime: c.JSValue) !void {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishVoid(&s, installBody(&s, syntax, runtime));
}
fn installBody(s: *Scope, syntax: c.JSValue, runtime: c.JSValue) !void {
    const state = try v.own(s, try createState(s.engine, syntax, runtime));
    try bindState(s.engine, state);
}
pub fn bindState(engine: *Engine, state: c.JSValue) !void {
    try engine.registerValueModule(module_name, state);
}
pub fn language(engine: *Engine, path: c.JSValue) !c.JSValue {
    return @import("native_sdk_highlight_paths.zig").get(engine, path);
}
pub fn highlight(engine: *Engine, code: c.JSValue, lang: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, installedHighlight(&s, code, lang));
}
fn installedHighlight(s: *Scope, code: c.JSValue, lang: c.JSValue) !c.JSValue {
    // Keep any earlier private C-module registration intact. The completed
    // application owner supplies the one actual public binding when present.
    const state = if (s.engine.native_module_values.get(public_owner_key)) |owner|
        try v.get(s, owner, "highlightState")
    else
        s.engine.native_module_values.get(module_name) orelse return error.NativeThemedHighlightNotInstalled;
    return highlightState(s.engine, state, code, lang, false);
}
pub fn highlightState(engine: *Engine, state: c.JSValue, code: c.JSValue, lang: c.JSValue, markdown: bool) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, highlightBody(&s, state, code, lang, markdown));
}
fn highlightBody(s: *Scope, state: c.JSValue, code: c.JSValue, lang: c.JSValue, markdown: bool) !c.JSValue {
    const valid = if (v.truthy(s, lang) and try supported(s.engine, state, lang)) lang else c.pi_js_undefined();
    if (!v.truthy(s, valid)) return coloredLines(s.engine, state, code);
    const options = try v.object(s);
    try v.put(s, options, "language", valid);
    try v.put(s, options, "ignoreIllegals", v.boolean(s, true));
    try v.put(s, options, "theme", try v.own(s, try cliTheme(s.engine, state)));
    // Source builds the options/cache outside its ordinary highlighting catch.
    return highlightedLines(s.engine, state, code, options) catch |err| {
        try discardCaught(s.engine, err);
        return if (markdown) coloredLines(s.engine, state, code)
        else v.invokeTextOwned(s.engine, code, "split", "\n");
    };
}
fn supported(engine: *Engine, state: c.JSValue, lang: c.JSValue) !bool {
    var s: Scope = .{ .engine = engine };
    const value = try v.owned.finishValue(&s, supportedBody(&s, state, lang));
    return c.JS_ToBool(engine.context, value) == 1;
}
fn supportedBody(s: *Scope, state: c.JSValue, lang: c.JSValue) !c.JSValue {
    const result = try v.call(s, try v.get(s, state, "supportsLanguage"), c.pi_js_undefined(), &.{lang});
    return v.boolean(s, v.truthy(s, result));
}
fn discardCaught(engine: *Engine, err: anyerror) !void {
    // No value tag or callback-wide allocation generation classifies DATA.
    const reason = try agent.caught(engine, err);
    var completion = v.owned.Completion.initVoid(engine, {});
    completion.release(reason);
    return completion.finishVoid();
}
fn highlightedLines(engine: *Engine, state: c.JSValue, code: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, highlightedLinesBody(&s, state, code, options));
}
fn highlightedLinesBody(s: *Scope, state: c.JSValue, code: c.JSValue, options: c.JSValue) !c.JSValue {
    const result = try v.call(s, try v.get(s, state, "highlight"), c.pi_js_undefined(), &.{ code, options });
    return v.invokeTextOwned(s.engine, result, "split", "\n");
}
fn coloredLines(engine: *Engine, state: c.JSValue, code: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, coloredLinesBody(&s, state, code));
}
fn coloredLinesBody(s: *Scope, state: c.JSValue, code: c.JSValue) !c.JSValue {
    const lines = try v.own(s, try v.invokeTextOwned(s.engine, code, "split", "\n"));
    const map = try v.get(s, lines, "map");
    const theme = try v.get(s, state, "theme");
    const callback = try formatter(s, theme, "", "mdCodeBlock", "fg");
    return v.duplicate(s, try v.call(s, map, lines, &.{callback}));
}
fn formatColor(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, colorBody(&s, v.arg(args, 0), roots[0], roots[1]));
}
fn colorBody(s: *Scope, input: c.JSValue, theme: c.JSValue, token: c.JSValue) !c.JSValue {
    const callable = try v.get(s, theme, "fg");
    return v.duplicate(s, try v.call(s, callable, theme, &.{ token, input }));
}
fn formatStyle(engine: *Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, styleBody(&s, v.arg(args, 0), roots[0], roots[1]));
}
fn styleBody(s: *Scope, input: c.JSValue, theme: c.JSValue, property: c.JSValue) !c.JSValue {
    const callable = try v.key(s, theme, property);
    return v.duplicate(s, try v.call(s, callable, theme, &.{input}));
}
pub fn formatter(s: *Scope, theme: c.JSValue, name: [*:0]const u8, token: []const u8, comptime method: []const u8) !c.JSValue {
    return if (comptime @import("std").mem.eql(u8, method, "fg"))
        v.arrow(s, name, 1, formatColor, &.{ theme, try v.text(s, token) })
    else
        v.arrow(s, name, 1, formatStyle, &.{ theme, try v.text(s, method) });
}
fn cliTheme(engine: *Engine, state: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    return v.owned.finishValue(&s, cliThemeBody(&s, state));
}
fn cliThemeBody(s: *Scope, state: c.JSValue) !c.JSValue {
    const theme = try v.get(s, state, "theme");
    if (v.equal(s, try v.get(s, state, "cachedHighlightThemeFor"), theme)) {
        const cached = try v.get(s, state, "cachedCliHighlightTheme");
        if (v.truthy(s, cached)) return v.duplicate(s, cached);
    }
    try v.set(s, state, "cachedHighlightThemeFor", theme);
    const mapping = try v.object(s);
    inline for (.{
        .{ "keyword", "syntaxKeyword" }, .{ "built_in", "syntaxType" },
        .{ "literal", "syntaxNumber" }, .{ "number", "syntaxNumber" },
        .{ "regexp", "syntaxString" }, .{ "string", "syntaxString" },
        .{ "subst", "text" }, .{ "comment", "syntaxComment" },
        .{ "doctag", "syntaxComment" }, .{ "meta", "muted" },
        .{ "function", "syntaxFunction" }, .{ "title", "syntaxFunction" },
        .{ "class", "syntaxType" }, .{ "type", "syntaxType" },
        .{ "tag", "syntaxPunctuation" }, .{ "name", "syntaxKeyword" },
        .{ "attr", "syntaxVariable" }, .{ "variable", "syntaxVariable" },
        .{ "params", "syntaxVariable" }, .{ "operator", "syntaxOperator" },
        .{ "punctuation", "syntaxPunctuation" },
    }) |entry| try v.put(s, mapping, entry[0], try formatter(s, theme, entry[0], entry[1], "fg"));
    try v.put(s, mapping, "emphasis", try formatter(s, theme, "emphasis", "", "italic"));
    try v.put(s, mapping, "strong", try formatter(s, theme, "strong", "", "bold"));
    try v.put(s, mapping, "link", try formatter(s, theme, "link", "", "underline"));
    try v.put(s, mapping, "addition", try formatter(s, theme, "addition", "toolDiffAdded", "fg"));
    try v.put(s, mapping, "deletion", try formatter(s, theme, "deletion", "toolDiffRemoved", "fg"));
    try v.set(s, state, "cachedCliHighlightTheme", mapping);
    return v.duplicate(s, mapping);
}
