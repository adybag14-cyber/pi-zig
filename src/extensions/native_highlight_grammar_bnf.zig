//! Actual highlight.js10.7.3 Backus–Naur Form factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "bnf", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Backus–Naur Form"));
    const attribute = try b.mode(&s, "attribute");
    try s.put(attribute, "begin", try b.rx(&s, "<"));
    try s.put(attribute, "end", try b.rx(&s, ">"));
    const rule = try s.object();
    try s.put(rule, "begin", try b.rx(&s, "::="));
    try s.put(rule, "end", try b.rx(&s, "$"));
    const nested = try s.object();
    try s.put(nested, "begin", try b.rx(&s, "<"));
    try s.put(nested, "end", try b.rx(&s, ">"));
    try s.put(rule, "contains", try b.list(&s, &.{ nested, try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE"), try s.get(hljs, "APOS_STRING_MODE"), try s.get(hljs, "QUOTE_STRING_MODE") }));
    try s.put(language, "contains", try b.list(&s, &.{ attribute, rule }));
    return b.c.JS_DupValue(engine.context, language);
}
