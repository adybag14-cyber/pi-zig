//! Actual highlight.js10.7.3 Apache config factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "apache", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const number_ref = try b.mode(&s, "number");
    try s.put(number_ref, "begin", try b.rx(&s, "[$%]\\d+"));
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try b.rx(&s, "\\d+"));
    const ip = try b.mode(&s, "number");
    try s.put(ip, "begin", try b.rx(&s, "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}(:\\d{1,5})?"));
    const port = try b.mode(&s, "number");
    try s.put(port, "begin", try b.rx(&s, ":\\d{1,5}"));
    const language = try s.object();
    try s.put(language, "name", try s.text("Apache config"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("apacheconf")}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    const contains = try b.list(&s, &.{try s.get(hljs, "HASH_COMMENT_MODE")});
    const section = try b.mode(&s, "section");
    try s.put(section, "begin", try b.rx(&s, "<\\/?"));
    try s.put(section, "end", try b.rx(&s, ">"));
    const inherit = try s.get(hljs, "inherit");
    const quote = try s.get(hljs, "QUOTE_STRING_MODE");
    const changes = try s.object();
    try s.put(changes, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(section, "contains", try b.list(&s, &.{ ip, port, try s.call(inherit, hljs, &.{ quote, changes }) }));
    try s.index(contains, 1, section);
    const attribute = try b.mode(&s, "attribute");
    try s.put(attribute, "begin", try b.rx(&s, "\\w+"));
    try s.put(attribute, "relevance", b.c.JS_NewInt32(e.context, 0));
    const words = try s.object();
    try s.put(words, "nomarkup", try s.text("order deny allow setenv rewriterule rewriteengine rewritecond documentroot sethandler errordocument loadmodule options header listen serverroot servername"));
    try s.put(attribute, "keywords", words);
    const starts = try s.object();
    try s.put(starts, "end", try b.rx(&s, "$"));
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    const literals = try s.object();
    try s.put(literals, "literal", try s.text("on off all deny allow"));
    try s.put(starts, "keywords", literals);
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try b.rx(&s, "\\s\\["));
    try s.put(meta, "end", try b.rx(&s, "\\]$"));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try b.rx(&s, "[\\$%]\\{"));
    try s.put(variable, "end", try b.rx(&s, "\\}"));
    try s.put(variable, "contains", try b.list(&s, &.{ try s.text("self"), number_ref }));
    try s.put(starts, "contains", try b.list(&s, &.{ meta, variable, ip, number, try s.get(hljs, "QUOTE_STRING_MODE") }));
    try s.put(attribute, "starts", starts);
    try s.index(contains, 2, attribute);
    try s.put(language, "contains", contains);
    try s.put(language, "illegal", try b.rx(&s, "\\S"));
    return b.c.JS_DupValue(e.context, language);
}
