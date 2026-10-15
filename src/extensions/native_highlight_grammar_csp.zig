//! Actual highlight.js10.7.3 CSP factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(engine: *b.Engine) !b.c.JSValue {
    return b.factory(engine, "csp", build);
}
pub fn build(engine: *b.Engine, _: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = engine };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("CSP"));
    try s.put(language, "case_insensitive", b.boolean(&s, false));
    const keywords = try s.object();
    try s.put(keywords, "$pattern", try s.text("[a-zA-Z][a-zA-Z0-9_-]*"));
    try s.put(keywords, "keyword", try s.text("base-uri child-src connect-src default-src font-src form-action frame-ancestors frame-src img-src media-src object-src plugin-types report-uri sandbox script-src style-src"));
    try s.put(language, "keywords", keywords);
    const string = try b.mode(&s, "string");
    try s.put(string, "begin", try s.text("'"));
    try s.put(string, "end", try s.text("'"));
    const attribute = try b.mode(&s, "attribute");
    try s.put(attribute, "begin", try s.text("^Content"));
    try s.put(attribute, "end", try s.text(":"));
    try s.put(attribute, "excludeEnd", b.boolean(&s, true));
    try s.put(language, "contains", try b.list(&s, &.{ string, attribute }));
    return b.c.JS_DupValue(engine.context, language);
}
