//! Complete Source highlight.js10.7.3 Scala factory; source-only draft.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
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
fn brackets(s: *Scope, type_mode: c.JSValue, params: bool) !c.JSValue {
    const result = if (params) try mode(s, "params") else try s.object();
    try s.put(result, "begin", try literal(s, if (params) "\\(" else "\\["));
    try s.put(result, "end", try literal(s, if (params) "\\)" else "\\]"));
    try s.put(result, "excludeBegin", c.pi_js_bool(s.engine.context, 1));
    try s.put(result, "excludeEnd", c.pi_js_bool(s.engine.context, 1));
    try s.put(result, "relevance", c.JS_NewInt32(s.engine.context, 0));
    try s.put(result, "contains", try list(s, &.{type_mode}));
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "scala", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const annotation = try mode(&s, "meta");
    try s.put(annotation, "begin", try s.text("@[A-Za-z]+"));
    const subst = try mode(&s, "subst");
    const substitutions = try s.array();
    const variable = try s.object();
    try s.put(variable, "begin", try s.text("\\$[A-Za-z0-9_]+"));
    try s.index(substitutions, 0, variable);
    const braced = try s.object();
    try s.put(braced, "begin", try literal(&s, "\\$\\{"));
    try s.put(braced, "end", try literal(&s, "\\}"));
    try s.index(substitutions, 1, braced);
    try s.put(subst, "variants", substitutions);
    const string = try mode(&s, "string");
    const strings = try s.array();
    const triple = try s.object();
    try s.put(triple, "begin", try s.text("\"\"\""));
    try s.put(triple, "end", try s.text("\"\"\""));
    try s.index(strings, 0, triple);
    const quote = try s.object();
    try s.put(quote, "begin", try s.text("\""));
    try s.put(quote, "end", try s.text("\""));
    try s.put(quote, "illegal", try s.text("\\n"));
    try s.put(quote, "contains", try list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    try s.index(strings, 1, quote);
    const interpolation = try s.object();
    try s.put(interpolation, "begin", try s.text("[a-z]+\""));
    try s.put(interpolation, "end", try s.text("\""));
    try s.put(interpolation, "illegal", try s.text("\\n"));
    try s.put(interpolation, "contains", try list(&s, &.{ try s.get(hljs, "BACKSLASH_ESCAPE"), subst }));
    try s.index(strings, 2, interpolation);
    const triple_interpolation = try mode(&s, "string");
    try s.put(triple_interpolation, "begin", try s.text("[a-z]+\"\"\""));
    try s.put(triple_interpolation, "end", try s.text("\"\"\""));
    try s.put(triple_interpolation, "contains", try list(&s, &.{subst}));
    try s.put(triple_interpolation, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(strings, 3, triple_interpolation);
    try s.put(string, "variants", strings);
    const symbol = try mode(&s, "symbol");
    try s.put(symbol, "begin", try s.text("'\\w[\\w\\d_]*(?!')"));
    const type_mode = try mode(&s, "type");
    try s.put(type_mode, "begin", try s.text("\\b[A-Z][A-Za-z0-9_]*"));
    try s.put(type_mode, "relevance", c.JS_NewInt32(engine.context, 0));
    const name = try mode(&s, "title");
    try s.put(name, "begin", try literal(&s, "[^0-9\\n\\t \"'(),.`{}\\[\\]:;][^\\n\\t \"'(),.`{}\\[\\]:;]+|[^0-9\\n\\t \"'(),.`{}\\[\\]:;=]"));
    try s.put(name, "relevance", c.JS_NewInt32(engine.context, 0));
    const class_mode = try mode(&s, "class");
    try s.put(class_mode, "beginKeywords", try s.text("class object trait type"));
    try s.put(class_mode, "end", try literal(&s, "[:={\\[\\n;]"));
    try s.put(class_mode, "excludeEnd", c.pi_js_bool(engine.context, 1));
    const class_children = try s.array();
    try s.index(class_children, 0, try s.get(hljs, "C_LINE_COMMENT_MODE"));
    try s.index(class_children, 1, try s.get(hljs, "C_BLOCK_COMMENT_MODE"));
    const extends = try s.object();
    try s.put(extends, "beginKeywords", try s.text("extends with"));
    try s.put(extends, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(class_children, 2, extends);
    try s.index(class_children, 3, try brackets(&s, type_mode, false));
    try s.index(class_children, 4, try brackets(&s, type_mode, true));
    try s.index(class_children, 5, name);
    try s.put(class_mode, "contains", class_children);
    const method = try mode(&s, "function");
    try s.put(method, "beginKeywords", try s.text("def"));
    try s.put(method, "end", try literal(&s, "[:={\\[(\\n;]"));
    try s.put(method, "excludeEnd", c.pi_js_bool(engine.context, 1));
    try s.put(method, "contains", try list(&s, &.{name}));
    const language = try s.object();
    try s.put(language, "name", try s.text("Scala"));
    const keywords = try s.object();
    try s.put(keywords, "literal", try s.text("true false null"));
    try s.put(keywords, "keyword", try s.text("type yield lazy override def with val var sealed abstract private trait object if forSome for while throw finally protected extends import final return else break new catch super class case package default try this match continue throws implicit"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try list(&s, &.{ try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), string, symbol, type_mode, method, class_mode, try s.get(hljs, "C_NUMBER_MODE"), annotation }));
    return c.JS_DupValue(engine.context, language);
}
