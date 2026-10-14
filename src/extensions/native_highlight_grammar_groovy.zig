//! Complete Source highlight.js10.7.3 Groovy factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
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
fn variants(s: *Scope, values: c.JSValue, object: ?c.JSValue) !c.JSValue {
    const result = object orelse try s.object();
    try s.set(result, "variants", values);
    return result;
}
fn sourceCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return @import("native_highlight_regex.zig").source(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_sdk.zig").fail(engine, err);
}
fn lookahead(s: *Scope, value: c.JSValue) !c.JSValue {
    const args = try list(s, &.{ try s.text("(?="), value, try s.text(")") });
    const fn_value = try s.own(try s.engine.checked(c.JS_NewCFunction(s.engine.context, sourceCallback, "", 1)));
    return s.invoke(try s.invoke(args, "map", &.{fn_value}), "join", &.{try s.text("")});
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "groovy", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const comments = try s.array();
    try s.index(comments, 0, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(comments, 1, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const comment_fn = try s.get(hljs, "COMMENT");
    const comment_options = try s.object();
    try s.put(comment_options, "relevance", c.JS_NewInt32(engine.context, 0));
    const email = try s.object();
    try s.put(email, "begin", try literal(&s, "\\w+@"));
    try s.put(email, "relevance", c.JS_NewInt32(engine.context, 0));
    const doctag = try mode(&s, "doctag");
    try s.put(doctag, "begin", try s.text("@[A-Za-z]+"));
    try s.put(comment_options, "contains", try list(&s, &.{ email, doctag }));
    try s.index(comments, 2, try s.call(comment_fn, hljs, &.{ try s.text("/\\*\\*"), try s.text("\\*/"), comment_options }));
    const comment = try variants(&s, comments, null);
    const regexp = try mode(&s, "regexp");
    try s.put(regexp, "begin", try literal(&s, "~?/[^/\\n]+/"));
    try s.put(regexp, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const number = try variants(&s, try list(&s, &.{ try s.get(hljs, "BINARY_NUMBER_MODE"), try s.get(hljs, "C_NUMBER_MODE") }), null);
    const strings = try s.array();
    inline for (.{ "\"\"\"", "'''" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, delimiter));
        try s.put(variant, "end", try literal(&s, delimiter));
        try s.index(strings, index, variant);
    }
    const dollars = try s.object();
    try s.put(dollars, "begin", try s.text("\\$/"));
    try s.put(dollars, "end", try s.text("/\\$"));
    try s.put(dollars, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(strings, 2, dollars);
    try s.index(strings, 3, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(strings, 4, try s.get(hljs, "QUOTE_STRING_MODE"));
    const string = try variants(&s, strings, try mode(&s, "string"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Groovy"));
    const keywords = try s.object();
    try s.put(keywords, "built_in", try s.text("this super"));
    try s.put(keywords, "literal", try s.text("true false null"));
    try s.put(keywords, "keyword", try s.text("byte short char int long boolean float double void def as in assert trait abstract static volatile transient public private protected synchronized final class interface enum if else for while switch case break default continue throw throws try catch finally implements extends new import package return instanceof"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    const shebang_fn = try s.get(hljs, "SHEBANG");
    const shebang_options = try s.object();
    try s.put(shebang_options, "binary", try s.text("groovy"));
    try s.put(shebang_options, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 0, try s.call(shebang_fn, hljs, &.{shebang_options}));
    try s.index(contains, 1, comment);
    try s.index(contains, 2, string);
    try s.index(contains, 3, regexp);
    try s.index(contains, 4, number);
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class interface trait enum"));
    try s.put(class_mode, "end", try literal(&s, "\\{"));
    try s.put(class_mode, "illegal", try s.text(":"));
    const extends = try s.object();
    try s.put(extends, "beginKeywords", try s.text("extends implements"));
    try s.put(class_mode, "contains", try list(&s, &.{ extends, try s.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    try s.index(contains, 5, class_mode);
    const meta = try mode(&s, "meta");
    try s.put(meta, "begin", try s.text("@[A-Za-z]+"));
    try s.put(meta, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 6, meta);
    const attr = try mode(&s, "attr");
    try s.put(attr, "begin", try s.text("[A-Za-z0-9_$]+[ \t]*:"));
    try s.put(attr, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 7, attr);
    const ternary = try s.object();
    try s.put(ternary, "begin", try literal(&s, "\\?"));
    try s.put(ternary, "end", try literal(&s, ":"));
    try s.put(ternary, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(ternary, "contains", try list(&s, &.{ comment, string, regexp, number, try s.text("self") }));
    try s.index(contains, 8, ternary);
    const labelled = try mode(&s, "symbol");
    try s.put(labelled, "begin", try s.concat(try s.text("^[ \t]*"), try lookahead(&s, try s.text("[A-Za-z0-9_$]+:"))));
    try s.put(labelled, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(labelled, "end", try s.text("[A-Za-z0-9_$]+:"));
    try s.put(labelled, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 9, labelled);
    try s.put(language, "contains", contains);
    try s.put(language, "illegal", try literal(&s, "#|</"));
    return c.JS_DupValue(engine.context, language);
}
