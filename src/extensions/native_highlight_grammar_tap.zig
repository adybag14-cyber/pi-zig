//! Actual highlight.js10.7.3 Test Anything Protocol factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "tap", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Test Anything Protocol"));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "HASH_COMMENT_MODE"));
    const meta = try b.mode(&s, "meta");
    const meta_variants = try s.array();
    inline for (.{ "^TAP version (\\d+)$", "^1\\.\\.(\\d+)$" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(meta_variants, index, variant);
    }
    try s.put(meta, "variants", meta_variants);
    try s.index(contains, 1, meta);
    const yaml = try s.object();
    try s.put(yaml, "begin", try b.rx(&s, "---$"));
    try s.put(yaml, "end", try s.text("\\.\\.\\.$"));
    try s.put(yaml, "subLanguage", try s.text("yaml"));
    try s.put(yaml, "relevance", b.c.JS_NewInt32(engine.context, 0));
    try s.index(contains, 2, yaml);
    const number = try b.mode(&s, "number");
    try s.put(number, "begin", try s.text(" (\\d+) "));
    try s.index(contains, 3, number);
    const symbol = try b.mode(&s, "symbol");
    const variants = try s.array();
    inline for (.{ "^ok", "^not ok" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(variants, index, variant);
    }
    try s.put(symbol, "variants", variants);
    try s.index(contains, 4, symbol);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
