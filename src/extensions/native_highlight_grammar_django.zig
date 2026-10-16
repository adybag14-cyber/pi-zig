//! Actual highlight.js 10.7.3 Django factory; source-only, unqualified.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "django", build);
}
pub fn build(e: *b.Engine, h: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const filter = try s.object();
    try s.put(filter, "begin", try b.rx(&s, "\\|[A-Za-z]+:?"));
    const fk = try s.object();
    try s.put(fk, "name", try s.text("truncatewords removetags linebreaksbr yesno get_digit timesince random striptags filesizeformat escape linebreaks length_is ljust rjust cut urlize fix_ampersands title floatformat capfirst pprint divisibleby add make_list unordered_list urlencode timeuntil urlizetrunc wordcount stringformat linenumbers slice date dictsort dictsortreversed default_if_none pluralize lower join center default truncatewords_html upper length phone2numeric wordwrap time addslashes slugify first escapejs force_escape iriencode last safe safeseq truncatechars localize unlocalize localtime utc timezone"));
    try s.put(filter, "keywords", fk);
    try s.put(filter, "contains", try b.list(&s, &.{ try s.get(h, "QUOTE_STRING_MODE"), try s.get(h, "APOS_STRING_MODE") }));
    const l = try s.object();
    try s.put(l, "name", try s.text("Django"));
    try s.put(l, "aliases", try b.list(&s, &.{try s.text("jinja")}));
    try s.put(l, "case_insensitive", b.boolean(&s, true));
    try s.put(l, "subLanguage", try s.text("xml"));
    const a = try s.array();
    const c1 = try s.get(h, "COMMENT");
    const b1 = try b.rx(&s, "\\{%\\s*comment\\s*%\\}");
    const e1 = try b.rx(&s, "\\{%\\s*endcomment\\s*%\\}");
    try s.index(a, 0, try s.call(c1, h, &.{ b1, e1 }));
    const c2 = try s.get(h, "COMMENT");
    const b2 = try b.rx(&s, "\\{#");
    const e2 = try b.rx(&s, "#\\}");
    try s.index(a, 1, try s.call(c2, h, &.{ b2, e2 }));
    const tag = try b.mode(&s, "template-tag");
    try s.put(tag, "begin", try b.rx(&s, "\\{%"));
    try s.put(tag, "end", try b.rx(&s, "%\\}"));
    const name = try b.mode(&s, "name");
    try s.put(name, "begin", try b.rx(&s, "\\w+"));
    const nk = try s.object();
    try s.put(nk, "name", try s.text("comment endcomment load templatetag ifchanged endifchanged if endif firstof for endfor ifnotequal endifnotequal widthratio extends include spaceless endspaceless regroup ifequal endifequal ssi now with cycle url filter endfilter debug block endblock else autoescape endautoescape csrf_token empty elif endwith static trans blocktrans endblocktrans get_static_prefix get_media_prefix plural get_current_language language get_available_languages get_current_language_bidi get_language_info get_language_info_list localize endlocalize localtime endlocaltime timezone endtimezone get_current_timezone verbatim"));
    try s.put(name, "keywords", nk);
    const starts = try s.object();
    try s.put(starts, "endsWithParent", b.boolean(&s, true));
    try s.put(starts, "keywords", try s.text("in by as"));
    try s.put(starts, "contains", try b.list(&s, &.{filter}));
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(name, "starts", starts);
    try s.put(tag, "contains", try b.list(&s, &.{name}));
    try s.index(a, 2, tag);
    const variable = try b.mode(&s, "template-variable");
    try s.put(variable, "begin", try b.rx(&s, "\\{\\{"));
    try s.put(variable, "end", try b.rx(&s, "\\}\\}"));
    try s.put(variable, "contains", try b.list(&s, &.{filter}));
    try s.index(a, 3, variable);
    try s.put(l, "contains", a);
    return b.c.JS_DupValue(e.context, l);
}
