//! Complete Source highlight.js10.7.3 Kotlin factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const decimal = "[0-9](_*[0-9])*";
const frac = "\\.(" ++ decimal ++ ")";
const hex = "[0-9a-fA-F](_*[0-9a-fA-F])*";
fn literal(scope: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try scope.text(pattern)};
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(scope: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try scope.array();
    for (values, 0..) |value, index| try scope.index(result, @intCast(index), value);
    return result;
}
fn mode(scope: *Scope, name: []const u8) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "className", try scope.text(name));
    return result;
}
fn numeric(scope: *Scope) !c.JSValue {
    const number = try mode(scope, "number");
    const variants = try scope.array();
    inline for (.{
        "(\\b(" ++ decimal ++ ")((" ++ frac ++ ")|\\.)?|(" ++ frac ++ "))[eE][+-]?(" ++ decimal ++ ")[fFdD]?\\b",
        "\\b(" ++ decimal ++ ")((" ++ frac ++ ")[fFdD]?\\b|\\.([fFdD]\\b)?)",
        "(" ++ frac ++ ")[fFdD]?\\b",
        "\\b(" ++ decimal ++ ")[fFdD]\\b",
        "\\b0[xX]((" ++ hex ++ ")\\.?|(" ++ hex ++ ")?\\.(" ++ hex ++ "))[pP][+-]?(" ++ decimal ++ ")[fFdD]?\\b",
        "\\b(0|[1-9](_*[0-9])*)[lL]?\\b",
        "\\b0[xX](" ++ hex ++ ")[lL]?\\b",
        "\\b0(_*[0-7])*[lL]?\\b",
        "\\b0[bB][01](_*[01])*[lL]?\\b",
    }, 0..) |pattern, index| {
        const variant = try scope.object();
        try scope.put(variant, "begin", try scope.text(pattern));
        try scope.index(variants, index, variant);
    }
    try scope.put(number, "variants", variants);
    try scope.put(number, "relevance", c.JS_NewInt32(scope.engine.context, 0));
    return number;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const module = "pi-native:highlight-kotlin-module";
    if (!engine.native_module_values.contains(module)) {
        var s: Scope = .{ .engine = engine };
        defer s.deinit();
        const number = try numeric(&s);
        const exports = try s.object();
        try s.put(exports, "NUMERIC", number);
        const Adapter = struct {
            fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
                return build(host, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
            }
        };
        try s.put(exports, "factory", try s.own(try ordinary.create(engine, "kotlin", 1, Adapter.invoke, &.{number})));
        try engine.registerValueModule(module, exports);
    }
    return @import("native_sdk.zig").get(engine, engine.native_module_values.get(module).?, "factory");
}
fn typeAngles(s: *Scope, exclude: bool) !c.JSValue {
    const result = try mode(s, "type");
    try s.put(result, "begin", try literal(s, "<"));
    try s.put(result, "end", try literal(s, ">"));
    if (exclude) {
        try s.put(result, "excludeBegin", c.pi_js_bool(s.engine.context, 1));
        try s.put(result, "excludeEnd", c.pi_js_bool(s.engine.context, 1));
    } else try s.put(result, "keywords", try s.text("reified"));
    try s.put(result, "relevance", c.JS_NewInt32(s.engine.context, 0));
    return result;
}
fn build(engine: *em.Engine, hljs: c.JSValue, number: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("abstract as val var vararg get set class object open private protected public noinline crossinline dynamic final enum if else do while for when throw try catch finally import package is in fun override companion reified inline lateinit init interface annotation data sealed internal infix operator out by constructor super tailrec where const inner suspend typealias external expect actual"));
    try s.put(keywords, "built_in", try s.text("Byte Short Char Int Long Boolean Float Double Void Unit Nothing"));
    try s.put(keywords, "literal", try s.text("true false null"));
    const labelled = try mode(&s, "keyword");
    try s.put(labelled, "begin", try literal(&s, "\\b(break|continue|return|this)\\b"));
    const starts = try s.object();
    const label_symbol = try mode(&s, "symbol");
    try s.put(label_symbol, "begin", try literal(&s, "@\\w+"));
    try s.put(starts, "contains", try list(&s, &.{label_symbol}));
    try s.put(labelled, "starts", starts);
    const label = try mode(&s, "symbol");
    try s.put(label, "begin", try s.concat(try s.get(hljs, "UNDERSCORE_IDENT_RE"), try s.text("@")));
    const subst = try mode(&s, "subst");
    try s.put(subst, "begin", try literal(&s, "\\$\\{"));
    try s.put(subst, "end", try literal(&s, "\\}"));
    try s.put(subst, "contains", try list(&s, &.{try s.get(hljs, "C_NUMBER_MODE")}));
    const variable = try mode(&s, "variable");
    try s.put(variable, "begin", try s.concat(try s.text("\\$"), try s.get(hljs, "UNDERSCORE_IDENT_RE")));
    const string = try mode(&s, "string");
    const strings = try s.array();
    const triple = try s.object();
    try s.put(triple, "begin", try s.text("\"\"\""));
    try s.put(triple, "end", try s.text("\"\"\"(?=[^\"])"));
    try s.put(triple, "contains", try list(&s, &.{ variable, subst }));
    try s.index(strings, 0, triple);
    const apostrophe = try s.object();
    try s.put(apostrophe, "begin", try s.text("'"));
    try s.put(apostrophe, "end", try s.text("'"));
    try s.put(apostrophe, "illegal", try literal(&s, "\\n"));
    try s.put(apostrophe, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    try s.index(strings, 1, apostrophe);
    const quote = try s.object();
    try s.put(quote, "begin", try s.text("\""));
    try s.put(quote, "end", try s.text("\""));
    try s.put(quote, "illegal", try literal(&s, "\\n"));
    try s.put(quote, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), variable, subst }));
    try s.index(strings, 2, quote);
    try s.put(string, "variants", strings);
    _ = try s.invoke(try s.get(subst, "contains"), "push", &.{string});
    const use_site = try mode(&s, "meta");
    try s.put(use_site, "begin", try s.concat(try s.concat(try s.text("@(?:file|property|field|get|set|receiver|param|setparam|delegate)\\s*:(?:\\s*"), try s.get(hljs, "UNDERSCORE_IDENT_RE")), try s.text(")?")));
    const annotation = try mode(&s, "meta");
    try s.put(annotation, "begin", try s.concat(try s.text("@"), try s.get(hljs, "UNDERSCORE_IDENT_RE")));
    const annotation_params = try s.object();
    try s.put(annotation_params, "begin", try literal(&s, "\\("));
    try s.put(annotation_params, "end", try literal(&s, "\\)"));
    const inherit = try s.get(hljs, "inherit");
    const annotation_changes = try s.object();
    try s.put(annotation_changes, "className", try s.text("meta-string"));
    try s.put(annotation_params, "contains", try list(&s, &.{try s.call(inherit, hljs, &.{ string, annotation_changes })}));
    try s.put(annotation, "contains", try list(&s, &.{annotation_params}));
    const comment = try s.get(hljs, "COMMENT");
    const comment_options = try s.object();
    try s.put(comment_options, "contains", try list(&s, &.{try s.get(hljs, "C_BLOCK_COMMENT_MODE")}));
    const nested_comment = try s.call(comment, hljs, &.{ try s.text("/\\*"), try s.text("\\*/"), comment_options });
    const paren_type = try s.object();
    const type_variant = try mode(&s, "type");
    try s.put(type_variant, "begin", try s.get(hljs, "UNDERSCORE_IDENT_RE"));
    const parens = try s.object();
    try s.put(parens, "begin", try literal(&s, "\\("));
    try s.put(parens, "end", try literal(&s, "\\)"));
    try s.put(parens, "contains", try s.array());
    try s.put(paren_type, "variants", try list(&s, &.{ type_variant, parens }));
    try s.set(parens, "contains", try list(&s, &.{paren_type}));
    try s.set(parens, "contains", try list(&s, &.{paren_type}));
    const language = try s.object();
    try s.put(language, "name", try s.text("Kotlin"));
    try s.put(language, "aliases", try list(&s, &.{ try s.text("kt"), try s.text("kts") }));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    const doc_comment = try s.get(hljs, "COMMENT");
    const doc_options = try s.object();
    try s.put(doc_options, "relevance", c.JS_NewInt32(engine.context, 0));
    const doctag = try mode(&s, "doctag");
    try s.put(doctag, "begin", try s.text("@[A-Za-z]+"));
    try s.put(doc_options, "contains", try list(&s, &.{doctag}));
    try s.index(contains, 0, try s.call(doc_comment, hljs, &.{ try s.text("/\\*\\*"), try s.text("\\*/"), doc_options }));
    try s.index(contains, 1, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(contains, 2, nested_comment);
    try s.index(contains, 3, labelled);
    try s.index(contains, 4, label);
    try s.index(contains, 5, use_site);
    try s.index(contains, 6, annotation);
    const function = try mode(&s, "function");
    try s.put(function, "beginKeywords", try s.text("fun"));
    try s.put(function, "end", try s.text("[(]|$"));
    try s.put(function, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(function, "keywords", keywords);
    try s.put(function, "relevance", c.JS_NewInt32(engine.context, 5));
    const function_children = try s.array();
    const title = try s.object();
    try s.put(title, "begin", try s.concat(try s.get(hljs, "UNDERSCORE_IDENT_RE"), try s.text("\\s*\\(")));
    try s.put(title, "returnBegin", c.pi_js_bool(engine.context, 1));
    try s.put(title, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(title, "contains", try list(&s, &.{try s.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    try s.index(function_children, 0, title);
    try s.index(function_children, 1, try typeAngles(&s, false));
    const params = try mode(&s, "params");
    try s.put(params, "begin", try literal(&s, "\\("));
    try s.put(params, "end", try literal(&s, "\\)"));
    try s.put(params, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(params, "keywords", keywords);
    try s.put(params, "relevance", c.JS_NewInt32(engine.context, 0));
    const typed = try s.object();
    try s.put(typed, "begin", try literal(&s, ":"));
    try s.put(typed, "end", try literal(&s, "[=,/]"));
    try s.put(typed, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(typed, "contains", try list(&s, &.{ paren_type, try s.get(hljs, "C_LINE_COMMENT_MODE"), nested_comment }));
    try s.put(typed, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(params, "contains", try list(&s, &.{ typed, try s.get(hljs, "C_LINE_COMMENT_MODE"), nested_comment, use_site, annotation, string, try s.get(hljs, "C_NUMBER_MODE") }));
    try s.index(function_children, 2, params);
    try s.index(function_children, 3, nested_comment);
    try s.put(function, "contains", function_children);
    try s.index(contains, 7, function);
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class interface trait"));
    try s.put(class_mode, "end", try literal(&s, "[:\\{(]|$"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(class_mode, "illegal", try s.text("extends implements"));
    const access = try s.object();
    try s.put(access, "beginKeywords", try s.text("public protected internal private constructor"));
    const class_title = try s.get(hljs, "UNDERSCORE_TITLE_MODE");
    const class_type = try typeAngles(&s, true);
    const ancestor = try mode(&s, "type");
    try s.put(ancestor, "begin", try literal(&s, "[,:]\\s*"));
    try s.put(ancestor, "end", try literal(&s, "[<\\(,]|$"));
    try s.put(ancestor, "excludeBegin", c.pi_js_bool(engine.context, 1));
    try s.put(ancestor, "returnEnd", c.pi_js_bool(engine.context, 1));
    try s.put(class_mode, "contains", try list(&s, &.{ access, class_title, class_type, ancestor, use_site, annotation }));
    try s.index(contains, 8, class_mode);
    try s.index(contains, 9, string);
    const shebang = try mode(&s, "meta");
    try s.put(shebang, "begin", try s.text("^#!/usr/bin/env"));
    try s.put(shebang, "end", try s.text("$"));
    try s.put(shebang, "illegal", try s.text("\n"));
    try s.index(contains, 10, shebang);
    try s.index(contains, 11, number);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
