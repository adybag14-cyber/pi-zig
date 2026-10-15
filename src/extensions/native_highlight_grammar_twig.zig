//! Actual highlight.js10.7.3 Twig factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
fn endTag(e: *b.Engine, _: b.c.JSValue, args: []const b.c.JSValue, _: []const b.c.JSValue) anyerror!b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    return b.c.JS_DupValue(e.context, try s.concat(try s.text("end"), if (args.len > 0) args[0] else b.c.pi_js_undefined()));
}
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "twig", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const params = try b.mode(&s, "params");
    try s.put(params, "begin", try s.text("\\("));
    try s.put(params, "end", try s.text("\\)"));
    const function_names = "attribute block constant cycle date dump include max min parent random range source template_from_string";
    const functions = try s.object();
    try s.put(functions, "beginKeywords", try s.text(function_names));
    const function_keywords = try s.object();
    try s.put(function_keywords, "name", try s.text(function_names));
    try s.put(functions, "keywords", function_keywords);
    try s.put(functions, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(functions, "contains", try b.list(&s, &.{params}));
    const filter = try s.object();
    try s.put(filter, "begin", try b.rx(&s, "\\|[A-Za-z_]+:?"));
    try s.put(filter, "keywords", try s.text("abs batch capitalize column convert_encoding date date_modify default escape filter first format inky_to_html inline_css join json_encode keys last length lower map markdown merge nl2br number_format raw reduce replace reverse round slice sort spaceless split striptags title trim upper url_encode"));
    try s.put(filter, "contains", try b.list(&s, &.{functions}));
    var tags = try s.text("apply autoescape block deprecated do embed extends filter flush for from if import include macro sandbox set use verbatim with");
    const prefix = try s.concat(tags, try s.text(" "));
    const split = try s.invoke(tags, "split", &.{try s.text(" ")});
    const map = try s.get(split, "map");
    const callback = try s.own(try @import("native_legacy_function.zig").create(e, "", 1, endTag, &.{}));
    const mapped = try s.call(map, split, &.{callback});
    tags = try s.concat(prefix, try s.invoke(mapped, "join", &.{try s.text(" ")}));
    const language = try s.object();
    try s.put(language, "name", try s.text("Twig"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("craftcms")}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "subLanguage", try s.text("xml"));
    const comment = try s.get(hljs, "COMMENT");
    const contains = try b.list(&s, &.{try s.call(comment, hljs, &.{ try b.rx(&s, "\\{#"), try b.rx(&s, "#\\}") })});
    const tag = try b.mode(&s, "template-tag");
    try s.put(tag, "begin", try b.rx(&s, "\\{%"));
    try s.put(tag, "end", try b.rx(&s, "%\\}"));
    const name = try b.mode(&s, "name");
    try s.put(name, "begin", try b.rx(&s, "\\w+"));
    try s.put(name, "keywords", tags);
    const starts = try s.object();
    try s.put(starts, "endsWithParent", b.boolean(&s, true));
    try s.put(starts, "contains", try b.list(&s, &.{ filter, functions }));
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(name, "starts", starts);
    try s.put(tag, "contains", try b.list(&s, &.{name}));
    try s.index(contains, 1, tag);
    const variable = try b.mode(&s, "template-variable");
    try s.put(variable, "begin", try b.rx(&s, "\\{\\{"));
    try s.put(variable, "end", try b.rx(&s, "\\}\\}"));
    try s.put(variable, "contains", try b.list(&s, &.{ try s.text("self"), filter, functions }));
    try s.index(contains, 2, variable);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(e.context, language);
}
