//! Actual highlight.js10.7.3 SubUnit factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "subunit", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const details = try b.mode(&s, "string");
    try s.put(details, "begin", try s.text("\\[\n(multipart)?"));
    try s.put(details, "end", try s.text("\\]\n"));
    const time = try b.mode(&s, "string");
    // Source's non-escape \. in its JS string evaluates to a plain dot.
    try s.put(time, "begin", try s.text("\\d{4}-\\d{2}-\\d{2}(\\s+)\\d{2}:\\d{2}:\\d{2}.\\d+Z"));
    const progress = try b.mode(&s, "string");
    try s.put(progress, "begin", try s.text("(\\+|-)\\d+"));
    const keywords = try b.mode(&s, "keyword");
    try s.put(keywords, "relevance", b.c.JS_NewInt32(engine.context, 10));
    const variants = try s.array();
    inline for (.{ "^(test|testing|success|successful|failure|error|skip|xfail|uxsuccess)(:?)\\s+(test)?", "^progress(:?)(\\s+)?(pop|push)?", "^tags:", "^time:" }, 0..) |pattern, index| {
        const variant = try s.object();
        try s.put(variant, "begin", try s.text(pattern));
        try s.index(variants, index, variant);
    }
    try s.put(keywords, "variants", variants);
    const language = try s.object();
    try s.put(language, "name", try s.text("SubUnit"));
    try s.put(language, "case_insensitive", b.boolean(&s, true));
    try s.put(language, "contains", try b.list(&s, &.{ details, time, progress, keywords }));
    return b.c.JS_DupValue(engine.context, language);
}
