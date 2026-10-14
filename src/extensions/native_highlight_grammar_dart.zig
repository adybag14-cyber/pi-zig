//! Complete Source highlight.js10.7.3 Dart factory; source-only draft.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn words(s: *Scope, text: []const u8) !c.JSValue {
    const result = try s.array();
    var parts = std.mem.splitScalar(u8, text, ' ');
    var index: u32 = 0;
    while (parts.next()) |part| : (index += 1) try s.index(result, index, try s.text(part));
    return result;
}
fn literal(s: *Scope, text: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(text)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn mode(s: *Scope, name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(name));
    return result;
}
fn nullable(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return nullableValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn nullableValue(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    return c.JS_DupValue(engine.context, try s.concat(try s.stringify(value), try s.text("?")));
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "dart", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const subst = try mode(&s, "subst");
    const variable = try s.object();
    try s.put(variable, "begin", try s.text("\\$[A-Za-z0-9_]+"));
    try s.put(subst, "variants", try list(&s, &.{variable}));
    const braced = try mode(&s, "subst");
    const braces = try s.object();
    try s.put(braces, "begin", try literal(&s, "\\$\\{"));
    try s.put(braces, "end", try literal(&s, "\\}"));
    try s.put(braced, "variants", try list(&s, &.{braces}));
    try s.put(braced, "keywords", try s.text("true false null this is new super"));
    const string = try mode(&s, "string");
    const variants = try s.array();
    inline for (.{ .{ "r'''", "'''", false, false }, .{ "r\"\"\"", "\"\"\"", false, false }, .{ "r'", "'", true, false }, .{ "r\"", "\"", true, false }, .{ "'''", "'''", false, true }, .{ "\"\"\"", "\"\"\"", false, true }, .{ "'", "'", true, true }, .{ "\"", "\"", true, true } }, 0..) |entry, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(entry[0]));
        try s.put(variant, "end", try s.text(entry[1]));
        if (entry[2]) try s.put(variant, "illegal", try s.text("\\n"));
        if (entry[3]) try s.put(variant, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst, braced }));
        try s.index(variants, index, variant);
    }
    try s.put(string, "variants", variants);
    try s.set(braced, "contains", try list(&s, &.{ try s.get(hljs, "C_NUMBER_MODE"), string }));
    const builtins = try words(&s, "Comparable DateTime Duration Function Iterable Iterator List Map Match Object Pattern RegExp Set Stopwatch String StringBuffer StringSink Symbol Type Uri bool double int num Element ElementList");
    const nullable_fn = try s.own(try engine.checked(c.JS_NewCFunction(engine.context, nullable, "", 1)));
    const nullable_types = try s.invoke(builtins, "map", &.{nullable_fn});
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in inferface is late library mixin new null on operator part required rethrow return set show static super switch sync this throw true try typedef var void while with yield"));
    const combined = try s.invoke(builtins, "concat", &.{nullable_types});
    const concat = try s.get(combined, "concat");
    const extra = try words(&s, "Never Null dynamic print document querySelector querySelectorAll window");
    try s.put(keywords, "built_in", try s.call(concat, combined, &.{extra}));
    try s.put(keywords, "$pattern", try literal(&s, "[A-Za-z][A-Za-z0-9_]*\\??"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Dart"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, string);
    const comment = try s.get(hljs, "COMMENT");
    const comment_begin = try literal(&s, "/\\*\\*(?!/)");
    const comment_end = try literal(&s, "\\*/");
    const comment_options = try s.object();
    try s.put(comment_options, "subLanguage", try s.text("markdown"));
    try s.put(comment_options, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 1, try s.call(comment, hljs, &.{ comment_begin, comment_end, comment_options }));
    const line_comment = try s.get(hljs, "COMMENT");
    const line_begin = try literal(&s, "/{3,} ?");
    const line_end = try literal(&s, "$");
    const line_options = try s.object();
    const inner = try s.object();
    try s.put(inner, "subLanguage", try s.text("markdown"));
    try s.put(inner, "begin", try s.text("."));
    try s.put(inner, "end", try s.text("$"));
    try s.put(inner, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(line_options, "contains", try list(&s, &.{inner}));
    try s.index(contains, 2, try s.call(line_comment, hljs, &.{ line_begin, line_end, line_options }));
    try s.index(contains, 3, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(contains, 4, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class interface"));
    try s.put(class_mode, "end", try literal(&s, "\\{"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const extends = try s.object();
    try s.put(extends, "beginKeywords", try s.text("extends implements"));
    try s.put(class_mode, "contains", try list(&s, &.{ extends, try s.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    try s.index(contains, 5, class_mode);
    try s.index(contains, 6, try s.get(hljs, "C_NUMBER_MODE"));
    const meta = try mode(&s, "meta");
    try s.put(meta, "begin", try s.text("@[A-Za-z]+"));
    try s.index(contains, 7, meta);
    const arrow = try s.object();
    try s.put(arrow, "begin", try s.text("=>"));
    try s.index(contains, 8, arrow);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
