//! Actual highlight.js10.7.3 Awk factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "awk", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const variable = try b.mode(&s, "variable");
    const simple = try s.object();
    try s.put(simple, "begin", try b.rx(&s, "\\$[\\w\\d#@][\\w\\d_]*"));
    const braced = try s.object();
    try s.put(braced, "begin", try b.rx(&s, "\\$\\{(.*?)\\}"));
    try s.put(variable, "variants", try b.list(&s, &.{ simple, braced }));
    const string = try b.mode(&s, "string");
    try s.put(string, "contains", try b.list(&s, &.{try s.get(hljs, "BACKSLASH_ESCAPE")}));
    const variants = try s.array();
    inline for (.{ .{ "(u|b)?r?'''", "'''" }, .{ "(u|b)?r?\"\"\"", "\"\"\"" }, .{ "(u|r|ur)'", "'" }, .{ "(u|r|ur)\"", "\"" }, .{ "(b|br)'", "'" }, .{ "(b|br)\"", "\"" } }, 0..) |pair, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try b.rx(&s, pair[0]));
        try s.put(variant, "end", try b.rx(&s, pair[1]));
        if (index < 4) try s.put(variant, "relevance", b.c.JS_NewInt32(engine.context, 10));
        try s.index(variants, index, variant);
    }
    try s.index(variants, 6, try s.get(hljs, "APOS_STRING_MODE"));
    try s.index(variants, 7, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.put(string, "variants", variants);
    const language = try s.object();
    try s.put(language, "name", try s.text("Awk"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("BEGIN END if else while do for in break continue delete next nextfile function func exit|10"));
    try s.put(language, "keywords", keywords);
    try s.put(language, "contains", try b.list(&s, &.{ variable, string, try s.get(hljs, "REGEXP_MODE"), try s.get(hljs, "HASH_COMMENT_MODE"), try s.get(hljs, "NUMBER_MODE") }));
    return b.c.JS_DupValue(engine.context, language);
}
