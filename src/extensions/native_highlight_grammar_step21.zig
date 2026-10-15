//! Actual highlight.js10.7.3 STEP Part21 factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "step21", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text("[A-Z_][A-Z0-9_.]*"));
    try s.put(keywords, "keyword", try s.text("HEADER ENDSEC DATA"));
    const start = try b.mode(&s, "meta");
    try s.put(start, "begin", try s.text("ISO-10303-21;"));
    try s.put(start, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const close = try b.mode(&s, "meta");
    try s.put(close, "begin", try s.text("END-ISO-10303-21;"));
    try s.put(close, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const language = try s.object();
    try s.put(language, "name", try s.text("STEP Part 21"));
    try s.put(language, "aliases", try b.list(&s, &.{ try s.text("p21"), try s.text("step"), try s.text("stp") }));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "keywords", keywords);
    const contains = try b.list(&s, &.{ start, close, try s.get(hljs, "C_LINE_COMMENT_MODE"), try s.get(hljs, "C_BLOCK_COMMENT_MODE") });
    const comment = try s.get(hljs, "COMMENT");
    try s.index(contains, 4, try s.call(comment, hljs, &.{ try s.text("/\\*\\*!"), try s.text("\\*/") }));
    try s.index(contains, 5, try s.get(hljs, "C_NUMBER_MODE"));
    inline for (.{ "APOS_STRING_MODE", "QUOTE_STRING_MODE" }, 0..) |name, index| {
        const inherit = try s.get(hljs, "inherit");
        const base = try s.get(hljs, name);
        const changes = try s.object();
        try s.put(changes, "illegal", b.c.pi_js_null());
        try s.index(contains, @intCast(index + 6), try s.call(inherit, hljs, &.{ base, changes }));
    }
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("'"));
    try s.put(string, "end", try s.text("'"));
    try s.index(contains, 8, string);
    const symbol = try b.mode(&s, "symbol");
    const variant = try s.object();
    try s.put(variant, "begin", try s.text("#"));
    try s.put(variant, "end", try s.text("\\d+"));
    try s.put(variant, "illegal", try s.text("\\W"));
    try s.put(symbol, "variants", try b.list(&s, &.{variant}));
    try s.index(contains, 9, symbol);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
