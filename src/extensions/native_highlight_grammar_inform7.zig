//! Actual highlight.js10.7.3 Inform7 factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "inform7", build);
}
pub fn build(e: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Inform 7"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("i7")}));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("thing room person man woman animal container supporter backdrop door scenery open closed locked inside gender is are say understand kind of rule"));
    try s.put(language, "keywords", keywords);
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("\""));
    try s.put(string, "end", try s.text("\""));
    try s.put(string, "relevance", b.c.JS_NewInt32(e.context, 0));
    const subst = try b.mode(&s, "subst");
    try s.put(subst, "begin", try s.text("\\["));
    try s.put(subst, "end", try s.text("\\]"));
    try s.put(string, "contains", try b.list(&s, &.{subst}));
    const section = try b.mode(&s, "section");
    try s.put(section, "begin", try b.rx(&s, "^(Volume|Book|Part|Chapter|Section|Table)\\b"));
    try s.put(section, "end", try s.text("$"));
    const rule = try s.object();
    try s.put(rule, "begin", try b.rx(&s, "^(Check|Carry out|Report|Instead of|To|Rule|When|Before|After)\\b"));
    try s.put(rule, "end", try s.text(":"));
    const rule_name = try s.object();
    try s.put(rule_name, "begin", try s.text("\\(This"));
    try s.put(rule_name, "end", try s.text("\\)"));
    try s.put(rule, "contains", try b.list(&s, &.{rule_name}));
    const comment = try b.mode(&s, "comment");
    try s.put(comment, "begin", try s.text("\\["));
    try s.put(comment, "end", try s.text("\\]"));
    try s.put(comment, "contains", try b.list(&s, &.{try s.text("self")}));
    try s.put(language, "contains", try b.list(&s, &.{ string, section, rule, comment }));
    return b.c.JS_DupValue(e.context, language);
}
