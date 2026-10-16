//! Actual highlight.js10.7.3 Dust factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "dust", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Dust"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("dst")}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "subLanguage", try s.text("xml"));
    const tag = try b.mode(&s, "template-tag");
    try s.put(tag, "begin", try b.rx(&s, "\\{[#\\/]"));
    try s.put(tag, "end", try b.rx(&s, "\\}"));
    try s.put(tag, "illegal", try b.rx(&s, ";"));
    const name = try b.mode(&s, "name");
    try s.put(name, "begin", try b.rx(&s, "[a-zA-Z\\.-]+"));
    const starts = try s.object();
    try s.put(starts, "endsWithParent", b.boolean(&s, true));
    try s.put(starts, "relevance", b.c.JS_NewInt32(e.context, 0));
    try s.put(starts, "contains", try b.list(&s, &.{try s.get(hljs, "QUOTE_STRING_MODE")}));
    try s.put(name, "starts", starts);
    try s.put(tag, "contains", try b.list(&s, &.{name}));
    const variable = try b.mode(&s, "template-variable");
    try s.put(variable, "begin", try b.rx(&s, "\\{"));
    try s.put(variable, "end", try b.rx(&s, "\\}"));
    try s.put(variable, "illegal", try b.rx(&s, ";"));
    try s.put(variable, "keywords", try s.text("if eq ne lt lte gt gte select default math sep"));
    try s.put(language, "contains", try b.list(&s, &.{ tag, variable }));
    return b.c.JS_DupValue(e.context, language);
}
