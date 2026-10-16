//! Actual highlight.js10.7.3 ERB factory; unqualified source.
const b = @import("native_highlight_lazy_batch3_values.zig");
pub fn create(e: *b.Engine) !b.c.JSValue {
    return b.factory(e, "erb", build);
}
pub fn build(e: *b.Engine, hljs: b.c.JSValue) !b.c.JSValue {
    var s: b.Scope = .{ .engine = e };
    defer s.deinit();
    const language = try s.object();
    try s.put(language, "name", try s.text("ERB"));
    try s.put(language, "subLanguage", try s.text("xml"));
    const comment_function = try s.get(hljs, "COMMENT");
    const comment = try s.call(comment_function, hljs, &.{ try s.text("<%#"), try s.text("%>") });
    const ruby = try s.object();
    try s.put(ruby, "begin", try s.text("<%[%=-]?"));
    try s.put(ruby, "end", try s.text("[%-]?%>"));
    try s.put(ruby, "subLanguage", try s.text("ruby"));
    try s.put(ruby, "excludeBegin", b.boolean(&s, true));
    try s.put(ruby, "excludeEnd", b.boolean(&s, true));
    try s.put(language, "contains", try b.list(&s, &.{ comment, ruby }));
    return b.c.JS_DupValue(e.context, language);
}
