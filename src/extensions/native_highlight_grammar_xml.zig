//! Actual highlight.js 10.7.3 HTML/XML factory; source-only.
const em = @import("engine.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_legacy_function.zig");
const regex = @import("native_highlight_regex.zig");
const c = em.c;

fn literal(s: *Scope, pattern: []const u8) !c.JSValue {
    var args = [_]c.JSValue{try s.text(pattern)};
    return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, args.len, &args)));
}
fn list(s: *Scope, values: []const c.JSValue) !c.JSValue {
    const result = try s.array();
    for (values, 0..) |value, index| try s.index(result, @intCast(index), value);
    return result;
}
fn concat(s: *Scope, values: []const c.JSValue) !c.JSValue {
    return s.own(try regex.concat(s.engine, try list(s, values)));
}
fn either(s: *Scope, values: []const c.JSValue) !c.JSValue {
    return s.own(try regex.either(s.engine, try list(s, values)));
}
fn lookahead(s: *Scope, value: c.JSValue) !c.JSValue {
    return concat(s, &.{ try s.text("(?="), value, try s.text(")") });
}
fn mode(s: *Scope, class_name: []const u8) !c.JSValue {
    const result = try s.object();
    try s.put(result, "className", try s.text(class_name));
    return result;
}
pub fn create(engine: *em.Engine) !c.JSValue {
    const Adapter = struct {
        fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) anyerror!c.JSValue {
            return build(host, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return ordinary.create(engine, "xml", 1, Adapter.invoke, &.{});
}
pub fn build(engine: *em.Engine, hljs: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const tag_initial = try literal(&s, "[A-Z_]");
    const namespace = try literal(&s, "[A-Z0-9_.-]*:");
    const namespace_optional = try concat(&s, &.{ try s.text("("), namespace, try s.text(")?") });
    const tag_tail = try literal(&s, "[A-Z0-9_.-]*");
    const tag_name = try concat(&s, &.{ tag_initial, namespace_optional, tag_tail });
    const xml_ident = try literal(&s, "[A-Za-z0-9._:-]+");
    const entities = try mode(&s, "symbol");
    try s.put(entities, "begin", try literal(&s, "&[a-z]+;|&#[0-9]+;|&#x[a-f0-9]+;"));
    const meta_keywords = try s.object();
    try s.put(meta_keywords, "begin", try literal(&s, "\\s"));
    const meta_keyword = try mode(&s, "meta-keyword");
    try s.put(meta_keyword, "begin", try literal(&s, "#?[a-z_][a-z1-9_-]+"));
    try s.put(meta_keyword, "illegal", try literal(&s, "\\n"));
    try s.put(meta_keywords, "contains", try list(&s, &.{meta_keyword}));
    const inherit_parens = try s.get(hljs, "inherit");
    const paren_changes = try s.object();
    try s.put(paren_changes, "begin", try literal(&s, "\\("));
    try s.put(paren_changes, "end", try literal(&s, "\\)"));
    const meta_parens = try s.call(inherit_parens, hljs, &.{ meta_keywords, paren_changes });
    const inherit_apos = try s.get(hljs, "inherit");
    const apos_source = try s.get(hljs, "APOS_STRING_MODE");
    const apos_changes = try mode(&s, "meta-string");
    const apos_meta = try s.call(inherit_apos, hljs, &.{ apos_source, apos_changes });
    const inherit_quote = try s.get(hljs, "inherit");
    const quote_source = try s.get(hljs, "QUOTE_STRING_MODE");
    const quote_changes = try mode(&s, "meta-string");
    const quote_meta = try s.call(inherit_quote, hljs, &.{ quote_source, quote_changes });
    const internals = try s.object();
    try s.put(internals, "endsWithParent", c.pi_js_bool(engine.context, 1));
    try s.put(internals, "illegal", try literal(&s, "<"));
    try s.put(internals, "relevance", c.JS_NewInt32(engine.context, 0));
    const attr = try mode(&s, "attr");
    try s.put(attr, "begin", xml_ident);
    try s.put(attr, "relevance", c.JS_NewInt32(engine.context, 0));
    const assignment = try s.object();
    try s.put(assignment, "begin", try literal(&s, "=\\s*"));
    try s.put(assignment, "relevance", c.JS_NewInt32(engine.context, 0));
    const string = try mode(&s, "string");
    try s.put(string, "endsParent", c.pi_js_bool(engine.context, 1));
    const string_variants = try s.array();
    inline for (.{ "\"", "'" }, 0..) |delimiter, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try literal(&s, delimiter));
        try s.put(variant, "end", try literal(&s, delimiter));
        try s.put(variant, "contains", try list(&s, &.{entities}));
        try s.index(string_variants, index, variant);
    }
    const unquoted = try s.object();
    try s.put(unquoted, "begin", try literal(&s, "[^\\s\"'=<>`]+"));
    try s.index(string_variants, 2, unquoted);
    try s.put(string, "variants", string_variants);
    try s.put(assignment, "contains", try list(&s, &.{string}));
    try s.put(internals, "contains", try list(&s, &.{ attr, assignment }));
    const language = try s.object();
    try s.put(language, "name", try s.text("HTML, XML"));
    const aliases = try s.array();
    inline for (.{ "html", "xhtml", "rss", "atom", "xjb", "xsd", "xsl", "plist", "wsf", "svg" }, 0..) |alias, index| try s.index(aliases, index, try s.text(alias));
    try s.put(language, "aliases", aliases);
    try s.put(language, "case_insensitive", c.pi_js_bool(engine.context, 1));
    const contains = try s.array();
    const meta = try mode(&s, "meta");
    try s.put(meta, "begin", try literal(&s, "<![a-z]"));
    try s.put(meta, "end", try literal(&s, ">"));
    try s.put(meta, "relevance", c.JS_NewInt32(engine.context, 10));
    const meta_contains = try list(&s, &.{ meta_keywords, quote_meta, apos_meta, meta_parens });
    const brackets = try s.object();
    try s.put(brackets, "begin", try literal(&s, "\\["));
    try s.put(brackets, "end", try literal(&s, "\\]"));
    const nested_meta = try mode(&s, "meta");
    try s.put(nested_meta, "begin", try literal(&s, "<![a-z]"));
    try s.put(nested_meta, "end", try literal(&s, ">"));
    try s.put(nested_meta, "contains", try list(&s, &.{ meta_keywords, meta_parens, quote_meta, apos_meta }));
    try s.put(brackets, "contains", try list(&s, &.{nested_meta}));
    try s.index(meta_contains, 4, brackets);
    try s.put(meta, "contains", meta_contains);
    try s.index(contains, 0, meta);
    const comment = try s.get(hljs, "COMMENT");
    const comment_begin = try literal(&s, "<!--");
    const comment_end = try literal(&s, "-->");
    const comment_options = try s.object();
    try s.put(comment_options, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 1, try s.call(comment, hljs, &.{ comment_begin, comment_end, comment_options }));
    const cdata = try s.object();
    try s.put(cdata, "begin", try literal(&s, "<!\\[CDATA\\["));
    try s.put(cdata, "end", try literal(&s, "\\]\\]>"));
    try s.put(cdata, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 2, cdata);
    try s.index(contains, 3, entities);
    const declaration = try mode(&s, "meta");
    try s.put(declaration, "begin", try literal(&s, "<\\?xml"));
    try s.put(declaration, "end", try literal(&s, "\\?>"));
    try s.put(declaration, "relevance", c.JS_NewInt32(engine.context, 10));
    try s.index(contains, 4, declaration);
    inline for (.{ .{ "style", "<style(?=\\s|>)", "<\\/style>" }, .{ "script", "<script(?=\\s|>)", "<\\/script>" } }, 0..) |entry, index| {
        const tag = try mode(&s, "tag");
        try s.put(tag, "begin", try literal(&s, entry[1]));
        try s.put(tag, "end", try literal(&s, ">"));
        const keywords = try s.object();
        try s.put(keywords, "name", try s.text(entry[0]));
        try s.put(tag, "keywords", keywords);
        try s.put(tag, "contains", try list(&s, &.{internals}));
        const starts = try s.object();
        try s.put(starts, "end", try literal(&s, entry[2]));
        try s.put(starts, "returnEnd", c.pi_js_bool(engine.context, 1));
        const sublanguages = if (index == 0) try list(&s, &.{ try s.text("css"), try s.text("xml") }) else try list(&s, &.{ try s.text("javascript"), try s.text("handlebars"), try s.text("xml") });
        try s.put(starts, "subLanguage", sublanguages);
        try s.put(tag, "starts", starts);
        try s.index(contains, @intCast(index + 5), tag);
    }
    const fragment = try mode(&s, "tag");
    try s.put(fragment, "begin", try literal(&s, "<>|<\\/>"));
    try s.index(contains, 7, fragment);
    const open_tag = try mode(&s, "tag");
    const open_prefix = try literal(&s, "<");
    const open_alternatives = try either(&s, &.{ try literal(&s, "\\/>"), try literal(&s, ">"), try literal(&s, "\\s") });
    const open_contents = try concat(&s, &.{ tag_name, open_alternatives });
    try s.put(open_tag, "begin", try concat(&s, &.{ open_prefix, try lookahead(&s, open_contents) }));
    try s.put(open_tag, "end", try literal(&s, "\\/?>"));
    const open_name = try mode(&s, "name");
    try s.put(open_name, "begin", tag_name);
    try s.put(open_name, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(open_name, "starts", internals);
    try s.put(open_tag, "contains", try list(&s, &.{open_name}));
    try s.index(contains, 8, open_tag);
    const close_tag = try mode(&s, "tag");
    const close_prefix = try literal(&s, "<\\/");
    const close_contents = try concat(&s, &.{ tag_name, try literal(&s, ">") });
    try s.put(close_tag, "begin", try concat(&s, &.{ close_prefix, try lookahead(&s, close_contents) }));
    const close_name = try mode(&s, "name");
    try s.put(close_name, "begin", tag_name);
    try s.put(close_name, "relevance", c.JS_NewInt32(engine.context, 0));
    const close_end = try s.object();
    try s.put(close_end, "begin", try literal(&s, ">"));
    try s.put(close_end, "relevance", c.JS_NewInt32(engine.context, 0));
    try s.put(close_end, "endsParent", c.pi_js_bool(engine.context, 1));
    try s.put(close_tag, "contains", try list(&s, &.{ close_name, close_end }));
    try s.index(contains, 9, close_tag);
    try s.put(language, "contains", contains);
    return c.JS_DupValue(engine.context, language);
}
