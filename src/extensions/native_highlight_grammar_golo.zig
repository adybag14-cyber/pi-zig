//! Actual highlight.js10.7.3 Golo factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "golo", build);
}
pub fn build(engine: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Golo"));
    const keywords = try s.object();
    try s.put(keywords, "keyword", try s.text("println readln print import module function local return let var while for foreach times in case when match with break continue augment augmentation each find filter reduce if then else otherwise try catch finally raise throw orIfNull DynamicObject|10 DynamicVariable struct Observable map set vector list array"));
    try s.put(keywords, "literal", try s.text("true false null"));
    try s.put(language, "keywords", keywords);
    const contains = try s.array();
    try s.index(contains, 0, try s.get(hljs, "HASH_COMMENT_MODE"));
    try s.index(contains, 1, try s.get(hljs, "QUOTE_STRING_MODE"));
    try s.index(contains, 2, try s.get(hljs, "C_NUMBER_MODE"));
    const meta = try b.mode(&s, "meta");
    try s.put(meta, "begin", try s.text("@[A-Za-z]+"));
    try s.index(contains, 3, meta);
    try s.put(language, "contains", contains);
    return b.c.JS_DupValue(engine.context, language);
}
