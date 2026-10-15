//! Actual highlight.js10.7.3 Shell Session factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "shell", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("Shell Session"));
    try s.put(language, "aliases", try b.list(&s, &.{try s.text("console")}));
    const prompt = try b.mode(&s, "meta");
    try s.put(prompt, "begin", try b.rx(&s, "^\\s{0,3}[/~\\w\\d[\\]()@-]*[>%$#]"));
    const starts = try s.object();
    try s.put(starts, "end", try b.rx(&s, "[^\\\\](?=\\s*$)"));
    try s.put(starts, "subLanguage", try s.text("bash"));
    try s.put(prompt, "starts", starts);
    try s.put(language, "contains", try b.list(&s, &.{prompt}));
    return b.c.JS_DupValue(engine.context, language);
}
