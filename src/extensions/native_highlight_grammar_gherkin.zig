//! Actual highlight.js10.7.3 Gherkin factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "gherkin", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Gherkin"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("feature")}));
    try s.put(language, "keywords", try s.text("Feature Background Ability Business Need Scenario Scenarios Scenario Outline Scenario Template Examples Given And Then But When"));
    const symbol = try b.mode(&s, "symbol");
    try s.put(symbol, "begin", try s.text("\\*"));
    try s.put(symbol, "relevance", b.c.JS_NewInt32(engine.context, 0));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("@[^@\\s]+"));
    const table = try s.object();
    try s.put(table, "begin", try s.text("\\|"));
    try s.put(table, "end", try s.text("\\|\\w*$"));
    const cell = try b.mode(&s, "string");
    try s.put(cell, "begin", try s.text("[^|]+"));
    try s.put(table, "contains", try b.list(&s, &.{cell}));
    const variable = try b.mode(&s, "variable");
    try s.put(variable, "begin", try s.text("<"));
    try s.put(variable, "end", try s.text(">"));
    const contains = try b.list(&s, &.{ symbol, meta, table, variable, try s.get(hljs, "HASH_COMMENT_MODE") });
    const multiline = try b.mode(&s, "string");
    try s.put(multiline, "begin", try s.text("\"\"\""));
    try s.put(multiline, "end", try s.text("\"\"\""));
    try s.index(contains, 5, multiline);
    try s.index(contains, 6, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
