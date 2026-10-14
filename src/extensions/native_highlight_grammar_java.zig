//! Complete Source highlight.js10.7.3 Java factory and shared module NUMERIC graph.
//! Private source-only; no grammar/scanner/public qualification.
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const c = em.c;
const decimal = "[0-9](_*[0-9])*";
const frac = "\\.(" ++ decimal ++ ")";
const hex = "[0-9a-fA-F](_*[0-9a-fA-F])*";
const ident = "[À-ʸa-zA-Z_$][À-ʸa-zA-Z_$0-9]*";
const generic = ident ++ "(<" ++ ident ++ "(\\s*,\\s*" ++ ident ++ ")*>)?";
const keywords = "false synchronized int abstract float private char boolean var static null if const for true while long strictfp finally protected import native final void enum else break transient catch instanceof byte super volatile case assert short package default double public try this switch continue throws protected public private module requires exports do";
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
    const module = "pi-native:highlight-java-module";
    if (!engine.native_module_values.contains(module)) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const number = try numeric(&scope);
        const exports = try scope.object();
        try scope.put(exports, "NUMERIC", number);
        const Adapter = struct {
            fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
                return build(host, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]);
            }
        };
        try scope.put(exports, "factory", try scope.own(try ordinary.create(engine, "java", 1, Adapter.invoke, &.{number})));
        try engine.registerValueModule(module, exports);
    }
    return @import("native_sdk.zig").get(engine, engine.native_module_values.get(module).?, "factory");
}
fn params(scope: *Scope, contains: c.JSValue) !c.JSValue {
    const result = try mode(scope, "params");
    try scope.put(result, "begin", try literal(scope, "\\("));
    try scope.put(result, "end", try literal(scope, "\\)"));
    try scope.put(result, "keywords", try scope.text(keywords));
    try scope.put(result, "relevance", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(result, "contains", contains);
    return result;
}
fn titleCall(scope: *Scope, hljs: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "begin", try scope.concat(try scope.get(hljs, "UNDERSCORE_IDENT_RE"), try scope.text("\\s*\\(")));
    try scope.put(result, "returnBegin", c.pi_js_bool(scope.engine.context, 1));
    try scope.put(result, "relevance", c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(result, "contains", try list(scope, &.{try scope.get(hljs, "UNDERSCORE_TITLE_MODE")}));
    return result;
}
fn build(engine: *em.Engine, hljs: c.JSValue, number: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const annotation = try mode(&scope, "meta");
    try scope.put(annotation, "begin", try scope.text("@" ++ ident));
    const annotation_params = try scope.object();
    try scope.put(annotation_params, "begin", try literal(&scope, "\\("));
    try scope.put(annotation_params, "end", try literal(&scope, "\\)"));
    try scope.put(annotation_params, "contains", try list(&scope, &.{try scope.text("self")}));
    try scope.put(annotation, "contains", try list(&scope, &.{annotation_params}));
    const language = try scope.object();
    try scope.put(language, "name", try scope.text("Java"));
    try scope.put(language, "aliases", try list(&scope, &.{try scope.text("jsp")}));
    try scope.put(language, "keywords", try scope.text(keywords));
    try scope.put(language, "illegal", try literal(&scope, "</|#"));
    const contains = try scope.array();
    const comment = try scope.get(hljs, "COMMENT");
    const comment_options = try scope.object();
    try scope.put(comment_options, "relevance", c.JS_NewInt32(engine.context, 0));
    const email = try scope.object();
    try scope.put(email, "begin", try literal(&scope, "\\w+@"));
    try scope.put(email, "relevance", c.JS_NewInt32(engine.context, 0));
    const tag = try mode(&scope, "doctag");
    try scope.put(tag, "begin", try scope.text("@[A-Za-z]+"));
    try scope.put(comment_options, "contains", try list(&scope, &.{ email, tag }));
    try scope.index(contains, 0, try scope.call(comment, hljs, &.{ try scope.text("/\\*\\*"), try scope.text("\\*/"), comment_options }));
    const import = try scope.object();
    try scope.put(import, "begin", try literal(&scope, "import java\\.[a-z]+\\."));
    try scope.put(import, "keywords", try scope.text("import"));
    try scope.put(import, "relevance", c.JS_NewInt32(engine.context, 2));
    try scope.index(contains, 1, import);
    try scope.index(contains, 2, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    try scope.index(contains, 3, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try scope.index(contains, 4, try scope.get(hljs, "APOS_STRING_MODE"));
    try scope.index(contains, 5, try scope.get(hljs, "QUOTE_STRING_MODE"));
    const declaration = try mode(&scope, "class");
    try scope.put(declaration, "beginKeywords", try scope.text("class interface enum"));
    try scope.put(declaration, "end", try literal(&scope, "[{;=]"));
    try scope.put(declaration, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(declaration, "relevance", c.JS_NewInt32(engine.context, 1));
    try scope.put(declaration, "keywords", try scope.text("class interface enum"));
    try scope.put(declaration, "illegal", try literal(&scope, "[:\"\\[\\]]"));
    const extends = try scope.object();
    try scope.put(extends, "beginKeywords", try scope.text("extends implements"));
    try scope.put(declaration, "contains", try list(&scope, &.{ extends, try scope.get(hljs, "UNDERSCORE_TITLE_MODE") }));
    try scope.index(contains, 6, declaration);
    const expression = try scope.object();
    try scope.put(expression, "beginKeywords", try scope.text("new throw return else"));
    try scope.put(expression, "relevance", c.JS_NewInt32(engine.context, 0));
    try scope.index(contains, 7, expression);
    const record = try mode(&scope, "class");
    try scope.put(record, "begin", try scope.concat(try scope.concat(try scope.text("record\\s+"), try scope.get(hljs, "UNDERSCORE_IDENT_RE")), try scope.text("\\s*\\(")));
    try scope.put(record, "returnBegin", c.pi_js_bool(engine.context, 1));
    try scope.put(record, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(record, "end", try literal(&scope, "[{;=]"));
    try scope.put(record, "keywords", try scope.text(keywords));
    const record_children = try scope.array();
    const record_word = try scope.object();
    try scope.put(record_word, "beginKeywords", try scope.text("record"));
    try scope.index(record_children, 0, record_word);
    try scope.index(record_children, 1, try titleCall(&scope, hljs));
    try scope.index(record_children, 2, try params(&scope, try list(&scope, &.{try scope.get(hljs, "C_BLOCK_COMMENT_MODE")})));
    try scope.index(record_children, 3, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    try scope.index(record_children, 4, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try scope.put(record, "contains", record_children);
    try scope.index(contains, 8, record);
    const function = try mode(&scope, "function");
    try scope.put(function, "begin", try scope.concat(try scope.concat(try scope.text("(" ++ generic ++ "\\s+)+"), try scope.get(hljs, "UNDERSCORE_IDENT_RE")), try scope.text("\\s*\\(")));
    try scope.put(function, "returnBegin", c.pi_js_bool(engine.context, 1));
    try scope.put(function, "end", try literal(&scope, "[{;=]"));
    try scope.put(function, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try scope.put(function, "keywords", try scope.text(keywords));
    const children = try scope.array();
    try scope.index(children, 0, try titleCall(&scope, hljs));
    try scope.index(children, 1, try params(&scope, try list(&scope, &.{ annotation, try scope.get(hljs, "APOS_STRING_MODE"), try scope.get(hljs, "QUOTE_STRING_MODE"), number, try scope.get(hljs, "C_BLOCK_COMMENT_MODE") })));
    try scope.index(children, 2, try scope.get(hljs, "C_LINE_COMMENT_MODE"));
    try scope.index(children, 3, try scope.get(hljs, "C_BLOCK_COMMENT_MODE"));
    try scope.put(function, "contains", children);
    try scope.index(contains, 9, function);
    try scope.index(contains, 10, number);
    try scope.index(contains, 11, annotation);
    try scope.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
